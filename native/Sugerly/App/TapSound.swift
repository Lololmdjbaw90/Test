import AudioToolbox
import Foundation

// Soft, bubbly click sounds for taps. The sounds are made in code (a tiny
// pitch-dropping "pop"), saved once as short WAV files and played as system
// sounds: instant, quiet, they mix with your music and they follow the
// phone's silent switch. Turn them off in Settings.
enum TapSound {
    enum Kind: CaseIterable { case tap, select, toggle }

    static let settingKey = "sugerly.clickSounds"

    private static var ids: [Kind: SystemSoundID] = [:]
    private static var ready = false
    private static var last = Date.distantPast

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    static func play(_ kind: Kind = .tap) {
        guard enabled else { return }
        // Never machine-gun: at most one click every 45 ms.
        let now = Date()
        guard now.timeIntervalSince(last) > 0.045 else { return }
        last = now
        prepare()
        if let id = ids[kind] { AudioServicesPlaySystemSound(id) }
    }

    // Builds the sounds once (a few KB each).
    static func prepare() {
        guard !ready else { return }
        ready = true
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        for kind in Kind.allCases {
            let url = dir.appendingPathComponent("sugerly-\(kind)-v1.wav")
            if !FileManager.default.fileExists(atPath: url.path) {
                try? wav(samples(kind)).write(to: url)
            }
            var id: SystemSoundID = 0
            if AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr { ids[kind] = id }
        }
    }

    static let rate = 44_100.0

    // A quick sine "pop": fast attack, pitch sliding down, soft decay.
    private static func samples(_ kind: Kind) -> [Int16] {
        let (from, to, length, volume): (Double, Double, Double, Double) = {
            switch kind {
            case .tap: return (1250, 620, 0.055, 0.32)
            case .select: return (1650, 1050, 0.05, 0.26)
            case .toggle: return (900, 1400, 0.07, 0.28)
            }
        }()
        let count = Int(rate * length)
        var phase = 0.0
        var out: [Int16] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let t = Double(i) / rate
            let progress = t / length
            let freq = from + (to - from) * min(1, progress * 1.6)
            phase += 2 * Double.pi * freq / rate
            let attack = min(1, t / 0.003)
            let decay = exp(-progress * 5.5)
            let tone = sin(phase) * 0.85 + sin(phase * 2) * 0.15
            out.append(Int16(max(-1, min(1, tone * attack * decay * volume)) * Double(Int16.max)))
        }
        return out
    }

    static func wav(_ samples: [Int16]) -> Data {
        var data = Data()
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36) + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(rate)); put(UInt32(rate) * 2); put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); put(bytes)
        for s in samples { put(s) }
        return data
    }
}

// A sparkly "you got coins" chime for rewards: a quick rising bell arpeggio
// with a little shimmer on top. Made in code like the taps; follows the
// silent switch.
enum RewardSound {
    private static var id: SystemSoundID = 0

    static func play() {
        if id == 0 {
            let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("sugerly-reward-v1.wav")
            if !FileManager.default.fileExists(atPath: url.path) { try? TapSound.wav(samples()).write(to: url) }
            AudioServicesCreateSystemSoundID(url as CFURL, &id)
        }
        if id != 0 { AudioServicesPlaySystemSound(id) }
    }

    private static func samples() -> [Int16] {
        let rate = TapSound.rate
        let length = 1.2
        var buffer = [Double](repeating: 0, count: Int(rate * length))
        func bell(_ freq: Double, at start: Double, volume: Double, decay: Double) {
            let from = Int(start * rate)
            let count = min(Int(0.9 * rate), buffer.count - from)
            guard count > 0 else { return }
            for i in 0..<count {
                let t = Double(i) / rate
                let env = min(1, t / 0.003) * exp(-t * decay)
                let phase = 2 * Double.pi * freq * t
                buffer[from + i] += (sin(phase) + 0.3 * sin(phase * 2) + 0.1 * sin(phase * 3.01)) * env * volume
            }
        }
        // C6 E6 G6 C7, then a high E7 sparkle.
        for (i, f) in [1046.5, 1318.5, 1568.0, 2093.0].enumerated() {
            bell(f, at: Double(i) * 0.075, volume: 0.2, decay: 6)
        }
        bell(2637.0, at: 0.32, volume: 0.14, decay: 5)
        // Tiny twinkles.
        for (f, t) in [(3520.0, 0.40), (4186.0, 0.50), (3951.0, 0.62), (4699.0, 0.74)] {
            bell(f, at: t, volume: 0.05, decay: 22)
        }
        return buffer.map { Int16(max(-1, min(1, $0)) * Double(Int16.max)) }
    }
}
