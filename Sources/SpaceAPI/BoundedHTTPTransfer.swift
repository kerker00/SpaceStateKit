import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// All mutable state is protected by the lock. URLSession also serializes delegate callbacks.
final class BoundedHTTPTransfer: SharedSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var continuation: CheckedContinuation<(Data, URLResponse), any Error>?
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
                let task = SharedURLSessions.shared.dataTask(with: request, requestTimeout: request.timeoutInterval,
                                                             resourceTimeout: request.timeoutInterval, delegate: self)
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
        let task = self.task
        self.task = nil
        body = Data()
        lock.unlock()
        task?.cancel()
        continuation.resume(with: result)
    }

    func didReceive(response: URLResponse,
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

    func didReceive(data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        let tooLarge = data.count > maximumBytes - body.count
        if !tooLarge { body.append(data) }
        lock.unlock()
        if tooLarge { finish(.failure(StatusClientError.responseTooLarge)) }
    }

    func didComplete(error: (any Error)?) {
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

    func willRedirect(response: HTTPURLResponse, to request: URLRequest,
                      completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Follow HTTP(S) redirects but never downgrade an HTTPS request to plaintext.
        let scheme = request.url?.scheme?.lowercased()
        let downgrade = response.url?.scheme?.lowercased() == "https" && scheme == "http"
        let valid = request.url.map { (try? SpaceEndpoint.validate($0)) != nil } ?? false
        completionHandler(valid && !downgrade ? request : nil)
    }
}
