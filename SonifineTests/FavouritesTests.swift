import Foundation
import Testing
@testable import Sonifine

/// The favourite stations: kept in the user's order across launches.
@MainActor
struct FavouritesTests {
    /// The storage of one installation; each test has its own.
    private let defaults = UserDefaults(suiteName: "FavouritesTests-\(UUID())")!

    private func stream(_ name: String) -> Favourite {
        Favourite(name: name, source: .stream(URL(string: "https://example.com/\(name).mp3")!))
    }

    @Test func theFirstLaunchFillsInDutchStreamsWithLogos() {
        let favourites = Favourites(defaults: defaults)

        #expect(favourites.all.count == 13)
        #expect(favourites.all.prefix(3).map(\.name) == ["NPO Radio 1", "NPO Radio 2", "BNR Nieuwsradio"])
        #expect(favourites.all.allSatisfy { $0.logoURL != nil })
        #expect(favourites.all.allSatisfy { if case .stream(let url) = $0.source { url.scheme == "https" } else { false } })
    }

    @Test func removedSeedsStayRemovedOnTheNextLaunch() {
        let favourites = Favourites(defaults: defaults)
        favourites.remove(atOffsets: IndexSet(integersIn: 0..<favourites.all.count))

        #expect(Favourites(defaults: defaults).all.isEmpty)
    }

    @Test func addingMovingEditingAndRemovingLastAcrossLaunches() throws {
        let favourites = Favourites(defaults: defaults)
        favourites.remove(atOffsets: IndexSet(integersIn: 0..<favourites.all.count))
        favourites.add(stream("A"))
        favourites.add(stream("B"))
        favourites.add(stream("C"))

        favourites.move(fromOffsets: [2], toOffset: 0)
        var renamed = try #require(favourites.all.last)
        renamed.name = "B2"
        renamed.logoURL = URL(string: "https://example.com/b.png")
        favourites.update(renamed)
        favourites.remove(favourites.all[1])

        let relaunched = Favourites(defaults: defaults).all
        #expect(relaunched.map(\.name) == ["C", "B2"])
        #expect(relaunched.last == renamed)
    }

    @Test func aSonosRadioStationIsAddedOnceAndTakenOutAgain() throws {
        let favourites = Favourites(defaults: defaults)
        let npo2 = try #require(RadioItem(id: "tunein:5668", itemType: "stream", name: "NPO Radio 2",
                                          imageURL: URL(string: "https://cdn-radiotime-logos.tunein.com/s9483g.png")))

        favourites.toggle(npo2)
        #expect(favourites.contains(npo2))
        #expect(favourites.all.last?.source == .sonosRadio("tunein:5668"))
        #expect(favourites.all.last?.logoURL == npo2.imageURL)

        favourites.toggle(npo2)
        #expect(!favourites.contains(npo2))
        #expect(favourites.all.count == 13)
    }

    @Test func aCategoryIsNoFavourite() throws {
        let favourites = Favourites(defaults: defaults)
        let music = try #require(RadioItem(id: "/genres/en-US/NL", itemType: "container", name: "Music", imageURL: nil))

        favourites.toggle(music)

        #expect(favourites.all.count == 13)
    }
}

/// What the custom stream form accepts before it asks the address for audio.
struct StreamCheckTests {
    @Test func aStreamAddressIsHTTPOrHTTPSWithAHost() throws {
        #expect(try StreamCheck.address("  https://stream.bnr.nl/bnr_mp3_128_20\n").absoluteString
                == "https://stream.bnr.nl/bnr_mp3_128_20")
        #expect(try StreamCheck.address("http://icecast.omroep.nl/radio1-bb-mp3").scheme == "http")
        for text in ["", "stream.bnr.nl/bnr_mp3_128_20", "ftp://example.com/radio.mp3", "https://", "NPO Radio 1"] {
            #expect(throws: AppError.self, "\(text)") { try StreamCheck.address(text) }
        }
    }

    @Test func audioIsAStream() {
        #expect(StreamCheck.problem(status: 200, contentType: "audio/mpeg") == nil)
        #expect(StreamCheck.problem(status: 200, contentType: "audio/aacp; charset=utf-8") == nil)
        #expect(StreamCheck.problem(status: 200, contentType: "application/ogg") == nil)
    }

    @Test func aWebPageAPlaylistOrAnErrorIsNoStream() {
        #expect(StreamCheck.problem(status: 200, contentType: "text/html")
                == "This address gives text/html, not audio.")
        #expect(StreamCheck.problem(status: 200, contentType: "audio/x-mpegurl")?.contains("playlist") == true)
        #expect(StreamCheck.problem(status: 200, contentType: "application/vnd.apple.mpegurl")?.contains("playlist") == true)
        #expect(StreamCheck.problem(status: 404, contentType: "audio/mpeg") == "The address answers with error 404.")
        #expect(StreamCheck.problem(status: 200, contentType: nil) == "This address gives no audio.")
    }
}
