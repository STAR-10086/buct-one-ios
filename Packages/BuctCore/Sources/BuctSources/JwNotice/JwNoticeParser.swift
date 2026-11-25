import BuctModel
import Foundation
import SwiftSoup

public struct JwNoticeAuthExpiredError: Error, LocalizedError, Sendable {
    public let message: String

    public init(_ message: String = "教务系统统一认证会话已过期，请重新登录") {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public enum JwNoticeParser {
    public static let parserVersion = 1
    private static let detailBaseURL = "https://jwglxt.buct.edu.cn/jwglxt/xtgl/"

    public static func isJwLoginHtml(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.hasPrefix("<") else { return false }
        let lower = trimmed.lowercased()
        return lower.contains("login-page-flowkey") ||
            lower.contains("login-croypto") ||
            lower.contains("slogin.html") ||
            lower.contains("id=\"pwd\"") ||
            lower.contains("name=\"yhm\"") ||
            trimmed.contains("用户登录") ||
            trimmed.contains("统一身份认证")
    }

    public static func parseRemindersPage(_ jsonString: String) throws -> (total: Int, items: [JwReminderItem]) {
        guard let data = jsonString.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw NSError(domain: "JwNoticeParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "教务提醒响应格式异常"])
        }
        let array = (root["items"] as? [[String: Any]]) ?? []
        var items: [JwReminderItem] = []
        var seen = Set<String>()

        for row in array {
            let rawId = firstClean(row, keys: ["id", "zjxx", "w_id"])
            let titleRaw = firstClean(row, keys: ["xxbt", "xxbtjc"])
            let title = titleRaw.isEmpty ? "教务提醒" : titleRaw
            let contentRaw = firstClean(row, keys: ["xxnr"])
            let content = contentRaw.isEmpty ? title : contentRaw
            guard !(titleRaw.isEmpty && contentRaw.isEmpty) else { continue }

            let createdAt = firstClean(row, keys: ["cjsj"])
            let id = rawId.isEmpty ? "\(createdAt)|\(title)" : rawId
            guard seen.insert(id).inserted else { continue }

            let clzt = firstClean(row, keys: ["clzt"])
            let sfyd = firstClean(row, keys: ["sfyd"])
            let isRead = (clzt == "1") || (sfyd == "1")
            let category = classifyReminder(title: title, content: content)

            items.append(
                JwReminderItem(
                    id: id,
                    title: title,
                    content: content,
                    createdAt: createdAt,
                    isRead: isRead,
                    category: category
                )
            )
        }

        let totalRaw = firstClean(root, keys: ["totalResult", "totalCount"])
        let total = max(Int(totalRaw) ?? items.count, items.count)
        return (total, items)
    }

    public static func parseAnnouncementsPage(_ jsonString: String) throws -> (total: Int, items: [JwAnnouncementItem]) {
        guard let data = jsonString.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw NSError(domain: "JwNoticeParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "教务公告响应格式异常"])
        }
        let array = (root["items"] as? [[String: Any]]) ?? []
        var items: [JwAnnouncementItem] = []
        var seen = Set<String>()

        for row in array {
            let rawId = firstClean(row, keys: ["xwbh"])
            let titleRaw = firstClean(row, keys: ["xwbtqc", "xwbt"])
            guard !(rawId.isEmpty && titleRaw.isEmpty) else { continue }

            let title = titleRaw.isEmpty ? "教务公告" : titleRaw
            let publisher = firstClean(row, keys: ["fbr"])
            let publishedAt = firstClean(row, keys: ["fbsj"])
            let id = rawId.isEmpty ? "\(publishedAt)|\(title)" : rawId
            guard seen.insert(id).inserted else { continue }

            let isPinned = firstClean(row, keys: ["sfzd"]) == "1"
            let sfyd = firstClean(row, keys: ["sfyd"])
            let isRead = sfyd != "0"
            let externalUrl = firstClean(row, keys: ["fbdz"])
            let inlineHtml = firstClean(row, keys: ["fbnr"])

            items.append(
                JwAnnouncementItem(
                    id: id,
                    title: title,
                    publisher: publisher,
                    publishedAt: publishedAt,
                    isPinned: isPinned,
                    isRead: isRead,
                    externalUrl: externalUrl,
                    inlineHtml: inlineHtml
                )
            )
        }

        let totalRaw = firstClean(root, keys: ["totalResult", "totalCount"])
        let total = max(Int(totalRaw) ?? items.count, items.count)
        return (total, items)
    }

    public static func parseAnnouncementDetail(html: String, item: JwAnnouncementItem) -> JwAnnouncementDetail {
        let doc = (try? SwiftSoup.parse(html, detailBaseURL)) ?? Document(detailBaseURL)
        let container = (try? doc.select("div.newsdisp").first()) ?? doc.body()
        let titleText = ((try? container?.select("h3.text-center").first()?.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        var publisher = item.publisher
        var publishedAt = item.publishedAt
        var viewCount = ""

        if let spans = try? container?.select("h5.news_title1 span") {
            for span in spans {
                let text = ((try? span.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if text.hasPrefix("发布人：") || text.hasPrefix("发布人:") {
                    let val = text.dropFirst(4).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !val.isEmpty { publisher = val }
                } else if text.hasPrefix("发布时间：") || text.hasPrefix("发布时间:") {
                    let val = text.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !val.isEmpty { publishedAt = val }
                } else if text.hasPrefix("浏览人数：") || text.hasPrefix("浏览人数:") {
                    viewCount = text.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        let rawBody = ((try? container?.select("div.news_con").first()?.html()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let bodySource = rawBody.isEmpty ? item.inlineHtml : rawBody
        let sanitized = sanitizeBodyHtml(bodySource)

        return JwAnnouncementDetail(
            id: item.id,
            title: titleText.isEmpty ? item.title : titleText,
            publisher: publisher,
            publishedAt: publishedAt,
            viewCount: viewCount,
            bodyHtml: sanitized.html,
            plainText: sanitized.plainText
        )
    }

    public static func sanitizeBodyHtml(_ rawHtml: String) -> (html: String, plainText: String) {
        let trimmed = rawHtml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let doc = try? SwiftSoup.parseBodyFragment(trimmed, detailBaseURL) else {
            return ("", "")
        }
        _ = try? doc.select("script, iframe, object, embed, form, style").remove()
        if let all = try? doc.select("*") {
            for el in all {
                if let attrs = el.getAttributes() {
                    for attr in attrs {
                        let key = attr.getKey().lowercased()
                        let val = attr.getValue().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        if key.hasPrefix("on") {
                            _ = try? el.removeAttr(attr.getKey())
                        } else if (key == "href" || key == "src") &&
                                    (val.hasPrefix("javascript:") || val.hasPrefix("vbscript:")) {
                            _ = try? el.removeAttr(attr.getKey())
                        }
                    }
                }
            }
        }
        if let links = try? doc.select("a[href]") {
            for a in links {
                if let abs = try? a.absUrl("href"), !abs.isEmpty {
                    _ = try? a.attr("href", abs)
                }
            }
        }
        if let imgs = try? doc.select("img[src]") {
            for img in imgs {
                if let abs = try? img.absUrl("src"), !abs.isEmpty {
                    _ = try? img.attr("src", abs)
                }
            }
        }
        let bodyHtml = (try? doc.body()?.html()) ?? trimmed
        let plainText = ((try? doc.body()?.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (bodyHtml, plainText)
    }

    private static func classifyReminder(title: String, content: String) -> JwReminderCategory {
        let merged = "\(title)\n\(content)"
        if merged.contains("调课") { return .reschedule }
        if merged.contains("补课") { return .makeup }
        if merged.contains("停课") { return .cancel }
        if merged.contains("考试") || merged.contains("缓考") || merged.contains("补考") { return .exam }
        return .other
    }

    private static func firstClean(_ dict: [String: Any], keys: [String]) -> String {
        for key in keys {
            guard let raw = dict[key], !(raw is NSNull) else { continue }
            let str = "\(raw)".trimmingCharacters(in: .whitespacesAndNewlines)
            if !str.isEmpty && str.caseInsensitiveCompare("null") != .orderedSame {
                return str
            }
        }
        return ""
    }
}
