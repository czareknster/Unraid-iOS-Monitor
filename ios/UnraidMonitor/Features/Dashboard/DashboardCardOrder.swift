import Foundation
import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

enum CardID: String, CaseIterable, Codable, Identifiable, Hashable, Transferable {
    case system
    case array
    case cpu
    case memory
    case gpu
    case disks
    case fans
    case containers
    case notifications

    var id: String { rawValue }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

@MainActor
final class DashboardCardOrder: ObservableObject {
    @Published var order: [CardID] {
        didSet { save() }
    }

    private static let storageKey = "dashboard.cardOrder.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([CardID].self, from: data) {
            var merged = decoded.filter { CardID.allCases.contains($0) }
            for id in CardID.allCases where !merged.contains(id) {
                merged.append(id)
            }
            self.order = merged
        } else {
            self.order = CardID.allCases
        }
    }

    func move(_ id: CardID, before target: CardID) {
        guard id != target,
              let from = order.firstIndex(of: id) else { return }
        order.remove(at: from)
        let to = order.firstIndex(of: target) ?? order.endIndex
        order.insert(id, at: to)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
    }

    func resetToDefault() {
        order = CardID.allCases
    }

    private func save() {
        if let data = try? JSONEncoder().encode(order) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
