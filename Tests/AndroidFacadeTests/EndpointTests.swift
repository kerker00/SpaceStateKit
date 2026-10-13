import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SpaceAPI
import SpacePushClient
import Synchronization
import Testing
@testable import SpaceStateAndroidFacade

struct AndroidEndpointTests {
    @Test func invalidRawEndpointsKeepStableErrorAndDoNotLoad() async throws {
        let requests = Mutex(0)
        let service = SpaceStateService(service: StatusService(spacePush: nil, direct: StatusClient { _ in
            requests.withLock { $0 += 1 }
            throw URLError(.cannotConnectToHost)
        }))
        for endpoint in ["file:///tmp/status", "https://user:secret@space.example/api", "https://space.example/api\n"] {
            do {
                _ = try await service.space(endpoint: endpoint)
                Issue.record("Expected endpoint validation failure")
            } catch {
                #expect(String(describing: error) == "spacestatekit:invalidEndpoint")
            }
        }
        #expect(requests.withLock { $0 } == 0)
    }

    @Test func invalidProxyConfigurationFailsInsteadOfSilentlyUsingDirectReads() async {
        for endpoint in ["not a URL", "file:///tmp/status", "https://push.example/\n"] {
            let service = SpaceStateService(spacePushURL: endpoint, userAgent: "Test", activePeriodsFile: nil)
            for operation in [0, 1, 2] {
                do {
                    switch operation {
                    case 0: _ = try await service.space(endpoint: SpaceStateService.mainframeEndpoint)
                    case 1: _ = try await service.directory()
                    default: _ = try await service.mainframeRooms()
                    }
                    Issue.record("Expected invalid proxy configuration")
                } catch {
                    #expect(String(describing: error) == "spacestatekit:invalidEndpoint")
                }
            }
        }
    }

    @Test func validEndpointsReachTheSharedService() async throws {
        let service = SpaceStateService(service: StatusService(spacePush: nil, direct: StatusClient { request in
            #expect(request.url?.absoluteString == "https://space.example/api")
            return (Data(#"{"space":"A"}"#.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }))
        let space = try await service.space(endpoint: "http://space.example/api")
        #expect(space.name == "A")
        #expect(space.endpoint == "http://space.example/api")
    }

    @Test func mainframeRecognitionRejectsInvalidEndpoint() {
        #expect(SpaceStateService.isMainframe(endpoint: SpaceStateService.mainframeEndpoint))
        #expect(!SpaceStateService.isMainframe(endpoint: SpaceStateService.mainframeEndpoint + "\n"))
    }
}
