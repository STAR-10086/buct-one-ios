import BuctModel
import SwiftUI

struct ElectricityView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var showRoomPicker = false
    @State private var showThresholdSheet = false
    @State private var catalog: ElectricityRoomCatalog?
    @State private var catalogError = ""

    private var snapshot: ElectricitySnapshot {
        environment.electricitySlice.data ?? ElectricitySnapshot()
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
            } else if !environment.electricityConsentGranted && environment.currentProfile?.isDemoMode != true {
                consentGateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if let err = environment.electricitySlice.lastError, !err.isEmpty {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .buctGlassCard(cornerRadius: 16, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                        }

                        if snapshot.targets.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "bolt.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.orange)
                                Text("尚未绑定宿舍房间")
                                    .font(.headline)
                                Text("支持东/西/昌平三校区离线房间目录，可一次绑定照明 + 空调双表。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Button("选择宿舍") {
                                    showRoomPicker = true
                                }
                                .buttonStyle(.glassProminent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(24)
                            .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                        } else {
                            ForEach(snapshot.targets) { target in
                                let reading = snapshot.readings.first(where: { $0.id == target.id })
                                electricityCard(target: target, reading: reading)
                            }

                            HStack(spacing: 10) {
                                Button {
                                    showRoomPicker = true
                                } label: {
                                    Label("更换宿舍", systemImage: "building.2")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.glass)

                                Button {
                                    showThresholdSheet = true
                                } label: {
                                    Label("预警 ¥\(Int(snapshot.lowBalanceThreshold))", systemImage: "bell.badge")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.glass)
                            }
                        }

                        if environment.currentProfile?.isDemoMode != true {
                            Button("撤回电费查询隐私授权并清除缓存", role: .destructive) {
                                Task { await environment.setElectricityConsent(false) }
                            }
                            .font(.caption)
                            .padding(.top, 8)
                        }
                    }
                    .padding(16)
                }
                .refreshable {
                    await environment.refreshElectricity()
                }
            }
        }
        .navigationTitle("宿舍电费")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if environment.currentProfile != nil && (environment.electricityConsentGranted || environment.currentProfile?.isDemoMode == true) {
                    Button {
                        Task { await environment.refreshElectricity() }
                    } label: {
                        if environment.isSyncingElectricity {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(snapshot.targets.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showRoomPicker) {
            ElectricityRoomPickerSheet(catalog: catalog, catalogError: catalogError) { selected in
                Task { await environment.saveElectricityTargets(selected) }
            }
        }
        .sheet(isPresented: $showThresholdSheet) {
            ElectricityThresholdSheet(current: snapshot.lowBalanceThreshold) { newVal in
                Task { await environment.saveElectricityTargets(snapshot.targets, threshold: newVal) }
            }
        }
        .onAppear {
            environment.trackVisit(path: "/module/electricity", title: "宿舍电费")
            loadCatalogIfNeeded()
        }
    }

    private var consentGateView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("宿舍电费查询说明", systemImage: "bolt.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("查询宿舍电费需要通过北化一站自建网关（ele.buct.one）代理请求，并在请求头中携带你的学号与随机客户端标识以防接口滥用。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("• 仅在你主动点击查询或下拉刷新时发起请求。\n• 随时可在页面底部撤回授权并清除本地绑定记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("同意并开始使用") {
                    Task { await environment.setElectricityConsent(true) }
                }
                .buttonStyle(.glassProminent)
                .frame(maxWidth: .infinity)
            }
            .padding(20)
            .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
            .padding(16)
        }
    }

    private func electricityCard(target: ElectricityRoomTarget, reading: ElectricityReading?) -> some View {
        let isLow = (reading?.balanceValue ?? .greatestFiniteMagnitude) < snapshot.lowBalanceThreshold
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.displayTitle)
                        .font(.subheadline.weight(.semibold))
                    if !target.floorName.isEmpty {
                        Text(target.floorName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let r = reading {
                    Text(r.fromCache ? "网关缓存" : "实时回源")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(r.fromCache ? Color.secondary : Color.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((r.fromCache ? Color.secondary : Color.green).opacity(0.12), in: Capsule())
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(reading?.balanceText ?? "点击右上角刷新查询")
                    .font(.system(size: reading == nil ? 16 : 30, weight: .bold, design: .rounded))
                    .foregroundStyle(isLow ? Color.red : Color.primary)
                Spacer()
                if isLow {
                    Label("低于预警值", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.red)
                }
            }

            if let r = reading {
                HStack {
                    if r.accountStatus != "1" && !r.accountStatus.isEmpty {
                        Text("状态：\(r.accountStatus)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    if r.queriedAt > 0 {
                        Text("更新：\(formatTimestamp(r.queriedAt))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(16)
        .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private func loadCatalogIfNeeded() {
        guard catalog == nil else { return }
        guard let url = Bundle.main.url(forResource: "electricity_rooms", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            catalogError = "未找到内置宿舍目录文件"
            return
        }
        Task {
            do {
                catalog = try await environment.campusSync.loadElectricityCatalog(data: data)
            } catch {
                catalogError = error.localizedDescription
            }
        }
    }

    private func formatTimestamp(_ sec: Int64) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "MM-dd HH:mm"
        return fmt.string(from: Date(timeIntervalSince1970: TimeInterval(sec)))
    }
}

private struct ElectricityRoomPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let catalog: ElectricityRoomCatalog?
    let catalogError: String
    let onConfirm: ([ElectricityRoomTarget]) -> Void

    @State private var selectedCampus: ElectricityCampusOption?
    @State private var selectedBuilding: ElectricityBuildingOption?
    @State private var selectedFloor: ElectricityFloorOption?
    @State private var bindBothMeters = true
    @State private var buildingQuery = ""
    @State private var roomQuery = ""

    var body: some View {
        NavigationStack {
            List {
                if !catalogError.isEmpty {
                    Text(catalogError).foregroundStyle(.red)
                } else if let catalog {
                    Section("1. 选择校区") {
                        ForEach(catalog.campuses) { campus in
                            Button {
                                selectedCampus = campus
                                selectedBuilding = nil
                                selectedFloor = nil
                            } label: {
                                HStack {
                                    Text(campus.name)
                                    Spacer()
                                    if selectedCampus?.id == campus.id {
                                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }

                    if let campus = selectedCampus {
                        Section("2. 选择楼栋") {
                            TextField("筛选楼栋...", text: $buildingQuery)
                            let filteredBuildings = campus.buildings.filter {
                                buildingQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(buildingQuery)
                            }
                            ForEach(filteredBuildings) { bld in
                                Button {
                                    selectedBuilding = bld
                                    selectedFloor = nil
                                } label: {
                                    HStack {
                                        Text(bld.name)
                                        Spacer()
                                        if selectedBuilding?.id == bld.id {
                                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                        }
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }

                    if let bld = selectedBuilding {
                        Section("3. 选择楼层") {
                            ForEach(bld.floors) { floor in
                                Button {
                                    selectedFloor = floor
                                } label: {
                                    HStack {
                                        Text(floor.name)
                                        Spacer()
                                        if selectedFloor?.id == floor.id {
                                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                        }
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }

                    if let campus = selectedCampus, let bld = selectedBuilding, let floor = selectedFloor {
                        Section("4. 选择宿舍") {
                            if campus.hasMeterType {
                                Toggle("同时绑定照明与空调双表", isOn: $bindBothMeters)
                            }
                            TextField("搜索房间号...", text: $roomQuery)
                            if campus.hasMeterType && bindBothMeters {
                                let groups = groupedRooms(floor.rooms).filter {
                                    roomQuery.isEmpty || $0.baseName.localizedCaseInsensitiveContains(roomQuery)
                                }
                                ForEach(groups, id: \.baseName) { group in
                                    Button {
                                        let targets = group.rooms.map { r in
                                            ElectricityRoomTarget(
                                                schoolId: campus.schoolId,
                                                campusName: campus.name,
                                                buildingId: bld.buildingId,
                                                buildingName: bld.name,
                                                floorId: floor.floorId,
                                                floorName: floor.name,
                                                roomId: r.roomId,
                                                roomName: r.name,
                                                meterType: r.meterType
                                            )
                                        }
                                        onConfirm(targets)
                                        dismiss()
                                    } label: {
                                        HStack {
                                            Text(group.baseName)
                                            Spacer()
                                            Text(group.rooms.map(\.meterType).filter { !$0.isEmpty }.joined(separator: " + "))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .foregroundStyle(.primary)
                                }
                            } else {
                                let filtered = floor.rooms.filter {
                                    roomQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(roomQuery)
                                }
                                ForEach(filtered) { room in
                                    Button {
                                        let target = ElectricityRoomTarget(
                                            schoolId: campus.schoolId,
                                            campusName: campus.name,
                                            buildingId: bld.buildingId,
                                            buildingName: bld.name,
                                            floorId: floor.floorId,
                                            floorName: floor.name,
                                            roomId: room.roomId,
                                            roomName: room.name,
                                            meterType: room.meterType
                                        )
                                        onConfirm([target])
                                        dismiss()
                                    } label: {
                                        HStack {
                                            Text(room.name)
                                            Spacer()
                                            if !room.meterType.isEmpty {
                                                Text(room.meterType)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                } else {
                    ProgressView("正在加载宿舍目录...")
                }
            }
            .navigationTitle("选择宿舍")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func groupedRooms(_ rooms: [ElectricityRoomOption]) -> [(baseName: String, rooms: [ElectricityRoomOption])] {
        let grouped = Dictionary(grouping: rooms) { ElectricityRoomCatalog.baseRoomName($0.name) }
        return grouped.keys.sorted().map { base in
            let sorted = (grouped[base] ?? []).sorted { a, b in
                let ra = a.meterType.contains("照明") ? 0 : 1
                let rb = b.meterType.contains("照明") ? 0 : 1
                if ra != rb { return ra < rb }
                return a.name < b.name
            }
            return (base, sorted)
        }
    }
}

private struct ElectricityThresholdSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var threshold: Double
    let onSave: (Double) -> Void

    init(current: Double, onSave: @escaping (Double) -> Void) {
        _threshold = State(initialValue: current)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("低电量预警阈值（元/度）") {
                    Stepper(value: $threshold, in: 1...500, step: 5) {
                        Text("低于 \(Int(threshold)) 时高亮提醒")
                    }
                }
            }
            .navigationTitle("预警设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        onSave(threshold)
                        dismiss()
                    }
                }
            }
        }
    }
}
