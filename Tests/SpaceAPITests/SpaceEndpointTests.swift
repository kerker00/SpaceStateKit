import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SpaceAPI

struct SpaceEndpointTests {
    @Test func acceptsSupportedEndpointsWithoutChangingIdentity() throws {
        for string in ["http://localhost/status", "HTTP://a.example:8080/x", "https://[::1]:443/api",
                       "https://xn--mnchen-3ya.example/api", "https://space.example/a%20b?x=a+b&y=1",
                       "https://space.example/%250A", "https://space.example/api#status"] {
            #expect(try SpaceEndpoint.parse(string).absoluteString == URL(string: string)?.absoluteString)
        }
    }

    @Test func rejectsInvalidStringsBeforeNormalization() {
        for string in ["file:///tmp/status", "ftp://space.example/status", "javascript:alert(1)",
                       "api/status", "//space.example/api", "https:///api", "https://",
                       "https://user:secret@space.example/api", "https://@space.example/api",
                       "https://space.example/api\n", "https://space.example/\u{0}",
                       "https://space.example/%00", "https://space.example/%1f", "https://space.example/%7F",
                       "https://space.example/%C2%85", "https://space.example/%ff%0a",
                       "https://space.example:/api", "https://space.example:0/api", "https://space.example:65536/api",
                       "https://space.example:9999999999999999999999999999/api"] {
            #expect(throws: EndpointValidationError.invalidEndpoint) { try SpaceEndpoint.parse(string) }
        }
    }

    @Test func rejectsRelativeURLsEvenWhenTheyHaveABase() throws {
        let url = try #require(URL(string: "api", relativeTo: URL(string: "https://space.example/")))
        #expect(throws: EndpointValidationError.invalidEndpoint) { try SpaceEndpoint.validate(url) }
    }

    @Test func redirectsUseEndpointRulesAndKeepDowngradeProtection() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let source = try #require(URL(string: "https://space.example/api"))
        let task = session.dataTask(with: source) // Never resumed; only the delegate is exercised.
        let response = try #require(HTTPURLResponse(url: source, statusCode: 302, httpVersion: nil, headerFields: nil))
        let transfer = BoundedHTTPTransfer(maximumBytes: 1024)
        for (string, allowed) in [("https://other.example/api", true), ("http://other.example/api", false),
                                  ("https://user:secret@other.example/api", false),
                                  ("https://other.example/%0A", false), ("file:///tmp/status", false)] {
            let request = URLRequest(url: try #require(URL(string: string)))
            let redirected: URLRequest? = await withCheckedContinuation { continuation in
                transfer.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) {
                    continuation.resume(returning: $0)
                }
            }
            #expect((redirected != nil) == allowed)
        }
    }
}
