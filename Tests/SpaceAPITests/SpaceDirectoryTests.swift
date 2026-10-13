import Foundation
import Testing
@testable import SpaceAPI

struct SpaceDirectoryTests {
    @Test func skipsInvalidEndpointEntriesIndividually() throws {
        let urls = ["https://space.example/api", "http://localhost/status", "file:///tmp/status",
                    "https://user:secret@space.example/api", "https://space.example/api\n",
                    "https://space.example/%0A", "api/status", "https://space.example:65536/api"]
        let json = try JSONSerialization.data(withJSONObject: urls.map { ["url": $0, "data": ["space": $0]] })
        let entries = try SpaceDirectory.decode(json)
        #expect(Set(entries.map(\.endpoint.absoluteString)) == Set(urls.prefix(2)))
    }

    @Test func decodesAggregatorAndSkipsEntriesWithoutData() throws {
        let entries = try SpaceDirectory.decode(Fixture.data("aggregator"))

        #expect(entries.map(\.info.name) == [
            "Apollo-NG", "B4CKSP4CE", "Hacker Embassy", "LuXeria",
            "Mainframe", "Milton Keynes Makerspace", "Nerd2Nerd",
        ])
        #expect(!entries.contains { $0.endpoint.host() == "blog.attraktor.org" })
    }

    @Test func mapsStatusOfEachEntry() throws {
        let entries = try SpaceDirectory.decode(Fixture.data("aggregator"))
        let status = Dictionary(uniqueKeysWithValues: entries.map { ($0.info.name, $0.info.status) })

        #expect(status == [
            "Apollo-NG": .closed,
            "B4CKSP4CE": .unknown,
            "Hacker Embassy": .closed,
            "LuXeria": .unknown,
            "Mainframe": .open,
            "Milton Keynes Makerspace": .unknown,
            "Nerd2Nerd": .open,
        ])
    }

    @Test func keepsEndpointAndLastSeen() throws {
        let entries = try SpaceDirectory.decode(Fixture.data("aggregator"))
        let mainframe = try #require(entries.first { $0.info.name == "Mainframe" })

        #expect(mainframe.endpoint == URL(string: "https://status.mainframe.io/api/spaceInfo"))
        #expect(mainframe.lastSeen != nil)
    }

    @Test func survivesBrokenEntries() throws {
        let json = #"[42, {"url":"https://a.example/space.json","data":{"space":"A"}}, {"url":"https://b.example","data":"oops"}]"#
        let entries = try SpaceDirectory.decode(Data(json.utf8))

        #expect(entries.map(\.info.name) == ["A"])
    }
}
