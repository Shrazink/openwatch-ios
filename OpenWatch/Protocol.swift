import Foundation
import CoreBluetooth

/// Port em Swift do Protocol.kt do OpenWatch (engenharia reversa do LaxaFit Pro / FitPro).
enum Protocol {
    // UART Nordic. Alguns relógios usam ...dcca9f em vez de ...dcca9d: o manager tenta os dois.
    static let uartService     = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9d")
    static let uartWrite       = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9d")
    static let uartNotify      = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9d")
    static let uartServiceAlt  = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9f")
    static let uartWriteAlt    = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9f")
    static let uartNotifyAlt   = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9f")

    // Serviço proprietário que o seu relógio expõe (visto no LightBlue): FF00, FF02 = escrita, FF01 = notificação.
    static let ff00Service = CBUUID(string: "FF00")
    static let ff00Write   = CBUUID(string: "FF02")
    static let ff00Notify  = CBUUID(string: "FF01")

    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel   = CBUUID(string: "2A19")

    enum Icon: UInt8 {
        case sms = 1, qq, wechat, facebook, twitter, skype, line, whatsapp, kakaotalk
        case instagram = 16, linkedin = 17
    }

    // MARK: - Montagem de pacote

    private static func getProtocol(cmd: UInt8, key: UInt8, payload: [UInt8]) -> Data {
        let total = 8 + payload.count
        let lengthField = total - 3
        var pkt = [UInt8](repeating: 0, count: total)
        pkt[0] = 0xCD
        pkt[1] = UInt8((lengthField >> 8) & 0xFF)
        pkt[2] = UInt8(lengthField & 0xFF)
        pkt[3] = cmd
        pkt[4] = 0x01
        pkt[5] = key
        pkt[6] = UInt8((payload.count >> 8) & 0xFF)
        pkt[7] = UInt8(payload.count & 0xFF)
        pkt.replaceSubrange(8..<total, with: payload)
        return Data(pkt)
    }

    private static func be32(_ v: UInt32) -> [UInt8] {
        [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    // MARK: - Comandos

    /// Enviar uma vez logo depois de cada conexão.
    static func pair() -> Data { Data([0xCD, 0, 6, 18, 1, 10, 0, 1, 2]) }

    /// Só no primeiro setup: reenviar reseta o visual do relógio.
    static func bind() -> Data { Data([0xCD, 0, 2, 19, 1]) }

    static func enableAllPushCategories() -> Data {
        getProtocol(cmd: 0x12, key: 0x07, payload: [UInt8](repeating: 1, count: 11))
    }

    static func setTime(_ date: Date = Date()) -> Data {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let value: UInt32 =
            UInt32(c.second!) |
            (UInt32(c.year! - 2000) << 26) |
            (UInt32(c.month!) << 22) |
            (UInt32(c.day!) << 17) |
            (UInt32(c.hour!) << 12) |
            (UInt32(c.minute!) << 6)
        return getProtocol(cmd: 0x12, key: 0x01, payload: be32(value))
    }

    static func pushNotification(text: String, icon: Icon) -> Data {
        getProtocol(cmd: 0x12, key: 0x12, payload: [icon.rawValue, 0, 0] + Array(text.utf8))
    }

    static func findWatch(_ enable: Bool) -> Data {
        Data([0xCD, 0, 6, 18, 1, 11, 0, 1, enable ? 1 : 0])
    }

    static func setStepGoal(_ steps: UInt32) -> Data {
        getProtocol(cmd: 0x12, key: 0x03, payload: be32(steps))
    }

    // MARK: - Watchface (dial)

    enum Dial {
        static let chunkDataSize = 202
        static let sourceCustomPhoto: UInt8 = 0x04
        static let sourcePresetTheme: UInt8 = 0x01

        private static let cmd: UInt8 = 31
        private static let keyFile: UInt8 = 1
        private static let keyStart: UInt8 = 2
        private static let keyFinish: UInt8 = 3

        static func updateStart(sourceType: UInt8 = sourceCustomPhoto) -> Data {
            Protocol.getProtocol(cmd: cmd, key: keyStart, payload: [sourceType, 0x00, 0xFF, 0xFF, 0xFF])
        }

        static func updateChunk(seq: Int, chunk: Data) -> Data {
            let payload: [UInt8] = [UInt8((seq >> 8) & 0xFF), UInt8(seq & 0xFF)] + Array(chunk)
            return Protocol.getProtocol(cmd: cmd, key: keyFile, payload: payload)
        }

        static func updateFinish(totalLength: UInt32, totalChecksum: UInt32) -> Data {
            Protocol.getProtocol(cmd: cmd, key: keyFinish,
                                 payload: Protocol.be32(totalLength) + Protocol.be32(totalChecksum))
        }

        /// Soma de 32 bits de todos os bytes do arquivo, módulo 2^32.
        static func checksum(_ data: Data) -> UInt32 {
            data.reduce(UInt32(0)) { $0 &+ UInt32($1) }
        }
    }
}
