import Foundation

/// Singolo preset di una SoundFont (.sf2). Equivale a una entry del chunk PHDR.
public struct SF2Preset: Identifiable, Equatable, Hashable, Sendable {
    public let id = UUID()
    public let name: String       // 20 char ASCII zero-padded
    public let program: UInt8     // 0..127 (GM program)
    public let bank: UInt16       // 0 = melodic, 128 = percussion

    public init(name: String, program: UInt8, bank: UInt16) {
        self.name = name
        self.program = program
        self.bank = bank
    }
}

public enum SF2ParseError: Error {
    case notRIFF
    case notSF2
    case missingPDTA
    case missingPHDR
    case truncated
}

/// Parser leggero del formato RIFF SoundFont 2. Estrae solo il chunk PHDR (preset header)
/// per popolare la lista dei preset disponibili. Zero dipendenze esterne.
public nonisolated enum SF2Parser {
    public static func parsePresets(from url: URL) throws -> [SF2Preset] {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try parsePresets(from: data)
    }

    public static func parsePresets(from data: Data) throws -> [SF2Preset] {
        guard data.count >= 12 else { throw SF2ParseError.truncated }

        guard read4CC(data, at: 0) == "RIFF" else { throw SF2ParseError.notRIFF }
        guard read4CC(data, at: 8) == "sfbk" else { throw SF2ParseError.notSF2 }

        var offset = 12
        var pdtaRange: Range<Int>? = nil

        while offset + 8 <= data.count {
            let chunkID = read4CC(data, at: offset)
            let chunkSize = Int(readUInt32LE(data, at: offset + 4))
            let dataStart = offset + 8
            let dataEnd = dataStart + chunkSize
            guard dataEnd <= data.count else { throw SF2ParseError.truncated }

            if chunkID == "LIST" {
                guard chunkSize >= 4 else { throw SF2ParseError.truncated }
                let listType = read4CC(data, at: dataStart)
                if listType == "pdta" {
                    pdtaRange = (dataStart + 4)..<dataEnd
                    break
                }
            }
            offset = dataEnd + (chunkSize & 1)
        }

        guard let pdtaRange else { throw SF2ParseError.missingPDTA }

        var pos = pdtaRange.lowerBound
        var phdrRange: Range<Int>? = nil
        while pos + 8 <= pdtaRange.upperBound {
            let chunkID = read4CC(data, at: pos)
            let chunkSize = Int(readUInt32LE(data, at: pos + 4))
            let dataStart = pos + 8
            let dataEnd = dataStart + chunkSize
            guard dataEnd <= pdtaRange.upperBound else { throw SF2ParseError.truncated }

            if chunkID == "phdr" {
                phdrRange = dataStart..<dataEnd
                break
            }
            pos = dataEnd + (chunkSize & 1)
        }

        guard let phdrRange else { throw SF2ParseError.missingPHDR }

        let entrySize = 38
        let phdrLen = phdrRange.count
        guard phdrLen >= entrySize, phdrLen % entrySize == 0 else { throw SF2ParseError.truncated }
        let entryCount = phdrLen / entrySize
        guard entryCount >= 1 else { return [] }

        var presets: [SF2Preset] = []
        presets.reserveCapacity(entryCount - 1)
        for i in 0..<(entryCount - 1) {
            let entryStart = phdrRange.lowerBound + i * entrySize
            let name = readCString(data, at: entryStart, maxLen: 20)
            let program = readUInt16LE(data, at: entryStart + 20)
            let bank = readUInt16LE(data, at: entryStart + 22)
            presets.append(SF2Preset(
                name: name.isEmpty ? "Preset \(presets.count + 1)" : name,
                program: UInt8(min(127, program)),
                bank: bank
            ))
        }
        return presets
    }

    // MARK: - Byte readers (LE)

    private static func read4CC(_ data: Data, at offset: Int) -> String {
        let start = data.startIndex + offset
        let end = start + 4
        guard end <= data.endIndex else { return "" }
        return String(data: data.subdata(in: start..<end), encoding: .ascii) ?? ""
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        let s = data.startIndex + offset
        return UInt32(data[s])
            | (UInt32(data[s + 1]) << 8)
            | (UInt32(data[s + 2]) << 16)
            | (UInt32(data[s + 3]) << 24)
    }

    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        let s = data.startIndex + offset
        return UInt16(data[s]) | (UInt16(data[s + 1]) << 8)
    }

    private static func readCString(_ data: Data, at offset: Int, maxLen: Int) -> String {
        let s = data.startIndex + offset
        var bytes: [UInt8] = []
        bytes.reserveCapacity(maxLen)
        for i in 0..<maxLen {
            let b = data[s + i]
            if b == 0 { break }
            bytes.append(b)
        }
        return (String(bytes: bytes, encoding: .ascii) ?? "").trimmingCharacters(in: .whitespaces)
    }
}
