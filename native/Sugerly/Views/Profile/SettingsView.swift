import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var appearance = Appearance.shared
    @State private var customHex = ""
    @State private var legal: LegalDoc?
    @State private var confirmDelete = false
    @State private var confirmLogout = false
    @State private var deleting = false
    @State private var editing = false
    @State private var admin = false
    @State private var error: String?
    private let swatches = ["D9577F", "D52F85", "AC53C4", "7363D3", "CC653E", "23877B"]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    CandyHero(title: "Your world, your way.", subtitle: "A little more you. A little more Sugerly.")
                    CandyCard(title: "Make it yours", icon: "paintpalette.fill") {
                        Text("Choose your signature color").font(.subheadline.bold())
                        HStack {
                            ForEach(swatches, id: \.self) { hex in
                                Button { appearance.hex = hex; customHex = hex } label: {
                                    Circle().fill(Color(hex: hex)).frame(maxWidth: .infinity).frame(height: 40)
                                        .overlay { if appearance.hex == hex { Image(systemName: "checkmark").foregroundStyle(.white).bold() } }
                                }.accessibilityLabel("Accent \(hex)")
                            }
                        }
                        HStack {
                            Text("#").foregroundStyle(Theme.pink)
                            TextField("D9577F", text: $customHex).textInputAutocapitalization(.characters).autocorrectionDisabled()
                            Button("Apply") {
                                let value = customHex.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
                                guard value.count == 6, UInt32(value, radix: 16) != nil else { error = "Use a six-digit hex color, like D9577F."; return }
                                appearance.hex = value.uppercased(); error = nil
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }.font(.subheadline.bold())
                        }.padding(14).background(Theme.soft, in: RoundedRectangle(cornerRadius: 16))
                        Text("Appearance").font(.subheadline.bold())
                        HStack {
                            ForEach(["system", "light", "dark"], id: \.self) { mode in
                                Button { appearance.mode = mode } label: { Text(mode.capitalized).font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(appearance.mode == mode ? .white : Theme.pink).background(appearance.mode == mode ? Theme.pink : Theme.soft, in: Capsule()) }
                            }
                        }
                        Button { appearance.motion.toggle() } label: {
                            HStack { VStack(alignment: .leading) { Text("Playful button motion").font(.subheadline.bold()); Text("Respects your iPhone's Reduce Motion setting.").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: appearance.motion ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(Theme.pink) }
                        }.foregroundStyle(.primary).accessibilityValue(appearance.motion ? "On" : "Off")
                        Text("Colors and appearance are saved on this device.").font(.caption).foregroundStyle(.secondary)
                    }
                    DailyRewardCard()
                    CandyCard(title: "Your little corner", icon: "person.fill") {
                        Text(model.me?.email ?? "").font(.footnote).textSelection(.enabled)
                        HStack { stat("Coins", "\(model.me?.coins ?? 0)"); stat("Level", "\(model.me?.level ?? 1)"); stat("XP", "\(model.me?.xp ?? 0)") }
                        row("Edit your profile", "pencil") { editing = true }
                        if model.me?.isAdmin == true { row("Admin studio", "shield.lefthalf.filled") { admin = true } }
                    }
                    CandyCard(title: "Here to help", icon: "heart.text.square.fill") {
                        ForEach(LegalDoc.allCases) { doc in row(doc.title, "arrow.up.right") { legal = doc } }
                    }
                    CandyCard(title: "Account controls", icon: "lock.fill") {
                        row("Log out", "rectangle.portrait.and.arrow.right") { confirmLogout = true }
                        Button("Delete account") { confirmDelete = true }.foregroundStyle(.red)
                        Text("Account deletion is permanent.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    Text("made with a little extra sugar ✦").font(.custom("CuteHereRegular", size: 20)).foregroundStyle(Theme.pink)
                }.padding(18).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }.background(Theme.background).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .principal) { NativeWordmark() }; ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(item: $legal) { LegalView(doc: $0) }
                .sheet(isPresented: $editing) { EditProfileView() }
                .sheet(isPresented: $admin) { NativeAdminView() }
                .confirmationDialog("Delete your account permanently?", isPresented: $confirmDelete, titleVisibility: .visible) { Button("Delete account", role: .destructive) { Task { await deleteAccount() } } }
                .confirmationDialog("Log out of Sugerly?", isPresented: $confirmLogout, titleVisibility: .visible) { Button("Log out") { model.signOut() } }
                .disabled(deleting).onAppear { customHex = appearance.hex }
                .buttonStyle(CandyButtonStyle())
        }
    }
    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) { Text(value).font(.title3.bold()).foregroundStyle(Theme.pink); Text(label).font(.caption) }.frame(maxWidth: .infinity).padding(12).background(Theme.soft, in: RoundedRectangle(cornerRadius: 18))
    }
    private func row(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { Text(title); Spacer(); Image(systemName: icon).foregroundStyle(Theme.pink) }.font(.subheadline.bold()).padding(.vertical, 8) }.foregroundStyle(.primary)
    }
    private func deleteAccount() async {
        deleting = true
        defer { deleting = false }
        do { try await model.deleteAccount() } catch { self.error = error.localizedDescription }
    }
}
