import Foundation
import simd

public enum AstroTime {
    public static let j2000 = 2_451_545.0
    /// TT - UTC, close enough for this viewer (leap seconds + 32.184 s).
    public static let ttMinusUTC = 69.184

    public static func julianDate(_ date: Date) -> Double {
        2_440_587.5 + (date.timeIntervalSince1970 + ttMinusUTC) / 86_400
    }
    public static func date(julian jd: Double) -> Date {
        Date(timeIntervalSince1970: (jd - 2_440_587.5) * 86_400 - ttMinusUTC)
    }
    /// Supported range of the planetary theory (JPL approximate elements, 3000 BC to AD 3000).
    public static let minJD = 1_721_423.5   // AD 1-01-01
    public static let maxJD = 2_816_787.5   // AD 3000-01-01
}

/// Simulation clock. `rate` is simulated seconds per real second (1 = real time, 0 = paused,
/// negative = backwards). Thread-safe: read from the render thread, written from the main thread.
public final class SimClock: @unchecked Sendable {
    private let lock = NSLock()
    private var anchorWall: Double
    private var anchorJD: Double
    private var _rate: Double = 1
    private let wall: () -> Double

    public init(wall: @escaping () -> Double = { Date().timeIntervalSince1970 }) {
        self.wall = wall
        anchorWall = wall()
        anchorJD = AstroTime.julianDate(Date(timeIntervalSince1970: anchorWall))
    }

    public var jd: Double {
        lock.lock(); defer { lock.unlock() }
        return currentLocked()
    }

    public var rate: Double {
        get { lock.lock(); defer { lock.unlock() }; return _rate }
        set {
            lock.lock(); defer { lock.unlock() }
            reanchorLocked()
            _rate = newValue
        }
    }

    public func set(jd: Double) {
        lock.lock(); defer { lock.unlock() }
        anchorWall = wall()
        anchorJD = min(max(jd, AstroTime.minJD), AstroTime.maxJD)
    }

    /// Back to the present moment at real-time speed.
    public func goLive() {
        lock.lock(); defer { lock.unlock() }
        anchorWall = wall()
        anchorJD = AstroTime.julianDate(Date(timeIntervalSince1970: anchorWall))
        _rate = 1
    }

    /// True when the clock shows the present (within a minute) at real-time speed.
    public var isLive: Bool {
        lock.lock(); defer { lock.unlock() }
        let now = AstroTime.julianDate(Date(timeIntervalSince1970: wall()))
        return _rate == 1 && abs(currentLocked() - now) < 60.0 / 86_400
    }

    private func currentLocked() -> Double {
        let jd = anchorJD + (wall() - anchorWall) * _rate / 86_400
        if jd < AstroTime.minJD || jd > AstroTime.maxJD {
            return min(max(jd, AstroTime.minJD), AstroTime.maxJD)
        }
        return jd
    }

    private func reanchorLocked() {
        anchorJD = currentLocked()
        anchorWall = wall()
    }
}
