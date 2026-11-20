import Foundation
import QuartzCore
import AstroCore

/// Tour mode: a slow, calm, automatic camera journey from the Sun outwards. About one minute at
/// every stop (Sun, each planet, each major moon, the asteroid belt, Ceres / Vesta, dwarf planets,
/// comets): a slow fly-in, then a gentle orbit with a slow push-in. All controls and cards are hidden
/// (like viewing mode); the BGM keeps shuffling; a tap ends it. At the end it returns to the opening
/// view (about one minute per stop, ~42 min in all). Heliocentric frame, time at one hour per second so moons and spins move gently.
enum TourStop: Equatable {
    case body(BodyID)
    case belt

    static let all: [TourStop] = {
        let b: [BodyID] = [.sun, .mercury, .venus, .earth, .moon, .mars, .phobos, .deimos]
        let after: [BodyID] = [.ceres, .vesta,
                               .jupiter, .io, .europa, .ganymede, .callisto,
                               .saturn, .mimas, .enceladus, .tethys, .dione, .rhea, .titan, .iapetus,
                               .uranus, .miranda, .ariel, .umbriel, .titania, .oberon,
                               .neptune, .triton,
                               .pluto, .charon, .eris, .haumea, .makemake,
                               .halley, .encke, .churyumov, .swiftTuttle, .haleBopp]
        return b.map { .body($0) } + [.belt] + after.map { .body($0) }
    }()

    var focus: BodyID { if case .body(let id) = self { return id }; return .sun }

    /// Camera distance at arrival; the camera then eases in to `closeFactor` of it.
    var distanceKm: Double {
        switch self {
        case .belt: return 1.9e9                                     // ~13 au: the whole belt
        case .body(let id): return ViewerState.defaultDistance(id) * 1.7
        }
    }
    var closeFactor: Double { self == .belt ? 0.8 : 0.62 }
}

@MainActor
final class TourDirector {
    static let stopSeconds = 60.0
    static let flySeconds = 10.0
    private weak var model: AppModel?
    private var timer: Timer?
    private var index = 0
    private var stopStart: CFTimeInterval = 0
    private var yaw0 = 0.0

    init(model: AppModel) { self.model = model }

    var running: Bool { timer != nil }

    func start(at first: Int = 0) {
        guard let model else { return }
        stop()
        model.mode = .heliocentric
        model.setRate(3_600)                 // 1 hour per second
        model.showInfo = false
        index = max(0, min(first, TourStop.all.count - 1))
        yaw0 = model.viewer.yaw
        begin(TourStop.all[index])
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func begin(_ s: TourStop) {
        guard let model else { return }
        stopStart = CACurrentMediaTime()
        yaw0 = model.viewer.yaw
        model.viewer.flyTo(s.focus, duration: index == 0 ? 6 : Self.flySeconds, distanceKm: s.distanceKm)
        model.focus = s.focus
    }

    private func tick() {
        guard let model else { return }
        let t = CACurrentMediaTime() - stopStart
        if t >= Self.stopSeconds {
            index += 1
            if index >= TourStop.all.count {
                stop()
                model.endTour(finished: true)
                return
            }
            begin(TourStop.all[index])
            return
        }
        let s = TourStop.all[index]
        // Gentle orbit: a third of a turn per stop, slowly breathing elevation.
        let ease = smooth(t / Self.stopSeconds)
        model.viewer.yaw = yaw0 + 2 * .pi / 3 * ease
        let basePitch = s == .belt ? 0.42 : 0.22
        model.viewer.pitch = basePitch + 0.12 * sin(t / Self.stopSeconds * 2 * .pi)
        if model.viewer.fly == nil {
            let k = smooth(max(0, t - Self.flySeconds) / (Self.stopSeconds - Self.flySeconds))
            let d = s.distanceKm * (1 - (1 - s.closeFactor) * k)
            model.viewer.distanceKm = max(d, ViewerState.minDistance(s.focus) * 1.2)
        }
    }

    private func smooth(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }
}
