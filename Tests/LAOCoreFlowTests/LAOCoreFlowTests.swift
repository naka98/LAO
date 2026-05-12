import XCTest
import LAODomain
@testable import LAO

/// Regression guard for the DesignWorkflow Codable decoder asymmetry.
///
/// Background: the custom `DesignWorkflow.init(from:)` was missing decode calls
/// for fields listed in CodingKeys but encoded by the synthesized encoder. The
/// concrete symptom was `structureApprovedAt` silently going to nil on every
/// app restart, demoting an in-progress SPECIFY workflow back to REFINE phase
/// where the structure-approval gate rejected re-entry on `unreviewedItems`.
final class LAOCoreFlowTests: XCTestCase {

    private func makeJSONEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    private func makeJSONDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    func testDesignWorkflowDecoderPreservesAllStateFields() throws {
        let approvedAt = Date(timeIntervalSince1970: 1_778_573_524)
        let freezeAt = Date(timeIntervalSince1970: 1_778_500_000)
        let usage = [
            "claude": ProviderUsageStats(
                callCount: 7, inputChars: 12_345,
                outputChars: 6_789, failedCallCount: 1
            )
        ]

        var workflow = DesignWorkflow(phase: .planning, taskDescription: "round-trip")
        workflow.structureApprovedAt = approvedAt
        workflow.designFreezeAt = freezeAt
        workflow.partialAnalysisOutput = "partial analysis output checkpoint"
        workflow.providerUsage = usage

        let data = try makeJSONEncoder().encode(workflow)
        let restored = try makeJSONDecoder().decode(DesignWorkflow.self, from: data)

        XCTAssertEqual(
            restored.structureApprovedAt?.timeIntervalSince1970,
            approvedAt.timeIntervalSince1970,
            "structureApprovedAt must round-trip — losing it demotes SPECIFY back to REFINE phase"
        )
        XCTAssertTrue(restored.isStructureApproved)
        XCTAssertEqual(
            restored.designFreezeAt?.timeIntervalSince1970,
            freezeAt.timeIntervalSince1970
        )
        XCTAssertEqual(restored.partialAnalysisOutput, "partial analysis output checkpoint")
        XCTAssertEqual(restored.providerUsage?["claude"]?.callCount, 7)
        XCTAssertEqual(restored.providerUsage?["claude"]?.inputChars, 12_345)
        XCTAssertEqual(restored.providerUsage?["claude"]?.failedCallCount, 1)
    }

    func testDeliverableItemPreservesVerdictFlipCount() throws {
        var item = DeliverableItem(name: "oscillating-item")
        item.verdictFlipCount = 3

        let data = try makeJSONEncoder().encode(item)
        let restored = try makeJSONDecoder().decode(DeliverableItem.self, from: data)

        XCTAssertEqual(
            restored.verdictFlipCount, 3,
            "verdictFlipCount must round-trip — losing it resets the oscillation warning on every restart"
        )
    }

    func testDesignWorkflowDecoderAcceptsLegacyJSON() throws {
        let legacy = Data("""
        {
          "phase": "planning",
          "taskDescription": "legacy session",
          "deliverables": [],
          "teamMembers": [],
          "steps": [],
          "directorSummary": "",
          "apiCallCount": 0,
          "totalInputChars": 0,
          "totalOutputChars": 0,
          "chatHistory": [],
          "edges": [],
          "uncertainties": [],
          "hiddenRequirements": []
        }
        """.utf8)

        let workflow = try makeJSONDecoder().decode(DesignWorkflow.self, from: legacy)
        XCTAssertNil(workflow.structureApprovedAt)
        XCTAssertNil(workflow.designFreezeAt)
        XCTAssertNil(workflow.partialAnalysisOutput)
        XCTAssertNil(workflow.providerUsage)
        XCTAssertFalse(workflow.isStructureApproved)
    }
}
