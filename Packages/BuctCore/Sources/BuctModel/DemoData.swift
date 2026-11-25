import Foundation

public enum DemoData {
    public static let profile = UserAccountProfile(
        studentId: "2024000001",
        studentName: "演示用户",
        systemType: .demo
    )

    public static let currentTerm = AcademicTerm(year: 2025, semester: 2)

    public static func scheduleCourses() -> [ScheduleCourse] {
        let w = Array(1...18)
        return [
            ScheduleCourse(id: "demo-1", name: "数据结构与算法", teacher: "张明远", location: "昌平 教学楼A201", dayOfWeek: 1, startPeriod: 1, endPeriod: 2, weeksText: "1-18周", weeks: w, colorIndex: 0),
            ScheduleCourse(id: "demo-2", name: "概率论与数理统计", teacher: "李静", location: "昌平 教学楼B105", dayOfWeek: 1, startPeriod: 3, endPeriod: 4, weeksText: "1-18周", weeks: w, colorIndex: 1),
            ScheduleCourse(id: "demo-3", name: "学术英语写作", teacher: "王芳", location: "昌平 阶梯教室2", dayOfWeek: 1, startPeriod: 7, endPeriod: 8, weeksText: "1-18周", weeks: w, colorIndex: 2),
            ScheduleCourse(id: "demo-4", name: "人工智能导论", teacher: "陈志强", location: "昌平 信息楼302", dayOfWeek: 2, startPeriod: 3, endPeriod: 4, weeksText: "1-18周", weeks: w, colorIndex: 3),
            ScheduleCourse(id: "demo-5", name: "操作系统", teacher: "刘伟", location: "昌平 教学楼A305", dayOfWeek: 2, startPeriod: 5, endPeriod: 6, weeksText: "1-18周", weeks: w, colorIndex: 4),
            ScheduleCourse(id: "demo-6", name: "电影音乐鉴赏", teacher: "赵敏", location: "昌平 艺术中心101", dayOfWeek: 2, startPeriod: 9, endPeriod: 10, weeksText: "1-18周", weeks: w, colorIndex: 5),
            ScheduleCourse(id: "demo-7", name: "数据结构与算法", teacher: "张明远", location: "昌平 教学楼A201", dayOfWeek: 3, startPeriod: 3, endPeriod: 4, weeksText: "1-18周", weeks: w, colorIndex: 0),
            ScheduleCourse(id: "demo-8", name: "积极心理学", teacher: "周婷", location: "昌平 教学楼C202", dayOfWeek: 3, startPeriod: 7, endPeriod: 8, weeksText: "1-18周", weeks: w, colorIndex: 6),
            ScheduleCourse(id: "demo-9", name: "经济学思维", teacher: "孙磊", location: "昌平 教学楼B304", dayOfWeek: 4, startPeriod: 1, endPeriod: 2, weeksText: "1-18周", weeks: w, colorIndex: 7),
            ScheduleCourse(id: "demo-10", name: "计算机网络", teacher: "吴昊", location: "昌平 教学楼A401", dayOfWeek: 4, startPeriod: 3, endPeriod: 4, weeksText: "1-18周", weeks: w, colorIndex: 8),
            ScheduleCourse(id: "demo-11", name: "Web 应用开发", teacher: "郑阳", location: "昌平 实验楼402", dayOfWeek: 4, startPeriod: 5, endPeriod: 6, weeksText: "1-18周", weeks: w, colorIndex: 9),
            ScheduleCourse(id: "demo-12", name: "交互设计基础", teacher: "林琳", location: "昌平 设计工坊201", dayOfWeek: 5, startPeriod: 1, endPeriod: 2, weeksText: "1-18周", weeks: w, colorIndex: 10),
            ScheduleCourse(id: "demo-13", name: "羽毛球", teacher: "陈教练", location: "昌平 体育馆", dayOfWeek: 5, startPeriod: 5, endPeriod: 6, weeksText: "1-18周", weeks: w, colorIndex: 11)
        ]
    }

    public static func overallBundle() -> OverallAcademicBundle {
        let sem2025 = [
            GradeItem(id: "g1", courseCode: "CS201", courseName: "数据结构与算法", score: "94", credits: 3.5, serverGpa: 4.00, courseType: "专业必修", year: "2025", term: "12", college: "计算机科学与技术学院", examNature: "正常考试", detail: "平时(30%): 96 | 期末(70%): 93"),
            GradeItem(id: "g2", courseCode: "MA204", courseName: "概率论与数理统计", score: "88", credits: 3.0, serverGpa: 3.67, courseType: "学科基础", year: "2025", term: "12", college: "数理学院", examNature: "正常考试", detail: "平时(30%): 90 | 期末(70%): 87"),
            GradeItem(id: "g3", courseCode: "CS302", courseName: "操作系统", score: "91", credits: 3.5, serverGpa: 4.00, courseType: "专业必修", year: "2025", term: "12", college: "计算机科学与技术学院", examNature: "正常考试", detail: "平时(25%): 92 | 实验(25%): 94 | 期末(50%): 89"),
            GradeItem(id: "g4", courseCode: "CS305", courseName: "计算机网络", score: "86", credits: 3.0, serverGpa: 3.67, courseType: "专业必修", year: "2025", term: "12", college: "计算机科学与技术学院", examNature: "正常考试", detail: "平时(30%): 88 | 期末(70%): 85"),
            GradeItem(id: "g5", courseCode: "AI201", courseName: "人工智能导论", score: "93", credits: 2.5, serverGpa: 4.00, courseType: "专业选修", year: "2025", term: "12", college: "计算机科学与技术学院", examNature: "正常考试", detail: "平时(40%): 95 | 期末(60%): 92"),
            GradeItem(id: "g6", courseCode: "EN202", courseName: "学术英语写作", score: "89", credits: 2.0, serverGpa: 3.67, courseType: "通识必修", year: "2025", term: "12", college: "文法学院", examNature: "正常考试", detail: "平时(50%): 91 | 期末(50%): 87"),
            GradeItem(id: "g7", courseCode: "PE204", courseName: "体育 IV", score: "优秀", credits: 1.0, serverGpa: nil, courseType: "通识必修", year: "2025", term: "12", college: "体育部", examNature: "正常考试")
        ]
        let sem2024 = [
            GradeItem(id: "g8", courseCode: "CS104", courseName: "离散数学", score: "90", credits: 3.0, serverGpa: 4.00, courseType: "专业必修", year: "2024", term: "3", college: "计算机科学与技术学院", examNature: "正常考试", detail: "平时(30%): 92 | 期末(70%): 89"),
            GradeItem(id: "g9", courseCode: "CS102", courseName: "面向对象程序设计", score: "96", credits: 3.5, serverGpa: 4.33, courseType: "专业必修", year: "2024", term: "12", college: "计算机科学与技术学院", examNature: "正常考试", detail: "平时(40%): 97 | 期末(60%): 95"),
            GradeItem(id: "g10", courseCode: "PH101", courseName: "大学物理", score: "84", credits: 3.0, serverGpa: 3.33, courseType: "学科基础", year: "2024", term: "3", college: "数理学院", examNature: "正常考试", detail: "平时(30%): 86 | 期末(70%): 83")
        ]

        let nodes = [
            CurriculumNode(id: "root", parentId: "", name: "计算机科学与技术培养方案", isLeaf: false, earnedCredits: 27.5, requiredCredits: 160.0, passed: false),
            CurriculumNode(
                id: "n-major",
                parentId: "root",
                name: "专业核心课程",
                isLeaf: true,
                earnedCredits: 16.5,
                requiredCredits: 32.0,
                passed: false,
                courses: [
                    CurriculumCourse(id: "cc1", courseCode: "CS102", courseName: "面向对象程序设计", credits: 3.5, studyStatus: "4", grade: "96", suggestedYear: "2024-2025", suggestedTerm: "2"),
                    CurriculumCourse(id: "cc2", courseCode: "CS201", courseName: "数据结构与算法", credits: 3.5, studyStatus: "4", grade: "94", suggestedYear: "2025-2026", suggestedTerm: "2"),
                    CurriculumCourse(id: "cc3", courseCode: "CS302", courseName: "操作系统", credits: 3.5, studyStatus: "4", grade: "91", suggestedYear: "2025-2026", suggestedTerm: "2"),
                    CurriculumCourse(id: "cc4", courseCode: "CS401", courseName: "编译原理", credits: 3.0, studyStatus: "1", suggestedYear: "2026-2027", suggestedTerm: "1"),
                    CurriculumCourse(id: "cc5", courseCode: "CS405", courseName: "分布式系统", credits: 3.0, studyStatus: "3", suggestedYear: "2026-2027", suggestedTerm: "2")
                ]
            ),
            CurriculumNode(
                id: "n-basic",
                parentId: "root",
                name: "学科基础课",
                isLeaf: true,
                earnedCredits: 6.0,
                requiredCredits: 24.0,
                passed: false,
                courses: [
                    CurriculumCourse(id: "cc6", courseCode: "PH101", courseName: "大学物理", credits: 3.0, studyStatus: "4", grade: "84", suggestedYear: "2024-2025", suggestedTerm: "1"),
                    CurriculumCourse(id: "cc7", courseCode: "MA204", courseName: "概率论与数理统计", credits: 3.0, studyStatus: "4", grade: "88", suggestedYear: "2025-2026", suggestedTerm: "2")
                ]
            )
        ]

        return OverallAcademicBundle(
            grades: sem2025 + sem2024,
            summary: OverallGradeSummary(officialGpa: 3.96, officialCredits: 27.5, officialCourseCount: 10),
            curriculumNodes: nodes
        )
    }

    public static func exams() -> [ExamItem] {
        [
            ExamItem(id: "ex1", courseName: "操作系统", examTime: "2026-06-18(09:00-11:00)", location: "博学楼 B301", seatNumber: "18", examName: "期末考试"),
            ExamItem(id: "ex2", courseName: "计算机网络", examTime: "2026-06-20(14:00-16:00)", location: "博学楼 B305", seatNumber: "22", examName: "期末考试"),
            ExamItem(id: "ex3", courseName: "概率论与数理统计", examTime: "2026-06-23(09:00-11:00)", location: "博雅楼 201", seatNumber: "07", examName: "期末考试"),
            ExamItem(id: "ex4", courseName: "人工智能导论", examTime: "2026-06-25(14:00-16:00)", location: "创新中心 301", seatNumber: "15", examName: "期末考试")
        ]
    }

    public static func emptyClassrooms(campus: EmptyClassroomCampus) -> [EmptyClassroom] {
        let all = [
            EmptyClassroom(id: "r1", code: "N101", name: "北一教 101", campus: "北区", building: "第一教学楼", floor: "1", type: "多媒体教室", seats: 120, examSeats: 60),
            EmptyClassroom(id: "r2", code: "N204", name: "北二教 204", campus: "北区", building: "第二教学楼", floor: "2", type: "智慧教室", seats: 80, examSeats: 40),
            EmptyClassroom(id: "r3", code: "E302", name: "主教 302", campus: "东区", building: "主教学楼", floor: "3", type: "多媒体教室", seats: 100, examSeats: 50),
            EmptyClassroom(id: "r4", code: "W105", name: "西阶 105", campus: "西区", building: "阶梯教室", floor: "1", type: "阶梯教室", seats: 150, examSeats: 75)
        ]
        if campus == .all { return all }
        return all.filter { $0.campus == campus.title }
    }

    public static func calendar() -> OfficialCalendarSnapshot {
        OfficialCalendarSnapshot(
            currentTermId: currentTerm.id,
            beginDate: "2026-03-02",
            endDate: "2026-07-05",
            currentTeachingWeek: 13,
            terms: [
                OfficialTermDate(wid: "1", academicYear: 2025, semester: 2, termId: currentTerm.id, beginDate: "2026-03-02", endDate: "2026-07-05", isCurrent: true)
            ]
        )
    }

    public static func jwNoticeSnapshot() -> JwNoticeSnapshot {
        JwNoticeSnapshot(
            reminders: [
                JwReminderItem(id: "demo-r1", title: "调课通知：《操作系统》上课时间调整", content: "第 14 周周一 3-4 节调整至周五 5-6 节，地点不变（北区二教 204）。", createdAt: "2026-05-25 10:20", isRead: false, category: .reschedule),
                JwReminderItem(id: "demo-r2", title: "期末考试安排已发布", content: "《编译原理》期末考试定于 2026-06-18 09:00 在博学楼 A201 举行。", createdAt: "2026-05-24 14:00", isRead: true, category: .exam)
            ],
            reminderTotal: 2,
            announcements: [
                JwAnnouncementItem(id: "demo-a1", title: "关于 2025-2026 学年第二学期期末考试考风考纪的通知", publisher: "教务处", publishedAt: "2026-05-22 09:00", isPinned: true, isRead: false, inlineHtml: "<p>请各位同学严格遵守考场纪律，携带有效证件按时参加期末考试。</p>"),
                JwAnnouncementItem(id: "demo-a2", title: "2026 年秋季学期本科生选课日程安排", publisher: "教务运行科", publishedAt: "2026-05-18 16:30", isPinned: false, isRead: true, inlineHtml: "<p>第一轮选课将于第 16 周开启，请提前关注培养方案学分要求。</p>")
            ],
            announcementTotal: 2
        )
    }

    public static func portalNewsSnapshot() -> PortalNewsSnapshot {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        return PortalNewsSnapshot(columns: [
            PortalNewsColumn.notice.rawValue: PortalNewsColumnPage(
                columnId: PortalNewsColumn.notice.rawValue,
                totalCount: 1,
                articles: [
                    PortalNewsArticle(id: "demo-n1", columnId: PortalNewsColumn.notice.rawValue, title: "关于开展 2026 年夏季学期校园安全教育活动的通知", sourceOrg: "学工办", publishTimestampMs: nowMs - 3_600_000, summary: "请各学院组织学生按时完成安全教育专题学习。", content: "请各学院组织学生按时完成安全教育专题学习，注意实验室与宿舍用电安全。", publicUrl: "https://i.buct.edu.cn", isTop: true)
                ]
            ),
            PortalNewsColumn.activity.rawValue: PortalNewsColumnPage(
                columnId: PortalNewsColumn.activity.rawValue,
                totalCount: 1,
                articles: [
                    PortalNewsArticle(id: "demo-n2", columnId: PortalNewsColumn.activity.rawValue, title: "第十六届校园科技文化节闭幕式暨晚会预告", sourceOrg: "校团委", publishTimestampMs: nowMs - 7_200_000, summary: "本周五晚 19:00 在昌平校区大学生活动中心举行。", content: "本周五晚 19:00 在昌平校区大学生活动中心举行，欢迎同学们凭校园卡入场。", publicUrl: "https://i.buct.edu.cn", isHot: true)
                ]
            ),
            PortalNewsColumn.career.rawValue: PortalNewsColumnPage(
                columnId: PortalNewsColumn.career.rawValue,
                totalCount: 1,
                articles: [
                    PortalNewsArticle(id: "demo-n3", columnId: PortalNewsColumn.career.rawValue, title: "2026 届毕业生春季重点企业双选会邀请函", sourceOrg: "就业信息网", publishTimestampMs: nowMs - 14_400_000, summary: "60 余家化工、材料与信息类重点企业进校招聘。", content: "60 余家重点企业进校招聘，请携带简历前往东区就业中心大厅。", publicUrl: "https://i.buct.edu.cn")
                ]
            ),
            PortalNewsColumn.news.rawValue: PortalNewsColumnPage(
                columnId: PortalNewsColumn.news.rawValue,
                totalCount: 1,
                articles: [
                    PortalNewsArticle(id: "demo-n4", columnId: PortalNewsColumn.news.rawValue, title: "我校绿色化学工程重点实验室取得新突破", sourceOrg: "新闻中心", publishTimestampMs: nowMs - 28_800_000, summary: "相关成果发表于国际顶级期刊。", content: "北京化工大学研究团队在绿色催化领域取得重要进展。", publicUrl: "https://i.buct.edu.cn", isNewest: true)
                ]
            )
        ])
    }

    public static func portalLibrarySnapshot() -> PortalLibrarySnapshot {
        PortalLibrarySnapshot(
            totalCount: 2,
            books: [
                PortalBookItem(title: "深入理解计算机系统（原书第3版）", barcode: "B202400182", borrowDate: "2026-05-01", dueDate: "2026-06-15"),
                PortalBookItem(title: "编译原理（第2版）", barcode: "B202400951", borrowDate: "2026-05-10", dueDate: "2026-06-10")
            ]
        )
    }

    public static func theolSnapshot() -> TheolSnapshot {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        return TheolSnapshot(
            homeworks: [
                TheolHomeworkItem(hwtid: "9001", lid: "1001", courseName: "操作系统", title: "实验三：进程调度与同步互斥", deadline: "2026-06-01 23:59", deadlineMillis: nowMs + 2 * 86_400_000, publisher: "王老师", canSubmit: true, status: "未提交"),
                TheolHomeworkItem(hwtid: "9002", lid: "1002", courseName: "编译原理", title: "LL(1) 语法分析器设计报告", deadline: "2026-06-05 23:59", deadlineMillis: nowMs + 5 * 86_400_000, publisher: "张老师", canSubmit: true, status: "未提交"),
                TheolHomeworkItem(hwtid: "9003", lid: "1003", courseName: "计算机网络", title: "TCP 拥塞控制实验", deadline: "2026-05-15 23:59", deadlineMillis: nowMs - 3 * 86_400_000, score: "95", publisher: "李老师", hasResult: true, status: "已完成")
            ],
            tests: [
                TheolTestItem(testId: "7001", lid: "1004", courseName: "软件工程", title: "第 14 周随堂在线测验", startTime: "2026-05-25 08:00", endTime: "2026-05-30 22:00", endTimeMillis: nowMs + 3 * 86_400_000, duration: "45 分钟", allowedAttempts: "1", canStart: true, status: "可进行")
            ],
            failedCourseCount: 0,
            courses: [
                TheolCourseInfo(lid: "1001", courseName: "操作系统", type: "course", url: "https://course.buct.edu.cn/meol/jpk/course/layout/newpage/index.jsp?courseId=1001"),
                TheolCourseInfo(lid: "1002", courseName: "编译原理", type: "course", url: "https://course.buct.edu.cn/meol/jpk/course/layout/newpage/index.jsp?courseId=1002"),
                TheolCourseInfo(lid: "1003", courseName: "计算机网络", type: "course", url: "https://course.buct.edu.cn/meol/jpk/course/layout/newpage/index.jsp?courseId=1003"),
                TheolCourseInfo(lid: "1004", courseName: "软件工程", type: "course", url: "https://course.buct.edu.cn/meol/jpk/course/layout/newpage/index.jsp?courseId=1004")
            ]
        )
    }

    public static func mailSnapshot() -> MailSnapshot {
        MailSnapshot(
            account: MailAccountInfo(email: "demo@buct.edu.cn", displayName: "演示同学", orgName: "北京化工大学"),
            folders: [
                MailFolder(id: MailFolder.inboxId, name: "收件箱", totalCount: 2, unreadCount: 1, isSystem: true),
                MailFolder(id: MailFolder.sentId, name: "已发送", totalCount: 1, unreadCount: 0, isSystem: true),
                MailFolder(id: MailFolder.trashId, name: "已删除", totalCount: 0, unreadCount: 0, isSystem: true)
            ],
            inboxTotal: 2,
            inboxMessages: [
                MailMessageSummary(
                    id: "demo-mail-1",
                    folderId: MailFolder.inboxId,
                    subject: "关于 2026 年春季学期选课与补退选的通知",
                    fromName: "教务处",
                    fromAddress: "jwc@buct.edu.cn",
                    summary: "各位同学：本学期第二轮补退选将于本周五 16:00 截止，请及时核对个人课表...",
                    sentAt: "2026-05-19 09:30",
                    receivedAt: "2026-05-19 09:30",
                    isRead: false,
                    hasAttachments: true,
                    attachments: [MailAttachment(partId: "2", filename: "选课操作指南.pdf", contentType: "application/pdf", sizeBytes: 420_100)]
                ),
                MailMessageSummary(
                    id: "demo-mail-2",
                    folderId: MailFolder.inboxId,
                    subject: "信息中心：校园邮箱空间升级提醒",
                    fromName: "信息中心",
                    fromAddress: "nic@buct.edu.cn",
                    summary: "您的北京化工大学校园邮箱已支持 SSO 免密登录与网易企业邮客户端同步。",
                    sentAt: "2026-05-16 14:15",
                    receivedAt: "2026-05-16 14:15",
                    isRead: true
                )
            ]
        )
    }

    public static func electricitySnapshot() -> ElectricitySnapshot {
        let nowSec = Int64(Date().timeIntervalSince1970)
        let target1 = ElectricityRoomTarget(
            schoolId: "demo-east",
            campusName: "东校区",
            buildingId: "b1",
            buildingName: "1号楼",
            floorId: "f3",
            floorName: "3层",
            roomId: "301-light",
            roomName: "301 照明",
            meterType: "照明"
        )
        let target2 = ElectricityRoomTarget(
            schoolId: "demo-east",
            campusName: "东校区",
            buildingId: "b1",
            buildingName: "1号楼",
            floorId: "f3",
            floorName: "3层",
            roomId: "301-ac",
            roomName: "301 空调",
            meterType: "空调"
        )
        return ElectricitySnapshot(
            targets: [target1, target2],
            readings: [
                ElectricityReading(
                    schoolId: target1.schoolId,
                    roomId: target1.roomId,
                    campusName: target1.campusName,
                    buildingName: target1.buildingName,
                    floorName: target1.floorName,
                    roomName: target1.roomName,
                    meterType: target1.meterType,
                    balanceText: "48.60 元",
                    balanceValue: 48.60,
                    unit: "元",
                    accountStatus: "1",
                    queriedAt: nowSec,
                    fromCache: false
                ),
                ElectricityReading(
                    schoolId: target2.schoolId,
                    roomId: target2.roomId,
                    campusName: target2.campusName,
                    buildingName: target2.buildingName,
                    floorName: target2.floorName,
                    roomName: target2.roomName,
                    meterType: target2.meterType,
                    balanceText: "15.20 元",
                    balanceValue: 15.20,
                    unit: "元",
                    accountStatus: "1",
                    queriedAt: nowSec,
                    fromCache: true
                )
            ],
            lowBalanceThreshold: 20.0
        )
    }

    public static func campusNetSnapshot() -> CampusNetSnapshot {
        CampusNetSnapshot(
            username: "2024000000",
            isOnline: true,
            accountStatus: "正常",
            onlineIp: "10.21.18.42",
            productsName: "学生20元套餐",
            billingName: "20元包40G",
            sumBytes: 18_420_000_000,
            allBytes: 40_000_000_000,
            sumSeconds: 185_400,
            trafficText: "18.42 GB",
            durationText: "51 小时 30 分钟",
            userBalance: 20.0,
            walletBalance: 65.5,
            userCharge: 20.0,
            onlineDeviceTotal: 2,
            onlineDevices: [
                CampusNetOnlineDevice(ip: "10.21.18.42", loginTime: "2026-05-19 08:12:05", billingName: "20元包40G"),
                CampusNetOnlineDevice(ip: "10.21.34.119", loginTime: "2026-05-18 21:04:19", billingName: "20元包40G")
            ],
            payRecords: [
                CampusNetPayRecord(amountText: "50.00 元", payType: "微信支付", payTime: "2026-05-01 10:20:00"),
                CampusNetPayRecord(amountText: "30.00 元", payType: "支付宝", payTime: "2026-03-02 18:45:12")
            ],
            checkoutRecords: [
                CampusNetCheckoutRecord(feeText: "20.00 元", productName: "学生20元套餐", trafficText: "34.18 GB", durationText: "142 小时", checkoutTime: "2026-04-30 23:59:59"),
                CampusNetCheckoutRecord(feeText: "20.00 元", productName: "学生20元套餐", trafficText: "29.65 GB", durationText: "128 小时", checkoutTime: "2026-03-31 23:59:59")
            ]
        )
    }

    public static func cardSnapshot() -> CardSnapshot {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        return CardSnapshot(
            account: CardAccountInfo(
                idSerial: "2024000000",
                userName: "演示同学",
                cardNo: "10086001",
                balanceFen: 12850,
                accStatus: "1",
                accTypeName: "校园主卡",
                createDate: "2024-09-01"
            ),
            transactions: [
                CardTransaction(id: "demo-tx-1", txCode: "2100", summary: "东区二食堂风味窗口", merchantName: "东区二食堂", amountFen: 1650, balanceAfterFen: 12850, timestampMillis: nowMs - 3_600_000, timeText: "2026-05-19 12:10", isExpense: true),
                CardTransaction(id: "demo-tx-2", txCode: "2100", summary: "紫竹超市消费", merchantName: "校内超市", amountFen: 890, balanceAfterFen: 14500, timestampMillis: nowMs - 18_000_000, timeText: "2026-05-19 08:15", isExpense: true),
                CardTransaction(id: "demo-tx-3", txCode: "2100", summary: "宿舍淋浴水控", merchantName: "水控系统", amountFen: 230, balanceAfterFen: 15390, timestampMillis: nowMs - 86_400_000, timeText: "2026-05-18 21:40", isExpense: true),
                CardTransaction(id: "demo-tx-4", txCode: "2241", summary: "发放补助", merchantName: "学校补助", amountFen: 10000, balanceAfterFen: 15620, timestampMillis: nowMs - 172_800_000, timeText: "2026-05-17 09:00", isExpense: false)
            ],
            queryStartDate: "2026-05-01",
            queryEndDate: "2026-05-19",
            totalCount: 4,
            hasMore: false
        )
    }

    public static func scsSnapshot() -> ScsSnapshot {
        ScsSnapshot(
            studentName: "演示同学",
            studentId: "2024000000",
            collegeName: "信息科学与技术学院",
            className: "计科2401",
            gradeName: "2024级",
            currentWindow: ScsEvalWindow(yearId: 2025, termId: 2, yearName: "2025-2026", termName: "第二学期", isOpen: true, selfStartTime: "2026-05-01", selfEndTime: "2026-06-30"),
            dimensions: [
                ScsDimensionDef(id: 1, name: "德育", totalScore: 180),
                ScsDimensionDef(id: 2, name: "智育", totalScore: 120),
                ScsDimensionDef(id: 3, name: "体育", totalScore: 100),
                ScsDimensionDef(id: 4, name: "美育", totalScore: 100),
                ScsDimensionDef(id: 5, name: "劳育", totalScore: 100)
            ],
            terms: [
                ScsTermScore(
                    yearId: 2025, termId: 0, yearName: "2025-2026", termName: "全年", isFullYear: true,
                    totalScore: 462.5, moral: 145, academic: 102, physical: 78, aesthetics: 68.5, labor: 69,
                    details: [
                        ScsCategoryDetail(typeId: 1, typeName: "德育", score: 145, maxScore: 180, items: [
                            ScsEvalItem(id: "d1", title: "青年大学习与主题团日", isBasic: true, score: 85, maxScore: 100),
                            ScsEvalItem(id: "d2", title: "校级志愿服务时长", isBasic: false, score: 60, maxScore: 80)
                        ]),
                        ScsCategoryDetail(typeId: 5, typeName: "劳育", score: 69, maxScore: 100, items: [
                            ScsEvalItem(id: "l1", title: "校园劳动实践", isBasic: true, score: 69, maxScore: 100, laborHours: 16)
                        ])
                    ]
                )
            ],
            activities: [
                ScsActivityItem(id: "a1", title: "AI 前沿技术学术沙龙", categoryName: "智育", startTime: "2026-05-22 14:00", location: "科技大厦报告厅", scoreText: "+2.0", status: "报名中"),
                ScsActivityItem(id: "a2", title: "校园环保志愿清理行动", categoryName: "劳育", startTime: "2026-05-24 09:00", location: "东校区操场集合", scoreText: "+3.0", status: "已报名")
            ]
        )
    }

    public static func sjcxSnapshot() -> SjcxSnapshot {
        SjcxSnapshot(
            yearterm: "2025-2026-2",
            currentWeek: 13,
            reports: [
                SjcxReportItem(id: "r1", reportId: "101", groupId: "1", courseName: "计算机组成原理实验", expName: "单周期 CPU 设计", docName: "cpu_report.pdf", state: 2, stateText: "已批阅", scoreText: "94", submitTime: "2026-05-12 20:15"),
                SjcxReportItem(id: "r2", reportId: "102", groupId: "1", courseName: "操作系统实验", expName: "内存分页管理", state: 0, stateText: "待提交")
            ],
            schedules: [
                SjcxScheduleItem(id: "s1", courseName: "操作系统实验", expName: "内存分页管理", week: 13, weekDay: 4, jcText: "6-7节", roomName: "电教楼 402", teacherName: "王老师")
            ],
            scores: [
                SjcxScoreItem(id: "sc1", courseName: "计算机组成原理实验", expName: "单周期 CPU 设计", scoreText: "94", detailScores: ["预习 20", "操作 36", "报告 38"])
            ],
            openLectures: [
                SjcxLectureItem(id: "l1", projectTimeId: "pt1", title: "大学生创新创业项目申报实务", speaker: "教务处创新中心", location: "阶梯教室 201", startTime: "2026-05-25 18:30", credit: 0.5, capacityText: "85/120", statusText: "可报名", isRegistered: false)
            ],
            myLectures: [
                SjcxLectureItem(id: "l2", projectTimeId: "pt2", registrationId: "reg2", title: "化工与人工智能交叉前沿讲座", speaker: "李教授", location: "会议中心", startTime: "2026-05-10 15:00", credit: 0.5, statusText: "已签到", isRegistered: true, hasExperience: true)
            ],
            creditRecords: [
                SjcxCreditRecord(id: "c1", title: "全国大学生程序设计竞赛校赛二等奖", category: "学科竞赛", credit: 1.5, grantedAt: "2026-04-18"),
                SjcxCreditRecord(id: "c2", title: "化工与人工智能交叉前沿讲座", category: "创新讲座", credit: 0.5, grantedAt: "2026-05-12")
            ],
            totalCredit: 2.0,
            noSignCount: 0
        )
    }

    public static func tyglSnapshot() -> TyglSnapshot {
        TyglSnapshot(
            profile: TyglStudentProfile(name: "演示同学", studentId: "2024000000", gender: "男", grade: "大二", className: "计科2401", college: "信息学院", testRequired: "是"),
            fitnessRecords: [
                TyglFitnessRecord(
                    year: "2025-2026",
                    updatedAt: "2025-11-18",
                    totalScore: "83.6",
                    level: "良好",
                    heightCm: "176",
                    weightKg: "66",
                    bonusScore: "2.0",
                    bonusReason: "1000米加分",
                    items: [
                        TyglFitnessItem(name: "肺活量", rawValue: "4520 ml", score: "84", grade: "良好"),
                        TyglFitnessItem(name: "50米跑", rawValue: "7.2 s", score: "78", grade: "及格"),
                        TyglFitnessItem(name: "坐位体前屈", rawValue: "16.5 cm", score: "78", grade: "及格"),
                        TyglFitnessItem(name: "立定跳远", rawValue: "248 cm", score: "80", grade: "良好"),
                        TyglFitnessItem(name: "引体向上", rawValue: "14 个", score: "76", grade: "及格"),
                        TyglFitnessItem(name: "1000米跑", rawValue: "3'35\"", score: "88", grade: "良好")
                    ]
                )
            ],
            runPlan: TyglRunPlan(term: "2025-2026 春季", startTime: "2026-03-09", endTime: "2026-06-12", targetText: "有效打卡 24 次 / 48 km", summary: "已完成 18 次"),
            exerciseColumns: ["阳光长跑", "早操"],
            exerciseTerms: [
                TyglExerciseTerm(year: "2025-2026", term: "春", values: ["阳光长跑": "18 次", "早操": "10 次"])
            ],
            peCourses: [
                TyglPeCourseScore(year: "2025-2026", term: "秋", courseName: "羽毛球（初级）", teacher: "刘老师", score: "89", note: "正常")
            ],
            examInfo: TyglExamInfo(currentTerm: "2025-2026 春", peClass: "羽毛球提高班", remainingAttempts: "2 次", highestScore: "92", notice: "期末理论考试已开放，请在截止前完成作答。")
        )
    }

    public static func courseSelectionSnapshot() -> CourseSelectionSnapshot {
        let c1 = CourseSelectionCourse(
            courseId: "CS301", classId: "JXB-301-1", doJxbId: "DEMO_DO_301_1",
            name: "人工智能导论", teacher: "赵教授", teachingClassName: "人工智能导论-01",
            timeText: "周二 第6-7节", location: "东校区 教阶201", credits: "2.0",
            capacity: 120, enrolled: 98, isSelected: false, kklxdm: "10", xkkzId: "DEMO_XKKZ_10"
        )
        let c2 = CourseSelectionCourse(
            courseId: "GE108", classId: "JXB-108-1", doJxbId: "DEMO_DO_108_1",
            name: "西方音乐赏析", teacher: "陈老师", teachingClassName: "西方音乐赏析-01",
            timeText: "周四 第10-11节", location: "东校区 阶梯104", credits: "1.5",
            capacity: 80, enrolled: 80, isSelected: false, kklxdm: "10", xkkzId: "DEMO_XKKZ_10"
        )
        let sel = CourseSelectionCourse(
            courseId: "PE202", classId: "JXB-202-1", doJxbId: "DEMO_DO_202_1",
            name: "羽毛球（提高）", teacher: "刘老师", teachingClassName: "羽毛球-02",
            timeText: "周三 第3-4节", location: "体育馆", credits: "1.0",
            capacity: 40, enrolled: 36, isSelected: true, kklxdm: "05", xkkzId: "DEMO_XKKZ_05"
        )
        return CourseSelectionSnapshot(
            isOpen: true,
            statusMessage: "演示模式 · 选课开放中",
            xkxnm: "2025",
            xkxqm: "12",
            tabs: [
                CourseSelectionTabParam(kklxdm: "10", xkkzId: "DEMO_XKKZ_10"),
                CourseSelectionTabParam(kklxdm: "05", xkkzId: "DEMO_XKKZ_05")
            ],
            availableCourses: [c1, c2, sel],
            selectedCourses: [sel]
        )
    }
}
