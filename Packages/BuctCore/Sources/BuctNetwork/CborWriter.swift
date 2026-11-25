import Foundation

/// 极简 RFC 8949 CBOR 编码器（与 Android BuctSoftwarePasskey.CborWriter 逐字节一致）。
public struct CborWriter: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func writeMapHeader(_ size: Int) {
        writeHead(major: 5, value: UInt64(max(0, size)))
    }

    public mutating func writeBytes(_ value: Data) {
        writeHead(major: 2, value: UInt64(value.count))
        buffer.append(value)
    }

    public mutating func writeText(_ value: String) {
        let bytes = Data(value.utf8)
        writeHead(major: 3, value: UInt64(bytes.count))
        buffer.append(bytes)
    }

    public mutating func writeInt(_ value: Int) {
        if value >= 0 {
            writeHead(major: 0, value: UInt64(value))
        } else {
            writeHead(major: 1, value: UInt64(-1 - value))
        }
    }

    public func toData() -> Data {
        buffer
    }

    private mutating func writeHead(major: UInt8, value: UInt64) {
        let prefix = major << 5
        if value < 24 {
            buffer.append(prefix | UInt8(value))
        } else if value < 256 {
            buffer.append(prefix | 24)
            buffer.append(UInt8(value))
        } else if value < 65536 {
            buffer.append(prefix | 25)
            buffer.append(UInt8((value >> 8) & 0xFF))
            buffer.append(UInt8(value & 0xFF))
        } else {
            buffer.append(prefix | 26)
            buffer.append(UInt8((value >> 24) & 0xFF))
            buffer.append(UInt8((value >> 16) & 0xFF))
            buffer.append(UInt8((value >> 8) & 0xFF))
            buffer.append(UInt8(value & 0xFF))
        }
    }
}
