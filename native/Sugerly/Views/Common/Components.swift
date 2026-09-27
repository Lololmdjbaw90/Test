import SwiftUI
import UIKit


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
                .font(.jakarta(size * 0.4, .bold))
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

    private var placeholder: some View { Rectangle().fill(Palette.surface2) }
}

typealias PrimaryButtonStyle = GradientButtonStyle

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
        let pattern = #"(https?://|www\.)\S+|\b[a-z0-9-]+\.(com|net|org|io|co|gg|ly|me|app|xyz|link|shop|site)\b"#
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
