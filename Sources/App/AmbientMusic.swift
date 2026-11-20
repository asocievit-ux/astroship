import AVFoundation
import Foundation

/// Background music: every audio file in the bundle's Audio folder (Resources/Audio, licences in
/// docs/licenses.md) played as an endless playlist, always shuffled among the tracks the user has not
/// excluded (minus button in the music screen), reshuffled each cycle without back-to-back repeats.
/// Tapping a track in the music screen plays it; the shuffle then continues. Adding a track = dropping a
/// 44.1 kHz stereo file in Resources/Audio (tools/add_bgm.sh) and a line in `BGMCatalog`.
/// Session category .playback: plays even with the silent switch on (user request); the hardware
/// volume buttons set the level. Pauses in the background.
@MainActor
final class AmbientMusic: ObservableObject {
    static let shared = AmbientMusic()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// All bundled tracks in list (file-name) order. Streamed from disk, one reader per pass.
    @Published private(set) var tracks: [BGMTrack] = []
    @Published private(set) var current: BGMTrack?
    @Published private(set) var isPlaying = false
    /// File names the user excluded with the minus button (persisted; at least one track stays in).
    @Published private(set) var excluded: Set<String>
    /// Repeat the current track forever (set by tapping a track; toggle in the music screen).
    @Published var repeatOne: Bool {
        didSet { UserDefaults.standard.set(repeatOne, forKey: Self.repeatKey) }
    }

    private var order: [BGMTrack] = []        // remaining tracks of the current shuffled cycle
    private var history: [BGMTrack] = []      // for the previous button
    private var format: AVAudioFormat?
    static let audioExtensions: Set<String> = ["m4a", "mp3", "aac", "wav", "caf", "aif", "aiff"]
    private var configured = false
    private var wantsPlay = false
    private let volume: Float = 0.35
    private var generation = 0
    nonisolated static let enabledKey = "music.enabled"
    private static let excludedKey = "music.excluded"
    private static let repeatKey = "music.repeatOne"
    private static let currentKey = "music.current"

    private init() {
        let d = UserDefaults.standard
        excluded = Set(d.stringArray(forKey: Self.excludedKey) ?? [])
        repeatOne = d.bool(forKey: Self.repeatKey)
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                if raw == AVAudioSession.InterruptionType.ended.rawValue { AmbientMusic.shared.resumeIfWanted() }
            }
        }
        nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { _ in
            Task { @MainActor in AmbientMusic.shared.restartAfterConfigChange() }
        }
        _ = configure()
    }

    @discardableResult
    private func configure() -> Bool {
        if configured { return format != nil }
        configured = true
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Audio"),
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return false }
        let candidates = urls.filter { Self.audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        // The player node runs at one format; keep only tracks that match the first readable one.
        var list: [BGMTrack] = []
        for url in candidates {
            guard let f = try? AVAudioFile(forReading: url) else { continue }
            if format == nil { format = f.processingFormat }
            if f.processingFormat == format {
                list.append(BGMTrack(url: url, duration: Double(f.length) / f.processingFormat.sampleRate))
            }
        }
        tracks = list
        excluded = excluded.intersection(list.map(\.id))
        if excluded.count >= list.count { excluded = [] }
        if repeatOne, let id = UserDefaults.standard.string(forKey: Self.currentKey),
           let t = list.first(where: { $0.id == id }), !excluded.contains(id) { current = t }
        guard let fmt = format, !tracks.isEmpty else { return false }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
        player.volume = volume
        return true
    }

    /// Settings switch (persisted, default on).
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        objectWillChange.send()
        if on { start() } else { pause() }
    }

    func start() {
        guard Self.enabled, !SleepTimer.shared.asleep else { return }
        fadeTimer?.invalidate(); fadeTimer = nil
        player.volume = volume
        wantsPlay = true
        resumeIfWanted()
    }

    // MARK: Music screen actions

    func isIncluded(_ t: BGMTrack) -> Bool { !excluded.contains(t.id) }
    var includedCount: Int { tracks.filter(isIncluded).count }

    /// Minus / plus button. The last included track cannot be excluded.
    func toggleIncluded(_ t: BGMTrack) {
        if excluded.contains(t.id) {
            excluded.remove(t.id)
        } else {
            guard includedCount > 1 else { return }
            excluded.insert(t.id)
            order.removeAll { $0 == t }
            if current == t { skip(to: nextTrack(after: t, ignoringRepeat: true)) }
        }
        UserDefaults.standard.set(Array(excluded).sorted(), forKey: Self.excludedKey)
    }

    /// Tapping a row: play that track now (re-including it if it was excluded); afterwards the shuffle
    /// continues (the repeat-one button is left as it is).
    func play(_ t: BGMTrack) {
        if excluded.contains(t.id) { toggleIncluded(t) }
        if !Self.enabled { UserDefaults.standard.set(true, forKey: Self.enabledKey); objectWillChange.send() }
        skip(to: t)
    }

    func next() { skip(to: nextTrack(after: current, ignoringRepeat: true)) }

    func previous() {
        while let t = history.popLast() {
            if isIncluded(t), t != current { skip(to: t, record: false); return }
        }
        // No history: step back in list order among included tracks.
        let inc = tracks.filter(isIncluded)
        guard !inc.isEmpty else { return }
        let i = current.flatMap { inc.firstIndex(of: $0) } ?? 0
        skip(to: inc[(i - 1 + inc.count) % inc.count], record: false)
    }

    func togglePlay() { setEnabled(!(Self.enabled && isPlaying)) }

    private func skip(to t: BGMTrack?, record: Bool = true) {
        guard let t else { return }
        if record, let c = current { history.append(c); if history.count > 50 { history.removeFirst() } }
        generation += 1
        scheduled = false
        player.stop()
        setCurrent(t)
        if Self.enabled, !SleepTimer.shared.asleep {
            wantsPlay = true
            resumeIfWanted()
        }
    }

    private func setCurrent(_ t: BGMTrack?) {
        current = t
        UserDefaults.standard.set(t?.id, forKey: Self.currentKey)
    }

    // MARK: Engine

    private var fadeTimer: Timer?

    /// Sleep timer: ramp the volume down, then stop (the Settings switch is left as it is).
    func fadeOutAndStop(seconds: Double) {
        guard wantsPlay else { return }
        fadeTimer?.invalidate()
        fadeStep = 0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: seconds / Double(Self.fadeSteps), repeats: true) { _ in
            Task { @MainActor in AmbientMusic.shared.fadeTick() }
        }
    }

    private static let fadeSteps = 40
    private var fadeStep = 0

    private func fadeTick() {
        fadeStep += 1
        player.volume = volume * Float(max(0, 1 - Double(fadeStep) / Double(Self.fadeSteps)))
        if fadeStep >= Self.fadeSteps {
            fadeTimer?.invalidate(); fadeTimer = nil
            pause()
            player.volume = volume
        }
    }

    func pause() {
        wantsPlay = false
        player.pause()
        engine.pause()
        isPlaying = false
    }

    func resumeIfWanted() {
        guard wantsPlay, configure(), format != nil else { return }
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .default, options: [])   // plays with the silent switch on
            try s.setActive(true)
            if !engine.isRunning { try engine.start() }
            if !player.isPlaying {
                if !scheduled {
                    if current == nil || !isIncluded(current!) {
                        setCurrent(nextTrack(after: nil, ignoringRepeat: true))
                    }
                    if let c = current { schedule(c) }
                }
                player.play()
            }
            isPlaying = player.isPlaying
        } catch {
            // Audio is decoration only; ignore failures (e.g. another app holds the hardware).
        }
    }

    private var scheduled = false

    /// One track at a time; the next is scheduled the moment this one finishes playing (the node keeps
    /// running, so the hand-over is a few ms). Changing the exclusions / repeat mode applies to the next
    /// track without cutting the current one.
    private func schedule(_ t: BGMTrack) {
        guard let f = try? AVAudioFile(forReading: t.url) else { return }
        scheduled = true
        let gen = generation
        player.scheduleFile(f, at: nil, completionCallbackType: .dataPlayedBack) { _ in
            Task { @MainActor in
                let m = AmbientMusic.shared
                guard m.generation == gen, m.scheduled else { return }
                let n = m.nextTrack(after: m.current, ignoringRepeat: false)
                if let c = m.current, n != c { m.history.append(c); if m.history.count > 50 { m.history.removeFirst() } }
                m.setCurrent(n)
                if let n { m.schedule(n) } else { m.scheduled = false }
            }
        }
    }

    /// Repeat-one keeps the track; otherwise shuffled cycles over the included tracks, never the same
    /// track twice in a row.
    private func nextTrack(after last: BGMTrack?, ignoringRepeat: Bool) -> BGMTrack? {
        if !ignoringRepeat, repeatOne, let last, isIncluded(last) { return last }
        let inc = tracks.filter(isIncluded)
        guard !inc.isEmpty else { return tracks.first }
        order.removeAll { !isIncluded($0) }
        if order.isEmpty {
            order = inc.shuffled()
            if order.count > 1, order.first == last { order.swapAt(0, Int.random(in: 1..<order.count)) }
        }
        var t = order.removeFirst()
        if t == last, !order.isEmpty { order.append(t); t = order.removeFirst() }
        return t
    }

    private func restartAfterConfigChange() {
        scheduled = false
        generation += 1
        player.stop()
        isPlaying = false
        resumeIfWanted()
    }
}

struct BGMTrack: Identifiable, Hashable {
    let url: URL
    let duration: Double
    var id: String { url.deletingPathExtension().lastPathComponent }
    var title: String { BGMCatalog.info[id]?.title ?? id }
    var artist: String { BGMCatalog.info[id]?.artist ?? "" }
    var durationText: String {
        let s = Int(duration.rounded()); return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Display names for the bundled tracks (Pixabay titles and creators; see docs/licenses.md).
enum BGMCatalog {
    static let info: [String: (title: String, artist: String)] = [
        "bgm1": ("Meditation Binaural 8 Hz 528 Hz", "Siarhei Korbut"),
        "bgm2": ("Activate Feminine Energy", "Soul Frequencies"),
        "bgm3": ("528 Hz Frequency Ambient Music", "Ribhav Agrawal"),
        "bgm4": ("Revelation of the Misty Planet", "Siarhei Korbut"),
        "bgm5": ("Sunset Glow", "Siarhei Korbut"),
        "bgm6": ("Angels Lullaby 528 Hz", "Siarhei Korbut"),
        "bgm7": ("528 Hz Solar Plexus Chakra Healing", "Roman Sol"),
        "bgm8": ("あなたはちゃんと守られるから、安心してね。", "KI-chorus"),
        "bgm9": ("528 Hz Résonance Solaire Arcturienne", "C-STyLe-Background"),
        "bgm10": ("639 Hz Harmonie du cœur arcturien", "C-STyLe-Background"),
        "bgm11": ("528 Hz Angelic Choir Meditation 2", "Megis-music"),
        "bgm12": ("963 Hz Énergie Arcturienne", "C-STyLe-Background"),
    ]
}
