import Foundation
import Observation

/// Everything the screens show from Sonos Radio: its home rows, its categories
/// and the stations found by a search. `SonosRadioService` answers.
@MainActor
@Observable
final class RadioCatalog {
    private(set) var shelves: [RadioShelf] = []
    /// The well-known Dutch stations, which Sonos Radio files under the provinces.
    private(set) var dutch: [RadioItem] = []
    private(set) var searchResults: [RadioItem] = []
    private(set) var errorMessage: String?

    private let service: SonosRadioService

    init(service: SonosRadioService) {
        self.service = service
    }

    /// The Dutch stations to show first: their Sonos Radio IDs, and the name to search for.
    /// Chosen by hand from Sonos Radio's search; add one by searching its name there.
    static let dutchStations = [
        ("tunein:5668", "NPO Radio 2"), ("tunein:7177", "NPO Radio 1"), ("tunein:4345", "BNR Nieuwsradio"), ("tunein:4855", "NPO 3FM"),
        ("tunein:9724", "NPO Klassiek"), ("tunein:19004", "Qmusic"), ("tunein:4853", "Radio 538"),
        ("tunein:5568", "Sky Radio"), ("tunein:192652", "Radio Veronica"), ("tunein:17761", "100% NL"),
        ("tunein:7073", "Radio 10"), ("tunein:47580", "KINK"), ("tunein:17258", "SLAM!"),
    ]

    /// Loads the Sonos Radio home, with the Dutch stations.
    func load() async {
        async let dutchStations = loadDutch()
        do {
            shelves = try await service.home()
            errorMessage = nil
        } catch {
            report(error)
        }
        dutch = await dutchStations
    }

    /// Finds each Dutch station by name, for its logo; a station that doesn't turn up is left out.
    private func loadDutch() async -> [RadioItem] {
        await withTaskGroup(of: (Int, RadioItem?).self) { tasks in
            for (index, (id, name)) in Self.dutchStations.enumerated() {
                tasks.addTask { @MainActor in
                    (index, (try? await self.service.search(name))?.first { $0.id == id })
                }
            }
            var found: [(Int, RadioItem)] = []
            for await (index, item) in tasks { if let item { found.append((index, item)) } }
            return found.sorted { $0.0 < $1.0 }.map(\.1)
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
