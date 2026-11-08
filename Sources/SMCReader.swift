import Foundation
import IOKit

/// Reads AppleSMC keys. On Apple silicon the numeric payload is little-endian;
/// older Macs may still return big-endian `sp78` temperatures. Values are
/// accepted only when they fall in a plausible battery range.
final class SMCReader {
    private var connection: io_connect_t = 0
    private let recordSize = 80

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    func batteryTemperature() -> Double? {
        guard open() else { return nil }
        for key in ["TB0T", "TB1T", "TB2T"] {
            guard let reading = read(key: key) else { continue }
            if let temperature = Self.temperature(type: reading.type, bytes: reading.bytes) {
                return temperature
            }
        }
        return nil
    }

    private func open() -> Bool {
        if connection != 0 { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        var opened: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &opened)
        guard result == KERN_SUCCESS else { return false }
        connection = opened
        return true
    }

    private func read(key: String) -> (type: String, bytes: [UInt8])? {
        guard key.utf8.count == 4 else { return nil }
        var input = [UInt8](repeating: 0, count: recordSize)
        var output = [UInt8](repeating: 0, count: recordSize)
        writeFourCC(key, into: &input, at: 0)
        input[42] = 9
        guard call(&input, &output) else { return nil }

        let dataSize = Int(readUInt32(output, at: 28))
        let dataType = readUInt32(output, at: 32)
        guard dataSize > 0, dataSize <= 32 else { return nil }

        input = [UInt8](repeating: 0, count: recordSize)
        writeFourCC(key, into: &input, at: 0)
        writeUInt32(UInt32(dataSize), into: &input, at: 28)
        input[42] = 5
        guard call(&input, &output) else { return nil }

        return (Self.fourCCString(dataType), Array(output[48..<(48 + dataSize)]))
    }

    private func call(_ input: inout [UInt8], _ output: inout [UInt8]) -> Bool {
        var outputSize = recordSize
        let result = input.withUnsafeBytes { inputBytes in
            output.withUnsafeMutableBytes { outputBytes in
                IOConnectCallStructMethod(
                    connection,
                    2,
                    inputBytes.baseAddress,
                    recordSize,
                    outputBytes.baseAddress,
                    &outputSize
                )
            }
        }
        if result != KERN_SUCCESS {
            IOServiceClose(connection)
            connection = 0
            return false
        }
        return true
    }

    private func writeFourCC(_ key: String, into buffer: inout [UInt8], at offset: Int) {
        let bytes = Array(key.utf8)
        let value = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        writeUInt32(value, into: &buffer, at: offset)
    }

    private func writeUInt32(_ value: UInt32, into buffer: inout [UInt8], at offset: Int) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { raw in
            for index in 0..<4 {
                buffer[offset + index] = raw[index]
            }
        }
    }

    private func readUInt32(_ buffer: [UInt8], at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        withUnsafeMutableBytes(of: &value) { raw in
            for index in 0..<4 {
                raw[index] = buffer[offset + index]
            }
        }
        return UInt32(littleEndian: value)
    }

    private static func fourCCString(_ value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    private static func temperature(type: String, bytes: [UInt8]) -> Double? {
        if type == "flt" {
            guard bytes.count >= 4 else { return nil }
            let little = bytes.withUnsafeBytes { Double($0.load(as: Float.self)) }
            if let sane = sane(little) { return sane }
            let swapped = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
            var big = swapped.bigEndian
            let bigValue = withUnsafeBytes(of: &big) { Double($0.load(as: Float.self)) }
            return sane(bigValue)
        }
        if type.hasPrefix("sp"), bytes.count >= 2 {
            let raw = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
            return sane(Double(raw) / 256.0)
        }
        return nil
    }

    private static func sane(_ celsius: Double) -> Double? {
        guard celsius > -10, celsius < 100 else { return nil }
        return (celsius * 10).rounded() / 10
    }
}
