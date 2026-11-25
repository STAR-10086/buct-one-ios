@testable import BuctNetwork
import XCTest

final class BuctTlsTests: XCTestCase {
    func testBundledCertificatesAllDecode() {
        let certs = BuctCertificates.loadBundledCertificates()
        XCTAssertEqual(certs.count, 4, "应成功加载 4 张内置校方双链 TLS 证书")
    }
}
