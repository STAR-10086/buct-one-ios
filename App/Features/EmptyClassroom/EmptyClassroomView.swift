import BuctModel
import SwiftUI

struct EmptyClassroomView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var campus: EmptyClassroomCampus = .north
    @State private var week: Int = 1
    @State private var dayOfWeek: Int = ScheduleDates.todayDayOfWeek()
    @State private var period: Int = 1

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var rooms: [EmptyClassroom] = []
    @State private var selectedBuilding: String = "全部"
    @State private var selectedFloor: String = "全部"

    private var buildingOptions: [String] {
        let buildings = Array(Set(rooms.map(\.building).filter { !$0.isEmpty })).sorted()
        return ["全部"] + buildings
    }

    private var floorOptions: [String] {
        let floors = Array(Set(rooms.map(\.floor).filter { !$0.isEmpty }))
            .sorted { (Int($0) ?? 999) < (Int($1) ?? 999) }
        return ["全部"] + floors
    }

    private var filteredRooms: [EmptyClassroom] {
        rooms.filter { room in
            (selectedBuilding == "全部" || room.building == selectedBuilding) &&
            (selectedFloor == "全部" || room.floor == selectedFloor)
        }
    }

    var body: some View {
        ZStack {
            BuctBackdropBackground()

            ScrollView {
                VStack(spacing: 14) {
                    filterPanel

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !rooms.isEmpty {
                        dynamicFacetFilters
                    }

                    if filteredRooms.isEmpty && !isLoading {
                        Text("点击「查询空教室」获取实时空教室列表")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(28)
                            .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredRooms) { room in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(room.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text([room.campus, room.building, room.type].filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if room.seats > 0 {
                                        Text("\(room.seats) 座")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color.accentColor)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                                    }
                                }
                                .padding(14)
                                .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("空闲教室")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            week = environment.currentTeachingWeek ?? environment.selectedWeek
        }
    }

    private var filterPanel: some View {
        VStack(spacing: 12) {
            Picker("校区", selection: $campus) {
                ForEach(EmptyClassroomCampus.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Picker("周次", selection: $week) {
                    ForEach(1...20, id: \.self) { w in
                        Text("第 \(w) 周").tag(w)
                    }
                }
                .pickerStyle(.menu)

                Picker("星期", selection: $dayOfWeek) {
                    ForEach(1...7, id: \.self) { d in
                        Text(["周一", "周二", "周三", "周四", "周五", "周六", "周日"][d - 1]).tag(d)
                    }
                }
                .pickerStyle(.menu)

                Picker("节次", selection: $period) {
                    ForEach(1...12, id: \.self) { p in
                        Text("第 \(p) 节").tag(p)
                    }
                }
                .pickerStyle(.menu)
            }

            Button {
                Task { await query() }
            } label: {
                HStack {
                    if isLoading { ProgressView().tint(.white) }
                    Text("查询空教室")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .disabled(isLoading)
        }
        .padding(16)
        .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private var dynamicFacetFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(buildingOptions, id: \.self) { b in
                        Button(b) { selectedBuilding = b }
                            .buttonStyle(.glass)
                            .tint(selectedBuilding == b ? Color.accentColor : .secondary)
                    }
                }
            }
            if floorOptions.count > 2 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(floorOptions, id: \.self) { f in
                            Button(f == "全部" ? "全部楼层" : "\(f)层") { selectedFloor = f }
                                .buttonStyle(.glass)
                                .tint(selectedFloor == f ? Color.accentColor : .secondary)
                        }
                    }
                }
            }
        }
    }

    private func query() async {
        isLoading = true
        errorMessage = nil
        selectedBuilding = "全部"
        selectedFloor = "全部"
        defer { isLoading = false }

        do {
            rooms = try await environment.syncService.queryEmptyClassrooms(
                profile: environment.currentProfile,
                term: environment.selectedTerm,
                campus: campus,
                week: week,
                day: dayOfWeek,
                period: period
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
