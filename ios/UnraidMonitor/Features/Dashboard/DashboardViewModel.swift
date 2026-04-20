import Foundation
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var snapshot: AggregateSnapshot?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    private let api = APIClient()

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await api.snapshot()
            lastUpdated = Date()
            errorMessage = nil
        } catch let err as APIError where err.isCancelled {
            // SwiftUI cancels the outer .task when the view disappears; ignore.
        } catch {
            errorMessage = APIError.from(error).errorDescription
        }
    }

    func runDockerAction(containerId: String, action: String) async {
        do {
            try await api.dockerAction(containerId: containerId, action: action)
            await refresh()
        } catch let err as APIError where err.isCancelled {
            // ignore
        } catch {
            errorMessage = APIError.from(error).errorDescription
        }
    }

    func runParityAction(action: String, correct: Bool? = nil) async {
        do {
            try await api.parityAction(action: action, correct: correct)
            await refresh()
        } catch let err as APIError where err.isCancelled {
            // ignore
        } catch {
            errorMessage = APIError.from(error).errorDescription
        }
    }
}

private extension APIError {
    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }
}
