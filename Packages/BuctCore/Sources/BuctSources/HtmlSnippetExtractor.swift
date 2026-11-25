import Foundation
import SwiftSoup

public enum HtmlSnippetExtractor {
    public static func textById(_ html: String, id: String) throws -> String? {
        let doc = try SwiftSoup.parse(html)
        guard let element = try doc.getElementById(id) else {
            return nil
        }
        let text = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
