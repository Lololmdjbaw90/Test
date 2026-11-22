import SwiftUI
import AVFoundation
import CoreImage.CIFilterBuiltins

// More ways into your account than a password (like Roblox): a code by
// email, quick login (a new iPhone or iPad shows a QR code, a phone that's
// already logged in scans it and says yes) and backup codes. The work is
// done by Sugerly's login server (netlify/functions/account.mjs, see Backend).

enum AccountServer {
    @discardableResult
    static func call(_ action: String, _ payload: [String: Any] = [:], signedIn: Bool = false) async throws -> [String: Any] {
        var body = payload
        body["action"] = action
        return try await Backend.call("account", body, signedIn: signedIn, missing: "This isn't switched on yet — the Sugerly website needs its newest update.")
    }
}

// MARK: - Shared pieces

// The round icon, title and a line of help at the top of each sheet.
struct AccessHeader: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .background(Theme.gradient, in: Circle())
                .shadow(color: Palette.shadow, radius: 12, y: 5)
            Text(title)
                .font(.display(28, relativeTo: .title))
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
            Text(text)
                .font(.jakarta(14, .medium))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AccessField<Content: View>: View {
    let icon: String
    let content: Content

    init(icon: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.main).frame(width: 20)
            content.font(.jakarta(16, .medium))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .frostedFill(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.main.opacity(0.25), lineWidth: 1.5))
    }
}

struct AccessMessage: View {
    let text: String
    var good = false

    var body: some View {
        Label(text, systemImage: good ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.jakarta(13, .semibold))
            .foregroundStyle(good ? Palette.success : Palette.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.rise)
    }
}

// Six boxes for a code from an email. One hidden field does the typing, so
// the iPhone can fill the code in straight from Mail.
struct CodeBoxes: View {
    @Binding var code: String
    var length = 6
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Code")
                .onChange(of: code) { _, value in
                    let clean = String(value.filter(\.isNumber).prefix(length))
                    if clean != value { code = clean }
                }
            HStack(spacing: 8) {
                ForEach(0..<length, id: \.self) { i in
                    box(i)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(height: 58)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { focused = true }
    }

    private func box(_ i: Int) -> some View {
        let chars = Array(code)
        let digit = i < chars.count ? String(chars[i]) : ""
        let current = focused && i == min(chars.count, length - 1)
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(digit.isEmpty ? Palette.surface : Theme.main.opacity(0.08))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(current ? Theme.main : Theme.main.opacity(0.22), lineWidth: current ? 2 : 1.5)
            if !digit.isEmpty {
                Text(digit)
                    .font(.jakarta(24, .heavy))
                    .foregroundStyle(Theme.main)
                    .transition(.pop)
            }
        }
        .frame(width: 46, height: 56)
        .scaleEffect(current ? 1.05 : 1)
        .motion(Motion.playful, value: digit)
        .motion(Motion.standard, value: current)
    }
}

// MARK: - Email code (log in, or reset your password)

struct EmailCodeSheet: View {
    enum Purpose { case login, reset }

    let purpose: Purpose
    @State var email: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var sent = false
    @State private var code = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var info: String?
    @State private var wait = 0

    private var title: String { purpose == .login ? "Log in with a code" : "Reset your password" }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                AccessHeader(icon: purpose == .login ? "envelope.badge.fill" : "key.fill", title: title,
                             text: sent ? "We sent a 6-digit code to \(email). It works for 10 minutes."
                                        : purpose == .login ? "We'll email you a little code. No password needed."
                                                            : "We'll email you a code, then you pick a new password.")
                    .contentTransition(.opacity)
                if sent { codeStep.transition(.slideIn(from: .trailing)) } else { emailStep.transition(.slideIn(from: .leading)) }
                if let error { AccessMessage(text: error) }
                if let info { AccessMessage(text: info, good: true) }
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .sugarBackground()
        .presentationDetents([.large])
        .presentationCornerRadius(30)
        .sensoryFeedback(.error, trigger: error)
        .motion(Motion.standard, value: sent)
        .motion(Motion.standard, value: error)
        .task(id: wait > 0) {
            while wait > 0 {
                try? await Task.sleep(for: .seconds(1))
                wait -= 1
            }
        }
    }

    private var emailStep: some View {
        VStack(spacing: 14) {
            AccessField(icon: "envelope") {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit { Task { await send() } }
            }
            Button { Task { await send() } } label: {
                if busy { ProgressView().tint(.white) } else { Label("Send me a code", systemImage: "paperplane.fill") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy)
        }
    }

    private var codeStep: some View {
        VStack(spacing: 14) {
            CodeBoxes(code: $code)
            if purpose == .reset {
                AccessField(icon: "lock") {
                    SecureField("New password (6+ characters)", text: $password)
                        .textContentType(.newPassword)
                }
            }
            Button { Task { await verify() } } label: {
                if busy { ProgressView().tint(.white) } else { Text(purpose == .login ? "Log in" : "Save and log in") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy || code.count < 6)
            .opacity(code.count < 6 ? 0.6 : 1)
            HStack {
                Button("Different email") { withMotion { sent = false; code = ""; error = nil; info = nil } }
                Spacer()
                Button(wait > 0 ? "New code in \(wait)s" : "Send a new code") { Task { await send() } }
                    .disabled(wait > 0 || busy)
                    .contentTransition(.numericText())
            }
            .font(.jakarta(13, .bold))
            .foregroundStyle(Theme.main)
            Text("Can't find it? Look in Spam or Promotions too.")
                .font(.jakarta(12, .medium)).foregroundStyle(Palette.muted)
        }
        .onChange(of: code) { _, value in
            if value.count == 6 && purpose == .login { Task { await verify() } }
        }
    }

    private func send() async {
        error = nil
        info = nil
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard address.contains("@") else { withMotion { error = "Type your email first." }; return }
        busy = true
        defer { busy = false }
        do {
            let json = try await AccountServer.call("code-send", ["email": address, "purpose": purpose == .login ? "login" : "reset"])
            if json["setup"] as? Bool == false {
                await fallback(address)
                return
            }
            email = address
            code = ""
            wait = 40
            withMotion { sent = true }
        } catch let failure as APIError where failure.code == "NOT_DEPLOYED" {
            await fallback(address)
        } catch {
            withMotion { self.error = error.localizedDescription }
        }
    }

    // Codes by email aren't switched on yet: a password reset falls back to
    // the reset link email.
    private func fallback(_ address: String) async {
        guard purpose == .reset else {
            withMotion { error = "Email codes aren't switched on yet. Use Quick login, a backup code or your password." }
            return
        }
        do {
            try await AuthClient.shared.sendPasswordReset(email: address)
            withMotion { info = "We emailed you a link to reset your password. Check Spam too." }
        } catch {
            withMotion { self.error = error.localizedDescription }
        }
    }

    private func verify() async {
        guard !busy, code.count == 6 else { return }
        if purpose == .reset && password.count < 6 { withMotion { error = "Pick a new password with at least 6 characters." }; return }
        error = nil
        busy = true
        defer { busy = false }
        do {
            var payload: [String: Any] = ["email": email, "code": code]
            if purpose == .reset { payload["password"] = password }
            let json = try await AccountServer.call("code-verify", payload)
            guard let token = json["token"] as? String else { throw APIError(message: "Couldn't log in. Try again.") }
            try await model.signIn(token: token, email: json["email"] as? String ?? email)
            dismiss()
        } catch {
            code = ""
            withMotion { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Backup code

struct BackupLoginSheet: View {
    @State var email: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                AccessHeader(icon: "key.horizontal.fill", title: "Use a backup code",
                             text: "One of the codes you saved from Settings → Login & security. Each one works once.")
                AccessField(icon: "envelope") {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                AccessField(icon: "key") {
                    TextField("XXXX-XXXX", text: $code)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { Task { await logIn() } }
                }
                Button { Task { await logIn() } } label: {
                    if busy { ProgressView().tint(.white) } else { Text("Log in") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
                if let error { AccessMessage(text: error) }
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .sugarBackground()
        .presentationDetents([.large])
        .presentationCornerRadius(30)
        .sensoryFeedback(.error, trigger: error)
        .motion(Motion.standard, value: error)
    }

    private func logIn() async {
        error = nil
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard address.contains("@") else { withMotion { error = "Type your email first." }; return }
        guard code.filter({ $0.isLetter || $0.isNumber }).count == 8 else { withMotion { error = "Backup codes have 8 letters and numbers." }; return }
        busy = true
        defer { busy = false }
        do {
            let json = try await AccountServer.call("backup-login", ["email": address, "code": code])
            guard let token = json["token"] as? String else { throw APIError(message: "Couldn't log in. Try again.") }
            try await model.signIn(token: token, email: json["email"] as? String ?? address)
            if let left = json["left"] as? Int {
                model.showToast(left == 0 ? "That was your last backup code. Make new ones in Settings." : "\(left) backup code\(left == 1 ? "" : "s") left", icon: "key.fill")
            }
            dismiss()
        } catch {
            withMotion { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Quick login: the new device

struct QuickLoginSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var id = ""
    @State private var secret = ""
    @State private var code = ""
    @State private var expires = Date()
    @State private var status = "starting"
    @State private var error: String?
    @State private var clock = Date()
    @State private var round = 0

    private var left: Int { max(0, Int(expires.timeIntervalSince(clock).rounded())) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                AccessHeader(icon: "qrcode", title: "Quick login",
                             text: "On a phone where you're logged in to Sugerly, scan this with the Camera app and tap Yes. Or go to Settings → Log in another device and type the code.")
                qrCard
                statusLine
                if let error { AccessMessage(text: error) }
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 30)
        }
        .sugarBackground()
        .presentationDetents([.large])
        .presentationCornerRadius(30)
        .motion(Motion.standard, value: status)
        .sensoryFeedback(.success, trigger: status) { _, new in new == "approved" }
        .task(id: round) { await run() }
    }

    private var qrCard: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white)
                    .shadow(color: Palette.shadow, radius: 12, y: 8)
                if !code.isEmpty, let image = QRCode.image("sugerly://quick?c=\(code)") {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(20)
                        .opacity(status == "waiting" ? 1 : 0.15)
                        .id(code)
                        .transition(.blurSwap)
                } else {
                    ProgressView().tint(Theme.main)
                }
                if status == "expired" || status == "denied" {
                    Button { round += 1 } label: {
                        Label("New code", systemImage: "arrow.clockwise")
                            .font(.jakarta(15, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 42)
                            .background(Theme.gradient, in: Capsule())
                            .shadow(color: Palette.shadow, radius: 8, y: 3)
                    }
                    .buttonStyle(BouncyStyle(scale: 0.92))
                    .transition(.pop)
                }
            }
            .frame(width: 230, height: 230)
            Text(code.isEmpty ? " " : "\(code.prefix(3)) \(code.suffix(3))")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .tracking(4)
                .foregroundStyle(Theme.main)
                .contentTransition(.numericText())
                .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case "waiting":
            HStack(spacing: 8) {
                PulseDot()
                Text("Waiting for your other device · \(left / 60):\(String(format: "%02d", left % 60))")
                    .font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        case "approved":
            Label("Yes! Logging you in…", systemImage: "checkmark.circle.fill")
                .font(.jakarta(14, .bold)).foregroundStyle(Palette.success)
                .transition(.pop)
        case "denied":
            Text("The other device said no.").font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
        case "expired":
            Text("That code ran out.").font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
        default:
            Text("Making your code…").font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
        }
    }

    private func run() async {
        error = nil
        status = "starting"
        do {
            let json = try await AccountServer.call("quick-start", ["device": UIDevice.current.model])
            id = json["id"] as? String ?? ""
            secret = json["secret"] as? String ?? ""
            withMotion { code = json["code"] as? String ?? "" }
            expires = Date().addingTimeInterval(5 * 60)
            clock = Date()
            status = "waiting"
        } catch {
            withMotion { self.error = error.localizedDescription; status = "expired" }
            return
        }
        var tick = 0
        while !Task.isCancelled && status == "waiting" {
            try? await Task.sleep(for: .seconds(1))
            clock = Date()
            if left == 0 { status = "expired"; return }
            tick += 1
            guard tick % 2 == 0 else { continue }
            do {
                let json = try await AccountServer.call("quick-status", ["id": id, "secret": secret])
                let next = json["status"] as? String ?? "waiting"
                if next == "approved", let token = json["token"] as? String {
                    status = "approved"
                    try await model.signIn(token: token, email: json["email"] as? String)
                    dismiss()
                    return
                }
                if next != status { status = next }
            } catch let failure as APIError where failure.status == -1 {
                continue
            } catch {
                withMotion { self.error = error.localizedDescription; status = "expired" }
                return
            }
        }
    }
}

// A soft dot that breathes while something waits.
struct PulseDot: View {
    @State private var on = false

    var body: some View {
        Circle().fill(Theme.main)
            .frame(width: 8, height: 8)
            .scaleEffect(on ? 1.25 : 0.8)
            .opacity(on ? 1 : 0.45)
            // Scoped to the dot, so nothing around it gets carried along.
            .animation(Motion.reduced ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: on)
            .onAppear { if !Motion.reduced { on = true } }
    }
}

enum QRCode {
    // A QR code in a deep rose (dark enough for any camera to read).
    static func image(_ text: String) -> UIImage? {
        let qr = CIFilter.qrCodeGenerator()
        qr.message = Data(text.utf8)
        qr.correctionLevel = "M"
        guard let raw = qr.outputImage else { return nil }
        let tint = CIFilter.falseColor()
        tint.inputImage = raw
        tint.color0 = CIColor(red: 0.62, green: 0.13, blue: 0.36)
        tint.color1 = CIColor(red: 1, green: 1, blue: 1)
        guard let colored = tint.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = CIContext().createCGImage(colored, from: colored.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Quick login: the phone that's already logged in

struct QuickApproveSheet: View {
    // From a scanned link (the iPhone's Camera app opened Sugerly on it).
    var initialCode: String? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var code = ""
    @State private var device: String?
    @State private var busy = false
    @State private var error: String?
    @State private var done = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if done {
                    finished.transition(.pop)
                } else if let device {
                    confirm(device).transition(.slideIn(from: .trailing))
                } else {
                    scan.transition(.slideIn(from: .leading))
                }
                if let error { AccessMessage(text: error) }
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .sugarBackground()
        .presentationDetents([.large])
        .presentationCornerRadius(30)
        .motion(Motion.standard, value: device)
        .motion(Motion.standard, value: done)
        .motion(Motion.standard, value: error)
        .sensoryFeedback(.success, trigger: device) { _, new in new != nil }
        .sensoryFeedback(.success, trigger: done)
        .task {
            if let initialCode, device == nil {
                typed = initialCode
                await check(initialCode)
            }
        }
    }

    private var scan: some View {
        VStack(spacing: 16) {
            AccessHeader(icon: "qrcode.viewfinder", title: "Log in another device",
                         text: "On the new iPhone or iPad, tap Quick login on the login page. Then scan its code here, or type it.")
            QRScanner { value in
                guard !busy, device == nil, let found = Self.code(in: value) else { return }
                Task { await check(found) }
            }
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(ScanFrame().padding(40))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.main.opacity(0.3), lineWidth: 1.5))
            AccessField(icon: "keyboard") {
                TextField("Or type the code", text: $typed)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { Task { await check(typed) } }
            }
            Button { Task { await check(typed) } } label: {
                if busy { ProgressView().tint(.white) } else { Text("Next") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy || Self.clean(typed).count != 6)
            .opacity(Self.clean(typed).count != 6 ? 0.6 : 1)
        }
    }

    private func confirm(_ device: String) -> some View {
        VStack(spacing: 18) {
            AccessHeader(icon: "ipad.and.iphone", title: "Log in on this \(device)?",
                         text: "It will be logged in to your account (\(model.me?.email ?? "")).")
            VStack(alignment: .leading, spacing: 8) {
                Label("Only say yes if it's you", systemImage: "exclamationmark.shield.fill")
                    .font(.jakarta(14, .heavy)).foregroundStyle(Palette.danger)
                Text("Say yes only if you're holding that device right now. If someone sent you this code or asked you to scan it, tap Not me: they're trying to get into your account.")
                    .font(.jakarta(13, .medium)).foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button { Task { await answer(true) } } label: {
                if busy { ProgressView().tint(.white) } else { Label("Yes, log me in", systemImage: "checkmark") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy)
            Button { Task { await answer(false) } } label: {
                Text("Not me").frame(maxWidth: .infinity)
            }
            .buttonStyle(OutlineButtonStyle(height: 46, fullWidth: true))
            .disabled(busy)
        }
    }

    private var finished: some View {
        VStack(spacing: 16) {
            AccessHeader(icon: "checkmark", title: "All done!", text: "Your other device is logging in now.")
            Button("Close") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    static func clean(_ text: String) -> String {
        String(text.uppercased().filter { $0.isLetter || $0.isNumber })
    }

    static func code(in scanned: String) -> String? {
        var raw: String
        if let link = URLComponents(string: scanned), link.scheme?.lowercased() == "sugerly",
           let value = link.queryItems?.first(where: { $0.name == "c" })?.value {
            raw = value
        } else if scanned.hasPrefix("SUGERLY-QUICK:") {
            raw = String(scanned.dropFirst("SUGERLY-QUICK:".count))
        } else {
            return nil
        }
        raw = clean(raw)
        return raw.count == 6 ? raw : nil
    }

    private func check(_ text: String) async {
        let value = Self.clean(text)
        guard value.count == 6, !busy else { return }
        error = nil
        busy = true
        defer { busy = false }
        do {
            let json = try await AccountServer.call("quick-check", ["code": value], signedIn: true)
            code = value
            withMotion { device = json["device"] as? String ?? "device" }
        } catch {
            withMotion { self.error = error.localizedDescription }
        }
    }

    private func answer(_ yes: Bool) async {
        error = nil
        busy = true
        defer { busy = false }
        do {
            try await AccountServer.call("quick-approve", ["code": code, "approve": yes], signedIn: true)
            if yes {
                withMotion { done = true }
            } else {
                model.showToast("Stopped. Nobody got in.", icon: "hand.raised.fill")
                dismiss()
            }
        } catch {
            withMotion { self.error = error.localizedDescription }
        }
    }
}

// A quick-login code from a scanned link.
struct QuickLink: Identifiable {
    let code: String
    var id: String { code }
}

// Four rounded corners showing where the code goes.
struct ScanFrame: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let arm = side * 0.18
            Path { p in
                let r = CGRect(x: (geo.size.width - side) / 2, y: (geo.size.height - side) / 2, width: side, height: side)
                p.move(to: CGPoint(x: r.minX, y: r.minY + arm)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + arm, y: r.minY))
                p.move(to: CGPoint(x: r.maxX - arm, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + arm))
                p.move(to: CGPoint(x: r.maxX, y: r.maxY - arm)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - arm, y: r.maxY))
                p.move(to: CGPoint(x: r.minX + arm, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - arm))
            }
            .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.3), radius: 4)
        }
        .allowsHitTesting(false)
    }
}

// The back camera, reading QR codes.
struct QRScanner: UIViewRepresentable {
    var onCode: (String) -> Void

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: (String) -> Void
        let session = AVCaptureSession()
        private var last = ""

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard let value = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue, value != last else { return }
            last = value
            onCode(value)
        }

        func start() {
            let session = self.session
            AVCaptureDevice.requestAccess(for: .video) { granted in
                guard granted else { return }
                DispatchQueue.main.async {
                    guard session.inputs.isEmpty,
                          let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                          let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else { return }
                    session.beginConfiguration()
                    session.addInput(input)
                    let output = AVCaptureMetadataOutput()
                    if session.canAddOutput(output) {
                        session.addOutput(output)
                        output.setMetadataObjectsDelegate(self, queue: .main)
                        output.metadataObjectTypes = output.availableMetadataObjectTypes.contains(.qr) ? [.qr] : []
                    }
                    session.commitConfiguration()
                    DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.preview.videoGravity = .resizeAspectFill
        view.preview.session = context.coordinator.session
        context.coordinator.start()
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        context.coordinator.onCode = onCode
    }

    static func dismantleUIView(_ view: PreviewView, coordinator: Coordinator) {
        let session = coordinator.session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }
}

// MARK: - Backup codes (Settings)

struct BackupCodesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var left: Int?
    @State private var codes: [String] = []
    @State private var busy = false
    @State private var error: String?
    @State private var confirmNew = false

    private var allCodes: String { codes.joined(separator: "\n") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    AccessHeader(icon: "key.horizontal.fill", title: "Backup codes",
                                 text: "If you can't get into your email or forget your password, log in with one of these. Each code works once.")
                    if codes.isEmpty { status.transition(.rise) } else { list.transition(.rise) }
                    if let error { AccessMessage(text: error) }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .sugarBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.font(.jakarta(16, .bold)) }
            }
            .motion(Motion.standard, value: codes)
            .motion(Motion.standard, value: error)
            .confirmationDialog("Make new backup codes?", isPresented: $confirmNew, titleVisibility: .visible) {
                Button("Make new codes", role: .destructive) { Task { await make() } }
            } message: {
                Text("Your old codes stop working.")
            }
            .task { await load() }
        }
        .presentationCornerRadius(30)
    }

    private var status: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: (left ?? 0) > 0 ? "checkmark.shield.fill" : "shield.slash.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle((left ?? 0) > 0 ? Palette.success : Palette.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(left == nil ? "Checking…" : (left ?? 0) > 0 ? "\(left ?? 0) code\(left == 1 ? "" : "s") left" : "No backup codes yet")
                        .font(.jakarta(16, .heavy)).foregroundStyle(Palette.text)
                        .contentTransition(.numericText())
                    Text("Keep them somewhere safe, like Notes or a photo.")
                        .font(.jakarta(12, .medium)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
            }
            .sugarCard(radius: 22, padding: 14)
            Button {
                if (left ?? 0) > 0 { confirmNew = true } else { Task { await make() } }
            } label: {
                if busy { ProgressView().tint(.white) } else { Text((left ?? 0) > 0 ? "Make new codes" : "Make backup codes") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy || left == nil)
        }
    }

    private var list: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(codes.enumerated()), id: \.offset) { i, code in
                    Text(code)
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .frostedFill(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .textSelection(.enabled)
                        .transition(.pop)
                        .animation(Motion.staggered(Motion.enter, i), value: codes)
                }
            }
            .sugarCard(radius: 22, padding: 12)
            Label("You won't see these again. Save them now.", systemImage: "exclamationmark.triangle.fill")
                .font(.jakarta(13, .bold)).foregroundStyle(Color(hex: 0xD98A00))
            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = allCodes
                    model.showToast("Copied", icon: "doc.on.doc.fill")
                } label: { Label("Copy all", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }
                    .buttonStyle(OutlineButtonStyle(height: 46, fullWidth: true))
                ShareLink(item: "My Sugerly backup codes (\(model.me?.email ?? "")):\n\n\(allCodes)") {
                    Label("Save", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                }
                .buttonStyle(GradientButtonStyle(height: 46))
            }
        }
    }

    private func load() async {
        do {
            let json = try await AccountServer.call("backup-status", signedIn: true)
            withMotion { left = json["left"] as? Int ?? 0 }
        } catch {
            left = 0
            withMotion { self.error = error.localizedDescription }
        }
    }

    private func make() async {
        error = nil
        busy = true
        defer { busy = false }
        do {
            let json = try await AccountServer.call("backup-create", signedIn: true)
            let list = json["codes"] as? [String] ?? []
            withMotion { codes = list; left = list.count }
        } catch {
            withMotion { self.error = error.localizedDescription }
        }
    }
}
