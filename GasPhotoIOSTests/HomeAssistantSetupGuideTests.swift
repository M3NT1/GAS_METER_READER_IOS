import XCTest
@testable import GasPhotoIOS

final class HomeAssistantSetupGuideTests: XCTestCase {
    func testSetupGuideMetadataAndSections() {
        XCTAssertEqual(HomeAssistantSetupGuide.lastVerified, "2026-09-20")
        XCTAssertFalse(HomeAssistantSetupGuide.sections.isEmpty)
        XCTAssertGreaterThanOrEqual(HomeAssistantSetupGuide.sections.count, 7)
    }

    func testAllLinksAreAbsoluteHTTPSAndDoNotContainTokens() {
        for section in HomeAssistantSetupGuide.sections {
            for link in section.links {
                XCTAssertEqual(link.url.scheme, "https", "All guide links must use https scheme: \(link.url)")
                XCTAssertFalse(link.url.absoluteString.contains("token"), "Links must not contain token parameters: \(link.url)")
                XCTAssertFalse(link.url.absoluteString.contains("Bearer"), "Links must not contain auth headers: \(link.url)")
                XCTAssertFalse(link.url.absoluteString.contains("key"), "Links must not contain keys: \(link.url)")
            }
        }
    }

    func testContainsExactIntegrationRepoURL() {
        let allURLs = HomeAssistantSetupGuide.sections.flatMap(\.links).map(\.url.absoluteString)
        XCTAssertTrue(
            allURLs.contains("https://github.com/M3NT1/home-assistant-gas-photo"),
            "Guide must contain the exact integration repository URL"
        )
    }

    func testContainsHACSAndManualPaths() {
        let allDetails = HomeAssistantSetupGuide.sections.flatMap(\.details).joined(separator: " ")
        XCTAssertTrue(
            allDetails.contains("/config/custom_components/gas_photo"),
            "Guide must mention the /config/custom_components/gas_photo path for manual installation"
        )

        let allURLs = HomeAssistantSetupGuide.sections.flatMap(\.links).map(\.url.absoluteString)
        XCTAssertTrue(
            allURLs.contains("https://www.hacs.xyz/docs/use/download/download/"),
            "Guide must contain the HACS download link"
        )
    }

    func testContainsYAMLSnippet() {
        let snippets = HomeAssistantSetupGuide.sections.compactMap(\.codeSnippet)
        XCTAssertTrue(
            snippets.contains(where: { $0.contains("gas_photo:") && $0.contains("max_m3_per_hour:") }),
            "Guide must contain the configuration.yaml snippet"
        )
    }

    func testContainsAdminTokenRequirementAndConnectionTestLimits() {
        let allDetails = HomeAssistantSetupGuide.sections.flatMap(\.details).joined(separator: " ")
        XCTAssertTrue(
            allDetails.contains("adminisztrátori"),
            "Guide must mention that an admin token is required"
        )
        XCTAssertTrue(
            allDetails.contains("REST API és a gas_photo"),
            "Guide must explain what the connection test verifies"
        )
    }

    func testContainsGasMainEntityIdentifier() {
        let allDetails = HomeAssistantSetupGuide.sections.flatMap(\.details).joined(separator: " ")
        XCTAssertTrue(
            allDetails.contains("gas_photo:gas_main"),
            "Guide must mention the gas_photo:gas_main entity identifier for the Energy dashboard"
        )
    }
}
