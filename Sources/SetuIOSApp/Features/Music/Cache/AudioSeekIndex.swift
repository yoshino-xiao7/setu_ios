import Foundation

/// Conservative admission to AVPlayer's direct seek path. A duration alone does not
/// establish a correct VBR byte map; incomplete/contradictory headers use exact indexing.
enum AudioSeekIndex {
    static func supportsDirectSeek(header: Data, fileLength: Int64) -> Bool {
        let bytes = [UInt8](header)
        if bytes.starts(with: Array("fLaC".utf8)) { return true }
        if bytes.count >= 8, Array(bytes[4..<8]) == Array("ftyp".utf8) { return true }
        var offset = 0
        if bytes.count >= 10, bytes.prefix(3) == Array("ID3".utf8)[...] {
            guard bytes[6..<10].allSatisfy({ $0 < 128 }) else { return false }
            offset = 10 + bytes[6..<10].reduce(0) { ($0 << 7) | Int($1) }
            if bytes[5] & 0x10 != 0 { offset += 10 }
        }
        guard offset + 4 < bytes.count, bytes[offset] == 0xff, bytes[offset + 1] & 0xe0 == 0xe0 else { return false }
        let version = (bytes[offset + 1] >> 3) & 3, layer = (bytes[offset + 1] >> 1) & 3
        guard version != 1, layer == 1 else { return false }
        let mono = bytes[offset + 3] >> 6 == 3
        let sideInfo = version == 3 ? (mono ? 17 : 32) : (mono ? 9 : 17)
        let crc = bytes[offset + 1] & 1 == 0 ? 2 : 0
        let xing = offset + 4 + crc + sideInfo
        guard xing + 116 <= bytes.count,
              Array(bytes[xing..<xing + 4]) == Array("Xing".utf8) else { return false }
        func uint32(_ index: Int) -> Int64 { bytes[index..<index + 4].reduce(0) { ($0 << 8) | Int64($1) } }
        let flags = uint32(xing + 4), frames = uint32(xing + 8), audioBytes = uint32(xing + 12)
        guard flags & 7 == 7, frames > 1, audioBytes > 0,
              abs(audioBytes - (fileLength - Int64(offset))) <= 128 else { return false }
        let toc = Array(bytes[xing + 16..<xing + 116])
        return toc.first == 0 && (toc.last ?? 0) > 200 && zip(toc, toc.dropFirst()).allSatisfy { $0 <= $1 }
    }
}
