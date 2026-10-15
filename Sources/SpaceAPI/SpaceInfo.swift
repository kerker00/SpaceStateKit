import Foundation

/// A SpaceAPI document (https://spaceapi.io): the space's state, location, contacts, feeds and links.
///
/// Follows schema v15 and also reads the flat layout of v0.12 and older, which some spaces still serve.
/// Membership plans, webcams, areas, SpaceFED and events are not modelled yet.
public struct SpaceInfo: Sendable, Hashable, Decodable {
    public var name: String
    public var logo: URL?
    public var website: URL?
    public var location: Location?
    /// Nil if the space does not publish a state at all.
    public var state: State?
    public var contact: Contact
    public var feeds: Feeds
    /// Links to the space's projects.
    public var projects: [URL]
    public var links: [Link]
    public var linkedSpaces: [LinkedSpace]
    public var sensors: Sensors
    /// Schema versions the document claims to follow, such as `["14", "15"]`.
    public var apiCompatibility: [String]
    /// The single `api` version of documents older than v14, such as `"0.13"`.
    public var legacyAPIVersion: String?

    /// The calendar feed's URL.
    public var calendar: URL? {
        get { feeds.calendar?.url }
        set { feeds.calendar = newValue.map { Feed(url: $0, type: feeds.calendar?.type) } }
    }

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
        /// ISO 3166-1 alpha-2, such as `DE`. Few spaces publish it.
        public var countryCode: String?
        /// How to get in, such as which bell to ring.
        public var hint: String?

        private enum CodingKeys: String, CodingKey {
            case address, lat, lon, timezone, hint
            case countryCode = "country_code"
        }

        public init(
            address: String?, latitude: Double?, longitude: Double?, timezone: String?,
            countryCode: String? = nil, hint: String? = nil
        ) {
            self.address = address
            self.latitude = latitude
            self.longitude = longitude
            self.timezone = timezone
            self.countryCode = countryCode
            self.hint = hint
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            address = container.lossy(String.self, forKey: .address)
            latitude = container.lossy(Double.self, forKey: .lat)
            longitude = container.lossy(Double.self, forKey: .lon)
            timezone = container.lossy(String.self, forKey: .timezone)
            countryCode = container.lossy(String.self, forKey: .countryCode)
            hint = container.lossy(String.self, forKey: .hint)
        }
    }

    public struct State: Sendable, Hashable, Decodable {
        /// Nil means the state is temporarily unavailable.
        public var open: Bool?
        public var lastChange: Date?
        public var message: String?
        public var triggerPerson: String?
        /// The space's own pictures for open and closed.
        public var icon: Icon?

        private enum CodingKeys: String, CodingKey {
            case open, lastchange, message, icon
            case triggerPerson = "trigger_person"
        }

        public init(open: Bool?, lastChange: Date?, message: String?, triggerPerson: String?, icon: Icon? = nil) {
            self.open = open
            self.lastChange = lastChange
            self.message = message
            self.triggerPerson = triggerPerson
            self.icon = icon
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            open = container.lossy(Bool.self, forKey: .open)
            lastChange = container.lossyDate(forKey: .lastchange)
            message = container.lossy(String.self, forKey: .message)
            triggerPerson = container.lossy(String.self, forKey: .triggerPerson)
            icon = container.lossy(Icon.self, forKey: .icon)
        }
    }

    public struct Contact: Sendable, Hashable, Decodable {
        public var email: String?
        public var phone: String?
        public var irc: String?
        public var mailingList: String?
        public var matrix: String?
        public var mastodon: String?
        public var xmpp: String?
        public var mumble: String?
        public var sip: String?
        /// Where to report problems with the space's infrastructure.
        public var issueMail: String?
        public var gopher: String?
        /// People who can open the space.
        public var keymasters: [Keymaster]

        private enum CodingKeys: String, CodingKey {
            case email, phone, irc, matrix, mastodon, xmpp, mumble, sip, gopher, keymasters
            case mailingList = "ml"
            case issueMail = "issue_mail"
            // Before v13, XMPP was called Jabber.
            case jabber
        }

        public init(
            email: String? = nil, phone: String? = nil, irc: String? = nil,
            mailingList: String? = nil, matrix: String? = nil, mastodon: String? = nil,
            xmpp: String? = nil, mumble: String? = nil, sip: String? = nil,
            issueMail: String? = nil, gopher: String? = nil, keymasters: [Keymaster] = []
        ) {
            self.email = email
            self.phone = phone
            self.irc = irc
            self.mailingList = mailingList
            self.matrix = matrix
            self.mastodon = mastodon
            self.xmpp = xmpp
            self.mumble = mumble
            self.sip = sip
            self.issueMail = issueMail
            self.gopher = gopher
            self.keymasters = keymasters
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            email = container.lossy(String.self, forKey: .email)
            phone = container.lossy(String.self, forKey: .phone)
            irc = container.lossy(String.self, forKey: .irc)
            mailingList = container.lossy(String.self, forKey: .mailingList)
            matrix = container.lossy(String.self, forKey: .matrix)
            mastodon = container.lossy(String.self, forKey: .mastodon)
            xmpp = container.lossy(String.self, forKey: .xmpp) ?? container.lossy(String.self, forKey: .jabber)
            mumble = container.lossy(String.self, forKey: .mumble)
            sip = container.lossy(String.self, forKey: .sip)
            issueMail = container.lossy(String.self, forKey: .issueMail)
            gopher = container.lossy(String.self, forKey: .gopher)
            keymasters = container.lossyArray(Keymaster.self, forKey: .keymasters).filter { !$0.isEmpty }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case space, logo, url, location, state, contact, feeds, projects, links, sensors
        case linkedSpaces = "linked_spaces"
        case apiCompatibility = "api_compatibility"
        case api
        // v0.12 and older kept these at the top level; v0.13 moved them into `state` and `location`.
        case open, lastchange, status, address, lat, lon, icon
    }

    public init(
        name: String, logo: URL? = nil, website: URL? = nil, location: Location? = nil,
        state: State? = nil, contact: Contact = Contact(), calendar: URL? = nil,
        feeds: Feeds = Feeds(), projects: [URL] = [], links: [Link] = [], linkedSpaces: [LinkedSpace] = [],
        apiCompatibility: [String] = [], legacyAPIVersion: String? = nil, sensors: Sensors = Sensors()
    ) {
        self.name = name
        self.logo = logo
        self.website = website
        self.location = location
        self.state = state
        self.contact = contact
        self.feeds = feeds
        self.projects = projects
        self.links = links
        self.linkedSpaces = linkedSpaces
        self.sensors = sensors
        self.apiCompatibility = apiCompatibility
        self.legacyAPIVersion = legacyAPIVersion
        if let calendar { self.calendar = calendar }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .space)
        logo = container.webURL(forKey: .logo)
        website = container.webURL(forKey: .url)
        contact = container.lossy(Contact.self, forKey: .contact) ?? Contact()
        feeds = container.lossy(Feeds.self, forKey: .feeds) ?? Feeds()
        projects = container.lossyArray(URL.self, forKey: .projects).filter(\.isWebLink)
        links = container.lossyArray(Link.self, forKey: .links)
        linkedSpaces = container.lossyArray(LinkedSpace.self, forKey: .linkedSpaces)
        sensors = container.lossy(Sensors.self, forKey: .sensors) ?? Sensors()
        apiCompatibility = container.lossyArray(String.self, forKey: .apiCompatibility)
        legacyAPIVersion = container.lossy(String.self, forKey: .api)

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
        // v0.13 and older kept the icons at the top level.
        if state != nil, state?.icon == nil {
            state?.icon = container.lossy(Icon.self, forKey: .icon)
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
