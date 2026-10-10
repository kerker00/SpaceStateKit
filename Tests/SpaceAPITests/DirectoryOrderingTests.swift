import Foundation
import Testing
@testable import SpaceAPI

@Test func directoryUsesNumericOrderingAndStableEndpointTies() throws {
    let rows = [
        ["url": "https://b.test", "data": ["space": "Space 10"]],
        ["url": "https://z.test", "data": ["space": "space 2"]],
        ["url": "https://a.test", "data": ["space": "Space 2"]],
        ["url": "https://umlaut.test", "data": ["space": "Äther"]],
    ] as [[String: Any]]
    let entries = try SpaceDirectory.decode(JSONSerialization.data(withJSONObject: rows))
    let numeric = entries.filter { $0.info.name.lowercased().hasPrefix("space") }
    #expect(numeric.map(\.endpoint.absoluteString) == ["https://a.test", "https://z.test", "https://b.test"])
    #expect(entries.contains { $0.info.name == "Äther" })
}
