/// The public open state of a space, reduced to what every SpaceAPI endpoint can express.
public enum SpaceStatus: String, Sendable, Hashable, Codable {
    case open
    case closed
    /// The space does not publish a state, or it is temporarily unavailable.
    case unknown
}
