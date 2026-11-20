import simd
import SwiftUI
import AstroCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: RemoveAdsStore
    @EnvironmentObject var lang: AppLanguage

    var body: some View {
        ZStack {
            SolarSceneView(model: model)
                .ignoresSafeArea()
            if !model.viewing {
                VStack(spacing: 10) {
                    TopBar()
                    if store.premiumNoticeVisible { PremiumBanner() }
                    Spacer()
                    if model.showInfo, let info = model.info { InfoCard(info: info) }
                    TimeBar()
                }
                .padding(.horizontal, 22)   // keep the bars well inside the rounded screen corners
                .padding(.bottom, 12)
                .id(lang.code)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.viewing)
        #if os(iOS)
        .statusBarHidden(model.viewing)
        #endif
        .persistentSystemOverlays(model.viewing ? .hidden : .automatic)
        .background(Color.black)
        .preferredColorScheme(.dark)
        #if os(visionOS)
        .modifier(ImmersiveShotOpener())
        #endif
        .sheet(isPresented: $model.showPicker) { BodyPicker().environmentObject(model).appLanguage(lang).id(lang.code) }
        .sheet(isPresented: $model.showSettings) {
            SettingsView().environmentObject(model).environmentObject(store).environmentObject(SleepTimer.shared)
                .appLanguage(lang).id(lang.code)
        }
        .fullScreenCover(isPresented: $model.showGalaxy) {
            GalaxyScreen().environmentObject(model).appLanguage(lang).id(lang.code)
        }
    }
}

struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 0.5))
    }
}
extension View { func glass() -> some View { modifier(GlassCapsule()) } }

struct TopBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if model.isLive {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 7, height: 7)
                        Text(L("time.live")).font(.caption2.weight(.bold)).foregroundStyle(Color.red)
                    }
                }
                Text(model.dateText.isEmpty ? " \n " : model.dateText)
                    .font(.caption.monospacedDigit()).foregroundStyle(.white)
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .fixedSize()
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .glass()
            .layoutPriority(2)
            Spacer(minLength: 4)
            // All top controls in one row: mode switch (Saturn = heliocentric, helix = galactic) | tour,
            // galaxy map, settings (far right). Viewing mode moved to the bottom bar (eye).
            HStack(spacing: 2) {
                ModeToggle(embedded: true)
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 22).padding(.horizontal, 3)
                Button { model.startTour() } label: {
                    RocketGlyph().frame(width: 34, height: 34).contentShape(Rectangle())
                }
                .accessibilityLabel(L("tour.start"))
                #if os(visionOS)
                ImmersiveToggle()
                #endif
                IconButton(system: "hurricane", label: L("galaxy.title"), embedded: true) { model.showGalaxy = true }
                IconButton(system: "gearshape", label: L("settings.title"), embedded: true) { model.showSettings = true }
            }
            .padding(3)
            .glass()
            .layoutPriority(1)
        }
        .padding(.top, 6)
    }
}

/// Heliocentric / galactic switch as two icons (sun / helix), labelled for VoiceOver.
struct ModeToggle: View {
    @EnvironmentObject var model: AppModel
    var embedded = false
    var body: some View {
        let row = HStack(spacing: 2) {
            seg(.heliocentric, nil, L("frame.sun"))
            seg(.galactic, "tornado", L("frame.galaxy"))
        }
        if embedded { row } else { row.padding(3).glass() }
    }
    private func seg(_ m: FrameMode, _ icon: String?, _ label: String) -> some View {
        let on = model.mode == m
        return Button { model.mode = m } label: {
            Group {
                if let icon { Image(systemName: icon).font(.system(size: 16, weight: .regular)) }
                else { SaturnGlyph(ring: on ? Color.black : Color.white.opacity(0.9)) }
            }
                .frame(width: 36, height: 34)
                .foregroundStyle(on ? Color.black : Color.white)
                .background(on ? Color.white.opacity(0.9) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Small Saturn drawing (SF Symbols has none): planet disc with a tilted ring.
struct SaturnGlyph: View {
    var ring: Color = Color.white.opacity(0.9)
    var body: some View {
        ZStack {
            Ellipse().stroke(ring, lineWidth: 1.5)
                .frame(width: 26, height: 8).rotationEffect(.degrees(-22))
            Circle().fill(Color(red: 0.93, green: 0.82, blue: 0.6)).frame(width: 12, height: 12)
            // front half of the ring over the disc
            Ellipse().trim(from: 0, to: 0.5).stroke(ring, lineWidth: 1.5)
                .frame(width: 26, height: 8).rotationEffect(.degrees(-22))
        }
    }
}

/// Thin-line rocket for the tour button (SF Symbols has none), tilted to fly up and to the right.
struct RocketGlyph: View {
    var color: Color = .white
    var body: some View {
        Canvas { ctx, size in
            let u = min(size.width, size.height) / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.rotate(by: .degrees(45))
            ctx.translateBy(x: -12 * u, y: -12 * u)
            var body = Path()
            body.move(to: p(12, 2.5))
            body.addCurve(to: p(15.5, 12), control1: p(14.6, 4.6), control2: p(15.5, 8))
            body.addLine(to: p(15.5, 16.5)); body.addLine(to: p(8.5, 16.5)); body.addLine(to: p(8.5, 12))
            body.addCurve(to: p(12, 2.5), control1: p(8.5, 8), control2: p(9.4, 4.6))
            body.closeSubpath()
            var fins = Path()
            fins.move(to: p(8.5, 12.5)); fins.addLine(to: p(5.5, 16)); fins.addLine(to: p(5.5, 18.5)); fins.addLine(to: p(8.5, 16.5))
            fins.move(to: p(15.5, 12.5)); fins.addLine(to: p(18.5, 16)); fins.addLine(to: p(18.5, 18.5)); fins.addLine(to: p(15.5, 16.5))
            var flame = Path()
            flame.move(to: p(10.5, 18.5)); flame.addLine(to: p(10.5, 20.5))
            flame.move(to: p(12, 18.5)); flame.addLine(to: p(12, 22))
            flame.move(to: p(13.5, 18.5)); flame.addLine(to: p(13.5, 20.5))
            let style = StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
            ctx.stroke(body, with: .color(color), style: style)
            ctx.stroke(fins, with: .color(color), style: style)
            ctx.stroke(flame, with: .color(color.opacity(0.8)), style: style)
            ctx.stroke(Path(ellipseIn: CGRect(x: 10.4 * u, y: 7.6 * u, width: 3.2 * u, height: 3.2 * u)), with: .color(color), style: style)
        }
        .frame(width: 22, height: 22)
    }
}

struct IconButton: View {
    let system: String
    let label: String
    var embedded = false
    let action: () -> Void
    var body: some View {
        let b = Button(action: action) {
            Image(systemName: system).font(.system(size: 17, weight: embedded ? .regular : .semibold))
                .frame(width: embedded ? 34 : 40, height: embedded ? 34 : 40)
                .foregroundStyle(.white)
        }
        .accessibilityLabel(label)
        if embedded { b } else { b.glass() }
    }
}

struct TimeBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Button { model.showPicker = true } label: {
                Image(systemName: "list.bullet.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("bodyPickerButton")
            .accessibilityLabel(L("picker.title"))
            .accessibilityValue(model.focus.localizedName)
            .layoutPriority(2)
            .foregroundStyle(.white)
            .glass()
            Spacer(minLength: 2)
            HStack(spacing: 2) {
                ctl("backward.fill", L("time.slower")) { model.slower() }
                ctl(model.paused ? "play.fill" : "pause.fill", model.paused ? L("time.play") : L("time.pause")) { model.togglePause() }
                ctl("forward.fill", L("time.faster")) { model.faster() }
                Text(SpeedSteps.label(model.rate))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 44)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .padding(.trailing, model.isLive ? 10 : 0)
                if !model.isLive {
                    Button { model.goLive() } label: {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 15, weight: .bold))
                            .frame(width: 40, height: 30)
                            .background(Color.accentColor, in: Capsule())
                    }
                    .accessibilityLabel(L("time.now"))
                    .foregroundStyle(.white)
                    .padding(.trailing, 6)
                    .layoutPriority(1)
                }
            }
            .glass()
            Spacer(minLength: 2)
            Button { model.viewing = true } label: {
                Image(systemName: "eye")
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 44, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L("view.mode"))
            .layoutPriority(2)
            .foregroundStyle(.white)
            .glass()
        }
        .environment(\.layoutDirection, .leftToRight)   // time arrows keep their physical meaning in RTL
    }

    private func ctl(_ name: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 16, weight: .semibold)).frame(width: 38, height: 44)
        }
        .foregroundStyle(.white)
        .accessibilityLabel(label)
    }
}

struct InfoCard: View {
    @EnvironmentObject var model: AppModel
    let info: BodyInfo

    var body: some View {
        let b = Catalog.body(info.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(info.id.localizedName).font(.title3.weight(.bold))
                Text(b.kind.localizedName).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { withAnimation { model.showInfo = false } } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .accessibilityLabel(L("common.close"))
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                row(L("info.radius"), L("unit.km", Fmt.number(b.radiusKm)))
                if info.id != .sun { row(L("info.distanceSun"), Fmt.distance(km: info.distanceSunKm)) }
                if info.id != .earth {
                    row(L("info.distanceEarth"), Fmt.distance(km: info.distanceEarthKm) + "  ·  " + Fmt.lightTime(km: info.distanceEarthKm))
                }
                if let p = info.periodDays { row(L("info.period"), Fmt.duration(days: p)) }
                if info.id != .sun { row(L("info.orbitalSpeed"), L("unit.kms", Fmt.number(info.orbitalSpeed, digits: 1))) }
                row(L("info.galacticSpeed"), L("unit.kms", Fmt.number(info.galacticSpeed, digits: 1)))
            }
            .font(.footnote)
            if model.mode == .galactic {
                Text(L("info.galacticNote", Fmt.number(GalacticMotion.speed, digits: 0)))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: 520)
        .glass()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v).monospacedDigit()
        }
    }
}

struct PremiumBanner: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: RemoveAdsStore
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(.yellow)
            Text(L("ads.banner")).font(.footnote).lineLimit(2)
            Spacer()
            Button(L("ads.learnMore")) { model.showSettings = true; store.dismissPremiumNotice() }
                .font(.footnote.weight(.semibold))
            Button { store.dismissPremiumNotice() } label: { Image(systemName: "xmark") }
                .accessibilityLabel(L("common.close"))
        }
        .padding(12)
        .glass()
    }
}
