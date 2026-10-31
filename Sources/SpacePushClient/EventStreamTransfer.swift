import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SpaceAPI

/// What an open event stream delivers: first the response, then body chunks as they arrive.
public enum EventStreamChunk: Sendable {
    case response(HTTPURLResponse)
    case data(Data)
}

/// Opens a long-lived request. Tests pass a stub; the default is `EventStreamTransfer.open`.
public typealias EventStreamOpener = @Sendable (URLRequest) -> AsyncThrowingStream<EventStreamChunk, any Error>

/// Streams a response body chunk by chunk through a URL session delegate.
/// The request's `timeoutInterval` is the idle limit between chunks; the whole
/// transfer may last `maximumDuration`. Ending iteration cancels the task.
/// All mutable state is protected by the lock. URLSession also serializes delegate callbacks.
public final class EventStreamTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// Longer than SpacePush's one-hour stream lifetime.
    public static let maximumDuration: TimeInterval = 2 * 60 * 60
    /// The body of an error answer is read up to this size for its reason.
    static let maximumErrorBytes = 16 * 1024

    private let lock = NSLock()
    private let continuation: AsyncThrowingStream<EventStreamChunk, any Error>.Continuation
    private var session: URLSession?
    private var errorStatus: Int?
    private var errorBody = Data()
    private var finished = false

    private init(continuation: AsyncThrowingStream<EventStreamChunk, any Error>.Continuation) {
        self.continuation = continuation
    }

    public static let open: EventStreamOpener = { request in
        AsyncThrowingStream { continuation in
            let transfer = EventStreamTransfer(continuation: continuation)
            continuation.onTermination = { _ in transfer.cancel() }
            transfer.start(request)
        }
    }

    private func start(_ request: URLRequest) {
        guard let url = request.url, (try? SpaceEndpoint.validate(url)) != nil else {
            finish(throwing: EndpointValidationError.invalidEndpoint)
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = Self.maximumDuration
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        lock.lock()
        guard !finished else { lock.unlock(); return }
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        lock.unlock()
        session.dataTask(with: request).resume()
    }

    private func cancel() {
        lock.lock()
        finished = true
        let session = self.session
        self.session = nil
        lock.unlock()
        session?.invalidateAndCancel()
    }

    private func finish(throwing error: (any Error)?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let session = self.session
        self.session = nil
        lock.unlock()
        session?.invalidateAndCancel()
        continuation.finish(throwing: error)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(throwing: URLError(.badServerResponse))
            return
        }
        lock.lock()
        let finished = self.finished
        if !(200..<300).contains(http.statusCode) { errorStatus = http.statusCode }
        lock.unlock()
        if !finished, (200..<300).contains(http.statusCode) { continuation.yield(.response(http)) }
        completionHandler(finished ? .cancel : .allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        if errorStatus != nil {
            if errorBody.count + data.count <= Self.maximumErrorBytes { errorBody.append(data) }
            lock.unlock()
            return
        }
        lock.unlock()
        continuation.yield(.data(data))
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock()
        let status = errorStatus
        let body = errorBody
        lock.unlock()
        if let status {
            let reason = (try? JSONDecoder().decode([String: String].self, from: body))?["error"]
            finish(throwing: SpacePushError.httpStatus(status, reason: reason))
        } else {
            finish(throwing: error)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                           completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // A stream is never redirected; the redirect itself becomes the answer.
        completionHandler(nil)
    }
}
