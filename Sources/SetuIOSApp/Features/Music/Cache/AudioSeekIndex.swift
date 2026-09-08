import Foundation

/// Conservative admission to AVPlayer's direct seek path. A duration alone does not
/// establish a correct VBR byte map; incomplete/contradictory headers use exact indexing.
enum AudioSeekIndex {
    static func supportsDirectSeek(header: Data, fileLength: Int64) -> Bool {
        let bytes = [UInt8](header)
        if bytes.starts(with: Array("fLaC".utf8)) { return true }
        if bytes.count >= 8, Array(bytes[4..<8]) == Array("ftyp".utf8) { return true }
        // A Xing TOC is only an approximate byte map. Even a monotonic table
        // with correct frame/byte totals can address the wrong decoded audio.
        // MPEG audio therefore needs the shared cache's precise local index.
        return false
    }
}
