import Foundation

/// Delegate delivery keeps first-byte latency independent of the response's total size.
final class MusicAudioTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Event: @unchecked Sendable { case response(HTTPURLResponse), bytes(Data); case checkpoint(@Sendable () -> Void); case cancellation(@Sendable () -> Void) }
    private var continuation: AsyncThrowingStream<Event, Error>.Continuation?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private let lock = NSLock()
    private var pendingBytes = 0
    private var suspended = false

    static func events(for request: URLRequest) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
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
            continuation.yield(.cancellation { transport.cancel() })
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
        lock.lock()
        pendingBytes += data.count
        if pendingBytes >= 512 * 1024, !suspended {
            suspended = true; dataTask.suspend()
        }
        lock.unlock()
        continuation?.yield(.bytes(data))
        let count = data.count
        continuation?.yield(.checkpoint { [weak self] in self?.consumed(count) })
    }
    private func consumed(_ count: Int) {
        lock.lock(); defer { lock.unlock() }
        pendingBytes = max(0, pendingBytes - count)
        if suspended, pendingBytes <= 256 * 1024, session != nil {
            suspended = false; task?.resume()
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { continuation?.finish(throwing: error) } else { continuation?.finish() }
        cancel()
    }
}
