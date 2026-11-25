@testable import BuctModel
@testable import BuctNetwork
@testable import BuctSources
import XCTest

final class M2ParsersTests: XCTestCase {

    func testJwNoticeRemindersAndAnnouncementsParsing() throws {
        let remindersJson = """
        {
          "totalResult": "2",
          "items": [
            {"id": "r1", "xxbt": "调课通知", "xxnr": "操作系统调至周五", "cjsj": "2026-05-25 10:00", "clzt": "0"},
            {"id": "r2", "xxbt": "考试提醒", "xxnr": "编译原理期末考试", "cjsj": "2026-05-24 09:00", "sfyd": "1"}
          ]
        }
        """
        let rem = try JwNoticeParser.parseRemindersPage(remindersJson)
        XCTAssertEqual(rem.total, 2)
        XCTAssertEqual(rem.items.count, 2)
        XCTAssertEqual(rem.items[0].category, .reschedule)
        XCTAssertFalse(rem.items[0].isRead)
        XCTAssertEqual(rem.items[1].category, .exam)
        XCTAssertTrue(rem.items[1].isRead)

        let annJson = """
        {
          "totalCount": 1,
          "items": [
            {"xwbh": "xw1", "xwbtqc": "考风考纪通知", "fbr": "教务处", "fbsj": "2026-05-22", "sfzd": "1", "sfyd": "0"}
          ]
        }
        """
        let ann = try JwNoticeParser.parseAnnouncementsPage(annJson)
        XCTAssertEqual(ann.items.count, 1)
        XCTAssertTrue(ann.items[0].isPinned)
        XCTAssertFalse(ann.items[0].isRead)

        let detailHtml = """
        <div class="newsdisp">
          <h3 class="text-center">考风考纪通知</h3>
          <h5 class="news_title1"><span>发布人：教务处</span><span>发布时间：2026-05-22</span><span>浏览人数：99</span></h5>
          <div class="news_con"><p>严格遵守纪律</p><script>alert(1)</script><a href="att.pdf">附件</a></div>
        </div>
        """
        let detail = JwNoticeParser.parseAnnouncementDetail(html: detailHtml, item: ann.items[0])
        XCTAssertEqual(detail.viewCount, "99")
        XCTAssertFalse(detail.bodyHtml.contains("alert(1)"))
        XCTAssertTrue(detail.plainText.contains("严格遵守纪律"))
    }

    func testPortalNewsAndLibraryParsing() throws {
        let newsJson = """
        callback({
          "result": "1",
          "data": {
            "count": 1,
            "articles": [
              {
                "id": "art1",
                "title": "科技文化节开幕",
                "from": "校团委",
                "publishTimestamp": 1779696000000,
                "summary": "欢迎参加",
                "content": "本周五晚举行",
                "linkUrl": "https://i.buct.edu.cn/jump?linkUrl=https%3A%2F%2Fnews.buct.edu.cn%2F1.html&foo=1",
                "isTop": "1"
              }
            ]
          }
        })
        """
        let page = try PortalCalendarParser.parseNewsArticlesPage(newsJson, columnId: PortalNewsColumn.activity.rawValue)
        XCTAssertEqual(page.articles.count, 1)
        XCTAssertEqual(page.articles[0].publicUrl, "https://news.buct.edu.cn/1.html")
        XCTAssertTrue(page.articles[0].isTop)

        let libJson = """
        {
          "result": "1",
          "data": {
            "count": 1,
            "list": [
              {"tsmc": "编译原理", "tstxm": "B001", "jsrq": "2026-05-01", "hsrq": "2026-06-15"}
            ]
          }
        }
        """
        let lib = try PortalCalendarParser.parseBorrowedBooks(libJson)
        XCTAssertEqual(lib.books.count, 1)
        XCTAssertEqual(lib.books[0].title, "编译原理")
    }

    func testTheolParsersAndGbkDecodingAndMeolCookieScope() throws {
        let reminderHtml = """
        <a onclick="window.open('x?lid=1001&t=hw')">操作系统</a>
        <a onclick="window.open('x?lid=24199&t=test')">过滤课程</a>
        <a onclick="window.open('x?lid=1002&t=test')">编译原理</a>
        """
        let pending = TheolParser.parsePendingCourses(reminderHtml)
        XCTAssertEqual(pending.homeworks.map(\.lid), ["1001"])
        XCTAssertEqual(pending.tests.map(\.lid), ["1002"])

        let hwHtml = """
        <table class="valuelist">
          <tr>
            <td><a href="/meol/common/hw/student/hwtask.view.jsp?hwtid=501">实验报告</a></td>
            <td>2099-06-01 23:59</td>
            <td>暂无分数</td>
            <td>王老师</td>
            <td><a class="enter" href="/meol/common/hw/student/hwtask.enter.jsp?hwtid=501">提交</a></td>
          </tr>
        </table>
        """
        let base = URL(string: "https://course.buct.edu.cn/meol/common/hw/student/hwtask.jsp")!
        let hwParsed = TheolParser.parseHomeworkPage(hwHtml, lid: "1001", courseName: "操作系统", baseURL: base)
        XCTAssertEqual(hwParsed.items.count, 1)
        XCTAssertTrue(hwParsed.items[0].canSubmit)
        XCTAssertEqual(hwParsed.items[0].status, "未提交")

        let resHtml = """
        <table class="valuelist">
          <tr>
            <td><a href="/meol/common/script/preview/download_preview.jsp?fileid=88&resid=99">课件1.pdf</a></td>
            <td>2.5 MB</td>
            <td>2026-03-01</td>
          </tr>
        </table>
        """
        let resBase = URL(string: "https://course.buct.edu.cn/meol/common/script/listview.jsp?lid=1001")!
        let resItems = TheolParser.parseResourceList(resHtml, lid: "1001", baseURL: resBase)
        XCTAssertEqual(resItems.count, 1)
        XCTAssertTrue(resItems[0].url.contains("/download.jsp"))
        XCTAssertTrue(resItems[0].previewUrl.contains("/download_preview.jsp"))

        let jar = MatchingMemoryCookieJar()
        jar.seed(cookieHeader: "JSESSIONID=abc123; _zte_cid_=z1", setByHost: "course.buct.edu.cn", path: "/meol")
        let meolURL = URL(string: "https://course.buct.edu.cn/meol/welcomepage/student/index.jsp")!
        let rootURL = URL(string: "https://course.buct.edu.cn/other")!
        XCTAssertTrue(jar.cookieHeaderFor(url: meolURL).contains("JSESSIONID=abc123"))
        XCTAssertFalse(jar.cookieHeaderFor(url: rootURL).contains("JSESSIONID=abc123"))
        XCTAssertTrue(jar.cookieHeaderFor(url: rootURL).contains("_zte_cid_=z1"))

        let gbkEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let gbkData = "北化在线课程资源".data(using: gbkEncoding)!
        let resp = HttpResponseData(url: meolURL, statusCode: 200, headers: ["Content-Type": "text/html; charset=gb2312"], setCookieHeaders: [], body: gbkData)
        XCTAssertEqual(resp.decodedText(preferGBKFallback: true), "北化在线课程资源")
    }

    func testMailParsersAndSessionExpiryDetection() throws {
        let foldersJson = """
        {"code":"S_OK","var":[{"id":1,"name":"收件箱","stats":{"messageCount":12,"unreadMessageCount":3},"flags":{"system":true}}]}
        """
        let folders = try MailParser.parseFolders(jsonString: foldersJson)
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders[0].unreadCount, 3)

        let msgsJson = """
        {"code":"S_OK","total":1,"var":[{"id":"m1","fid":1,"subject":"","from":"\\"教务处\\" <jwc@buct.edu.cn>","summary":"选课通知","flags":{"read":false,"attached":true},"attachments":[{"id":"2","filename":"guide.pdf","contentLength":1024,"inlined":false}]}]}
        """
        let list = try MailParser.parseMessages(jsonString: msgsJson, defaultFolderId: 1)
        XCTAssertEqual(list.total, 1)
        XCTAssertEqual(list.messages[0].subject, "(无主题)")
        XCTAssertEqual(list.messages[0].fromName, "教务处")
        XCTAssertEqual(list.messages[0].fromAddress, "jwc@buct.edu.cn")
        XCTAssertTrue(list.messages[0].hasAttachments)

        XCTAssertTrue(MailParser.isRpcSessionExpired(code: "FA_NEED_LOGIN"))
        XCTAssertFalse(MailParser.isRpcSessionExpired(code: "S_OK"))
    }

    func testElectricityParserAndDualMeterBaseName() throws {
        let target = ElectricityRoomTarget(schoolId: "1", campusName: "东校区", buildingName: "1号楼", floorName: "3层", roomId: "r1", roomName: "301照明", meterType: "照明")
        let readingJson = """
        {"balanceText":"45.20 元","accountStatus":"1","queriedAt":1732500000,"fromCache":true}
        """
        let reading = try ElectricityParser.parseReading(jsonString: readingJson, target: target)
        XCTAssertEqual(reading.balanceValue ?? 0, 45.20, accuracy: 0.001)
        XCTAssertEqual(reading.unit, "元")
        XCTAssertTrue(reading.fromCache)

        let err = ElectricityParser.parseGatewayError(statusCode: 429, jsonString: #"{"error":"请求频繁","retryAfterSeconds":180}"#, retryAfterHeader: nil)
        XCTAssertEqual(err.retryAfterSeconds, 180)
        XCTAssertTrue(err.message.contains("3 分钟"))
        XCTAssertEqual(ElectricityRoomCatalog.baseRoomName("301照明"), "301")
        XCTAssertEqual(ElectricityRoomCatalog.baseRoomName("301空调"), "301")
    }

    func testCampusNetParsersAndDecimalTrafficFormatting() throws {
        let jsonp = #"jQuery1124_123({"error":"ok","user_name":"20240001","online_ip":"10.1.2.3","products_name":"学生20元","billing_name":"20元包40G","sum_bytes":2500000000,"sum_seconds":7200,"user_balance":18.5,"wallet_balance":50.0,"user_charge":20.0,"online_device_total":"2"})"#
        let rad = try XCTUnwrap(CampusNetParser.parseRadUserInfo(jsonp: jsonp))
        XCTAssertTrue(rad.isOnline)
        XCTAssertEqual(rad.onlineDeviceTotal, 2)
        XCTAssertEqual(CampusNetSnapshot.formatTraffic(bytes: rad.sumBytes), "2.50 GB")

        let homeHtml = """
        <html><body>
          <ul>
            <li class="list-group-item"><label>状态</label>正常</li>
            <li class="list-group-item"><label>电子钱包</label>66.50 元<a href="#">充值</a></li>
          </ul>
          <div id="w1-container"><table><tbody><tr>
            <td data-col-seq="1">10.1.2.3</td><td data-col-seq="3">2026-05-19 08:00</td><td data-col-seq="11">20元包40G</td>
          </tr></tbody></table></div>
          <div id="w3-container"><table><tbody><tr>
            <td data-col-seq="1">学生20元套餐</td><td data-col-seq="2">20元包40G</td><td data-col-seq="3">12.34 GB</td>
            <td data-col-seq="4">20小时</td><td data-col-seq="6">20.00</td><td data-col-seq="7">19.50</td>
          </tr></tbody></table></div>
        </body></html>
        """
        let home = try XCTUnwrap(CampusNetParser.parseSelfServiceHome(html: homeHtml))
        XCTAssertEqual(home.accountStatus, "正常")
        XCTAssertEqual(home.walletBalance ?? 0, 66.50, accuracy: 0.001)
        XCTAssertEqual(home.onlineDevices.count, 1)
        XCTAssertEqual(home.productBalance ?? 0, 19.50, accuracy: 0.001)
    }
}
