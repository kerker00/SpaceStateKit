import Foundation
import Testing
@testable import SpacePushClient

struct ServerSentEventParserTests {
    private static let stream = "retry: 10000\n\n: ping\n\nevent: change\ndata: {\"a\":1}\n\ndata: one\ndata: two\n\n"

    @Test func parsesWholeStream() throws {
        var parser = ServerSentEventParser()
        let events = try parser.feed(Array(Self.stream.utf8))
        #expect(events == [ServerSentEvent(event: "change", data: "{\"a\":1}"), ServerSentEvent(data: "one\ntwo")])
        #expect(parser.retry == .milliseconds(10000))
    }

    @Test func chunkBoundariesDoNotMatter() throws {
        var whole = ServerSentEventParser()
        let expected = try whole.feed(Array(Self.stream.utf8))
        var parser = ServerSentEventParser()
        var events: [ServerSentEvent] = []
        for byte in Self.stream.utf8 { events += try parser.feed([byte]) }
        #expect(events == expected)
    }

    @Test(arguments: ["\r\n", "\r", "\n"])
    func acceptsEveryLineEnding(_ ending: String) throws {
        var parser = ServerSentEventParser()
        let text = ["event: test", "data:x", "", ""].joined(separator: ending)
        #expect(try parser.feed(Array(text.utf8)) == [ServerSentEvent(event: "test", data: "x")])
    }

    @Test func crlfSplitAcrossChunksIsOneLineEnd() throws {
        var parser = ServerSentEventParser()
        #expect(try parser.feed(Array("data: a\r".utf8)).isEmpty)
        // The LF completes the CR; only the following empty line dispatches.
        #expect(try parser.feed(Array("\n".utf8)).isEmpty)
        #expect(try parser.feed(Array("\r\n".utf8)) == [ServerSentEvent(data: "a")])
    }

    @Test func eventWithoutDataIsNotDispatchedAndResets() throws {
        var parser = ServerSentEventParser()
        #expect(try parser.feed(Array("event: change\n\ndata: x\n\n".utf8)) == [ServerSentEvent(data: "x")])
    }

    @Test func invalidRetryIsIgnored() throws {
        var parser = ServerSentEventParser()
        _ = try parser.feed(Array("retry: 5000\n\nretry: soon\n\nretry: -1\n\n".utf8))
        #expect(parser.retry == .milliseconds(5000))
    }

    @Test func overlongLineFails() {
        var parser = ServerSentEventParser()
        #expect(throws: ServerSentEventError.lineTooLong) {
            try parser.feed([UInt8](repeating: UInt8(ascii: "a"), count: ServerSentEventParser.maximumLineBytes + 1))
        }
    }
}

struct StateChangeTests {
    @Test func decodesChange() throws {
        let event = ServerSentEvent(event: "change", data: """
            {"endpoint":"https://status.mainframe.io/api/spaceInfo","room":"radstelle","name":"Mainframe · Radstelle",\
            "from":"closed","to":"open","at":1793440800}
            """)
        let change = try #require(try StateChange(event))
        #expect(change.kind == .change)
        #expect(change.room == "radstelle")
        #expect(change.from == "closed" && change.to == "open")
        #expect(change.at == Date(timeIntervalSince1970: 1793440800))
        #expect(change.subscription == PushSubscription(endpoint: change.endpoint, room: "radstelle"))
    }

    @Test func decodesTestEventWithoutStates() throws {
        let event = ServerSentEvent(event: "test", data: """
            {"endpoint":"https://a.example/","room":"space","name":"A","test":true,"at":1}
            """)
        let change = try #require(try StateChange(event))
        #expect(change.kind == .test)
        #expect(change.from == nil)
        #expect(change.subscription == PushSubscription(endpoint: change.endpoint))
    }

    @Test func otherEventsAreIgnored() throws {
        #expect(try StateChange(ServerSentEvent(data: "{}")) == nil)
    }

    @Test func changeWithoutStatesIsInvalid() {
        #expect(throws: DecodingError.self) {
            try StateChange(ServerSentEvent(event: "change", data: """
                {"endpoint":"https://a.example/","room":"space","name":"A","at":1}
                """))
        }
    }
}
