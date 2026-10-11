import Foundation

// The smaller parts of a SpaceAPI document. Every link is checked with `webURL`;
// an entry without its required fields is dropped on its own.

extension SpaceInfo {
    /// The space's pictures for its open and closed state. Both must be web links.
    public struct Icon: Sendable, Hashable, Decodable {
        public var open: URL
        public var closed: URL

        private enum CodingKeys: String, CodingKey {
            case open, closed
        }

        public init(open: URL, closed: URL) {
            self.open = open
            self.closed = closed
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let open = container.webURL(forKey: .open), let closed = container.webURL(forKey: .closed) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Icon needs two web links"))
            }
            self.open = open
            self.closed = closed
        }
    }

    /// A person who can open the space. At least one field is set.
    public struct Keymaster: Sendable, Hashable, Decodable {
        public var name: String?
        public var ircNick: String?
        public var phone: String?
        public var email: String?
        public var xmpp: String?
        public var mastodon: String?
        public var matrix: String?

        private enum CodingKeys: String, CodingKey {
            case name, phone, email, xmpp, mastodon, matrix
            case ircNick = "irc_nick"
        }

        public init(
            name: String? = nil, ircNick: String? = nil, phone: String? = nil, email: String? = nil,
            xmpp: String? = nil, mastodon: String? = nil, matrix: String? = nil
        ) {
            self.name = name
            self.ircNick = ircNick
            self.phone = phone
            self.email = email
            self.xmpp = xmpp
            self.mastodon = mastodon
            self.matrix = matrix
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = container.lossy(String.self, forKey: .name)
            ircNick = container.lossy(String.self, forKey: .ircNick)
            phone = container.lossy(String.self, forKey: .phone)
            email = container.lossy(String.self, forKey: .email)
            xmpp = container.lossy(String.self, forKey: .xmpp)
            mastodon = container.lossy(String.self, forKey: .mastodon)
            matrix = container.lossy(String.self, forKey: .matrix)
        }

        var isEmpty: Bool {
            [name, ircNick, phone, email, xmpp, mastodon, matrix].allSatisfy { $0 == nil }
        }
    }

    public struct Feed: Sendable, Hashable, Decodable {
        public var url: URL
        /// The format as the space states it, such as `rss`, `atom` or `ical`.
        public var type: String?

        private enum CodingKeys: String, CodingKey {
            case url, type
        }

        public init(url: URL, type: String? = nil) {
            self.url = url
            self.type = type
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let url = container.webURL(forKey: .url) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Feed needs a web link"))
            }
            self.url = url
            type = container.lossy(String.self, forKey: .type)
        }
    }

    public struct Feeds: Sendable, Hashable, Decodable {
        public var blog: Feed?
        public var wiki: Feed?
        public var calendar: Feed?
        public var flickr: Feed?

        private enum CodingKeys: String, CodingKey {
            case blog, wiki, calendar, flickr
        }

        public init(blog: Feed? = nil, wiki: Feed? = nil, calendar: Feed? = nil, flickr: Feed? = nil) {
            self.blog = blog
            self.wiki = wiki
            self.calendar = calendar
            self.flickr = flickr
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            blog = container.lossy(Feed.self, forKey: .blog)
            wiki = container.lossy(Feed.self, forKey: .wiki)
            calendar = container.lossy(Feed.self, forKey: .calendar)
            flickr = container.lossy(Feed.self, forKey: .flickr)
        }
    }

    public struct Link: Sendable, Hashable, Decodable {
        public var name: String
        public var description: String?
        public var url: URL

        private enum CodingKeys: String, CodingKey {
            case name, description, url
        }

        public init(name: String, description: String? = nil, url: URL) {
            self.name = name
            self.description = description
            self.url = url
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let url = container.webURL(forKey: .url) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Link needs a web link"))
            }
            name = try container.decode(String.self, forKey: .name)
            description = container.lossy(String.self, forKey: .description)
            self.url = url
        }
    }

    /// Another space this one is connected with. At least one of the links is set.
    public struct LinkedSpace: Sendable, Hashable, Decodable {
        /// The other space's SpaceAPI endpoint.
        public var endpoint: URL?
        public var website: URL?

        private enum CodingKeys: String, CodingKey {
            case endpoint, website
        }

        public init(endpoint: URL?, website: URL?) {
            self.endpoint = endpoint
            self.website = website
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            endpoint = container.webURL(forKey: .endpoint)
            website = container.webURL(forKey: .website)
            guard endpoint != nil || website != nil else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Linked space needs a web link"))
            }
        }
    }
}
