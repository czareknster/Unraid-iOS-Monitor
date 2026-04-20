import SwiftUI

struct UnraidNotificationItem: Decodable, Identifiable {
    let id: String
    let title: String?
    let subject: String?
    let description: String?
    let importance: String   // "INFO" | "WARNING" | "ALERT"
    let timestamp: String?
    let formattedTimestamp: String?
}

struct NotificationsListResponse: Decodable {
    let list: [UnraidNotificationItem]
}

struct NotificationsListView: View {
    @EnvironmentObject var settings: Settings

    @State private var items: [UnraidNotificationItem] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var filter: Filter = .unread

    enum Filter: String, CaseIterable, Identifiable {
        case unread = "UNREAD"
        case archive = "ARCHIVE"
        var id: String { rawValue }
        var label: String { self == .unread ? "Unread" : "Archive" }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            content
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if filter == .unread && !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await archiveAll() }
                    } label: {
                        Text("Archive all")
                    }
                    .disabled(loading)
                }
            }
        }
        .task(id: filter) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if loading && items.isEmpty {
            Spacer()
            ProgressView()
            Spacer()
        } else if let err = errorMessage {
            ContentUnavailableView("Failed to load", systemImage: "exclamationmark.triangle", description: Text(err))
        } else if items.isEmpty {
            ContentUnavailableView("No notifications", systemImage: "bell.slash")
        } else {
            List(items) { item in
                row(item)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if filter == .unread {
                            Button {
                                Task { await archive(item) }
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.blue)
                        } else {
                            Button {
                                Task { await unarchive(item) }
                            } label: {
                                Label("Unarchive", systemImage: "tray.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                    }
            }
            .listStyle(.plain)
            .refreshable { await load() }
        }
    }

    @ViewBuilder
    private func row(_ item: UnraidNotificationItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: item.importance))
                .foregroundStyle(color(for: item.importance))
                .font(.title3)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.subject ?? item.title ?? "Notification")
                        .font(.subheadline).bold()
                        .lineLimit(2)
                    Spacer()
                    if let ts = item.formattedTimestamp {
                        Text(shortDate(ts))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let body = item.description, !body.isEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func icon(for importance: String) -> String {
        switch importance {
        case "ALERT": return "exclamationmark.octagon.fill"
        case "WARNING": return "exclamationmark.triangle.fill"
        default: return "info.circle.fill"
        }
    }

    private func color(for importance: String) -> Color {
        switch importance {
        case "ALERT": return .red
        case "WARNING": return .orange
        default: return .blue
        }
    }

    private func shortDate(_ formatted: String) -> String {
        // Backend gives e.g. "Sunday, 19-04-2026 14:57". Keep last 5 chars for "HH:mm" if long.
        if formatted.count > 18, let range = formatted.range(of: ", ") {
            return String(formatted[range.upperBound...])
        }
        return formatted
    }

    private func archive(_ item: UnraidNotificationItem) async {
        // Optimistic removal so the list animates before the request finishes.
        let keptItems = items.filter { $0.id != item.id }
        withAnimation { items = keptItems }
        await postAction(path: "/api/notifications/\(percentEncode(item.id))/archive")
    }

    private func unarchive(_ item: UnraidNotificationItem) async {
        let keptItems = items.filter { $0.id != item.id }
        withAnimation { items = keptItems }
        await postAction(path: "/api/notifications/\(percentEncode(item.id))/unarchive")
    }

    private func archiveAll() async {
        withAnimation { items = [] }
        await postAction(path: "/api/notifications/archive-all")
    }

    private func postAction(path: String) async {
        do {
            guard let base = URL(string: settings.baseURL),
                  let url = URL(string: path, relativeTo: base) else { throw APIError.invalidURL }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            for (k, v) in settings.authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw APIError.http(-1) }
            guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        } catch {
            // Reload on error to resync with the server; the optimistic removal may be wrong.
            errorMessage = APIError.from(error).errorDescription
            await load()
        }
    }

    private func percentEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(.init(charactersIn: ":/"))) ?? s
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            guard var components = URLComponents(string: settings.baseURL) else { throw APIError.invalidURL }
            components.path = "/api/notifications"
            components.queryItems = [
                URLQueryItem(name: "type", value: filter.rawValue),
                URLQueryItem(name: "limit", value: "100"),
            ]
            guard let url = components.url else { throw APIError.invalidURL }
            var req = URLRequest(url: url)
            for (k, v) in settings.authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw APIError.http(-1) }
            guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
            let decoded = try JSONDecoder().decode(NotificationsListResponse.self, from: data)
            self.items = decoded.list
            self.errorMessage = nil
        } catch {
            self.errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
