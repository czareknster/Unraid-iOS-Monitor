import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var settings: Settings
    @StateObject private var vm = DashboardViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            if let snapshot = vm.snapshot {
                if let ts = vm.lastUpdated {
                    TimelineView(.periodic(from: ts, by: 1)) { _ in
                        HStack {
                            if vm.isLoading {
                                ProgressView().scaleEffect(0.7)
                            }
                            Spacer()
                            Text("Updated \(ts, format: .dateTime.hour().minute().second()) · \(relativeTime(since: ts))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .id(ts)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 4, leading: 14, bottom: 0, trailing: 14))
                    .listRowSeparator(.hidden)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 340), spacing: 12)],
                    spacing: 12
                ) {
                    SystemCard(snapshot: snapshot)
                    ArrayCard(array: snapshot.unraid?.array) { action, correct in
                        Task { await vm.runParityAction(action: action, correct: correct) }
                    }
                    CpuCard(hwmon: snapshot.hwmon, metrics: snapshot.unraid?.metrics)
                    MemoryCard(metrics: snapshot.unraid?.metrics, system: snapshot.system)
                    GpuCard(gpu: snapshot.gpu)
                    DisksCard(array: snapshot.unraid?.array)
                    FansCard(hwmon: snapshot.hwmon)
                    ContainersCard(docker: snapshot.unraid?.docker) { container, action in
                        Task { await vm.runDockerAction(containerId: container.id, action: action) }
                    }
                    NotificationsCard(section: snapshot.unraid?.notifications)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(.init(top: 8, leading: 12, bottom: 12, trailing: 12))
                .listRowSeparator(.hidden)
            } else if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if let err = vm.errorMessage {
                ContentUnavailableView("Failed to load", systemImage: "exclamationmark.triangle", description: Text(err))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("UNRAID")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.75, green: 0.27, blue: 0.17),
                                     Color(red: 0.95, green: 0.56, blue: 0.20)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    NavigationLink { NotificationsListView() } label: {
                        let counts = vm.snapshot?.unraid?.notifications.overview.unread
                        let hasUnread = (counts?.total ?? 0) > 0
                        Image(systemName: hasUnread ? "bell.badge" : "bell")
                            .foregroundStyle(counts.map(badgeColor) ?? .accentColor)
                    }
                    NavigationLink { HistoryView() } label: {
                        Image(systemName: "chart.xyaxis.line")
                    }
                    NavigationLink { SettingsView(firstRun: false) } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .refreshable { await vm.refresh() }
        .task { await vm.refresh() }
        .onChange(of: scenePhase) { _, newPhase in
            // Returning to foreground after tapping a push notification or
            // switching back from another app — pull fresh state so badges /
            // counts reflect anything that arrived while we were away.
            if newPhase == .active {
                Task { await vm.refresh() }
            }
        }
    }

    private func badgeColor(counts: NotificationsSection.Overview.Counts) -> Color {
        if counts.alert > 0 { return .red }
        if counts.warning > 0 { return .orange }
        return .blue
    }

    private func relativeTime(since date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 2 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }
}
