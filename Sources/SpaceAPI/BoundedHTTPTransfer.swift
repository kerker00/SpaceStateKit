import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// All mutable state is protected by the lock. URLSession also serializes delegate callbacks.
final class BoundedHTTPTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var continuation: CheckedContinuation<(Data, URLResponse), any Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var body = Data()
    private var response: URLResponse?
    private var cancelled = false
    private var finished = false

    init(maximumBytes: Int) {
        precondition(maximumBytes > 0)
        self.maximumBytes = maximumBytes
    }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = request.timeoutInterval
                configuration.timeoutIntervalForResource = request.timeoutInterval
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                let task = session.dataTask(with: request)
                self.task = task
                task.resume()
                lock.unlock()
            }
        } onCancel: {
            self.lock.lock()
            self.cancelled = true
            self.lock.unlock()
            self.finish(.failure(CancellationError()))
        }
    }

    private func finish(_ result: Result<(Data, URLResponse), any Error>) {
        lock.lock()
        guard !finished, let continuation else { lock.unlock(); return }
        finished = true
        self.continuation = nil
        let session = self.session
        self.session = nil
        self.task = nil
        body = Data()
        lock.unlock()
        session?.invalidateAndCancel()
        continuation.resume(with: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard response.expectedContentLength <= Int64(maximumBytes) else {
            completionHandler(.cancel)
            finish(.failure(StatusClientError.responseTooLarge))
            return
        }
        lock.lock()
        self.response = response
        let finished = self.finished
        lock.unlock()
        completionHandler(finished ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        let tooLarge = data.count > maximumBytes - body.count
        if !tooLarge { body.append(data) }
        lock.unlock()
        if tooLarge { finish(.failure(StatusClientError.responseTooLarge)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock()
        let response = self.response
        let body = self.body
        lock.unlock()
        if let error {
            finish(.failure(error))
        } else if let response {
            finish(.success((body, response)))
        } else {
            finish(.failure(URLError(.badServerResponse)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Follow HTTP(S) redirects but never downgrade an HTTPS request to plaintext.
        let scheme = request.url?.scheme?.lowercased()
        let downgrade = response.url?.scheme?.lowercased() == "https" && scheme == "http"
        completionHandler((scheme == "https" || scheme == "http") && !downgrade ? request : nil)
    }
}
