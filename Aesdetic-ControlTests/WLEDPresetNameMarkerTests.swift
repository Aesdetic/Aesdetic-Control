import Foundation
import Testing
@testable import Aesdetic_Control

struct WLEDPresetNameMarkerTests {
    @Test("marker parser strips app metadata from display names")
    func markerParserStripsDisplayName() {
        let marker = AesdeticWLEDPresetNameMarker.parse("[AD saved-color] Color 1")

        #expect(marker?.kind == .savedColor)
        #expect(marker?.displayName == "Color 1")
        #expect(marker?.ownershipToken == nil)
        #expect(AesdeticWLEDPresetNameMarker.displayName(from: "[AD saved-color] Color 1") == "Color 1")
    }

    @Test("marker parser accepts versioned legacy form")
    func markerParserAcceptsVersionedForm() {
        let marker = AesdeticWLEDPresetNameMarker.parse("[AD:v1 automation-step] Morning Step 1")

        #expect(marker?.kind == .automationStep)
        #expect(marker?.displayName == "Morning Step 1")
        #expect(marker?.ownershipToken == nil)
    }

    @Test("marker writer and parser preserve scoped automation ownership")
    func markerWriterPreservesOwnership() throws {
        let ownerId = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let marked = AesdeticWLEDPresetNameMarker.markedName(
            "Morning",
            as: .automation,
            ownerId: ownerId
        )
        let marker = AesdeticWLEDPresetNameMarker.parse(marked)

        #expect(marked == "[AD:o=111111112222 automation] Morning")
        #expect(marker?.kind == .automation)
        #expect(marker?.ownershipToken == "111111112222")
    }

    @Test("marker writer replaces existing marker")
    func markerWriterReplacesExistingMarker() {
        let marked = AesdeticWLEDPresetNameMarker.markedName("[AD automation-step] Old", as: .savedTransition)

        #expect(marked == "[AD saved-transition] Old")
    }

    @Test("rename helper preserves existing marker type")
    func renameHelperPreservesExistingMarkerType() {
        let renamed = AesdeticWLEDPresetNameMarker.preservingExistingMarker(
            from: "[AD saved-animation] Rainbow",
            newDisplayName: "Glow"
        )

        #expect(renamed == "[AD saved-animation] Glow")
    }
}
