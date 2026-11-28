import BuctModel
import BuctSources
import XCTest

final class M3ParsersTests: XCTestCase {
    func testEcardParserAndCategoryClassification() throws {
        let html = #"window.sessionStorage.setItem('rasPublicKey', 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A\/TEST\/KEY==');"#
        XCTAssertEqual(EcardParser.extractRsaPublicKey(fromIndexHtml: html), "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A/TEST/KEY==")
        XCTAssertEqual(
            EcardClient.extractWebportalCookie(from: ["webportal=abc123; Path=/; HttpOnly", "other=1"]),
            "abc123"
        )

        let emptyJson = #"{"success":false,"message":"WEB20006"}"#
        let empty = try EcardParser.parseTransactions(jsonString: emptyJson)
        XCTAssertEqual(empty.total, 0)
        XCTAssertTrue(empty.rows.isEmpty)

        XCTAssertNoThrow(try EcardParser.validateLoginResponse(#"{"success":true,"message":"CODE10004"}"#))

        let txJson = """
        {"success":true,"resultData":{"total":2,"rows":[
          {"journo":"J1","txcode":"2100","mername":"东区二食堂","txamt":-1550,"balance":8450,"txdate":"2026-05-19 12:00:00"},
          {"journo":"J2","txcode":"2241","summary":"助学金","txamt":10000,"balance":10000,"txdate":1779163200000}
        ]}}
        """
        let parsed = try EcardParser.parseTransactions(jsonString: txJson)
        XCTAssertEqual(parsed.rows.count, 2)
        XCTAssertEqual(parsed.rows[0].category, .dining)
        XCTAssertTrue(parsed.rows[0].isExpense)
        XCTAssertEqual(parsed.rows[1].summary, "发放补助")
        XCTAssertFalse(parsed.rows[1].isExpense)
        XCTAssertEqual(CardMoneyFormatter.formatFenToYuan(12850), "128.50")
    }

    func testScsParserSortsFullYearFirst() throws {
        let dims = ScsParser.parseDimensions(#"{"code":200,"data":[]}"#)
        XCTAssertEqual(dims.count, 5)

        let json = """
        {"code":200,"data":[
          {"year":2025,"mc":"2025-2026","terms":[
            {"id":1,"mc":"第一学期","totalScore":120,"studentScore":{"moral":40,"academic":30,"physical":20,"aesthetics":15,"labor":15},"details":[{"typeId":1,"desc":"德育","studentTypeScore":40,"typeTotalScore":180,"basic":[{"id":1,"shortDesc":"主题团日","score":40}]}]},
            {"id":0,"mc":"全年","totalScore":420,"studentScore":{"moral":140,"academic":100,"physical":60,"aesthetics":60,"labor":60}}
          ]}
        ]}
        """
        let terms = try ScsParser.parseAllTermScores(json, dimensions: dims)
        XCTAssertEqual(terms.count, 2)
        XCTAssertTrue(terms[0].isFullYear)
        XCTAssertEqual(terms[0].displayTitle, "2025-2026 全年")
        XCTAssertFalse(terms[1].isFullYear)
        XCTAssertEqual(terms[1].displayTitle, "2025-2026 第一学期")
        XCTAssertEqual(terms[1].details.first?.score, 40)
        XCTAssertEqual(terms[1].details.first?.items.first?.title, "主题团日")
    }

    func testSjcxParserTokenAndReportDedup() {
        let loc = "https://sjcx.buct.edu.cn/#/product/cas?token=eyJhbGciOiJIUzI1NiJ9.abc"
        XCTAssertEqual(SjcxParser.extractTokenFromLocation(loc), "eyJhbGciOiJIUzI1NiJ9.abc")

        let reportJson = """
        {"code":200,"data":{"list":[{"course_name":"组成原理实验","course_exp":[
          {"report_id":"10","exp_name":"ALU设计","state":0,"doc_name":""},
          {"report_id":"10","exp_name":"ALU设计","state":2,"doc_name":"alu.pdf","score":"95"}
        ]}]}}
        """
        let reports = SjcxParser.parseReports(reportJson)
        XCTAssertEqual(reports.count, 1)
        XCTAssertTrue(reports[0].isSubmitted)
        XCTAssertEqual(reports[0].scoreText, "95")
    }

    func testTyglParserAndNationalFitnessScorer() {
        let html = """
        <div id="mainContent">
          <table class="table_bg">
            <tr><th>姓名</th><td>测试同学</td><th>测试年度</th><td>2025-2026</td></tr>
            <tr><th>成绩</th><td>85.0</td><th>等级</th><td>良好</td></tr>
            <tr><td>肺活量</td><td>4800</td><td>90</td><td>良好</td><td>加分</td><td>2.0</td><td>1000米</td><td>加分</td></tr>
          </table>
        </div>
        """
        XCTAssertTrue(TyglParser.isAuthenticatedPage(html))
        let parsed = TyglParser.parseFitnessPage(html: html)
        XCTAssertEqual(parsed.profile?.name, "测试同学")
        XCTAssertEqual(parsed.record?.items.count, 1)
        XCTAssertEqual(parsed.record?.bonusScore, "2.0")

        XCTAssertEqual(NationalFitnessScorer.parseEnduranceSeconds("3'40\""), 220)
        let sim = NationalFitnessScorer.evaluate(
            FitnessSimInput(gender: .male, gradeGroup: .lower, heightCm: 175, weightKg: 65, lungCapacityMl: 5040, run50mSec: 6.7, sitAndReachCm: 24.9, standingJumpCm: 273, strengthCount: 21, enduranceSec: 193)
        )
        XCTAssertGreaterThanOrEqual(sim.standardTotal, 99.9)
        XCTAssertGreaterThan(sim.bonusScore, 0)
        XCTAssertEqual(sim.level, "优秀")
    }

    func testCourseSelectionParsers() {
        let indexHtml = """
        <input type="hidden" name="xkxnm" value="2025" />
        <input type="hidden" name="xkxqm" value="12" />
        <a onclick="queryCourse(this,'10','XKKZ_10','2024','0809')">通识</a>
        <a onclick="queryCourse(this,'05','XKKZ_05','2024','0809')">体育</a>
        """
        let inputs = CourseSelectionParser.parseHiddenInputs(html: indexHtml)
        XCTAssertEqual(inputs["xkxnm"], "2025")
        let tabs = CourseSelectionParser.parseTabParams(html: indexHtml, hiddenInputs: inputs)
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(tabs[0].kklxdm, "10")
        XCTAssertEqual(tabs[1].xkkzId, "XKKZ_05")

        let listJson = """
        {"tmpList":[{"kch_id":"CS101","kcmc":"人工智能导论","jxb_id":"JXB1","do_jxb_id":"DO_ENC_1","jsxx":"1001/王教授/教授","sksj":"周二第6-7节<br/>1-16周","jxdd":"教阶201","xf":"2.0","jxbrl":100,"yxzrs":80,"sfxkbj":"0"}]}
        """
        let courses = CourseSelectionParser.parseCourseList(jsonString: listJson, tab: tabs[0], baseParams: inputs)
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses[0].teacher, "王教授")
        XCTAssertEqual(courses[0].remainingSeats, 20)
        XCTAssertTrue(courses[0].timeText.contains("；"))

        let selRes = CourseSelectionParser.parseSelectResult(jsonString: #"{"flag":"1","msg":"成功"}"#)
        XCTAssertTrue(selRes.success)
        let dropRes = CourseSelectionParser.parseDropResult(rawText: "1")
        XCTAssertTrue(dropRes.success)
    }
}
