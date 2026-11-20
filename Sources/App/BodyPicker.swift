import simd
import SwiftUI
import UIKit
import AstroCore

/// Fly-to picker: the Sun and planets as a horizontal row of round thumbnails in solar-system order,
/// then dwarf planets & asteroids, moons grouped under their planet, and comets. Thumbnails are
/// rendered from the app's own textures (tools/make_thumbs.py, Solar System Scope CC BY 4.0).
struct BodyPicker: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private static let planets: [BodyID] = [.sun, .mercury, .venus, .earth, .mars, .jupiter, .saturn, .uranus, .neptune]
    private static let small: [BodyID] = [.ceres, .vesta, .pluto, .eris, .haumea, .makemake]
    private static let moonParents: [BodyID] = [.earth, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto]

    var body: some View {
        NavigationStack {
            List {
                Section(L("picker.planets")) { row(Self.planets, size: 62) }
                Section(L("picker.dwarfs")) { row(Self.small, size: 50) }
                Section(L("picker.moons")) {
                    ForEach(Self.moonParents, id: \.self) { p in
                        let moons = Catalog.all.filter { $0.kind == .moon && $0.parent == p }.map(\.id)
                        if !moons.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.localizedName).font(.caption).foregroundStyle(.secondary)
                                row(moons, size: 44, inset: false)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 0))
                        }
                    }
                }
                Section(L("picker.comets")) {
                    row(Catalog.all.filter { $0.kind == .comet }.map(\.id), size: 44)
                }
            }
            .navigationTitle(L("picker.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("common.done")) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ ids: [BodyID], size: CGFloat, inset: Bool = true) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(ids, id: \.self) { id in
                    Button {
                        model.select(id)
                        dismiss()
                    } label: {
                        VStack(spacing: 5) {
                            BodyThumb(id: id)
                                .frame(width: id == .saturn ? size * 1.5 : size, height: size)
                                .overlay(alignment: .bottomTrailing) {
                                    if id == model.focus {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14)).foregroundStyle(Color.accentColor)
                                            .background(Circle().fill(Color.black))
                                    }
                                }
                            Text(id.localizedName).font(.caption2).foregroundStyle(.primary)
                                .lineLimit(1).fixedSize()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(id.localizedName)
                }
            }
            .padding(.vertical, 6)
            .padding(.trailing, 16)
        }
        .listRowInsets(inset ? EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 0) : EdgeInsets())
    }
}

/// Round body image: a pre-rendered thumbnail when one exists, the Moon's texture tinted for other
/// rocky moons, or a softly lit disc in the body's colour.
struct BodyThumb: View {
    let id: BodyID

    private static var cache: [BodyID: UIImage] = [:]
    private static func image(_ name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Thumbs") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    var body: some View {
        let b = Catalog.body(id)
        let color = Color(red: b.color.0, green: b.color.1, blue: b.color.2)
        if let img = Self.thumb(id) {
            Image(uiImage: img).resizable().scaledToFit()
        } else if b.texture == "moon", let moon = Self.thumb(.moon) {
            Image(uiImage: moon).resizable().scaledToFit()
                .colorMultiply(color.opacity(1))
                .saturation(0.9)
        } else if b.kind == .comet {
            ZStack {
                Ellipse().fill(LinearGradient(colors: [Color.cyan.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 10).offset(x: 10).rotationEffect(.degrees(-30))
                Circle().fill(RadialGradient(colors: [.white, Color(white: 0.75), .clear], center: .center, startRadius: 0, endRadius: 9))
                    .frame(width: 18, height: 18).offset(x: -8, y: 5)
            }
        } else {
            Circle().fill(RadialGradient(colors: [color, color.opacity(0.55), Color.black.opacity(0.9)],
                                         center: UnitPoint(x: 0.3, y: 0.3), startRadius: 0, endRadius: 40))
                .padding(4)
        }
    }

    private static func thumb(_ id: BodyID) -> UIImage? {
        if let c = cache[id] { return c }
        guard let img = image(id.key) else { return nil }
        cache[id] = img
        return img
    }
}
