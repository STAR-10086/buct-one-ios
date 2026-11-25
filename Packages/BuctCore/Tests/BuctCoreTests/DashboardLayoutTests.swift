@testable import BuctModel
import XCTest

final class DashboardLayoutTests: XCTestCase {

    func testDefaultLayoutHasNoOverlapsAndFitsInFourColumns() {
        let slots = DashboardLayout.default.slots
        XCTAssertEqual(slots.count, DashboardModule.allCases.count)
        for i in slots.indices {
            let a = slots[i]
            XCTAssertGreaterThanOrEqual(a.col, 0)
            XCTAssertLessThanOrEqual(a.col + a.size.colSpan, DashboardLayout.totalCols)
            for j in (i + 1)..<slots.count {
                XCTAssertFalse(
                    DashboardLayout.overlaps(a, slots[j]),
                    "默认布局存在重叠: \(a.module.rawValue) 与 \(slots[j].module.rawValue)"
                )
            }
        }
    }

    func testResolvePlacementSwapsOrPushesWithoutOverlap() {
        var layout = DashboardLayout.default
        // 把 row 2 col 0 的 secondClass 拖到 row 2 col 2（与 campusCard 碰撞，应触发互换）
        layout.resolvePlacement(moving: .secondClass, toCol: 2, row: 2)
        let scs = layout.slots.first { $0.module == .secondClass }!
        let card = layout.slots.first { $0.module == .campusCard }!
        XCTAssertEqual(scs.col, 2)
        XCTAssertEqual(scs.row, 2)
        XCTAssertEqual(card.col, 0)
        XCTAssertEqual(card.row, 2)

        // 把 homeworkTodo (4x2) 拖到 row 2，应将碰撞卡片下推且全局无重叠
        layout.resolvePlacement(moving: .homeworkTodo, toCol: 0, row: 2)
        for i in layout.slots.indices {
            for j in (i + 1)..<layout.slots.count {
                XCTAssertFalse(DashboardLayout.overlaps(layout.slots[i], layout.slots[j]))
            }
        }
    }

    func testCycleSizeKeepsValidBoundsAndNoOverlap() {
        var layout = DashboardLayout.default
        layout.cycleSize(for: .campusCard) // 1x1 -> 0.5x0.5
        XCTAssertEqual(layout.slots.first { $0.module == .campusCard }?.size, .miniHalf)
        layout.cycleSize(for: .campusCard) // 0.5x0.5 -> 2x1
        let updated = layout.slots.first { $0.module == .campusCard }!
        XCTAssertEqual(updated.size, .large2x1)
        XCTAssertEqual(updated.col, 0)

        for i in layout.slots.indices {
            for j in (i + 1)..<layout.slots.count {
                XCTAssertFalse(DashboardLayout.overlaps(layout.slots[i], layout.slots[j]))
            }
        }
    }
}
