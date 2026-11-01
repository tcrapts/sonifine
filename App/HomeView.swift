import AuthenticationServices
import SafariServices
import SwiftUI

/// The start screen: Spotify's home page, one tap from playing.
struct HomeView: View {
    @Environment(SpotifyController.self) private var spotify
    @Environment(SpotifyHome.self) private var home
    @Environment(SonosController.self) private var sonos

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if sonos.groups.isEmpty {
                    Label("Looking for your Sonos…", systemImage: "wifi")
                        .foregroundStyle(.secondary).padding(.horizontal)
                }
                if home.isLinked {
                    ForEach(home.shelves) { Shelf(title: $0.title, items: $0.items) }
                    Shelf(title: "Your playlists", items: spotify.playlists)
                } else {
                    ConnectSpotifyHome().padding(.horizontal)
                    Shelf(title: "Jump back in", items: spotify.jumpBackIn)
                    Shelf(title: "Your playlists", items: spotify.playlists)
                    Shelf(title: "Recently played", items: spotify.recentlyPlayed)
                    Shelf(title: "Your albums", items: spotify.albums)
                }
                if !spotify.isSignedIn {
                    SpotifySignIn().padding(.horizontal)
                }
                ForEach([home.errorMessage, spotify.errorMessage].compactMap { $0 }, id: \.self) {
                    Text($0).font(.footnote).foregroundStyle(.red).padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(greeting)
        .refreshable { await load() }
        .task(id: sonos.groups.isEmpty) {
            if home.shelves.isEmpty || spotify.playlists.isEmpty { await load() }
        }
    }

    private func load() async {
        async let library: Void = spotify.isSignedIn ? spotify.loadLibrary() : ()
        if let household = await sonos.household() { await home.loadHome(household: household) }
        await library
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}

/// Links the app to Spotify on Sonos, for Daily Mix, Release Radar and the rest of Spotify's home page.
struct ConnectSpotifyHome: View {
    @Environment(SpotifyHome.self) private var home
    @Environment(SonosController.self) private var sonos

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Get your Spotify home").font(.title2.bold())
            Text("Daily Mix, Release Radar, your top mixes and radio stations, as in the Spotify app.")
                .foregroundStyle(.secondary)
            Button {
                Task { if let household = await sonos.household() { await home.link(household: household) } }
            } label: {
                Text("Connect Spotify").bold().frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accent)
            .foregroundStyle(.black)
            .disabled(sonos.groups.isEmpty)
        }
        .padding()
        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 16))
    }
}

struct SpotifySignIn: View {
    @Environment(SpotifyController.self) private var spotify
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect your library").font(.title2.bold())
            Text("Your own playlists, liked songs, albums and search.")
                .foregroundStyle(.secondary)
            Button {
                Task { await spotify.signIn(using: webAuthenticationSession) }
            } label: {
                Text("Sign in with Spotify").bold().frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accent)
            .foregroundStyle(.black)
            if let message = spotify.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 16))
    }
}

/// The Sonos sign-in page while linking. It closes by itself once the link works.
struct SpotifyLinkSheet: ViewModifier {
    @Environment(SpotifyHome.self) private var home

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { home.linkURL != nil }, set: { if !$0 { home.cancelLink() } })) {
            if let url = home.linkURL { SafariView(url: url).ignoresSafeArea() }
        }
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
