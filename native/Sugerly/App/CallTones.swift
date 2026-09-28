import AudioToolbox
import Foundation

// Call sounds made just for Sugerly (instead of borrowing iOS sounds like the
// charging chime): a soft marimba-style ringtone for incoming calls, and a
// gentle two-tone "tuu" while your call is ringing on the other side.
enum CallTones {
    enum Kind: CaseIterable { case ringtone, ringback }

    private static var ids: [Kind: SystemSoundID] = [:]
    private static var ready = false

    static func play(_ kind: Kind) {
        prepare()
        if let id = ids[kind] { AudioServicesPlaySystemSound(id) }
    }

    private static func prepare() {
        guard !ready else { return }
        ready = true
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        for kind in Kind.allCases {
            let url = dir.appendingPathComponent("sugerly-call-\(kind)-v1.wav")
            if !FileManager.default.fileExists(atPath: url.path) {
                try? TapSound.wav(samples(kind)).write(to: url)
            }
            var id: SystemSoundID = 0
            if AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr { ids[kind] = id }
        }
    }

    private static func samples(_ kind: Kind) -> [Int16] {
        let rate = TapSound.rate
        switch kind {
        case .ringtone:
            // A little rising-and-falling marimba phrase.
            let notes: [(freq: Double, at: Double)] = [(1046.5, 0.00), (1318.5, 0.14), (1568.0, 0.28), (2093.0, 0.42), (1568.0, 0.64), (1318.5, 0.78)]
            let length = 1.5
            var buffer = [Double](repeating: 0, count: Int(rate * length))
            for note in notes {
                let start = Int(note.at * rate)
                let count = min(Int(0.55 * rate), buffer.count - start)
                guard count > 0 else { continue }
                for i in 0..<count {
                    let t = Double(i) / rate
                    let attack = min(1, t / 0.004)
                    let decay = exp(-t * 7.5)
                    let phase = 2 * Double.pi * note.freq * t
                    let tone = sin(phase) + 0.28 * sin(phase * 2) + 0.08 * sin(phase * 3)
                    buffer[start + i] += tone * attack * decay * 0.26
                }
            }
            return buffer.map { Int16(max(-1, min(1, $0)) * Double(Int16.max)) }
        case .ringback:
            // Two soft tones together for about a second, faded in and out.
            let length = 1.1
            let count = Int(rate * length)
            return (0..<count).map { i in
                let t = Double(i) / rate
                let fade = min(1, t / 0.04) * min(1, (length - t) / 0.06)
                let tone = (sin(2 * Double.pi * 440 * t) + sin(2 * Double.pi * 480 * t)) * 0.5
                return Int16(max(-1, min(1, tone * fade * 0.16)) * Double(Int16.max))
            }
        }
    }
}
