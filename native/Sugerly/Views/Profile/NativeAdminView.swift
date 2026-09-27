import SwiftUI

struct NativeAdminView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var reports: [Doc] = []
    @State private var cursor: Doc?
    @State private var more = true
    @State private var loading = false
    @State private var busy = false
    @State private var error: String?
    @State private var pending: String?
    @State private var confirm = false
    private let targets = ["post": "CommunityPost", "comment": "CommunityComment", "track": "MusicReview", "message": "ChannelMessage", "reel": "Reel"]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if model.me?.isAdmin == true {
                        CandyHero(title: "Keep it kind.", subtitle: "Admin studio · review reports and protect your community.")
                        HStack { Label("\(reports.filter { $0.str("status") == "open" }.count) open in loaded reports", systemImage: "flag.fill"); Spacer() }.font(.subheadline.bold()).foregroundStyle(Theme.pink)
                        ForEach(reports, id: \.selfID) { report in
                            CandyCard(title: report.str("target_type").capitalized + " report", icon: "flag.fill") {
                                Text(report.str("reason")).font(.headline)
                                Text(report.str("target_preview")).font(.subheadline).lineLimit(6)
                                if !report.str("details").isEmpty { Text(report.str("details")).font(.footnote).foregroundStyle(.secondary) }
                                Text("By \(report.str("reporter_name")) · \(report.str("status"))").font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button("Resolve") { Task { await resolve(report) } }.buttonStyle(PrimaryButtonStyle())
                                    if targets[report.str("target_type")] != nil { Button("Remove content") { pending = report.str("id"); confirm = true }.font(.caption.bold()).foregroundStyle(.red) }
                                }.disabled(busy)
                            }
                        }
                        if more { Button(loading ? "Loading…" : "Load more reports") { Task { await load() } }.disabled(loading) }
                        if reports.isEmpty && !loading { Text("No reports. A little peace and quiet ♥").foregroundStyle(Theme.pink) }
                    } else { Text("This studio is for administrators only.") }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }.padding(18).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.background(Theme.background).navigationTitle("Admin studio").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .confirmationDialog("Permanently remove the reported content?", isPresented: $confirm, titleVisibility: .visible) { Button("Remove content", role: .destructive) { Task { await remove() } } }
                .task { await load() }
        }
    }
    private func load() async {
        guard model.me?.isAdmin == true, !loading, more else { return }
        loading = true; error = nil
        defer { loading = false }
        do { let page = try await FS.page("Report", after: cursor); let known = Set(reports.map { $0.str("id") }); reports += page.rows.filter { !known.contains($0.str("id")) }; cursor = page.rows.last ?? cursor; more = page.more }
        catch { self.error = error.localizedDescription }
    }
    private func resolve(_ report: Doc) async {
        guard model.me?.isAdmin == true, !busy else { return }
        busy = true; defer { busy = false }
        do { try await FS.update("Report", report.str("id"), ["status": "resolved", "updated_date": FS.nowISO()]); if let i = reports.firstIndex(where: { $0.str("id") == report.str("id") }) { reports[i]["status"] = "resolved" } }
        catch { self.error = error.localizedDescription }
    }
    private func remove() async {
        guard model.me?.isAdmin == true, !busy, let report = reports.first(where: { $0.str("id") == pending }), let collection = targets[report.str("target_type")], !report.str("target_id").isEmpty else { return }
        busy = true
        do {
            try await FS.delete(collection, report.str("target_id"))
            try await FS.update("Report", report.str("id"), ["status": "resolved", "updated_date": FS.nowISO()])
            if let i = reports.firstIndex(where: { $0.str("id") == report.str("id") }) { reports[i]["status"] = "resolved" }
        } catch { self.error = error.localizedDescription }
        busy = false
    }
}

private extension Dictionary where Key == String, Value == Any {
    var selfID: String { str("id") }
}
