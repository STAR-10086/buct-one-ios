import Foundation
import Security

/// 北化全端统一 TLS 校验代理。
/// 校验顺序：
/// 1. 先走系统默认信任库；
/// 2. 失败时附加校方内置 4 张证书（GlobalSign R3 链 / Sectigo E46 链）复验；
/// 3. 均失败则拒绝连接，绝不做无条件信任。
public final class BuctTlsDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    public static let shared = BuctTlsDelegate()

    private let bundledCertificates: [SecCertificate]

    public override init() {
        self.bundledCertificates = BuctCertificates.loadBundledCertificates()
        super.init()
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        if evaluateServerTrust(trust, host: host) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    public func evaluateServerTrust(_ trust: SecTrust, host: String) -> Bool {
        let policy = SecPolicyCreateSSL(true, host as CFString)
        SecTrustSetPolicies(trust, policy)

        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) {
            return true
        }

        guard !bundledCertificates.isEmpty else {
            return false
        }

        SecTrustSetAnchorCertificates(trust, bundledCertificates as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, false)

        error = nil
        return SecTrustEvaluateWithError(trust, &error)
    }
}
