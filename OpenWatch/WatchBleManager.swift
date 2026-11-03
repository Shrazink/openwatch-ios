import Foundation
import CoreBluetooth

/// Conecta no relógio, acha o canal de comandos (UART Nordic ou FF00) e manda o handshake.
/// Lembre de pôr NSBluetoothAlwaysUsageDescription no Info.plist.
final class WatchBleManager: NSObject, ObservableObject {
    @Published var status = "Parado"
    @Published var battery: Int?

    private var central: CBCentralManager!
    private var watch: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var writeType: CBCharacteristicWriteType = .withoutResponse

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        status = "Procurando..."
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    func send(_ data: Data) {
        guard let p = watch, let c = writeChar else { return }
        let mtu = p.maximumWriteValueLength(for: writeType)
        var offset = 0
        while offset < data.count {
            let end = min(offset + mtu, data.count)
            p.writeValue(data.subdata(in: offset..<end), for: c, type: writeType)
            offset = end
        }
    }

    /// Candidatos de (serviço, escrita, notificação), na ordem de tentativa.
    private let channels: [(CBUUID, CBUUID, CBUUID)] = [
        (Protocol.uartService, Protocol.uartWrite, Protocol.uartNotify),
        (Protocol.uartServiceAlt, Protocol.uartWriteAlt, Protocol.uartNotifyAlt),
        (Protocol.ff00Service, Protocol.ff00Write, Protocol.ff00Notify),
    ]
}

extension WatchBleManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn { startScan() } else { status = "Bluetooth indisponível" }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = p.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        guard name.localizedCaseInsensitiveContains("Ultra 3") else { return }
        c.stopScan()
        watch = p
        p.delegate = self
        c.connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        status = "Conectado, descobrindo serviços..."
        p.discoverServices(nil)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        p.services?.forEach { p.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        let chars = s.characteristics ?? []

        if s.uuid == Protocol.batteryService,
           let b = chars.first(where: { $0.uuid == Protocol.batteryLevel }) {
            p.readValue(for: b)
        }

        guard writeChar == nil,
              let ch = channels.first(where: { $0.0 == s.uuid }),
              let w = chars.first(where: { $0.uuid == ch.1 }),
              let n = chars.first(where: { $0.uuid == ch.2 }) else { return }

        writeChar = w
        writeType = w.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        p.setNotifyValue(true, for: n)
        status = "Pronto (\(s.uuid))"

        send(Protocol.pair())
        send(Protocol.setTime())
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard let d = c.value else { return }
        if c.uuid == Protocol.batteryLevel, let b = d.first {
            DispatchQueue.main.async { self.battery = Int(b) }
        } else {
            print("RX \(c.uuid):", d.map { String(format: "%02x", $0) }.joined())
        }
    }
}
