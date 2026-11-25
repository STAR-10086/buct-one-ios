import BuctModel
import BuctNetwork
import Foundation

public actor CourseSelectionClient {
    private static let baseURL = "https://jwglxt.buct.edu.cn/jwglxt"
    private static let origin = "https://jwglxt.buct.edu.cn"
    private static let indexURL = "https://jwglxt.buct.edu.cn/jwglxt/xsxk/zzxkyzb_cxZzxkYzbIndex.html?gnmkdm=N253512&layout=default&su=jwglxt.buct.edu.cn"
    private static let desktopUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

    private let transport: BuctHttpTransport
    private let jar = MatchingMemoryCookieJar()
    private var cachedIndexParams: [String: String] = [:]
    private var cachedDisplayParamsByTab: [String: [String: String]] = [:]

    public init(transport: BuctHttpTransport = .shared) {
        self.transport = transport
    }

    public func seedCookies(sidCookies: String, jwCookies: String) {
        jar.clear()
        let cleanSid = sidCookies.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSid.isEmpty {
            jar.seed(cookieHeader: cleanSid, setByHost: "sidportal.buct.edu.cn")
        }
        let cleanJw = jwCookies.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanJw.isEmpty {
            jar.seed(cookieHeader: cleanJw, setByHost: "jwglxt.buct.edu.cn")
        }
    }

    public func exportJwCookies() -> String {
        jar.cookieHeaderFor(url: URL(string: "\(Self.baseURL)/")!)
    }

    public func fetchSnapshot(
        sidCookies: String,
        jwCookies: String,
        onlyWithSeats: Bool = false,
        keyword: String = ""
    ) async throws -> CourseSelectionSnapshot {
        seedCookies(sidCookies: sidCookies, jwCookies: jwCookies)
        let (indexParams, tabs, notOpenNotice) = try await loadIndexContext()
        cachedIndexParams = indexParams

        if tabs.isEmpty {
            return CourseSelectionSnapshot(
                isOpen: false,
                statusMessage: notOpenNotice,
                xkxnm: indexParams["xkxnm"] ?? "",
                xkxqm: indexParams["xkxqm"] ?? ""
            )
        }

        var allAvailable: [CourseSelectionCourse] = []
        var seenIds = Set<String>()

        for tab in tabs {
            let displayParams = (try? await loadDisplayParams(tab: tab)) ?? [:]
            cachedDisplayParamsByTab[tab.id] = displayParams
            let merged = indexParams.merging(displayParams) { _, new in new }

            var ksPage = 1
            let pageSize = 20
            for _ in 0..<8 {
                let jsPage = ksPage + pageSize - 1
                let pageCourses = (try? await fetchAvailablePage(
                    tab: tab,
                    mergedParams: merged,
                    ksPage: ksPage,
                    jsPage: jsPage,
                    onlyWithSeats: onlyWithSeats,
                    keyword: keyword
                )) ?? []
                if pageCourses.isEmpty { break }
                for c in pageCourses where seenIds.insert(c.id).inserted {
                    allAvailable.append(c)
                }
                if pageCourses.count < pageSize { break }
                ksPage = jsPage + 1
            }
        }

        let selected = (try? await fetchSelectedCourses(indexParams: indexParams)) ?? []
        let selectedClassIds = Set(selected.map(\.classId).filter { !$0.isEmpty })
        let markedAvailable = allAvailable.map { c -> CourseSelectionCourse in
            var copy = c
            if !c.classId.isEmpty && selectedClassIds.contains(c.classId) {
                copy.isSelected = true
            }
            return copy
        }

        return CourseSelectionSnapshot(
            isOpen: true,
            statusMessage: "选课开放中 · 共 \(tabs.count) 个分类",
            xkxnm: indexParams["xkxnm"] ?? "",
            xkxqm: indexParams["xkxqm"] ?? "",
            tabs: tabs,
            availableCourses: markedAvailable,
            selectedCourses: selected
        )
    }

    public func fetchTeachingClasses(
        sidCookies: String,
        jwCookies: String,
        course: CourseSelectionCourse
    ) async throws -> [CourseSelectionCourse] {
        seedCookies(sidCookies: sidCookies, jwCookies: jwCookies)
        let indexParams: [String: String]
        if cachedIndexParams.isEmpty {
            let loaded = try await loadIndexContext()
            cachedIndexParams = loaded.inputs
            indexParams = loaded.inputs
        } else {
            indexParams = cachedIndexParams
        }
        let tab = CourseSelectionTabParam(kklxdm: course.kklxdm, xkkzId: course.xkkzId, njdmId: course.njdmId, zyhId: course.zyhId)
        let displayParams: [String: String]
        if let cached = cachedDisplayParamsByTab[tab.id] {
            displayParams = cached
        } else {
            let loaded = (try? await loadDisplayParams(tab: tab)) ?? [:]
            cachedDisplayParamsByTab[tab.id] = loaded
            displayParams = loaded
        }
        let merged = indexParams.merging(displayParams) { _, new in new }
        return try await postTeachingClasses(courseId: course.courseId, tab: tab, merged: merged)
    }

    public func selectCourse(
        sidCookies: String,
        jwCookies: String,
        course: CourseSelectionCourse
    ) async throws -> CourseSelectionActionResult {
        seedCookies(sidCookies: sidCookies, jwCookies: jwCookies)
        // Step 1: 刷新 Index 与 Display 参数
        let loadedIndex = try await loadIndexContext()
        cachedIndexParams = loadedIndex.inputs
        let tab = CourseSelectionTabParam(
            kklxdm: course.kklxdm,
            xkkzId: course.xkkzId.isEmpty ? (loadedIndex.tabs.first(where: { $0.kklxdm == course.kklxdm })?.xkkzId ?? loadedIndex.tabs.first?.xkkzId ?? "") : course.xkkzId,
            njdmId: course.njdmId.isEmpty ? (loadedIndex.inputs["njdm_id"] ?? "") : course.njdmId,
            zyhId: course.zyhId.isEmpty ? (loadedIndex.inputs["zyh_id"] ?? "") : course.zyhId
        )
        let displayParams = (try? await loadDisplayParams(tab: tab)) ?? [:]
        cachedDisplayParamsByTab[tab.id] = displayParams
        let merged = loadedIndex.inputs.merging(displayParams) { _, new in new }

        // Step 2: 获取最新加密 do_jxb_id
        let classes = try await postTeachingClasses(courseId: course.courseId, tab: tab, merged: merged)
        let matched = classes.first(where: { !course.classId.isEmpty && $0.classId == course.classId })
            ?? classes.first(where: { !course.doJxbId.isEmpty && $0.doJxbId == course.doJxbId })
            ?? classes.first
        let target = matched ?? course
        let doJxbId = target.doJxbId.isEmpty ? target.classId : target.doJxbId
        guard !doJxbId.isEmpty else {
            return CourseSelectionActionResult(success: false, message: "未能获取该教学班的选课编号（do_jxb_id）")
        }

        // Step 3: 提交选课（固定 18 字段）
        let form: [(String, String)] = [
            ("jxb_ids", doJxbId),
            ("kch_id", target.courseId),
            ("kcmc", "(\(target.courseId))\(target.name)"),
            ("rwlx", target.rwlx),
            ("rlkz", target.rlkz),
            ("rlzlkz", target.rlzlkz),
            ("sxbj", target.sxbj),
            ("xxkbj", target.xxkbj),
            ("qz", "0"),
            ("cxbj", target.cxbj),
            ("xkkz_id", target.xkkzId.isEmpty ? tab.xkkzId : target.xkkzId),
            ("njdm_id", target.njdmId.isEmpty ? (merged["njdm_id"] ?? "") : target.njdmId),
            ("zyh_id", target.zyhId.isEmpty ? (merged["zyh_id"] ?? "") : target.zyhId),
            ("kklxdm", target.kklxdm),
            ("xklc", target.xklc),
            ("xkxnm", target.xkxnm.isEmpty ? (merged["xkxnm"] ?? "") : target.xkxnm),
            ("xkxqm", target.xkxqm.isEmpty ? (merged["xkxqm"] ?? "") : target.xkxqm),
            ("jcxx_id", target.jcxxId)
        ]
        let text = try await postForm(path: "/xsxk/zzxkyzbjk_xkBcZyZzxkYzb.html?gnmkdm=N253512", fields: form)
        return CourseSelectionParser.parseSelectResult(jsonString: text)
    }

    public func dropCourse(
        sidCookies: String,
        jwCookies: String,
        course: CourseSelectionCourse
    ) async throws -> CourseSelectionActionResult {
        seedCookies(sidCookies: sidCookies, jwCookies: jwCookies)
        let xkxnm = course.xkxnm.isEmpty ? (cachedIndexParams["xkxnm"] ?? "") : course.xkxnm
        let xkxqm = course.xkxqm.isEmpty ? (cachedIndexParams["xkxqm"] ?? "") : course.xkxqm
        let jxbId = course.doJxbId.isEmpty ? course.classId : course.doJxbId
        let form: [(String, String)] = [
            ("kch_id", course.courseId),
            ("jxb_ids", jxbId),
            ("xkxnm", xkxnm),
            ("xkxqm", xkxqm),
            ("txbsfrl", "0")
        ]
        let text = try await postForm(path: "/xsxk/zzxkyzb_tuikBcZzxkYzb.html?gnmkdm=N253512", fields: form)
        return CourseSelectionParser.parseDropResult(rawText: text)
    }

    // MARK: - Internal Requests

    private func loadIndexContext() async throws -> (inputs: [String: String], tabs: [CourseSelectionTabParam], notice: String) {
        var req = URLRequest(url: URL(string: Self.indexURL)!)
        req.httpMethod = "GET"
        req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let resp = try await transport.send(req, cookieJar: jar, timeout: 20)
        let html = resp.decodedText()
        if CourseSelectionParser.isSessionExpired(statusCode: resp.statusCode, url: resp.url, body: html) {
            throw CourseSelectionAuthExpiredError()
        }
        let inputs = CourseSelectionParser.parseHiddenInputs(html: html)
        let tabs = CourseSelectionParser.parseTabParams(html: html, hiddenInputs: inputs)
        let notice = tabs.isEmpty ? CourseSelectionParser.extractNotOpenNotice(html: html) : ""
        return (inputs, tabs, notice)
    }

    private func loadDisplayParams(tab: CourseSelectionTabParam) async throws -> [String: String] {
        let fields: [(String, String)] = [
            ("xkkz_id", tab.xkkzId),
            ("kklxdm", tab.kklxdm),
            ("xszxzt", "1"),
            ("njdm_id", tab.njdmId),
            ("zyh_id", tab.zyhId),
            ("kspage", "0"),
            ("jspage", "0")
        ]
        let html = try await postForm(path: "/xsxk/zzxkyzb_cxZzxkYzbDisplay.html?gnmkdm=N253512", fields: fields)
        return CourseSelectionParser.parseHiddenInputs(html: html)
    }

    private func fetchAvailablePage(
        tab: CourseSelectionTabParam,
        mergedParams m: [String: String],
        ksPage: Int,
        jsPage: Int,
        onlyWithSeats: Bool,
        keyword: String
    ) async throws -> [CourseSelectionCourse] {
        let isPe = tab.kklxdm == "05"
        var fields: [(String, String)] = []
        if onlyWithSeats {
            fields.append(("yl_list[0]", "1"))
        }
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !kw.isEmpty {
            fields.append(("filter_list[0]", kw))
        }
        let base: [(String, String)] = [
            ("rwlx", m["rwlx"] ?? "1"),
            ("xklc", m["xklc"] ?? "2"),
            ("xkly", m["xkly"] ?? "0"),
            ("bklx_id", m["bklx_id"] ?? "0"),
            ("sfkkjyxdxnxq", m["sfkkjyxdxnxq"] ?? "0"),
            ("kzkcgs", m["kzkcgs"] ?? "0"),
            ("xqh_id", m["xqh_id"] ?? ""),
            ("jg_id", m["jg_id"] ?? ""),
            ("njdm_id_1", m["njdm_id_1"] ?? m["njdm_id"] ?? ""),
            ("zyh_id_1", m["zyh_id_1"] ?? m["zyh_id"] ?? ""),
            ("gnjkxdnj", m["gnjkxdnj"] ?? "0"),
            ("zyh_id", m["zyh_id"] ?? tab.zyhId),
            ("zyfx_id", m["zyfx_id"] ?? ""),
            ("njdm_id", m["njdm_id"] ?? tab.njdmId),
            ("bh_id", m["bh_id"] ?? ""),
            ("bjgkczxbbjwcx", m["bjgkczxbbjwcx"] ?? (isPe ? "1" : "0")),
            ("xbm", m["xbm"] ?? ""),
            ("xslbdm", m["xslbdm"] ?? ""),
            ("mzm", m["mzm"] ?? ""),
            ("xz", m["xz"] ?? ""),
            ("ccdm", m["ccdm"] ?? ""),
            ("xsbj", m["xsbj"] ?? ""),
            ("sfkknj", m["sfkknj"] ?? "0"),
            ("sfkkzy", m["sfkkzy"] ?? "0"),
            ("kzybkxy", m["kzybkxy"] ?? "0"),
            ("sfznkx", m["sfznkx"] ?? "0"),
            ("zdkxms", m["zdkxms"] ?? "0"),
            ("sfkxq", m["sfkxq"] ?? "0"),
            ("sfkcfx", m["sfkcfx"] ?? (isPe ? "1" : "0")),
            ("kkbk", m["kkbk"] ?? "0"),
            ("kkbkdj", m["kkbkdj"] ?? "0"),
            ("bklbkcj", m["bklbkcj"] ?? "0"),
            ("sfkgbcx", m["sfkgbcx"] ?? (isPe ? "1" : "0")),
            ("sfrxtgkcxd", m["sfrxtgkcxd"] ?? (isPe ? "1" : "0")),
            ("tykczgxdcs", m["tykczgxdcs"] ?? (isPe ? "8" : "0")),
            ("xkxnm", m["xkxnm"] ?? ""),
            ("xkxqm", m["xkxqm"] ?? ""),
            ("xkxskcgskg", m["xkxskcgskg"] ?? "0"),
            ("kklxdm", tab.kklxdm),
            ("xkkz_id", tab.xkkzId),
            ("xkkz_xh", tab.xkkzId),
            ("kspage", "\(ksPage)"),
            ("jspage", "\(jsPage)"),
            ("bbhzxjxb", "0"),
            ("rlkz", "0"),
            ("xkzgbj", "0"),
            ("jxbzb", "")
        ]
        fields.append(contentsOf: base)
        let text = try await postForm(path: "/xsxk/zzxkyzb_cxZzxkYzbPartDisplay.html?gnmkdm=N253512", fields: fields)
        return CourseSelectionParser.parseCourseList(jsonString: text, tab: tab, baseParams: m, markSelected: false)
    }

    private func postTeachingClasses(
        courseId: String,
        tab: CourseSelectionTabParam,
        merged m: [String: String]
    ) async throws -> [CourseSelectionCourse] {
        let fields: [(String, String)] = [
            ("rwlx", m["rwlx"] ?? "1"),
            ("xkly", m["xkly"] ?? "0"),
            ("bklx_id", m["bklx_id"] ?? "0"),
            ("sfkkjyxdxnxq", m["sfkkjyxdxnxq"] ?? "0"),
            ("kzkcgs", m["kzkcgs"] ?? "0"),
            ("txbsfrl", m["txbsfrl"] ?? "0"),
            ("xqh_id", m["xqh_id"] ?? ""),
            ("jg_id", m["jg_id"] ?? ""),
            ("zyh_id", m["zyh_id"] ?? tab.zyhId),
            ("zyfx_id", m["zyfx_id"] ?? ""),
            ("njdm_id", m["njdm_id"] ?? tab.njdmId),
            ("bh_id", m["bh_id"] ?? ""),
            ("xbm", m["xbm"] ?? ""),
            ("xslbdm", m["xslbdm"] ?? ""),
            ("mzm", m["mzm"] ?? ""),
            ("xz", m["xz"] ?? ""),
            ("ccdm", m["ccdm"] ?? ""),
            ("xsbj", m["xsbj"] ?? ""),
            ("sfkknj", m["sfkknj"] ?? "0"),
            ("gnjkxdnj", m["gnjkxdnj"] ?? "0"),
            ("sfkkzy", m["sfkkzy"] ?? "0"),
            ("kzybkxy", m["kzybkxy"] ?? "0"),
            ("sfznkx", m["sfznkx"] ?? "0"),
            ("zdkxms", m["zdkxms"] ?? "0"),
            ("sfkxq", m["sfkxq"] ?? "0"),
            ("sfkcfx", m["sfkcfx"] ?? "0"),
            ("bbhzxjxb", m["bbhzxjxb"] ?? "0"),
            ("kkbk", m["kkbk"] ?? "0"),
            ("kkbkdj", m["kkbkdj"] ?? "0"),
            ("bklbkcj", m["bklbkcj"] ?? "0"),
            ("xkxnm", m["xkxnm"] ?? ""),
            ("xkxqm", m["xkxqm"] ?? ""),
            ("xkxskcgskg", m["xkxskcgskg"] ?? "0"),
            ("rlkz", m["rlkz"] ?? "0"),
            ("cdrlkz", m["cdrlkz"] ?? "0"),
            ("rlzlkz", m["rlzlkz"] ?? "0"),
            ("kklxdm", tab.kklxdm),
            ("kch_id", courseId),
            ("jxbzcxskg", m["jxbzcxskg"] ?? "0"),
            ("xklc", m["xklc"] ?? "2"),
            ("xkkz_id", tab.xkkzId),
            ("cxbj", m["cxbj"] ?? "0"),
            ("fxbj", m["fxbj"] ?? "0")
        ]
        let text = try await postForm(path: "/xsxk/zzxkyzbjk_cxJxbWithKchZzxkYzb.html?gnmkdm=N253512", fields: fields)
        return CourseSelectionParser.parseCourseList(jsonString: text, tab: tab, baseParams: m, markSelected: false)
    }

    private func fetchSelectedCourses(indexParams m: [String: String]) async throws -> [CourseSelectionCourse] {
        let fields: [(String, String)] = [
            ("jg_id", m["jg_id"] ?? ""),
            ("zyh_id", m["zyh_id"] ?? ""),
            ("njdm_id", m["njdm_id"] ?? ""),
            ("zyfx_id", m["zyfx_id"] ?? ""),
            ("bh_id", m["bh_id"] ?? ""),
            ("xz", m["xz"] ?? ""),
            ("ccdm", m["ccdm"] ?? ""),
            ("xqh_id", m["xqh_id"] ?? ""),
            ("xkxnm", m["xkxnm"] ?? ""),
            ("xkxqm", m["xkxqm"] ?? ""),
            ("xkly", m["xkly"] ?? "0")
        ]
        let text = try await postForm(path: "/xsxk/zzxkyzb_cxZzxkYzbChoosedDisplay.html?gnmkdm=N253512", fields: fields)
        return CourseSelectionParser.parseCourseList(jsonString: text, baseParams: m, markSelected: true)
    }

    private func postForm(path: String, fields: [(String, String)]) async throws -> String {
        var req = URLRequest(url: URL(string: "\(Self.baseURL)\(path)")!)
        req.httpMethod = "POST"
        req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue(Self.origin, forHTTPHeaderField: "Origin")
        req.setValue(Self.indexURL, forHTTPHeaderField: "Referer")
        let encoded = fields.map { "\(Self.formEncode($0.0))=\(Self.formEncode($0.1))" }.joined(separator: "&")
        req.httpBody = Data(encoded.utf8)

        let resp = try await transport.send(req, cookieJar: jar, timeout: 20)
        let text = resp.decodedText()
        if CourseSelectionParser.isSessionExpired(statusCode: resp.statusCode, url: resp.url, body: text) {
            throw CourseSelectionAuthExpiredError()
        }
        guard resp.statusCode == 200 else {
            throw NSError(domain: "CourseSelectionClient", code: resp.statusCode, userInfo: [NSLocalizedDescriptionKey: "教务选课请求失败（HTTP \(resp.statusCode)）"])
        }
        return text
    }

    private static func formEncode(_ raw: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return (raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw)
            .replacingOccurrences(of: "%20", with: "+")
    }
}
