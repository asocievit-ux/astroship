import AVFoundation
import Foundation

/// Original 528 Hz ambient loop (Resources/Audio/ambient528.m4a, made by tools/make_music.py).
/// Plays from launch at a modest volume. Session category .ambient: mixes with other audio and
/// respects the silent switch; the hardware volume buttons set the level. Pauses in the background.
@MainActor
final class AmbientMusic {
    static let shared = AmbientMusic()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
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
        if configured { return buffer != nil }
        configured = true
        guard let url = Bundle.main.url(forResource: "ambient528", withExtension: "m4a", subdirectory: "Audio"),
              let file = try? AVAudioFile(forReading: url),
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buf)) != nil else { return false }
        buffer = buf
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: buf.format)
        player.volume = volume
        return true
    }

    static let enabledKey = "music.enabled"
    /// Settings switch (persisted, default on).
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on { start() } else { pause() }
    }

    func start() {
        guard Self.enabled else { return }
        wantsPlay = true
        resumeIfWanted()
    }

    func pause() {
        wantsPlay = false
        player.pause()
        engine.pause()
    }

    func resumeIfWanted() {
        guard wantsPlay, configure(), let buf = buffer else { return }
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try s.setActive(true)
            if !engine.isRunning { try engine.start() }
            if !player.isPlaying {
                if !scheduled {
                    player.scheduleBuffer(buf, at: nil, options: .loops)
                    scheduled = true
                }
                player.play()
            }
        } catch {
            // Audio is decoration only; ignore failures (e.g. another app holds the hardware).
        }
    }

    private var scheduled = false

    private func restartAfterConfigChange() {
        scheduled = false
        player.stop()
        resumeIfWanted()
    }
}
