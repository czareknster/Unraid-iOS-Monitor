import SwiftUI

// MARK: - Shared card chrome

struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    var expanded: Binding<Bool>? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var header: some View {
        if let expanded {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded.wrappedValue ? 180 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.wrappedValue.toggle() }
            }
        } else {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct Row: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(valueColor).monospacedDigit()
        }
        .font(.subheadline)
    }
}

// MARK: - System

struct SystemCard: View {
    let snapshot: AggregateSnapshot

    var body: some View {
        Card(title: "System", systemImage: "server.rack") {
            if let info = snapshot.unraid?.info {
                Row(label: "Host", value: info.os.hostname)
                Row(label: "Unraid", value: info.versions.core.unraid)
                Row(label: "Kernel", value: info.versions.core.kernel)
            }
            Row(label: "Uptime", value: Fmt.uptime(snapshot.system?.uptimeSec))
            if let la = snapshot.system?.loadavg {
                Row(label: "Load", value: String(format: "%.2f / %.2f / %.2f", la.oneMin, la.fiveMin, la.fifteenMin))
            }
        }
    }
}

// MARK: - Array

struct ArrayCard: View {
    let array: ArraySection?
    let onParityAction: (String, Bool?) -> Void

    var body: some View {
        Card(title: "Array", systemImage: "externaldrive.connected.to.line.below") {
            if let a = array, let free = Int64(a.capacity.kilobytes.free), let total = Int64(a.capacity.kilobytes.total) {
                let used = total - free
                let pct = total > 0 ? Double(used) / Double(total) : 0
                Row(label: "Status", value: a.state, valueColor: a.state == "STARTED" ? .green : .orange)
                Row(label: "Used", value: "\(Fmt.bytes(kb: used)) / \(Fmt.bytes(kb: total))")
                ProgressView(value: pct).tint(pct > 0.9 ? .red : .accentColor)
                parityControls(for: a)
            } else {
                Text("No data").foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func parityControls(for a: ArraySection) -> some View {
        let running = a.parityCheckStatus.running == true
        let paused = a.parityCheckStatus.paused == true

        if running || paused {
            Row(label: "Parity check", value: Fmt.percent(a.parityCheckStatus.progress))
            HStack(spacing: 8) {
                if paused {
                    Button { onParityAction("resume", nil) } label: {
                        Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button { onParityAction("pause", nil) } label: {
                        Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Button(role: .destructive) { onParityAction("cancel", nil) } label: {
                    Label("Cancel", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)
        }
    }
}

// MARK: - CPU

struct CpuCard: View {
    let hwmon: HwmonSection?
    let metrics: MetricsSection?

    @State private var expanded = false

    var body: some View {
        Card(title: "CPU", systemImage: "cpu", expanded: $expanded) {
            Row(label: "Load", value: Fmt.percent(metrics?.cpu.percentTotal))
            Row(label: "Package", value: Fmt.temp(hwmon?.cpu.packageC))

            if let cores = hwmon?.cpu.cores, !cores.isEmpty {
                let maxC = cores.map(\.tempC).max() ?? 0
                let avgC = cores.map(\.tempC).reduce(0, +) / Double(cores.count)

                Row(label: "Cores (avg/max)", value: "\(Int(avgC))°C / \(Int(maxC))°C")

                // Per-core spark bars (always visible, quick glance)
                HStack(spacing: 2) {
                    ForEach(cores, id: \.label) { c in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(coreColor(c.tempC))
                            .frame(height: 18)
                    }
                }

                if expanded {
                    VStack(alignment: .leading, spacing: 10) {
                        // Per-core temperatures (from coretemp labels — hybrid CPUs
                        // interleave P-core and E-core indexes, so this is not 1:1
                        // with the logical-CPU load grid below).
                        Text("Temperatures")
                            .font(.caption.smallCaps())
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                            spacing: 6
                        ) {
                            ForEach(cores, id: \.label) { c in
                                VStack(spacing: 2) {
                                    Text(coreShortLabel(c.label))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("\(Int(c.tempC))°")
                                        .font(.caption.monospacedDigit().bold())
                                        .foregroundStyle(coreColor(c.tempC))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }

                        if let threads = metrics?.cpu.cpus, !threads.isEmpty {
                            Text("Load per thread")
                                .font(.caption.smallCaps())
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5),
                                spacing: 6
                            ) {
                                ForEach(Array(threads.enumerated()), id: \.offset) { idx, t in
                                    VStack(spacing: 2) {
                                        Text("T\(idx)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("\(Int(t.percentTotal.rounded()))%")
                                            .font(.caption.monospacedDigit().bold())
                                            .foregroundStyle(loadColor(t.percentTotal))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func loadColor(_ pct: Double) -> Color {
        switch pct {
        case ..<20: return .secondary
        case 20..<60: return .green
        case 60..<85: return .orange
        default: return .red
        }
    }

    private func coreShortLabel(_ label: String) -> String {
        // "Core 25" → "C25"; keep Package as is.
        if let num = label.match(pattern: #"\d+"#) { return "C\(num)" }
        return label
    }

    private func coreColor(_ c: Double) -> Color {
        switch c {
        case ..<50: return .green
        case 50..<70: return .yellow
        case 70..<85: return .orange
        default: return .red
        }
    }
}

private extension String {
    func match(pattern: String) -> String? {
        guard let range = self.range(of: pattern, options: .regularExpression) else { return nil }
        return String(self[range])
    }
}

// MARK: - Memory

struct MemoryCard: View {
    let metrics: MetricsSection?
    let system: SystemSection?

    var body: some View {
        Card(title: "Memory", systemImage: "memorychip") {
            if let m = metrics?.memory {
                let pct = m.percentTotal / 100.0
                Row(label: "Used", value: "\(Fmt.percent(m.percentTotal))")
                ProgressView(value: pct).tint(pct > 0.9 ? .red : .accentColor)
                Row(label: "Total", value: ByteCountFormatter.string(fromByteCount: m.total, countStyle: .binary))
            }
            if let s = system?.memory {
                Row(label: "Available", value: Fmt.bytes(kb: s.availableKB))
                if s.swapTotalKB > 0 {
                    Row(label: "Swap used", value: Fmt.bytes(kb: s.swapTotalKB - s.swapFreeKB))
                }
            }
        }
    }
}

// MARK: - GPU

struct GpuCard: View {
    let gpu: GpuSection?

    var body: some View {
        Card(title: "GPU (iGPU)", systemImage: "display") {
            if let g = gpu, g.present {
                Row(label: "Busy", value: Fmt.percent(g.busyPercent))
                Row(label: "Idle (rc6)", value: Fmt.percent(g.rc6Percent))
                if let p = g.powerW { Row(label: "Power", value: String(format: "%.1f W", p)) }
                if let f = g.frequencyMhz { Row(label: "Frequency", value: "\(f) MHz") }
                if let t = g.tempC { Row(label: "Temp", value: Fmt.temp(t)) }
            } else {
                Text("No GPU detected").foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Disks

struct DisksCard: View {
    let array: ArraySection?

    var body: some View {
        Card(title: "Disks", systemImage: "internaldrive") {
            if let a = array {
                ForEach(a.parities + a.disks + a.caches) { d in
                    diskRow(d)
                }
            }
        }
    }

    @ViewBuilder
    private func diskRow(_ d: ArrayDisk) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(d.status == "DISK_OK" ? Color.green : Color.orange).frame(width: 8, height: 8)
                Text(d.name).font(.subheadline)
                Spacer()
                Text(Fmt.tempInt(d.temp)).monospacedDigit().foregroundStyle(.secondary)
                if let errs = d.numErrors, errs > 0 {
                    Text("\(errs) err").font(.caption).foregroundStyle(.red)
                }
            }
            if let size = d.fsSize, size > 0, let used = d.fsUsed {
                let pct = Double(used) / Double(size)
                ProgressView(value: pct)
                    .tint(pct > 0.9 ? .red : (pct > 0.75 ? .orange : .accentColor))
                HStack {
                    Text("\(Fmt.bytes(kb: used)) / \(Fmt.bytes(kb: size))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Fmt.percent(pct))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Fans

struct FansCard: View {
    let hwmon: HwmonSection?

    var body: some View {
        Card(title: "Fans", systemImage: "fan") {
            if let fans = hwmon?.fans, !fans.isEmpty {
                ForEach(fans) { f in
                    Row(label: f.name, value: "\(f.rpm) RPM")
                }
            } else {
                Text("No fans reporting").foregroundStyle(.tertiary)
            }
            if let t = hwmon?.motherboard.tempC {
                Divider().padding(.vertical, 2)
                Row(label: "Motherboard", value: Fmt.temp(t))
            }
        }
    }
}

// MARK: - Containers

struct ContainersCard: View {
    let docker: DockerSection?
    let onContainerAction: (DockerContainer, String) -> Void

    @State private var pendingStop: DockerContainer?

    var body: some View {
        Card(title: "Containers", systemImage: "shippingbox") {
            if let containers = docker?.containers {
                let running = containers.filter { $0.state == "RUNNING" }.count
                Row(label: "Running", value: "\(running) / \(containers.count)")
                ForEach(containers) { c in
                    containerRow(c)
                }
            }
        }
        .confirmationDialog(
            pendingStop.map { "Stop \($0.displayName)?" } ?? "",
            isPresented: Binding(get: { pendingStop != nil }, set: { if !$0 { pendingStop = nil } }),
            titleVisibility: .visible
        ) {
            Button("Stop", role: .destructive) {
                if let c = pendingStop { onContainerAction(c, "stop") }
                pendingStop = nil
            }
            Button("Cancel", role: .cancel) { pendingStop = nil }
        }
    }

    @ViewBuilder
    private func containerRow(_ c: DockerContainer) -> some View {
        HStack {
            Circle().fill(c.state == "RUNNING" ? Color.green : Color.gray).frame(width: 8, height: 8)
            Text(c.displayName).font(.subheadline).lineLimit(1)
            Spacer()
            Text(c.state.lowercased()).font(.caption).foregroundStyle(.secondary)
            Menu {
                if c.state == "RUNNING" {
                    Button { pendingStop = c } label: { Label("Stop", systemImage: "stop.fill") }
                    Button { onContainerAction(c, "restart") } label: { Label("Restart", systemImage: "arrow.clockwise") }
                } else {
                    Button { onContainerAction(c, "start") } label: { Label("Start", systemImage: "play.fill") }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Notifications

struct NotificationsCard: View {
    let section: NotificationsSection?

    var body: some View {
        Card(title: "Notifications", systemImage: "bell") {
            if let c = section?.overview.unread {
                Row(label: "Unread total", value: "\(c.total)")
                Row(label: "Info", value: "\(c.info)")
                Row(label: "Warning", value: "\(c.warning)", valueColor: c.warning > 0 ? .orange : .primary)
                Row(label: "Alert", value: "\(c.alert)", valueColor: c.alert > 0 ? .red : .primary)
            }
        }
    }
}
