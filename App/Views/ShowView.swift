import AuthenticationServices
import SwiftUI

/// A podcast: its cover and name, and its episodes in an `ItemList`, newest first,
/// each with its date, length and how far the user listened. A tap plays an
/// episode from there.
struct ShowView: View {
    let show: SpotifyItem
    @Environment(SpotifyCatalog.self) private var catalog
    @Environment(\.play) private var play
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var episodes: [SpotifyItem]?
    @State private var errorMessage: String?

    var body: some View {
        ItemList("", items: episodes, orderKey: "episodesOrder", sortKeys: [.custom, .title, .released],
                 sectionTitle: "Episodes", message: errorMessage, prompt: "Search in \(show.name)") { _ in
            ListHeader(item: show) { EmptyView() }
            if !catalog.canResume {
                Section {
                    Button("Sign in to Spotify again to see where you left off", action: signIn)
                        .font(.footnote)
                }
            }
        } row: { episode, _ in
            ItemRow(item: episode) { play(.tap(episode)) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            episodes = try await catalog.episodes(of: show)
            errorMessage = nil
        } catch {
            if HTTP.isCancellation(error) { return }
            episodes = episodes ?? []
            errorMessage = error.localizedDescription
        }
    }

    private func signIn() {
        Task {
            await catalog.signIn { url in
                try await webAuthenticationSession.authenticate(using: url, callbackURLScheme: SpotifyWebAPI.callbackScheme)
            }
            await load()
        }
    }
}
