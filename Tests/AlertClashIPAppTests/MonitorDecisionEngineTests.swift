import XCTest
@testable import AlertClashIPApp

final class MonitorDecisionEngineTests: XCTestCase {
    func testInitialMismatchTriggersAlert() {
        let now = Date(timeIntervalSince1970: 1_000)
        let result = MonitorDecisionEngine.evaluate(
            previous: .empty,
            nextStatus: .ipMismatch(currentIP: "1.1.1.1", expectedIP: "2.2.2.2"),
            now: now,
            escalationInterval: 300
        )

        XCTAssertEqual(result.notificationKind, .alertInitial)
        XCTAssertEqual(result.snapshot.lastNotificationAt, now)
    }

    func testRepeatedMismatchEscalatesAfterInterval() {
        let then = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 1_500)
        let previous = MonitorSnapshot(
            status: .ipMismatch(currentIP: "1.1.1.1", expectedIP: "2.2.2.2"),
            lastCheckedAt: then,
            lastStatusChangeAt: then,
            lastNotificationAt: then,
            lastHealthyIP: nil
        )

        let result = MonitorDecisionEngine.evaluate(
            previous: previous,
            nextStatus: .ipMismatch(currentIP: "1.1.1.1", expectedIP: "2.2.2.2"),
            now: now,
            escalationInterval: 300
        )

        XCTAssertEqual(result.notificationKind, .alertEscalated)
        XCTAssertEqual(result.snapshot.lastNotificationAt, now)
    }

    func testRecoveryTriggersRecoveryNotification() {
        let then = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 1_050)
        let previous = MonitorSnapshot(
            status: .ipLookupFailed(errorSummary: "timeout"),
            lastCheckedAt: then,
            lastStatusChangeAt: then,
            lastNotificationAt: then,
            lastHealthyIP: nil
        )

        let result = MonitorDecisionEngine.evaluate(
            previous: previous,
            nextStatus: .healthy(currentIP: "8.8.8.8"),
            now: now,
            escalationInterval: 300
        )

        XCTAssertEqual(result.notificationKind, .recovered)
        XCTAssertEqual(result.snapshot.lastHealthyIP, "8.8.8.8")
    }

    func testHealthyStateDoesNotNotify() {
        let now = Date(timeIntervalSince1970: 1_000)
        let result = MonitorDecisionEngine.evaluate(
            previous: .empty,
            nextStatus: .healthy(currentIP: "8.8.8.8"),
            now: now,
            escalationInterval: 300
        )

        XCTAssertNil(result.notificationKind)
    }

    func testValidationAcceptsIPv4AndIPv6() {
        XCTAssertTrue(IPValidation.isValidIPAddress("1.1.1.1"))
        XCTAssertTrue(IPValidation.isValidIPAddress("2001:4860:4860::8888"))
        XCTAssertFalse(IPValidation.isValidIPAddress("not-an-ip"))
    }
}
