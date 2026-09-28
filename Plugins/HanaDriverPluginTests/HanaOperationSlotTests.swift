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
}
