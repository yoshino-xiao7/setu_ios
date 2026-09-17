import Foundation

/// Incrementally surfaces SSE `data:` payloads via URLSession callbacks.
/// Prefer this over `URLSession.AsyncBytes.lines`, which often appears fully buffered on device.
final class ServerSentEventDataTask: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let requestID: String
    private let onEvent: @Sendable (Data) -> Void
    private let onComplete: @Sendable (Error?) -> Void
    private var buffer = Data()
    private var response: HTTPURLResponse?
    private var errorBody = Data()
    private var completed = false
    private var session: URLSession?

    init(
        requestID: String,
        onEvent: @escaping @Sendable (Data) -> Void,
        onComplete: @escaping @Sendable (Error?) -> Void
    ) {
        self.requestID = requestID
        self.onEvent = onEvent
        self.onComplete = onComplete
    }

    func start(request: URLRequest, configuration: URLSessionConfiguration) {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        lock.lock()
        self.session = session
        lock.unlock()
        session.dataTask(with: request).resume()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let http = response as? HTTPURLResponse
        lock.lock()
        self.response = http
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let status = response?.statusCode
        if let status, !(200..<300).contains(status) {
            if errorBody.count < 8_192 {
                let room = 8_192 - errorBody.count
                errorBody.append(data.prefix(room))
            }
            lock.unlock()
            return
        }
        buffer.append(data)
        let payloads = Self.drainSSEPayloads(from: &buffer)
        lock.unlock()
        for payload in payloads {
            onEvent(payload)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error)
    }

    private func finish(_ error: Error?) {
        lock.lock()
        if completed {
            lock.unlock()
            return
        }
        completed = true
        let status = response?.statusCode
        let errorBody = self.errorBody
        var trailingBuffer = buffer
        buffer = Data()
        let session = self.session
        self.session = nil
        lock.unlock()

        if let error {
            onComplete(error)
            session?.invalidateAndCancel()
            return
        }

        var trailing = Self.drainSSEPayloads(from: &trailingBuffer)
        if let last = AiChatDrawBilling.sseDataPayload(in: String(data: trailingBuffer, encoding: .utf8) ?? "") {
            trailing.append(Data(last.utf8))
        }
        for payload in trailing {
            onEvent(payload)
        }

        if response == nil {
            onComplete(APIError.invalidResponse)
        } else if let status, !(200..<300).contains(status) {
            onComplete(
                APIError.httpStatus(
                    status,
                    message: String(data: errorBody, encoding: .utf8),
                    requestID: requestID,
                    traceID: nil,
                    code: nil
                )
            )
        } else {
            onComplete(nil)
        }
        session?.invalidateAndCancel()
    }

    /// Extracts complete SSE blocks terminated by a blank line.
    static func drainSSEPayloads(from buffer: inout Data) -> [Data] {
        var payloads: [Data] = []
        while let separator = buffer.range(of: Data([0x0A, 0x0A])) // \n\n
            ?? buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) // \r\n\r\n
        {
            let chunk = buffer.subdata(in: buffer.startIndex..<separator.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<separator.upperBound)
            let text = String(data: chunk, encoding: .utf8) ?? ""
            if let payload = AiChatDrawBilling.sseDataPayload(in: text) {
                payloads.append(Data(payload.utf8))
            }
        }
        return payloads
    }
}
