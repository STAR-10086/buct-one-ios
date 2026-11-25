import BuctModel
import SwiftUI

private enum SjcxTab: String, CaseIterable {
    case reports = "实验报告"
    case schedule = "实验课表"
    case lectures = "创新讲座"
    case credits = "创新学分"
}

struct PracticeTeachingView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var tab: SjcxTab = .reports
    @State private var actionMsg = ""
    @State private var experienceTarget: SjcxLectureItem?
    @State private var didAutoSync = false

    private var snapshot: SjcxSnapshot? {
        environment.sjcxSlice.data
    }

    var body: some View {
        ZStack {
            BuctBackdropBackground()

            if environment.currentProfile == nil {
                VStack(spacing: 12) {
                    Text("请先登录统一身份认证").font(.headline)
                    Button("去登录") { environment.showLoginSheet = true }
                        .buttonStyle(.glassProminent)
                }
            } else {
                VStack(spacing: 10) {
                    Picker("实践教学", selection: $tab) {
                        ForEach(SjcxTab.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    if !actionMsg.isEmpty {
                        Text(actionMsg)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 16)
                    }

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if let err = environment.sjcxSlice.lastError, !err.isEmpty {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .buctGlassCard(cornerRadius: 16, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                            }

                            if let snap = snapshot {
                                switch tab {
                                case .reports:
                                    reportsContent(snap.reports)
                                case .schedule:
                                    scheduleAndScoresContent(snap)
                                case .lectures:
                                    lecturesContent(snap)
                                case .credits:
                                    creditsContent(snap)
                                }
                            } else {
                                emptyCard(environment.isSyncingSjcx ? "正在同步实践教学数据..." : "暂无数据，下拉或点击右上角刷新")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                    .refreshable {
                        await environment.refreshSjcx(userInitiated: true)
                    }
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("实践教学")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if environment.currentProfile != nil {
                    Button {
                        Task { await environment.refreshSjcx(userInitiated: true) }
                    } label: {
                        if environment.isSyncingSjcx {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .sheet(item: $experienceTarget) { lec in
            LectureExperienceSheet(lecture: lec) { text in
                Task { await submitExperience(lec, text: text) }
            }
        }
        .onAppear {
            environment.trackVisit(path: "/module/practiceTeaching", title: "实践教学")
            if !didAutoSync, environment.currentProfile != nil,
               environment.sjcxSlice.provenance.refreshState == .never {
                didAutoSync = true
                Task { await environment.refreshSjcx(userInitiated: false) }
            }
        }
    }

    @ViewBuilder
    private func reportsContent(_ reports: [SjcxReportItem]) -> some View {
        if reports.isEmpty {
            emptyCard("暂无实验报告任务")
        } else {
            ForEach(reports) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(item.courseName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                        Text(item.stateText)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(item.isSubmitted ? Color.green : Color.orange)
                    }
                    Text(item.expName)
                        .font(.subheadline.weight(.semibold))
                    if !item.docName.isEmpty {
                        Label(item.docName, systemImage: "doc.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        if !item.scoreText.isEmpty {
                            Text("成绩：\(item.scoreText)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        if !item.submitTime.isEmpty {
                            Text(item.submitTime).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    if !item.opinion.isEmpty {
                        Text("评语：\(item.opinion)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
            }
        }
    }

    @ViewBuilder
    private func scheduleAndScoresContent(_ snap: SjcxSnapshot) -> some View {
        if !snap.schedules.isEmpty {
            ForEach(snap.schedules) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.expName).font(.subheadline.weight(.semibold))
                        Text("\(item.courseName) · 第\(item.week)周 周\(item.weekDay) \(item.jcText)")
                            .font(.caption2).foregroundStyle(.secondary)
                        let loc = [item.roomName, item.teacherName].filter { !$0.isEmpty }.joined(separator: " · ")
                        if !loc.isEmpty { Text(loc).font(.caption2).foregroundStyle(.tertiary) }
                    }
                    Spacer()
                }
                .padding(14)
                .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
            }
        }

        if !snap.scores.isEmpty {
            ForEach(snap.scores) { sc in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sc.expName).font(.subheadline.weight(.medium))
                        Text(sc.courseName).font(.caption2).foregroundStyle(.secondary)
                        if !sc.detailScores.isEmpty {
                            Text(sc.detailScores.joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Text(sc.scoreText)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                }
                .padding(14)
                .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
            }
        }

        if snap.schedules.isEmpty && snap.scores.isEmpty {
            emptyCard("暂无实验课表与成绩")
        }
    }

    @ViewBuilder
    private func lecturesContent(_ snap: SjcxSnapshot) -> some View {
        if !snap.myLectures.isEmpty {
            Text("我的报名（\(snap.myLectures.count)）")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(snap.myLectures) { lec in
                lectureCard(lec)
            }
        }

        Text("可报名讲座（\(snap.openLectures.count)）")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        if snap.openLectures.isEmpty {
            emptyCard("当前暂无可报名的创新讲座")
        } else {
            ForEach(snap.openLectures) { lec in
                lectureCard(lec)
            }
        }
    }

    private func lectureCard(_ lec: SjcxLectureItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(lec.title).font(.subheadline.weight(.semibold))
                Spacer()
                if lec.credit > 0 {
                    Text(String(format: "+%.1f 学分", lec.credit))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            let meta = [lec.speaker, lec.startTime, lec.location, lec.capacityText].filter { !$0.isEmpty }.joined(separator: " · ")
            if !meta.isEmpty {
                Text(meta).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if lec.isRegistered {
                    Button("写心得") { experienceTarget = lec }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    if !lec.registrationId.isEmpty {
                        Button("取消报名", role: .destructive) {
                            Task { await cancelLecture(lec) }
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                } else if !lec.projectTimeId.isEmpty {
                    Button("立即报名") {
                        Task { await registerLecture(lec) }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                }
                Spacer()
                if !lec.statusText.isEmpty {
                    Text(lec.statusText).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    @ViewBuilder
    private func creditsContent(_ snap: SjcxSnapshot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("已获创新学分").font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%.2f", snap.totalCredit))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
            }
            Spacer()
            if snap.noSignCount > 0 {
                Label("未签到 \(snap.noSignCount) 次", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)

        if snap.creditRecords.isEmpty {
            emptyCard("暂无创新学分记录")
        } else {
            ForEach(snap.creditRecords) { rec in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rec.title).font(.subheadline.weight(.medium))
                        Text([rec.category, rec.grantedAt].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "+%.1f", rec.credit))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                }
                .padding(14)
                .buctGlassCard(cornerRadius: 16, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
            }
        }
    }

    private func registerLecture(_ lec: SjcxLectureItem) async {
        guard let profile = environment.currentProfile else { return }
        do {
            try await environment.campusSync.registerSjcxLecture(profile: profile, projectTimeId: lec.projectTimeId)
            actionMsg = "已报名：\(lec.title)"
            await environment.refreshSjcx(userInitiated: true)
        } catch {
            actionMsg = error.localizedDescription
        }
    }

    private func cancelLecture(_ lec: SjcxLectureItem) async {
        guard let profile = environment.currentProfile else { return }
        do {
            try await environment.campusSync.cancelSjcxLecture(profile: profile, registrationId: lec.registrationId)
            actionMsg = "已取消报名"
            await environment.refreshSjcx(userInitiated: true)
        } catch {
            actionMsg = error.localizedDescription
        }
    }

    private func submitExperience(_ lec: SjcxLectureItem, text: String) async {
        guard let profile = environment.currentProfile else { return }
        do {
            try await environment.campusSync.submitSjcxExperience(profile: profile, registrationId: lec.registrationId, experience: text)
            actionMsg = "讲座心得已提交"
            await environment.refreshSjcx(userInitiated: true)
        } catch {
            actionMsg = error.localizedDescription
        }
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(24)
            .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }
}

private struct LectureExperienceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let lecture: SjcxLectureItem
    let onSubmit: (String) -> Void
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(lecture.title) {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                }
            }
            .navigationTitle("提交讲座心得")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("提交") {
                        onSubmit(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
