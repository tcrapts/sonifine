import Foundation
import Testing
@testable import Sonifine

/// The state policy of the Sonos controller, against a fake player.
@MainActor
struct SonosControllerTests {
    private let speaker = URL(string: "http://10.0.0.2:1400")!
    private let fake = FakeSonosPlayer()
    private let defaults = UserDefaults(suiteName: "SonosControllerTests-\(UUID())")!

    private func controller(groups: [SonosGroup]? = nil) async -> SonosController {
        fake.groups = groups ?? [SonosGroup(id: "RINCON_K", name: "Kitchen", coordinator: speaker, roomIDs: ["RINCON_K"])]
        let controller = SonosController(makePlayer: { _ in fake }, defaults: defaults)
        controller.found([speaker])
        await controller.loadGroups()
        return controller
    }

    private func settle(_ controller: SonosController) async {
        while controller.isSendingVolume { await Task.yield() }
    }

    @Test func quickPressesTravelAsOneChange() async {
        let controller = await controller()
        fake.status.volume = 20
        await controller.refresh()
        controller.stepSize = 2

        for _ in 0..<5 { controller.nudgeVolume(1) }
        await settle(controller)

        #expect(fake.adjustments == [10])
        #expect(controller.selectedStatus.volume == 30)
        #expect(controller.volumeButtonPresses == 5)
    }

    @Test func aPollThatStartedBeforeAChangeDoesNotUndoIt() async {
        let controller = await controller()
        fake.status.volume = 50
        fake.statusDelay = .milliseconds(200)
        let poll = Task { await controller.refresh() }
        try? await Task.sleep(for: .milliseconds(50))

        await controller.setVolume(20, of: controller.groups[0])
        await poll.value

        #expect(controller.selectedStatus.volume == 20)
    }

    @Test func aSongInAPlaylistStartsWhereSonosQueuedIt() async {
        let controller = await controller()
        let start = SpotifyURI("spotify:track:C")!
        // The Web API leaves out a podcast that Sonos keeps, so the song is fourth here.
        fake.queueEntries = ["A", "podcast", "B", "C"].enumerated().map { index, id in
            QueueEntry(id: index, title: id, artist: "", artworkURL: nil, spotifyTrack: SpotifyURI("spotify:track:\(id)"))
        }

        await controller.play(.collection(SpotifyURI("spotify:playlist:P")!, start: start, shuffle: false))

        #expect(fake.queuedItems.count == 1)
        #expect(fake.seeks == [4])
        #expect(fake.plays == 1)
    }

    @Test func shuffleNeverJumpsToASong() async {
        let controller = await controller()
        await controller.play(.songs([song("A").uri, song("B").uri], start: 1, shuffle: true))

        #expect(fake.seeks.isEmpty)
        #expect(fake.playModes.last == PlayMode(shuffle: true, repeatMode: .off))
    }

    @Test func somethingSonosCantPlayLeavesTheQueueAlone() async {
        let controller = await controller()
        await controller.play(.songs([SpotifyURI("spotify:episode:E")!], start: 0, shuffle: false))

        #expect(fake.queuedItems.isEmpty)
        #expect(controller.errorMessage == "Sonos can't play this.")
    }

    @Test func anItemSonosCantOpenGetsAPlainMessage() async {
        let controller = await controller()
        fake.failure = AppError("AddMultipleURIsToQueue failed (error 804)", code: 804)

        await controller.play(.collection(SpotifyURI("spotify:playlist:Empty")!, start: nil, shuffle: false))

        #expect(controller.errorMessage?.hasPrefix("Sonos can't play this. Is it empty") == true)
    }

    @Test func playNextGoesRightAfterTheCurrentSong() async {
        let controller = await controller()
        fake.status.queuePosition = 7
        await controller.refresh()

        await controller.addToQueue(song("A").uri, next: true)
        await controller.addToQueue(song("B").uri, next: false)

        #expect(fake.additions.map(\.after) == [7, nil])
        #expect(controller.notice == "Added to the queue")
    }

    @Test func theChosenRoomStaysChosenWhenItJoinsAnotherGroup() async {
        let kitchen = SonosGroup(id: "RINCON_K", name: "Kitchen", coordinator: speaker, roomIDs: ["RINCON_K"])
        let bedroom = SonosGroup(id: "RINCON_B", name: "Bedroom", coordinator: speaker, roomIDs: ["RINCON_B"])
        let controller = await controller(groups: [bedroom, kitchen])
        controller.select(bedroom)

        fake.groups = [SonosGroup(id: "RINCON_K", name: "Kitchen + 1", coordinator: speaker,
                                  roomIDs: ["RINCON_K", "RINCON_B"])]
        await controller.loadGroups()

        #expect(controller.selectedGroup?.name == "Kitchen + 1")
    }
}

/// The SOAP adapter speaks the protocol a Sonos player expects.
@MainActor
struct SOAPSonosPlayerTests {
    @Test func fillsTheQueueSixteenItemsAtATime() async throws {
        let recorded = RecordedTransport()
        recorded.answer(soapAction: "RemoveAllTracksFromQueue", (200, soapAnswer("RemoveAllTracksFromQueue", "")))
        for _ in 0..<3 {
            recorded.answer(soapAction: "AddMultipleURIsToQueue",
                            (200, soapAnswer("AddMultipleURIsToQueue", "<NumTracksAdded>16</NumTracksAdded>")))
        }
        recorded.answer(soapAction: "SetAVTransportURI", (200, soapAnswer("SetAVTransportURI", "")))
        let player = SOAPSonosPlayer(address: URL(string: "http://10.0.0.2:1400")!, transport: recorded.transport)
        let items = (0..<40).compactMap { SpotifyURI("spotify:track:T\($0)")?.queueItem(account: .default) }

        let added = try await player.replaceQueue(with: items, groupID: "RINCON_K")

        #expect(recorded.count(soapAction: "AddMultipleURIsToQueue") == 3)
        #expect(added == 48)
        #expect(recorded.requests.last?.bodyText.contains("x-rincon-queue:RINCON_K#0") == true)
        #expect(recorded.requests[1].bodyText.contains("<NumberOfURIs>16</NumberOfURIs>"))
    }

    @Test func playNextAsksSonosForThePlaceAfterTheCurrentSong() async throws {
        let recorded = RecordedTransport()
        recorded.answer(soapAction: "AddMultipleURIsToQueue",
                        (200, soapAnswer("AddMultipleURIsToQueue", "<NumTracksAdded>1</NumTracksAdded>")))
        let player = SOAPSonosPlayer(address: URL(string: "http://10.0.0.2:1400")!, transport: recorded.transport)
        let item = try #require(SpotifyURI("spotify:track:A")?.queueItem(account: .default))

        _ = try await player.addToQueue([item], after: 7)

        let body = recorded.requests[0].bodyText
        #expect(body.contains("<DesiredFirstTrackNumberEnqueued>8</DesiredFirstTrackNumberEnqueued>"))
        #expect(body.contains("<EnqueueAsNext>1</EnqueueAsNext>"))
    }

    @Test func aFaultCarriesTheSonosErrorCode() async {
        let recorded = RecordedTransport()
        recorded.answer(soapAction: "Play", (500, """
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault>\
            <faultcode>s:Client</faultcode><detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0">\
            <errorCode>701</errorCode></UPnPError></detail></s:Fault></s:Body></s:Envelope>
            """))
        let player = SOAPSonosPlayer(address: URL(string: "http://10.0.0.2:1400")!, transport: recorded.transport)

        await #expect(throws: AppError("Play failed on 10.0.0.2 (error 701)", code: 701)) {
            try await player.play()
        }
    }
}
