import XCTest
@testable import MacLimitsTrackerCore

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("Handler is unavailable.")
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class HttpTests: XCTestCase {
    private var originalSession: URLSession!

    override func setUp() {
        super.setUp()
        originalSession = Http.sharedSession

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        Http.sharedSession = URLSession(configuration: configuration)
    }

    override func tearDown() {
        Http.sharedSession = originalSession
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func test_httpGet_success_setsHeadersAndReturnsData() async throws {
        let expectedData = Data("{\"success\":true}".utf8)
        let expectedToken = "test_token"
        let expectedUserAgent = "test-agent/1.0"
        let url = URL(string: "https://api.example.com/data")!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url, url)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(expectedToken)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), expectedUserAgent)

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, expectedData)
        }

        let data = try await Http.httpGet(url, expectedToken, userAgent: expectedUserAgent)
        XCTAssertEqual(data, expectedData)
    }

    func test_httpGet_defaultUserAgent() async throws {
        let expectedData = Data("{}".utf8)
        let url = URL(string: "https://api.example.com/data")!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "claude-code/2.1.207")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, expectedData)
        }

        _ = try await Http.httpGet(url, "token")
    }

    func test_httpGet_non2xxResponse_throwsNSError() async {
        let url = URL(string: "https://api.example.com/data")!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await Http.httpGet(url, "token")
            XCTFail("Expected httpGet to throw an error, but it succeeded")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, "Network")
            XCTAssertEqual(error.code, 401)
            XCTAssertEqual(error.userInfo[NSLocalizedDescriptionKey] as? String, "HTTP 401")
        }
    }

    func test_httpGet_transportError_throwsError() async {
        let url = URL(string: "https://api.example.com/data")!
        let transportError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)

        MockURLProtocol.requestHandler = { request in
            throw transportError
        }

        do {
            _ = try await Http.httpGet(url, "token")
            XCTFail("Expected httpGet to throw an error, but it succeeded")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, NSURLErrorDomain)
            XCTAssertEqual(error.code, NSURLErrorNotConnectedToInternet)
        }
    }
}
