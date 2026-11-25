import BuctModel
import SwiftUI

private enum TyglTab: String, CaseIterable {
    case fitness = "体测成绩"
    case exercise = "阳光体育"
    case simulator = "国标算分"
}

struct PhysicalFitnessView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var tab: TyglTab = .fitness
    @State private var selectedYear: String = ""
    @State private var simInput = FitnessSimInput()
    @State private var didAutoSync = false

    private var snapshot: TyglSnapshot? {
        environment.tyglSlice.data
    }

    private var currentRecord: TyglFitnessRecord? {
        guard let list = snapshot?.fitnessRecords, !list.isEmpty else { return nil }
        return list.first(where: { $0.year == selectedYear }) ?? list.first
    }

    var body: some View {
        ZStack {
            BuctBackdropBackground()

            VStack(spacing: 10) {
                Picker("体测", selection: $tab) {
                    ForEach(TyglTab.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        if tab == .simulator {
                            simulatorContent
                        } else if environment.currentProfile == nil {
                            VStack(spacing: 12) {
                                Text("请先登录统一身份认证").font(.headline)
                                Button("去登录") { environment.showLoginSheet = true }
                                    .buttonStyle(.glassProminent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(24)
                            .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                        } else {
                            if let err = environment.tyglSlice.lastError, !err.isEmpty {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .buctGlassCard(cornerRadius: 16, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                            }

                            if let snap = snapshot {
                                if tab == .fitness {
                                    fitnessContent(snap)
                                } else {
                                    exerciseContent(snap)
                                }
                            } else {
                                Text(environment.isSyncingTygl ? "正在同步体测与体育成绩..." : "暂无数据，下拉或点击右上角刷新")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(28)
                                    .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .refreshable {
                    if environment.currentProfile != nil {
                        await environment.refreshTygl(userInitiated: true)
                    }
                }
            }
            .padding(.top, 8)
        }
        .navigationTitle("体测与体育")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if environment.currentProfile != nil {
                    Button {
                        Task { await environment.refreshTygl(userInitiated: true) }
                    } label: {
                        if environment.isSyncingTygl {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .onAppear {
            environment.trackVisit(path: "/module/physicalFitness", title: "体测与体育")
            if !didAutoSync, environment.currentProfile != nil,
               environment.tyglSlice.provenance.refreshState == .never {
                didAutoSync = true
                Task { await environment.refreshTygl(userInitiated: false) }
            }
        }
    }

    @ViewBuilder
    private func fitnessContent(_ snap: TyglSnapshot) -> some View {
        if let rec = currentRecord {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(rec.year) 体测总评").font(.headline)
                        if !rec.heightCm.isEmpty || !rec.weightKg.isEmpty {
                            Text("身高 \(rec.heightCm) cm · 体重 \(rec.weightKg) kg")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if snap.fitnessRecords.count > 1 {
                        Menu {
                            ForEach(snap.fitnessRecords) { r in
                                Button(r.year) { selectedYear = r.year }
                            }
                        } label: {
                            Label(rec.year, systemImage: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.glass)
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(rec.totalScore.isEmpty ? "--" : rec.totalScore)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    if !rec.level.isEmpty {
                        Text(rec.level)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                    }
                    Spacer()
                    if !rec.bonusScore.isEmpty {
                        Text("加分 +\(rec.bonusScore)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(16)
            .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)

            ForEach(rec.items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.subheadline.weight(.semibold))
                        Text(item.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(item.score.isEmpty ? "--" : "\(item.score) 分")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                        if !item.grade.isEmpty {
                            Text(item.grade).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
                .buctGlassCard(cornerRadius: 16, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
            }
        } else {
            Text("暂无体测成绩记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(24)
                .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
        }
    }

    @ViewBuilder
    private func exerciseContent(_ snap: TyglSnapshot) -> some View {
        if let plan = snap.runPlan {
            VStack(alignment: .leading, spacing: 6) {
                Text(plan.term.isEmpty ? "阳光长跑计划" : plan.term).font(.subheadline.weight(.semibold))
                if !plan.targetText.isEmpty { Text(plan.targetText).font(.caption).foregroundStyle(.secondary) }
                if !plan.summary.isEmpty { Text(plan.summary).font(.caption).foregroundStyle(Color.accentColor) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
        }

        ForEach(snap.exerciseTerms) { term in
            VStack(alignment: .leading, spacing: 6) {
                Text("\(term.year) \(term.term)").font(.subheadline.weight(.semibold))
                ForEach(term.values.keys.sorted(), id: \.self) { k in
                    HStack {
                        Text(k).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(term.values[k] ?? "").font(.caption.weight(.medium))
                    }
                }
            }
            .padding(14)
            .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
        }

        if !snap.peCourses.isEmpty {
            ForEach(snap.peCourses) { pe in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pe.courseName).font(.subheadline.weight(.semibold))
                        Text("\(pe.year) \(pe.term) · \(pe.teacher)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(pe.score).font(.headline.monospacedDigit()).foregroundStyle(Color.accentColor)
                }
                .padding(14)
                .buctGlassCard(cornerRadius: 16, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
            }
        }

        if let exam = snap.examInfo {
            VStack(alignment: .leading, spacing: 6) {
                Text("体育理论考试").font(.subheadline.weight(.semibold))
                if !exam.peClass.isEmpty { Text("体育班：\(exam.peClass)").font(.caption).foregroundStyle(.secondary) }
                if !exam.highestScore.isEmpty { Text("最高成绩：\(exam.highestScore)").font(.caption).foregroundStyle(.secondary) }
                if !exam.remainingAttempts.isEmpty { Text("剩余次数：\(exam.remainingAttempts)").font(.caption).foregroundStyle(.secondary) }
                if !exam.notice.isEmpty { Text(exam.notice).font(.caption2).foregroundStyle(.tertiary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
        }
    }

    private var simulatorContent: some View {
        let res = NationalFitnessScorer.evaluate(simInput)
        return VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("2014 国家学生体质健康标准 · 实时试算")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%.1f", res.finalTotal))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text(res.level)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                    Spacer()
                    Text(String(format: "BMI %.1f · 加分 +%.0f", res.bmi, res.bonusScore))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)

            VStack(spacing: 12) {
                Picker("性别", selection: $simInput.gender) {
                    ForEach(FitnessGender.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("年级", selection: $simInput.gradeGroup) {
                    ForEach(FitnessGradeGroup.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                simSlider("身高 (cm)", value: $simInput.heightCm, range: 145...205, step: 1, score: res.bmiScore)
                simSlider("体重 (kg)", value: $simInput.weightKg, range: 35...120, step: 1, score: res.bmiScore)
                simSlider("肺活量 (ml)", value: $simInput.lungCapacityMl, range: 1500...6500, step: 100, score: res.lungScore)
                simSlider("50米跑 (s)", value: $simInput.run50mSec, range: 6.2...11.5, step: 0.1, score: res.run50mScore)
                simSlider("坐位体前屈 (cm)", value: $simInput.sitAndReachCm, range: -5...30, step: 0.5, score: res.sitAndReachScore)
                simSlider("立定跳远 (cm)", value: $simInput.standingJumpCm, range: 120...290, step: 1, score: res.standingJumpScore)
                simSlider(simInput.gender == .male ? "引体向上 (个)" : "仰卧起坐 (个)", value: $simInput.strengthCount, range: 0...70, step: 1, score: res.strengthScore)
                simSlider(simInput.gender == .male ? "1000米跑 (秒)" : "800米跑 (秒)", value: $simInput.enduranceSec, range: 170...360, step: 1, score: res.enduranceScore)
            }
            .padding(16)
            .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
        }
    }

    private func simSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, score: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption.weight(.medium))
                Spacer()
                Text(String(format: "%.1f（%.0f 分）", value.wrappedValue, score))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
