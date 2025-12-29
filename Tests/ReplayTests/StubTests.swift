import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing

@testable import Replay

@Suite("Stub Tests", .serialized)
struct StubTests {

    // MARK: - Stub Initializers

    @Suite("Stub Initializers")
    struct StubInitializerTests {
        @Test("initializes with URL and default values")
        func initWithURL() {
            let url = URL(string: "https://example.com/api")!
            let stub = Stub(.get, url)

            #expect(stub.method == .get)
            #expect(stub.url == url)
            #expect(stub.status == 200)
            #expect(stub.headers.isEmpty)
            #expect(stub.body == nil)
            #expect(stub.sourceLocation != nil)
        }

        @Test("initializes with URL string")
        func initWithURLString() {
            let stub = Stub(.post, "https://example.com/api")

            #expect(stub.method == .post)
            #expect(stub.url.absoluteString == "https://example.com/api")
            #expect(stub.status == 200)
        }

        @Test("initializes with custom status and headers")
        func initWithStatusAndHeaders() {
            let url = URL(string: "https://example.com/api")!
            let stub = Stub(
                .put,
                url,
                status: 201,
                headers: ["Content-Type": "application/json"]
            )

            #expect(stub.status == 201)
            #expect(stub.headers["Content-Type"] == "application/json")
        }

        @Test("initializes with body Data")
        func initWithBodyData() {
            let url = URL(string: "https://example.com/api")!
            let body = "test data".data(using: .utf8)!
            let stub = Stub(.post, url, body: body)

            #expect(stub.body == body)
        }

        @Test("initializes with body String")
        func initWithBodyString() {
            let url = URL(string: "https://example.com/api")!
            let stub = Stub(.post, url, body: "test response")

            #expect(stub.body == "test response".data(using: .utf8))
        }

        @Test("initializes with body String and URL string")
        func initWithBodyStringAndURLString() {
            let stub = Stub(.get, "https://example.com/api", body: "response")

            #expect(stub.url.absoluteString == "https://example.com/api")
            #expect(stub.body == "response".data(using: .utf8))
        }

        @Test("captures source location")
        func capturesSourceLocation() {
            let stub = Stub(.get, URL(string: "https://example.com")!)

            #expect(stub.sourceLocation != nil)
            #expect(stub.sourceLocation?.file.contains("StubTests.swift") == true)
        }
    }

    // MARK: - Stub.Method Tests

    @Suite("Stub.Method Tests")
    struct MethodTests {
        @Test("initializes from rawValue for standard methods")
        func initFromRawValueStandard() {
            #expect(Stub.Method(rawValue: "GET") == .get)
            #expect(Stub.Method(rawValue: "POST") == .post)
            #expect(Stub.Method(rawValue: "PUT") == .put)
            #expect(Stub.Method(rawValue: "DELETE") == .delete)
            #expect(Stub.Method(rawValue: "PATCH") == .patch)
            #expect(Stub.Method(rawValue: "HEAD") == .head)
            #expect(Stub.Method(rawValue: "OPTIONS") == .options)
            #expect(Stub.Method(rawValue: "TRACE") == .trace)
            #expect(Stub.Method(rawValue: "CONNECT") == .connect)
        }

        @Test("initializes from rawValue case-insensitively")
        func initFromRawValueCaseInsensitive() {
            #expect(Stub.Method(rawValue: "get") == .get)
            #expect(Stub.Method(rawValue: "Get") == .get)
            #expect(Stub.Method(rawValue: "POST") == .post)
            #expect(Stub.Method(rawValue: "post") == .post)
        }

        @Test("initializes custom method for unknown values")
        func initFromRawValueCustom() {
            let method = Stub.Method(rawValue: "CUSTOM")
            if case .custom(let value) = method {
                #expect(value == "CUSTOM")
            } else {
                Issue.record("Expected custom method")
            }
        }

        @Test("rawValue returns correct string for standard methods")
        func rawValueStandard() {
            #expect(Stub.Method.get.rawValue == "GET")
            #expect(Stub.Method.post.rawValue == "POST")
            #expect(Stub.Method.put.rawValue == "PUT")
            #expect(Stub.Method.delete.rawValue == "DELETE")
            #expect(Stub.Method.patch.rawValue == "PATCH")
            #expect(Stub.Method.head.rawValue == "HEAD")
            #expect(Stub.Method.options.rawValue == "OPTIONS")
            #expect(Stub.Method.trace.rawValue == "TRACE")
            #expect(Stub.Method.connect.rawValue == "CONNECT")
        }

        @Test("rawValue returns custom string for custom methods")
        func rawValueCustom() {
            let method = Stub.Method.custom("CUSTOM")
            #expect(method.rawValue == "CUSTOM")
        }

        @Test("description matches rawValue")
        func description() {
            #expect(Stub.Method.get.description == "GET")
            #expect(Stub.Method.post.description == "POST")
            let custom = Stub.Method.custom("CUSTOM")
            #expect(custom.description == "CUSTOM")
        }

        @Test("equality is case-insensitive")
        func equalityCaseInsensitive() {
            #expect(Stub.Method.get == Stub.Method(rawValue: "GET"))
            #expect(Stub.Method.get == Stub.Method(rawValue: "get"))
            #expect(Stub.Method.get == Stub.Method(rawValue: "Get"))
            #expect(Stub.Method.post == Stub.Method(rawValue: "POST"))
        }

        @Test("equality for custom methods")
        func equalityCustom() {
            let method1 = Stub.Method.custom("CUSTOM")
            let method2 = Stub.Method(rawValue: "CUSTOM")
            if case .custom(let value) = method2 {
                #expect(method1.rawValue.uppercased() == value.uppercased())
            } else {
                Issue.record("Expected custom method")
            }
        }

        @Test("hashing is case-insensitive")
        func hashingCaseInsensitive() {
            let method1 = Stub.Method.get
            let method2 = Stub.Method(rawValue: "GET")
            let method3 = Stub.Method(rawValue: "get")

            var hasher1 = Hasher()
            var hasher2 = Hasher()
            var hasher3 = Hasher()

            method1.hash(into: &hasher1)
            method2.hash(into: &hasher2)
            method3.hash(into: &hasher3)

            #expect(hasher1.finalize() == hasher2.finalize())
            #expect(hasher2.finalize() == hasher3.finalize())
        }
    }

    // MARK: - Stub.SourceLocation Tests

    @Suite("Stub.SourceLocation Tests")
    struct SourceLocationTests {
        @Test("initializes with file and line")
        func initWithFileAndLine() {
            let location = Stub.SourceLocation(file: "/path/to/file.swift", line: 42)

            #expect(location.file == "/path/to/file.swift")
            #expect(location.line == 42)
        }

        @Test("description includes filename and line")
        func description() {
            let location = Stub.SourceLocation(file: "/path/to/TestFile.swift", line: 123)

            let description = location.description
            #expect(description.contains("TestFile.swift"))
            #expect(description.contains("123"))
        }

        @Test("description uses last path component")
        func descriptionUsesLastPathComponent() {
            let location = Stub.SourceLocation(file: "/very/long/path/to/File.swift", line: 5)

            #expect(!location.description.contains("very"))
            #expect(location.description.contains("File.swift"))
        }

        @Test("is Hashable")
        func isHashable() {
            let location1 = Stub.SourceLocation(file: "/file.swift", line: 1)
            let location2 = Stub.SourceLocation(file: "/file.swift", line: 1)
            let location3 = Stub.SourceLocation(file: "/file.swift", line: 2)

            #expect(location1 == location2)
            #expect(location1 != location3)
        }
    }

    // MARK: - Factory Methods Tests

    @Suite("Stub Factory Methods")
    struct FactoryMethodTests {
        @Test("get factory method")
        func getFactory() {
            let stub = Stub.get("https://example.com/api", 200, ["Content-Type": "text/plain"]) {
                "response body"
            }

            #expect(stub.method == .get)
            #expect(stub.url.absoluteString == "https://example.com/api")
            #expect(stub.status == 200)
            #expect(stub.headers["Content-Type"] == "text/plain")
            #expect(stub.body == "response body".data(using: .utf8))
        }

        @Test("post factory method")
        func postFactory() {
            let stub = Stub.post("https://example.com/api", 201, [:]) {
                "created"
            }

            #expect(stub.method == .post)
            #expect(stub.status == 201)
        }

        @Test("put factory method")
        func putFactory() {
            let stub = Stub.put("https://example.com/api", 200, [:]) {
                "updated"
            }

            #expect(stub.method == .put)
        }

        @Test("delete factory method")
        func deleteFactory() {
            let stub = Stub.delete("https://example.com/api", 204, [:]) {
                "deleted"
            }

            #expect(stub.method == .delete)
            #expect(stub.status == 204)
        }

        @Test("patch factory method")
        func patchFactory() {
            let stub = Stub.patch("https://example.com/api", 200, [:]) {
                "patched"
            }

            #expect(stub.method == .patch)
        }

        @Test("head factory method")
        func headFactory() {
            let stub = Stub.head("https://example.com/api", 200, ["ETag": "abc123"])

            #expect(stub.method == .head)
            #expect(stub.body == nil)
            #expect(stub.headers["ETag"] == "abc123")
        }

        @Test("options factory method")
        func optionsFactory() {
            let stub = Stub.options("https://example.com/api", 200, ["Allow": "GET, POST"])

            #expect(stub.method == .options)
            #expect(stub.body == nil)
        }

        @Test("trace factory method")
        func traceFactory() {
            let stub = Stub.trace("https://example.com/api", 200, [:])

            #expect(stub.method == .trace)
        }

        @Test("connect factory method")
        func connectFactory() {
            let stub = Stub.connect("https://example.com/api", 200, [:])

            #expect(stub.method == .connect)
        }
    }
}
