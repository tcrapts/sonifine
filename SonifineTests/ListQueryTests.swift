import Foundation
import Testing
@testable import Sonifine

/// Search, filter and sort of every list: what the user sees after typing,
/// choosing a chip or choosing a sort.
struct ListQueryTests {
    private func song(_ id: String, _ name: String, by artist: String, album: String? = nil, added: Date? = nil) -> SpotifyItem {
        var item = SpotifyItem(uri: SpotifyURI("spotify:track:\(id)")!, name: name, subtitle: artist, imageURL: nil)
        item.album = album
        item.addedAt = added
        return item
    }

    private var songs: [SpotifyItem] {
        [song("A", "Yellow", by: "Coldplay", album: "Parachutes"),
         song("B", "Café del Mar", by: "Energy 52", album: "Café del Mar"),
         song("C", "Clocks", by: "Coldplay", album: "A Rush of Blood to the Head"),
         song("D", "Hallelujah", by: "Jeff Buckley", album: "Grace")]
    }

    @Test func searchMatchesTitleArtistAndAlbumWhateverTheCaseOrAccents() {
        #expect(ListQuery(text: "cafe").apply(to: songs).map(\.name) == ["Café del Mar"])
        #expect(ListQuery(text: "COLDPLAY").apply(to: songs).map(\.name) == ["Yellow", "Clocks"])
        #expect(ListQuery(text: "grace").apply(to: songs).map(\.name) == ["Hallelujah"], "the album counts")
        #expect(ListQuery(text: "coldplay clo").apply(to: songs).map(\.name) == ["Clocks"], "every word must match")
        #expect(ListQuery(text: "  ").apply(to: songs).count == 4)
        #expect(ListQuery(text: "metallica").apply(to: songs).isEmpty)
    }

    @Test func searchAndSortTogetherGiveTheSongsThatPlay() {
        let query = ListQuery(text: "coldplay", order: ListOrder.custom.choosing(.title))
        let shown = query.apply(to: songs)

        #expect(shown.map(\.name) == ["Clocks", "Yellow"])
        #expect(query.rearranges)
        let tap = PlayRequest.tap(shown[1], in: shown)
        #expect(tap == .songs(shown.map(\.uri), start: 1, shuffle: false), "a tap plays the songs shown, in that order")
    }

    @Test func onlyAListAsItCameKeepsItsPlaylistOrder() {
        #expect(!ListQuery().rearranges)
        #expect(ListQuery(text: "a").rearranges)
        #expect(ListQuery(kind: "Songs").rearranges)
        #expect(ListQuery(order: .newestFirst).rearranges)
    }

    @Test func theFilterShowsOneKindAndOnlyListsWithTwoKindsHaveOne() throws {
        let station = try #require(RadioItem(id: "tunein:5668", itemType: nil, name: "NPO Radio 1", imageURL: nil))
        let genre = try #require(RadioItem(id: "/genres/NL", itemType: "container", name: "Pop", imageURL: nil))
        let other = try #require(RadioItem(id: "sonos:2997", itemType: nil, name: "Radio 538", imageURL: nil))
        let mixed = [station, genre, other]

        #expect(ListQuery.kinds(in: mixed) == ["Stations", "Categories"])
        #expect(ListQuery(kind: "Stations").apply(to: mixed).map(\.name) == ["NPO Radio 1", "Radio 538"])
        #expect(ListQuery.kinds(in: songs) == ["Songs"])
    }

    @Test func aSortChoiceOnlyShowsWhenTheListHasItsData() {
        let all: [ListOrder.Key] = [.custom, .title, .artist, .album, .added]
        let playlists = [SpotifyItem(uri: SpotifyURI("spotify:playlist:P")!, name: "Mix", subtitle: "Spotify", imageURL: nil)]

        #expect(ListOrder.keys(all, for: playlists) == [.custom, .title, .artist])
        #expect(ListOrder.keys(all, for: songs) == [.custom, .title, .artist, .album])
    }

    @Test func episodesSortByReleaseNewestFirstThenOldest() {
        func episode(_ id: String, released: Date?) -> SpotifyItem {
            var item = SpotifyItem(uri: SpotifyURI("spotify:episode:\(id)")!, name: id, subtitle: "", imageURL: nil)
            item.episode = .init(released: released, duration: 60)
            return item
        }
        let episodes = [episode("Middle", released: Date(timeIntervalSince1970: 200)),
                        episode("Undated", released: nil),
                        episode("Newest", released: Date(timeIntervalSince1970: 300)),
                        episode("Oldest", released: Date(timeIntervalSince1970: 100))]

        let newestFirst = ListOrder.custom.choosing(.released)
        #expect(newestFirst.apply(to: episodes).map(\.name) == ["Newest", "Middle", "Oldest", "Undated"])
        #expect(newestFirst.choosing(.released).apply(to: episodes).map(\.name) == ["Oldest", "Middle", "Newest", "Undated"])
    }

    @Test func theSortChoiceSurvivesBeingStored() {
        let order = ListOrder.custom.choosing(.album).choosing(.album)
        #expect(ListOrder(rawValue: order.rawValue) == ListOrder(key: .album, ascending: false))
        #expect(ListOrder(rawValue: "added descending") == .newestFirst, "a choice stored before every list could sort")
    }
}
