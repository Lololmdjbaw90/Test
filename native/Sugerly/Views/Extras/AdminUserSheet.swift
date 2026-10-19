import SwiftUI

// Admin → Users → a person: give or take coins, give or remove Nitro, and ban.
struct AdminUserSheet: View {
    let email: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var amount = "100"
    @State private var reason = ""
    @State private var banDays = 7
    @State private var busy = false
    @State private var confirmBan = false
    @State private var confirmDelete = false

    private var user: UserProfile? { model.person(email) }
    private var isOwner: Bool { FirebaseConfig.siteOwners.contains(model.me?.email ?? "") }
    // Owners can manage anyone but other owners; admins can manage regular people.
    private var canManage: Bool {
        guard let user, user.email != model.me?.email, !FirebaseConfig.siteOwners.contains(user.email) else { return false }
        return isOwner || user.role != "admin"
    }
    private let banOptions: [(String, Int)] = [("1 day", 1), ("7 days", 7), ("30 days", 30), ("Forever", 0)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let user {
                    VStack(alignment: .leading, spacing: 16) {
                        header(user)
                        if !canManage {
                            Label(user.email == model.me?.email ? "You can't change your own account here." : "Only the site owner can manage admins.", systemImage: "lock.fill")
                                .font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
                        }
                        coins(user).disabled(!canManage || busy).opacity(canManage ? 1 : 0.5)
                        nitro(user).disabled(!canManage || busy).opacity(canManage ? 1 : 0.5)
                        ban(user).disabled(!canManage || busy).opacity(canManage ? 1 : 0.5)
                        deleteBox(user).disabled(!canManage || busy).opacity(canManage ? 1 : 0.5)
                    }
                    .padding(16)
                }
            }
            .background(Palette.bg)
            .navigationTitle("Manage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button("Done") { dismiss() } }
                }
            }
            .confirmationDialog("Ban \(user?.displayName ?? "")?", isPresented: $confirmBan, titleVisibility: .visible) {
                Button(banDays == 0 ? "Ban forever" : "Ban for \(banDays) day\(banDays == 1 ? "" : "s")", role: .destructive) {
                    Task { await setBan(true) }
                }
            } message: {
                Text("They'll see a ban screen and can't use Sugerly until it ends or you lift it.")
            }
            .confirmationDialog("Delete \(user?.displayName ?? "this account")?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete account forever", role: .destructive) { Task { await deleteAccount() } }
            } message: {
                Text("Their login, profile, posts, reels, art, comments and messages are deleted. This can't be undone.")
            }
        }
    }

    private func header(_ u: UserProfile) -> some View {
        HStack(spacing: 12) {
            Avatar(url: u.picture, name: u.displayName, size: 58, nitro: u.isNitro)
            VStack(alignment: .leading, spacing: 3) {
                Text(u.displayName).font(.jakarta(18, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                Text(u.email).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1)
                HStack(spacing: 6) {
                    pill("\(u.coins) coins", icon: "circle.hexagongrid.fill", color: Color(hex: 0xF0A020))
                    if u.isNitro { pill("MimiPlus", icon: "sparkles", color: Color(hex: 0x8B5CF6)) }
                    if u.isBanned { pill("Banned", icon: "hand.raised.fill", color: Palette.danger) }
                }
            }
            Spacer(minLength: 0)
        }
        .sugarCard(radius: 22, padding: 12)
    }

    private func pill(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon).font(.jakarta(11, .heavy)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func box<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.jakarta(15, .heavy)).foregroundStyle(Palette.text)
            content()
        }
        .sugarCard(radius: 22, padding: 14)
    }

    private func coins(_ u: UserProfile) -> some View {
        box("Coins", icon: "circle.hexagongrid.fill") {
            HStack(spacing: 6) {
                ForEach([50, 100, 500, 1000], id: \.self) { n in
                    Chip(title: "\(n)", active: amount == "\(n)") { amount = "\(n)" }
                }
            }
            TextField("Amount", text: $amount).keyboardType(.numberPad).font(.jakarta(15, .semibold))
                .padding(.horizontal, 14).frame(height: 46)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(spacing: 8) {
                Button { Task { await changeCoins(+1) } } label: { Label("Give", systemImage: "plus.circle.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(GradientButtonStyle(height: 44))
                Button { Task { await changeCoins(-1) } } label: { Label("Take away", systemImage: "minus.circle.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(OutlineButtonStyle(height: 44, fullWidth: true))
            }
        }
    }

    private func nitro(_ u: UserProfile) -> some View {
        box("MimiPlus", icon: "sparkles") {
            if u.isNitro {
                if let until = Dates.parse(u.nitroUntil) {
                    Text("Active until \(until.formatted(date: .abbreviated, time: .omitted))").font(.jakarta(13)).foregroundStyle(Palette.muted)
                } else {
                    Text("Active").font(.jakarta(13)).foregroundStyle(Palette.muted)
                }
                Button(role: .destructive) { Task { await setNitro(days: nil) } } label: { Label("Remove MimiPlus", systemImage: "xmark.circle.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(OutlineButtonStyle(height: 44, fullWidth: true))
            } else {
                Text("No membership right now.").font(.jakarta(13)).foregroundStyle(Palette.muted)
            }
            HStack(spacing: 8) {
                Button { Task { await setNitro(days: 30) } } label: { Text(u.isNitro ? "+30 days" : "Give 30 days").frame(maxWidth: .infinity) }
                    .buttonStyle(GradientButtonStyle(height: 42))
                Button { Task { await setNitro(days: 365) } } label: { Text(u.isNitro ? "+1 year" : "Give 1 year").frame(maxWidth: .infinity) }
                    .buttonStyle(OutlineButtonStyle(height: 42, fullWidth: true))
            }
        }
    }

    private func ban(_ u: UserProfile) -> some View {
        box(u.isBanned ? "Banned" : "Ban", icon: "hand.raised.fill") {
            if u.isBanned {
                Text(AppModel.banMessage(u)).font(.jakarta(13)).foregroundStyle(Palette.text2)
                Button { Task { await setBan(false) } } label: { Label("Lift the ban", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(GradientButtonStyle(height: 44))
            } else {
                TextField("Reason (they'll see this)", text: $reason, axis: .vertical).lineLimit(1...3).font(.jakarta(15))
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack(spacing: 6) {
                    ForEach(banOptions, id: \.1) { option in
                        Chip(title: option.0, active: banDays == option.1) { banDays = option.1 }
                    }
                }
                Button(role: .destructive) { confirmBan = true } label: {
                    Label("Ban", systemImage: "hand.raised.fill").font(.jakarta(15, .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Palette.danger, in: Capsule())
                }
                .buttonStyle(BouncyStyle(scale: 0.96))
            }
        }
    }

    private func deleteBox(_ u: UserProfile) -> some View {
        box("Delete account", icon: "trash.fill") {
            Text("Removes their login and everything they posted. Use this for spam, bots or when someone asks you to.")
                .font(.jakarta(13)).foregroundStyle(Palette.text2)
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Delete account", systemImage: "trash.fill").font(.jakarta(15, .bold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.85).frame(maxWidth: .infinity).frame(height: 44)
                    .background(Palette.danger, in: Capsule())
            }
            .buttonStyle(BouncyStyle(scale: 0.96))
        }
    }

    // MARK: actions

    private func deleteAccount() async {
        guard let u = user else { return }
        busy = true
        defer { busy = false }
        do {
            let json = try await AccountServer.call("admin-delete", ["email": u.email], signedIn: true)
            let removed = json["removed"] as? Int ?? 0
            model.people.removeValue(forKey: u.email)
            Removed.shared.add(u.id)
            await model.loadPeople()
            model.showToast("\(u.displayName)'s account is deleted\(removed > 0 ? " (\(removed) things removed)" : "")", icon: "trash.fill")
            dismiss()
        } catch {
            model.showToast("Couldn't delete — \(error.localizedDescription)", error: true)
        }
    }

    private func changeCoins(_ sign: Int) async {
        guard let u = user, let n = Int(amount.filter(\.isNumber)), n > 0 else {
            model.showToast("Type how many coins", error: true)
            return
        }
        let next = max(0, u.coins + sign * n)
        await apply(u, ["coins": next], log: sign > 0 ? "coins_give" : "coins_remove", detail: "\(u.email) \(sign > 0 ? "+" : "-")\(n) → \(next)",
                    toast: sign > 0 ? "Gave \(n) coins" : "Took away \(min(n, u.coins)) coins",
                    notify: sign > 0 ? "An admin gave you \(n) coins!" : "An admin took away \(min(n, u.coins)) coins.")
    }

    private func setNitro(days: Int?) async {
        guard let u = user else { return }
        if let days {
            let base = u.isNitro ? (Dates.parse(u.nitroUntil) ?? Date()) : Date()
            let until = Dates.iso(max(base, Date()).addingTimeInterval(Double(days) * 86_400))
            await apply(u, ["nitro_active": true, "nitro_until": until], log: "nitro_give", detail: "\(u.email) +\(days)d",
                        toast: "Gave \(days == 365 ? "1 year" : "\(days) days") of MimiPlus", notify: "An admin gave you MimiPlus!")
        } else {
            await apply(u, ["nitro_active": false, "nitro_until": ""], log: "nitro_remove", detail: u.email,
                        toast: "MimiPlus removed", notify: "Your MimiPlus membership was removed by an admin.")
        }
    }

    private func setBan(_ on: Bool) async {
        guard let u = user else { return }
        if on {
            let until = banDays == 0 ? "" : Dates.iso(Date().addingTimeInterval(Double(banDays) * 86_400))
            let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            await apply(u, ["banned": true, "ban_reason": why, "banned_until": until], log: "ban",
                        detail: "\(u.email) \(banDays == 0 ? "forever" : "\(banDays)d") \(why)", toast: "\(u.displayName) is banned", notify: nil)
            reason = ""
        } else {
            await apply(u, ["banned": false, "ban_reason": "", "banned_until": ""], log: "unban", detail: u.email,
                        toast: "Ban lifted", notify: "An admin lifted your ban. Welcome back!")
        }
    }

    private func apply(_ u: UserProfile, _ fields: Doc, log: String, detail: String, toast: String, notify: String?) async {
        busy = true
        defer { busy = false }
        var update = fields
        update["updated_date"] = FS.nowISO()
        do {
            try await FS.update("User", u.id, update)
            _ = try? await FS.create("Log", ["action": log, "details": detail, "user_email": model.me?.email ?? "", "created_date": FS.nowISO()])
            if let notify, let me = model.me {
                Notify.send(to: u.email, from: me, type: "admin", message: notify, link: "/Profile?email=\(u.email)")
            }
            await model.loadPeople()
            model.showToast(toast, icon: "checkmark.seal.fill")
        } catch {
            model.showToast("Couldn't save — \(error.localizedDescription)", error: true)
        }
    }
}
