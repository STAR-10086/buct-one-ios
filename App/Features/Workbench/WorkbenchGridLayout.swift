import BuctModel
import SwiftUI

struct WorkbenchSlotKey: LayoutValueKey {
    static let defaultValue: DashboardCardSlot? = nil
}

extension View {
    func workbenchSlot(_ slot: DashboardCardSlot) -> some View {
        layoutValue(key: WorkbenchSlotKey.self, value: slot)
    }
}

/// 严格对齐 Android DashboardRoute 的 4 列自由坐标栅格：
/// - gap = 10pt
/// - cellH = 76pt (1 rowSpan)
/// - MINI = 1×1 (cellW × 76), MEDIUM = 2×2 ((2*cellW+10) × 162), LARGE = 4×2 (full × 162)
struct WorkbenchGridLayout: Layout {
    static let cellHeight: CGFloat = 76
    static let spacing: CGFloat = 10

    let minRows: Int

    init(minRows: Int = 0) {
        self.minRows = minRows
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let totalWidth = proposal.width ?? 360
        let maxRow = max(
            minRows,
            subviews.compactMap { $0[WorkbenchSlotKey.self] }.map { $0.row + $0.size.rowSpan }.max() ?? 2
        )
        let height = CGFloat(maxRow) * Self.cellHeight + CGFloat(max(0, maxRow - 1)) * Self.spacing
        return CGSize(width: totalWidth, height: max(height, Self.cellHeight * 2))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let cellW = Self.cellWidth(for: bounds.width)
        let gap = Self.spacing

        for subview in subviews {
            guard let slot = subview[WorkbenchSlotKey.self] else { continue }

            let x = bounds.minX + CGFloat(slot.col) * (cellW + gap)
            let y = bounds.minY + CGFloat(slot.row) * (Self.cellHeight + gap)
            let w = CGFloat(slot.size.colSpan) * cellW + CGFloat(max(0, slot.size.colSpan - 1)) * gap
            let h = CGFloat(slot.size.rowSpan) * Self.cellHeight + CGFloat(max(0, slot.size.rowSpan - 1)) * gap

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: w, height: h)
            )
        }
    }

    static func cellWidth(for totalWidth: CGFloat) -> CGFloat {
        let cols = CGFloat(DashboardLayout.totalCols)
        return max(44, (totalWidth - spacing * (cols - 1)) / cols)
    }
}
