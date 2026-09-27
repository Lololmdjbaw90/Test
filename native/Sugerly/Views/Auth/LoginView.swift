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
    @FocusState private var focus: Field?

    enum Field { case name, email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 84)
                    .padding(.top, 48)
                    .accessibilityLabel("Sugerly")

                VStack(spacing: 6) {
                    Text(register ? "Join Sugerly" : "Welcome back")
                        .font(.custom("Bubbly-Regular", size: 38))
                        .contentTransition(.opacity)
                    Text(register ? "A cozy home for artists." : "Log in to pick up where you left off.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    ForEach([false, true], id: \.self) { signup in
                        Button { register = signup } label: { Text(signup ? "Sign up" : "Log in").font(.custom("CuteHereRegular", size: 22)).frame(maxWidth: .infinity).padding(13).foregroundStyle(register == signup ? .white : Theme.pink).background(register == signup ? Theme.pink : Theme.soft, in: Capsule()) }
                    }
                }

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
                }

                if register {
                    Toggle(isOn: $agreed) {
                        (Text("I agree to the ") + Text("Terms").bold() + Text(" and ") + Text("Community Guidelines").bold())
                            .font(.footnote)
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.pink)
                    HStack(spacing: 16) {
                        Button("Terms") { legal = .terms }
                        Button("Guidelines") { legal = .guidelines }
                        Button("Privacy") { legal = .privacy }
                    }
                    .font(.footnote.weight(.semibold))
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
                if let info {
                    Label(info, systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
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
                    Button("Forgot password?") { Task { await reset() } }
                        .font(.footnote.weight(.semibold))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .sensoryFeedback(.error, trigger: error)
        .sheet(item: $legal) { doc in LegalView(doc: doc) }
    }

    private func field<Content: View>(icon: String, content: Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 20)
            content
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func submit() async {
        error = nil
        info = nil
        if register && !agreed { withAnimation { error = "Please agree to the Terms and Community Guidelines to sign up." }; return }
        if register && name.trimmingCharacters(in: .whitespaces).isEmpty { withAnimation { error = "Pick a display name." }; return }
        busy = true
        defer { busy = false }
        do {
            if register {
                try await model.signUp(name: name.trimmingCharacters(in: .whitespaces), email: email, password: password)
            } else {
                try await model.signIn(email: email, password: password)
            }
        } catch {
            withAnimation { self.error = error.localizedDescription }
        }
    }

    private func reset() async {
        error = nil
        guard !email.isEmpty else { withAnimation { error = "Type your email above first." }; return }
        do {
            try await AuthClient.shared.sendPasswordReset(email: email)
            withAnimation { info = "Check your email for a link to reset your password." }
        } catch {
            withAnimation { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Terms, Privacy, Guidelines (same text as the website)

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
            ("Agreeing to these terms", "By creating an account or using Sugerly you agree to these Terms, our Privacy Policy and our Community Guidelines. If you don't agree, please don't use Sugerly."),
            ("Who can use Sugerly", "You must be at least 13 years old (or the minimum age for online services in your country, if higher). If you're under 18, you need permission from a parent or guardian. You're responsible for your account and for keeping your password safe."),
            ("Your content", "You own the art, music, reels, posts, comments and messages you share. By posting them, you give Sugerly a worldwide, non-exclusive, royalty-free licence to host, store, show and share them inside Sugerly so the service can work. This licence ends when you delete the content or your account. Only post things you have the right to share."),
            ("Zero tolerance for objectionable content and abusive users", "There is no place on Sugerly for objectionable content or abusive behaviour. You must not post or send anything that is illegal, hateful, harassing, sexually explicit, violent, or that sexualises minors; that bullies or threatens others; that is spam or a scam; or that infringes someone else's rights. You can report any post, comment, message or person, and block anyone. We review reports within 24 hours and remove content that breaks these rules and suspend or ban the accounts that posted it."),
            ("Coins, levels and rewards", "Coins, XP and levels are just for fun inside Sugerly. They have no money value and can't be sold or exchanged for money."),
            ("Ending your account", "You can delete your account at any time in Settings. We may suspend or remove accounts that break these Terms."),
            ("No warranty", "Sugerly is provided \"as is\". We work hard to keep it running and safe, but we can't promise it will always be available or error-free."),
        ]
        case .privacy: return [
            ("What we collect", "Account details you give us: email address, display name, profile picture and bio. What you create: posts, comments, messages, likes, follows and reports. We don't collect your location, contacts or advertising identifiers, and we don't track you across other apps or websites."),
            ("How we use it", "To run Sugerly: show your profile and content, deliver messages, keep the community safe and fix problems. We don't sell your personal data and we don't show ads."),
            ("Services we use", "Google Firebase (accounts, database and file storage). It processes data under its own privacy policy."),
            ("Who can see what", "Your profile, posts and comments are visible to other Sugerly users. Direct messages are visible only to the people in them (and to moderators when a message is reported)."),
            ("How long we keep it", "As long as your account exists. When you delete your account, your profile is deleted from our database."),
            ("Your rights", "You can see and edit your profile in the app and delete your account in Settings. Depending on where you live you may have more rights (for example under the GDPR)."),
            ("Children", "Sugerly isn't for children under 13 and we don't knowingly collect their data."),
        ]
        case .guidelines: return [
            ("Be kind", "Sugerly is a friendly place for artists. Give feedback kindly, celebrate each other's work, and never bully, harass or threaten anyone."),
            ("Post your own work", "Share art and music you made or have the right to share. Credit collaborators and references."),
            ("Keep it safe for everyone", "No nudity or sexual content, no gore or glorified violence, no hate speech, no self-harm encouragement, no illegal goods, and nothing that sexualises minors — ever."),
            ("No spam, scams or links", "Don't spam, sell followers, impersonate others, or post scam links. Links aren't allowed in bios."),
            ("If you see something", "Use Report on the post, comment, message or profile, and Block anyone you don't want to hear from. Our moderators review reports within 24 hours."),
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
