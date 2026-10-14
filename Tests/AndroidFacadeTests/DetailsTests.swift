import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SpaceAPI
import SpacePushClient
import Testing
@testable import SpaceStateAndroidFacade

struct AndroidDetailsTests {
    private let endpoint = "https://space.example/api"
    private func value(_ info: SpaceInfo) -> Space { Space(endpoint: endpoint, info: info) }
    private func decode(_ raw: String) throws -> SpaceInfo { try JSONDecoder().decode(SpaceInfo.self, from: Data(raw.utf8)) }

    @Test func absentDetailsExportEmptyCollectionsWithoutChangingStatus() {
        let space = value(SpaceInfo(name: "A", state: .init(open: true, lastChange: nil, message: nil, triggerPerson: nil)))
        #expect(space.status == .open)
        #expect(space.details.contacts.isEmpty)
        #expect(space.details.keyholders.isEmpty)
        #expect(space.details.feeds.isEmpty)
        #expect(space.details.projects.isEmpty)
        #expect(space.details.links.isEmpty)
        #expect(space.details.linkedSpaces.isEmpty)
        #expect(space.details.latitude == nil)
    }

    @Test func locationMetadataAndCoordinatesArePreserved() {
        let details = value(SpaceInfo(name: "A", location: .init(address: "Street", latitude: 53.1, longitude: 8.2,
            timezone: "Europe/Berlin", countryCode: "DE", hint: " Ring the bell "))).details
        #expect(details.accessHint == "Ring the bell")
        #expect(details.countryCode == "DE")
        #expect(details.timezone == "Europe/Berlin")
        #expect(details.latitude == 53.1 && details.longitude == 8.2)
    }

    @Test func invalidOrUnpairedCoordinatesDoNotExportAMapTarget() {
        for (lat, lon): (Double?, Double?) in [(nil, 8), (53, nil), (.nan, 8), (53, .infinity), (91, 8), (53, -181)] {
            let details = value(SpaceInfo(name: "A", location: .init(address: nil, latitude: lat, longitude: lon, timezone: nil))).details
            #expect(details.latitude == nil && details.longitude == nil)
        }
    }

    @Test func everyContactKindHasAStableIdentifier() {
        let contact = SpaceInfo.Contact(email: " mail@example.org ", phone: "+49 123", irc: "ircs://chat.example/#a",
            mailingList: "list@example.org", matrix: "#a:example.org", mastodon: "@a@example.org", xmpp: "a@example.org",
            mumble: "mumble://voice.example", sip: "sip:a@example.org", issueMail: "issue@example.org", gopher: "gopher://g.example")
        let fields = value(SpaceInfo(name: "A", contact: contact)).details.contacts
        #expect(fields.map(\.kind) == ["email", "phone", "irc", "mailingList", "matrix", "mastodon", "xmpp", "mumble", "sip", "issueMail", "gopher"])
        #expect(fields.first?.value == "mail@example.org")
    }

    @Test func emptyContactsAreDroppedWhileUnlinkableTextRemainsReadable() {
        let details = value(SpaceInfo(name: "A", contact: .init(email: " ", phone: "Ask at the door", matrix: ""))).details
        #expect(details.contacts.count == 1)
        #expect(details.contacts[0].kind == "phone")
        #expect(details.contacts[0].value == "Ask at the door")
    }

    @Test func keyholderNamesNicknamesAndContactKindsStayTogether() {
        let contact = SpaceInfo.Contact(keymasters: [.init(name: " "), .init(name: "Ada", ircNick: "ada",
            phone: "+49 123", email: "ada@example.org", xmpp: "ada@example.org", mastodon: "@ada@example.org", matrix: "@ada:example.org")])
        let people = value(SpaceInfo(name: "A", contact: contact)).details.keyholders
        #expect(people.count == 1)
        #expect(people[0].name == "Ada" && people[0].ircNick == "ada")
        #expect(people[0].contacts.map(\.kind) == ["email", "phone", "matrix", "mastodon", "xmpp"])
    }

    @Test func validFeedsKeepTheirKindsAndFormatsIndependently() {
        let feeds = SpaceInfo.Feeds(blog: .init(url: URL(string: "https://a.example/blog")!, type: " atom "),
            wiki: .init(url: URL(string: "file:///tmp/wiki")!, type: "rss"),
            calendar: .init(url: URL(string: "https://a.example/calendar?key=one&b=two")!, type: "ical"))
        let exported = value(SpaceInfo(name: "A", feeds: feeds)).details.feeds
        #expect(exported.map(\.kind) == ["blog", "calendar"])
        #expect(exported[0].format == "atom")
        #expect(exported[1].url == "https://a.example/calendar?key=one&b=two")
    }

    @Test func unsafeProjectAndNamedLinksDoNotHideValidNeighbours() {
        let info = SpaceInfo(name: "A", projects: [URL(string: "https://a.example/project")!, URL(string: "https://u:p@a.example/")!],
            links: [.init(name: " Good ", description: " Description ", url: URL(string: "https://a.example/good")!),
                .init(name: " ", url: URL(string: "https://a.example/blank")!), .init(name: "Bad", url: URL(string: "file:///tmp/a")!)])
        let details = value(info).details
        #expect(details.projects == ["https://a.example/project"])
        #expect(details.links.count == 1)
        #expect(details.links[0].name == "Good" && details.links[0].summary == "Description")
    }

    @Test func linkedSpaceFieldsAreValidatedSeparately() {
        let good = URL(string: "http://localhost:8080/api")!
        let website = URL(string: "https://a.example/")!
        let bad = URL(string: "https://u:p@a.example/api")!
        let details = value(SpaceInfo(name: "A", linkedSpaces: [.init(endpoint: good, website: website),
            .init(endpoint: bad, website: website), .init(endpoint: bad, website: nil)])).details
        #expect(details.linkedSpaces.count == 2)
        #expect(details.linkedSpaces[0].apiEndpoint == good.absoluteString)
        #expect(details.linkedSpaces[1].apiEndpoint == nil && details.linkedSpaces[1].website == website.absoluteString)
    }

    @Test func malformedOptionalRecordsCannotDiscardTheSpaceState() throws {
        let info = try decode(#"{"space":"A","state":{"open":true},"location":{"hint":3,"country_code":[]},"contact":{"email":"a@example.org","keymasters":[false,{"name":"Ada"}]},"feeds":{"blog":false,"calendar":{"url":"https://a.example/c"}},"projects":[42,"https://a.example/p"],"links":[null,{"name":"Good","url":"https://a.example/l"}],"linked_spaces":[{}, {"website":"https://a.example/"}]}"#)
        let space = value(info)
        #expect(space.status == .open)
        #expect(space.details.accessHint == nil)
        #expect(space.details.contacts.count == 1 && space.details.keyholders.count == 1)
        #expect(space.details.feeds.count == 1 && space.details.projects.count == 1)
        #expect(space.details.links.count == 1 && space.details.linkedSpaces.count == 1)
    }

    @Test func detailsDoNotInventAnUnknownOpeningState() {
        let space = value(SpaceInfo(name: "A", location: .init(address: "Street", latitude: 1, longitude: 2, timezone: nil, hint: "Ring")))
        #expect(space.status == .unknown)
        #expect(space.details.accessHint == "Ring")
        #expect(space.lastChange == nil)
    }

    @Test func legacyAndObservedReadsBothExportDetailsWithoutRestampingEvidence() async throws {
        let receipt = Date(timeIntervalSince1970: 1000)
        let direct = StatusClient(now: { receipt }, load: { request in
            (Data(#"{"space":"A","state":{"open":true,"lastchange":1},"location":{"hint":"Ring","lat":53,"lon":8}}"#.utf8),
             HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let service = SpaceStateService(service: StatusService(spacePush: nil, direct: direct))
        #expect(try await service.space(endpoint: endpoint).details.accessHint == "Ring")
        let observed = try await service.spaceObservation(endpoint: endpoint)
        #expect(observed.value.details.accessHint == "Ring")
        #expect(observed.value.lastChange == 1)
        #expect(observed.timing.observedAt == 1000 && observed.timing.receivedAt == 1000)
    }
}
