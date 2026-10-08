import Foundation
import Testing
import SpaceAPI
@testable import MainframeStatus

struct MainframeTests {
    @Test func decodesRoomsInDisplayOrder() throws {
        let rooms = try Mainframe.decodeRooms(Fixture.data("mainframe-openstate"))

        #expect(rooms.map(\.id) == ["space", "radstelle", "lab3d", "machining"])
        #expect(rooms.map(\.state) == [.openPlus, .closed, .closed, .closed])
        #expect(rooms.first?.since == Date(timeIntervalSince1970: 1_791_483_594))
    }

    @Test func sortsUnknownRoomsLast() throws {
        let json = #"{"zeta":{"state":"open"},"alpha":{"state":"open"},"lab3d":{"state":"open"},"broken":{}}"#
        let rooms = try Mainframe.decodeRooms(Data(json.utf8))

        #expect(rooms.map(\.id) == ["lab3d", "alpha", "zeta"])
        #expect(rooms.map(\.name) == ["3D Lab", "alpha", "zeta"])
    }

    @Test(arguments: [
        ("none", MainframeRoomState.closed, SpaceStatus.closed),
        ("keyholder", .keyholder, .closed),
        ("member", .member, .closed),
        ("open", .open, .open),
        ("open+", .openPlus, .open),
        ("closing", .closing, .closed),
        ("off", .closed, .closed),
        ("on", .open, .open),
        ("party", .unknown("party"), .unknown),
    ])
    func mapsStates(raw: String, state: MainframeRoomState, status: SpaceStatus) {
        #expect(MainframeRoomState(rawValue: raw) == state)
        #expect(MainframeRoomState(rawValue: raw).status == status)
    }

    @Test func recognizesEndpoint() throws {
        #expect(Mainframe.isMainframe(Mainframe.spaceAPIEndpoint))
        #expect(Mainframe.isMainframe(try #require(URL(string: "http://STATUS.mainframe.io/status.json"))))
        #expect(!Mainframe.isMainframe(try #require(URL(string: "https://api.nerd2nerd.org/status.json"))))
    }

    @Test func clientFetchesRoomsFromOpenState() async throws {
        let body = try Fixture.data("mainframe-openstate")
        let client = StatusClient { request in
            #expect(request.url == Mainframe.openStateURL)
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let rooms = try await client.mainframeRooms()

        #expect(rooms.count == 4)
    }
}
