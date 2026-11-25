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

struct WorkbenchGridLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 10) {
        self.spacing = spacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let totalWidth = proposal.width ?? 360
        let unitSize = halfUnitSize(for: totalWidth)
        let maxRowUnit = subviews
            .compactMap { $0[WorkbenchSlotKey.self] }
            .map { $0.rowUnit + $0.size.rowUnits }
            .max() ?? 2

        let height = CGFloat(maxRowUnit) * unitSize + CGFloat(max(0, maxRowUnit / 2 - 1)) * spacing
        return CGSize(width: totalWidth, height: max(height, unitSize * 2))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let unitSize = halfUnitSize(for: bounds.width)
        let halfGap = spacing / 2

        for subview in subviews {
            guard let slot = subview[WorkbenchSlotKey.self] else { continue }

            let x = bounds.minX + CGFloat(slot.colUnit) * (unitSize + halfGap)
            let y = bounds.minY + CGFloat(slot.rowUnit) * (unitSize + halfGap)
            let w = CGFloat(slot.size.colUnits) * unitSize + CGFloat(max(0, slot.size.colUnits - 1)) * halfGap
            let h = CGFloat(slot.size.rowUnits) * unitSize + CGFloat(max(0, slot.size.rowUnits - 1)) * halfGap

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: w, height: h)
            )
        }
    }

    private func halfUnitSize(for totalWidth: CGFloat) -> CGFloat {
        let totalUnits = CGFloat(DashboardLayout.totalColUnits)
        let halfGap = spacing / 2
        let gaps = (totalUnits - 1) * halfGap
        return max(24, (totalWidth - gaps) / totalUnits)
    }
}
