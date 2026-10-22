import AudioToolbox
import Foundation

// Offline-rendered Earshot sounds, with synthesized fallbacks.
// Soft, bubbly sounds for the whole app: taps, tabs, switches, likes,
// sending, new messages, sheets opening and closing, and little chimes for
// "done" and "oops". They're made in code (short sine "pops" and bells),
// saved once as tiny WAV files and played as system sounds: instant, quiet,
// they mix with your music and they follow the phone's silent switch. Turn
// them off in Settings.
enum TapSound {
    enum Kind: String, CaseIterable {
        case tap, select, toggle, toggleOff, like, send, receive, open, close, chime, error
    }

    static let settingKey = "sugerly.clickSounds"

    private static var ids: [Kind: SystemSoundID] = [:]
    private static var ready = false
    private static var last = Date.distantPast

    // Off unless turned on in Settings, and never for ordinary taps: a
    // calm app doesn't click at you.
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? false
    }

    static func play(_ kind: Kind = .tap) {
        guard enabled, kind != .tap, kind != .select, kind != .open, kind != .close else { return }
        // Never machine-gun: at most one sound every 45 ms.
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
            let url = bundled(kind.rawValue) ?? dir.appendingPathComponent("sugerly-\(kind.rawValue)-v2.wav")
            if !FileManager.default.fileExists(atPath: url.path) {
                try? wav(samples(kind)).write(to: url)
            }
            var id: SystemSoundID = 0
            if AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr { ids[kind] = id }
        }
    }

    static func bundled(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "wav")
            ?? Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds")
    }

    static let rate = 44_100.0

    // One little sound: a sine "pop" sliding from one pitch to another, or a
    // soft bell that rings out.
    private struct Note {
        var at: Double
        var from: Double
        var to: Double
        var length: Double
        var volume: Double
        var bell = false
    }

    private static func notes(_ kind: Kind) -> [Note] {
        switch kind {
        case .tap:
            return [Note(at: 0, from: 1250, to: 620, length: 0.055, volume: 0.32)]
        case .select:
            return [Note(at: 0, from: 1650, to: 1050, length: 0.05, volume: 0.26)]
        case .toggle:
            return [Note(at: 0, from: 900, to: 1400, length: 0.07, volume: 0.28)]
        case .toggleOff:
            return [Note(at: 0, from: 1300, to: 800, length: 0.07, volume: 0.26)]
        case .like:
            // Two bubbly pops going up.
            return [Note(at: 0, from: 880, to: 1320, length: 0.06, volume: 0.26),
                    Note(at: 0.07, from: 1320, to: 1980, length: 0.08, volume: 0.24)]
        case .send:
            // A quick swoosh up with a tiny sparkle at the end.
            return [Note(at: 0, from: 520, to: 1700, length: 0.13, volume: 0.22),
                    Note(at: 0.11, from: 2350, to: 2350, length: 0.04, volume: 0.07, bell: true)]
        case .receive:
            // A soft two-note bell.
            return [Note(at: 0, from: 1318.5, to: 1318.5, length: 0.12, volume: 0.15, bell: true),
                    Note(at: 0.09, from: 1760, to: 1760, length: 0.16, volume: 0.15, bell: true)]
        case .open:
            return [Note(at: 0, from: 600, to: 1000, length: 0.09, volume: 0.22)]
        case .close:
            return [Note(at: 0, from: 1000, to: 600, length: 0.09, volume: 0.2)]
        case .chime:
            // "Done!": two little bells, low then high.
            return [Note(at: 0, from: 1568, to: 1568, length: 0.1, volume: 0.12, bell: true),
                    Note(at: 0.07, from: 2093, to: 2093, length: 0.14, volume: 0.12, bell: true)]
        case .error:
            // "Oops": two soft notes going down.
            return [Note(at: 0, from: 520, to: 480, length: 0.09, volume: 0.22),
                    Note(at: 0.11, from: 400, to: 360, length: 0.12, volume: 0.22)]
        }
    }

    private static func samples(_ kind: Kind) -> [Int16] {
        let list = notes(kind)
        let tail = 0.25
        let total = list.map { $0.at + $0.length + ($0.bell ? tail : 0) }.max() ?? 0.1
        var buffer = [Double](repeating: 0, count: Int(rate * total) + 1)
        for n in list {
            let start = Int(n.at * rate)
            let count = min(Int((n.length + (n.bell ? tail : 0)) * rate), buffer.count - start)
            guard count > 0 else { continue }
            var phase = 0.0
            for i in 0..<count {
                let t = Double(i) / rate
                let progress = min(1, t / n.length)
                let freq = n.from + (n.to - n.from) * min(1, progress * 1.6)
                phase += 2 * Double.pi * freq / rate
                let attack = min(1, t / 0.003)
                let decay = n.bell ? exp(-t * 11) : exp(-progress * 5.5)
                let tone = n.bell
                    ? (sin(phase) + 0.25 * sin(phase * 2) + 0.08 * sin(phase * 3.01)) / 1.33
                    : sin(phase) * 0.85 + sin(phase * 2) * 0.15
                buffer[start + i] += tone * attack * decay * n.volume
            }
        }
        return buffer.map { Int16(max(-1, min(1, $0)) * Double(Int16.max)) }
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
            let url = TapSound.bundled("reward") ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
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
