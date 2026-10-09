import SwiftUI
import UIKit

// Invite friends: everyone has an invite code, and when someone new signs up
// with it the inviter gets 400 coins (collected next time they open the app).
// A Referral record per new account (its id is the new person's uid, so each
// account can only ever count once).
@MainActor
enum Referrals {
    static let reward = 400
    private static var claiming = false

    static func code(for uid: String) -> String {
        String(uid.filter { $0.isLetter || $0.isNumber }.prefix(8)).uppercased()
    }

    static func shareText(_ code: String) -> String {
        "Come draw with me on Sugerly! Sign up with my invite code \(code) and we both get treats: \(Servers.site)/Login?ref=\(code)"
    }

    // Saves your code on your account so others can find you by it.
    static func ensureCode(_ model: AppModel) async {
        guard let me = model.me, me.inviteCode.isEmpty else { return }
        try? await model.updateMe(["invite_code": code(for: me.id)])
    }

    // A new account: link it to whoever invited you.
    static func redeem(_ raw: String, model: AppModel) async {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count >= 6, let me = model.me, let uid = AuthClient.shared.uid else { return }
        guard let inviter = (try? await FS.query("User", [.equals("invite_code", code)], limit: 1))?.first else {
            model.showToast("That invite code wasn't found, but you're in!", icon: "questionmark.circle")
            return
        }
        let inviterEmail = inviter.str("email").lowercased()
        guard !inviterEmail.isEmpty, inviterEmail != me.email else { return }
        do {
            _ = try await FS.create("Referral", [
                "inviter_email": inviterEmail, "inviter_uid": inviter.str("id"), "invitee_email": me.email,
                "invitee_uid": uid, "invitee_name": me.displayName, "code": code, "claimed": false,
            ], id: uid)
            Notify.send(to: inviterEmail, from: me, type: "invite",
                        message: "\(me.displayName) joined Sugerly with your invite! Open the app to collect \(reward) coins.", link: "/Profile")
            let name = inviter.str("display_name")
            model.showToast("Invite linked\(name.isEmpty ? "" : ": \(name) gets \(reward) coins")", icon: "gift.fill")
        } catch {
            // Already linked, or offline: nothing to do.
        }
    }

    // Collects 400 coins for each friend who joined with your code.
    static func claim(_ model: AppModel) async {
        guard let me = model.me, !claiming else { return }
        claiming = true
        defer { claiming = false }
        guard let rows = try? await FS.query("Referral", [.equals("inviter_email", me.email), .equals("claimed", false)], limit: 20),
              !rows.isEmpty else { return }
        var count = 0
        for row in rows {
            do {
                try await FS.update("Referral", row.str("id"), ["claimed": true, "claimed_date": FS.nowISO()])
                count += 1
            } catch {}
        }
        guard count > 0 else { return }
        try? await model.addToMe(["coins": count * reward, "invites_joined": count])
        model.showToast(count == 1 ? "A friend joined with your invite: +\(reward) coins!" : "\(count) friends joined with your invite: +\(count * reward) coins!", icon: "gift.fill")
    }
}

// "Invite friends, get 400 coins each": your code, copy and share.
struct InviteCard: View {
    @Environment(AppModel.self) private var model
    var compact = false
    @State private var copied = false

    private var code: String {
        guard let me = model.me else { return "" }
        return me.inviteCode.isEmpty ? Referrals.code(for: me.id) : me.inviteCode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite friends").font(.display(20)).foregroundStyle(Palette.text)
                    Text("Get \(Referrals.reward) coins for every friend who joins with your code.")
                        .font(.jakarta(12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Text(code)
                    .font(.system(size: 20, weight: .heavy, design: .monospaced)).tracking(3)
                    .foregroundStyle(Theme.main)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(Theme.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.main.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                Button {
                    UIPasteboard.general.string = code
                    withMotion(Motion.standard) { copied = true }
                    Task { try? await Task.sleep(for: .seconds(1.6)); withMotion(Motion.standard) { copied = false } }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 15, weight: .bold))
                        .frame(width: 46, height: 46)
                        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(BouncyStyle())
                .accessibilityLabel("Copy code")
                ShareLink(item: Referrals.shareText(code)) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityLabel("Share invite")
            }
            if !compact, let me = model.me, me.invitesJoined > 0 {
                Label("\(me.invitesJoined) friend\(me.invitesJoined == 1 ? "" : "s") joined · \(me.invitesJoined * Referrals.reward) coins earned", systemImage: "person.2.fill")
                    .font(.jakarta(12, .bold)).foregroundStyle(Theme.main)
            }
        }
        .sugarCard(radius: 24, padding: 14)
    }
}
