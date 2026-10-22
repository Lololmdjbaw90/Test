import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var register = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var agreed = false
    @State private var busy = false
    @State private var error: String?
    @State private var info: String?
    @State private var legal: LegalDoc?
    @State private var invite = ""
    @State private var access: Access?
    @State private var showWays = false
    @State private var appeared = false
    @FocusState private var focus: Field?

    enum Field { case name, email, password }

    // The other ways in (see AccountAccess.swift).
    enum Access: String, Identifiable {
        case code, reset, quick, backup
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                // The badge pops in, then everything else rises after it.
                AppBadge(size: 104)
                    .budgetShadow(color: Theme.glow(0.25), radius: 16, y: 8)
                    .padding(.top, 40)
                    .scaleEffect(appeared || Motion.reduced ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                    .animation(Motion.reduced ? nil : Motion.playful, value: appeared)
                BrandLogo(height: 64)
                    .budgetShadow(color: Palette.shadow, radius: 12)
                    .padding(.top, -8)
                    .accessibilityLabel("Sugerly")
                    .stagger(appeared, 1)

                VStack(spacing: 6) {
                    Text(register ? "Join Sugerly" : "Welcome back")
                        .font(.display(38, relativeTo: .largeTitle))
                        .foregroundStyle(Theme.gradient)
                        .contentTransition(.opacity)
                    Text(register ? "A cozy home for artists." : "Log in to pick up where you left off.")
                        .font(.jakarta(15, .medium))
                        .foregroundStyle(Palette.text2)
                }
                .stagger(appeared, 2)

                HStack(spacing: 10) {
                    Chip(title: "Log in", icon: "heart.fill", active: !register) { withMotion(Motion.standard) { register = false } }
                    Chip(title: "Sign up", icon: "sparkles", active: register) { withMotion(Motion.standard) { register = true } }
                }
                .stagger(appeared, 3)

                VStack(spacing: 12) {
                    if register {
                        field(icon: "person", content: TextField("Display name", text: $name)
                            .textContentType(.nickname)
                            .focused($focus, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focus = .email })
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    field(icon: "envelope", content: TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password })
                    field(icon: "lock", content: SecureField("Password", text: $password)
                        .textContentType(register ? .newPassword : .password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } })
                    if register {
                        field(icon: "gift", content: TextField("Invite code (optional)", text: $invite)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled())
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                if register {
                    Toggle(isOn: $agreed) {
                        (Text("I'm at least 13 and I agree to the ") + Text("Terms").bold() + Text(" and ") + Text("Community Guidelines").bold() + Text(", and I've read the ") + Text("Privacy Policy").bold())
                            .font(.jakarta(13))
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.pink)
                    HStack(spacing: 16) {
                        Button("Terms") { legal = .terms }
                        Button("Guidelines") { legal = .guidelines }
                        Button("Privacy") { legal = .privacy }
                    }
                    .font(.jakarta(13, .bold))
                    .foregroundStyle(Theme.main)
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.jakarta(13, .semibold))
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
                if let info {
                    Label(info, systemImage: "checkmark.circle.fill")
                        .font(.jakarta(13, .semibold))
                        .foregroundStyle(Palette.success)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await submit() }
                } label: {
                    if busy { ProgressView().tint(.white) } else { Text(register ? "Create account" : "Log in") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)

                if !register {
                    Button("Forgot password?") { access = .reset }
                        .font(.jakarta(13, .bold))
                        .foregroundStyle(Theme.main)
                    otherWays
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .sugarBackground()
        .onAppear { appeared = true }
        .sensoryFeedback(.error, trigger: error)
        .sheet(item: $legal) { doc in LegalView(doc: doc) }
        .sheet(item: $access) { way in
            switch way {
            case .code: EmailCodeSheet(purpose: .login, email: email)
            case .reset: EmailCodeSheet(purpose: .reset, email: email)
            case .quick: QuickLoginSheet()
            case .backup: BackupLoginSheet(email: email)
            }
        }
        .onAppear {
            guard !showWays else { return }
            withAnimation(Motion.pick(Motion.enter).delay(0.15)) { showWays = true }
        }
    }

    // Email code, quick login and backup codes, as three soft tiles.
    private var otherWays: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Capsule().fill(Theme.main.opacity(0.18)).frame(height: 1.5)
                Text("or log in with").font(.jakarta(12, .bold)).foregroundStyle(Palette.muted).fixedSize()
                Capsule().fill(Theme.main.opacity(0.18)).frame(height: 1.5)
            }
            HStack(spacing: 10) {
                wayTile("Email code", icon: "envelope.badge.fill", index: 0) { access = .code }
                wayTile("Quick login", icon: "qrcode", index: 1) { access = .quick }
                wayTile("Backup code", icon: "key.horizontal.fill", index: 2) { access = .backup }
            }
        }
        .padding(.top, 6)
    }

    private func wayTile(_ title: String, icon: String, index: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Theme.gradient, in: Circle())
                Text(title)
                    .font(.jakarta(12, .heavy))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.main.opacity(0.18), lineWidth: 1.5))
        }
        .buttonStyle(BouncyStyle(scale: 0.94))
        .opacity(showWays ? 1 : 0)
        .offset(y: showWays || Motion.reduced ? 0 : 14)
        .animation(Motion.staggered(Motion.enter, index).delay(0.15), value: showWays)
    }

    private func field<Content: View>(icon: String, content: Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.main).frame(width: 20)
            content.font(.jakarta(16, .medium))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.main.opacity(0.25), lineWidth: 1.5))
        .budgetShadow(color: Palette.shadow, radius: 12, y: 4)
    }

    private func submit() async {
        error = nil
        info = nil
        if register && !agreed { withMotion { error = "Please agree to the Terms and Community Guidelines to sign up." }; return }
        if register && name.trimmingCharacters(in: .whitespaces).isEmpty { withMotion { error = "Pick a display name." }; return }
        if register {
            let check = ModEngine.analyze(name, kind: .name)
            if check.blocked { withMotion { error = check.reason }; return }
        }
        busy = true
        defer { busy = false }
        do {
            if register {
                try await model.signUp(name: name.trimmingCharacters(in: .whitespaces), email: email, password: password)
                if !invite.trimmingCharacters(in: .whitespaces).isEmpty { await Referrals.redeem(invite, model: model) }
            } else {
                try await model.signIn(email: email, password: password)
            }
        } catch {
            withMotion { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Terms, Privacy, Guidelines (same text as the website, src/pages/Legal.jsx)

enum LegalDoc: String, Identifiable, CaseIterable {
    case terms, privacy, guidelines
    var id: String { rawValue }
    var title: String {
        switch self {
        case .terms: return "Terms of Use"
        case .privacy: return "Privacy Policy"
        case .guidelines: return "Community Guidelines"
        }
    }
    var sections: [(String, String)] {
        switch self {
        case .terms: return [
            ("Agreeing to these terms", "By creating an account or using Sugerly (the app and the website) you agree to these Terms, our Privacy Policy and our Community Guidelines. If you don't agree, please don't use Sugerly."),
            ("Who can use Sugerly", "You must be at least 13 years old (or the minimum age for online services in your country, if higher). If you're under 18, you need permission from a parent or guardian, and a parent must agree before you buy a commission. You're responsible for your account and for keeping your password safe."),
            ("Your content", "You own the art, music, reels, posts, comments and messages you share. By posting them, you give Sugerly a worldwide, non-exclusive, royalty-free licence to host, store, show and share them inside Sugerly so the service can work (for example to show your reel in the feed). This licence ends when you delete the content or your account, except for copies other people already shared with you or that we must keep by law. Only post things you have the right to share."),
            ("Zero tolerance for objectionable content and abusive users", "There is no place on Sugerly for objectionable content or abusive behaviour. You must not post or send anything that is illegal, hateful, harassing, sexually explicit, violent, or that sexualises minors; that bullies or threatens others; that is spam or a scam; or that infringes someone else's rights. You can report any post, reel, comment, message or person, and block anyone. We review reports within 24 hours and will remove content that breaks these rules and suspend or ban the accounts that posted it."),
            ("Safety tools", "Every post, reel, comment, message and profile has Report, and you can Block people from their profile. Blocked people can't message you, call you or see your posts. Captions, comments and messages are checked automatically for harmful words, and unclear cases can get a second check by AI (see the Privacy Policy)."),
            ("Commissions", "Artists can offer commissions: custom art made on request. The deal is between the buyer and the artist. The artist agrees to make what was described at the agreed price, and the buyer pays through Sugerly. Card payments are processed by Stripe; Sugerly never sees your full card number. Sugerly keeps a small service fee (shown to artists in their shop) and pays the rest to the artist after the buyer approves the finished art. Artists keep the copyright of their art; the buyer gets a personal, non-commercial licence to use what they commissioned unless the artist agrees otherwise. Artists are responsible for their own taxes. Never agree to pay outside Sugerly: we can't protect those payments."),
            ("Cancellations and refunds", "You can cancel for free before you pay. After paying, you can ask for a refund until you approve the art; our team looks at every request and refunds the full amount to your card when the artist didn't deliver what was agreed. Because commissions are made to your personal request, the 14-day right of withdrawal doesn't apply once the artist has started, where the law allows this. This doesn't affect your other rights as a consumer."),
            ("Music, GIFs and AI", "Song previews come from Deezer and GIFs from GIPHY. If you connect Apple Music, whole songs play through your own Apple Music subscription. All of these belong to their owners and are only played inside Sugerly. Where offered, \"Write with AI\" uses Google's Gemini (through Firebase) to suggest captions from your picture; suggestions can be wrong, so check them before posting."),
            ("Coins, levels, rewards and MimiPlus", "Coins, XP, levels and MimiPlus are just for fun inside Sugerly. Coins are earned (daily rewards, invites, posting) and can't be bought, sold or exchanged for money, and MimiPlus is unlocked with coins only. They may change."),
            ("Ending your account", "You can delete your account at any time in Settings. We may suspend or remove accounts that break these Terms. Open commissions are cancelled or refunded as described above."),
            ("No warranty", "Sugerly is provided \"as is\". We work hard to keep it running and safe, but we can't promise it will always be available or error-free. To the extent the law allows, we aren't liable for indirect or consequential losses. Nothing in these Terms limits rights you have by law as a consumer."),
            ("Apple", "If you use the iPhone or iPad app, these Terms are between you and Sugerly, not Apple. Apple isn't responsible for the app, its content, support or any claims about it, and Apple and its subsidiaries may enforce these Terms as third-party beneficiaries."),
            ("Changes", "We may update these Terms. If the changes are important we'll tell you in the app (What's new). Using Sugerly after that means you accept the new Terms."),
            ("Contact", "Questions or requests? Email sugerlysupport@gmail.com, or use the Help & support chat in the app (Settings → Help & legal, or Help & support in the menu) or on the Help page of the website. We usually reply within 2 days."),
        ]
        case .privacy: return [
            ("What we collect", "Account details you give us: email address, display name, profile picture, banner and bio. What you create: artworks, posts, reels, music, comments, messages, likes, follows and reports. If you use commissions: your orders, prices and payment status (card details go straight to Stripe; we never see or store your full card number). Artists can add a PayPal email for payouts, which only admins can see. We don't collect your location, contacts or advertising identifiers, and we don't track you across other apps or websites."),
            ("Camera, microphone and face filters", "Camera and microphone are used only while you record a reel, take a photo, send a voice note or join a call. Face filters find your face on your device to place the effect; no face data is stored or sent anywhere."),
            ("On your device only", "What you watch in Reels (watch time, skips) is used to personalise your feed and stays on your device. Your theme, sounds and haptics settings are also stored on your device."),
            ("How we use it", "To run Sugerly: show your profile and content, deliver messages and notifications, recommend posts and reels, handle commissions and payouts, keep the community safe (moderation, reports, blocking) and fix problems. We don't sell your personal data and we don't show ads."),
            ("Safety checks with AI", "What you write is first checked on your device. If a caption, comment or message looks unclear, only its text (not your name or email) may be sent to Google's Gemini through Firebase AI Logic for a second opinion on whether it breaks the rules."),
            ("Services we use", "Google Firebase (accounts, database, file storage and hosting); Google Gemini through Firebase AI Logic (the safety checks above, and \"Write with AI\" when you tap it: the picture and your draft are sent to suggest captions); Stripe (card payments); PayPal (artist payouts); Apple Music (only if you connect it: Apple handles your subscription and we don't get your Apple ID); GIPHY (GIF search); Deezer (song previews); and, for calls, direct peer-to-peer connections between the people in the call. Each processes data under its own privacy policy. Some are based in the United States and protect transfers with the safeguards the law requires, such as standard contractual clauses."),
            ("Why we can use it (EU and UK)", "To provide Sugerly under our Terms (contract); to keep it safe and prevent abuse and fraud (legitimate interests); with your permission for camera, microphone, photos and Apple Music, which you can withdraw any time in iOS Settings (consent); and to keep payment records (legal obligation)."),
            ("Who can see what", "Your profile, posts, reels, artworks and comments are visible to other Sugerly users. Direct messages and group chats are visible only to the people in them (and to moderators when a message is reported). Commission orders are visible to the buyer, the artist and admins. Admins can see content and reports to keep Sugerly safe."),
            ("How long we keep it", "As long as your account exists. When you delete your account, your profile and content are deleted from our database; backups are cleared within 30 days. Payment records are kept as long as tax and accounting laws require, and reports may be kept longer when needed for safety or the law."),
            ("Your rights", "You can see and edit your profile in Settings and delete your account there; on the website you can also download a copy of your data (Settings → Account & data). Depending on where you live (for example the EU/UK under the GDPR, or California) you may also have rights to access, correct, delete or move your data and to object to processing, and you can complain to your data protection authority. Contact us to use them."),
            ("Children", "Sugerly isn't for children under 13 and we don't knowingly collect their data. If you believe a child under 13 has an account, contact us and we'll delete it."),
            ("Security", "Data is sent over encrypted connections and protected by Firebase security rules that only let people read and change what they're allowed to. Only our payment server can mark an order as paid."),
            ("Changes", "We'll tell you in the app if this policy changes in an important way."),
            ("Contact", "Questions or requests? Email sugerlysupport@gmail.com, or use the Help & support chat in the app (Settings → Help & legal, or Help & support in the menu) or on the Help page of the website. We usually reply within 2 days."),
        ]
        case .guidelines: return [
            ("Be kind", "Sugerly is a friendly place for artists. Give feedback kindly, celebrate each other's work, and never bully, harass or threaten anyone."),
            ("Post your own work", "Share art, music and reels you made or have the right to share. Credit collaborators and references. Don't trace or repost other people's work as your own."),
            ("Keep it safe for everyone", "No nudity or sexual content, no gore or glorified violence, no hate speech, no self-harm encouragement, no illegal goods, and nothing that sexualises minors — ever."),
            ("No spam, scams or links", "Don't spam, sell followers, impersonate others, or post scam links. Links aren't allowed in reel captions or bios."),
            ("Fair commissions", "Only offer what you can make, be honest about prices and timing, deliver your own work, and keep all payments inside Sugerly."),
            ("Protect privacy", "Don't share other people's personal information (addresses, phone numbers, private photos) without permission."),
            ("If you see something", "Use Report on the post, reel, comment, message or profile, and Block anyone you don't want to hear from. Our moderators review reports within 24 hours and remove content and accounts that break these rules."),
        ]
        }
    }
}

struct LegalView: View {
    let doc: LegalDoc
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(doc.sections.enumerated()), id: \.offset) { _, section in
                    Section(section.0) {
                        Text(section.1).font(.callout).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(doc.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

