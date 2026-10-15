import XCTest
@testable import Textly

final class SSEParserTests: XCTestCase {
    private let parser = SSEParser()

    func testTextChunk() {
        let line = #"data: {"id":"1","choices":[{"index":0,"delta":{"role":"assistant","content":"Bon"}}]}"#
        XCTAssertEqual(parser.parse(line), [.text("Bon")])
    }

    func testCommentsAndOtherLinesAreIgnored() {
        XCTAssertEqual(parser.parse(": OPENROUTER PROCESSING"), [])
        XCTAssertEqual(parser.parse(""), [])
        XCTAssertEqual(parser.parse("event: message"), [])
        XCTAssertEqual(parser.parse("data: not json"), [])
    }

    func testDone() {
        XCTAssertEqual(parser.parse("data: [DONE]"), [.done])
    }

    func testUsageInTheLastChunk() {
        let line = #"data: {"choices":[{"delta":{"content":""},"finish_reason":"stop"}],"usage":{"prompt_tokens":120,"completion_tokens":30,"cost":0.00012}}"#
        XCTAssertEqual(parser.parse(line), [.usage(prompt: 120, completion: 30, cost: 0.00012)])
    }

    func testNullUsageIsIgnored() {
        let line = #"data: {"choices":[{"delta":{"content":"Hi"}}],"usage":null,"error":null}"#
        XCTAssertEqual(parser.parse(line), [.text("Hi")])
    }

    func testErrorMidStream() {
        let line = #"data: {"error":{"code":502,"message":"Provider returned error"},"choices":[{"delta":{"content":""},"finish_reason":"error"}]}"#
        XCTAssertEqual(parser.parse(line), [.error("Provider returned error")])
    }

    func testCompleteResponseFallback() throws {
        let json = #"{"choices":[{"message":{"role":"assistant","content":"Hello"}}],"usage":{"prompt_tokens":5,"completion_tokens":1}}"#
        let result = try AIClient.parseComplete(Data(json.utf8))
        XCTAssertEqual(result, CompletionResult(content: "Hello", promptTokens: 5, completionTokens: 1, cost: nil))
    }
}

final class AIClientTests: XCTestCase {
    private func request(_ endpoint: AIEndpoint) -> CompletionRequest {
        CompletionRequest(endpoint: endpoint, model: "m", system: "s", user: "u", temperature: 0.2, noTraining: true, fastMode: true)
    }

    func testOpenRouterBodyHasItsOptions() {
        let body = AIClient.body(for: request(.openRouter(apiKey: "k")), stream: true)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertNotNil(body["usage"])
        XCTAssertNotNil(body["provider"])
        XCTAssertNotNil(body["reasoning"])
        XCTAssertNil(body["stream_options"])
    }

    func testLocalBodyHasNoOpenRouterOptions() throws {
        let endpoint = try XCTUnwrap(AIEndpoint.local("localhost:11434"))
        let body = AIClient.body(for: request(endpoint), stream: true)
        XCTAssertNil(body["usage"])
        XCTAssertNil(body["provider"])
        XCTAssertNil(body["reasoning"])
        XCTAssertNotNil(body["stream_options"])
        XCTAssertEqual(body["model"] as? String, "m")
    }

    func testLocalAddresses() {
        XCTAssertEqual(LocalServer.normalisedURL("localhost:11434")?.absoluteString, "http://localhost:11434/v1")
        XCTAssertEqual(LocalServer.normalisedURL("http://localhost:1234/v1/")?.absoluteString, "http://localhost:1234/v1")
        XCTAssertEqual(LocalServer.normalisedURL(" http://192.168.1.20:8080/api/v1 ")?.absoluteString, "http://192.168.1.20:8080/api/v1")
        XCTAssertNil(LocalServer.normalisedURL(""))
        XCTAssertNil(LocalServer.normalisedURL("ftp://localhost"))
    }

    func testLocalErrorsAreFriendly() throws {
        let endpoint = try XCTUnwrap(AIEndpoint.local(LocalServer.ollama))
        XCTAssertTrue(AIClient.friendly(status: 404, message: "model \"x\" not found", endpoint: endpoint).contains("doesn't have this model"))
        XCTAssertTrue(AIClient.friendly(status: 401, message: "", endpoint: .openRouter(apiKey: "k")).contains("API key"))
    }
}

final class UpdateTests: XCTestCase {
    func testVersionComparison() throws {
        func v(_ text: String) throws -> AppVersion { try XCTUnwrap(AppVersion(text)) }
        XCTAssertLessThan(try v("0.3.0"), try v("0.4.0"))
        XCTAssertLessThan(try v("0.9.9"), try v("0.10.0"))
        XCTAssertLessThan(try v("1.2"), try v("1.2.1"))
        XCTAssertEqual(try v("v1.2.0"), try v("1.2"))
        XCTAssertEqual(try v("0.4.0-beta"), try v("0.4.0"))
        XCTAssertFalse(try v("0.4.0") < v("0.4.0"))
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion(""))
    }

    func testReleaseParsing() throws {
        let json = """
        {"tag_name": "v0.5.0", "html_url": "https://github.com/a/b/releases/tag/v0.5.0", "draft": false, "prerelease": false,
         "body": "Notes", "assets": [{"name": "Textly-0.5.0.dmg", "browser_download_url": "https://github.com/a/b/releases/download/v0.5.0/Textly-0.5.0.dmg"}]}
        """
        let release = try XCTUnwrap(ReleaseInfo.parse(Data(json.utf8)))
        XCTAssertEqual(release.version, "v0.5.0")
        XCTAssertEqual(release.downloadURL?.lastPathComponent, "Textly-0.5.0.dmg")
        XCTAssertEqual(release.notes, "Notes")
    }

    func testPrereleasesAreIgnored() {
        let json = #"{"tag_name": "v0.6.0", "html_url": "https://x.y", "prerelease": true}"#
        XCTAssertNil(ReleaseInfo.parse(Data(json.utf8)))
    }
}
