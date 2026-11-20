import simd
import SwiftUI
import AstroCore

struct BodyPicker: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var groups: [(String, [Body])] {
        [
            (L("kind.star"), Catalog.all.filter { $0.kind == .star }),
            (L("picker.planets"), Catalog.all.filter { $0.kind == .planet }),
            (L("picker.moons"), Catalog.all.filter { $0.kind == .moon }),
            (L("picker.dwarfs"), Catalog.all.filter { $0.kind == .dwarf }),
            (L("picker.comets"), Catalog.all.filter { $0.kind == .comet }),
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1) { b in
                            Button {
                                model.select(b.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Circle().fill(Color(red: b.color.0, green: b.color.1, blue: b.color.2))
                                        .frame(width: 12, height: 12)
                                    Text(b.id.localizedName).foregroundStyle(.primary)
                                    if let p = b.parent, b.kind == .moon {
                                        Text(p.localizedName).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if b.id == model.focus { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                                }
                            }
                        }
                    }
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
}
