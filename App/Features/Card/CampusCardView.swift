import BuctModel
import SwiftUI

private enum CardRangeOption: String, CaseIterable {
    case days7 = "近 7 天"
    case thisMonth = "本月"
    case days30 = "近 30 天"

    func dateRange() -> (start: String, end: String) {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        fmt.dateFormat = "yyyy-MM-dd"
        let end = fmt.string(from: now)
        let startDate: Date
        switch self {
        case .days7:
            startDate = cal.date(byAdding: .day, value: -6, to: now) ?? now
        case .thisMonth:
            let comps = cal.dateComponents([.year, .month], from: now)
            startDate = cal.date(from: comps) ?? now
        case .days30:
            startDate = cal.date(byAdding: .day, value: -29, to: now) ?? now
        }
        return (fmt.string(from: startDate), end)
    }
}

struct CampusCardView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var range: CardRangeOption = .days7
    @State private var hideAmount = false
    @State private var showLoginSheet = false
    @State private var extraTransactions: [CardTransaction] = []
    @State private var currentPage = 0
    @State private var hasMorePages = false
    @State private var isLoadingMore = false

    private var snapshot: CardSnapshot? {
        environment.cardSlice.data
    }

    private var allTransactions: [CardTransaction] {
        var list = snapshot?.transactions ?? []
        let seen = Set(list.map(\.id))
        list.append(contentsOf: extraTransactions.filter { !seen.contains($0.id) })
        return list
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
            } else if !environment.hasCardCredential && snapshot == nil {
                VStack(spacing: 14) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(Color.accentColor)
                    Text("校园卡需要独立查询密码登录")
                        .font(.headline)
                    Text("校园一卡通（ecard.buct.edu.cn）独立于统一身份认证，密码将加密保存在本机独立 Keychain 中；校外自动走 WebVPN。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("登录校园卡") {
                        showLoginSheet = true
                    }
                    .buttonStyle(.glassProminent)
                }
                .padding(24)
                .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                .padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if let err = environment.cardSlice.lastError, !err.isEmpty {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .buctGlassCard(cornerRadius: 16, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                        }

                        if let snap = snapshot {
                            balanceCard(snap.account)
                            insightsCard(transactions: allTransactions)

                            Picker("区间", selection: $range) {
                                ForEach(CardRangeOption.allCases, id: \.self) { opt in
                                    Text(opt.rawValue).tag(opt)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: range) { _, newRange in
                                Task { await reloadRange(newRange) }
                            }

                            if allTransactions.isEmpty {
                                Text("所选区间暂无交易记录")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(24)
                                    .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                            } else {
                                ForEach(allTransactions) { tx in
                                    transactionRow(tx)
                                }
                                if hasMorePages || snap.hasMore {
                                    Button {
                                        Task { await loadMore() }
                                    } label: {
                                        if isLoadingMore {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Text("加载更多流水")
                                                .font(.caption.weight(.semibold))
                                        }
                                    }
                                    .buttonStyle(.glass)
                                    .padding(.vertical, 6)
                                }
                            }
                        }

                        if environment.currentProfile?.isDemoMode != true && environment.hasCardCredential {
                            Button("退出校园卡并清除查询密码", role: .destructive) {
                                Task { await environment.logoutCard() }
                            }
                            .font(.caption)
                            .padding(.top, 8)
                        }
                    }
                    .padding(16)
                }
                .refreshable {
                    await reloadRange(range)
                }
            }
        }
        .navigationTitle("校园一卡通")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if environment.currentProfile != nil {
                    Button {
                        showLoginSheet = true
                    } label: {
                        Image(systemName: "key.fill")
                    }
                    Button {
                        Task { await reloadRange(range) }
                    } label: {
                        if environment.isSyncingCard {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(!environment.hasCardCredential)
                }
            }
        }
        .sheet(isPresented: $showLoginSheet) {
            CardLoginSheet(range: range)
        }
        .onAppear {
            environment.trackVisit(path: "/module/campusCard", title: "校园卡")
            if let snap = snapshot {
                hasMorePages = snap.hasMore
            }
        }
    }

    private func balanceCard(_ account: CardAccountInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.accTypeName.isEmpty ? "校园一卡通" : account.accTypeName)
                        .font(.subheadline.weight(.semibold))
                    Text("\(account.userName) · \(account.maskedIdSerial)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    hideAmount.toggle()
                } label: {
                    Image(systemName: hideAmount ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(hideAmount ? "¥ ****" : "¥ \(account.balanceYuanText)")
                .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())

            HStack {
                Text(account.accStatus == "1" ? "状态：正常" : "状态码：\(account.accStatus)")
                    .font(.caption2)
                    .foregroundStyle(account.accStatus == "1" ? Color.green : Color.orange)
                Spacer()
                if !account.cardNo.isEmpty {
                    Text("卡号 \(account.cardNo)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(16)
        .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private func insightsCard(transactions: [CardTransaction]) -> some View {
        let expenses = transactions.filter(\.isExpense)
        let totalFen = expenses.reduce(Int64(0)) { $0 + $1.amountFen }
        let grouped = Dictionary(grouping: expenses, by: \.category)
        let sortedCats = CardSpendingCategory.allCases
            .map { cat -> (cat: CardSpendingCategory, fen: Int64) in
                (cat, (grouped[cat] ?? []).reduce(Int64(0)) { $0 + $1.amountFen })
            }
            .filter { $0.fen > 0 }
            .sorted { $0.fen > $1.fen }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("消费洞察")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(hideAmount ? "支出 ****" : "共 \(expenses.count) 笔 · ¥\(CardMoneyFormatter.formatFenToYuan(totalFen))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if sortedCats.isEmpty {
                Text("当前区间暂无消费统计")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedCats, id: \.cat) { entry in
                    let ratio = totalFen > 0 ? Double(entry.fen) / Double(totalFen) : 0
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.cat.rawValue).font(.caption)
                            Spacer()
                            Text(hideAmount ? "****" : "¥\(CardMoneyFormatter.formatFenToYuan(entry.fen)) (\(Int(ratio * 100))%)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: ratio)
                            .tint(Color.accentColor)
                    }
                }
            }
        }
        .padding(16)
        .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private func transactionRow(_ tx: CardTransaction) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tx.summary)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("\(tx.timeText) · \(tx.category.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(hideAmount ? "****" : tx.signedAmountText)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(tx.isExpense ? Color.primary : Color.green)
                if tx.balanceAfterFen > 0 {
                    Text(hideAmount ? "余 ****" : "余 ¥\(CardMoneyFormatter.formatFenToYuan(tx.balanceAfterFen))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .buctGlassCard(cornerRadius: 16, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private func reloadRange(_ opt: CardRangeOption) async {
        let r = opt.dateRange()
        extraTransactions = []
        currentPage = 0
        await environment.refreshCard(startDate: r.start, endDate: r.end)
        hasMorePages = environment.cardSlice.data?.hasMore ?? false
    }

    private func loadMore() async {
        guard let profile = environment.currentProfile, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let r = range.dateRange()
        let nextPage = currentPage + 1
        if let res = try? await environment.campusSync.loadMoreCardTransactions(
            profile: profile,
            startDate: r.start,
            endDate: r.end,
            pageNumber: nextPage
        ) {
            currentPage = nextPage
            extraTransactions.append(contentsOf: res.rows)
            hasMorePages = (allTransactions.count < res.total) && !res.rows.isEmpty
        }
    }
}

private struct CardLoginSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let range: CardRangeOption
    @State private var idSerial = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMsg = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("校园一卡通独立认证") {
                    TextField("学号", text: $idSerial)
                        .keyboardType(.asciiCapable)
                    SecureField("校园卡查询密码（6 位数字）", text: $password)
                }
                if !errorMsg.isEmpty {
                    Section {
                        Text(errorMsg).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("登录校园卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSubmitting ? "登录中..." : "登录") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || idSerial.isEmpty || password.isEmpty)
                }
            }
            .onAppear {
                if idSerial.isEmpty {
                    idSerial = environment.currentProfile?.studentId ?? ""
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMsg = ""
        defer { isSubmitting = false }
        let r = range.dateRange()
        do {
            try await environment.loginAndSyncCard(
                idSerial: idSerial.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                startDate: r.start,
                endDate: r.end
            )
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
