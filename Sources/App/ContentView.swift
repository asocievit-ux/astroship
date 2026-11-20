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
            LabelsCanvas(viewer: model.viewer, showNames: model.options.labels)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                TopBar()
                if store.premiumNoticeVisible { PremiumBanner() }
                Spacer()
                if model.showInfo, let info = model.info { InfoCard(info: info) }
                TimeBar()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.showPicker) { BodyPicker().environmentObject(model) }
        .sheet(isPresented: $model.showSettings) {
            SettingsView().environmentObject(model).environmentObject(store)
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
                HStack(spacing: 6) {
                    Circle().fill(model.isLive ? Color.red : Color.gray).frame(width: 7, height: 7)
                    Text(model.isLive ? L("time.live") : L("time.simulated"))
                        .font(.caption2.weight(.bold)).foregroundStyle(model.isLive ? Color.red : Color.secondary)
                }
                Text(model.dateText).font(.footnote.monospacedDigit()).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .glass()
            Spacer(minLength: 4)
            Picker("", selection: $model.mode) {
                Text(L("frame.sun")).tag(FrameMode.heliocentric)
                Text(L("frame.galaxy")).tag(FrameMode.galactic)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 210)
            .padding(6)
            .glass()
            VStack(spacing: 8) {
                IconButton(system: "gearshape.fill", label: L("settings.title")) { model.showSettings = true }
                IconButton(system: "hurricane", label: L("galaxy.title")) { model.showGalaxy = true }
            }
        }
        .padding(.top, 4)
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
                HStack(spacing: 6) {
                    Image(systemName: "scope")
                    Text(model.focus.localizedName).lineLimit(1)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).frame(height: 44)
            }
            .foregroundStyle(.white)
            .glass()
            Spacer(minLength: 2)
            HStack(spacing: 2) {
                ctl("backward.fill", L("time.slower")) { model.slower() }
                ctl(model.paused ? "play.fill" : "pause.fill", model.paused ? L("time.play") : L("time.pause")) { model.togglePause() }
                ctl("forward.fill", L("time.faster")) { model.faster() }
                Text(SpeedSteps.label(model.rate))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 52)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.trailing, model.isLive ? 10 : 0)
                if !model.isLive {
                    Button { model.goLive() } label: {
                        Text(L("time.now")).font(.caption.weight(.bold))
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 10).frame(height: 30)
                            .background(Color.accentColor, in: Capsule())
                    }
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
