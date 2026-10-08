import Foundation

/// The parts of a SpaceAPI document (https://spaceapi.io) the apps use.
///
/// Follows schema v15 and also reads the flat layout of v0.13, which many spaces still serve.
public struct SpaceInfo: Sendable, Hashable, Decodable {
    public var name: String
    public var logo: URL?
    public var website: URL?
    public var location: Location?
    /// Nil if the space does not publish a state at all.
    public var state: State?
    public var contact: Contact
    public var calendar: URL?

    public var status: SpaceStatus {
        switch state?.open {
        case true: .open
        case false: .closed
        case nil: .unknown
        }
    }

    public struct Location: Sendable, Hashable, Decodable {
        public var address: String?
        public var latitude: Double?
        public var longitude: Double?
        public var timezone: String?

        private enum CodingKeys: String, CodingKey {
            case address, lat, lon, timezone
        }

        public init(address: String?, latitude: Double?, longitude: Double?, timezone: String?) {
            self.address = address
            self.latitude = latitude
            self.longitude = longitude
            self.timezone = timezone
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            address = container.lossy(String.self, forKey: .address)
            latitude = container.lossy(Double.self, forKey: .lat)
            longitude = container.lossy(Double.self, forKey: .lon)
            timezone = container.lossy(String.self, forKey: .timezone)
        }
    }

    public struct State: Sendable, Hashable, Decodable {
        /// Nil means the state is temporarily unavailable.
        public var open: Bool?
        public var lastChange: Date?
        public var message: String?
        public var triggerPerson: String?

        private enum CodingKeys: String, CodingKey {
            case open, lastchange, message
            case triggerPerson = "trigger_person"
        }

        public init(open: Bool?, lastChange: Date?, message: String?, triggerPerson: String?) {
            self.open = open
            self.lastChange = lastChange
            self.message = message
            self.triggerPerson = triggerPerson
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            open = container.lossy(Bool.self, forKey: .open)
            lastChange = container.lossyDate(forKey: .lastchange)
            message = container.lossy(String.self, forKey: .message)
            triggerPerson = container.lossy(String.self, forKey: .triggerPerson)
        }
    }

    public struct Contact: Sendable, Hashable, Decodable {
        public var email: String?
        public var phone: String?
        public var irc: String?
        public var mailingList: String?
        public var matrix: String?
        public var mastodon: String?

        private enum CodingKeys: String, CodingKey {
            case email, phone, irc, matrix, mastodon
            case mailingList = "ml"
        }

        public init(
            email: String? = nil, phone: String? = nil, irc: String? = nil,
            mailingList: String? = nil, matrix: String? = nil, mastodon: String? = nil
        ) {
            self.email = email
            self.phone = phone
            self.irc = irc
            self.mailingList = mailingList
            self.matrix = matrix
            self.mastodon = mastodon
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            email = container.lossy(String.self, forKey: .email)
            phone = container.lossy(String.self, forKey: .phone)
            irc = container.lossy(String.self, forKey: .irc)
            mailingList = container.lossy(String.self, forKey: .mailingList)
            matrix = container.lossy(String.self, forKey: .matrix)
            mastodon = container.lossy(String.self, forKey: .mastodon)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case space, logo, url, location, state, contact, feeds
        // v0.13 kept these at the top level.
        case open, lastchange, status, address, lat, lon
    }

    private struct Feeds: Decodable {
        struct Feed: Decodable {
            var url: URL?
        }

        var calendar: Feed?
    }

    public init(
        name: String, logo: URL? = nil, website: URL? = nil, location: Location? = nil,
        state: State? = nil, contact: Contact = Contact(), calendar: URL? = nil
    ) {
        self.name = name
        self.logo = logo
        self.website = website
        self.location = location
        self.state = state
        self.contact = contact
        self.calendar = calendar
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .space)
        logo = container.lossy(URL.self, forKey: .logo)
        website = container.lossy(URL.self, forKey: .url)
        contact = container.lossy(Contact.self, forKey: .contact) ?? Contact()
        calendar = container.lossy(Feeds.self, forKey: .feeds)?.calendar?.url

        if let state = container.lossy(State.self, forKey: .state) {
            self.state = state
        } else if container.contains(.open) {
            state = State(
                open: container.lossy(Bool.self, forKey: .open),
                lastChange: container.lossyDate(forKey: .lastchange),
                message: container.lossy(String.self, forKey: .status),
                triggerPerson: nil
            )
        }

        if let location = container.lossy(Location.self, forKey: .location) {
            self.location = location
        } else if container.contains(.address) || container.contains(.lat) {
            location = Location(
                address: container.lossy(String.self, forKey: .address),
                latitude: container.lossy(Double.self, forKey: .lat),
                longitude: container.lossy(Double.self, forKey: .lon),
                timezone: nil
            )
        }
    }
}
