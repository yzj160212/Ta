import Foundation

/// 校验模型服务的 Base URL，并判断它处在本机的哪一层网络里。
///
/// 规则：
/// - 公网服务必须 HTTPS（密钥会明文出现在请求头里，不能被中间人截获）；
/// - 回环地址（本机服务）与私有网段（局域网里的 Ollama / 推理机）允许 http，
///   这类服务往往本来就没有鉴权，也不会把图片和密钥送进公网；
/// - 私有网段的 http 依旧是明文，所以只在「本机或同一个局域网」这个前提下放开。
public struct ProviderEndpointValidator: Sendable {
    public enum Reach: Equatable, Sendable {
        /// 127.0.0.0/8、::1、localhost
        case loopback
        /// 10/8、172.16/12、192.168/16、169.254/16、fc00::/7、fe80::/10、*.local
        case privateNetwork
        /// 其余一切需要走公网的目标
        case publicInternet
    }

    public init() {}

    /// 解析 Base URL 所处的网络层级；URL 无效时返回 nil。
    public func reach(of rawValue: String) -> Reach? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }

        if host == "localhost" || host.hasSuffix(".localhost") || host == "::1" || host == "[::1]" {
            return .loopback
        }
        if let octets = ipv4Octets(host) {
            if octets[0] == 127 { return .loopback }
            if octets[0] == 10 { return .privateNetwork }
            if octets[0] == 172, (16...31).contains(octets[1]) { return .privateNetwork }
            if octets[0] == 192, octets[1] == 168 { return .privateNetwork }
            if octets[0] == 169, octets[1] == 254 { return .privateNetwork }
            return .publicInternet
        }
        if host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe80") {
            // IPv6 ULA (fc00::/7) 与 link-local (fe80::/10)
            return .privateNetwork
        }
        if host.hasSuffix(".local") {
            return .privateNetwork
        }
        return .publicInternet
    }

    /// 是否为本机或同一局域网内的地址。
    public func isLocal(_ rawValue: String) -> Bool {
        guard let reach = reach(of: rawValue) else { return false }
        return reach != .publicInternet
    }

    /// 本地服务通常不校验密钥（如 Ollama），只有公网服务才强制要求 API Key。
    /// URL 无效时按「需要密钥」处理，宁可多要求一次也不放过。
    public func requiresAPIKey(for rawValue: String) -> Bool {
        guard let reach = reach(of: rawValue) else { return true }
        return reach == .publicInternet
    }

    public func validationMessage(for rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            return "Base URL 格式无效"
        }
        if scheme != "https", !(scheme == "http" && isLocal(trimmed)) {
            return "远程服务必须使用 HTTPS；只有本机（localhost/127.0.0.1）或局域网私有地址（192.168.x / 10.x / 172.16-31.x）可以用 http"
        }
        return nil
    }

    private func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets: [Int] = []
        for part in parts {
            guard let value = Int(part), (0...255).contains(value) else { return nil }
            octets.append(value)
        }
        return octets
    }
}