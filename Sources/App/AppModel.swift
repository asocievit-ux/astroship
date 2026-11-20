import simd
import Foundation
import SwiftUI
import AstroCore

/// Time-speed steps: simulated seconds per real second.
enum SpeedSteps {
    static let values: [Double] = [1, 60, 3_600, 86_400, 604_800, 2_629_800, 31_557_600, 315_576_000]
    static func label(_ rate: Double) -> String {
        if rate == 0 { return L("speed.paused") }
        let a = abs(rate)
        let sign = rate < 0 ? "−" : ""
        let unit: String
        switch a {
        case ..<2: unit = L("speed.realtime")
        case ..<3_000: unit = L("speed.minPerSec")
        case ..<80_000: unit = L("speed.hourPerSec")
        case ..<600_000: unit = L("speed.dayPerSec")
        case ..<2_000_000: unit = L("speed.weekPerSec")
        case ..<30_000_000: unit = L("speed.monthPerSec")
        case ..<300_000_000: unit = L("speed.yearPerSec")
        default: unit = L("speed.decadePerSec")
        }
        return sign + unit
    }
}

struct BodyInfo {
    var id: BodyID
    var distanceSunKm: Double
    var distanceEarthKm: Double
    var orbitalSpeed: Double      // km/s around its parent (Sun for planets)
    var galacticSpeed: Double     // km/s relative to the galactic centre
    var periodDays: Double?
}

@MainActor
final class AppModel: ObservableObject {
    let viewer = ViewerState()
    lazy var renderer: SolarRenderer = {
        let r = SolarRenderer(state: viewer)
        r.onSnapshot = { [weak self] st in self?.snapshot(st) }
        return r
    }()

    @Published var dateText = ""
    @Published var isLive = true
    @Published var rate: Double = 1
    @Published var paused = false
    @Published var focus: BodyID = .earth
    @Published var info: BodyInfo?
    @Published var mode: FrameMode = .heliocentric {
        didSet { viewer.mode = mode; UserDefaults.standard.set(mode.rawValue, forKey: "frameMode") }
    }
    @Published var options = DisplayOptions() {
        didSet { viewer.options = options; saveOptions() }
    }
    @Published var showGalaxy = false
    @Published var showPicker = false
    @Published var showSettings = false
    @Published var showInfo = true
    /// Viewing mode: every bar and card hidden, only the scene. Any tap brings the controls back.
    @Published var viewing = false
    /// Km travelled through the galaxy since the app was opened (real time).
    @Published var travelledKm = 0.0
    private let openedAt = Date()
    private var rateBeforePause: Double = 1
    private(set) var interacted = false
    /// Screenshot runs only: show SceneKit's fps / frame-time statistics.
    private(set) var debugStats = false

    init() {
        if let m = FrameMode(rawValue: UserDefaults.standard.integer(forKey: "frameMode")) { mode = m }
        loadOptions()
        viewer.mode = mode
        viewer.options = options
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-shot"), i + 1 < args.count {
            applyScreenshot(args[i + 1])
        } else {
            applyOpeningView()
        }
    }

    /// Opening view on every cold start: the whole solar system sailing through the Milky Way.
    /// Galactic frame, camera ahead of the Sun looking back along its path so the planets' helical
    /// trails recede into the distance, and time running at one month per second.
    func applyOpeningView() {
        mode = .galactic
        viewer.mode = .galactic
        if !options.trails { options.trails = true }   // the opening view is all about the trails
        viewer.focus = .sun; focus = .sun
        viewer.distanceKm = Self.openingDistanceKm
        let (yaw, pitch) = Self.openingAngles()
        viewer.yaw = yaw; viewer.pitch = pitch
        setRate(Self.openingRate)
        showInfo = false            // clean galaxy view at launch; tapping a body opens its card
        viewing = true              // launch in viewing mode: only the scene; a tap brings the controls back
    }

    static let openingRate = 2_629_800.0          // 1 month per second
    static let openingDistanceKm = 1.2e10         // about 80 AU: trails stream across the screen

    /// The camera looks at the Sun towards galactic longitude 11 deg, latitude +14 deg, so the bright
    /// Milky Way core with its dust lanes sits in the lower left behind the Sun and the Sun's path and
    /// the planets' trails run diagonally across the screen. The Sun is the focus (floating origin), so
    /// the camera keeps homing on it as it moves.
    static func openingAngles() -> (Double, Double) {
        let l = 11.0 * .pi / 180, b = 14.0 * .pi / 180
        let g = SIMD3<Double>(cos(b) * cos(l), cos(b) * sin(l), sin(b))
        let view = normalize(Frames.eclToScene * (Frames.galToEcl * g))   // camera -> Sun
        let d = -view                                                    // Sun -> camera
        return (atan2(d.x, d.z), asin(max(-1, min(1, d.y))))
    }

    /// Tap on the 3D view: nearest body within a generous hit area. Returns false if nothing is near.
    @discardableResult
    func handleTap(at p: CGPoint) -> Bool {
        guard let id = TapPicker.pick(at: p, markers: viewer.markers, focus: viewer.focus) else { return false }
        select(id)
        return true
    }

    func noteInteraction() { interacted = true }

    func select(_ id: BodyID) {
        viewer.flyTo(id)
        focus = id
        showInfo = true
    }

    // MARK: Time

    func play() {
        if paused { setRate(rateBeforePause == 0 ? 1 : rateBeforePause) }
    }
    func togglePause() {
        if paused { play() } else { rateBeforePause = rate; setRate(0) }
    }
    func faster() { step(+1) }
    func slower() { step(-1) }
    func goLive() {
        viewer.clock.goLive()
        rate = 1; paused = false
    }

    private func step(_ dir: Int) {
        // Signed ladder: ... -yr, -mo, ..., -1, +1, ..., +10yr
        let ladder = SpeedSteps.values.reversed().map { -$0 } + SpeedSteps.values
        let current = paused ? rateBeforePause : rate
        let idx = ladder.firstIndex(where: { $0 >= current - 1e-9 }) ?? ladder.count - 1
        let next = ladder[min(max(idx + dir, 0), ladder.count - 1)]
        setRate(next)
    }

    func setRate(_ r: Double) {
        viewer.clock.rate = r
        rate = r
        paused = r == 0
    }

    // MARK: Snapshot (main thread, ~4 Hz)

    private func snapshot(_ st: EphemerisState) {
        dateText = Fmt.dateFormatter.string(from: AstroTime.date(julian: st.jd))
        isLive = viewer.clock.isLive
        let jd = st.jd
        if jd <= AstroTime.minJD + 1 || jd >= AstroTime.maxJD - 1, rate != 0 { setRate(0) }
        travelledKm = Date().timeIntervalSince(openedAt) * GalacticMotion.speed
        let id = viewer.focus
        let body = Catalog.body(id)
        let dt = 0.01
        let p0 = Ephemeris.relativeToParent(id, jd: jd - dt), p1 = Ephemeris.relativeToParent(id, jd: jd + dt)
        let orbital = length(p1 - p0) / (2 * dt * 86_400)
        let h0 = Ephemeris.position(id, jd: jd - dt), h1 = Ephemeris.position(id, jd: jd + dt)
        let helioV = (h1 - h0) / (2 * dt * 86_400)
        let gal = length(helioV + GalacticMotion.velocityEcliptic)
        info = BodyInfo(id: id, distanceSunKm: length(st[id]), distanceEarthKm: length(st[id] - st[.earth]),
                        orbitalSpeed: body.kind == .star ? 0 : orbital, galacticSpeed: gal,
                        periodDays: Catalog.periodDays(id, jd: jd))
        if focus != id { focus = id }
    }

    // MARK: Options persistence

    private func saveOptions() {
        let d = UserDefaults.standard
        d.set(options.labels, forKey: "opt.labels"); d.set(options.orbits, forKey: "opt.orbits")
        d.set(options.trails, forKey: "opt.trails"); d.set(options.moons, forKey: "opt.moons")
        d.set(options.dwarfs, forKey: "opt.dwarfs"); d.set(options.comets, forKey: "opt.comets")
        d.set(options.belt, forKey: "opt.belt")
    }

    private func loadOptions() {
        let d = UserDefaults.standard
        guard d.object(forKey: "opt.labels") != nil else { return }
        options = DisplayOptions(labels: d.bool(forKey: "opt.labels"), orbits: d.bool(forKey: "opt.orbits"),
                                 trails: d.bool(forKey: "opt.trails"), moons: d.bool(forKey: "opt.moons"),
                                 dwarfs: d.bool(forKey: "opt.dwarfs"), comets: d.bool(forKey: "opt.comets"),
                                 belt: d.bool(forKey: "opt.belt"))
    }

    // MARK: Simulator screenshots (launch argument "-shot <name>")

    private func applyScreenshot(_ name: String) {
        AdGate.disabledForScreenshots = true
        switch name {
        case "earth":
            viewer.focus = .earth; focus = .earth
            viewer.distanceKm = 26_000; viewer.yaw = 2.2; viewer.pitch = 0.25
        case "saturn":
            viewer.focus = .saturn; focus = .saturn
            viewer.distanceKm = 420_000; viewer.yaw = 0.9; viewer.pitch = 0.35
        case "inner":
            viewer.focus = .sun; focus = .sun
            viewer.distanceKm = 5.5e8; viewer.yaw = 0.4; viewer.pitch = 0.9
            mode = .heliocentric
        case "galactic":
            viewer.focus = .sun; focus = .sun
            viewer.distanceKm = 2.2e9; viewer.yaw = 1.9; viewer.pitch = 0.45
            mode = .galactic
        case "galaxy":
            showGalaxy = true
        case "opening":
            applyOpeningView()
            return
        case "tap":
            // Inner solar system; after 3 s simulate a tap 18 pt away from Mars (no marker on screen).
            viewer.focus = .sun; focus = .sun
            viewer.distanceKm = 5.5e8; viewer.yaw = 0.4; viewer.pitch = 0.9
            mode = .heliocentric
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if let m = viewer.markers.first(where: { $0.id == .mars }) {
                    handleTap(at: CGPoint(x: m.point.x + 18, y: m.point.y - 10))
                }
            }
        case "fast":
            // Max speed (10 years/s) in the opening view, with SceneKit's fps counter on screen.
            applyOpeningView()
            setRate(SpeedSteps.values.last!)
            debugStats = true
            return
        case "fasthelio":
            viewer.focus = .sun; focus = .sun
            viewer.distanceKm = 7.0e9; viewer.yaw = 0.4; viewer.pitch = 0.9
            mode = .heliocentric
            setRate(SpeedSteps.values.last!)
            debugStats = true
        case "viewing":
            applyOpeningView()
            return
        case "controls":
            // Opening view after the first tap: controls visible.
            applyOpeningView()
            viewing = false
            return
        case "picker":
            showPicker = true
        case "fly":
            // Same call the body list makes: fly from the Sun to Jupiter after 2 s.
            viewer.focus = .sun; focus = .sun
            viewer.distanceKm = 5.5e8; viewer.yaw = 0.4; viewer.pitch = 0.9
            mode = .heliocentric
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                select(.jupiter)
            }
        default: break
        }
        viewer.mode = mode
    }
}
