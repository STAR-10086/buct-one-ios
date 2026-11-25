import Foundation

/// 北化 WebVPN（w.buct.edu.cn，Wengine 网关）URL 编解码与域名识别。
public enum BuctWebVpnCodec {
    public static let vpnHost = "w.buct.edu.cn"
    public static let vpnBase = "https://w.buct.edu.cn"
    public static let vpnCookieName = "wengine_vpn_ticketw_buct_edu_cn"

    private static let cryptKey = Data("wrdvpnisthebest!".utf8)
    private static let cryptIV = Data("wrdvpnisthebest!".utf8)

    public static let campusOnlyHosts: Set<String> = [
        "scs.buct.edu.cn",
        "eapi.buct.edu.cn",
        "ecard.buct.edu.cn",
        "gmis.buct.edu.cn",
        "i.buct.edu.cn",
        "mnews.buct.edu.cn",
        "tree.buct.edu.cn"
    ]

    public static func isCampusOnlyHost(_ host: String) -> Bool {
        campusOnlyHosts.contains(host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    public static func encryptHost(_ host: String) throws -> String {
        let plain = Data(host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().utf8)
        let encrypted = try BuctCrypto.aes128CFB128Encrypt(plaintext: plain, key: cryptKey, iv: cryptIV)
        return toLowerHex(cryptIV) + toLowerHex(encrypted)
    }

    public static func decryptHost(_ hexToken: String) -> String? {
        let clean = hexToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > 32, clean.count % 2 == 0 else { return nil }
        let splitIdx = clean.index(clean.startIndex, offsetBy: 32)
        guard let tokenIV = hexToData(String(clean[..<splitIdx])),
              let ciphertext = hexToData(String(clean[splitIdx...])) else {
            return nil
        }
        guard let plainData = try? BuctCrypto.aes128CFB128Decrypt(ciphertext: ciphertext, key: cryptKey, iv: tokenIV),
              let host = String(data: plainData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty,
              !host.contains(where: { $0 <= " " || $0 == "/" || $0 == "\\" }) else {
            return nil
        }
        return host
    }

    public static func toVpnURL(_ original: URL) throws -> URL {
        guard let components = URLComponents(url: original, resolvingAgainstBaseURL: false),
              let host = components.host else {
            return original
        }
        if host.caseInsensitiveCompare(vpnHost) == .orderedSame {
            return original
        }
        let scheme = (components.scheme ?? "https").lowercased()
        let defaultPort = (scheme == "https") ? 443 : 80
        let protoSeg: String
        if let port = components.port, port != defaultPort {
            protoSeg = "\(scheme)-\(port)"
        } else {
            protoSeg = scheme
        }
        let encHost = try encryptHost(host)
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        let fragment = components.percentEncodedFragment.map { "#\($0)" } ?? ""
        guard let vpnURL = URL(string: "\(vpnBase)/\(protoSeg)/\(encHost)\(path)\(query)\(fragment)") else {
            return original
        }
        return vpnURL
    }

    public static func fromVpnURL(_ vpnURL: URL) -> URL? {
        guard let components = URLComponents(url: vpnURL, resolvingAgainstBaseURL: false),
              let vpnHostVal = components.host,
              vpnHostVal.caseInsensitiveCompare(vpnHost) == .orderedSame else {
            return nil
        }
        let path = components.percentEncodedPath
        guard path.hasPrefix("/") else { return nil }
        let trimmed = String(path.dropFirst())
        guard let firstSlash = trimmed.firstIndex(of: "/") else { return nil }
        let protoSeg = String(trimmed[..<firstSlash]).lowercased()
        let restAfterProto = String(trimmed[trimmed.index(after: firstSlash)...])

        let encHost: String
        let restPath: String
        if let secondSlash = restAfterProto.firstIndex(of: "/") {
            encHost = String(restAfterProto[..<secondSlash])
            restPath = String(restAfterProto[secondSlash...])
        } else {
            encHost = restAfterProto
            restPath = "/"
        }

        let scheme: String
        let port: Int?
        if protoSeg == "http" {
            scheme = "http"
            port = nil
        } else if protoSeg == "https" {
            scheme = "https"
            port = nil
        } else if protoSeg.hasPrefix("http-") {
            guard let parsedPort = Int(protoSeg.dropFirst("http-".count)), (1...65535).contains(parsedPort) else {
                return nil
            }
            scheme = "http"
            port = parsedPort
        } else if protoSeg.hasPrefix("https-") {
            guard let parsedPort = Int(protoSeg.dropFirst("https-".count)), (1...65535).contains(parsedPort) else {
                return nil
            }
            scheme = "https"
            port = parsedPort
        } else {
            return nil
        }

        guard let host = decryptHost(encHost) else { return nil }
        var out = URLComponents()
        out.scheme = scheme
        out.host = host
        out.port = port
        out.percentEncodedPath = restPath
        out.percentEncodedQuery = components.percentEncodedQuery
        out.percentEncodedFragment = components.percentEncodedFragment
        return out.url
    }

    private static func toLowerHex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func hexToData(_ hex: String) -> Data? {
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let nextIdx = hex.index(idx, offsetBy: 2)
            guard let byte = UInt8(hex[idx..<nextIdx], radix: 16) else { return nil }
            data.append(byte)
            idx = nextIdx
        }
        return data
    }
}
