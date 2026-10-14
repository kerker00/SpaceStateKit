import Foundation
import SpaceAPI

/// JNI-compatible detail values. Existing status/timing fields remain independent.
public final class SpaceDetails: Sendable {
    public let accessHint: String?
    public let countryCode: String?
    public let timezone: String?
    public let latitude: Double?
    public let longitude: Double?
    public let contacts: [DetailContact]
    public let keyholders: [DetailKeyholder]
    public let feeds: [DetailFeed]
    public let projects: [String]
    public let links: [DetailLink]
    public let linkedSpaces: [DetailLinkedSpace]

    init(_ info: SpaceInfo) {
        accessHint = detailText(info.location?.hint)
        countryCode = detailText(info.location?.countryCode)
        timezone = detailText(info.location?.timezone)
        if let lat = info.location?.latitude, let lon = info.location?.longitude,
           lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon) {
            latitude = lat
            longitude = lon
        } else {
            latitude = nil
            longitude = nil
        }
        contacts = DetailContact.fields(info.contact)
        keyholders = info.contact.keymasters.map(DetailKeyholder.init).filter { $0.hasContent }
        feeds = [("blog", info.feeds.blog), ("wiki", info.feeds.wiki),
                 ("calendar", info.feeds.calendar), ("flickr", info.feeds.flickr)].compactMap { kind, feed in
            guard let feed, let url = detailWebURL(feed.url) else { return nil }
            return DetailFeed(kind: kind, url: url, format: detailText(feed.type))
        }
        projects = info.projects.compactMap(detailWebURL)
        links = info.links.compactMap { link in
            guard let name = detailText(link.name), let url = detailWebURL(link.url) else { return nil }
            return DetailLink(name: name, url: url, summary: detailText(link.description))
        }
        linkedSpaces = info.linkedSpaces.compactMap { linked in
            let endpoint = detailWebURL(linked.endpoint)
            let website = detailWebURL(linked.website)
            guard endpoint != nil || website != nil else { return nil }
            return DetailLinkedSpace(apiEndpoint: endpoint, website: website)
        }
    }
}

public final class DetailContact: Sendable {
    public let kind: String
    public let value: String
    init(kind: String, value: String) { self.kind = kind; self.value = value }

    static func fields(_ contact: SpaceInfo.Contact) -> [DetailContact] {
        [("email", contact.email), ("phone", contact.phone), ("irc", contact.irc),
         ("mailingList", contact.mailingList), ("matrix", contact.matrix), ("mastodon", contact.mastodon),
         ("xmpp", contact.xmpp), ("mumble", contact.mumble), ("sip", contact.sip),
         ("issueMail", contact.issueMail), ("gopher", contact.gopher)].compactMap { kind, value in
            detailText(value).map { DetailContact(kind: kind, value: $0) }
        }
    }
}

public final class DetailKeyholder: Sendable {
    public let name: String?
    public let ircNick: String?
    public let contacts: [DetailContact]
    var hasContent: Bool { name != nil || ircNick != nil || !contacts.isEmpty }
    init(_ person: SpaceInfo.Keymaster) {
        name = detailText(person.name)
        ircNick = detailText(person.ircNick)
        contacts = DetailContact.fields(SpaceInfo.Contact(email: person.email, phone: person.phone,
            matrix: person.matrix, mastodon: person.mastodon, xmpp: person.xmpp))
    }
}

public final class DetailFeed: Sendable {
    public let kind: String
    public let url: String
    public let format: String?
    init(kind: String, url: String, format: String?) { self.kind = kind; self.url = url; self.format = format }
}

public final class DetailLink: Sendable {
    public let name: String
    public let url: String
    public let summary: String?
    init(name: String, url: String, summary: String?) { self.name = name; self.url = url; self.summary = summary }
}

public final class DetailLinkedSpace: Sendable {
    public let apiEndpoint: String?
    public let website: String?
    init(apiEndpoint: String?, website: String?) { self.apiEndpoint = apiEndpoint; self.website = website }
}

private func detailText(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    return value
}

private func detailWebURL(_ url: URL?) -> String? {
    guard let url, (try? SpaceEndpoint.validate(url)) != nil else { return nil }
    return url.absoluteString
}
