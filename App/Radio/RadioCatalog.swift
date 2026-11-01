import Foundation
import Observation

/// Everything the screens show from Sonos Radio: its home rows, its categories
/// and the stations found by a search. `SonosRadioService` answers.
@MainActor
@Observable
final class RadioCatalog {
    private(set) var shelves: [RadioShelf] = []
    private(set) var searchResults: [RadioItem] = []
    private(set) var errorMessage: String?

    private let service: SonosRadioService

    init(service: SonosRadioService) {
        self.service = service
    }

    /// Loads the Sonos Radio home.
    func load() async {
        do {
            shelves = try await service.home()
            errorMessage = nil
        } catch {
            report(error)
        }
    }

    /// The stations and categories in a category; empty when it didn't load.
    func items(in category: RadioItem) async -> [RadioItem] {
        do {
            return try await service.items(in: category)
        } catch {
            report(error)
            return []
        }
    }

    func search(_ query: String) async {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        do {
            searchResults = try await service.search(query)
            errorMessage = nil
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        guard !HTTP.isCancellation(error) else { return }
        errorMessage = error.localizedDescription
    }
}
