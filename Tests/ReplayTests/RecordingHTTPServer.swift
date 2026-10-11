import Foundation

#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

/// A single-response loopback server that exercises URLSession's actual transport.
final class RecordingHTTPServer: @unchecked Sendable {
    let url: URL
    private let listener: Int32

    init(response: String, holdOpen: Bool = false) throws {
        #if canImport(Darwin)
            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        #else
            let descriptor = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(descriptor, 1) == 0 else {
            close(descriptor)
            throw POSIXError(.EIO)
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard result == 0 else {
            close(descriptor)
            throw POSIXError(.EIO)
        }
        listener = descriptor
        url = URL(string: "http://127.0.0.1:\(UInt16(bigEndian: address.sin_port))/response")!
        DispatchQueue.global().async {
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else { return }
            defer { close(client) }
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            _ = setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            #if canImport(Darwin)
                var enabled: Int32 = 1
                _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
            #endif
            var buffer = [UInt8](repeating: 0, count: 8192)
            guard recv(client, &buffer, buffer.count, 0) > 0 else { return }
            let bytes = Array(response.utf8)
            bytes.withUnsafeBytes { pointer in
                var sent = 0
                while sent < bytes.count {
                    #if canImport(Darwin)
                        let count = send(client, pointer.baseAddress!.advanced(by: sent), bytes.count - sent, 0)
                    #else
                        let count = send(
                            client, pointer.baseAddress!.advanced(by: sent), bytes.count - sent, Int32(MSG_NOSIGNAL))
                    #endif
                    guard count > 0 else { return }
                    sent += count
                }
            }
            if holdOpen {
                // Wait for the recording flush to cancel its transport.
                while recv(client, &buffer, buffer.count, 0) > 0 {}
            }
        }
    }

    deinit { close(listener) }
}
