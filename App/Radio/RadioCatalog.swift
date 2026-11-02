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

    /// Loads the rows of the Sonos Radio home.
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

    /// Searches stations for the Search tab, into `searchResults`.
    func search(_ query: String) async {
        if let found = await stations(matching: query) { searchResults = found }
    }

    /// The stations and categories that match `query`: empty for no query, nil when the search failed.
    func stations(matching query: String) async -> [RadioItem]? {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        do {
            let found = try await service.search(query)
            errorMessage = nil
            return found
        } catch {
            report(error)
            return nil
        }
    }

    private func report(_ error: Error) {
        guard !HTTP.isCancellation(error) else { return }
        errorMessage = error.localizedDescription
    }
}
