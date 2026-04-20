import Foundation

enum Fmt {
    static func bytes(kb: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: kb * 1024, countStyle: .binary)
    }

    static func uptime(_ seconds: Double?) -> String {
        guard let s = seconds else { return "—" }
        let total = Int(s)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func percent(_ v: Double?) -> String {
        guard let v = v else { return "—" }
        return String(format: "%.0f%%", v)
    }

    static func temp(_ v: Double?) -> String {
        guard let v = v else { return "—" }
        return String(format: "%.0f°C", v)
    }

    static func tempInt(_ v: Int?) -> String {
        guard let v = v else { return "—" }
        return "\(v)°C"
    }
}
