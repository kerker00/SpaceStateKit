import Foundation
import Testing
@testable import SpaceAPI

struct SpaceInfoTests {
    @Test func decodesMainframeEndpoint() throws {
        let info = try JSONDecoder().decode(SpaceInfo.self, from: Fixture.data("mainframe-spaceinfo"))

        #expect(info.name == "Mainframe")
        #expect(info.status == .open)
        #expect(info.state?.message == "Open!")
        #expect(info.state?.lastChange == Date(timeIntervalSince1970: 1_791_483_594))
        #expect(info.location?.address == "Bahnhofsplatz 10, 26122 Oldenburg, Germany")
        #expect(info.location?.latitude == 53.14402)
        #expect(info.contact.email == "vorstand@kreativitaet-trifft-technik.de")
        #expect(info.calendar != nil)
    }

    @Test(arguments: [
        (#"{"space":"A","state":{"open":true}}"#, SpaceStatus.open),
        (#"{"space":"A","state":{"open":false}}"#, .closed),
        (#"{"space":"A","state":{"open":null}}"#, .unknown),
        (#"{"space":"A","state":{"message":"ask on chat"}}"#, .unknown),
        (#"{"space":"A"}"#, .unknown),
        (#"{"space":"A","state":{"open":"yes"}}"#, .unknown),
        (#"{"space":"A","open":true,"lastchange":1}"#, .open),
    ])
    func mapsState(json: String, expected: SpaceStatus) throws {
        let info = try JSONDecoder().decode(SpaceInfo.self, from: Data(json.utf8))
        #expect(info.status == expected)
    }

    @Test func readsFlatLegacyLayout() throws {
        let json = #"{"space":"A","open":false,"lastchange":10,"status":"gone","address":"Street 1","lat":1.5,"lon":2.5}"#
        let info = try JSONDecoder().decode(SpaceInfo.self, from: Data(json.utf8))

        #expect(info.state == SpaceInfo.State(open: false, lastChange: Date(timeIntervalSince1970: 10), message: "gone", triggerPerson: nil))
        #expect(info.location == SpaceInfo.Location(address: "Street 1", latitude: 1.5, longitude: 2.5, timezone: nil))
    }

    @Test func toleratesMalformedOptionalFields() throws {
        let json = #"{"space":"A","logo":42,"location":"nowhere","contact":[],"feeds":{"calendar":"x"},"state":{"open":true,"lastchange":"soon"}}"#
        let info = try JSONDecoder().decode(SpaceInfo.self, from: Data(json.utf8))

        #expect(info.status == .open)
        #expect(info.state?.lastChange == nil)
        #expect(info.logo == nil)
        #expect(info.location == nil)
        #expect(info.contact == SpaceInfo.Contact())
        #expect(info.calendar == nil)
    }

    @Test func requiresName() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SpaceInfo.self, from: Data(#"{"state":{"open":true}}"#.utf8))
        }
    }
}
