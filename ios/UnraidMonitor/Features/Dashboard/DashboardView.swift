import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var settings: Settings
    @StateObject private var vm = DashboardViewModel()
    @StateObject private var cardOrder = DashboardCardOrder()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var isEditing = false
    @State private var dropTargetID: CardID?

    var body: some View {
        Group {
            if let snapshot = vm.snapshot {
                if hSize == .regular {
                    gridContent(snapshot: snapshot)
                } else {
                    listContent(snapshot: snapshot)
                }
            } else if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.errorMessage {
                ContentUnavailableView(
                    "Failed to load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(err)
                )
            }
        }
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
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isEditing.toggle() }
                    } label: {
                        Image(systemName: isEditing ? "checkmark.circle.fill" : "rectangle.grid.2x2")
                            .foregroundStyle(isEditing ? Color.accentColor : .primary)
                    }
                    .accessibilityLabel(isEditing ? "Done rearranging" : "Rearrange cards")
                    NavigationLink { SettingsView(firstRun: false) } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .refreshable { await vm.refresh() }
        .task { await vm.refresh() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await vm.refresh() }
            }
        }
    }

    // MARK: - iPhone list

    @ViewBuilder
    private func listContent(snapshot: AggregateSnapshot) -> some View {
        List {
            if let ts = vm.lastUpdated {
                updatedStampRow(ts: ts)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 4, leading: 14, bottom: 0, trailing: 14))
                    .listRowSeparator(.hidden)
            }

            ForEach(cardOrder.order) { id in
                cardView(for: id, snapshot: snapshot)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowSeparator(.hidden)
            }
            .onMove { from, to in
                cardOrder.move(fromOffsets: from, toOffset: to)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
    }

    // MARK: - iPad grid

    @ViewBuilder
    private func gridContent(snapshot: AggregateSnapshot) -> some View {
        GeometryReader { geo in
            let cols = max(1, Int((geo.size.width - 24) / 340))
            ScrollView {
                VStack(spacing: 12) {
                    if let ts = vm.lastUpdated {
                        updatedStampRow(ts: ts)
                            .padding(.horizontal, 14)
                            .padding(.top, 4)
                    }

                    MasonryLayout(columns: cols, spacing: 12) {
                        ForEach(cardOrder.order) { id in
                            reorderableCard(id: id, snapshot: snapshot)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .animation(.easeInOut(duration: 0.2), value: cardOrder.order)
                }
            }
        }
    }

    @ViewBuilder
    private func reorderableCard(id: CardID, snapshot: AggregateSnapshot) -> some View {
        let isDropTarget = dropTargetID == id
        cardView(for: id, snapshot: snapshot)
            .scaleEffect(isDropTarget ? 1.03 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isDropTarget)
            .overlay {
                if isEditing {
                    ZStack {
                        Color.black.opacity(0.001)
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor.opacity(isDropTarget ? 0.18 : 0))
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                Color.accentColor.opacity(isDropTarget ? 1.0 : 0.7),
                                style: StrokeStyle(
                                    lineWidth: isDropTarget ? 3 : 2,
                                    dash: isDropTarget ? [] : [6, 4]
                                )
                            )
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .draggable(id) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            .overlay {
                                Label(cardTitle(for: id), systemImage: cardIcon(for: id))
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 240, height: 80)
                            .shadow(radius: 8)
                    }
                    .dropDestination(for: CardID.self) { items, _ in
                        dropTargetID = nil
                        guard let dragged = items.first else { return false }
                        cardOrder.move(dragged, before: id)
                        return true
                    } isTargeted: { targeted in
                        if targeted {
                            dropTargetID = id
                        } else if dropTargetID == id {
                            dropTargetID = nil
                        }
                    }
                }
            }
    }

    // MARK: - Card resolver

    @ViewBuilder
    private func cardView(for id: CardID, snapshot: AggregateSnapshot) -> some View {
        switch id {
        case .system:
            SystemCard(snapshot: snapshot)
        case .array:
            ArrayCard(array: snapshot.unraid?.array) { action, correct in
                Task { await vm.runParityAction(action: action, correct: correct) }
            }
        case .cpu:
            CpuCard(hwmon: snapshot.hwmon, metrics: snapshot.unraid?.metrics)
        case .memory:
            MemoryCard(metrics: snapshot.unraid?.metrics, system: snapshot.system)
        case .gpu:
            GpuCard(gpu: snapshot.gpu)
        case .disks:
            DisksCard(array: snapshot.unraid?.array)
        case .fans:
            FansCard(hwmon: snapshot.hwmon)
        case .containers:
            ContainersCard(docker: snapshot.unraid?.docker) { container, action in
                Task { await vm.runDockerAction(containerId: container.id, action: action) }
            }
        case .notifications:
            NotificationsCard(section: snapshot.unraid?.notifications)
        }
    }

    @ViewBuilder
    private func updatedStampRow(ts: Date) -> some View {
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
    }

    private func cardTitle(for id: CardID) -> String {
        switch id {
        case .system: return "System"
        case .array: return "Array"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .gpu: return "GPU"
        case .disks: return "Disks"
        case .fans: return "Fans"
        case .containers: return "Containers"
        case .notifications: return "Notifications"
        }
    }

    private func cardIcon(for id: CardID) -> String {
        switch id {
        case .system: return "server.rack"
        case .array: return "externaldrive.connected.to.line.below"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .gpu: return "display"
        case .disks: return "internaldrive"
        case .fans: return "fanblades"
        case .containers: return "shippingbox"
        case .notifications: return "bell"
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
