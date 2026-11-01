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

    @Test func theCoversToLoadAheadAreThoseOfTheNextThreeSongs() async {
        let controller = await controller()
        fake.queueEntries = (0..<6).map { index in
            QueueEntry(id: index, title: "\(index)", artist: "",
                       artworkURL: URL(string: "http://10.0.0.2:1400/getaa?\(index)"), spotifyTrack: nil)
        }
        fake.status.queuePosition = 2  // the second song plays
        await controller.refresh()

        let covers = await controller.upcomingArtwork()

        #expect(covers.map(\.query) == ["2", "3", "4"])
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

/// Sound settings belong to a room, so they skip the coordinator.
@MainActor
struct RoomSoundTests {
    private let kitchenSpeaker = URL(string: "http://10.0.0.2:1400")!
    private let livingRoomSpeaker = URL(string: "http://10.0.0.3:1400")!
    private let kitchenPlayer = FakeSonosPlayer()
    private let livingRoomPlayer = FakeSonosPlayer()

    /// Kitchen leads Living Room; each room has its own player.
    private func controller() async -> (SonosController, kitchen: SonosRoom, livingRoom: SonosRoom) {
        let kitchen = SonosRoom(id: "RINCON_K", name: "Kitchen", address: kitchenSpeaker, devices: [kitchenSpeaker])
        let livingRoom = SonosRoom(id: "RINCON_L", name: "Living Room", address: livingRoomSpeaker,
                                   devices: [livingRoomSpeaker])
        kitchenPlayer.groups = [SonosGroup(id: "RINCON_K", name: "Kitchen + 1", coordinator: kitchenSpeaker,
                                           rooms: [kitchen, livingRoom])]
        let players = [kitchenSpeaker: kitchenPlayer, livingRoomSpeaker: livingRoomPlayer]
        let controller = SonosController(makePlayer: { players[$0]! },
                                         defaults: UserDefaults(suiteName: "RoomSoundTests-\(UUID())")!)
        controller.found([kitchenSpeaker])
        await controller.loadGroups()
        return (controller, kitchen, livingRoom)
    }

    @Test func aChangeGoesToTheRoomsOwnPlayer() async throws {
        let (controller, _, livingRoom) = await controller()
        let room = try #require(controller.rooms.first { $0.id == livingRoom.id })

        await controller.change([.bass(4)], of: room)

        #expect(livingRoomPlayer.sound.bass == 4)
        #expect(kitchenPlayer.sound.bass == 0, "the coordinator keeps its own bass")
    }

    @Test func resetToDefaultFlattensTheSoundAndTurnsLoudnessOn() async {
        let (controller, kitchen, _) = await controller()
        kitchenPlayer.sound = SoundSettings(bass: -3, treble: 6, loudness: false, trueplay: true)

        await controller.change(SoundSettings.defaults, of: kitchen)

        #expect(kitchenPlayer.sound == SoundSettings(bass: 0, treble: 0, loudness: true, trueplay: true))
    }

    @Test func aRefusedChangeNamesTheRoom() async {
        let (controller, _, livingRoom) = await controller()
        livingRoomPlayer.failure = AppError("SetBass failed on 10.0.0.3 (error 402)", code: 402)

        let changed = await controller.change([.bass(2)], of: livingRoom)

        #expect(!changed)
        #expect(controller.errorMessage?.hasPrefix("Couldn't change the sound of Living Room") == true)
    }

    @Test func devicesLeaveOutAPlayerThatDoesNotAnswer() async {
        let (controller, kitchen, _) = await controller()
        kitchenPlayer.description = SonosDevice(id: "RINCON_K", name: "Bookshelf", model: "S21", serialNumber: "",
                                                softwareVersion: "", hardwareVersion: "", ipAddress: "10.0.0.2")
        let pair = SonosRoom(id: kitchen.id, name: kitchen.name, address: kitchenSpeaker,
                             devices: [kitchenSpeaker, livingRoomSpeaker])

        let devices = await controller.devices(in: pair)

        #expect(devices.map(\.id) == ["RINCON_K"])
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

    /// An answer in the format the Symfonisk sends, with other values.
    private func renderingControlAnswer(_ action: String, _ body: String) -> RecordedTransport.Answer {
        (200, """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" \
        s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>\
        <u:\(action)Response xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">\(body)</u:\(action)Response>\
        </s:Body></s:Envelope>
        """)
    }

    @Test func readsTheSoundOfARoomFromItsRenderingControl() async throws {
        let recorded = RecordedTransport()
        recorded.answer(soapAction: "GetBass", renderingControlAnswer("GetBass", "<CurrentBass>-3</CurrentBass>"))
        recorded.answer(soapAction: "GetTreble", renderingControlAnswer("GetTreble", "<CurrentTreble>2</CurrentTreble>"))
        recorded.answer(soapAction: "GetLoudness",
                        renderingControlAnswer("GetLoudness", "<CurrentLoudness>1</CurrentLoudness>"))
        recorded.answer(soapAction: "GetRoomCalibrationStatus", renderingControlAnswer("GetRoomCalibrationStatus",
            "<RoomCalibrationEnabled>1</RoomCalibrationEnabled><RoomCalibrationAvailable>0</RoomCalibrationAvailable>"))
        let player = SOAPSonosPlayer(address: URL(string: "http://10.0.0.3:1400")!, transport: recorded.transport)

        let sound = try await player.soundSettings()

        #expect(sound == SoundSettings(bass: -3, treble: 2, loudness: true, trueplay: true))
        #expect(recorded.requests.allSatisfy {
            $0.url?.absoluteString == "http://10.0.0.3:1400/MediaRenderer/RenderingControl/Control"
        })
        #expect(recorded.requests.first { $0.soapAction == "GetLoudness" }?.bodyText
            .contains("<Channel>Master</Channel>") == true)
    }

    @Test func aPlayerWithoutTrueplayStillGivesItsSound() async throws {
        let recorded = RecordedTransport()
        recorded.answer(soapAction: "GetBass", renderingControlAnswer("GetBass", "<CurrentBass>0</CurrentBass>"))
        recorded.answer(soapAction: "GetTreble", renderingControlAnswer("GetTreble", "<CurrentTreble>0</CurrentTreble>"))
        recorded.answer(soapAction: "GetLoudness",
                        renderingControlAnswer("GetLoudness", "<CurrentLoudness>0</CurrentLoudness>"))
        let player = SOAPSonosPlayer(address: URL(string: "http://10.0.0.3:1400")!, transport: recorded.transport)

        let sound = try await player.soundSettings()

        #expect(sound.trueplay == nil)
        #expect(!sound.loudness)
    }

    @Test func soundChangesUseTheSonosArgumentNames() async throws {
        let recorded = RecordedTransport()
        for action in ["SetBass", "SetTreble", "SetLoudness"] {
            recorded.answer(soapAction: action, renderingControlAnswer(action, ""))
        }
        let player = SOAPSonosPlayer(address: URL(string: "http://10.0.0.3:1400")!, transport: recorded.transport)

        for setting in [SoundSetting.bass(-4), .treble(3), .loudness(false)] { try await player.change(setting) }

        let bodies = recorded.requests.map(\.bodyText)
        #expect(bodies[0].contains("<DesiredBass>-4</DesiredBass>"))
        #expect(bodies[1].contains("<DesiredTreble>3</DesiredTreble>"))
        #expect(bodies[2].contains("<Channel>Master</Channel><DesiredLoudness>0</DesiredLoudness>"))
    }

    @Test func readsTheDeviceFromItsDescriptionNotItsServices() async throws {
        // Shortened from the Symfonisk's /xml/device_description.xml.
        let description = """
        <?xml version="1.0" encoding="utf-8" ?>
        <root xmlns="urn:schemas-upnp-org:device-1-0"><device>
        <deviceType>urn:schemas-upnp-org:device:ZonePlayer:1</deviceType>
        <modelNumber>S21</modelNumber><modelName>SYMFONISK Bookshelf</modelName>
        <softwareVersion>86.10-81100</softwareVersion><hardwareVersion>1.20.3.3-2.0</hardwareVersion>
        <serialNum>00-0E-58-A0-B1-C2:0</serialNum><UDN>uuid:RINCON_000E58A0B1C201400</UDN>
        <roomName>Symfonisk</roomName><displayName>Bookshelf</displayName>
        <deviceList><device><deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
        <modelNumber>S21</modelNumber><UDN>uuid:RINCON_000E58A0B1C201400_MR</UDN></device></deviceList>
        </device></root>
        """
        let recorded = RecordedTransport()
        recorded.answer((200, description)) { $0.url?.path() == "/xml/device_description.xml" }
        let player = SOAPSonosPlayer(address: URL(string: "http://192.168.1.147:1400")!, transport: recorded.transport)

        let device = try await player.device()

        #expect(device == SonosDevice(id: "RINCON_000E58A0B1C201400", name: "Bookshelf", model: "S21",
                                      serialNumber: "00-0E-58-A0-B1-C2:0", softwareVersion: "86.10-81100",
                                      hardwareVersion: "1.20.3.3-2.0", ipAddress: "192.168.1.147"))
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
