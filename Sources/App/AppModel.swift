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
    /// visionOS: the immersive orrery is open.
    @Published var immersiveOpen = false
    /// Screenshot run that should open the immersive space on launch (visionOS).
    private(set) var immersiveShot = false
    @Published var isLive = true
    @Published var rate: Double = 1
    @Published var paused = false
    @Published var focus: BodyID = .earth
    @Published var info: BodyInfo?
    @Published var mode: FrameMode = .heliocentric {
        didSet {
            viewer.mode = mode; UserDefaults.standard.set(mode.rawValue, forKey: "frameMode")
            // One "Orbits" switch in Settings: each mode starts from its own default when entered
            // (galactic helix trails on, heliocentric orbit ellipses off); the user can flip it within a mode.
            if mode != oldValue {
                if mode == .galactic { options.trails = true } else { options.orbits = false }
            }
        }
    }
    @Published var options = DisplayOptions() {
        didSet { viewer.options = options; saveOptions() }
    }
    @Published var showGalaxy = false
    @Published var showPicker = false
    @Published var showSettings = false
    @Published private(set) var touring = false
    lazy var tour = TourDirector(model: self)
    @Published var showMusic = false   // Settings > Music pushed (screenshot mode)
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
    static let openingDistanceKm = 2.45e9         // about 16 AU: the asteroid belt spans the screen width

    /// The user's reference framing (v3): camera ~16 deg above the ecliptic, in the vertical plane that
    /// holds the Sun's galactic velocity and behind it, so with the ecliptic-north "up" the motion points
    /// straight up the screen and the helix trails stream down from the Sun; the asteroid belt is a wide,
    /// nearly edge-on ellipse. The Sun is the focus (floating origin), so the camera keeps homing on it.
    static func openingAngles() -> (Double, Double) {
        let v = Frames.eclToScene * GalacticMotion.velocityEcliptic
        let yaw = atan2(v.x, v.z) - .pi
        return (yaw, 16.0 * .pi / 180)
    }

    /// Sleep timer: stop / restart SceneKit rendering (the simulated clock keeps its own time).
    func setRendering(_ on: Bool) {
        guard let v = renderer.view else { return }
        v.isPlaying = on
        v.rendersContinuously = on
        if on { v.preferredFramesPerSecond = 60 }
    }

    /// Tap on the 3D view: nearest body within a generous hit area. Returns false if nothing is near.
    @discardableResult
    func handleTap(at p: CGPoint) -> Bool {
        guard let id = TapPicker.pick(at: p, markers: viewer.markers, focus: viewer.focus) else { return false }
        select(id)
        return true
    }

    func noteInteraction() { interacted = true }

    // MARK: Tour

    private var optionsBeforeTour: DisplayOptions?

    func startTour(at index: Int = 0) {
        viewing = true           // hide every bar and card, like viewing mode
        showInfo = false
        touring = true
        // A clean sky for the tour: no orbit lines / trails (restored afterwards).
        optionsBeforeTour = options
        tour.start(at: index)
        options.orbits = false
        options.trails = false
        options.belt = true
        options.comets = true    // the tour visits the comets
    }

    /// A tap (or the sleep timer) ends the tour. Finished tours return to the opening view.
    func endTour(finished: Bool = false, restoreControls: Bool = true) {
        guard touring else { return }
        tour.stop()
        touring = false
        if let o = optionsBeforeTour { options = o; optionsBeforeTour = nil }
        if finished {
            applyOpeningView()
        } else {
            setRate(3_600)
            viewing = !restoreControls
        }
    }

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
        dateText = Fmt.twoLineDate(AstroTime.date(julian: st.jd))
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

    /// Settings' single "Orbits" switch: helix trails in the galactic mode, orbit ellipses in the
    /// heliocentric one.
    var orbitsShown: Bool {
        get { mode == .galactic ? options.trails : options.orbits }
        set { if mode == .galactic { options.trails = newValue } else { options.orbits = newValue } }
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
                                 trails: d.bool(forKey: "opt.trails"), moons: true,   // moons and dwarf
                                 dwarfs: true, comets: d.bool(forKey: "opt.comets"),
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
        case "immersive":
            immersiveShot = true
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
        case "settings":
            applyOpeningView()
            viewing = false
            SleepTimer.shared.minutes = 30
            showSettings = true
            return
        case "tour0", "tourjupiter", "toursaturn", "tourbelt":
            let target: [String: TourStop] = ["tour0": .body(.sun), "tourjupiter": .body(.jupiter),
                                              "toursaturn": .body(.saturn), "tourbelt": .belt]
            let i = TourStop.all.firstIndex(of: target[name]!) ?? 0
            viewer.focus = TourStop.all[i].focus; focus = viewer.focus
            viewer.distanceKm = TourStop.all[i].distanceKm
            startTour(at: i)
            return
        case "comet", "cometgal":
            // Comet Encke at its next perihelion (searched day by day), paused, tail in view.
            var best = viewer.clock.jd, bestR = Double.infinity
            for d in stride(from: 0.0, through: 1_300, by: 1) {
                let jd = viewer.clock.jd + d
                let r = length(Ephemeris.position(.encke, jd: jd))
                if r < bestR { bestR = r; best = jd }
            }
            viewer.clock.set(jd: best)
            setRate(0)
            mode = name == "cometgal" ? .galactic : .heliocentric
            options.orbits = false
            viewer.focus = name == "cometgal" ? .sun : .encke; focus = viewer.focus
            viewer.distanceKm = name == "cometgal" ? 4.0e8 : 9.0e7
            viewer.yaw = 1.2; viewer.pitch = 0.35
            viewing = true
            showInfo = false
            return
        case "infoslow", "infofast":
            // Info card for Earth at real time vs 10 years/s: the speeds must read the same.
            viewer.focus = .earth; focus = .earth
            mode = .heliocentric
            setRate(name == "infofast" ? 315_576_000 : 1)
            viewing = false
            showInfo = true
            return
        case "beltg", "belth":
            applyOpeningView()
            if name == "belth" { mode = .heliocentric }
            options.orbits = false
            viewer.distanceKm = 1.25e9; viewer.pitch = 0.6
            setRate(3_600)
            return
        case "settingshelio":
            applyOpeningView()
            viewing = false
            mode = .heliocentric
            showSettings = true
            return
        case "music":
            applyOpeningView()
            viewing = false
            let m = AmbientMusic.shared
            if let t = m.tracks.dropFirst(1).first, m.isIncluded(t) { m.toggleIncluded(t) }
            if let t = m.tracks.dropFirst(3).first { m.play(t) }
            showSettings = true
            showMusic = true
            return
        case "languagehe":
            applyOpeningView()
            viewing = false
            AppLanguage.shared.code = "he"
            showSettings = true
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
