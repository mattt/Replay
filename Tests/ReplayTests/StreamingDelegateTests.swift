import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing

@testable import Replay

@Suite("Streaming Delegate Tests")
struct StreamingDelegateTests {
    private let url = URL(string: "https://example.com/stream")!

    /// Calls `waitForResponse()` and returns `nil` instead of hanging
    /// if the delegate never resumes the wait.
    private func waitForResponse(
        from delegate: StreamingDelegate,
        timeoutNanoseconds: UInt64 = 5_000_000_000
    ) async -> Result<HTTPURLResponse, Error>? {
        final class Once: @unchecked Sendable {
            private let lock = NSLock()
            private var continuation: CheckedContinuation<Result<HTTPURLResponse, Error>?, Never>?

            init(_ continuation: CheckedContinuation<Result<HTTPURLResponse, Error>?, Never>) {
                self.continuation = continuation
            }

            func resume(_ value: Result<HTTPURLResponse, Error>?) {
                lock.lock()
                let continuation = self.continuation
                self.continuation = nil
                lock.unlock()
                continuation?.resume(returning: value)
            }
        }

        return await withCheckedContinuation { continuation in
            let once = Once(continuation)
            Task {
                do {
                    once.resume(.success(try await delegate.waitForResponse()))
                } catch {
                    once.resume(.failure(error))
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                once.resume(nil)
            }
        }
    }

    private func makeDataTask() -> (URLSession, URLSessionDataTask) {
        let session = URLSession(configuration: .ephemeral)
        // The task is never resumed; it only stands in for the callback arguments.
        return (session, session.dataTask(with: url))
    }

    @Test("Response that arrives before the wait is delivered")
    func responseBeforeWait() async throws {
        let delegate = StreamingDelegate()
        let (session, dataTask) = makeDataTask()
        defer { session.invalidateAndCancel() }

        let response = try #require(
            HTTPURLResponse(url: url, statusCode: 202, httpVersion: "HTTP/1.1", headerFields: nil)
        )
        var disposition: URLSession.ResponseDisposition?
        delegate.urlSession(session, dataTask: dataTask, didReceive: response) { disposition = $0 }
        #expect(disposition == .allow)

        let result = try #require(
            await waitForResponse(from: delegate),
            "waitForResponse() did not return a response that arrived before the wait"
        )
        #expect(try result.get().statusCode == 202)
    }

    @Test("Response and data that arrive before the wait are both delivered")
    func responseAndDataBeforeWait() async throws {
        let delegate = StreamingDelegate()
        let (session, dataTask) = makeDataTask()
        defer { session.invalidateAndCancel() }

        let response = try #require(
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
        )
        delegate.urlSession(session, dataTask: dataTask, didReceive: response) { _ in }
        delegate.urlSession(session, dataTask: dataTask, didReceive: Data("hello".utf8))
        delegate.urlSession(session, task: dataTask, didCompleteWithError: nil)

        let result = try #require(await waitForResponse(from: delegate))
        #expect(try result.get().statusCode == 200)

        var body = Data()
        for try await chunk in delegate.dataStream {
            body.append(chunk)
        }
        #expect(body == Data("hello".utf8))
    }

    @Test("Error that arrives before the wait is thrown")
    func errorBeforeWait() async throws {
        let delegate = StreamingDelegate()
        let (session, dataTask) = makeDataTask()
        defer { session.invalidateAndCancel() }

        delegate.urlSession(session, task: dataTask, didCompleteWithError: URLError(.timedOut))

        let result = try #require(await waitForResponse(from: delegate))
        #expect(throws: URLError(.timedOut)) { try result.get() }
    }

    @Test("Completion without an HTTP response fails the wait")
    func completionWithoutResponse() async throws {
        let delegate = StreamingDelegate()
        let (session, dataTask) = makeDataTask()
        defer { session.invalidateAndCancel() }

        delegate.urlSession(session, task: dataTask, didCompleteWithError: nil)

        let result = try #require(await waitForResponse(from: delegate))
        #expect(throws: URLError(.badServerResponse)) { try result.get() }
    }

    @Test("Response that arrives after the wait begins is delivered")
    func responseAfterWait() async throws {
        let delegate = StreamingDelegate()
        let (session, dataTask) = makeDataTask()
        defer { session.invalidateAndCancel() }

        let response = try #require(
            HTTPURLResponse(url: url, statusCode: 201, httpVersion: "HTTP/1.1", headerFields: nil)
        )
        async let result = waitForResponse(from: delegate)
        // Give the waiter time to store its continuation; either order must work.
        try await Task.sleep(nanoseconds: 50_000_000)
        delegate.urlSession(session, dataTask: dataTask, didReceive: response) { _ in }

        let delivered = try #require(await result)
        #expect(try delivered.get().statusCode == 201)
    }
}
