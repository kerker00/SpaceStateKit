import Foundation
import Testing
@testable import SpaceAPI

struct SpaceInfoDetailsTests {
    private func decode(_ json: String) throws -> SpaceInfo {
        try JSONDecoder().decode(SpaceInfo.self, from: Data(json.utf8))
    }

    @Test func decodesV15Document() throws {
        let info = try JSONDecoder().decode(SpaceInfo.self, from: Fixture.data("leinelab-v15"))

        #expect(info.location?.countryCode == "DE")
        #expect(info.location?.hint?.hasPrefix("If sign is red") == true)
        #expect(info.state?.icon == SpaceInfo.Icon(
            open: URL(string: "https://leinelab.org/open.png")!, closed: URL(string: "https://leinelab.org/closed.png")!))
        #expect(info.feeds.calendar?.type == "ical")
        #expect(info.feeds.wiki == SpaceInfo.Feed(url: URL(string: "https://leinelab.org/feed.php")!, type: "rss"))
        #expect(info.feeds.blog == nil)
        #expect(info.calendar == info.feeds.calendar?.url)
        #expect(info.projects.map(\.absoluteString) == ["https://github.com/LeineLab", "https://git.leinelab.org/LeineLab-Public"])
        #expect(info.links.map(\.name) == ["Arduino Hannover", "Freifunk Hannover"])
        #expect(info.linkedSpaces == [SpaceInfo.LinkedSpace(
            endpoint: URL(string: "https://hannover.ccc.de/spaceapi.json"), website: URL(string: "https://hannover.ccc.de"))])
        #expect(info.contact.mumble == "mumble://leineserver.leinelab.org")
        #expect(info.contact.sip != nil)
        #expect(info.apiCompatibility == ["15"])
        #expect(info.legacyAPIVersion == nil)
    }

    @Test func decodesV14DocumentWithKeymasters() throws {
        let info = try JSONDecoder().decode(SpaceInfo.self, from: Fixture.data("chaosstuff-v14"))

        #expect(info.status == .closed)
        #expect(info.contact.keymasters.count == 6)
        #expect(info.contact.keymasters.allSatisfy { $0.name == "Keymaster" })
        #expect(info.contact.xmpp == "c3l@conference.c3l.lu")
        #expect(info.contact.issueMail == "contact@example.org")
        #expect(info.contact.matrix == "#c3l:matrix.c3l.lu")
        #expect(info.links.count == 3)
        #expect(info.linkedSpaces.isEmpty)
        #expect(info.location?.countryCode == nil)
        #expect(info.apiCompatibility == ["14"])
    }

    @Test func dropsOnlyTheBrokenParts() throws {
        let info = try JSONDecoder().decode(SpaceInfo.self, from: Fixture.data("broken-fields"))

        #expect(info.name == "Broken Fields Space")
        #expect(info.status == .open)
        #expect(info.location?.address == "Somewhere 1")
        #expect(info.location?.countryCode == nil)
        #expect(info.location?.hint == nil)
        // One unsafe link makes the icon pair unusable.
        #expect(info.state?.icon == nil)
        #expect(info.contact.email == "contact@example.org")
        #expect(info.contact.xmpp == nil)
        #expect(info.contact.keymasters == [
            SpaceInfo.Keymaster(name: "Keymaster", email: "keymaster@example.org"), SpaceInfo.Keymaster(name: "Second"),
        ])
        #expect(info.feeds.blog == nil)
        #expect(info.feeds.wiki == nil)
        #expect(info.feeds.calendar?.url.absoluteString == "https://broken.example/calendar.ics")
        #expect(info.projects.map(\.absoluteString) == ["https://broken.example/project"])
        #expect(info.links.map(\.name) == ["Good"])
        #expect(info.linkedSpaces.count == 1)
        // Not an array of strings: nothing is guessed.
        #expect(info.apiCompatibility.isEmpty)
    }

    @Test func readsOlderLayouts() throws {
        let info = try decode(#"""
            {"space":"A","api":"0.13","state":{"open":true},
             "icon":{"open":"https://a.example/open.png","closed":"https://a.example/closed.png"},
             "contact":{"jabber":"a@jabber.example"}}
            """#)

        #expect(info.legacyAPIVersion == "0.13")
        #expect(info.state?.icon?.open.absoluteString == "https://a.example/open.png")
        #expect(info.contact.xmpp == "a@jabber.example")

        let flat = try decode(#"{"space":"A","open":true,"icon":{"open":"https://a.example/o.png","closed":"https://a.example/c.png"}}"#)
        #expect(flat.state?.icon != nil)
        let stateIconWins = try decode(#"""
            {"space":"A","state":{"open":true,"icon":{"open":"https://new.example/o.png","closed":"https://new.example/c.png"}},
             "icon":{"open":"https://old.example/o.png","closed":"https://old.example/c.png"}}
            """#)
        #expect(stateIconWins.state?.icon?.open.host() == "new.example")
        // Without a state, an icon has nothing to illustrate.
        #expect(try decode(#"{"space":"A","icon":{"open":"https://a.example/o.png","closed":"https://a.example/c.png"}}"#).state == nil)
    }

    @Test func calendarStaysCompatible() {
        var info = SpaceInfo(name: "A", calendar: URL(string: "https://a.example/cal.ics"))
        #expect(info.feeds.calendar == SpaceInfo.Feed(url: URL(string: "https://a.example/cal.ics")!))
        info.feeds.calendar?.type = "ical"
        info.calendar = URL(string: "https://a.example/other.ics")
        #expect(info.feeds.calendar == SpaceInfo.Feed(url: URL(string: "https://a.example/other.ics")!, type: "ical"))
        info.calendar = nil
        #expect(info.feeds.calendar == nil)
    }
}
