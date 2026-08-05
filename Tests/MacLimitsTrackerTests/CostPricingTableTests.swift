import XCTest
@testable import MacLimitsTrackerCore

final class CostPricingTableTests: XCTestCase {

    // MARK: - Helper Function

    private func assertRate(_ result: (tariffId: String, rate: CostRate)?,
                            expectedTariffId: String,
                            input: String,
                            output: String,
                            cacheCreation: String,
                            cacheRead: String,
                            line: UInt = #line) {
        guard let result = result else {
            XCTFail("Expected a valid rate but got nil", line: line)
            return
        }
        XCTAssertEqual(result.tariffId, expectedTariffId, line: line)
        XCTAssertEqual(result.rate.inputPerToken, Decimal(string: input)!, line: line)
        XCTAssertEqual(result.rate.outputPerToken, Decimal(string: output)!, line: line)
        XCTAssertEqual(result.rate.cacheCreationPerToken, Decimal(string: cacheCreation)!, line: line)
        XCTAssertEqual(result.rate.cacheReadPerToken, Decimal(string: cacheRead)!, line: line)
    }

    // MARK: - Exact Matches

    func test_rate_exactMatch_claudeSonnet_returnsCorrectTariffAndRates() {
        let result = CostPricingTable.rate(forModel: "claude-sonnet-4-5")
        assertRate(result,
                   expectedTariffId: "claude-sonnet-4-5",
                   input: "0.000003",
                   output: "0.000015",
                   cacheCreation: "0.00000375",
                   cacheRead: "0.0000003")
    }

    func test_rate_exactMatch_claudeOpus_returnsCorrectTariffAndRates() {
        let result = CostPricingTable.rate(forModel: "claude-opus-4-1")
        assertRate(result,
                   expectedTariffId: "claude-opus-4-1",
                   input: "0.000015",
                   output: "0.000075",
                   cacheCreation: "0.00001875",
                   cacheRead: "0.0000015")
    }

    func test_rate_exactMatch_gptCodex_returnsCorrectTariffAndRates() {
        let result = CostPricingTable.rate(forModel: "gpt-5-codex")
        assertRate(result,
                   expectedTariffId: "gpt-5-codex",
                   input: "0.00000125",
                   output: "0.00001",
                   cacheCreation: "0",
                   cacheRead: "0.000000125")
    }

    // MARK: - Prefix Aliases (Versioned Models)

    func test_rate_versionedModelId_claudeSonnet_resolvesViaPrefixAlias() {
        let result = CostPricingTable.rate(forModel: "claude-sonnet-4-5-20260101")
        assertRate(result,
                   expectedTariffId: "claude-sonnet-4-5",
                   input: "0.000003",
                   output: "0.000015",
                   cacheCreation: "0.00000375",
                   cacheRead: "0.0000003")
    }

    func test_rate_versionedModelId_gptCodex_resolvesViaPrefixAlias() {
        let result = CostPricingTable.rate(forModel: "gpt-5-codex-20260202")
        assertRate(result,
                   expectedTariffId: "gpt-5-codex",
                   input: "0.00000125",
                   output: "0.00001",
                   cacheCreation: "0",
                   cacheRead: "0.000000125")
    }

    // MARK: - Unknown and Invalid Models

    func test_rate_unknownModel_returnsNilRatherThanGuessing() {
        XCTAssertNil(CostPricingTable.rate(forModel: "some-model-nobody-heard-of"))
        XCTAssertNil(CostPricingTable.rate(forModel: "claude-future-6"))
    }

    func test_rate_doesNotMatchUnrelatedModelSharingNoPrefix() {
        // Shared words, different format
        XCTAssertNil(CostPricingTable.rate(forModel: "gpt-4o"))
        XCTAssertNil(CostPricingTable.rate(forModel: "claude-3-opus-20240229"))
        XCTAssertNil(CostPricingTable.rate(forModel: "gpt-5"))
    }

    func test_rate_emptyModelString_returnsNil() {
        XCTAssertNil(CostPricingTable.rate(forModel: ""))
    }
}
