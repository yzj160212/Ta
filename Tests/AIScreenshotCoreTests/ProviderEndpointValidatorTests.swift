import XCTest
@testable import AIScreenshotCore

/// 局域网里的 Ollama / 推理机要不要能填 http —— 这条以前被一刀切成「远程必须 HTTPS」，
/// 导致 `http://192.168.1.50:11434/v1` 直接填不进去。
final class ProviderEndpointValidatorTests: XCTestCase {
    private let validator = ProviderEndpointValidator()

    func testClassifiesLoopbackAddresses() {
        for address in [
            "http://localhost:11434/v1",
            "http://127.0.0.1:11434/v1",
            "https://127.0.0.1/v1",
            "http://[::1]:11434/v1"
        ] {
            XCTAssertEqual(validator.reach(of: address), .loopback, address)
            XCTAssertFalse(validator.requiresAPIKey(for: address), address)
            XCTAssertNil(validator.validationMessage(for: address), address)
        }
    }

    func testAllowsCleartextForPrivateNetworkAddresses() {
        for address in [
            "http://192.168.1.50:11434/v1",
            "http://10.0.0.9:8000/v1",
            "http://172.16.5.4:11434/v1",
            "http://172.31.255.1:11434/v1",
            "http://169.254.10.20:11434/v1",
            "http://ollama.local:11434/v1"
        ] {
            XCTAssertEqual(validator.reach(of: address), .privateNetwork, address)
            XCTAssertFalse(validator.requiresAPIKey(for: address), address)
            XCTAssertNil(validator.validationMessage(for: address), address)
        }
    }

    func testStillRequiresHTTPSForPublicHosts() {
        for address in [
            "http://api.openai.com/v1",
            "http://203.0.113.9/v1",
            "http://8.8.8.8/v1"
        ] {
            XCTAssertEqual(validator.reach(of: address), .publicInternet, address)
            XCTAssertTrue(validator.requiresAPIKey(for: address), address)
            XCTAssertNotNil(validator.validationMessage(for: address), address)
        }
    }

    func testAcceptsHTTPSForPublicHosts() {
        XCTAssertNil(validator.validationMessage(for: "https://api.deepseek.com"))
        XCTAssertEqual(validator.reach(of: "https://api.deepseek.com"), .publicInternet)
    }

    /// 局域网服务只填到端口时自动补 /v1，否则拼出的 …/chat/completions 会 404。
    func testNormalizesLocalEndpointWithoutPath() {
        XCTAssertEqual(
            validator.normalizedBaseURL("http://192.168.5.90:11434"),
            "http://192.168.5.90:11434/v1"
        )
        XCTAssertEqual(
            validator.normalizedBaseURL(" http://127.0.0.1:11434 "),
            "http://127.0.0.1:11434/v1"
        )
        XCTAssertTrue(validator.appendsVersionPath("http://192.168.5.90:11434"))
    }

    func testLeavesExplicitPathsAndPublicHostsAlone() {
        for address in [
            "http://192.168.5.90:11434/v1",
            "http://192.168.5.90:11434/v1/",
            "http://192.168.5.90:8000/custom/path",
            "https://api.deepseek.com",
            "https://api.openai.com/v1",
            "https://gateway.example.com/openai"
        ] {
            XCTAssertEqual(validator.normalizedBaseURL(address), address, address)
            XCTAssertFalse(validator.appendsVersionPath(address), address)
        }
    }

    func testInvalidOrEmptyInputFailsClosed() {
        XCTAssertNil(validator.reach(of: ""))
        XCTAssertNil(validator.reach(of: "api.openai.com/v1"))
        XCTAssertNil(validator.validationMessage(for: ""))
        XCTAssertTrue(validator.requiresAPIKey(for: ""), "无效地址必须按「需要密钥」处理")
        XCTAssertTrue(validator.requiresAPIKey(for: "ftp://192.168.1.2/v1"))
    }
}