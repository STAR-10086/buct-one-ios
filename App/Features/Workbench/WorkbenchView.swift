import BuctModel
import SwiftUI

struct WorkbenchView: View {
    @Environment(AppEnvironment.self) private var environment
    @Namespace private var glassNamespace

    @State private var isEditing = false
    @State private var draftLayout: DashboardLayout = .default
    @State private var undoStack: [DashboardLayout] = []
    @State private var selectedModule: DashboardModule?

    private var activeLayout: DashboardLayout {
        isEditing ? draftLayout : environment.dashboardLayout
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BuctBackdropBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if isEditing {
                            editToolbar
                        } else {
                            headerBanner
                        }

                        GlassEffectContainer(spacing: 12) {
                            WorkbenchGridLayout(spacing: 12) {
                                ForEach(activeLayout.slots) { slot in
                                    cardView(for: slot)
                                        .workbenchSlot(slot)
                                        .glassEffectID(slot.id, in: glassNamespace)
                                }
                            }
                        }

                        if isEditing && !draftLayout.hiddenModules.isEmpty {
                            hiddenModulesDock
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("北化一站")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !isEditing {
                        Button("自定义") {
                            draftLayout = environment.dashboardLayout
                            undoStack.removeAll()
                            withAnimation(.snappy) {
                                isEditing = true
                            }
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
            .navigationDestination(item: $selectedModule) { module in
                ModulePlaceholderView(module: module)
            }
        }
    }

    private var headerBanner: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("校园工作台")
                    .font(.headline)
                Text("iOS 26 原生液态玻璃 · M0 工程骨架")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(RefreshState.never.displayLabel)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .buctGlassCard(cornerRadius: 12, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
        }
        .padding(14)
        .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private var editToolbar: some View {
        HStack(spacing: 10) {
            Button {
                if let prev = undoStack.popLast() {
                    withAnimation(.snappy) {
                        draftLayout = prev
                    }
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.glass)
            .disabled(undoStack.isEmpty)

            Button {
                pushUndo()
                withAnimation(.snappy) {
                    draftLayout = .default
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.glass)

            Spacer()

            Button("取消") {
                withAnimation(.snappy) {
                    isEditing = false
                    undoStack.removeAll()
                }
            }
            .buttonStyle(.glass)

            Button("保存") {
                environment.saveDashboardLayout(draftLayout)
                withAnimation(.snappy) {
                    isEditing = false
                    undoStack.removeAll()
                }
            }
            .buttonStyle(.glassProminent)
        }
    }

    @ViewBuilder
    private func cardView(for slot: DashboardCardSlot) -> some View {
        Button {
            if isEditing {
                pushUndo()
                withAnimation(.snappy) {
                    draftLayout.cycleSize(for: slot.module)
                }
            } else {
                environment.trackVisit(path: slot.module.umamiPath, title: slot.module.title)
                selectedModule = slot.module
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                cardBody(for: slot)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if isEditing {
                    Button {
                        pushUndo()
                        withAnimation(.snappy) {
                            draftLayout.removeModule(slot.module)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
            }
            .buctGlassCard(
                cornerRadius: slot.size == .miniHalf ? 14 : 22,
                interactive: true,
                enabled: environment.appearance.liquidGlassEnabled
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func cardBody(for slot: DashboardCardSlot) -> some View {
        switch slot.size {
        case .miniHalf:
            VStack(spacing: 4) {
                Image(systemName: slot.module.systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                Text(slot.module.title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(6)

        case .medium1x1:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: slot.module.systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text(slot.module.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(isEditing ? slot.size.label : RefreshState.never.displayLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)

        case .large2x1:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: slot.module.systemImage)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Text(isEditing ? slot.size.label : RefreshState.never.displayLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(slot.module.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(slot.module.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(14)
        }
    }

    private var hiddenModulesDock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("点击加回工作台")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(draftLayout.hiddenModules) { module in
                        Button {
                            pushUndo()
                            withAnimation(.snappy) {
                                draftLayout.addModule(module)
                            }
                        } label: {
                            Label(module.title, systemImage: "plus.circle.fill")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
        .padding(12)
        .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private func pushUndo() {
        undoStack.append(draftLayout)
        if undoStack.count > 30 {
            undoStack.removeFirst()
        }
    }
}

struct ModulePlaceholderView: View {
    @Environment(AppEnvironment.self) private var environment
    let module: DashboardModule

    var body: some View {
        ZStack {
            BuctBackdropBackground()

            VStack(spacing: 16) {
                Image(systemName: module.systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
                    .padding(20)
                    .buctGlassCard(cornerRadius: 24, interactive: false, enabled: environment.appearance.liquidGlassEnabled)

                Text(module.title)
                    .font(.title2.weight(.bold))

                Text(module.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("接入域名", value: module.domainHost)
                    LabeledContent("当前状态", value: RefreshState.never.displayLabel)
                    LabeledContent("计划阶段", value: module.targetMilestone)
                }
                .font(.footnote)
                .padding(16)
                .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
            }
            .padding(20)
        }
        .navigationTitle(module.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
