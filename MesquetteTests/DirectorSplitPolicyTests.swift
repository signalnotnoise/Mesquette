import XCTest
@testable import Mesquette

final class DirectorSplitPolicyTests: XCTestCase {
    func testSystemPromptForbidsAnatomyAndArchitectureKits() {
        let prompt = DirectorSystemPrompt.text
        XCTAssertTrue(prompt.contains("Do NOT split a robot"))
        XCTAssertTrue(prompt.contains("car into wheels") || prompt.contains("Do NOT pad"))
        XCTAssertTrue(prompt.contains("castle"))
        XCTAssertTrue(prompt.contains("kind = set"))
        XCTAssertTrue(prompt.contains("kind = single"))
        XCTAssertTrue(prompt.contains("invent"))
        XCTAssertTrue(prompt.contains("slot"))
        XCTAssertTrue(prompt.contains("8K"))
        XCTAssertTrue(prompt.contains("octane"))
    }

    func testSystemPromptDescribesTableLayout() {
        let prompt = DirectorSystemPrompt.text
        XCTAssertTrue(prompt.contains("Do NOT invent meter offsets") || prompt.contains("meter"))
        XCTAssertTrue(prompt.contains("placeSetting") || prompt.contains("place setting"))
        XCTAssertTrue(prompt.contains("heroCenter") || prompt.contains("slot"))
        XCTAssertTrue(prompt.contains("paper"))
        XCTAssertTrue(prompt.contains("chunky") || prompt.contains("CHUNKY"))
        XCTAssertTrue(prompt.contains("5–6") || prompt.contains("5-6"))
        XCTAssertTrue(prompt.contains("SETTING") || prompt.contains("setting"))
        XCTAssertTrue(prompt.contains("Do NOT pad") || prompt.contains("REQUIRED"))
        XCTAssertTrue(prompt.contains("track"))
    }

    func testInventPromptWritesABriefNotALayout() {
        let prompt = DirectorSystemPrompt.inventText
        XCTAssertTrue(prompt.contains("not compiling"))
        XCTAssertTrue(prompt.contains("chunky"))
        XCTAssertTrue(prompt.contains("paper"))
        XCTAssertFalse(prompt.contains("offsetX"))
        XCTAssertTrue(prompt.contains("1 to 3 words") || prompt.contains("1 to 3"))
        XCTAssertTrue(prompt.contains("landmark") || prompt.contains("not a mug"))
        XCTAssertFalse(prompt.contains("tabletop diorama"))
        XCTAssertTrue(prompt.contains("scene brief"))
    }

    func testSystemPromptAsksForDistinctiveObjects() {
        let prompt = DirectorSystemPrompt.text
        XCTAssertTrue(prompt.contains("Do NOT default to mug"))
        XCTAssertTrue(prompt.contains("10–24") || prompt.contains("10-24"))
        XCTAssertTrue(prompt.contains("diving helmet") || prompt.contains("lighthouse"))
    }

    func testSystemPromptDoesNotAskTheModelToPose() {
        let prompt = DirectorSystemPrompt.text
        XCTAssertTrue(prompt.contains("as Shap-E generated") || prompt.contains("plants as"))
        XCTAssertFalse(prompt.contains("stand = longest"))
        let pins = DirectorSystemPrompt.pinPlanText
        XCTAssertTrue(pins.contains("plants as generated"))
        XCTAssertTrue(pins.contains("fillsToNeighbors is always false"))
        XCTAssertTrue(pins.contains("closed mound") || pins.contains("closed mound or clump"))
        XCTAssertFalse(pins.contains("guitar case lies flat"))
        XCTAssertFalse(pins.contains("fillsToNeighbors is true ONLY"))
        let scene = DirectorSystemPrompt.scenePinPlanText
        XCTAssertTrue(scene.contains("knight under a pale moon"))
        XCTAssertTrue(scene.contains("lifted pin"))
        XCTAssertTrue(scene.contains("plants as generated"))
        XCTAssertFalse(scene.contains("guitar case lies flat"))
        let tags = DirectorSystemPrompt.contentTagText
        XCTAssertTrue(tags.contains("knight floor"))
        XCTAssertTrue(tags.contains("moon airborne"))
        XCTAssertTrue(tags.localizedCaseInsensitiveContains("euler"))
        XCTAssertFalse(tags.contains("guitar case lies flat"))
    }
}
