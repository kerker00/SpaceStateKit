import Foundation

/// A space listed in the SpaceAPI directory, with the data the aggregator last fetched.
public struct DirectoryEntry: Sendable, Hashable, Identifiable {
    /// The space's own SpaceAPI endpoint.
    public var endpoint: URL
    public var info: SpaceInfo
    /// When the aggregator last reached the endpoint.
    public var lastSeen: Date?
    /// Explicit aggregator validation, when present. A failed reachability check
    /// does not erase the last known data or observation time.
    public var reachable: Bool?

    public var id: URL { endpoint }

    public init(endpoint: URL, info: SpaceInfo, lastSeen: Date?, reachable: Bool? = nil) {
        self.endpoint = endpoint
        self.info = info
        self.lastSeen = lastSeen
        self.reachable = reachable
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
                return DirectoryEntry(endpoint: endpoint, info: info, lastSeen: raw.lastSeen, reachable: raw.reachable)
            }
            .sorted { lhs, rhs in
                let comparison = lhs.info.name.compare(rhs.info.name, options: [.numeric, .caseInsensitive],
                                                       locale: Locale(identifier: "en_US_POSIX"))
                return comparison == .orderedSame
                    ? lhs.endpoint.absoluteString < rhs.endpoint.absoluteString
                    : comparison == .orderedAscending
            }
    }

    // Never throws, so one broken entry cannot fail the whole list.
    private struct RawEntry: Decodable {
        var url: URL?
        var lastSeen: Date?
        var data: SpaceInfo?
        var reachable: Bool?

        private enum CodingKeys: String, CodingKey {
            case url, lastSeen, data, validationResult
        }

        init(from decoder: any Decoder) throws {
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            url = container?.lossy(String.self, forKey: .url).flatMap { try? SpaceEndpoint.parse($0) }
            lastSeen = container?.lossyDate(forKey: .lastSeen)
            data = container?.lossy(SpaceInfo.self, forKey: .data)
            reachable = container?.lossy(ValidationResult.self, forKey: .validationResult)?.reachable
        }
    }

    private struct ValidationResult: Decodable {
        let reachable: Bool?
        private enum CodingKeys: String, CodingKey { case reachable }
        init(from decoder: any Decoder) throws {
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            reachable = container?.lossy(Bool.self, forKey: .reachable)
        }
    }
}
