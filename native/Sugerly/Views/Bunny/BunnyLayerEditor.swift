import SwiftUI

struct BunnyLayerEditor: View {
    @Binding var look: BunnyLook
    let slot: BunnySlot
    @Environment(\.dismiss) private var dismiss
    @State private var selected = ""

    private var layers: [BunnyClothingLayer] { look.layers(slot) }
    private var index: Int? { layers.firstIndex { $0.id == selected } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                BunnyPortrait(look: look, animated: false).frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 24)).padding(.horizontal)
                ScrollView {
                    VStack(spacing: 16) {
                        Text("Tap a layer to move it. The last layer sits in front.")
                            .font(.jakarta(13, .medium)).foregroundStyle(Palette.text2)
                        ForEach(layers) { layer in
                            Button { selected = layer.id } label: {
                                HStack {
                                    Image(systemName: selected == layer.id ? "checkmark.circle.fill" : "circle")
                                    Text(name(layer.id)).lineLimit(1)
                                    Spacer()
                                    Text("\((layers.firstIndex { $0.id == layer.id } ?? 0) + 1)")
                                }.font(.jakarta(15, .bold)).padding(12).frame(minHeight: 44)
                                    .background(selected == layer.id ? Theme.soft : Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                        }
                        if let index {
                            adjustment("Left / right", value: value(\.x), range: -0.4...0.4)
                            adjustment("Up / down", value: value(\.y), range: -0.4...0.4)
                            adjustment("Rotation", value: value(\.rotation), range: -180...180)
                            HStack {
                                Button { move(-1) } label: { Label("Back", systemImage: "square.2.layers.3d.bottom.filled") }
                                    .disabled(index == 0)
                                Spacer()
                                Button { move(1) } label: { Label("Front", systemImage: "square.2.layers.3d.top.filled") }
                                    .disabled(index == layers.count - 1)
                            }.buttonStyle(OutlineButtonStyle()).frame(minHeight: 44)
                            HStack {
                                Button("Reset position") {
                                    var next = layers; next[index] = .init(id: selected); look.setLayers(next, slot)
                                }
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    look.setLayers(layers.filter { $0.id != selected }, slot)
                                    selected = layers.first?.id ?? ""
                                }
                            }.font(.jakarta(14, .bold)).frame(minHeight: 44)
                        }
                    }.padding(18)
                }
            }
            .sugarBackground()
            .navigationTitle("Arrange \(slot.label.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { selected = layers.first?.id ?? "" }
    }

    private func name(_ id: String) -> String {
        if id == "classic:bow" { return "Bow" }
        if id.hasPrefix("classic:"), let top = BunnyTop(rawValue: String(id.dropFirst(8))) { return top.label }
        return BunnyCatalog.shared.item(id)?.name ?? "Item"
    }

    private func value(_ key: WritableKeyPath<BunnyClothingLayer, Double>) -> Binding<Double> {
        Binding(get: { index.map { layers[$0][keyPath: key] } ?? 0 }, set: { number in
            guard let index else { return }
            var next = layers; next[index][keyPath: key] = number; look.setLayers(next, slot)
        })
    }

    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.jakarta(13, .bold))
            Slider(value: value, in: range).tint(Theme.main).frame(minHeight: 44).accessibilityLabel(title)
        }
    }

    private func move(_ delta: Int) {
        guard let index, layers.indices.contains(index + delta) else { return }
        var next = layers; next.swapAt(index, index + delta); look.setLayers(next, slot)
    }
}

struct BunnyItemEditView: View {
    let item: BunnyItem
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var price = "0"
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Item name").font(.jakarta(14, .bold))
                    SugarField(placeholder: "Name", text: $name)
                    Text("Price in coins · 0 is free").font(.jakarta(14, .bold))
                    TextField("0", text: $price).keyboardType(.numberPad)
                        .padding(16).frostedFill(in: RoundedRectangle(cornerRadius: 16))
                    Text("People who already bought it keep their purchase when you change its name or price.")
                        .font(.jakarta(13, .medium)).foregroundStyle(Palette.text2)
                    Button { Task { await save() } } label: { Text(busy ? "Saving…" : "Save item") }
                        .buttonStyle(GradientButtonStyle(height: 50)).disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(20)
            }.sugarBackground().navigationTitle("Edit item").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.onAppear { name = item.name; price = String(item.price) }
    }

    private func save() async {
        guard let amount = Int(price), (0...1000000).contains(amount) else {
            model.showToast("Enter a price from 0 to 1,000,000 coins.", error: true); return
        }
        busy = true
        defer { busy = false }
        do {
            try await BunnyCatalog.shared.edit(item, name: name, price: amount)
            model.showToast("Item updated", icon: "checkmark.circle.fill")
            dismiss()
        } catch { model.showToast(error.localizedDescription, error: true) }
    }
}
