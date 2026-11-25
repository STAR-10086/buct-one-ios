import BuctModel
import BuctNetwork
import Foundation

public struct JwglxtClient: Sendable {
    private static let baseURL = "https://jwglxt.buct.edu.cn"
    private static let userAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36"
    private static let defaultReferer =
        "https://jwglxt.buct.edu.cn/jwglxt/xsxk/zzxkyzb_cxZzxkYzbIndex.html?gnmkdm=N253512&layout=default&su=jwglxt.buct.edu.cn"

    private let transport: BuctHttpTransport

    public init(transport: BuctHttpTransport = .shared) {
        self.transport = transport
    }

    public func validateAndFetchProfile(cookie: String, fallbackId: String = "") async throws -> (name: String, studentId: String) {
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        let url = URL(string: "\(Self.baseURL)/jwglxt/xtgl/index_cxYhxxIndex.html?xt=jw&localeKey=zh_CN&_=\(ts)&gnmkdm=index")!
        let resp = try await get(url: url, cookie: cookie)
        if let profile = JwglxtParser.parseStudentProfile(html: resp.bodyString, fallbackId: fallbackId) {
            return profile
        }
        let initURL = URL(string: "\(Self.baseURL)/jwglxt/xtgl/index_initMenu.html")!
        let initResp = try await get(url: initURL, cookie: cookie)
        if let profile = JwglxtParser.parseStudentProfile(html: initResp.bodyString, fallbackId: fallbackId) {
            return profile
        }
        throw JwglxtSessionExpiredError(message: "无法验证教务会话，请重新登录")
    }

    public func fetchSchedule(term: AcademicTerm, cookie: String) async throws -> [ScheduleCourse] {
        let url = URL(string: "\(Self.baseURL)/jwglxt/kbcx/xskbcx_cxXsKb.html?gnmkdm=N253508&su=jwglxt.buct.edu.cn")!
        let resp = try await postForm(url: url, cookie: cookie, params: [
            ("xnm", term.xnm),
            ("xqm", term.xqm)
        ])
        return try JwglxtParser.parseSchedule(jsonString: resp.bodyString)
    }

    public func fetchSemesterGrades(term: AcademicTerm, cookie: String, fetchDetails: Bool = true) async throws -> [GradeItem] {
        let url = URL(string: "\(Self.baseURL)/jwglxt/cjcx/cjcx_cxDgXscj.html?doType=query&gnmkdm=N305005")!
        let resp = try await postForm(url: url, cookie: cookie, params: [
            ("xnm", term.xnm),
            ("xqm", term.xqm),
            ("queryModel.showCount", "1500"),
            ("queryModel.currentPage", "1"),
            ("queryModel.sortName", ""),
            ("queryModel.sortOrder", "asc"),
            ("time", "0")
        ])
        var items = JwglxtParser.parseGradesJson(resp.bodyString)
        guard fetchDetails else { return items }

        let skipScores: Set<String> = ["", "--", "null", "合格", "不合格", "通过", "不通过", "缺考", "缓考", "免修", "P", "U"]
        let detailURL = URL(string: "\(Self.baseURL)/jwglxt/cjcx/cjcx_cxXsXmcjList.html?gnmkdm=N305007")!
        for idx in items.indices {
            guard items[idx].detail.isEmpty,
                  !items[idx].jxbId.isEmpty,
                  !skipScores.contains(items[idx].score),
                  !items[idx].examNature.contains("补考") else {
                continue
            }
            let ts = Int64(Date().timeIntervalSince1970 * 1000)
            if let detResp = try? await postForm(url: detailURL, cookie: cookie, params: [
                ("xnm", items[idx].year.isEmpty ? term.xnm : items[idx].year),
                ("xqm", items[idx].term.isEmpty ? term.xqm : items[idx].term),
                ("jxb_id", items[idx].jxbId),
                ("_search", "false"),
                ("nd", "\(ts)"),
                ("queryModel.showCount", "1500"),
                ("queryModel.currentPage", "1"),
                ("queryModel.sortName", ""),
                ("queryModel.sortOrder", "asc"),
                ("time", "0")
            ]) {
                let det = JwglxtParser.parseGradeComponentDetail(jsonString: detResp.bodyString)
                if !det.isEmpty {
                    items[idx].detail = det
                }
            }
        }
        return items
    }

    public func fetchOverallAndCurriculum(cookie: String) async throws -> OverallAcademicBundle {
        let indexURL = URL(string: "\(Self.baseURL)/jwglxt/xsxy/xsxyqk_cxXsxyqkIndex.html?gnmkdm=N105515&layout=default")!
        let indexResp = try await get(url: indexURL, cookie: cookie)
        let meta = JwglxtParser.parseOverallIndexHtml(indexResp.bodyString)

        let nodeURL = URL(string: "\(Self.baseURL)/jwglxt/xsxy/xsxyqk_cxJxzxjhxfyqKcxx.html?gnmkdm=N105515")!
        var allGrades: [GradeItem] = []
        var coursesByNodeId: [String: [CurriculumCourse]] = [:]

        for nodeId in meta.nodeIds {
            guard let resp = try? await postForm(url: nodeURL, cookie: cookie, params: [
                ("xfyqjd_id", nodeId),
                ("xh_id", meta.xhId),
                ("cjlrxn", meta.cjlrxn),
                ("cjlrxq", meta.cjlrxq),
                ("xscjcxkz", "0"),
                ("cjcxkzzt", "2"),
                ("cjztkz", "0"),
                ("cjzt", "")
            ]) else {
                continue
            }
            let body = resp.bodyString
            let parsedGrades = JwglxtParser.parseGradesJson(body)
            allGrades.append(contentsOf: parsedGrades)
            coursesByNodeId[nodeId] = JwglxtParser.parseCurriculumCoursesJson(body)
        }

        let updatedNodes = meta.nodes.map { node -> CurriculumNode in
            var copy = node
            copy.courses = coursesByNodeId[node.id] ?? []
            return copy
        }

        return OverallAcademicBundle(
            grades: BuctGpaScale.deduplicateBestAttempts(allGrades),
            summary: meta.summary,
            curriculumNodes: updatedNodes
        )
    }

    public func fetchExams(term: AcademicTerm, cookie: String) async throws -> [ExamItem] {
        let urlA = URL(string: "\(Self.baseURL)/jwglxt/design/funcData_cxFuncDataList.html?func_widget_guid=58944B9C2CD784DBE053839D04CA5AD7&gnmkdm=N358163")!
        let urlB = URL(string: "\(Self.baseURL)/jwglxt/kwgl/kscx_cxXsksxxIndex.html?doType=query&gnmkdm=N358105")!

        async let taskA = postForm(url: urlA, cookie: cookie, params: [
            ("xnmc", term.xnmcString),
            ("xq", term.xqString),
            ("kch", ""),
            ("kcmc", ""),
            ("jxbmc", ""),
            ("kssj", ""),
            ("queryModel.showCount", "100"),
            ("queryModel.currentPage", "1"),
            ("queryModel.sortName", ""),
            ("queryModel.sortOrder", "asc"),
            ("time", "1")
        ])

        async let taskB = postForm(url: urlB, cookie: cookie, params: [
            ("xnm", term.xnm),
            ("xqm", term.xqm),
            ("ksmcdmb_id", ""),
            ("kch", ""),
            ("kc", ""),
            ("ksrq", ""),
            ("kkbm_id", ""),
            ("_search", "false"),
            ("nd", "1"),
            ("queryModel.showCount", "100"),
            ("queryModel.currentPage", "1"),
            ("queryModel.sortName", "+"),
            ("queryModel.sortOrder", "asc"),
            ("time", "5")
        ])

        let respA = try? await taskA
        let respB = try? await taskB
        if respA == nil && respB == nil {
            throw NSError(domain: "JwglxtClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "查询考试安排失败，请检查网络"])
        }

        let listA = respA.map { JwglxtParser.parseExamChannelA(jsonString: $0.bodyString, wantXnmc: term.xnmcString, wantXq: term.xqString) } ?? []
        let listB = respB.map { JwglxtParser.parseExamChannelB(jsonString: $0.bodyString) } ?? []
        return JwglxtParser.mergeExams(channelA: listA, channelB: listB)
    }

    public func fetchEmptyClassrooms(
        term: AcademicTerm,
        campus: EmptyClassroomCampus,
        week: Int,
        day: Int,
        period: Int,
        cookie: String
    ) async throws -> [EmptyClassroom] {
        let targets: [EmptyClassroomCampus] = campus == .all ? [.north, .east, .west] : [campus]
        let zcd = (1...31).contains(week) ? (1 << (week - 1)) : 0
        let jcd = (1...31).contains(period) ? (1 << (period - 1)) : 0
        let url = URL(string: "\(Self.baseURL)/jwglxt/cdjy/cdjy_cxKxcdlb.html?doType=query&gnmkdm=N2155")!

        var merged: [EmptyClassroom] = []
        var seen = Set<String>()
        for target in targets {
            let ts = Int64(Date().timeIntervalSince1970 * 1000)
            let resp = try await postForm(url: url, cookie: cookie, params: [
                ("xqh_id", "\(target.rawValue)"),
                ("xnm", term.xnm),
                ("xqm", term.xqm),
                ("cdlb_id", ""),
                ("cdejlb_id", ""),
                ("qszws", ""),
                ("jszws", ""),
                ("cdmc", ""),
                ("cd_id", ""),
                ("lh", ""),
                ("jyfs", "0"),
                ("cdjylx", ""),
                ("zysx", ""),
                ("sflb", ""),
                ("hbsl", ""),
                ("bbsl", ""),
                ("sfyzz", ""),
                ("sfjtjs", ""),
                ("tjsl", ""),
                ("tymbsl", ""),
                ("yczb", ""),
                ("zws", ""),
                ("sfbhkc", ""),
                ("kszws1", ""),
                ("zcd", "\(zcd)"),
                ("xqj", "\(day)"),
                ("jcd", "\(jcd)"),
                ("queryModel.showCount", "5000"),
                ("queryModel.currentPage", "1"),
                ("queryModel.sortName", "cdbh"),
                ("queryModel.sortOrder", "asc"),
                ("time", "\(ts)")
            ])
            for room in JwglxtParser.parseEmptyClassrooms(jsonString: resp.bodyString) {
                if seen.insert(room.id).inserted {
                    merged.append(room)
                }
            }
        }
        return merged
    }

    private func get(url: URL, cookie: String) async throws -> HttpResponseData {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue(Self.defaultReferer, forHTTPHeaderField: "Referer")
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        let resp = try await transport.send(req, timeout: 20)
        if JwglxtParser.isSessionExpired(statusCode: resp.statusCode, url: resp.url, body: resp.bodyString) {
            throw JwglxtSessionExpiredError(statusCode: resp.statusCode)
        }
        return resp
    }

    private func postForm(url: URL, cookie: String, params: [(String, String)]) async throws -> HttpResponseData {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue(Self.baseURL, forHTTPHeaderField: "Origin")
        req.setValue(Self.defaultReferer, forHTTPHeaderField: "Referer")
        req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        req.httpBody = formEncode(params)
        let resp = try await transport.send(req, timeout: 25)
        if JwglxtParser.isSessionExpired(statusCode: resp.statusCode, url: resp.url, body: resp.bodyString) {
            throw JwglxtSessionExpiredError(statusCode: resp.statusCode)
        }
        return resp
    }

    private func formEncode(_ pairs: [(String, String)]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        let body = pairs.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }
}
