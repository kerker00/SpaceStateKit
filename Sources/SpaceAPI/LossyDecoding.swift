import Foundation

// Many SpaceAPI endpoints do not follow the schema exactly. A malformed optional
// field must not make the whole space unreadable, so optional fields decode lossily.
extension KeyedDecodingContainer {
    /// Returns the value for `key`, or nil if it is missing or malformed.
    func lossy<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// Returns a web link, or nil unless it is an absolute http or https URL.
    /// Spaces run their own endpoints; a link such as `javascript:`, `file:` or
    /// another app's URL scheme must never reach a button in the app.
    func webURL(forKey key: Key) -> URL? {
        lossy(URL.self, forKey: key).flatMap { $0.isWebLink ? $0 : nil }
    }

    /// Returns the array's readable elements; a malformed element is dropped on its own,
    /// and anything that is not an array gives an empty result.
    func lossyArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T] {
        (lossy([LossyElement<T>].self, forKey: key) ?? []).compactMap(\.value)
    }

    /// Returns a Unix timestamp in seconds as a date, or nil if it is missing or malformed.
    func lossyDate(forKey key: Key) -> Date? {
        lossy(Double.self, forKey: key).map(Date.init(timeIntervalSince1970:))
    }
}

private struct LossyElement<T: Decodable>: Decodable {
    let value: T?

    // Through a single-value container, so JSONDecoder reads URLs from plain strings.
    init(from decoder: any Decoder) throws {
        value = try? decoder.singleValueContainer().decode(T.self)
    }
}

extension URL {
    /// An absolute http or https URL with a host.
    var isWebLink: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return (scheme == "https" || scheme == "http") && host() != nil
    }
}
