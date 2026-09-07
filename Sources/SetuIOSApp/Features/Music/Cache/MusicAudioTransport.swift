import Foundation

/// Delegate delivery keeps first-byte latency independent of the response's total size.
final class MusicAudioTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Event: @unchecked Sendable { case response(HTTPURLResponse), bytes(Data) }
    private var continuation: AsyncThrowingStream<Event, Error>.Continuation?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private let lock = NSLock()

    static func events(for request: URLRequest) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(64)) { continuation in
            let transport = MusicAudioTransport()
            transport.continuation = continuation
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 120
            let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: configuration, delegate: transport, delegateQueue: queue)
            transport.session = session
            transport.task = session.dataTask(with: request)
            continuation.onTermination = { @Sendable _ in transport.cancel() }
            transport.task?.resume()
        }
    }

    private func cancel() {
        lock.lock(); let session = session; self.session = nil; lock.unlock()
        session?.invalidateAndCancel()
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else {
            completionHandler(.cancel); continuation?.finish(throwing: URLError(.badServerResponse)); return
        }
        continuation?.yield(.response(response)); completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // A stalled disk/consumer must not accumulate an entire song in RAM.
        if case .dropped = continuation?.yield(.bytes(data)) {
            continuation?.finish(throwing: URLError(.dataLengthExceedsMaximum)); cancel()
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { continuation?.finish(throwing: error) } else { continuation?.finish() }
        cancel()
    }
}
