import Compression
import Foundation

/// Minimal read-only ZIP reader, enough for .xlsx files (stored and deflated entries).
nonisolated struct ZipArchive {
    /// Upper bound for one entry and for all entries together after decompression. A small "ZIP bomb"
    /// could otherwise declare gigabytes, which `inflate` would allocate.
    static let maximumEntrySize = 64 * 1024 * 1024
    static let maximumTotalSize = 256 * 1024 * 1024

    struct Entry {
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let data: Data
    private(set) var entries: [String: Entry] = [:]

    init(data: Data) throws {
        self.data = Data(data)
        guard data.count >= 22 else { throw ImportError.notExcel }

        // The end of central directory record sits at the end, followed by an optional comment.
        var endRecord: Int?
        var offset = data.count - 22
        let lowerBound = max(0, data.count - 22 - 65_535)
        while offset >= lowerBound {
            if uint32(at: offset) == 0x0605_4B50 {
                endRecord = offset
                break
            }
            offset -= 1
        }
        guard let endRecord else { throw ImportError.notExcel }

        let entryCount = Int(uint16(at: endRecord + 10))
        var cursor = Int(uint32(at: endRecord + 16))
        var totalSize = 0
        for _ in 0..<entryCount {
            guard uint32(at: cursor) == 0x0201_4B50 else { throw ImportError.notExcel }
            let nameLength = Int(uint16(at: cursor + 28))
            let extraLength = Int(uint16(at: cursor + 30))
            let commentLength = Int(uint16(at: cursor + 32))
            let nameStart = cursor + 46
            guard nameStart + nameLength <= self.data.count else { throw ImportError.notExcel }

            let name = String(decoding: self.data[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            let uncompressedSize = Int(uint32(at: cursor + 24))
            totalSize += uncompressedSize
            guard uncompressedSize <= Self.maximumEntrySize, totalSize <= Self.maximumTotalSize else { throw ImportError.tooLarge }
            entries[name] = Entry(
                method: uint16(at: cursor + 10),
                compressedSize: Int(uint32(at: cursor + 20)),
                uncompressedSize: uncompressedSize,
                localHeaderOffset: Int(uint32(at: cursor + 42))
            )
            cursor = nameStart + nameLength + extraLength + commentLength
        }
    }

    func contents(of name: String) throws -> Data? {
        guard let entry = entries[name] else { return nil }
        let header = entry.localHeaderOffset
        guard uint32(at: header) == 0x0403_4B50 else { throw ImportError.notExcel }

        let start = header + 30 + Int(uint16(at: header + 26)) + Int(uint16(at: header + 28))
        guard start + entry.compressedSize <= data.count else { throw ImportError.notExcel }
        let compressed = data.subdata(in: start..<(start + entry.compressedSize))

        switch entry.method {
        case 0:
            return compressed
        case 8:
            return try inflate(compressed, expectedSize: entry.uncompressedSize)
        default:
            throw ImportError.notExcel
        }
    }

    private func inflate(_ input: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0, !input.isEmpty else { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { destination in
            input.withUnsafeBytes { source in
                // COMPRESSION_ZLIB decodes raw DEFLATE, which is what ZIP stores.
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!,
                    expectedSize,
                    source.bindMemory(to: UInt8.self).baseAddress!,
                    input.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else { throw ImportError.notExcel }
        return output
    }

    private func uint16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private func uint32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}
