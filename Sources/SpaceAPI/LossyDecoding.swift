import Foundation

// Many SpaceAPI endpoints do not follow the schema exactly. A malformed optional
// field must not make the whole space unreadable, so optional fields decode lossily.
extension KeyedDecodingContainer {
    /// Returns the value for `key`, or nil if it is missing or malformed.
    func lossy<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// Returns a Unix timestamp in seconds as a date, or nil if it is missing or malformed.
    func lossyDate(forKey key: Key) -> Date? {
        lossy(Double.self, forKey: key).map(Date.init(timeIntervalSince1970:))
    }
}
