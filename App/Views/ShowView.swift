import AuthenticationServices
import SwiftUI

/// A podcast: its cover and name, and its episodes, newest first, each with its
/// date, length and how far the user listened. A tap plays an episode from there.
struct ShowView: View {
    let show: SpotifyItem
    @Environment(SpotifyCatalog.self) private var catalog
    @Environment(\.play) private var play
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var episodes: [SpotifyItem] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Artwork(url: show.imageURL, cornerRadius: 10)
                        .frame(width: 200, height: 200)
                        .shadow(radius: 12)
                    Text(show.name).font(.title2.bold()).multilineTextAlignment(.center)
                    Text(show.subtitle).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            if !catalog.canResume {
                Section {
                    Button("Sign in to Spotify again to see where you left off", action: signIn)
                        .font(.footnote)
                }
            }

            Section("Episodes") {
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
                ForEach(episodes) { episode in
                    ItemRow(item: episode) { play(.tap(episode)) }
                }
            }
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
            if !HTTP.isCancellation(error) { errorMessage = error.localizedDescription }
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
