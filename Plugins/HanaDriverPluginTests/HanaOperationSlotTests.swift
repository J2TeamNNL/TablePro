import Foundation
import XCTest

final class HanaOperationSlotTests: XCTestCase {
    func testACancelAfterAssignmentReturnsTheTicketToInterrupt() {
        let slot = HanaOperationSlot()
        let ticket = HanaOperationTicket(session: 7, operation: 3)

        XCTAssertTrue(slot.assign(ticket))
        XCTAssertEqual(slot.cancel(), ticket)
    }

    func testACancelBeforeAssignmentKeepsTheOperationFromBeingIssued() {
        let slot = HanaOperationSlot()

        XCTAssertNil(slot.cancel())
        XCTAssertFalse(slot.assign(HanaOperationTicket(session: 7, operation: 4)))
    }

    func testOnlyTheFirstCancelReturnsTheTicket() {
        let slot = HanaOperationSlot()
        let ticket = HanaOperationTicket(session: 7, operation: 5)

        XCTAssertTrue(slot.assign(ticket))
        XCTAssertEqual(slot.cancel(), ticket)
        XCTAssertNil(slot.cancel())
        XCTAssertTrue(slot.isCancelled)
    }
}
