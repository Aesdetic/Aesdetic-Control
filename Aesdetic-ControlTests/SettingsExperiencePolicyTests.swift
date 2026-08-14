import Foundation
import Testing
@testable import Aesdetic_Control

struct SettingsExperiencePolicyTests {
    @Test func customProductsUseDeviceTerminology() {
        #expect(ProductType.sunriseLamp.settingsObjectName == "Lamp")
        #expect(ProductType.generic.settingsObjectName == "Device")
        #expect(ProductType.deskStrip.settingsObjectName == "Device")
        #expect(ProductType.ambianceStrip.settingsObjectName == "Device")
        #expect(ProductType.ceilingPanel.settingsObjectName == "Device")
    }

    @Test func advancedGroupsCoverEveryVisibleFirmwareCategoryOnce() async throws {
        let manifest = try await WLEDAdvancedSettingsService().loadManifest()
        let visibleCategoryIDs = Set(
            manifest.categories.map(\.id)
                .filter { !WLEDSettingsExperiencePolicy.hiddenCategoryIDs.contains($0) }
        )
        let groupedIDs = WLEDSettingsExperiencePolicy.advancedGroups.flatMap(\.categoryIDs)

        #expect(Set(groupedIDs) == visibleCategoryIDs)
        #expect(Set(groupedIDs).count == groupedIDs.count)
    }

    @Test func everyFirmwareFieldHasPlacementRiskAndCustomerWording() async throws {
        let manifest = try await WLEDAdvancedSettingsService().loadManifest()
        var resolvedFieldCount = 0

        for category in manifest.categories {
            #expect(!WLEDSettingsExperiencePolicy.categorySummary(category.id).isEmpty)
            for field in category.fields {
                let placement = WLEDSettingsExperiencePolicy.placement(
                    categoryID: category.id,
                    field: field
                )
                let label = WLEDSettingsExperiencePolicy.friendlyLabel(
                    categoryID: category.id,
                    field: field
                )
                let presentation = WLEDSettingsExperiencePolicy.presentation(
                    categoryID: category.id,
                    field: field
                )

                #expect(!placement.reason.isEmpty)
                #expect(!label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(presentation.label == label)
                #expect(presentation.placement == placement)
                resolvedFieldCount += 1
            }
        }

        #expect(resolvedFieldCount == 191)
    }

    @Test func customerBehaviorFieldsUseFriendlyControlsAndUnits() async throws {
        let manifest = try await WLEDAdvancedSettingsService().loadManifest()
        let category = try #require(manifest.category(id: "led-hardware"))
        let power = try #require(category.fields.first { $0.key == "BO" })
        let brightness = try #require(category.fields.first { $0.key == "BF" })
        let transition = try #require(category.fields.first { $0.key == "TD" })

        let powerPresentation = WLEDSettingsExperiencePolicy.presentation(categoryID: category.id, field: power)
        let brightnessPresentation = WLEDSettingsExperiencePolicy.presentation(categoryID: category.id, field: brightness)
        let transitionPresentation = WLEDSettingsExperiencePolicy.presentation(categoryID: category.id, field: transition)

        #expect(powerPresentation.control == .toggle)
        #expect(brightnessPresentation.control == .slider)
        #expect(brightnessPresentation.unit == "%")
        #expect(transitionPresentation.control == .segmented)
        #expect(transitionPresentation.unit == "ms")
        #expect([powerPresentation, brightnessPresentation, transitionPresentation].allSatisfy {
            $0.placement.layer == .simple && $0.placement.destination == .device
        })
    }

    @Test func wledBrowserAppearanceIsHiddenButDeviceNameIsCustomerFacing() async throws {
        let manifest = try await WLEDAdvancedSettingsService().loadManifest()
        let category = try #require(manifest.category(id: "user-interface"))
        let nameField = try #require(category.fields.first { $0.key == "DS" })
        let simplifiedUI = try #require(category.fields.first { $0.key == "SU" })

        #expect(WLEDSettingsExperiencePolicy.placement(categoryID: category.id, field: nameField).layer == .simple)
        #expect(WLEDSettingsExperiencePolicy.placement(categoryID: category.id, field: nameField).destination == .device)
        #expect(WLEDSettingsExperiencePolicy.placement(categoryID: category.id, field: simplifiedUI).layer == .hidden)
    }

    @Test func reconnectAndHardwareChangesAreNeverClassifiedAsSafe() async throws {
        let manifest = try await WLEDAdvancedSettingsService().loadManifest()

        for category in manifest.categories {
            for field in category.fields {
                let decision = WLEDSettingsExperiencePolicy.placement(categoryID: category.id, field: field)
                if field.sideEffects.contains(.wifiReconnect) {
                    #expect(decision.risk == .reconnect)
                }
                if field.sideEffects.contains(.ledReinit) || field.sideEffects.contains(.segmentRebuild) {
                    #expect(decision.risk == .hardware)
                }
                if field.sideEffects.contains(.securityLockout) {
                    #expect(decision.risk == .lockout)
                }
            }
        }
    }
}
