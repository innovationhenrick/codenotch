import AppKit
import XCTest
@testable import Codenotch

final class NotionAIUsageTests: XCTestCase {
    func testCreditsAndRunsComeFromTheInsightsResponse() throws {
        let windows = try NotionAIUsage.windows(from: Data(NotionAIFixture.insights.utf8))
        let window = try XCTUnwrap(windows.first)

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(window.id, "premium-credits")
        XCTAssertEqual(window.label, "Premium AI credits")
        XCTAssertEqual(window.usedFraction ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(window.usedText, "250 credits")
        XCTAssertEqual(window.detail, "250 credits · 3 runs")
        XCTAssertNil(window.resetsAt, "Notion Insights does not report a reset timestamp")
    }

    func testHiddenOrMissingLimitDoesNotInventAPercentage() throws {
        for limit in [#""hidden""#, "null"] {
            let json = NotionAIFixture.insights
                .replacingOccurrences(of: #""credit_limit":1000"#, with: #""credit_limit":\#(limit)"#)
            let window = try XCTUnwrap(NotionAIUsage.windows(from: Data(json.utf8)).first)
            XCTAssertNil(window.usedFraction, "a hidden or missing denominator is not a zero-percent limit")
            XCTAssertEqual(window.detail, "250 credits · 3 runs")
        }
    }

    func testStringCreditLimitIsAcceptedByTheDocumentedUnionType() throws {
        let json = NotionAIFixture.insights
            .replacingOccurrences(of: #""credit_limit":1000"#, with: #""credit_limit":"800""#)
        let reading = try NotionAIUsage.reading(from: Data(json.utf8))
        XCTAssertEqual(reading.usedFraction ?? -1, 0.3125, accuracy: 0.0001)
    }

    func testMalformedOrNegativeInsightsAreRejected() {
        let broken = [
            Data("not json".utf8),
            Data("{}".utf8),
            Data(#"{"total_credits_used":-1,"credit_limit":10,"runs_completed":1}"#.utf8),
            Data(#"{"total_credits_used":1,"credit_limit":10,"runs_completed":1.5}"#.utf8),
            Data(#"{"total_credits_used":1,"credit_limit":"unavailable","runs_completed":1}"#.utf8)
        ]

        for data in broken {
            XCTAssertThrowsError(try NotionAIUsage.reading(from: data))
        }
    }

    func testNotionGlyphAssetIsBundled() {
        XCTAssertNotNil(NSImage(named: ProviderGlyph.notion.assetName))
    }
}

enum NotionAIFixture {
    static let insights = #"{"object":"agent_insights","id":"notion_ai","name":"Cubinho","agent_type":"notion_ai","status":"active","pause_reason":null,"created_by":null,"total_credits_used":250,"credit_limit":1000,"runs_completed":3}"#
}
