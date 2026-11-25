@testable import BuctModel
@testable import BuctNetwork
@testable import BuctSources
import XCTest

final class SourceParsersTests: XCTestCase {

    func testMatchingMemoryCookieJarDomainRules() {
        let jar = MatchingMemoryCookieJar()
        jar.seed(
            cookieHeader: "_zte_cid_=abc; SOURCEID_TGC=TGT-999; SESSION=sess-1",
            setByHost: "sidportal.buct.edu.cn"
        )
        let sidURL = URL(string: "https://sidportal.buct.edu.cn/account")!
        let jwURL = URL(string: "https://jwglxt.buct.edu.cn/jwglxt/")!

        let sidHeader = jar.cookieHeaderFor(url: sidURL)
        XCTAssertTrue(sidHeader.contains("SOURCEID_TGC=TGT-999"))
        XCTAssertTrue(sidHeader.contains("_zte_cid_=abc"))

        let jwHeader = jar.cookieHeaderFor(url: jwURL)
        XCTAssertTrue(jwHeader.contains("_zte_cid_=abc"))
        XCTAssertFalse(jwHeader.contains("SOURCEID_TGC"))
    }

    func testJwglxtScheduleAndExamMergeAndEmptyClassroomFilter() throws {
        let kbJson = """
        {
          "kbList": [
            {
              "kcmc": "编译原理",
              "xm": "张老师",
              "xqmc": "北区",
              "cdmc": "B201",
              "xqj": "1",
              "zcd": "1-16周(双)",
              "jcs": "3-4",
              "kch_id": "CS401"
            }
          ]
        }
        """
        let courses = try JwglxtParser.parseSchedule(jsonString: kbJson)
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses[0].location, "北区 B201")
        XCTAssertEqual(courses[0].weeks, [2, 4, 6, 8, 10, 12, 14, 16])

        let chA = JwglxtParser.parseExamChannelA(
            jsonString: """
            {"items":[
              {"kcmc":"操作系统","kssj":"2026-06-18(09:00-11:00)","xnmc":"2025-2026","xq":"2"},
              {"kcmc":"旧学期考试","kssj":"2025-01-10(09:00-11:00)","xnmc":"2024-2025","xq":"1"}
            ]}
            """,
            wantXnmc: "2025-2026",
            wantXq: "2"
        )
        XCTAssertEqual(chA.count, 1)

        let chB = JwglxtParser.parseExamChannelB(
            jsonString: """
            {"items":[
              {"kcmc":"操作系统","kssj":"2026-06-18(09:00-11:00)","cdmc":"博学楼301","zwh":"12","ksmc":"期末"}
            ]}
            """
        )
        let merged = JwglxtParser.mergeExams(channelA: chA, channelB: chB)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].location, "博学楼301")
        XCTAssertEqual(merged[0].seatNumber, "12")

        let rooms = JwglxtParser.parseEmptyClassrooms(
            jsonString: """
            {"items":[
              {"cd_id":"1","cdbh":"N101","cdmc":"北一教101","xqmc":"北区","jxlmc":"第一教学楼","lch":"1","zws":"100","sfybyy":"0"},
              {"cd_id":"2","cdbh":"北102","cdmc":"北102虚拟","xqmc":"北区","jxlmc":"第一教学楼","lch":"1","zws":"50","sfybyy":"0"},
              {"cd_id":"3","cdbh":"N103","cdmc":"北一教103","xqmc":"北区","jxlmc":"第一教学楼","lch":"1","zws":"50","sfybyy":"1"}
            ]}
            """
        )
        XCTAssertEqual(rooms.map(\.code), ["N101"])
    }

    func testGmisScheduleCellMergeAndPayloadDecode() throws {
        let encryptedKey = Data("southsoft12345!#".utf8)
        let rawJson = #"[{"xm":"李同学","xh":"2025200001"}]"#
        let encryptedB64 = try BuctCrypto.aesECBEncrypt(plaintext: Data(rawJson.utf8), key: encryptedKey).base64EncodedString()
        let parsedCard = GmisParser.parseStudentCardInfo(rawPayload: encryptedB64, fallbackId: "")
        XCTAssertEqual(parsedCard?.name, "李同学")
        XCTAssertEqual(parsedCard?.studentId, "2025200001")

        let gmisKb = """
        {
          "rows": [
            {"mc":"第1节","z1":"高等数值分析 [1-16周] 王教授 [东区主教201]"},
            {"mc":"第2节","z1":"高等数值分析 [1-16周] 王教授 [东区主教201]"}
          ]
        }
        """
        let courses = GmisParser.parseSchedule(rawPayload: gmisKb)
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses[0].startPeriod, 1)
        XCTAssertEqual(courses[0].endPeriod, 2)
    }

    func testPortalCalendarParser() throws {
        let jxz = """
        {
          "result": "1",
          "data": {
            "beginDate": "2026-03-02",
            "endDate": "2026-07-05",
            "jxz": "10",
            "retStr": [
              {"wid":"w1","xn":"2025","xq":"2","ksrq":"2026-03-02","jsrq":"2026-07-05","sfdqxq":"1"}
            ]
          }
        }
        """
        let snap = try PortalCalendarParser.parseJxzResponse(jxz)
        XCTAssertEqual(snap.currentTermId, "2025-2026-2")
        XCTAssertEqual(snap.currentTeachingWeek, 10)
        XCTAssertEqual(snap.terms.count, 1)
    }

    func testJwglxtCurriculumNodeAndCourseDeduplication() {
        let html = """
        <input name="xh_id" value="2025000001"/>
        fxfyqjd_id='' id='root'><span xfyqjd_id='AAAA1111BBBB2222CCCC3333' jdkcsx='1' leaf='0' sfmjd='0' ><p class='title1' id='p1' yxxf='10' yqzdxf='20' sftg='0'>" +
        "总培养方案&nbsp;"
        fxfyqjd_id='AAAA1111BBBB2222CCCC3333' id='m1'><span xfyqjd_id='DDDD1111EEEE2222FFFF3333' jdkcsx='1' leaf='1' sfmjd='1' ><p class='title1' id='p2' yxxf='5' yqzdxf='10' sftg='0'>" +
        "模块一&nbsp;"
        fxfyqjd_id='AAAA1111BBBB2222CCCC3333' id='m1_dup'><span xfyqjd_id='DDDD1111EEEE2222FFFF3333' jdkcsx='1' leaf='1' sfmjd='1' ><p class='title1' id='p2' yxxf='5' yqzdxf='10' sftg='0'>" +
        "模块一&nbsp;"
        fxfyqjd_id='AAAA1111BBBB2222CCCC3333' id='m1_dup2'><span xfyqjd_id='DDDD1111EEEE2222FFFF3333' jdkcsx='1' leaf='1' sfmjd='1' ><p class='title1' id='p2' yxxf='5' yqzdxf='10' sftg='0'>" +
        "模块一&nbsp;"
        """
        let meta = JwglxtParser.parseOverallIndexHtml(html)
        XCTAssertEqual(meta.nodes.map(\.id), ["AAAA1111BBBB2222CCCC3333", "DDDD1111EEEE2222FFFF3333"])
        XCTAssertEqual(meta.nodeIds, ["AAAA1111BBBB2222CCCC3333", "DDDD1111EEEE2222FFFF3333"])

        let coursesJson = """
        {"items":[
          {"KCH":"CS101","KCMC":"高等数学","XF":"4.0","XDZT":"4","MAXCJ":"92"},
          {"KCH":"CS101","KCMC":"高等数学","XF":"4.0","XDZT":"4","MAXCJ":"92"},
          {"KCH":"CS102","KCMC":"线性代数","XF":"3.0","XDZT":"3"}
        ]}
        """
        let courses = JwglxtParser.parseCurriculumCoursesJson(coursesJson)
        XCTAssertEqual(courses.map(\.courseName), ["高等数学", "线性代数"])
    }
}
