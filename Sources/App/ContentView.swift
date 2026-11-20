import simd
import SwiftUI
import AstroCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: RemoveAdsStore

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
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.viewing)
        .statusBarHidden(model.viewing)
        .persistentSystemOverlays(model.viewing ? .hidden : .automatic)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.showPicker) { BodyPicker().environmentObject(model) }
        .sheet(isPresented: $model.showSettings) {
            SettingsView().environmentObject(model).environmentObject(store).environmentObject(SleepTimer.shared)
        }
        .fullScreenCover(isPresented: $model.showGalaxy) { GalaxyScreen().environmentObject(model) }
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
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if model.isLive {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 7, height: 7)
                        Text(L("time.live")).font(.caption2.weight(.bold)).foregroundStyle(Color.red)
                    }
                }
                Text(model.dateText).font(.footnote.monospacedDigit()).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .glass()
            Spacer(minLength: 4)
            ModeToggle()
            VStack(spacing: 8) {
                IconButton(system: "gearshape.fill", label: L("settings.title")) { model.showSettings = true }
                IconButton(system: "hurricane", label: L("galaxy.title")) { model.showGalaxy = true }
                Button { model.viewing = true } label: {
                    SaturnGlyph().frame(width: 42, height: 42)
                }
                .glass()
                .accessibilityLabel(L("view.mode"))
            }
        }
        .padding(.top, 4)
    }
}

/// Heliocentric / galactic switch as two icons (sun / helix), labelled for VoiceOver.
struct ModeToggle: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 2) {
            seg(.heliocentric, "sun.max.fill", L("frame.sun"))
            seg(.galactic, "tornado", L("frame.galaxy"))
        }
        .padding(3)
        .glass()
    }
    private func seg(_ m: FrameMode, _ icon: String, _ label: String) -> some View {
        let on = model.mode == m
        return Button { model.mode = m } label: {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 36)
                .foregroundStyle(on ? Color.black : Color.white)
                .background(on ? Color.white.opacity(0.9) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Small Saturn drawing (SF Symbols has none): planet disc with a tilted ring.
struct SaturnGlyph: View {
    var body: some View {
        ZStack {
            Ellipse().stroke(Color.white.opacity(0.9), lineWidth: 1.8)
                .frame(width: 28, height: 9).rotationEffect(.degrees(-22))
            Circle().fill(Color(red: 0.93, green: 0.82, blue: 0.6)).frame(width: 13, height: 13)
            // front half of the ring over the disc
            Ellipse().trim(from: 0, to: 0.5).stroke(Color.white.opacity(0.9), lineWidth: 1.8)
                .frame(width: 28, height: 9).rotationEffect(.degrees(-22))
        }
    }
}

struct IconButton: View {
    let system: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 17, weight: .semibold))
                .frame(width: 42, height: 42)
                .foregroundStyle(.white)
        }
        .glass()
        .accessibilityLabel(label)
    }
}

struct TimeBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Button { model.showPicker = true } label: {
                Image(systemName: "list.bullet.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 48, height: 44)
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
