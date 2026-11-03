import SwiftUI

struct ContentView: View {
    @StateObject var ble = WatchBleManager()
    var body: some View {
        VStack(spacing: 16) {
            Text(ble.status)
            if let b = ble.battery { Text("Bateria: \(b)%") }
            Button("Sincronizar hora") { ble.send(Protocol.setTime()) }
            Button("Achar relógio") { ble.send(Protocol.findWatch(true)) }
            Button("Parar de achar") { ble.send(Protocol.findWatch(false)) }
            Button("Procurar de novo") { ble.startScan() }
        }
        .padding()
    }
}
