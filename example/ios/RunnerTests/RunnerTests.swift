import CoreSpotlight
import Flutter
import UIKit
import XCTest

@testable import system_search_index

final class RunnerTests: XCTestCase {
    func testIdentityRoundTripAndDomainIsolation() {
        let id = "record:/42 \"*"
        let domain = "account/中文"
        let encoded = SystemSearchIndexPlugin.identifier(domain: domain, id: id)
        XCTAssertEqual(SystemSearchIndexPlugin.decodeIdentifier(encoded), ["domain": domain, "id": id])
        XCTAssertNotEqual(encoded, SystemSearchIndexPlugin.identifier(domain: "other", id: id))
        XCTAssertFalse(SystemSearchIndexPlugin.nativeDomain(domain).contains("*"))
    }

    func testForeignAndMalformedIdentifiersAreIgnored() {
        XCTAssertNil(SystemSearchIndexPlugin.decodeIdentifier("other-plugin.42"))
        XCTAssertNil(SystemSearchIndexPlugin.decodeIdentifier("ssi.item.not-base64"))
        XCTAssertNil(SystemSearchIndexPlugin.decodeIdentifier("ssi.item.W10="))
    }

    @MainActor
    func testColdActivationBufferedAndWarmActivationDelivered() {
        let plugin = SystemSearchIndexPlugin()
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier:
            SystemSearchIndexPlugin.identifier(domain: "account", id: "42")]
        let delegate: FlutterApplicationLifeCycleDelegate = plugin
        XCTAssertEqual(delegate.application?(UIApplication.shared, continue: activity, restorationHandler: { _ in }), true)
        var received: [[String: String]] = []
        XCTAssertNil(plugin.onListen(withArguments: nil) { event in
            if let value = event as? [String: String] { received.append(value) }
        })
        XCTAssertEqual(received, [["domain": "account", "id": "42"]])
        XCTAssertTrue(plugin.application(UIApplication.shared, continue: activity, restorationHandler: { _ in }))
        XCTAssertEqual(received.count, 2)
        _ = plugin.onCancel(withArguments: nil)
        _ = plugin.application(UIApplication.shared, continue: activity, restorationHandler: { _ in })
        XCTAssertEqual(received.count, 2)
        _ = plugin.onListen(withArguments: nil) { event in
            if let value = event as? [String: String] { received.append(value) }
        }
        XCTAssertEqual(received.count, 3)
    }

    @MainActor
    func testForeignActivityIsNotClaimed() {
        let plugin = SystemSearchIndexPlugin()
        XCTAssertFalse(plugin.application(UIApplication.shared,
            continue: NSUserActivity(activityType: "other.activity"), restorationHandler: { _ in }))
    }
}
