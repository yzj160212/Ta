import Foundation
import XCTest
@testable import AIScreenshotCore

final class OpenAICompatibleVisionClientTests: XCTestCase {
    override func tearDown() {
        VisionURLProtocol.handler = nil
        super.tearDown()
    }

    func testBuildsOpenAICompatibleVisionRequestAndParsesText() async throws {
        VisionURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            let body = try XCTUnwrap(Self.bodyData(from: request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "vision-model")
            let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
            let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
            let imagePart = try XCTUnwrap(content.first { ($0["type"] as? String) == "image_url" })
            let imageURL = try XCTUnwrap(imagePart["image_url"] as? [String: Any])
            XCTAssertEqual(imageURL["url"] as? String, "data:image/jpeg;base64,AQID")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"choices":[{"message":{"content":"识别结果"}}]}"#.utf8))
        }

        let result = try await makeClient().recognize(
            baseURL: "https://api.example.com/v1",
            model: "vision-model",
            apiKey: "secret",
            imageData: Data([1, 2, 3]),
            prompt: "识别图片"
        )
        XCTAssertEqual(result, "识别结果")
    }

    /// 局域网里的 Ollama 这类服务没有鉴权：不填 Key 也要能发请求，并且不带 Authorization 头。
    func testKeylessLanEndpointOmitsAuthorizationHeader() async throws {
        VisionURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://192.168.1.50:11434/v1/chat/completions")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"choices":[{"message":{"content":"局域网识别结果"}}]}"#.utf8))
        }

        let result = try await makeClient().recognize(
            baseURL: "http://192.168.1.50:11434/v1",
            model: "qwen2.5vl:7b",
            apiKey: "",
            imageData: Data([1, 2, 3]),
            prompt: "识别图片"
        )
        XCTAssertEqual(result, "局域网识别结果")
    }

    /// 公网服务仍然必须带 Key，缺了直接报错，不发请求。
    func testPublicEndpointStillRequiresAPIKey() async {
        VisionURLProtocol.handler = { _ in
            XCTFail("不应该发出请求")
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        do {
            _ = try await makeClient().recognize(
                baseURL: "https://api.example.com/v1",
                model: "vision-model",
                apiKey: "",
                imageData: Data([1]),
                prompt: "识别"
            )
            XCTFail("Expected missingAPIKey")
        } catch let error as VisionClientError {
            XCTAssertEqual(error, .missingAPIKey)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSurfacesProviderErrorMessage() async {
        VisionURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"error":{"message":"invalid key"}}"#.utf8))
        }
        do {
            _ = try await makeClient().recognize(
                baseURL: "https://api.example.com/v1",
                model: "vision-model",
                apiKey: "bad",
                imageData: Data([1]),
                prompt: "识别"
            )
            XCTFail("Expected server error")
        } catch let error as VisionClientError {
            XCTAssertEqual(error, .server(statusCode: 401, message: "invalid key"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeClient() -> OpenAICompatibleVisionClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VisionURLProtocol.self]
        return OpenAICompatibleVisionClient(session: URLSession(configuration: configuration))
    }

    func testZhipuVisionDisablesThinkingAndReasoningOnlyErrorIncludesGuidance() async throws {
        VisionURLProtocol.handler = { request in
            XCTAssertTrue(request.url?.host?.hasSuffix("bigmodel.cn") == true)
            let bodyData = try XCTUnwrap(Self.bodyData(from: request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            XCTAssertEqual((json["thinking"] as? [String: Any])?["type"] as? String, "disabled")
            XCTAssertEqual(json["max_tokens"] as? Int, 4096)
            let payload: [String: Any] = [
                "choices": [[
                    "message": [
                        "content": "",
                        "reasoning_content": "Inspecting layout and text regions first..."
                    ],
                    "finish_reason": "length"
                ]]
            ]
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(try! JSONSerialization.data(withJSONObject: payload)))
        }

        do {
            _ = try await makeClient().recognize(
                baseURL: "https://open.bigmodel.cn/api/paas/v4",
                model: "glm-4.5v",
                apiKey: "secret",
                imageData: Data([1]),
                prompt: "识别图片"
            )
            XCTFail("Expected reasoning-only error")
        } catch let error as VisionClientError {
            XCTAssertEqual(error, .reasoningOnlyOutput(truncated: true))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class VisionURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.handler?(request) ?? {
                throw VisionURLProtocolError.missingHandler
            }()
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private enum VisionURLProtocolError: Error {
    case missingHandler
}
