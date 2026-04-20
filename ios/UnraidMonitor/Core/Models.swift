import Foundation

// Mirrors backend AggregateSnapshot returned by GET /api/snapshot.
struct AggregateSnapshot: Decodable {
    let ts: String
    let unraid: UnraidSection?
    let hwmon: HwmonSection?
    let gpu: GpuSection?
    let system: SystemSection?
    let errors: [String: String]
}

struct UnraidSection: Decodable {
    let info: UnraidInfo
    let array: ArraySection
    let docker: DockerSection
    let notifications: NotificationsSection
    let metrics: MetricsSection
}

struct UnraidInfo: Decodable {
    let os: OsInfo
    let versions: Versions

    struct OsInfo: Decodable {
        let hostname: String
        let uptime: String
        let kernel: String
    }
    struct Versions: Decodable {
        let core: Core
        struct Core: Decodable {
            let unraid: String
            let api: String
            let kernel: String
        }
    }
}

struct ArraySection: Decodable {
    let state: String
    let capacity: Capacity
    let parities: [ArrayDisk]
    let disks: [ArrayDisk]
    let caches: [ArrayDisk]
    let parityCheckStatus: ParityStatus

    struct Capacity: Decodable {
        let kilobytes: KB
        struct KB: Decodable {
            let free: String
            let used: String
            let total: String
        }
    }
    struct ParityStatus: Decodable {
        let progress: Double?
        let running: Bool?
        let paused: Bool?
        let errors: Int?
    }
}

struct ArrayDisk: Decodable, Identifiable {
    let name: String
    let status: String
    let temp: Int?
    let numErrors: Int?
    var id: String { name }
}

struct DockerSection: Decodable {
    let containers: [DockerContainer]
}

struct DockerContainer: Decodable, Identifiable {
    let id: String
    let names: [String]
    let image: String
    let state: String
    let status: String
    let autoStart: Bool

    var displayName: String {
        names.first.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 } ?? id
    }
}

struct NotificationsSection: Decodable {
    let overview: Overview
    struct Overview: Decodable {
        let unread: Counts
        struct Counts: Decodable {
            let total: Int
            let info: Int
            let warning: Int
            let alert: Int
        }
    }
}

struct MetricsSection: Decodable {
    let cpu: Cpu
    let memory: Memory
    struct Cpu: Decodable {
        let percentTotal: Double
        let cpus: [Core]?   // per logical CPU / thread — nil on older backends
        struct Core: Decodable { let percentTotal: Double }
    }
    struct Memory: Decodable {
        let percentTotal: Double
        let total: Int64
        let used: Int64
    }
}

struct HwmonSection: Decodable {
    let cpu: CpuTemps
    let motherboard: Motherboard
    let fans: [Fan]

    struct CpuTemps: Decodable {
        let packageC: Double?
        let cores: [Core]
        struct Core: Decodable {
            let label: String
            let tempC: Double
        }
    }
    struct Motherboard: Decodable {
        let tempC: Double?
        let pchC: Double?
    }
    struct Fan: Decodable, Identifiable {
        let name: String
        let rpm: Int
        var id: String { name }
    }
}

struct GpuSection: Decodable {
    let present: Bool
    let tempC: Double?
    let rc6Percent: Double?
    let busyPercent: Double?
    let frequencyMhz: Int?
    let powerW: Double?
    let engines: [String: Double]?
}

struct SystemSection: Decodable {
    let uptimeSec: Double?
    let loadavg: LoadAvg?
    let memory: Memory?

    struct LoadAvg: Decodable {
        let oneMin: Double
        let fiveMin: Double
        let fifteenMin: Double
    }
    struct Memory: Decodable {
        let totalKB: Int64
        let freeKB: Int64
        let availableKB: Int64
        let buffersKB: Int64
        let cachedKB: Int64
        let swapTotalKB: Int64
        let swapFreeKB: Int64
    }
}
