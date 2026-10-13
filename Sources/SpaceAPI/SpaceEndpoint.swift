import Foundation

/// Endpoint validation failed. The error deliberately omits the supplied URL.
public enum EndpointValidationError: Error, Equatable, Sendable {
    case invalidEndpoint
}

/// The URL contract for direct reads, SpacePush and directory endpoints.
/// Local hosts, HTTP, ports, paths and queries are supported; this is URL validation,
/// not a restriction on the networks a consumer may access.
public enum SpaceEndpoint {
    /// Validates the original string before Foundation can encode its characters.
    public static func parse(_ string: String) throws -> URL {
        guard !containsControls(string), let url = URL(string: string) else {
            throw EndpointValidationError.invalidEndpoint
        }
        try validate(url)
        return url
    }

    /// Checks an already constructed URL at the transport boundary.
    public static func validate(_ url: URL) throws {
        guard url.baseURL == nil,
              !containsControls(url.absoluteString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              components.user == nil, components.password == nil,
              validPort(components) else {
            throw EndpointValidationError.invalidEndpoint
        }
    }

    private static func validPort(_ components: URLComponents) -> Bool {
        // `port` is also nil for an empty component or a number that overflows
        // Int. Check the text after the host so neither becomes an absent port.
        guard let string = components.string, let host = components.rangeOfHost else { return false }
        let suffix = string[host.upperBound...]
        guard suffix.first == ":" else { return true }
        let digits = suffix.dropFirst().prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard !digits.isEmpty, digits.utf8.allSatisfy({ (48...57).contains($0) }),
              let port = Int(digits) else { return false }
        return (1...65535).contains(port)
    }

    private static func containsControls(_ string: String) -> Bool {
        if string.rangeOfCharacter(from: .controlCharacters) != nil { return true }
        // Scan ASCII escapes even when unrelated invalid UTF-8 prevents whole-string decoding.
        if string.range(of: "%(?:0[0-9a-f]|1[0-9a-f]|7f)",
                        options: [.regularExpression, .caseInsensitive]) != nil { return true }
        return string.removingPercentEncoding?.rangeOfCharacter(from: .controlCharacters) != nil
    }
}
