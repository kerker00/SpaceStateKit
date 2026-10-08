import Foundation

/// A space listed in the SpaceAPI directory, with the data the aggregator last fetched.
public struct DirectoryEntry: Sendable, Hashable, Identifiable {
    /// The space's own SpaceAPI endpoint.
    public var endpoint: URL
    public var info: SpaceInfo
    /// When the aggregator last reached the endpoint.
    public var lastSeen: Date?

    public var id: URL { endpoint }

    public init(endpoint: URL, info: SpaceInfo, lastSeen: Date?) {
        self.endpoint = endpoint
        self.info = info
        self.lastSeen = lastSeen
    }
}

/// The SpaceAPI aggregator, which serves the latest data of every listed space in one response.
public enum SpaceDirectory {
    public static let aggregatorURL = URL(string: "https://api.spaceapi.io/")!

    /// Decodes an aggregator response, skipping spaces without readable data, sorted by name.
    public static func decode(_ data: Data) throws -> [DirectoryEntry] {
        try JSONDecoder().decode([RawEntry].self, from: data)
            .compactMap { raw in
                guard let endpoint = raw.url, let info = raw.data else { return nil }
                return DirectoryEntry(endpoint: endpoint, info: info, lastSeen: raw.lastSeen)
            }
            .sorted { $0.info.name.localizedStandardCompare($1.info.name) == .orderedAscending }
    }

    // Never throws, so one broken entry cannot fail the whole list.
    private struct RawEntry: Decodable {
        var url: URL?
        var lastSeen: Date?
        var data: SpaceInfo?

        private enum CodingKeys: String, CodingKey {
            case url, lastSeen, data
        }

        init(from decoder: any Decoder) throws {
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            url = container?.lossy(URL.self, forKey: .url)
            lastSeen = container?.lossyDate(forKey: .lastSeen)
            data = container?.lossy(SpaceInfo.self, forKey: .data)
        }
    }
}
