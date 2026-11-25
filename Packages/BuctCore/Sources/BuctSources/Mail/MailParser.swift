import BuctModel
import Foundation
import SwiftSoup

public struct MailSessionExpiredError: Error, LocalizedError, Sendable {
    public let message: String

    public init(_ message: String = "校园邮箱会话已过期，请重新认证") {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public enum MailParser {
    public static let parserVersion = 2

    public static func extractJsOrMetaRedirectURL(html: String, baseURL: URL) -> URL? {
        let pattern = #"(?:location(?:\.href)?\s*=\s*|url\s*=\s*)['"]?(https?://[^'"\s>]+)['"]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let raw = String(html[range])
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: raw, relativeTo: baseURL)?.absoluteURL
    }

    public static func isRpcSessionExpired(code: String) -> Bool {
        let upper = code.uppercased()
        let signals = ["INVALID_SESSION", "UNAUTHORIZED", "EXPIRED", "FORBIDDEN", "FA_NEED_LOGIN", "401", "403"]
        return signals.contains { upper.contains($0) }
    }

    public static func parseAccountInfo(jsonString: String) -> MailAccountInfo? {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let payload = (root["data"] as? [String: Any]) ?? root
        let defaultSender = payload["defaultSender"] as? [String: Any]
        let email = firstNonEmpty(payload, keys: ["displayEmail", "email", "accountName"])
            ?? firstNonEmpty(defaultSender ?? [:], keys: ["email"])
            ?? ""
        let name = firstNonEmpty(payload, keys: ["nickName", "senderName", "accountName"])
            ?? firstNonEmpty(defaultSender ?? [:], keys: ["nickName"])
            ?? ""
        let org = firstNonEmpty(payload, keys: ["orgName"]) ?? ""
        guard !email.isEmpty || !name.isEmpty else { return nil }
        return MailAccountInfo(email: email, displayName: name.isEmpty ? email : name, orgName: org)
    }

    public static func parseFolders(jsonString: String) throws -> [MailFolder] {
        let root = try parseRpcObject(jsonString)
        guard let arr = root["var"] as? [[String: Any]] else { return [] }
        return arr.compactMap { obj in
            guard let id = intValue(obj["id"]) else { return nil }
            let name = strValue(obj["name"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let stats = obj["stats"] as? [String: Any]
            let flags = obj["flags"] as? [String: Any]
            return MailFolder(
                id: id,
                name: name,
                totalCount: intValue(stats?["messageCount"]) ?? 0,
                unreadCount: intValue(stats?["unreadMessageCount"]) ?? 0,
                isSystem: boolValue(flags?["system"])
            )
        }
    }

    public static func parseMessages(jsonString: String, defaultFolderId: Int) throws -> (total: Int, messages: [MailMessageSummary]) {
        let root = try parseRpcObject(jsonString)
        let total = intValue(root["total"]) ?? 0
        guard let arr = root["var"] as? [[String: Any]] else { return (total, []) }

        let items: [MailMessageSummary] = arr.compactMap { obj in
            let id = strValue(obj["id"])
            guard !id.isEmpty else { return nil }
            let fid = intValue(obj["fid"]) ?? defaultFolderId
            let tid = strValue(obj["tid"])
            let rawSubject = strValue(obj["subject"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = rawSubject.isEmpty ? "(无主题)" : rawSubject

            let rawFrom = extractAddressList(obj["from"]).first ?? ""
            let (fromName, fromAddr) = splitSender(rawFrom)
            let toList = extractAddressList(obj["to"])
            let summary = strValue(obj["summary"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let sentAt = formatMailDate(obj["sentDate"])
            let receivedAt = formatMailDate(obj["receivedDate"])
            let size = int64Value(obj["size"]) ?? 0

            let flags = obj["flags"] as? [String: Any]
            let isRead = boolValue(flags?["read"])
            let isFlagged = (intValue(obj["label0"]) ?? 0) == 1
            let attachments = parseAttachments(obj["attachments"])
            let hasAtt = boolValue(flags?["attached"]) || boolValue(flags?["realAttached"]) || attachments.contains { !$0.isInlined }

            return MailMessageSummary(
                id: id,
                folderId: fid,
                threadId: tid,
                subject: subject,
                fromName: fromName,
                fromAddress: fromAddr,
                to: toList,
                summary: summary,
                sentAt: sentAt,
                receivedAt: receivedAt.isEmpty ? sentAt : receivedAt,
                sizeBytes: size,
                isRead: isRead,
                isFlagged: isFlagged,
                hasAttachments: hasAtt,
                attachments: attachments
            )
        }
        return (max(total, items.count), items)
    }

    public static func parseMessageDetail(jsonString: String, fallbackId: String, fallbackFolderId: Int) throws -> MailMessageDetail {
        let root = try parseRpcObject(jsonString)
        guard let v = root["var"] as? [String: Any] else {
            throw NSError(domain: "MailParser", code: -2, userInfo: [NSLocalizedDescriptionKey: "邮件正文为空"])
        }
        let fid = intValue(v["fid"]) ?? fallbackFolderId
        let rawSubject = strValue(v["subject"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = rawSubject.isEmpty ? "(无主题)" : rawSubject
        let (fromName, fromAddr) = splitSender(extractAddressList(v["from"]).first ?? "")
        let toList = extractAddressList(v["to"])
        let sentAt = formatMailDate(v["sentDate"])
        let htmlBody = strValue((v["html"] as? [String: Any])?["content"])
        var plainText = strValue((v["text"] as? [String: Any])?["content"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if plainText.isEmpty && !htmlBody.isEmpty {
            plainText = extractPlainText(fromHtml: htmlBody)
        }
        let attachments = parseAttachments(v["attachments"])

        return MailMessageDetail(
            id: fallbackId,
            folderId: fid,
            subject: subject,
            fromName: fromName,
            fromAddress: fromAddr,
            to: toList,
            sentAt: sentAt,
            htmlBody: htmlBody,
            plainText: plainText,
            attachments: attachments
        )
    }

    public static func validateRpcSuccess(jsonString: String) throws {
        _ = try parseRpcObject(jsonString)
    }

    public static func splitSender(_ raw: String) -> (name: String, address: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("未知发件人", "") }
        if let lt = trimmed.firstIndex(of: "<"), let gt = trimmed.lastIndex(of: ">"), lt < gt {
            let addr = String(trimmed[trimmed.index(after: lt)..<gt]).trimmingCharacters(in: .whitespacesAndNewlines)
            var name = String(trimmed[..<lt]).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            if name.isEmpty { name = addr }
            return (name, addr)
        }
        return (trimmed, trimmed)
    }

    // MARK: - Internal

    private static func parseRpcObject(_ jsonString: String) throws -> [String: Any] {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MailSessionExpiredError("校园邮箱返回非 JSON 内容，会话可能已失效")
        }
        let code = strValue(root["code"])
        if isRpcSessionExpired(code: code) {
            throw MailSessionExpiredError("校园邮箱会话已过期（\(code)）")
        }
        if !code.isEmpty && code != "S_OK" {
            let msg = strValue(root["summary"]).isEmpty ? code : strValue(root["summary"])
            throw NSError(domain: "MailParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "邮箱接口错误：\(msg)"])
        }
        return root
    }

    private static func parseAttachments(_ raw: Any?) -> [MailAttachment] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { obj in
            let partId = strValue(obj["id"])
            guard !partId.isEmpty else { return nil }
            let name = strValue(obj["filename"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let ct = strValue(obj["contentType"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let size = int64Value(obj["contentLength"]) ?? int64Value(obj["estimateSize"]) ?? 0
            let inlined = boolValue(obj["inlined"])
            let cid = strValue(obj["contentId"])
            return MailAttachment(
                partId: partId,
                filename: name.isEmpty ? "附件_\(partId)" : name,
                contentType: ct.isEmpty ? "application/octet-stream" : ct,
                sizeBytes: size,
                isInlined: inlined,
                contentId: cid
            )
        }
    }

    private static func extractAddressList(_ raw: Any?) -> [String] {
        if let s = raw as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? [] : [t]
        }
        if let arr = raw as? [Any] {
            return arr.compactMap { item -> String? in
                let s = strValue(item).trimmingCharacters(in: .whitespacesAndNewlines)
                return s.isEmpty ? nil : s
            }
        }
        return []
    }

    private static func formatMailDate(_ raw: Any?) -> String {
        if let s = raw as? String {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let num = raw as? NSNumber {
            let val = num.doubleValue
            let sec = val > 10_000_000_000 ? val / 1000.0 : val
            let date = Date(timeIntervalSince1970: sec)
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "zh_CN")
            fmt.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
            fmt.dateFormat = "yyyy-MM-dd HH:mm"
            return fmt.string(from: date)
        }
        return ""
    }

    private static func extractPlainText(fromHtml html: String) -> String {
        guard let doc = try? SwiftSoup.parse(html) else { return "" }
        _ = try? doc.select("script, style").remove()
        return (try? doc.body()?.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func firstNonEmpty(_ dict: [String: Any], keys: [String]) -> String? {
        for k in keys {
            let v = strValue(dict[k]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { return v }
        }
        return nil
    }

    private static func strValue(_ raw: Any?) -> String {
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return n.stringValue }
        return ""
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let i = raw as? Int { return i }
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func int64Value(_ raw: Any?) -> Int64? {
        if let i = raw as? Int64 { return i }
        if let i = raw as? Int { return Int64(i) }
        if let n = raw as? NSNumber { return n.int64Value }
        if let s = raw as? String { return Int64(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func boolValue(_ raw: Any?) -> Bool {
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber { return n.intValue != 0 }
        if let s = raw as? String { return s.lowercased() == "true" || s == "1" }
        return false
    }
}
