import Foundation

/// Owns the pending random choice so preparation and navigation consume one target.
struct PlaybackQueue {
    var tracks: [MusicPlaybackTrack] = [] { didSet { invalidateTarget() } }
    var currentIndex: Int? { didSet { invalidateTarget() } }
    var mode: MusicPlayMode = .sequence { didSet { invalidateTarget() } }
    private(set) var pendingRandomIndex: Int?
    private var explicitNextID: Int?

    mutating func invalidateTarget() { pendingRandomIndex = nil; explicitNextID = nil }
    mutating func prioritizeNext(_ id: Int) { explicitNextID = id; pendingRandomIndex = nil }

    mutating func target(from index: Int, offset: Int, isAuto: Bool,
                         random: (Range<Int>) -> Int = { Int.random(in: $0) }) -> Int? {
        guard tracks.indices.contains(index) else { return nil }
        if offset > 0, let explicitNextID, let target = tracks.firstIndex(where: { $0.id == explicitNextID }) { return target }
        switch mode {
        case .random:
            guard tracks.count > 1 else { return isAuto ? nil : index }
            if offset > 0, let pendingRandomIndex, pendingRandomIndex != index,
               tracks.indices.contains(pendingRandomIndex) { return pendingRandomIndex }
            // Select from count-1 candidates; no unbounded retry loop.
            let sampled = random(0..<(tracks.count - 1))
            let target = sampled >= index ? sampled + 1 : sampled
            if offset > 0 { pendingRandomIndex = target }
            return target
        case .loop:
            return ((index + offset) % tracks.count + tracks.count) % tracks.count
        case .single where isAuto:
            return index
        case .single, .sequence:
            return tracks.indices.contains(index + offset) ? index + offset : nil
        }
    }

    mutating func nextForPreparation() -> MusicPlaybackTrack? {
        guard mode != .single, let currentIndex,
              let index = target(from: currentIndex, offset: 1, isAuto: true) else { return nil }
        return tracks[index]
    }
}
