import SwiftUI

/// A page of Sonos Radio. Pages open by value, like the Spotify pages.
enum RadioPage: Hashable {
    /// Every row of the Sonos Radio home, and its categories.
    case home
    /// The stations and categories in one category.
    case category(RadioItem)
    /// The user's favourite stations, to manage.
    case favourites
}

struct RadioPageView: View {
    let page: RadioPage

    var body: some View {
        switch page {
        case .home: RadioHomeView()
        case .category(let category): RadioCategoryView(category: category)
        case .favourites: FavouritesView()
        }
    }
}

/// The Sonos Radio home: the favourites, rows of stations, then the categories to browse.
private struct RadioHomeView: View {
    @Environment(RadioCatalog.self) private var radio

    var body: some View {
        List {
            FavouritesShelf()
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

/// Sonos Radio on the start screen: the favourites, its rows of stations, then its categories.
struct RadioHomeContent: View {
    @Environment(RadioCatalog.self) private var radio

    var body: some View {
        FavouritesShelf()
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

/// The user's favourite stations, first on Sonos Radio. The title opens them to
/// put in order, edit, remove and add to.
private struct FavouritesShelf: View {
    @Environment(Favourites.self) private var favourites

    var body: some View {
        if favourites.all.isEmpty {
            NavigationLink(value: RadioPage.favourites) {
                Label("Add favourite stations", systemImage: "star").font(.headline)
            }
            .padding(.horizontal)
        } else {
            StationShelf(title: "Favourites", items: favourites.all, more: .favourites) { FavouriteCard(favourite: $0) }
        }
    }
}

/// A titled, horizontal row of station cards.
struct StationShelf<Item: Identifiable, Card: View>: View {
    let title: String
    let items: [Item]
    /// The page the title opens, such as the favourites to manage.
    var more: RadioPage?
    @ViewBuilder let card: (Item) -> Card

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
                        ForEach(items) { card($0) }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

extension StationShelf where Item == RadioItem, Card == RadioCard {
    /// A row of Sonos Radio stations and categories.
    init(title: String, items: [RadioItem]) {
        self.init(title: title, items: items) { RadioCard(item: $0) }
    }
}

/// A logo with a name and a line below it, as on a shelf.
private struct CoverCard<Cover: View>: View {
    let name: String
    let subtitle: String
    var size: CGFloat = 150
    @ViewBuilder let cover: () -> Cover

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            cover().frame(width: size, height: size)
            Text(name).font(.subheadline.bold()).lineLimit(1)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: size)
    }
}

/// A station's logo with its name; the round button plays it. A category opens.
/// Touch and hold a station to add it to the favourites or take it out.
struct RadioCard: View {
    let item: RadioItem
    @Environment(\.play) private var play

    var body: some View {
        CoverCard(name: item.name, subtitle: item.subtitle) {
            if item.isStation {
                ZStack(alignment: .bottomTrailing) {
                    cover
                    PlayCircle(name: item.name) { play(.station(item)) }
                }
            } else {
                NavigationLink(value: RadioPage.category(item)) { cover }.buttonStyle(.plain)
            }
        }
        .contextMenu { if item.isStation { FavouriteToggle(station: item) } }
    }

    private var cover: some View { Artwork(url: item.imageURL, cornerRadius: 8) }
}

/// A favourite's logo with its name and source; the round button plays it.
private struct FavouriteCard: View {
    let favourite: Favourite
    @Environment(Favourites.self) private var favourites
    @Environment(\.play) private var play

    var body: some View {
        CoverCard(name: favourite.name, subtitle: favourite.sourceLabel) {
            ZStack(alignment: .bottomTrailing) {
                Artwork(url: favourite.logoURL, cornerRadius: 8)
                PlayCircle(name: favourite.name) { play(favourite.playRequest) }
            }
        }
        .contextMenu {
            Button("Remove from Favourites", systemImage: "star.slash", role: .destructive) {
                favourites.remove(favourite)
            }
        }
    }
}

/// Adds a Sonos Radio station to the favourites, or takes it out.
struct FavouriteToggle: View {
    let station: RadioItem
    @Environment(Favourites.self) private var favourites

    var body: some View {
        if favourites.contains(station) {
            Button("Remove from Favourites", systemImage: "star.slash") { favourites.toggle(station) }
        } else {
            Button("Add to Favourites", systemImage: "star") { favourites.toggle(station) }
        }
    }
}

/// A station or category in a list. Tap a station to play it; its ⋯ menu adds it
/// to the favourites. A category opens.
struct RadioRow: View {
    let item: RadioItem
    @Environment(SonosController.self) private var sonos
    @Environment(\.play) private var play

    /// The station the selected room plays now, in green as in Spotify.
    private var isCurrent: Bool { item.isStation && sonos.selectedStatus.station == item.name }

    var body: some View {
        if item.isStation {
            HStack(spacing: 0) {
                Button { play(.station(item)) } label: { RadioLabel(item: item, isCurrent: isCurrent) }
                    .buttonStyle(.borderless).tint(.primary)
                MoreMenu(name: item.name) { FavouriteToggle(station: item) }
            }
            .contextMenu { FavouriteToggle(station: item) }
        } else {
            NavigationLink(value: RadioPage.category(item)) { RadioLabel(item: item) }
        }
    }
}

/// A station's logo, or a category's icon, with its name and a line below it, as in a list.
struct RadioLabel: View {
    let name: String
    let subtitle: String
    let imageURL: URL?
    var isCategory = false
    /// Green, as the station that plays now.
    var isCurrent = false

    var body: some View {
        HStack(spacing: 12) {
            if isCategory {
                // The category icons are white line drawings.
                CachedImage(url: imageURL) { Image(systemName: "dot.radiowaves.left.and.right") }
                    .padding(8)
                    .frame(width: 48, height: 48)
                    .background(Color.accent.gradient, in: .rect(cornerRadius: 4))
            } else {
                Artwork(url: imageURL, cornerRadius: 4).frame(width: 48, height: 48)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).lineLimit(1).foregroundStyle(isCurrent ? Color.accent : .primary)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}

extension RadioLabel {
    init(item: RadioItem, isCurrent: Bool = false) {
        self.init(name: item.name, subtitle: item.subtitle, imageURL: item.imageURL,
                  isCategory: !item.isStation, isCurrent: isCurrent)
    }
}
