import Foundation

struct SpotifyAccount {
    let serviceID: String
    let serialNumber: String
}

/// The URI and DIDL metadata with which a Sonos player queues a Spotify
/// playlist, album or track from its linked Spotify account.
struct SpotifyQueueItem {
    let uri: String
    let metadata: String

    init?(uri spotifyURI: String, account: SpotifyAccount) {
        let parts = spotifyURI.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify" else { return nil }
        let encoded = spotifyURI.replacingOccurrences(of: ":", with: "%3a")

        let itemID: String
        let upnpClass: String
        switch parts[1] {
        case "playlist":
            itemID = "1006206c" + encoded
            upnpClass = "object.container.playlistContainer"
            uri = "x-rincon-cpcontainer:" + itemID
        case "album":
            itemID = "1004206c" + encoded
            upnpClass = "object.container.album.musicAlbum"
            uri = "x-rincon-cpcontainer:" + itemID
        case "track":
            itemID = "10032020" + encoded
            upnpClass = "object.item.audioItem.musicTrack"
            uri = "x-sonos-spotify:\(encoded)?sid=\(account.serviceID)&flags=8224&sn=\(account.serialNumber)"
        default:
            return nil
        }

        // Sonos identifies the music service by its type: service ID × 256 + 7.
        let serviceType = (Int(account.serviceID) ?? 9) * 256 + 7
        metadata = """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
        xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" \
        xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">\
        <item id="\(itemID)" parentID="-1" restricted="true"><dc:title></dc:title>\
        <upnp:class>\(upnpClass)</upnp:class>\
        <desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">\
        SA_RINCON\(serviceType)_X_#Svc\(serviceType)-0-Token</desc></item></DIDL-Lite>
        """
    }
}
