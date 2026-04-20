import SwiftUI
import Charts

struct HistoryPoint: Decodable, Identifiable {
    let ts: Int
    let value: Double
    var id: Int { ts }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(ts) / 1000) }
}

struct HistoryResponse: Decodable {
    let metric: String
    let from: Int
    let to: Int
    let bucketMs: Int
    let points: [HistoryPoint]
}

enum HistoryRange: String, CaseIterable, Identifiable {
    case oneHour = "1h"
    case sixHours = "6h"
    case day = "24h"
    case week = "7d"
    var id: String { rawValue }
    var label: String { rawValue }
}

struct HistoryMetric: Identifiable, Hashable {
    let id: String  // backend metric key
    let label: String
    let unit: String
}

private let metrics: [HistoryMetric] = [
    .init(id: "cpu.packageC",     label: "CPU Package", unit: "°C"),
    .init(id: "cpu.coreMaxC",     label: "CPU Core Max", unit: "°C"),
    .init(id: "cpu.coreAvgC",     label: "CPU Core Avg", unit: "°C"),
    .init(id: "cpu.loadPercent",  label: "CPU Load",     unit: "%"),
    .init(id: "mb.tempC",         label: "Motherboard",  unit: "°C"),
    .init(id: "memory.percent",   label: "Memory",       unit: "%"),
    .init(id: "gpu.busyPercent",  label: "GPU Busy",     unit: "%"),
    .init(id: "gpu.powerW",       label: "GPU Power",    unit: "W"),
    .init(id: "disk.disk1.tempC", label: "disk1",        unit: "°C"),
    .init(id: "disk.cache.tempC", label: "cache",        unit: "°C"),
    .init(id: "disk.parity.tempC",label: "parity",       unit: "°C"),
    .init(id: "system.loadavg1",  label: "Load 1m",      unit: ""),
]

struct HistoryView: View {
    @EnvironmentObject var settings: Settings

    @State private var metric: HistoryMetric = metrics[0]
    @State private var range: HistoryRange = .oneHour
    @State private var points: [HistoryPoint] = []
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            pickerBar
            chartBody
            footer
        }
        .padding()
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: taskKey) { await load() }
    }

    private var taskKey: String { "\(metric.id)|\(range.rawValue)" }

    private var pickerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(metrics) { m in
                    Button(m.label) { metric = m }
                }
            } label: {
                HStack {
                    Text(metric.label).font(.headline)
                    Image(systemName: "chevron.down").font(.caption)
                    Spacer()
                }
                .contentShape(Rectangle())
            }

            Picker("Range", selection: $range) {
                ForEach(HistoryRange.allCases) { r in
                    Text(r.label).tag(r)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var chartBody: some View {
        if loading && points.isEmpty {
            ProgressView().frame(maxWidth: .infinity, minHeight: 260)
        } else if let err = errorMessage {
            ContentUnavailableView("Failed to load", systemImage: "exclamationmark.triangle", description: Text(err))
                .frame(maxWidth: .infinity, minHeight: 260)
        } else if points.isEmpty {
            ContentUnavailableView("No data", systemImage: "chart.xyaxis.line", description: Text("Samples start appearing ~10 s after backend restart."))
                .frame(maxWidth: .infinity, minHeight: 260)
        } else {
            Chart(points) { p in
                LineMark(x: .value("Time", p.date), y: .value(metric.label, p.value))
                    .interpolationMethod(.monotone)
                AreaMark(x: .value("Time", p.date), y: .value(metric.label, p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(colors: [.accentColor.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
            }
            .chartYAxis {
                AxisMarks { v in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = v.as(Double.self) {
                            Text(formatValue(d))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { v in
                    AxisGridLine()
                    AxisValueLabel(format: xAxisFormat)
                }
            }
            .frame(height: 260)
        }
    }

    private var footer: some View {
        HStack {
            if let min = points.map(\.value).min(), let max = points.map(\.value).max(), !points.isEmpty {
                Text("min \(formatValue(min))  max \(formatValue(max))  n=\(points.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var xAxisFormat: Date.FormatStyle {
        switch range {
        case .oneHour, .sixHours: return .dateTime.hour().minute()
        case .day:                 return .dateTime.hour()
        case .week:                return .dateTime.weekday(.abbreviated)
        }
    }

    private func formatValue(_ v: Double) -> String {
        if metric.unit == "°C" { return String(format: "%.0f°C", v) }
        if metric.unit == "%"  { return String(format: "%.0f%%", v) }
        if metric.unit == "W"  { return String(format: "%.1f W", v) }
        return String(format: "%.2f", v)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let response = try await fetch()
            self.points = response.points
            self.errorMessage = nil
        } catch {
            self.errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            self.points = []
        }
    }

    private func fetch() async throws -> HistoryResponse {
        guard var components = URLComponents(string: settings.baseURL) else { throw APIError.invalidURL }
        components.path = "/api/history"
        components.queryItems = [
            URLQueryItem(name: "metric", value: metric.id),
            URLQueryItem(name: "range", value: range.rawValue),
        ]
        guard let url = components.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        for (k, v) in settings.authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.http(-1) }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        return try JSONDecoder().decode(HistoryResponse.self, from: data)
    }
}
