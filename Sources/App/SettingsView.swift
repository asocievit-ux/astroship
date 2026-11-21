import simd
import SwiftUI
import AstroCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: RemoveAdsStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AmbientMusic.enabledKey) private var musicOn = true
    @EnvironmentObject var sleepTimer: SleepTimer
    @EnvironmentObject var lang: AppLanguage

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $lang.code) {
                        Text(L("language.system")).tag("")
                        ForEach(AppLanguage.codes, id: \.self) { c in
                            Text(AppLanguage.nativeName(c)).environment(\.layoutDirection, .leftToRight).tag(c)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "globe").foregroundStyle(.secondary).frame(width: 22)
                            Text(L("settings.language"))
                        }
                    }
                }
                Section(L("settings.display")) {
                    Button {
                        model.startSleepMode()
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "moon.zzz").foregroundStyle(.secondary).frame(width: 22)
                            Text(L("sleep.mode"))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    NavigationLink { MusicView() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "music.note").foregroundStyle(.secondary).frame(width: 22)
                            Text(L("settings.music"))
                            Spacer()
                            if !musicOn { Text(L("sleep.off")).foregroundStyle(.secondary) }
                        }
                    }
                    Picker(selection: $sleepTimer.minutes) {
                        ForEach(SleepTimer.choices, id: \.self) { m in
                            Text(m == 0 ? L("sleep.off") : L("sleep.minutes", Fmt.number(Double(m), digits: 0))).tag(m)
                        }
                    } label: {
                        HStack(spacing: 12) {
                          Image(systemName: "timer").foregroundStyle(.secondary).frame(width: 22)
                          VStack(alignment: .leading, spacing: 2) {
                            Text(L("sleep.title"))
                            if sleepTimer.endDate != nil {
                                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                    Text(L("sleep.remaining", sleepTimer.remainingText(now: ctx.date) ?? ""))
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                          }
                        }
                    }
                    Toggle(L("settings.orbit"), isOn: $model.orbitsShown)
                    Toggle(L("settings.comets"), isOn: $model.options.comets)
                    Toggle(L("settings.belt"), isOn: $model.options.belt)
                }
                Section {
                    Text(L("settings.scaleNote")).font(.footnote).foregroundStyle(.secondary)
                }
                #if !os(visionOS)
                PurchaseSection()
                #endif
                Section(L("settings.about")) {
                    NavigationLink(L("settings.credits")) { CreditsView() }
                    if store.privacyOptionsRequired {
                        Button(L("ads.privacyOptions")) { store.presentPrivacyOptions() }
                    }
                    HStack {
                        Text(L("settings.version"))
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $model.showMusic) { MusicView() }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("common.done")) { dismiss() } } }
        }
        .task { await store.loadProduct() }
    }
}

struct PurchaseSection: View {
    @EnvironmentObject var store: RemoveAdsStore

    var body: some View {
        Section(L("ads.section")) {
            if store.adsRemoved {
                Label(L("ads.removed"), systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else {
                Text(L("ads.description")).font(.footnote).foregroundStyle(.secondary)
                Button {
                    Task { await store.purchase() }
                } label: {
                    HStack {
                        Spacer()
                        if store.purchasing { ProgressView().tint(.white) }
                        Text(store.displayPrice.map { L("ads.buyWithPrice", $0) } ?? L("ads.buy"))
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(Color.accentColor.opacity(store.purchasing || store.unavailable ? 0.5 : 1),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(store.purchasing || store.restoring || store.unavailable)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            Button {
                Task { await store.restore() }
            } label: {
                HStack {
                    Text(L("ads.restore"))
                    if store.restoring { Spacer(); ProgressView() }
                }
            }
            .disabled(store.purchasing || store.restoring)
            if let note = store.note {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct CreditsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("credits.body")).font(.footnote)
                Text("""
                Textures: Solar System Scope (www.solarsystemscope.com), CC BY 4.0.
                Milky Way panorama: ESO/S. Brunier, CC BY 4.0 (stars removed, reprojected).
                Star positions: Yale Bright Star Catalogue, 5th ed. (Hoffleit & Warren, NASA ADC / CDS V/50).
                Planet positions: JPL "Approximate Positions of the Planets" (E. M. Standish).
                Moon: ELP-2000/82 main terms (J. Meeus, Astronomical Algorithms).
                Moons, dwarf planets and comets: JPL Solar System Dynamics (Horizons, SBDB, satellite mean elements).
                Galaxy map: procedural illustration.
                """)
                .font(.footnote.monospaced())
                .environment(\.layoutDirection, .leftToRight)
            }
            .padding()
        }
        .navigationTitle(L("settings.credits"))
    }
}

/// Settings > Music: on/off, now playing with previous / play-pause / next / repeat-one, and the track
/// list. Always shuffled among included tracks; ⊖ excludes a track (dimmed, skipped), ⊕ re-includes it;
/// tapping a row plays that track.
struct MusicView: View {
    @ObservedObject private var music = AmbientMusic.shared
    @AppStorage(AmbientMusic.enabledKey) private var musicOn = true

    var body: some View {
        List {
            Section {
                Toggle(isOn: $musicOn) {
                    HStack(spacing: 12) {
                        Image(systemName: "music.note").foregroundStyle(.secondary).frame(width: 22)
                        Text(L("settings.music"))
                    }
                }
                .onChange(of: musicOn) { _, on in music.setEnabled(on) }
            }
            Section(L("music.nowPlaying")) {
                VStack(spacing: 14) {
                    VStack(spacing: 3) {
                        Text(music.current?.title ?? "—").font(.headline).multilineTextAlignment(.center)
                        Text(music.current?.artist ?? "").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    HStack(spacing: 34) {
                        controlButton("backward.end", L("music.previous")) { music.previous() }
                        controlButton(musicOn && music.isPlaying ? "pause" : "play",
                                      L(musicOn && music.isPlaying ? "music.pause" : "music.play")) {
                            if musicOn && music.isPlaying { musicOn = false }
                            else if musicOn { music.start() } else { musicOn = true }
                        }
                        controlButton("forward.end", L("music.next")) { music.next() }
                        Button { music.repeatOne.toggle() } label: {
                            Image(systemName: "repeat.1")
                                .font(.title3.weight(.light))
                                .foregroundStyle(music.repeatOne ? Color.accentColor : Color.secondary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L("music.repeatOne"))
                        .accessibilityAddTraits(music.repeatOne ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)
            }
            Section {
                ForEach(music.tracks) { t in row(t) }
            } header: {
                Text(L("music.tracks"))
            } footer: {
                Text(L("music.footer"))
            }
        }
        .navigationTitle(L("settings.music"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func controlButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title2.weight(.light)).frame(width: 36, height: 36)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }

    private func row(_ t: BGMTrack) -> some View {
        let included = music.isIncluded(t)
        let isCurrent = music.current == t
        return HStack(spacing: 12) {
            Button {
                musicOn = true
                music.play(t)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isCurrent ? (music.repeatOne ? "repeat.1" : "speaker.wave.2") : "music.note")
                        .font(.body.weight(.light))
                        .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).foregroundStyle(isCurrent ? Color.accentColor : Color.primary).lineLimit(2)
                        Text("\(t.artist) · \(t.durationText)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { music.toggleIncluded(t) } label: {
                Image(systemName: included ? "minus.circle" : "plus.circle")
                    .font(.title3.weight(.light))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
            .disabled(included && music.includedCount <= 1)
            .accessibilityLabel(L(included ? "music.exclude" : "music.include"))
        }
        .opacity(included ? 1 : 0.4)
        .accessibilityElement(children: .contain)
    }
}
