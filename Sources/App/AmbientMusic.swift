import AVFoundation
import Foundation

/// Background music: every audio file in the bundle's Audio folder (Resources/Audio, licences in
/// docs/licenses.md) played as an endless gapless playlist in shuffled order, reshuffled each cycle
/// without repeating a track back-to-back. Adding a track = dropping a 44.1 kHz stereo file in
/// Resources/Audio (tools/add_bgm.sh re-encodes one). Plays from launch at a modest volume. Session category .playback: plays even with the silent switch on
/// (user request); the hardware volume buttons set the level. Pauses in the background.
@MainActor
final class AmbientMusic {
    static let shared = AmbientMusic()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    // Streamed from disk (far too long to hold decoded). The next track is always queued behind the
    // playing one, so the playlist is gapless. Each scheduled pass opens its own reader.
    private var tracks: [URL] = []
    private var order: [URL] = []          // remaining tracks of the current shuffled cycle
    private var lastQueued: URL?
    private var format: AVAudioFormat?
    static let audioExtensions: Set<String> = ["m4a", "mp3", "aac", "wav", "caf", "aif", "aiff"]
    private var configured = false
    private var wantsPlay = false
    private let volume: Float = 0.35

    private init() {
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
    }

    private func configure() -> Bool {
        if configured { return format != nil }
        configured = true
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Audio"),
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return false }
        let candidates = urls.filter { Self.audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        // The player node runs at one format; keep only tracks that match the first readable one.
        for url in candidates {
            guard let f = try? AVAudioFile(forReading: url) else { continue }
            if format == nil { format = f.processingFormat }
            if f.processingFormat == format { tracks.append(url) }
        }
        guard let fmt = format, !tracks.isEmpty else { return false }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
        player.volume = volume
        return true
    }

    nonisolated static let enabledKey = "music.enabled"
    /// Settings switch (persisted, default on).
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on { start() } else { pause() }
    }

    func start() {
        guard Self.enabled, !SleepTimer.shared.asleep else { return }
        fadeTimer?.invalidate(); fadeTimer = nil
        player.volume = volume
        wantsPlay = true
        resumeIfWanted()
    }

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
                    scheduled = true
                    scheduleNext(); scheduleNext()   // playing track + the next one queued -> gapless
                }
                player.play()
            }
        } catch {
            // Audio is decoration only; ignore failures (e.g. another app holds the hardware).
        }
    }

    private var scheduled = false
    private var generation = 0

    private func scheduleNext() {
        guard let url = nextTrack(), let f = try? AVAudioFile(forReading: url) else { return }
        let gen = generation
        player.scheduleFile(f, at: nil, completionCallbackType: .dataConsumed) { _ in
            Task { @MainActor in
                let m = AmbientMusic.shared
                if m.generation == gen, m.scheduled { m.scheduleNext() }
            }
        }
    }

    /// Shuffled cycles over all tracks; a new cycle never starts with the track that just played.
    private func nextTrack() -> URL? {
        guard !tracks.isEmpty else { return nil }
        if order.isEmpty {
            order = tracks.shuffled()
            if order.count > 1, order.first == lastQueued { order.swapAt(0, Int.random(in: 1..<order.count)) }
        }
        let url = order.removeFirst()
        lastQueued = url
        return url
    }

    private func restartAfterConfigChange() {
        scheduled = false
        generation += 1
        player.stop()
        resumeIfWanted()
    }
}
