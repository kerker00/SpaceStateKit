import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What a transfer hears about its task from `SharedURLSessions`.
package protocol SharedSessionTaskDelegate: AnyObject, Sendable {
    func didReceive(response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void)
    func didReceive(data: Data)
    func didComplete(error: (any Error)?)
    func willRedirect(response: HTTPURLResponse, to request: URLRequest,
                      completionHandler: @escaping @Sendable (URLRequest?) -> Void)
}

/// One URL session per set of timeouts for the whole process. They are never invalidated:
/// on Linux, releasing a session can abort the process in swift-corelibs-foundation
/// ("_MultiHandle deallocated with non-zero retain count"), which over HTTPS happened within
/// a few requests. A transfer ends by cancelling its own task.
///
/// Requests share these sessions, so nothing that could link them is kept: no cookies,
/// credentials or cache.
package final class SharedURLSessions: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    package static let shared = SharedURLSessions()

    private struct Timeouts: Hashable {
        var request: TimeInterval
        var resource: TimeInterval
    }

    private let lock = NSLock()
    private var sessions: [Timeouts: URLSession] = [:]
    private var delegates: [ObjectIdentifier: any SharedSessionTaskDelegate] = [:]

    /// A task to resume. `delegate` is held until the task completes.
    package func dataTask(with request: URLRequest, requestTimeout: TimeInterval, resourceTimeout: TimeInterval,
                          delegate: any SharedSessionTaskDelegate) -> URLSessionDataTask {
        lock.lock()
        defer { lock.unlock() }
        let timeouts = Timeouts(request: requestTimeout, resource: resourceTimeout)
        let session = sessions[timeouts] ?? makeSession(timeouts)
        sessions[timeouts] = session
        let task = session.dataTask(with: request)
        delegates[ObjectIdentifier(task)] = delegate
        return task
    }

    private func makeSession(_ timeouts: Timeouts) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeouts.request
        configuration.timeoutIntervalForResource = timeouts.resource
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    private func delegate(of task: URLSessionTask) -> (any SharedSessionTaskDelegate)? {
        lock.lock()
        defer { lock.unlock() }
        return delegates[ObjectIdentifier(task)]
    }

    package func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                            completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let delegate = delegate(of: dataTask) else { return completionHandler(.cancel) }
        delegate.didReceive(response: response, completionHandler: completionHandler)
    }

    package func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        delegate(of: dataTask)?.didReceive(data: data)
    }

    package func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock()
        let delegate = delegates.removeValue(forKey: ObjectIdentifier(task))
        lock.unlock()
        delegate?.didComplete(error: error)
    }

    package func urlSession(_ session: URLSession, task: URLSessionTask,
                            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                            completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let delegate = delegate(of: task) else { return completionHandler(nil) }
        delegate.willRedirect(response: response, to: request, completionHandler: completionHandler)
    }
}
