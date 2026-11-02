import SwiftUI

/// The items a list shows after search, filter and sort. Play buttons and rows
/// play from it, so music plays as the list shows it.
struct ShownItems<Item> {
    let items: [Item]
    /// Other items or another order than the list came with; see `ListQuery.rearranges`.
    let rearranged: Bool
}

/// Every list of the app: an optional header, a search field that filters as you
/// type, a sort menu, filter chips when the list holds two kinds or more, and the rows.
struct ItemList<Item: Listable, Header: View, Row: View>: View {
    private let title: String
    private let items: [Item]?
    private let sortKeys: [ListOrder.Key]
    private let sectionTitle: String
    private let message: String?
    private let prompt: String
    private let header: (ShownItems<Item>) -> Header
    private let row: (Item, ShownItems<Item>) -> Row
    @AppStorage private var order: ListOrder
    @State private var text = ""
    @State private var kind: String?

    /// - Parameters:
    ///   - title: The navigation title; empty on a page whose header names it.
    ///   - items: The items, or nil while they load.
    ///   - orderKey: Where the sort choice is kept, one per kind of list.
    ///   - sortKeys: The sort choices; those the items have no data for stay out.
    ///   - message: An error, shown above the rows.
    init(_ title: String, items: [Item]?, orderKey: String, defaultOrder: ListOrder = .custom,
         sortKeys: [ListOrder.Key], sectionTitle: String = "", message: String? = nil, prompt: String? = nil,
         @ViewBuilder header: @escaping (ShownItems<Item>) -> Header,
         @ViewBuilder row: @escaping (Item, ShownItems<Item>) -> Row) {
        self.title = title
        self.items = items
        self.sortKeys = sortKeys
        self.sectionTitle = sectionTitle
        self.message = message
        self.prompt = prompt ?? "Search in \(title)"
        self.header = header
        self.row = row
        _order = AppStorage(wrappedValue: defaultOrder, orderKey)
    }

    var body: some View {
        let all = items ?? []
        let query = ListQuery(text: text, kind: kind, order: order)
        let shown = ShownItems(items: query.apply(to: all), rearranged: query.rearranges)
        let kinds = ListQuery.kinds(in: all)
        let keys = ListOrder.keys(sortKeys, for: all)
        List {
            header(shown)
            if kinds.count > 1 {
                FilterChips(options: [nil] + kinds, selection: $kind) { $0 ?? "All" }
            }
            Section {
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
                if items == nil {
                    ProgressView().frame(maxWidth: .infinity)
                } else if shown.items.isEmpty && !text.isEmpty {
                    ContentUnavailableView.search(text: text)
                }
                ForEach(shown.items) { row($0, shown) }
            } header: {
                // An empty title would still leave a header's room.
                if !sectionTitle.isEmpty { Text(sectionTitle) }
            }
        }
        // The header with its buttons sits close to the list, as in Spotify.
        .listSectionSpacing(.compact)
        .navigationTitle(title)
        .searchable(text: $text, placement: .navigationBarDrawer, prompt: prompt)
        .toolbar {
            if keys.count > 1 { SortMenu(order: $order, keys: keys) }
        }
    }
}

extension ItemList where Header == EmptyView {
    /// A list without a header, such as the playlists of the library.
    init(_ title: String, items: [Item]?, orderKey: String, defaultOrder: ListOrder = .custom,
         sortKeys: [ListOrder.Key], message: String? = nil,
         @ViewBuilder row: @escaping (Item, ShownItems<Item>) -> Row) {
        self.init(title, items: items, orderKey: orderKey, defaultOrder: defaultOrder, sortKeys: sortKeys,
                  message: message, header: { _ in EmptyView() }, row: row)
    }
}

/// The top of a playlist, album, artist or podcast page: its cover, name and
/// subtitle, then `buttons`, such as `PlayButtons`. Without an item, only the buttons.
struct ListHeader<Buttons: View>: View {
    let item: SpotifyItem?
    @ViewBuilder var buttons: () -> Buttons

    var body: some View {
        Section {
            VStack(spacing: 12) {
                if let item {
                    Artwork(url: item.imageURL, round: item.kind == .artist, cornerRadius: 10)
                        .frame(width: 220, height: 220)
                        .shadow(radius: 12)
                    Text(item.name).font(.title2.bold()).multilineTextAlignment(.center)
                    Text(item.subtitle).foregroundStyle(.secondary)
                }
                buttons()
            }
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(item == nil ? EdgeInsets() : nil)
    }
}

/// A row of glass chips that scrolls sideways, as in Spotify, so every choice
/// keeps its full name. The chosen one is green.
struct FilterChips<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button(label(option)) { selection = option }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(GlassChip(isSelected: selection == option))
                        .accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }
}

/// Spotify's sort choice: choose a key, and choose it again to turn the direction.
/// The arrow shows the direction of the chosen key.
struct SortMenu: View {
    @Binding var order: ListOrder
    let keys: [ListOrder.Key]

    var body: some View {
        Menu {
            Section("Sort by") {
                ForEach(keys, id: \.self) { key in
                    Button {
                        order = order.choosing(key)
                    } label: {
                        if key == order.key, key != .custom {
                            Label(key.label, systemImage: order.ascending ? "arrow.up" : "arrow.down")
                        } else {
                            Text(key.label)
                        }
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .menuActionDismissBehavior(.disabled)
    }
}
