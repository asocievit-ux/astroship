import simd
import SwiftUI
import AstroCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: RemoveAdsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(L("settings.display")) {
                    Toggle(L("settings.labels"), isOn: $model.options.labels)
                    Toggle(L("settings.orbits"), isOn: $model.options.orbits)
                    Toggle(L("settings.trails"), isOn: $model.options.trails)
                    Toggle(L("settings.moons"), isOn: $model.options.moons)
                    Toggle(L("settings.dwarfs"), isOn: $model.options.dwarfs)
                    Toggle(L("settings.comets"), isOn: $model.options.comets)
                    Toggle(L("settings.belt"), isOn: $model.options.belt)
                }
                Section {
                    Text(L("settings.scaleNote")).font(.footnote).foregroundStyle(.secondary)
                }
                PurchaseSection()
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
