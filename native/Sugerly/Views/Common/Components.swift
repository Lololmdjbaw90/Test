import SwiftUI
import UIKit

enum Theme {
    static var pink: Color { Appearance.shared.color }
    static var rose: Color { pink }
    static let lavender = Color(red: 0.72, green: 0.52, blue: 0.98)
    static let blush = Color(red: 238/255, green: 143/255, blue: 174/255)
    static var gradient: LinearGradient { LinearGradient(colors: [pink, Color(hex: "EF88BD")], startPoint: .topLeading, endPoint: .bottomTrailing) }
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: 1)
        })
    }
    static let background = adaptive(0xffedf4, 0x1b101a)
    static let card = adaptive(0xffffff, 0x21171e)
    static var soft: Color { pink.opacity(0.12) }
    static let border = adaptive(0xefe4e9, 0x44323f)
}

struct NativeWordmark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shone = false
    var body: some View {
        Image("Logo").resizable().scaledToFit().frame(width: 104, height: 44)
            .overlay {
                if !reduceMotion {
                    LinearGradient(colors: [.clear, .white.opacity(0.65), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 30).rotationEffect(.degrees(18)).offset(x: shone ? 140 : -140)
                        .mask(Image("Logo").resizable().scaledToFit())
                }
            }
            .accessibilityLabel("Sugerly")
            .onAppear { if !shone { withAnimation(.easeOut(duration: 1.2).delay(0.4)) { shone = true } } }
    }
}

struct SugerlyHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR LITTLE CORNER OF THE INTERNET").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.3).foregroundStyle(Theme.pink)
            Text(title).font(.custom("Bubbly-Regular", size: 34, relativeTo: .largeTitle))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
    }
}

// Round profile picture with the person's initial as a fallback.
struct Avatar: View {
    var url: String
    var name: String
    var size: CGFloat = 40
    var online = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let link = URL(string: url), !url.isEmpty {
                    AsyncImage(url: link, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() } else { initial }
                    }
                } else {
                    initial
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())

            if online {
                Circle().fill(.green)
                    .frame(width: size * 0.28, height: size * 0.28)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }

    private var initial: some View {
        ZStack {
            Theme.gradient
            Text(String(name.first ?? "?").uppercased())
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

// Picture from the web, with a soft placeholder while it loads.
struct RemoteImage: View {
    var url: String
    var contentMode: ContentMode = .fill

    var body: some View {
        if let link = URL(string: url), !url.isEmpty {
            AsyncImage(url: link, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(contentMode: contentMode)
                case .failure: placeholder.overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                default: placeholder.overlay(ProgressView())
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View { Rectangle().fill(Color(.tertiarySystemFill)) }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduce
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.gradient, in: Capsule())
            .shadow(color: Theme.pink.opacity(0.35), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed && !reduce && Appearance.shared.motion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduce || !Appearance.shared.motion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// Report a post, comment, message or person (App Store requirement for
// apps with user content). Lands in Admin → Reports on the website.
struct ReportSheet: View {
    struct Target: Identifiable {
        var id: String
        var type: String
        var ownerEmail: String
        var preview: String
        var link: String
    }

    let target: Target
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var reason = Social.reportReasons[0]
    @State private var details = ""
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Why are you reporting this?") {
                    Picker("Reason", selection: $reason) {
                        ForEach(Social.reportReasons, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("More details (optional)") {
                    TextField("Tell us what happened", text: $details, axis: .vertical).lineLimit(3...6)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Text("Our moderators review reports within 24 hours.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "Sending…" : "Send") { Task { await send() } }.disabled(sending)
                }
            }
        }
    }

    private func send() async {
        guard let me = model.me else { return }
        sending = true
        defer { sending = false }
        let report: Doc = [
            "target_type": target.type, "target_id": target.id, "target_owner_email": target.ownerEmail,
            "target_preview": String(target.preview.prefix(280)), "link": target.link, "reason": reason,
            "details": String(details.prefix(1000)), "reporter_email": me.email, "reporter_name": me.displayName,
            "status": "open", "created_by": me.email, "created_date": FS.nowISO(), "updated_date": FS.nowISO(),
        ]
        do {
            try await FS.create("Report", report)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// Links aren't allowed in bios and captions (spam and scams).
enum Moderation {
    static func hasLink(_ text: String) -> Bool {
        let pattern = #"([a-z][a-z0-9+.-]*://|mailto:|www\.|[a-z0-9][a-z0-9.-]*\.[a-z]{2,63}\b|\b[0-9]{1,3}(\.[0-9]{1,3}){3}\b)"#
        let normalized = text.precomposedStringWithCompatibilityMapping.replacingOccurrences(of: "[\\u200B-\\u200D\\uFEFF]", with: "", options: .regularExpression)
        return normalized.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
