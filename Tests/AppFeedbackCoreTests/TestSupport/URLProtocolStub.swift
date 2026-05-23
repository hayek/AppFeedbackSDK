import Foundation

final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequestSnapshot) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var sequence: [Handler] = []

    static func respond(with handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        Self.handler = handler
        Self.sequence = []
    }

    /// Use when the test exercises a multi-request flow. Each subsequent call to
    /// `startLoading` consumes one handler from the front of the queue.
    static func enqueue(_ handlers: [Handler]) {
        lock.lock(); defer { lock.unlock() }
        Self.handler = nil
        Self.sequence = handlers
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        Self.handler = nil
        Self.sequence = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let active: Handler?
        if let single = Self.handler {
            active = single
        } else if !Self.sequence.isEmpty {
            active = Self.sequence.removeFirst()
        } else {
            active = nil
        }
        Self.lock.unlock()
        guard let active else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let snapshot = URLRequestSnapshot(request: request)
            let (response, data) = try active(snapshot)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

struct URLRequestSnapshot {
    let url: URL?
    let httpMethod: String?
    private let headerFields: [String: String]
    let bodyData: Data?

    init(request: URLRequest) {
        self.url = request.url
        self.httpMethod = request.httpMethod
        self.headerFields = request.allHTTPHeaderFields ?? [:]
        if let body = request.httpBody {
            self.bodyData = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buf.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buf, maxLength: 4096)
                if read <= 0 { break }
                collected.append(buf, count: read)
            }
            self.bodyData = collected
        } else {
            self.bodyData = nil
        }
    }

    func value(forHTTPHeaderField field: String) -> String? {
        headerFields.first { $0.key.caseInsensitiveCompare(field) == .orderedSame }?.value
    }
}
