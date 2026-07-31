import XCTest
@testable import MacLimitsTrackerCore

/// Маппинг агрегата `CostEstimateResult` → cost-строка/секция попапа (bd 725.2).
/// Критичное требование ревью 725.1: в `.incomplete` total — сумма только
/// ИЗВЕСТНЫХ оценённых записей, поэтому показывается как нижняя граница
/// («≥ $X») с явным индикатором неполноты — никогда как окончательный итог.
final class CostPopupContentTests: XCTestCase {
    private let pricingVersion = "2026-07-static-v1"

    private func estimate(total: String = "12.34") -> CostEstimate {
        CostEstimate(total: Decimal(string: total)!, breakdown: [], pricingTableVersion: pricingVersion)
    }

    private func costRow(_ result: CostEstimateResult) -> CostRowContent {
        guard case .cost(let content) = PopupContentBuilder.costRow(result) else {
            XCTFail("ожидалась строка .cost, получена \(PopupContentBuilder.costRow(result))")
            fatalError()
        }
        return content
    }

    func test_available_mapsToDefinitiveTotalWithLabelSourceAndPricing() {
        let row = costRow(.available(estimate(), diagnostics: CostDiagnostics()))

        XCTAssertEqual(row.state, .available)
        XCTAssertEqual(row.label, "Cost estimate")
        XCTAssertEqual(row.valueText, "$12.34")
        XCTAssertFalse(row.valueText.contains("≥"), "available — точный итог, не нижняя граница")
        XCTAssertEqual(row.sourceText, "local logs")
        XCTAssertEqual(row.pricingVersion, pricingVersion)
        XCTAssertNil(row.indicatorText)
    }

    func test_incomplete_mapsToLowerBoundWithExplicitIndicator() throws {
        let row = costRow(.incomplete(estimate(), diagnostics: CostDiagnostics(malformedLines: 2)))

        XCTAssertEqual(row.state, .incomplete)
        XCTAssertEqual(row.valueText, "≥ $12.34")
        XCTAssertNotEqual(row.valueText, "$12.34",
                          "неполную сумму нельзя показывать как окончательный итог")
        XCTAssertEqual(row.sourceText, "local logs")
        XCTAssertEqual(row.pricingVersion, pricingVersion)
        let indicator = try XCTUnwrap(row.indicatorText, "incomplete требует явного индикатора неполноты")
        XCTAssertTrue(indicator.contains("lower bound"))
        XCTAssertTrue(indicator.contains("unpriced"))
    }

    func test_unavailable_noLogsFound_isExplicit() {
        let row = costRow(.unavailable(.noLogsFound, diagnostics: CostDiagnostics()))

        XCTAssertEqual(row.state, .unavailable)
        XCTAssertEqual(row.valueText, "unavailable")
        XCTAssertEqual(row.sourceText, "local logs")
        XCTAssertNil(row.pricingVersion, "оценки нет — версии тарифов тоже")
        XCTAssertEqual(row.indicatorText, "no local logs found")
    }

    func test_unavailable_noPricedRecords_isExplicit() {
        let row = costRow(.unavailable(.noPricedRecords, diagnostics: CostDiagnostics()))

        XCTAssertEqual(row.state, .unavailable)
        XCTAssertEqual(row.valueText, "unavailable")
        XCTAssertNil(row.pricingVersion)
        XCTAssertEqual(row.indicatorText, "no priced records in logs")
    }

    func test_footnote_carriesSourcePricingAndIndicator() {
        let complete = costRow(.available(estimate(), diagnostics: CostDiagnostics()))
        XCTAssertEqual(complete.footnoteText, "local logs · pricing \(pricingVersion)")

        let incomplete = costRow(.incomplete(estimate(), diagnostics: CostDiagnostics(unknownModels: 1)))
        XCTAssertEqual(incomplete.footnoteText,
                       "local logs · pricing \(pricingVersion) · lower bound — some usage unpriced")

        let unavailable = costRow(.unavailable(.noLogsFound, diagnostics: CostDiagnostics()))
        XCTAssertEqual(unavailable.footnoteText, "local logs · no local logs found")
    }

    func test_moneyFormatting_usesUSDWithTwoFractionDigits() {
        let row = costRow(.available(estimate(total: "0.006"), diagnostics: CostDiagnostics()))
        XCTAssertEqual(row.valueText, "$0.01", "доли центов округляются до центов на отображении")
    }

    func test_sections_appendsCostSectionAfterProviderSections() {
        let state = ProviderState(descriptor: claudeDescriptor, snapshot: nil)
        let withoutCost = PopupContentBuilder.sections([state])
        XCTAssertEqual(withoutCost.count, 1)

        let result: CostEstimateResult = .available(estimate(), diagnostics: CostDiagnostics())
        let withCost = PopupContentBuilder.sections([state], costResult: result)

        XCTAssertEqual(withCost.count, 2)
        let costSection = withCost[1]
        XCTAssertEqual(costSection.descriptor.id, "cost")
        XCTAssertFalse(costSection.isStale)
        guard case .cost(let content) = costSection.rows.first else {
            return XCTFail("секция оценки должна содержать строку .cost")
        }
        XCTAssertEqual(content.state, .available)
    }
}

private let claudeDescriptor = ProviderDescriptor(
    id: "claude", displayName: "Claude Code", shortName: "Claude",
    menuBarSymbol: "C", accentColorHex: 0xFF9E64, loginHelp: nil
)
