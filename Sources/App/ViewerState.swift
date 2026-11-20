import simd
import Foundation
import QuartzCore
import AstroCore

enum FrameMode: Int { case heliocentric, galactic }

struct DisplayOptions: Equatable {
    var labels = true
    var orbits = true
    var trails = true
    var moons = true
    var dwarfs = true
    var comets = true
    var belt = true
}

struct FlyTransition {
    var from: BodyID
    var to: BodyID
    var start: CFTimeInterval
    var duration: CFTimeInterval
    var d0: Double
    var d1: Double
}

struct ScreenMarker {
    var id: BodyID
    var point: CGPoint   // UIKit coordinates (origin top-left)
    var radius: CGFloat  // on-screen radius of the body's disc (points)
}

/// State shared between the main thread (gestures, UI) and SceneKit's render thread.
final class ViewerState: @unchecked Sendable {
    private let lock = NSLock()
    let clock = SimClock()

    private var _yaw = 0.6, _pitch = 0.35, _distanceKm = 60_000.0
    private var _focus: BodyID = .earth
    private var _fly: FlyTransition?
    private var _mode: FrameMode = .heliocentric
    private var _options = DisplayOptions()
    private var _markers: [ScreenMarker] = []
    private var _labels: [LabelItem] = []
    private var _viewSize = CGSize(width: 390, height: 844)

    func read<T>(_ f: (ViewerState) -> T) -> T { f(self) }

    var yaw: Double { get { locked { _yaw } } set { locked { _yaw = newValue } } }
    var pitch: Double {
        get { locked { _pitch } }
        set { locked { _pitch = min(max(newValue, -1.52), 1.52) } }
    }
    var distanceKm: Double { get { locked { _distanceKm } } set { locked { _distanceKm = newValue } } }
    var focus: BodyID { get { locked { _focus } } set { locked { _focus = newValue } } }
    var fly: FlyTransition? { get { locked { _fly } } set { locked { _fly = newValue } } }
    var mode: FrameMode { get { locked { _mode } } set { locked { _mode = newValue } } }
    var options: DisplayOptions { get { locked { _options } } set { locked { _options = newValue } } }
    var markers: [ScreenMarker] { get { locked { _markers } } set { locked { _markers = newValue } } }
    var labels: [LabelItem] { get { locked { _labels } } set { locked { _labels = newValue } } }
    var viewSize: CGSize { get { locked { _viewSize } } set { locked { _viewSize = newValue } } }

    /// Nice viewing distance for a body (km from its centre).
    static func defaultDistance(_ id: BodyID) -> Double {
        let b = Catalog.body(id)
        switch b.kind {
        case .star: return b.radiusKm * 6
        case .planet: return id == .saturn ? b.radiusKm * 7 : b.radiusKm * 4.5
        case .comet: return 600
        default: return max(b.radiusKm * 5, 60)
        }
    }

    static func minDistance(_ id: BodyID) -> Double {
        let b = Catalog.body(id)
        return b.radiusKm * max(b.shape.x, b.shape.y, b.shape.z) * 1.15
    }
    static let maxDistanceKm = 3.0e11

    /// Tour: a slower fly with an explicit end distance.
    func flyTo(_ id: BodyID, duration: Double, distanceKm d1: Double) {
        locked {
            _fly = FlyTransition(from: _focus, to: id, start: CACurrentMediaTime(), duration: duration,
                                 d0: _distanceKm, d1: d1)
            _focus = id
        }
    }

    func flyTo(_ id: BodyID) {
        locked {
            let now = CACurrentMediaTime()
            let from = _focus
            guard from != id || _fly != nil else {
                _distanceKm = Self.defaultDistance(id)
                return
            }
            let st = clock.jd
            let gap = length(Ephemeris.position(from, jd: st) - Ephemeris.position(id, jd: st))
            let duration = min(3.2, 1.4 + 0.25 * log10(max(gap, 1e4) / 1e4))
            _fly = FlyTransition(from: from, to: id, start: now, duration: duration,
                                 d0: _distanceKm, d1: Self.defaultDistance(id))
            _focus = id
        }
    }

    private func locked<T>(_ f: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return f()
    }
}
