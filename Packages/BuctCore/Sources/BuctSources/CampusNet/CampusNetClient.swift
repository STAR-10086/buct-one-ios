import BuctModel
import BuctNetwork
import Foundation

public actor CampusNetClient {
    private static let portalBase = "https://tree.buct.edu.cn"
    private static let selfServiceBase = "http://tree.buct.edu.cn:8800"
    private static let mobileUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
    private static let maxRedirectHops = 6

    private let webVpn: BuctWebVpnManager
    private let jar = MatchingMemoryCookieJar()

    public init(webVpn: BuctWebVpnManager = .shared) {
        self.webVpn = webVpn
    }

    public func fetchSnapshot(fallbackStudentId: String, appVersion: String) async throws -> CampusNetSnapshot {
        let ua = "\(Self.mobileUA) BuctOne/\(appVersion)"
        var rad: CampusNetRadInfo?
        var webVpnError: BuctWebVpnAuthRequiredError?

        do {
            rad = try await fetchRadUserInfo(userAgent: ua)
        } catch let err as BuctWebVpnAuthRequiredError {
            webVpnError = err
        } catch {
            rad = nil
        }

        let resolvedId = (rad?.username.isEmpty == false ? rad!.username : fallbackStudentId)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var home: CampusNetSelfServiceHome?
        var payRecords: [CampusNetPayRecord] = []
        var checkoutRecords: [CampusNetCheckoutRecord] = []

        if !resolvedId.isEmpty {
            do {
                home = try await fetchSelfServiceHome(studentId: resolvedId, userAgent: ua)
                if home != nil {
                    payRecords = (try? await fetchPayRecords(userAgent: ua)) ?? []
                    checkoutRecords = (try? await fetchCheckoutRecords(userAgent: ua)) ?? []
                }
            } catch let err as BuctWebVpnAuthRequiredError {
                webVpnError = err
            } catch {
                home = nil
            }
        }

        if let webVpnError, rad == nil && home == nil {
            throw webVpnError
        }
        guard rad != nil || home != nil else {
            throw NSError(
                domain: "CampusNetClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法连接校园网服务，请确认已连接校园网或完成 WebVPN 认证"]
            )
        }

        return CampusNetParser.merge(
            studentId: resolvedId,
            rad: rad,
            home: home,
            payRecords: payRecords,
            checkoutRecords: checkoutRecords
        )
    }

    private func fetchRadUserInfo(userAgent: String) async throws -> CampusNetRadInfo? {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let urlStr = "\(Self.portalBase)/cgi-bin/rad_user_info?callback=jQuery11240000000000000000_\(nowMs)&_=\(nowMs)"
        guard let url = URL(string: urlStr) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("\(Self.portalBase)/", forHTTPHeaderField: "Referer")
        let resp = try await webVpn.execute(req, cookieJar: jar, timeout: 15)
        guard resp.statusCode == 200 else { return nil }
        return CampusNetParser.parseRadUserInfo(jsonp: resp.decodedText())
    }

    private func fetchSelfServiceHome(studentId: String, userAgent: String) async throws -> CampusNetSelfServiceHome? {
        jar.clear()
        let token = Data("zh-CN:\(studentId)".utf8).base64EncodedString()
        var comps = URLComponents(string: "\(Self.selfServiceBase)/site/sso")!
        comps.queryItems = [URLQueryItem(name: "data", value: token)]
        guard let startURL = comps.url else { return nil }

        let resp = try await sendFollowingRedirects(
            url: startURL,
            referer: "\(Self.portalBase)/",
            userAgent: userAgent
        )
        guard resp.statusCode == 200 else { return nil }
        return CampusNetParser.parseSelfServiceHome(html: resp.decodedText())
    }

    private func fetchPayRecords(userAgent: String) async throws -> [CampusNetPayRecord] {
        guard let url = URL(string: "\(Self.selfServiceBase)/log/pay") else { return [] }
        let resp = try await sendFollowingRedirects(
            url: url,
            referer: "\(Self.selfServiceBase)/home",
            userAgent: userAgent
        )
        guard resp.statusCode == 200 else { return [] }
        return CampusNetParser.parsePayRecords(html: resp.decodedText())
    }

    private func fetchCheckoutRecords(userAgent: String) async throws -> [CampusNetCheckoutRecord] {
        guard let url = URL(string: "\(Self.selfServiceBase)/log/check-out") else { return [] }
        let resp = try await sendFollowingRedirects(
            url: url,
            referer: "\(Self.selfServiceBase)/home",
            userAgent: userAgent
        )
        guard resp.statusCode == 200 else { return [] }
        return CampusNetParser.parseCheckoutRecords(html: resp.decodedText())
    }

    private func sendFollowingRedirects(url: URL, referer: String, userAgent: String) async throws -> HttpResponseData {
        var current = url
        var currentReferer = referer
        for _ in 0..<Self.maxRedirectHops {
            var req = URLRequest(url: current)
            req.httpMethod = "GET"
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue(currentReferer, forHTTPHeaderField: "Referer")
            let resp = try await webVpn.execute(req, cookieJar: jar, timeout: 20)
            if resp.isRedirect, let loc = resp.header("Location"),
               let next = URL(string: loc, relativeTo: current)?.absoluteURL {
                currentReferer = current.absoluteString
                current = next
                continue
            }
            return resp
        }
        throw NSError(domain: "CampusNetClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "校园网自服务重定向次数过多"])
    }
}
