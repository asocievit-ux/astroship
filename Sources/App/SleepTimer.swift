import Foundation
import SwiftUI
import UIKit

/// Sleep timer (Settings). When it runs out: the music fades out and stops, the 3D view stops
/// rendering, and the system idle timer is re-enabled so the device locks itself. The app keeps
/// running (no exit()). A tap on the screen wakes everything up again.
@MainActor
final class SleepTimer: ObservableObject {
    static let shared = SleepTimer()
    static let choices = [0, 15, 30, 45, 60, 90, 120]   // minutes; 0 = off

    @Published var minutes = 0 { didSet { restart() } }
    @Published private(set) var endDate: Date?
    @Published private(set) var asleep = false

    /// Set by the app: pauses / resumes rendering.
    var onSleep: (() -> Void)?
    var onWake: (() -> Void)?

    private var timer: Timer?

    /// Start (or restart) a timer of `m` minutes. Setting `minutes` alone would no-op if it is
    /// already that value.
    func start(minutes m: Int) {
        if minutes == m { restart() } else { minutes = m }
    }

    private func restart() {
        timer?.invalidate(); timer = nil
        guard minutes > 0 else { endDate = nil; return }
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        endDate = end
        timer = Timer.scheduledTimer(withTimeInterval: end.timeIntervalSinceNow, repeats: false) { _ in
            Task { @MainActor in SleepTimer.shared.fire() }
        }
    }

    /// Also called when the app returns to the foreground, in case the timer passed while suspended.
    func checkExpired() {
        if let end = endDate, Date() >= end { fire() }
    }

    private func fire() {
        timer?.invalidate(); timer = nil
        endDate = nil
        minutes = 0
        asleep = true
        AmbientMusic.shared.fadeOutAndStop(seconds: 8)
        onSleep?()
        UIApplication.shared.isIdleTimerDisabled = false   // let the device auto-lock
    }

    func wake() {
        guard asleep else { return }
        asleep = false
        onWake?()
        UIApplication.shared.isIdleTimerDisabled = true
        AmbientMusic.shared.start()
    }

    func remainingText(now: Date) -> String? {
        guard let end = endDate else { return nil }
        let s = max(0, Int(end.timeIntervalSince(now)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
