import SwiftUI

/// A page of Sonos Radio. Pages open by value, like the Spotify pages.
enum RadioPage: Hashable {
    /// Every row of the Sonos Radio home, and its categories.
    case home
    /// The stations and categories in one category.
    case category(RadioItem)
}

struct RadioPageView: View {
    let page: RadioPage

    var body: some View {
        switch page {
        case .home: RadioHomeView()
        case .category(let category): RadioCategoryView(category: category)
        }
    }
}

/// The Sonos Radio home: rows of stations, then the categories to browse.
private struct RadioHomeView: View {
    @Environment(RadioCatalog.self) private var radio

    var body: some View {
        List {
            StationShelf(title: "Dutch radio", items: radio.dutch)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            ForEach(radio.shelves) { shelf in
                if shelf.items.contains(where: \.isStation) {
                    StationShelf(title: shelf.title, items: shelf.items)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                } else {
                    Section(shelf.title) {
                        ForEach(shelf.items) { RadioRow(item: $0) }
                    }
                }
            }
            if let message = radio.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Sonos Radio")
        .refreshable { await radio.load() }
        .task { if radio.shelves.isEmpty { await radio.load() } }
    }
}

/// The stations and categories in a category, such as a genre or a country, in an `ItemList`.
private struct RadioCategoryView: View {
    let category: RadioItem
    @Environment(RadioCatalog.self) private var radio
    @State private var items: [RadioItem]?

    var body: some View {
        ItemList(category.name, items: items, orderKey: "radioOrder", sortKeys: [.custom, .title],
                 message: items?.isEmpty == true ? radio.errorMessage : nil) { item, _ in
            RadioRow(item: item)
        }
        .task { if items == nil { items = await radio.items(in: category) } }
    }
}

/// Sonos Radio on the start screen: its rows of stations, then its categories.
struct RadioHomeContent: View {
    @Environment(RadioCatalog.self) private var radio

    var body: some View {
        StationShelf(title: "Dutch radio", items: radio.dutch)
        ForEach(radio.shelves) { shelf in
            if shelf.items.contains(where: \.isStation) {
                StationShelf(title: shelf.title, items: shelf.items)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(shelf.title).font(.title2.bold())
                    ForEach(shelf.items) { item in
                        RadioRow(item: item)
                        if item.id != shelf.items.last?.id { Divider().padding(.leading, 60) }
                    }
                }
                .padding(.horizontal)
            }
        }
        if radio.shelves.isEmpty && radio.errorMessage == nil {
            ProgressView().frame(maxWidth: .infinity)
        }
        if let message = radio.errorMessage {
            Text(message).font(.footnote).foregroundStyle(.red).padding(.horizontal)
        }
    }
}

/// A titled, horizontal row of station cards.
struct StationShelf: View {
    let title: String
    let items: [RadioItem]
    /// The page the title opens, such as the whole Sonos Radio home.
    var more: RadioPage?

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Group {
                    if let more {
                        NavigationLink(value: more) {
                            HStack(spacing: 6) {
                                Text(title)
                                Image(systemName: "chevron.right").font(.title3.bold()).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(title)
                    }
                }
                .font(.title2.bold())
                .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(items) { RadioCard(item: $0) }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

/// A station's logo with its name; the round button plays it. A category opens.
private struct RadioCard: View {
    let item: RadioItem
    var size: CGFloat = 150
    @Environment(\.play) private var play

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if item.isStation {
                ZStack(alignment: .bottomTrailing) {
                    cover
                    PlayCircle(name: item.name) { play(.station(item)) }
                }
            } else {
                NavigationLink(value: RadioPage.category(item)) { cover }.buttonStyle(.plain)
            }
            Text(item.name).font(.subheadline.bold()).lineLimit(1)
            Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: size)
    }

    private var cover: some View {
        Artwork(url: item.imageURL, cornerRadius: 8).frame(width: size, height: size)
    }
}

/// A station or category in a list. Tap a station to play it; a category opens.
struct RadioRow: View {
    let item: RadioItem
    @Environment(SonosController.self) private var sonos
    @Environment(\.play) private var play

    /// The station the selected room plays now, in green as in Spotify.
    private var isCurrent: Bool { item.isStation && sonos.selectedStatus.station == item.name }

    var body: some View {
        if item.isStation {
            Button { play(.station(item)) } label: { label }.buttonStyle(.borderless).tint(.primary)
        } else {
            NavigationLink(value: RadioPage.category(item)) { label }
        }
    }

    private var label: some View {
        HStack(spacing: 12) {
            if item.isStation {
                Artwork(url: item.imageURL, cornerRadius: 4).frame(width: 48, height: 48)
            } else {
                // The category icons are white line drawings.
                CachedImage(url: item.imageURL) { Image(systemName: "dot.radiowaves.left.and.right") }
                    .padding(8)
                    .frame(width: 48, height: 48)
                    .background(Color.accent.gradient, in: .rect(cornerRadius: 4))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1).foregroundStyle(isCurrent ? Color.accent : .primary)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}
