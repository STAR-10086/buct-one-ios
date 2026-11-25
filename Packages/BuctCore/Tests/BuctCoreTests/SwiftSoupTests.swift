@testable import BuctSources
import XCTest

final class SwiftSoupTests: XCTestCase {
    func testExtractSidPortalLoginParams() throws {
        let html = """
        <html>
          <body>
            <p id="login-page-flowkey">e1s1_flow_token</p>
            <p id="login-croypto">MDEyMzQ1Njc4OWFiY2RlZg==</p>
          </body>
        </html>
        """
        XCTAssertEqual(try HtmlSnippetExtractor.textById(html, id: "login-page-flowkey"), "e1s1_flow_token")
        XCTAssertEqual(try HtmlSnippetExtractor.textById(html, id: "login-croypto"), "MDEyMzQ1Njc4OWFiY2RlZg==")
        XCTAssertNil(try HtmlSnippetExtractor.textById(html, id: "non-existent"))
    }
}
