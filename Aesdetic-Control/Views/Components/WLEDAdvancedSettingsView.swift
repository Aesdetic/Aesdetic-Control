import SwiftUI

struct WLEDAdvancedSettingsView: View {
    let device: WLEDDevice
    let contentBottomPadding: CGFloat
    let initialCategoryID: String?
    let openWLEDPath: (String) -> Void
    let openTimeSchedules: () -> Void
    let onHeaderStatusChange: (String) -> Void
    let onCategoryDetailActiveChange: (Bool) -> Void
    let onHeaderChromeChange: (EmbeddedSettingsHeaderChrome) -> Void
    let onHeaderActionsChange: (EmbeddedSettingsHeaderActions) -> Void
    let onFactoryResetComplete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var manifest: WLEDSettingsManifest?
    @State private var selectedCategoryID: String?
    @State private var draft: WLEDSettingsDraft?
    @State private var ledOutputDraft: WLEDLEDOutputDraft?
    @State private var pinInfo: WLEDPinInfo?
    @State private var matrixInfo: WLEDMatrixInfo?
    @State private var securityAboutInfo: WLEDSecurityAboutInfo?
    @State private var usermodsDraft: WLEDUsermodsDraft?
    @State private var isLoading: Bool = false
    @State private var isSaving: Bool = false
    @State private var isRestarting: Bool = false
    @State private var isFactoryResetting: Bool = false
    @State private var showRestartConfirmation: Bool = false
    @State private var showRiskySaveConfirmation: Bool = false
    @State private var showFactoryResetWarning: Bool = false
    @State private var showFactoryResetTypedConfirmation: Bool = false
    @State private var factoryResetConfirmationText: String = ""
    @State private var message: String?
    @State private var messageIsError: Bool = false
    @State private var lastSaveStatus: String = "Settings"
    @State private var lastPublishedHeaderStatus: String?
    @State private var lastPublishedHeaderChrome: EmbeddedSettingsHeaderChrome?
    @State private var supportedAdvancedFeatures: Set<String> = []
    @State private var expandedSectionIDs: Set<String> = []
    @State private var expandedHelpFieldIDs: Set<String> = []
    @State private var categorySearchText: String = ""
    @State private var searchTargetCategoryID: String?
    @State private var searchTargetSection: String?
    @State private var searchTargetFieldKey: String?
    @State private var categoryLoadTask: Task<Void, Never>?
    @State private var showUnsavedBackConfirmation: Bool = false
    @State private var showAdvancedFirmwareUpdateOptions: Bool = false

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }
    private let categoryNavigationAnimation = Animation.snappy(duration: 0.28, extraBounce: 0.02)
    private let restartCommandWindowNanos: UInt64 = 2_000_000_000
    private let restartProbeInitialDelayNanos: UInt64 = 2_500_000_000
    private let restartProbeIntervalNanos: UInt64 = 1_000_000_000
    private let restartProbeMaxSeconds: TimeInterval = 20
    private var espNowSupported: Bool { supportedAdvancedFeatures.contains("WLED_ENABLE_ESPNOW") }
    private var dmxInputSupported: Bool { supportedAdvancedFeatures.contains("WLED_ENABLE_DMX_INPUT") }

    private enum RestartCommandOutcome {
        case completed
        case timedOut
        case failed(String)
    }

    private struct AdvancedSearchResult: Identifiable {
        let category: WLEDSettingsCategoryDescriptor
        let section: String?
        let fieldKey: String?
        let title: String
        let context: String

        var id: String {
            [category.id, section ?? "category", fieldKey ?? title].joined(separator: "|")
        }
    }

    var body: some View {
        presentedContent
    }

    private var observedContent: some View {
        settingsContent
        .task {
            await loadManifest()
        }
        .onChange(of: draft?.isDirty ?? false) { _, _ in
            publishHeaderStatus()
        }
        .onChange(of: ledOutputDraft?.isDirty ?? false) { _, _ in
            publishHeaderStatus()
        }
        .onChange(of: usermodsDraft?.isDirty ?? false) { _, _ in
            publishHeaderStatus()
        }
        .onChange(of: selectedCategoryID) { _, newValue in
            onCategoryDetailActiveChange(newValue != nil)
            publishHeaderChrome()
        }
        .onDisappear {
            categoryLoadTask?.cancel()
            onCategoryDetailActiveChange(false)
            onHeaderChromeChange(.settings)
            onHeaderActionsChange(.none)
        }
    }

    private var standardAlertContent: some View {
        observedContent
        .alert(
            "Restart WLED?",
            isPresented: $showRestartConfirmation,
        ) {
            Button("Restart WLED", role: .destructive) {
                Task { await restartDevice() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("WLED will disconnect briefly while it restarts.")
        }
        .alert(
            riskySaveConfirmationTitle,
            isPresented: $showRiskySaveConfirmation,
        ) {
            Button("Save Changes") {
                Task { await saveCurrentDraft() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(riskySaveConfirmationMessage)
        }
    }

    private var factoryResetAlertContent: some View {
        standardAlertContent
        .alert(
            "Factory Reset Device?",
            isPresented: $showFactoryResetWarning
        ) {
            Button("Continue", role: .destructive) {
                factoryResetConfirmationText = ""
                Task { @MainActor in
                    await Task.yield()
                    showFactoryResetTypedConfirmation = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently erases WLED settings, presets, and WiFi credentials. The device will restart in setup mode and must be connected again.")
        }
        .alert(
            "Confirm Factory Reset",
            isPresented: $showFactoryResetTypedConfirmation
        ) {
            TextField("Type RESET", text: $factoryResetConfirmationText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Erase Everything", role: .destructive) {
                Task { await factoryResetDevice() }
            }
            .disabled(factoryResetConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "RESET")
            Button("Cancel", role: .cancel) {
                factoryResetConfirmationText = ""
            }
        } message: {
            Text("Type RESET to erase this device and begin setup again.")
        }
    }

    private var presentedContent: some View {
        factoryResetAlertContent
        .confirmationDialog(
            "Unsaved Changes",
            isPresented: $showUnsavedBackConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save Changes") {
                Task {
                    if await saveCurrentDraft() {
                        performCloseCategory()
                    }
                }
            }
            Button("Discard Changes", role: .destructive) {
                discardChanges()
                performCloseCategory()
            }
            Button("Continue Editing", role: .cancel) {}
        } message: {
            Text("Save or discard your changes before leaving this category.")
        }
        .sheet(isPresented: $showAdvancedFirmwareUpdateOptions) {
            WLEDFirmwareAdvancedUpdateView(device: device)
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        Group {
            if isLoading && manifest == nil {
                ScrollView(.vertical, showsIndicators: false) {
                    loadingCard("Loading advanced settings...")
                        .padding(.horizontal, 16)
                        .padding(.bottom, contentBottomPadding)
                }
            } else if let manifest {
                if selectedCategoryID == nil {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            categoryList(manifest)
                        }
                            .padding(.horizontal, 16)
                            .padding(.bottom, contentBottomPadding)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading),
                        removal: .move(edge: .leading)
                    ))
                } else {
                    categoryDetail(manifest)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .trailing)
                        ))
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    SettingsCard(title: "Advanced Settings") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(message ?? "Could not load the advanced settings definitions.")
                                .font(AppTypography.style(.caption))
                                .settingsForegroundStyle(.primary)
                            Button(action: { Task { await loadManifest() } }) {
                                SettingsButton(title: "Retry", icon: "arrow.clockwise")
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, contentBottomPadding)
                }
            }
        }
    }

    private func categoryList(_ manifest: WLEDSettingsManifest) -> some View {
        let categories = nativeAdvancedCategories(from: manifest)
        let query = categorySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleCategories = categories.filter { categoryMatchesSearch($0, query: query) }
        let searchResults = advancedSearchResults(in: categories, query: query)
        return VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Advanced Settings")
                    .font(AppTypography.style(.title2, weight: .semibold))
                    .foregroundStyle(theme.settingsText(.primary))
                    .accessibilityAddTraits(.isHeader)

                SettingsDescriptionText(
                    markdown: "**Advanced controls:** Installation, troubleshooting, and firmware features. Everyday controls stay in the main tabs."
                )

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(theme.settingsText(.secondary))
                    TextField("Search advanced settings", text: $categorySearchText)
                        .font(AppTypography.style(.subheadline))
                        .foregroundStyle(theme.settingsText(.primary))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    Color.clear.appLiquidGlass(
                        role: .highContrast,
                        cornerRadius: 10,
                        highContrastDarkTintOpacity: AppTheme.settingsGlassDarkTint(.control, for: colorScheme)
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(theme.divider, lineWidth: 1)
                )
            }

            if query.isEmpty {
                ForEach(WLEDSettingsExperiencePolicy.advancedGroups) { group in
                    let groupCategories = visibleCategories.filter { group.categoryIDs.contains($0.id) }

                    if !groupCategories.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            AdvancedSettingsGroupHeading(group: group)

                            ForEach(groupCategories) { category in
                                Button {
                                    selectCategory(category)
                                } label: {
                                    WLEDAdvancedCategoryRow(category: category)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("advanced-category-\(category.id)")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                ForEach(searchResults) { result in
                    Button {
                        selectCategory(
                            result.category,
                            searchSection: result.section,
                            searchFieldKey: result.fieldKey
                        )
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.title)
                                    .font(AppTypography.style(.subheadline, weight: .semibold))
                                    .foregroundStyle(theme.settingsText(.primary))
                                Text(result.context)
                                    .font(AppTypography.style(.caption))
                                    .foregroundStyle(theme.settingsText(.secondary))
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(AppTypography.style(.caption, weight: .bold))
                                .foregroundStyle(theme.settingsText(.secondary))
                        }
                        .padding(14)
                        .settingsDetailControlBackground(cornerRadius: 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("advanced-search-result-\(result.id)")
                }
            }

            if !query.isEmpty, searchResults.isEmpty {
                Text("No advanced settings match “\(query)”.")
                    .font(AppTypography.style(.subheadline))
                    .foregroundColor(theme.settingsText(.secondary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
            }
        }
        .onAppear {
            lastSaveStatus = "Settings"
            onCategoryDetailActiveChange(false)
            onHeaderChromeChange(.settings)
            onHeaderActionsChange(.none)
            publishHeaderStatus()
        }
    }

    private func advancedSearchResults(
        in categories: [WLEDSettingsCategoryDescriptor],
        query: String
    ) -> [AdvancedSearchResult] {
        guard !query.isEmpty else { return [] }
        var results: [AdvancedSearchResult] = []
        var seen: Set<String> = []

        for category in categories {
            let groupTitle = WLEDSettingsExperiencePolicy.group(containing: category.id)?.title ?? "Advanced Settings"
            let categoryMatches = category.title.localizedCaseInsensitiveContains(query)
                || WLEDSettingsExperiencePolicy.categorySummary(category.id).localizedCaseInsensitiveContains(query)
                || groupTitle.localizedCaseInsensitiveContains(query)

            let matchingFields = category.fields.filter { field in
                field.section.localizedCaseInsensitiveContains(query)
                    || field.key.localizedCaseInsensitiveContains(query)
                    || WLEDSettingsExperiencePolicy.friendlyLabel(categoryID: category.id, field: field)
                        .localizedCaseInsensitiveContains(query)
                    || (WLEDSettingsExperiencePolicy.presentation(categoryID: category.id, field: field).help?
                        .localizedCaseInsensitiveContains(query) ?? false)
            }

            if matchingFields.isEmpty, categoryMatches {
                results.append(AdvancedSearchResult(
                    category: category,
                    section: nil,
                    fieldKey: nil,
                    title: category.title,
                    context: groupTitle
                ))
                continue
            }

            for field in matchingFields {
                let label = WLEDSettingsExperiencePolicy.friendlyLabel(categoryID: category.id, field: field)
                let identity = "\(category.id)|\(field.section)|\(label)"
                guard seen.insert(identity).inserted else { continue }
                results.append(AdvancedSearchResult(
                    category: category,
                    section: field.section,
                    fieldKey: field.key,
                    title: label,
                    context: "\(category.title) · \(field.section.trimmingCharacters(in: CharacterSet(charactersIn: ":")))"
                ))
            }
        }

        return Array(results.prefix(50))
    }

    private func categoryMatchesSearch(
        _ category: WLEDSettingsCategoryDescriptor,
        query: String
    ) -> Bool {
        guard !query.isEmpty else { return true }
        let groupTitle = WLEDSettingsExperiencePolicy.group(containing: category.id)?.title ?? ""
        return category.title.localizedCaseInsensitiveContains(query)
            || WLEDSettingsExperiencePolicy.categorySummary(category.id)
                .localizedCaseInsensitiveContains(query)
            || groupTitle.localizedCaseInsensitiveContains(query)
            || category.fields.contains { field in
                field.section.localizedCaseInsensitiveContains(query)
                    || WLEDSettingsExperiencePolicy.friendlyLabel(
                        categoryID: category.id,
                        field: field
                    ).localizedCaseInsensitiveContains(query)
            }
    }

    private func nativeAdvancedCategories(from manifest: WLEDSettingsManifest) -> [WLEDSettingsCategoryDescriptor] {
        manifest.categories.filter { category in
            guard !WLEDSettingsExperiencePolicy.hiddenCategoryIDs.contains(category.id) else { return false }
            guard WLEDSettingsExperiencePolicy.group(containing: category.id) != nil else { return false }
            guard let requiredFeature = category.requiresFeature else { return true }
            return supportedAdvancedFeatures.contains(requiredFeature)
        }
    }

    private func categoryDetail(_ manifest: WLEDSettingsManifest) -> some View {
        let category = selectedCategoryID.flatMap { manifest.category(id: $0) }
        return Group {
            if let category {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            categoryContentHeading(category)

                        if isLoading && draft == nil {
                            loadingCard("Loading \(category.title)...")
                        } else if let draft {
                            categorySupportStrip(category)
                            if category.id == "wifi-network" {
                                wifiNetworkSection
                            } else if category.id == "pin-info" {
                                pinInfoSection
                            } else if category.id == "2d-configuration" {
                                matrixInfoSection
                            } else if category.id == "sync-interfaces" {
                                syncInterfacesSection
                            } else if category.id == "time-macros" {
                                timeMacrosSection
                            } else if category.id == "security-updates" {
                                securityUpdatesSection
                            } else if category.id == "dmx-output" {
                                dmxOutputSection
                            } else if category.id == "usermods" {
                                usermodsSection
                            } else {
                                ForEach(Array(groupedFields(for: draft.category).enumerated()), id: \.element.section) { index, group in
                                    advancedSectionCard(title: group.section, isPrimary: index == 0) {
                                        VStack(spacing: 12) {
                                            ForEach(group.fields) { field in
                                                if category.id == "led-hardware" {
                                                    ledHardwareFieldRow(field)
                                                } else {
                                                    advancedFieldRow(field)
                                                }
                                            }
                                        }
                                    }
                                    if category.id == "led-hardware", group.section == "LED setup" {
                                        ledOutputsSection
                                        ledDiagnosticsSection
                                    }
                                    if category.id == "led-hardware", group.section == "LED outputs:" {
                                        colorOrderOverridesSection
                                    }
                                    if category.id == "led-hardware", group.section == "Buttons" {
                                        hardwareButtonsParityNote
                                    }
                                    if category.id == "led-hardware", group.section == "Advanced" {
                                        ledConfigTemplateSection
                                    }
                                }
                            }
                        }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, contentBottomPadding)
                    }
                    .onChange(of: isLoading) { _, loading in
                        guard !loading else { return }
                        scrollToSearchTarget(using: proxy)
                    }
                }
            }
        }
    }

    private func categoryContentHeading(_ category: WLEDSettingsCategoryDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(WLEDSettingsExperiencePolicy.group(containing: category.id)?.title ?? "Advanced Settings")
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundStyle(theme.settingsText(.secondary))
                .textCase(.uppercase)
                .tracking(0.8)

            Text(category.title)
                .font(AppTypography.style(.title2, weight: .semibold))
                .foregroundStyle(theme.settingsText(.primary))
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            SettingsDescriptionText(
                markdown: WLEDSettingsExperiencePolicy.categorySummary(category.id)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private func groupedFields(for category: WLEDSettingsCategoryDescriptor) -> [(section: String, fields: [WLEDSettingDescriptor])] {
        guard category.id == "led-hardware" else {
            return category.groupedFields
        }
        let hiddenKeys: Set<String> = ["AS", "PPL", "data2"]
        return category.groupedFields.compactMap { group in
            let fields = group.fields.filter { !hiddenKeys.contains($0.key) }
            return fields.isEmpty ? nil : (group.section, fields)
        }
    }

    private func categorySupportStrip(_ category: WLEDSettingsCategoryDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { openWLEDPath(category.webPath) }) {
                SettingsInlineButton(title: "Open Original WLED Page", icon: "globe")
            }

            if !currentSideEffects.isEmpty {
                WLEDAdvancedSideEffectsView(effects: currentSideEffects)
            }

            if let message {
                Text(message)
                    .font(AppTypography.style(.caption, weight: .medium))
                    .foregroundStyle(messageIsError ? theme.status.warning : theme.settingsText(.secondary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if currentSideEffects.contains(.reboot) || lastSaveStatus == "Restart Required" {
                SettingsDescriptionText(
                    markdown: "**Hardware not updated?** Restart WLED after saving."
                )
            }
        }
    }

    @ViewBuilder
    private func advancedSectionCard<Content: View>(
        title: String,
        isPrimary: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let categoryID = draft?.category.id ?? selectedCategoryID ?? "advanced"
        let sectionID = "\(categoryID)|\(title)"
        let isExpanded = expandedSectionIDs.contains(sectionID)
        let isSearchTarget = searchTargetCategoryID == categoryID
            && normalizedSectionName(searchTargetSection) == normalizedSectionName(title)
        let summary = WLEDSettingsExperiencePolicy.sectionDescription(categoryID: categoryID, section: title)

        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.22, extraBounce: 0.01)) {
                    if isExpanded {
                        expandedSectionIDs.remove(sectionID)
                    } else {
                        expandedSectionIDs.insert(sectionID)
                    }
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title.trimmingCharacters(in: CharacterSet(charactersIn: ":")))
                            .font(AppTypography.style(.headline, weight: .semibold))
                            .foregroundStyle(theme.settingsText(.primary))
                            .accessibilityAddTraits(.isHeader)

                        if let summary {
                            SettingsDescriptionText(markdown: summary)
                        }

                        if isSearchTarget,
                           let fieldKey = searchTargetFieldKey,
                           let field = draft?.category.fields.first(where: { $0.key == fieldKey }) {
                            Text("Matched field: \(WLEDSettingsExperiencePolicy.friendlyLabel(categoryID: categoryID, field: field))")
                                .font(AppTypography.style(.caption, weight: .semibold))
                                .foregroundStyle(theme.status.info)
                        }
                    }

                    Spacer(minLength: 8)

                    if sectionHasErrors(title) {
                        settingsSectionBadge("Check", color: theme.status.warning)
                    } else if sectionIsModified(title) {
                        settingsSectionBadge("Modified", color: theme.settingsText(.primary))
                    } else if isSearchTarget {
                        settingsSectionBadge("Match", color: theme.status.info)
                    }

                    Image(systemName: "chevron.down")
                        .font(AppTypography.style(.caption, weight: .bold))
                        .foregroundStyle(theme.settingsText(.secondary))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(isExpanded ? "expanded" : "collapsed")")
            .accessibilityIdentifier("advanced-section-\(sectionID)")

            if isExpanded {
                Divider().overlay(theme.divider)
                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .settingsDetailControlBackground(cornerRadius: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSearchTarget ? theme.status.info.opacity(0.9) : .clear, lineWidth: 2)
        )
        .id("advanced-section-anchor-\(sectionID)")
        .onAppear {
            if isPrimary {
                expandedSectionIDs.insert(sectionID)
            }
            if sectionHasErrors(title) {
                expandedSectionIDs.insert(sectionID)
            }
        }
    }

    private func normalizedSectionName(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":")))
            .lowercased()
    }

    private func scrollToSearchTarget(using proxy: ScrollViewProxy) {
        guard let categoryID = searchTargetCategoryID,
              categoryID == selectedCategoryID,
              let section = searchTargetSection else { return }
        let sectionID = "\(categoryID)|\(section)"
        expandedSectionIDs.insert(sectionID)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard selectedCategoryID == categoryID else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo("advanced-section-anchor-\(sectionID)", anchor: .top)
            }
        }
    }

    private func settingsSectionBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(AppTypography.style(.caption2, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func sectionIsModified(_ section: String) -> Bool {
        if draft?.changedFields.contains(where: { $0.section == section }) == true {
            return true
        }
        if section == "LED outputs" || section == "LED outputs:" {
            return ledOutputDraft?.isDirty == true
        }
        if draft?.category.id == "usermods", section == "Installed Extensions" {
            return usermodsDraft?.isDirty == true
        }
        return false
    }

    private func sectionHasErrors(_ section: String) -> Bool {
        let errors = draft?.validationErrors() ?? [:]
        let fieldKeys = Set(draft?.category.fields.filter { $0.section == section }.map(\.key) ?? [])
        if !fieldKeys.isDisjoint(with: errors.keys) {
            return true
        }
        if section == "LED outputs" || section == "LED outputs:" {
            return !(ledOutputDraft?.validationErrors().isEmpty ?? true)
        }
        return false
    }

    @ViewBuilder
    private func advancedFieldRow(_ field: WLEDSettingDescriptor, labelOverride: String? = nil) -> some View {
        let categoryID = draft?.category.id ?? ""
        let presentation = WLEDSettingsExperiencePolicy.presentation(categoryID: categoryID, field: field)
        let displayLabel = labelOverride ?? presentation.label
        let helpID = "\(categoryID)|\(field.key)"
        if draft?.category.id == "wifi-network", field.key == "CM" {
            WLEDMDNSAddressFieldRow(
                field: field,
                text: stringBinding(for: field),
                error: draft?.validationErrors()[field.key]
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
            switch field.control {
            case .toggle:
                Toggle(isOn: boolBinding(for: field)) {
                    fieldLabel(displayLabel, help: presentation.help, helpID: helpID)
                }
                    .settingsToggleStyle()
                    .disabled(!field.isWritableByGenericConfig)
            case .number:
                HStack(spacing: 10) {
                    fieldLabel(displayLabel, help: presentation.help, helpID: helpID)
                    Spacer()
                    WLEDAdvancedBufferedTextField(
                        text: stringBinding(for: field),
                        keyboardType: .numbersAndPunctuation,
                        alignment: .trailing,
                        isDisabled: !field.isWritableByGenericConfig
                    )
                        .frame(width: 92)
                    if let unit = presentation.unit {
                        Text(unit)
                            .font(AppTypography.style(.caption, weight: .medium))
                            .foregroundStyle(theme.settingsText(.secondary))
                    }
                }
            case .select:
                HStack(spacing: 10) {
                    fieldLabel(displayLabel, help: presentation.help, helpID: helpID)
                    Spacer(minLength: 8)
                    Picker(displayLabel, selection: stringBinding(for: field)) {
                        ForEach(selectOptions(for: field)) { option in
                            Text(optionDisplayLabel(option, for: field)).tag(option.value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(theme.settingsText(.primary))
                    .disabled(!field.isWritableByGenericConfig || (field.options ?? []).isEmpty)
                }
            case .secret:
                WLEDSecretFieldRow(
                    field: field,
                    state: draft?.secretStates[field.key],
                    replacementText: secretReplacementBinding(for: field),
                    canReplace: canReplaceSecret(field)
                )
            case .file:
                if draft?.category.id == "led-hardware", field.key == "data2" {
                    Button(action: { openWLEDPath("/settings/leds") }) {
                        SettingsInlineButton(title: "Open Config Template on WLED", icon: "globe")
                    }
                    .buttonStyle(.plain)
                } else {
                    readonlyRow(field: field, value: "Use WLED page")
                }
            case .text:
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel(displayLabel, help: presentation.help, helpID: helpID)
                    WLEDAdvancedBufferedTextField(
                        placeholder: field.placeholder ?? "",
                        text: stringBinding(for: field),
                        keyboardType: .default,
                        alignment: .leading,
                        isDisabled: !field.isWritableByGenericConfig
                    )
                }
            }

            if let error = draft?.validationErrors()[field.key] {
                Text(error)
                    .font(AppTypography.style(.caption))
                    .foregroundStyle(theme.status.negative)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if expandedHelpFieldIDs.contains(helpID), let help = presentation.help {
                SettingsDescriptionText(markdown: help)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
        }
    }

    private func fieldLabel(_ label: String, help: String?, helpID: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(AppTypography.style(.subheadline, weight: .medium))
                .foregroundStyle(theme.settingsText(.primary))
                .fixedSize(horizontal: false, vertical: true)

            if help != nil {
                Button {
                    if expandedHelpFieldIDs.contains(helpID) {
                        expandedHelpFieldIDs.remove(helpID)
                    } else {
                        expandedHelpFieldIDs.insert(helpID)
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .font(AppTypography.style(.caption, weight: .semibold))
                        .foregroundStyle(theme.settingsText(.secondary))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About \(label)")
            }
        }
    }

    private func selectOptions(for field: WLEDSettingDescriptor) -> [WLEDSettingOption] {
        var options = field.options ?? []
        let currentValue = draft?.values[field.key]?.stringValue ?? ""

        if !currentValue.isEmpty && !options.contains(where: { $0.value == currentValue }) {
            options.append(WLEDSettingOption(label: fallbackOptionLabel(for: currentValue), value: currentValue))
        }

        return options
    }

    private func optionDisplayLabel(_ option: WLEDSettingOption, for field: WLEDSettingDescriptor) -> String {
        let label = option.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label != "-" else {
            return fallbackOptionLabel(for: option.value)
        }

        switch label.lowercased() {
        case "unused":
            return "Unused"
        case "none":
            return "None"
        case "disabled":
            return "Disabled"
        default:
            return label
        }
    }

    private func fallbackOptionLabel(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "-1" { return "Unused" }
        if trimmed.isEmpty { return "None" }
        return trimmed
    }

    private var wifiNetworkSection: some View {
        VStack(spacing: 12) {
            if let group = draft?.category.groupedFields.first(where: { $0.section == "Wireless network" }) {
                advancedSectionCard(title: "Wireless network", isPrimary: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(primaryWiFiFields(from: group.fields)) { field in
                            advancedFieldRow(field)
                        }

                        disclosureSection(
                            title: "Advanced network details",
                            sectionID: "wifi-advanced-network",
                            summary: "BSSID, static IP, gateway, and subnet. Leave these alone unless your network requires manual addressing."
                        ) {
                            ForEach(advancedWiFiFields(from: group.fields)) { field in
                                advancedFieldRow(field)
                            }
                        }
                    }
                }
            }

            ForEach(draft?.category.groupedFields.filter { $0.section != "Wireless network" } ?? [], id: \.section) { group in
                advancedSectionCard(title: group.section) {
                    VStack(alignment: .leading, spacing: 12) {
                        if group.section == "ESP-NOW Wireless", !espNowSupported {
                            unsupportedFirmwareText("**Support not confirmed:** WLED may save ESP-NOW, but this firmware might not apply it.")
                        }

                        ForEach(wifiVisibleFields(in: group.fields)) { field in
                            if group.section == "DNS & mDNS", field.key == "D0" {
                                WLEDDottedIPAddressFieldRow(
                                    title: "DNS server address",
                                    placeholder: "8.8.8.8",
                                    text: dottedIPAddressBinding(keys: ["D0", "D1", "D2", "D3"]),
                                    isDisabled: !field.isWritableByGenericConfig,
                                    error: wifiIPAddressError(keys: ["D0", "D1", "D2", "D3"])
                                )
                            } else {
                                advancedFieldRow(field)
                            }

                            if let description = wifiFieldDescription(for: field.key) {
                                Text(description)
                                    .font(AppTypography.style(.caption))
                                    .settingsForegroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }

    private func wifiVisibleFields(in fields: [WLEDSettingDescriptor]) -> [WLEDSettingDescriptor] {
        fields.filter { field in
            !["D1", "D2", "D3"].contains(field.key)
        }
    }

    private func primaryWiFiFields(from fields: [WLEDSettingDescriptor]) -> [WLEDSettingDescriptor] {
        fields.filter { field in
            field.key.hasPrefix("CS") || field.key.hasPrefix("PW")
        }
    }

    private func advancedWiFiFields(from fields: [WLEDSettingDescriptor]) -> [WLEDSettingDescriptor] {
        fields.filter { field in
            !(field.key.hasPrefix("CS") || field.key.hasPrefix("PW"))
        }
    }

    private func dottedIPAddressBinding(keys: [String]) -> Binding<String> {
        Binding(
            get: {
                keys.map { key in
                    let value = Int(draft?.values[key]?.numberValue ?? 0)
                    return String(max(0, min(255, value)))
                }
                .joined(separator: ".")
            },
            set: { newValue in
                let components = parseIPAddressComponents(newValue)
                for (index, key) in keys.enumerated() {
                    draft?.setValue(.number(Double(components[index])), for: key)
                }
                message = nil
                publishHeaderStatus()
            }
        )
    }

    private func parseIPAddressComponents(_ value: String) -> [Int] {
        let parts = value
            .split(separator: ".", omittingEmptySubsequences: false)
            .prefix(4)
            .map { part -> Int in
                let digits = part.filter(\.isNumber)
                return max(0, min(255, Int(digits) ?? 0))
            }

        return Array(parts + Array(repeating: 0, count: max(0, 4 - parts.count)))
    }

    private func wifiIPAddressError(keys: [String]) -> String? {
        let errors = draft?.validationErrors() ?? [:]
        return keys.compactMap { errors[$0] }.first
    }

    @ViewBuilder
    private func disclosureSection<Content: View>(
        title: String,
        sectionID: String,
        summary: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isExpanded = expandedSectionIDs.contains(sectionID)
        Button {
            withAnimation(.snappy(duration: 0.22, extraBounce: 0.01)) {
                if isExpanded {
                    expandedSectionIDs.remove(sectionID)
                } else {
                    expandedSectionIDs.insert(sectionID)
                }
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .settingsForegroundStyle(.primary)
                    SettingsDescriptionText(markdown: summary)
                }
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(AppTypography.style(.caption, weight: .bold))
                    .settingsForegroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if isExpanded {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func wifiFieldDescription(for key: String) -> String? {
        switch key {
        case "CM": return "Local browser address. WLED adds .local automatically."
        case "AS": return "Fallback access point name used if the \(device.productType.settingsObjectNameLowercased) cannot join WiFi."
        case "AP": return "Access point password. Leave blank to preserve the current WLED value."
        case "AC": return "WiFi channel used by the fallback access point."
        case "AB": return "Controls when WLED starts its fallback access point."
        case "TX": return "Transmit power. Lower values can reduce range; high values are not always more stable."
        case "WS": return "Disabling sleep can improve reliability but uses more power."
        case "RE": return "ESP-NOW is for remotes or ESP-NOW sync. Leave off if unused."
        default: return nil
        }
    }

    private func unsupportedFirmwareText(_ text: String) -> some View {
        SettingsDescriptionText(markdown: text, tone: .warning)
    }

    private func ledHardwareFieldRow(_ field: WLEDSettingDescriptor) -> AnyView {
        if field.key == "TD" {
            return AnyView(VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("Default transition time")
                        .font(AppTypography.style(.subheadline, weight: .medium))
                        .settingsForegroundStyle(.primary)
                    Spacer()
                    WLEDAdvancedBufferedTextField(
                        text: Binding(
                            get: {
                                let milliseconds = (draft?.values[field.key]?.numberValue ?? 0) * 100
                                return milliseconds.rounded() == milliseconds ? String(Int(milliseconds)) : String(milliseconds)
                            },
                            set: { newValue in
                                let milliseconds = Double(newValue) ?? 0
                                draft?.setValue(.number(milliseconds / 100), for: field.key)
                                message = nil
                                publishHeaderStatus()
                            }
                        ),
                        keyboardType: .numbersAndPunctuation,
                        alignment: .trailing,
                        isDisabled: !field.isWritableByGenericConfig
                    )
                    .frame(width: 92)
                    Text("ms")
                        .font(AppTypography.style(.caption, weight: .semibold))
                        .settingsForegroundStyle(.secondary)
                }
                ledHardwareDescriptionText("**Default fade:** Shown in milliseconds to match WLED's page.")
            })
        }

        return AnyView(VStack(alignment: .leading, spacing: 6) {
            advancedFieldRow(field, labelOverride: ledHardwareLabelOverride(for: field.key))
            if let description = ledHardwareFieldDescription(for: field.key) {
                ledHardwareDescriptionText(description)
            }
        })
    }

    private func ledHardwareDescriptionText(_ text: String) -> some View {
        SettingsDescriptionText(markdown: text)
    }

    private func ledHardwareLabelOverride(for key: String) -> String? {
        switch key {
        case "TH": return "Use harmonic colors in Random palettes"
        case "TP": return "Random Palette Cycle Time"
        case "TL": return "Default duration"
        case "TB": return "Default target brightness"
        case "FR": return "Target refresh rate"
        default: return nil
        }
    }

    private func ledHardwareFieldDescription(for key: String) -> String? {
        switch key {
        case "BF": return "**Brightness cap:** Scales maximum output before normal brightness control."
        case "ABL": return "**Automatic limiting:** Lowers brightness near the configured power limit."
        case "MA": return "**Supply rating:** Enter the power supply limit in mA, not theoretical strip draw."
        case "MS": return "**Segment layout:** Creates one segment per physical output after saving."
        case "GC": return "**Recommended:** Makes color output appear more visually linear."
        case "GB": return "**Optional:** Brightness gamma is not ideal for every setup."
        case "GV": return "**Gamma curve:** Used by color and brightness correction."
        case "CCT": return "**White balance:** For strips with a white channel."
        case "AW": return "**White channel:** Chooses how WLED derives white from RGB."
        case "CR": return "**Estimated CCT:** Derives color temperature from RGB."
        case "IC": return "**Athom hardware:** CCT option for supported bulbs."
        case "CB": return "**White blending:** Use 0 for two-wire reverse-polarity CCT strips."
        case "IP": return "**Button wiring:** Disables WLED's internal pull-up/down resistor."
        case "TT": return "**Touch sensitivity:** Threshold for capacitive inputs."
        case "IR": return "**Receiver pin:** `-1` means unused."
        case "IT": return "**Remote profile:** Selects the IR protocol and button map."
        case "MSO": return "**Main segment only:** Limits IR changes to that segment."
        case "RL": return "**Relay pin:** `-1` means unused."
        case "RM": return "**Invert output:** Reverses relay on/off behavior."
        case "RO": return "**Open drain:** Use only when supported by the relay circuit."
        case "BO": return "**Power recovery:** Turns LEDs on after power returns or WLED restarts."
        case "CA": return "**Startup level:** Brightness from 1 to 255."
        case "BP": return "**Startup preset:** `0` means none."
        case "TH": return "**Color harmony:** Coordinates colors in random palettes."
        case "TP": return "**Cycle time:** Seconds between random palette changes."
        case "TL": return "**Duration:** Default timed-light length in minutes."
        case "TB": return "**End brightness:** Target when timed light finishes."
        case "TW": return "**Completion mode:** Fade or switch at the end."
        case "PB": return "**Palette edges:** Controls wrapping during moving effects."
        case "FR": return "**Refresh target:** Higher is not always smoother on limited hardware."
        default: return nil
        }
    }

    private var ledOutputsSection: some View {
        advancedSectionCard(title: "LED outputs") {
            VStack(alignment: .leading, spacing: 14) {
                SettingsDescriptionText(
                    markdown: "**Each physical output:** Type, current estimate, color order, pins, length, skip, and white-channel behavior."
                )

                if let ledOutputDraft {
                    let validationErrors = ledOutputDraft.validationErrors()
                    ForEach(Array(ledOutputDraft.outputs.enumerated()), id: \.element.id) { index, output in
                        let outputID = output.id
                        WLEDLEDOutputEditor(
                            index: index,
                            output: Binding(
                                get: {
                                    self.ledOutputDraft?.outputs.first { $0.id == outputID } ?? output
                                },
                                set: { newValue in
                                    self.ledOutputDraft?.updateOutput(id: outputID, with: newValue)
                                    message = nil
                                    publishHeaderStatus()
                                }
                            ),
                            canRemove: ledOutputDraft.outputs.count > 1,
                            validationErrors: validationErrors,
                            onRemove: {
                                self.ledOutputDraft?.removeOutput(id: outputID)
                                message = nil
                                publishHeaderStatus()
                            }
                        )
                    }

                    Button {
                        self.ledOutputDraft?.addOutput()
                        message = nil
                        publishHeaderStatus()
                    } label: {
                        SettingsInlineButton(title: "Add Output", icon: "plus")
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                        Text("Loading LED outputs...")
                            .font(AppTypography.style(.caption))
                            .settingsForegroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var hardwareButtonsParityNote: some View {
        advancedSectionCard(title: "Physical button rows") {
            VStack(alignment: .leading, spacing: 10) {
                SettingsDescriptionText(
                    markdown: "**Button wiring:** Add or remove inputs on the WLED page to keep its pin-conflict checks."
                )
                Button(action: { openWLEDPath("/settings/leds") }) {
                    SettingsInlineButton(title: "Open Button Setup on WLED", icon: "globe")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var ledConfigTemplateSection: some View {
        advancedSectionCard(title: "Config template") {
            VStack(alignment: .leading, spacing: 10) {
                SettingsDescriptionText(
                    markdown: "**Template file:** Choose it on the WLED page so firmware can validate it."
                )
                Button(action: { openWLEDPath("/settings/leds") }) {
                    SettingsInlineButton(title: "Open Config Template on WLED", icon: "globe")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var pinInfoSection: some View {
        VStack(spacing: 12) {
            advancedSectionCard(title: "GPIO pins", isPrimary: true) {
                VStack(alignment: .leading, spacing: 10) {
                    if let pinInfo {
                        Text("\(pinInfo.pins.count) pins reported · \(pinInfo.allocatedCount) used · \(pinInfo.availableCount) available")
                            .font(AppTypography.style(.caption))
                            .settingsForegroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        WLEDPinInfoTable(pins: pinInfo.pins)
                    } else {
                        loadingPinInfoRow
                    }
                }
            }
        }
    }

    private var loadingPinInfoRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(.white)
            Text("Loading live pin info...")
                .font(AppTypography.style(.caption))
                .settingsForegroundStyle(.secondary)
        }
    }

    private var matrixInfoSection: some View {
        VStack(spacing: 12) {
            advancedSectionCard(title: "2D setup", isPrimary: true) {
                VStack(alignment: .leading, spacing: 10) {
                    if let matrixInfo {
                        InfoRow(label: "Strip or panel", value: matrixInfo.mode.displayName)
                        InfoRow(label: "Matrix dimensions", value: matrixInfo.dimensionsText)
                        InfoRow(label: "Number of panels", value: matrixInfo.panelCountText)
                        if let totalLEDs = matrixInfo.totalLEDs {
                            InfoRow(label: "Total LEDs", value: "\(totalLEDs)")
                        }
                        if let maxPanels = matrixInfo.maxPanels {
                            InfoRow(label: "Firmware max panels", value: "\(maxPanels)")
                        }
                        SettingsDescriptionText(
                            markdown: "**Read only:** Saving a 2D layout rebuilds segments and LED maps; native writes await matrix testing."
                        )
                    } else {
                        loadingMatrixInfoRow
                    }
                }
            }

            if let matrixInfo, matrixInfo.mode == .matrix {
                if matrixInfo.panels.isEmpty {
                    advancedSectionCard(title: "LED panel layout") {
                        SettingsDescriptionText(
                            markdown: "**Layout unavailable:** Inspect or repair the panel layout on the WLED page."
                        )
                    }
                } else {
                    advancedSectionCard(title: "LED panel layout") {
                        VStack(spacing: 10) {
                            ForEach(matrixInfo.panels) { panel in
                                WLEDMatrixPanelRow(panel: panel)
                            }
                        }
                    }
                }
            }
        }
    }

    private var timeMacrosSection: AnyView {
        AnyView(VStack(spacing: 12) {
            advancedSectionCard(title: "Time setup", isPrimary: true) {
                VStack(spacing: 12) {
                    timeField("NT", label: "Get time from NTP server")
                    timeField("NS", label: "NTP server")
                    timeField("CF", label: "Use 24h format")
                    timeField("TZ", label: "Time zone")
                    timeField("UO", label: "UTC offset")
                    timeCoordinateField("LT", label: "Latitude")
                    timeCoordinateField("LN", label: "Longitude")
                }
            }

            advancedSectionCard(title: "Clock") {
                VStack(alignment: .leading, spacing: 12) {
                    timeField("OL", label: "Analog Clock overlay")
                    timeField("O1", label: "First LED")
                    timeField("O2", label: "Last LED")
                    timeField("OM", label: "12h LED")
                    timeField("O5", label: "Show 5min marks")
                    timeField("OS", label: "Seconds as trail")
                    timeField("OB", label: "Show only if LEDs are solid black")
                    timeField("CE", label: "Countdown Mode")
                    Text("Countdown Goal")
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .settingsForegroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    timeCountdownGoalFields
                    timeDescriptionText("**Countdown target:** Year uses the last two digits after 20, matching WLED.")
                }
            }

            advancedSectionCard(title: "Timer & Alexa Presets") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Macro Presets")
                        .font(AppTypography.style(.headline, weight: .semibold))
                        .settingsForegroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SettingsDescriptionText(
                        markdown: "**Preset actions:** Use `0` for WLED's default behavior."
                    )
                    timeField("MC", label: "Countdown-Over Preset")
                    timeField("MN", label: "Timed-Light-Over Preset")
                    timeField("A0", label: "Alexa On Preset")
                    timeField("A1", label: "Alexa Off Preset")
                }
            }

            advancedSectionCard(title: "Button Action Presets") {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsDescriptionText(
                        markdown: "**Dynamic button actions:** Edit on the WLED page to preserve button types and existing assignments."
                    )
                    Button(action: { openWLEDPath("/settings/time") }) {
                        SettingsInlineButton(title: "Open Time & Macros on WLED", icon: "globe")
                    }
                    .buttonStyle(.plain)
                }
            }

            advancedSectionCard(title: "Time-Controlled Presets") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Managed by Time & Schedules")
                        .font(AppTypography.style(.headline, weight: .semibold))
                        .settingsForegroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SettingsDescriptionText(
                        markdown: "**Use Aesdetic for normal schedules:** Open WLED only for custom weekday or date ranges."
                    )
                    Button(action: openTimeSchedules) {
                        SettingsInlineButton(title: "Open Time & Schedules", icon: "clock")
                    }
                    .buttonStyle(.plain)
                }
            }
        })
    }

    private func timeField(_ key: String, label: String? = nil) -> AnyView {
        guard let field = draft?.category.fields.first(where: { $0.key == key }) else {
            return AnyView(EmptyView())
        }

        return AnyView(VStack(alignment: .leading, spacing: 6) {
            advancedFieldRow(field, labelOverride: label)
            if let description = timeFieldDescription(for: key) {
                timeDescriptionText(description)
            }
        })
    }

    private func timeCoordinateField(_ key: String, label: String) -> AnyView {
        guard let field = draft?.category.fields.first(where: { $0.key == key }) else {
            return AnyView(EmptyView())
        }

        return AnyView(VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(label)
                    .font(AppTypography.style(.subheadline, weight: .medium))
                    .settingsForegroundStyle(.primary)
                Spacer()
                Picker("\(label) hemisphere", selection: timeHemisphereBinding(for: key)) {
                    ForEach(timeHemisphereOptions(for: key), id: \.self) { hemisphere in
                        Text(hemisphere).tag(hemisphere)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .disabled(!field.isWritableByGenericConfig)
                .frame(width: 74, alignment: .trailing)
                WLEDAdvancedBufferedTextField(
                    text: timeCoordinateMagnitudeBinding(for: field),
                    keyboardType: .numbersAndPunctuation,
                    alignment: .trailing,
                    isDisabled: !field.isWritableByGenericConfig
                )
                .frame(width: 104)
            }
            if let error = draft?.validationErrors()[field.key] {
                Text(error)
                    .font(AppTypography.style(.caption))
                    .settingsForegroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let description = timeFieldDescription(for: key) {
                timeDescriptionText(description)
            }
        })
    }

    private var timeCountdownGoalFields: AnyView {
        AnyView(VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Date")
                    .font(AppTypography.style(.subheadline, weight: .medium))
                    .settingsForegroundStyle(.primary)
                Text("20")
                    .font(AppTypography.style(.subheadline, weight: .medium))
                    .settingsForegroundStyle(.secondary)
                timeCompactNumberField("CY", label: "YY", width: 58)
                timeCompactNumberField("CI", label: "MM", width: 58)
                timeCompactNumberField("CD", label: "DD", width: 58)
            }

            HStack(spacing: 8) {
                Text("Time")
                    .font(AppTypography.style(.subheadline, weight: .medium))
                    .settingsForegroundStyle(.primary)
                timeCompactNumberField("CH", label: "HH", width: 58)
                timeCompactNumberField("CM", label: "MM", width: 58)
                timeCompactNumberField("CS", label: "SS", width: 58)
            }
        })
    }

    private func timeHemisphereOptions(for key: String) -> [String] {
        key == "LT" ? ["N", "S"] : ["E", "W"]
    }

    private func timeHemisphereBinding(for key: String) -> Binding<String> {
        Binding(
            get: {
                let value = draft?.values[key]?.numberValue ?? 0
                if key == "LT" {
                    return value < 0 ? "S" : "N"
                }
                return value < 0 ? "W" : "E"
            },
            set: { newValue in
                let magnitude = abs(draft?.values[key]?.numberValue ?? 0)
                let negative = newValue == "S" || newValue == "W"
                draft?.setValue(.number(negative ? -magnitude : magnitude), for: key)
                message = nil
                publishHeaderStatus()
            }
        )
    }

    private func timeCoordinateMagnitudeBinding(for field: WLEDSettingDescriptor) -> Binding<String> {
        Binding(
            get: {
                let value = abs(draft?.values[field.key]?.numberValue ?? 0)
                if value.rounded() == value {
                    return String(Int(value))
                }
                return String(value)
            },
            set: { newValue in
                let existing = draft?.values[field.key]?.numberValue ?? 0
                let magnitude = abs(Double(newValue) ?? 0)
                let signed = existing < 0 ? -magnitude : magnitude
                draft?.setValue(.number(signed), for: field.key)
                message = nil
                publishHeaderStatus()
            }
        )
    }

    private func timeCompactNumberField(_ key: String, label: String, width: CGFloat) -> AnyView {
        guard let field = draft?.category.fields.first(where: { $0.key == key }) else {
            return AnyView(EmptyView())
        }

        return AnyView(VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(AppTypography.style(.caption2, weight: .semibold))
                .settingsForegroundStyle(.secondary)
            WLEDAdvancedBufferedTextField(
                text: stringBinding(for: field),
                keyboardType: .numberPad,
                alignment: .center,
                isDisabled: !field.isWritableByGenericConfig
            )
            .frame(width: width)
            if let error = draft?.validationErrors()[field.key] {
                Text(error)
                    .font(AppTypography.style(.caption2))
                    .settingsForegroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        })
    }

    private func timeDescriptionText(_ text: String) -> AnyView {
        AnyView(SettingsDescriptionText(markdown: text))
    }

    private func timeFieldDescription(for key: String) -> String? {
        switch key {
        case "NT": return "**Automatic time:** Keeps WLED's clock synced from the network."
        case "NS": return "**Time server:** Keep the default unless your network uses a local NTP server."
        case "CF": return "**Clock format:** Affects WLED's UI and LED clock displays."
        case "TZ": return "**Timezone rule:** Includes daylight saving where available."
        case "UO": return "**Fine adjustment:** Extra seconds when the timezone cannot match the location."
        case "LT": return "**Solar position:** North is positive; south is negative."
        case "LN": return "**Solar position:** East is positive; west is negative."
        case "OL": return "**Analog overlay:** Displays clock hands on the LEDs."
        case "O1": return "**Clock range:** First LED used by the overlay."
        case "O2": return "**Clock range:** Last LED used by the overlay."
        case "OM": return "**12 o'clock position:** LED treated as the top of the clock."
        case "O5": return "Adds marks at five-minute positions."
        case "OS": return "Uses the seconds indicator as a trail."
        case "OB": return "Only shows the clock overlay when the LEDs are otherwise black."
        case "CE": return "Enables countdown mode toward the countdown goal below."
        case "MC": return "Preset WLED runs when the countdown reaches zero."
        case "MN": return "Preset WLED runs when timed light finishes."
        case "A0": return "Preset WLED runs when Alexa turns the device on."
        case "A1": return "Preset WLED runs when Alexa turns the device off."
        default: return nil
        }
    }

    private var securityUpdatesSection: AnyView {
        AnyView(VStack(spacing: 12) {
            advancedSectionCard(title: "Security & Update Setup", isPrimary: true) {
                VStack(alignment: .leading, spacing: 12) {
                    securityField("PIN", label: "Settings PIN")
                    securityWarningText("**Local HTTP:** Never reuse a sensitive PIN or password here.")
                    securityField("NO", label: "Lock wireless (OTA) software update")
                    securityField("OP", label: "OTA passphrase")
                    securityField("OW", label: "Deny access to WiFi settings if locked")

                    Divider().overlay(Color.white.opacity(0.14))

                    SettingsDescriptionText(
                        markdown: "**Erases everything:** Factory reset remains on the WLED page to prevent accidental use.",
                        tone: .warning
                    )
                    Button(action: { openWLEDPath("/settings/sec") }) {
                        SettingsInlineButton(title: "Open Security & Updates on WLED", icon: "globe")
                    }
                    .buttonStyle(.plain)
                }
            }

            advancedSectionCard(title: "Software Update") {
                VStack(alignment: .leading, spacing: 12) {
                    securityField("AO", label: "Enable ArduinoOTA")
                    securityField("SU", label: "Only allow update from same network/WiFi")
                    securityWarningText("**Safer default:** Disable ArduinoOTA when not updating and keep update access local.")
                    Button(action: { showAdvancedFirmwareUpdateOptions = true }) {
                        SettingsInlineButton(title: "Advanced Update Options", icon: "wrench.and.screwdriver")
                    }
                    .buttonStyle(.plain)
                    Button(action: { openWLEDPath("/update") }) {
                        SettingsInlineButton(title: "Open Manual OTA Update", icon: "arrow.up.circle")
                    }
                    .buttonStyle(.plain)
                }
            }

            advancedSectionCard(title: "Backup & Restore") {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsDescriptionText(
                        markdown: "**Replaces current data:** Restore on the WLED page so firmware can validate the file.",
                        tone: .warning
                    )
                    Text("WLED backups do not include passwords.")
                        .font(AppTypography.style(.caption, weight: .semibold))
                        .foregroundColor(.orange.opacity(0.94))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: { openWLEDPath("/presets.json") }) {
                        SettingsInlineButton(title: "Backup Presets", icon: "square.and.arrow.down")
                    }
                    .buttonStyle(.plain)
                    Button(action: { openWLEDPath("/cfg.json") }) {
                        SettingsInlineButton(title: "Backup Configuration", icon: "square.and.arrow.down")
                    }
                    .buttonStyle(.plain)
                    Button(action: { openWLEDPath("/settings/sec") }) {
                        SettingsInlineButton(title: "Restore Presets on WLED", icon: "globe")
                    }
                    .buttonStyle(.plain)
                    Button(action: { openWLEDPath("/settings/sec") }) {
                        SettingsInlineButton(title: "Restore Configuration on WLED", icon: "globe")
                    }
                    .buttonStyle(.plain)
                }
            }

            advancedSectionCard(title: "About") {
                VStack(alignment: .leading, spacing: 10) {
                    if let securityAboutInfo {
                        Text(securityAboutInfo.installedVersionText)
                            .font(AppTypography.style(.body, weight: .semibold))
                            .settingsForegroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let boardText = securityAboutInfo.boardText {
                            securityAboutRow("Board", boardText)
                        }
                        if let brand = securityAboutInfo.brand {
                            securityAboutRow("Brand", brand)
                        }
                        if let core = securityAboutInfo.core {
                            securityAboutRow("Core", core)
                        }
                        if let freeHeap = securityAboutInfo.freeHeap {
                            securityAboutRow("Free heap", "\(freeHeap) B")
                        }
                        if let uptime = securityAboutInfo.uptime {
                            securityAboutRow("Uptime", formattedUptime(uptime))
                        }
                    } else {
                        Text("About details could not be loaded from WLED right now.")
                            .font(AppTypography.style(.caption))
                            .settingsForegroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button(action: { openWLEDPath("/settings/sec") }) {
                        SettingsInlineButton(title: "Open About on WLED", icon: "globe")
                    }
                    .buttonStyle(.plain)
                }
            }

            advancedSectionCard(title: "Recovery") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsDescriptionText(
                        markdown: "**Permanent reset:** Erases all WLED settings, presets, and WiFi credentials. Back up configuration and presets before continuing.",
                        tone: .warning
                    )

                    Button(action: { showFactoryResetWarning = true }) {
                        DangerSettingsButton(
                            title: isFactoryResetting ? "Resetting Device..." : "Factory Reset Device",
                            icon: "exclamationmark.triangle",
                            level: .danger
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStartFactoryReset)

                    if hasUnsavedChanges {
                        SettingsDescriptionText(
                            markdown: "**Unsaved changes:** Save or discard this category before resetting."
                        )
                    }
                }
            }
        })
    }

    private func securityField(_ key: String, label: String? = nil) -> AnyView {
        guard let field = draft?.category.fields.first(where: { $0.key == key }) else {
            return AnyView(EmptyView())
        }

        return AnyView(VStack(alignment: .leading, spacing: 6) {
            advancedFieldRow(field, labelOverride: label)
            if let description = securityFieldDescription(for: key) {
                securityDescriptionText(description)
            }
        })
    }

    private func securityWarningText(_ text: String) -> AnyView {
        AnyView(SettingsDescriptionText(markdown: text, tone: .warning))
    }

    private func securityAboutRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(AppTypography.style(.caption, weight: .semibold))
                .settingsForegroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(AppTypography.style(.caption))
                .settingsForegroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formattedUptime(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func securityDescriptionText(_ text: String) -> AnyView {
        AnyView(SettingsDescriptionText(markdown: text))
    }

    private func securityFieldDescription(for key: String) -> String? {
        switch key {
        case "PIN": return "**Settings lock:** Leave blank to preserve it; enter exactly 4 digits to replace it."
        case "NO": return "**OTA lock:** Requires the passphrase for wireless firmware updates."
        case "OP": return "**OTA passphrase:** Leave blank to preserve the current value."
        case "OW": return "**WiFi lock:** Also blocks WLED web changes to network settings."
        case "AO": return "**ArduinoOTA:** Enable only for update tools that require it."
        case "SU": return "**Local only:** Accept updates from the same network or subnet."
        default: return nil
        }
    }

    private var dmxOutputSection: AnyView {
        AnyView(VStack(spacing: 12) {
            advancedSectionCard(title: "DMX Output", isPrimary: true) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsDescriptionText(
                        markdown: "**Requires DMX output firmware:** Values save through WLED's DMX page."
                    )

                    dmxOutputField("PU", label: "Proxy Universe")
                    dmxOutputField("CN", label: "Channels per fixture")
                }
            }

            advancedSectionCard(title: "Fixture Layout") {
                VStack(alignment: .leading, spacing: 12) {
                    dmxOutputField("CS", label: "Start channel")
                    dmxOutputField("CG", label: "Spacing between start channels")
                    dmxOutputField("SL", label: "DMX fixtures start LED")

                    SettingsDescriptionText(
                        markdown: "**Address overlap:** Spacing must be at least the channels per fixture.",
                        tone: .warning
                    )
                }
            }

            advancedSectionCard(title: "Channel Functions") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsDescriptionText(
                        markdown: "**Channel map preserved:** Edit the dynamic 15-channel map on the WLED page."
                    )

                    Button(action: { openWLEDPath("/dmxmap") }) {
                        SettingsInlineButton(title: "Open DMX Map on WLED", icon: "globe")
                    }
                    .buttonStyle(.plain)
                }
            }
        })
    }

    private func dmxOutputField(_ key: String, label: String? = nil) -> AnyView {
        guard let field = draft?.category.fields.first(where: { $0.key == key }) else {
            return AnyView(EmptyView())
        }

        return AnyView(VStack(alignment: .leading, spacing: 6) {
            advancedFieldRow(field, labelOverride: label)
            if let description = dmxOutputFieldDescription(for: key) {
                Text(description)
                    .font(AppTypography.style(.caption))
                    .settingsForegroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        })
    }

    private func dmxOutputFieldDescription(for key: String) -> String? {
        switch key {
        case "PU": return "Forwards one E1.31 universe to DMX. Leave 0 to disable E1.31-to-DMX proxy mode."
        case "CN": return "Number of DMX channels each LED fixture consumes. WLED supports up to 15 here."
        case "CS": return "First DMX channel used by the first fixture."
        case "CG": return "Distance between fixture start channels. Larger gaps can make fixture addresses easier to remember."
        case "SL": return "First WLED LED index represented by DMX fixtures."
        default: return nil
        }
    }

    private var usermodsSection: AnyView {
        AnyView(VStack(spacing: 12) {
            advancedSectionCard(title: "Global I2C & SPI", isPrimary: true) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsDescriptionText(
                        markdown: "**Shared hardware buses:** Pin conflicts can cause WLED to set the entire bus to unused."
                    )

                    Text("I2C GPIOs (HW)")
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .settingsForegroundStyle(.primary)
                    usermodPinPickerField("SDA", label: "SDA")
                    usermodPinPickerField("SCL", label: "SCL")

                    Divider().overlay(Color.white.opacity(0.14))

                    Text("SPI GPIOs (HW)")
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .settingsForegroundStyle(.primary)
                    usermodsDescriptionText("Only changeable on ESP32 firmware builds.")
                    usermodPinPickerField("MOSI", label: "MOSI")
                    usermodPinPickerField("MISO", label: "MISO")
                    usermodPinPickerField("SCLK", label: "SCLK")

                    Divider().overlay(Color.white.opacity(0.14))

                    usermodField("RBT", label: "Reboot after save")
                    usermodsDescriptionText("**Action only:** Restarts WLED after saving so bus-pin changes apply.")
                }
            }

            advancedSectionCard(title: "Installed Extensions") {
                VStack(alignment: .leading, spacing: 12) {
                    if let usermodsDraft, !usermodsDraft.modules.isEmpty {
                        ForEach(usermodsDraft.modules) { module in
                            WLEDUsermodModuleEditor(module: usermodModuleBinding(module))
                        }
                    } else {
                        SettingsDescriptionText(
                            markdown: "**No Usermod config yet:** WLED may initialize defaults after its Usermods page is saved once."
                        )
                    }

                    SettingsDescriptionText(
                        markdown: "**Firmware-generated controls:** Changes can affect connected hardware."
                    )

                    Button(action: { openWLEDPath("/settings/um") }) {
                        SettingsInlineButton(title: "Open Usermods on WLED", icon: "globe")
                    }
                    .buttonStyle(.plain)
                }
            }
        })
    }

    private func usermodModuleBinding(_ module: WLEDUsermodModuleDraft) -> Binding<WLEDUsermodModuleDraft> {
        Binding(
            get: {
                usermodsDraft?.modules.first(where: { $0.id == module.id }) ?? module
            },
            set: { updatedModule in
                guard let index = usermodsDraft?.modules.firstIndex(where: { $0.id == updatedModule.id }) else { return }
                usermodsDraft?.modules[index] = updatedModule
                message = nil
                publishHeaderStatus()
            }
        )
    }

    private func usermodField(_ key: String, label: String? = nil) -> AnyView {
        guard let field = draft?.category.fields.first(where: { $0.key == key }) else {
            return AnyView(EmptyView())
        }

        return AnyView(VStack(alignment: .leading, spacing: 6) {
            advancedFieldRow(field, labelOverride: label)
            if let description = usermodFieldDescription(for: key) {
                usermodsDescriptionText(description)
            }
        })
    }

    private func usermodPinPickerField(_ key: String, label: String) -> AnyView {
        guard let field = draft?.category.fields.first(where: { $0.key == key }) else {
            return AnyView(EmptyView())
        }

        return AnyView(VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(label)
                    .font(AppTypography.style(.subheadline, weight: .medium))
                    .settingsForegroundStyle(.primary)
                Spacer()
                Picker(label, selection: Binding(
                    get: {
                        String(Int(draft?.values[key]?.numberValue ?? -1))
                    },
                    set: { newValue in
                        draft?.setValue(.number(Double(Int(newValue) ?? -1)), for: key)
                        message = nil
                        publishHeaderStatus()
                    }
                )) {
                    ForEach(syncPinPickerOptions(for: field), id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .disabled(!field.isWritableByGenericConfig)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            SettingsDescriptionText(markdown: "**Unused:** Saved to WLED as `-1`.")
            if let description = usermodFieldDescription(for: key) {
                usermodsDescriptionText(description)
            }
        })
    }

    private func usermodsDescriptionText(_ text: String) -> AnyView {
        AnyView(SettingsDescriptionText(markdown: text))
    }

    private func usermodFieldDescription(for key: String) -> String? {
        switch key {
        case "SDA": return "**I2C data:** Pair with SCL, or set both to unused."
        case "SCL": return "**I2C clock:** Pair with SDA, or set both to unused."
        case "MOSI": return "**SPI output:** Data sent from WLED to connected hardware."
        case "MISO": return "**SPI input:** Leave unused when the extension does not need it."
        case "SCLK": return "**SPI clock:** Required with MOSI to allocate the bus."
        case "RBT": return "**Restart after save:** Applies hardware-bus changes immediately."
        default: return nil
        }
    }

    private var syncInterfacesSection: AnyView {
        AnyView(VStack(spacing: 12) {
            advancedSectionCard(title: "WLED Broadcast", isPrimary: true) {
                VStack(spacing: 12) {
                    syncField("UP", label: "UDP Port")
                    syncField("U2", label: "2nd Port")
                }
            }

            advancedSectionCard(title: "ESP-NOW") {
                VStack(alignment: .leading, spacing: 10) {
                    if espNowSupported {
                        syncField("EN", label: "Use ESP-NOW sync")
                        SettingsDescriptionText(
                            markdown: "**Enable first:** Turn on ESP-NOW in WiFi & Network.",
                            tone: .warning
                        )
                    } else {
                        unsupportedFirmwareText("**Support not confirmed:** WLED may save ESP-NOW, but this firmware might not apply it.")
                        syncField("EN", label: "Use ESP-NOW sync")
                    }
                }
            }

            advancedSectionCard(title: "Sync groups") {
                VStack(alignment: .leading, spacing: 12) {
                    syncGroupMaskRow(title: "Send", key: "GS")
                    syncGroupMaskRow(title: "Receive", key: "GR")
                }
            }

            advancedSectionCard(title: "Receive") {
                VStack(spacing: 12) {
                    syncField("RB", label: "Brightness")
                    syncField("RC", label: "Color")
                    syncField("RX", label: "Effects")
                    syncField("RP", label: "Palette")
                    syncField("SO", label: "Segment options")
                    syncField("SG", label: "Bounds")
                }
            }

            advancedSectionCard(title: "Send") {
                VStack(spacing: 12) {
                    syncField("SS", label: "Enable Sync on start")
                    syncField("SD", label: "Send notifications on direct change")
                    syncField("SB", label: "Send notifications on button press or IR")
                    syncField("SA", label: "Send Alexa notifications")
                    syncField("SH", label: "Send Philips Hue change notifications")
                    syncField("UR", label: "UDP packet retransmissions")
                    syncWarningText("Reboot required to apply changes.")
                }
            }

            advancedSectionCard(title: "Instance List") {
                VStack(spacing: 12) {
                    syncField("NL", label: "Enable instance list")
                    syncField("NB", label: "Make this instance discoverable")
                }
            }

            advancedSectionCard(title: "Realtime") {
                VStack(spacing: 12) {
                    syncField("RD", label: "Receive UDP realtime")
                    syncField("MO", label: "Use main segment only")
                    syncField("RLM", label: "Respect LED Maps")

                    Divider().overlay(Color.white.opacity(0.14))

                    Text("Network DMX input")
                        .font(AppTypography.style(.headline, weight: .semibold))
                        .settingsForegroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    syncProtocolTypeRow
                    syncField("EM", label: "Multicast")
                    syncField("EU", label: "Start universe")
                    syncWarningText("Reboot required. Check out LedFx!")
                    syncField("ES", label: "Skip out-of-sequence packets")
                    syncField("DA", label: "DMX start address")
                    syncField("XX", label: "DMX segment spacing")
                    syncField("PY", label: "E1.31 port priority")
                    syncField("DM", label: "DMX mode")
                    syncScaledNumberField("ET", label: "Timeout", multiplier: 100, unit: "ms")
                    syncField("FB", label: "Force max brightness")
                    syncField("RG", label: "Disable realtime gamma correction")
                    syncField("WO", label: "Realtime LED offset")

                    Divider().overlay(Color.white.opacity(0.14))

                    Text("Wired DMX Input")
                        .font(AppTypography.style(.headline, weight: .semibold))
                        .settingsForegroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !dmxInputSupported {
                        unsupportedFirmwareText("**Support not confirmed:** WLED may save DMX input, but this firmware might not apply it.")
                    }
                    syncPinPickerField("IDMR", label: "DMX RX Pin", suffix: "RO")
                    syncPinPickerField("IDMT", label: "DMX TX Pin", suffix: "DI")
                    syncPinPickerField("IDME", label: "DMX Enable Pin", suffix: "RE+DE")
                    syncField("IDMP", label: "DMX Port")
                    syncWarningText("Reboot required to apply changes.")
                    syncWarningText("This firmware build may not include DMX output support.")
                }
            }

            advancedSectionCard(title: "Alexa Voice Assistant") {
                VStack(spacing: 12) {
                    syncField("AL", label: "Emulate Alexa device")
                    syncField("AI", label: "Alexa invocation name")
                    syncField("AP", label: "Also emulate devices to call the first presets")
                }
            }

            advancedSectionCard(title: "MQTT and Hue") {
                VStack(alignment: .leading, spacing: 8) {
                    syncWarningText("MQTT and Hue sync connect to external hosts.")
                    SettingsDescriptionText(
                        markdown: "**For best responsiveness:** Use MQTT or Hue sync, not both."
                    )
                }
            }

            advancedSectionCard(title: "MQTT") {
                VStack(spacing: 12) {
                    syncField("MQ", label: "Enable MQTT")
                    syncField("MS", label: "Broker")
                    syncField("MQPORT", label: "Port")
                    SettingsDescriptionText(
                        markdown: "**Unsecured connection:** Use a broker password created only for this device.",
                        tone: .warning
                    )
                    syncField("MQUSER", label: "Username")
                    syncField("MQPASS", label: "Password")
                    syncField("MQCID", label: "Client ID")
                    syncField("MD", label: "Device Topic")
                    syncField("MG", label: "Group Topic")
                    syncField("BM", label: "Publish on button press")
                    syncField("RT", label: "Retain brightness & color messages")
                    syncWarningText("Reboot required to apply changes.")
                }
            }

            advancedSectionCard(title: "Philips Hue") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsDescriptionText(
                        markdown: "**Hue details:** Find the bridge IP and light number in the Hue app's About section."
                    )
                    syncField("HL", label: "Poll Hue light")
                    syncScaledNumberField("HI", label: "Every", multiplier: 100, unit: "ms")
                    syncField("HP", label: "Enable Hue polling")
                    syncField("HO", label: "Receive On/Off")
                    syncField("HB", label: "Receive Brightness")
                    syncField("HC", label: "Receive Color")
                    syncIPAddressFields(title: "Hue Bridge IP", keys: ["H0", "H1", "H2", "H3"])
                    SettingsDescriptionText(
                        markdown: "**First connection:** Press the bridge pushlink button, then save."
                    )
                }
            }

            advancedSectionCard(title: "Serial") {
                VStack(spacing: 12) {
                    syncField("BD", label: "Baud rate")
                    syncWarningText("Reboot required to apply changes.")
                }
            }
        })
    }

    private func syncField(_ key: String, label: String? = nil) -> AnyView {
        guard let field = draft?.category.fields.first(where: { $0.key == key }) else {
            return AnyView(EmptyView())
        }

        return AnyView(VStack(alignment: .leading, spacing: 6) {
            advancedFieldRow(field, labelOverride: label)
            if let description = syncFieldDescription(for: key) {
                syncDescriptionText(description)
            }
        })
    }

    private func syncWarningText(_ text: String) -> AnyView {
        AnyView(SettingsDescriptionText(markdown: text, tone: .warning))
    }

    private func syncDescriptionText(_ text: String) -> AnyView {
        AnyView(SettingsDescriptionText(markdown: text))
    }

    private func syncGroupMaskRow(title: String, key: String) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .settingsForegroundStyle(.primary)

            SettingsDescriptionText(
                markdown: title == "Send"
                    ? "**Broadcast to:** Choose the groups that receive this device's changes."
                    : "**Listen to:** Choose the groups this device accepts changes from."
            )

            HStack(spacing: 7) {
                ForEach(0..<8, id: \.self) { bit in
                    let isEnabled = syncGroupBitEnabled(key: key, bit: bit)
                    Button {
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            toggleSyncGroupBit(key: key, bit: bit)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Text("\(bit + 1)")
                                .font(AppTypography.style(.caption2, weight: .semibold))
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isEnabled ? Color.blue : Color.white.opacity(0.94))
                                if isEnabled {
                                    Image(systemName: "checkmark")
                                        .font(AppTypography.style(.caption, weight: .bold))
                                        .settingsForegroundStyle(.primary)
                                }
                            }
                            .frame(width: 24, height: 24)
                        }
                        .foregroundColor(isEnabled ? .blue : .white.opacity(0.88))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(nil, value: Int(draft?.values[key]?.numberValue ?? 0))
        })
    }

    private func syncGroupBitEnabled(key: String, bit: Int) -> Bool {
        let mask = Int(draft?.values[key]?.numberValue ?? 0)
        return mask & (1 << bit) != 0
    }

    private func toggleSyncGroupBit(key: String, bit: Int) {
        var mask = Int(draft?.values[key]?.numberValue ?? 0)
        let value = 1 << bit
        if mask & value == 0 {
            mask |= value
        } else {
            mask &= ~value
        }
        draft?.setValue(.number(Double(mask)), for: key)
        message = nil
        publishHeaderStatus()
    }

    private var syncProtocolTypeRow: AnyView {
        AnyView(VStack(alignment: .leading, spacing: 6) {
            Text("Type")
                .font(AppTypography.style(.subheadline, weight: .medium))
                .settingsForegroundStyle(.primary)
            Picker("Type", selection: Binding(
                get: {
                    let port = Int(draft?.values["EP"]?.numberValue ?? 0)
                    if port == 5568 || port == 6454 {
                        return String(port)
                    }
                    return "0"
                },
                set: { value in
                    if let port = Int(value), port > 0 {
                        draft?.setValue(.number(Double(port)), for: "EP")
                        message = nil
                        publishHeaderStatus()
                    }
                }
            )) {
                Text("E1.31 (sACN)").tag("5568")
                Text("Art-Net").tag("6454")
                Text("Custom port").tag("0")
            }
            .pickerStyle(.menu)
            .tint(.white)

            syncField("EP", label: "Port")
            if let description = syncFieldDescription(for: "EP") {
                syncDescriptionText(description)
            }
        })
    }

    private func syncScaledNumberField(_ key: String, label: String, multiplier: Double, unit: String) -> AnyView {
        guard let field = draft?.category.fields.first(where: { $0.key == key }) else {
            return AnyView(EmptyView())
        }

        return AnyView(VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(label)
                    .font(AppTypography.style(.subheadline, weight: .medium))
                    .settingsForegroundStyle(.primary)
                Spacer()
                WLEDAdvancedBufferedTextField(
                    text: Binding(
                        get: {
                            let value = (draft?.values[key]?.numberValue ?? 0) * multiplier
                            return value.rounded() == value ? String(Int(value)) : String(value)
                        },
                        set: { newValue in
                            let displayValue = Double(newValue) ?? 0
                            draft?.setValue(.number(displayValue / multiplier), for: key)
                            message = nil
                            publishHeaderStatus()
                        }
                    ),
                    keyboardType: .numbersAndPunctuation,
                    alignment: .trailing,
                    isDisabled: !field.isWritableByGenericConfig
                )
                .frame(width: 92)
                Text(unit)
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .settingsForegroundStyle(.secondary)
            }
            if let description = syncFieldDescription(for: key) {
                syncDescriptionText(description)
            }
        })
    }

    private func syncIPAddressFields(title: String, keys: [String]) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.style(.subheadline, weight: .medium))
                .settingsForegroundStyle(.primary)
            HStack(spacing: 6) {
                ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                    if let field = draft?.category.fields.first(where: { $0.key == key }) {
                        WLEDAdvancedBufferedTextField(
                            text: stringBinding(for: field),
                            keyboardType: .numberPad,
                            alignment: .center,
                            isDisabled: !field.isWritableByGenericConfig
                        )
                        .frame(maxWidth: .infinity)
                        if index < keys.count - 1 {
                            Text(".")
                                .settingsForegroundStyle(.secondary)
                        }
                    }
                }
            }
            if title == "Hue Bridge IP" {
                syncDescriptionText("**Bridge address:** Leave `0.0.0.0` until pairing Hue.")
            }
        })
    }

    private func syncPinPickerField(_ key: String, label: String, suffix: String) -> AnyView {
        guard let field = draft?.category.fields.first(where: { $0.key == key }) else {
            return AnyView(EmptyView())
        }

        return AnyView(VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(label)
                    .font(AppTypography.style(.subheadline, weight: .medium))
                    .settingsForegroundStyle(.primary)
                Spacer()
                Picker(label, selection: Binding(
                    get: {
                        String(Int(draft?.values[key]?.numberValue ?? -1))
                    },
                    set: { newValue in
                        draft?.setValue(.number(Double(Int(newValue) ?? -1)), for: key)
                        message = nil
                        publishHeaderStatus()
                    }
                )) {
                    ForEach(syncPinPickerOptions(for: field), id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .disabled(!field.isWritableByGenericConfig)
                .frame(maxWidth: .infinity, alignment: .trailing)
                Text(suffix)
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .settingsForegroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)
            }
            SettingsDescriptionText(markdown: "**Unused:** Saved to WLED as `-1`.")
            if let description = syncFieldDescription(for: key) {
                syncDescriptionText(description)
            }
        })
    }

    private func syncPinPickerOptions(for field: WLEDSettingDescriptor) -> [(value: String, label: String)] {
        var options: [(value: String, label: String)] = [("-1", "Unused")]

        if let pins = pinInfo?.pins, !pins.isEmpty {
            options += pins
                .filter { $0.displayOwner != "System" }
                .map { pin in
                    let value = String(pin.gpio)
                    if pin.isAllocated {
                        return (value, "\(pin.gpio) (\(pin.displayOwner))")
                    }
                    return (value, "\(pin.gpio)")
                }
        } else {
            let maxPin = min(Int(field.max ?? "39") ?? 39, 39)
            options += (0...maxPin).map { (String($0), String($0)) }
        }

        let currentValue = String(Int(draft?.values[field.key]?.numberValue ?? -1))
        if !options.contains(where: { $0.value == currentValue }) {
            let label = currentValue == "-1" ? "Unused" : currentValue
            options.append((currentValue, label))
        }

        return options
    }

    private func syncFieldDescription(for key: String) -> String? {
        switch key {
        case "UP": return "Main UDP port WLED uses to send and receive sync packets."
        case "U2": return "Optional second UDP port for compatibility with older sync setups."
        case "EN": return "Allows WLED to listen for ESP-NOW events from remotes or other ESP devices."
        case "RB": return "When receiving sync, allow another WLED device to change this device's brightness."
        case "RC": return "When receiving sync, allow another WLED device to change this device's colors."
        case "RX": return "When receiving sync, allow another WLED device to change the active effect."
        case "RP": return "When receiving sync, allow another WLED device to change the palette."
        case "SO": return "When receiving sync, allow segment option changes such as selected segment behavior."
        case "SG": return "When receiving sync, allow segment boundary changes."
        case "SS": return "Starts UDP sync automatically after WLED boots."
        case "SD": return "Broadcasts changes you make directly in the app or WLED UI to other synced devices."
        case "SB": return "Broadcasts changes triggered by a physical button or IR remote."
        case "SA": return "Broadcasts changes that come from Alexa control."
        case "SH": return "Broadcasts changes that come from Philips Hue polling."
        case "UR": return "Repeats UDP sync packets to improve delivery on unreliable networks."
        case "NL": return "Lets WLED show nearby WLED instances in its instance list."
        case "NB": return "Advertises this device so other WLED instances can discover it."
        case "RD": return "Allows realtime UDP, E1.31, Art-Net, DDP, or DMX input to temporarily control the LEDs."
        case "MO": return "Applies realtime input only to the main segment instead of all segments."
        case "RLM": return "Keeps realtime input aligned with configured LED maps."
        case "EP": return "Network port used for E1.31, Art-Net, or custom realtime input."
        case "EM": return "Receives E1.31 multicast packets instead of only unicast packets."
        case "EU": return "First E1.31 universe WLED listens to."
        case "ES": return "Ignores DMX/E1.31 packets that arrive out of sequence."
        case "DA": return "DMX channel address where this device starts reading data."
        case "XX": return "Channel spacing WLED uses between segments when mapping DMX data."
        case "PY": return "Priority value for E1.31 input when multiple controllers are present."
        case "DM": return "How WLED maps incoming DMX channels to LED color data."
        case "ET": return "How long realtime input can go quiet before WLED returns to normal control."
        case "FB": return "Forces realtime input to use maximum brightness instead of incoming brightness."
        case "RG": return "Disables gamma correction while realtime data is controlling the LEDs."
        case "WO": return "Offsets where realtime LED data starts on the strip."
        case "IDMR": return "GPIO used to receive wired DMX data."
        case "IDMT": return "GPIO used to transmit wired DMX data."
        case "IDME": return "GPIO used to enable the RS485 driver for wired DMX."
        case "IDMP": return "UART port WLED uses for wired DMX input."
        case "AL": return "Makes WLED emulate an Alexa-compatible light on your local network."
        case "AI": return "Name Alexa should discover for this WLED device."
        case "AP": return "Also exposes the first presets as separate Alexa devices."
        case "MQ": return "Connects WLED to an MQTT broker for external automation."
        case "MS": return "Hostname or IP address of the MQTT broker."
        case "MQPORT": return "Network port for the MQTT broker, usually 1883."
        case "MQUSER": return "Username WLED uses when connecting to the MQTT broker."
        case "MQPASS": return "Password WLED uses when connecting to the MQTT broker. It is write-only."
        case "MQCID": return "Client ID WLED uses to identify itself to the MQTT broker."
        case "MD": return "MQTT topic for this specific device."
        case "MG": return "MQTT topic shared by a group of WLED devices."
        case "BM": return "Publishes MQTT messages when a physical button is pressed."
        case "RT": return "Keeps retained MQTT brightness and color messages on the broker."
        case "HL": return "Hue light number WLED polls from the Hue Bridge."
        case "HI": return "How often WLED checks the Hue Bridge for changes."
        case "HP": return "Enables polling from the Hue Bridge."
        case "HO": return "Receives Hue on/off state."
        case "HB": return "Receives Hue brightness."
        case "HC": return "Receives Hue color."
        case "BD": return "Serial speed for WLED serial control and Improv. Keep 115200 unless a connected controller requires another rate."
        default: return nil
        }
    }

    private var loadingMatrixInfoRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(.white)
            Text("Loading 2D configuration...")
                .font(AppTypography.style(.caption))
                .settingsForegroundStyle(.secondary)
        }
    }

    private var ledDiagnosticsSection: some View {
        advancedSectionCard(title: "LED diagnostics") {
            VStack(alignment: .leading, spacing: 10) {
                if let diagnostics = ledOutputDraft?.diagnostics {
                    InfoRow(label: "Total LEDs", value: "\(diagnostics.totalLEDs)")
                    if let amps = diagnostics.brightestWhiteAmps {
                        InfoRow(label: "Brightest white PSU", value: "\(formatAmps(amps)) A")
                    }
                    if let amps = diagnostics.typicalEffectsAmps {
                        InfoRow(label: "Most effects", value: "~\(formatAmps(amps)) A")
                    }
                    if let used = diagnostics.estimatedMemoryUsedBytes {
                        let total = diagnostics.estimatedMemoryAvailableBytes.map { " / \($0) B" } ?? " B"
                        InfoRow(label: "LED memory usage", value: "\(used)\(total)")
                    }
                    if let channels = diagnostics.hardwareChannelsSummary {
                        InfoRow(label: "Hardware channels", value: channels)
                    }
                    SettingsDescriptionText(
                        markdown: "**Calculated from WLED:** Matches its LED setup page where JSON data is available."
                    )
                } else {
                    Text("Diagnostics load with LED outputs.")
                        .font(AppTypography.style(.caption))
                        .settingsForegroundStyle(.secondary)
                }
            }
        }
    }

    private var colorOrderOverridesSection: some View {
        advancedSectionCard(title: "Color Order Override") {
            VStack(alignment: .leading, spacing: 14) {
                SettingsDescriptionText(
                    markdown: "**Mixed channel wiring only:** Override color order for specific LED ranges."
                )

                if let ledOutputDraft {
                    if ledOutputDraft.colorOverrides.isEmpty {
                        Text("No override ranges configured.")
                            .font(AppTypography.style(.caption))
                            .settingsForegroundStyle(.secondary)
                    }

                    let validationErrors = ledOutputDraft.validationErrors()
                    ForEach(Array(ledOutputDraft.colorOverrides.enumerated()), id: \.element.id) { index, colorOverride in
                        let colorOverrideID = colorOverride.id
                        WLEDColorOrderOverrideEditor(
                            index: index,
                            colorOverride: Binding(
                                get: {
                                    self.ledOutputDraft?.colorOverrides.first { $0.id == colorOverrideID }
                                        ?? colorOverride
                                },
                                set: { newValue in
                                    self.ledOutputDraft?.updateColorOverride(id: colorOverrideID, with: newValue)
                                    message = nil
                                    publishHeaderStatus()
                                }
                            ),
                            validationErrors: validationErrors,
                            onRemove: {
                                self.ledOutputDraft?.removeColorOverride(id: colorOverrideID)
                                message = nil
                                publishHeaderStatus()
                            }
                        )
                    }

                    Button {
                        self.ledOutputDraft?.addColorOverride()
                        message = nil
                        publishHeaderStatus()
                    } label: {
                        SettingsInlineButton(title: "Add Override", icon: "plus")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func formatAmps(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    private func readonlyRow(field: WLEDSettingDescriptor, value: String) -> some View {
        HStack {
            Text(field.label)
                .font(AppTypography.style(.subheadline, weight: .medium))
                .settingsForegroundStyle(.primary)
            Spacer()
            Text(value)
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .foregroundColor(theme.settingsText(.secondary))
        }
    }

    private func loadingCard(_ title: String) -> some View {
        SettingsCard(title: title) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.white)
                Text(title)
                    .font(AppTypography.style(.caption))
                    .foregroundColor(theme.settingsText(.secondary))
            }
        }
    }

    private func boolBinding(for field: WLEDSettingDescriptor) -> Binding<Bool> {
        Binding(
            get: { draft?.values[field.key]?.boolValue ?? false },
            set: { newValue in
                draft?.setValue(.bool(newValue), for: field.key)
                message = nil
                publishHeaderStatus()
            }
        )
    }

    private func stringBinding(for field: WLEDSettingDescriptor) -> Binding<String> {
        Binding(
            get: { draft?.values[field.key]?.stringValue ?? "" },
            set: { newValue in
                if field.control == .number {
                    draft?.setValue(.number(Double(newValue) ?? 0), for: field.key)
                } else {
                    draft?.setValue(.string(newValue), for: field.key)
                }
                message = nil
                publishHeaderStatus()
            }
        )
    }

    private func secretReplacementBinding(for field: WLEDSettingDescriptor) -> Binding<String> {
        Binding(
            get: {
                if case .replace(let value) = draft?.secretStates[field.key] {
                    return value
                }
                return ""
            },
            set: { newValue in
                let configured = configuredSecret(field)
                if newValue.isEmpty {
                    draft?.setSecretState(.preserve(configured: configured), for: field.key)
                } else {
                    draft?.setSecretState(.replace(newValue), for: field.key)
                }
                message = nil
                publishHeaderStatus()
            }
        )
    }

    private func configuredSecret(_ field: WLEDSettingDescriptor) -> Bool {
        if case .preserve(let configured) = draft?.secretStates[field.key] {
            return configured
        }
        return false
    }

    private func canReplaceSecret(_ field: WLEDSettingDescriptor) -> Bool {
        if draft?.category.id == "wifi-network", field.key == "AP" {
            return true
        }
        if draft?.category.id == "sync-interfaces", field.key == "MQPASS" {
            return true
        }
        if draft?.category.id == "security-updates", ["PIN", "OP"].contains(field.key) {
            return true
        }
        return false
    }

    @MainActor
    private func loadManifest() async {
        isLoading = true
        message = nil
        do {
            let loadedManifest = try await WLEDAdvancedSettingsService.shared.loadManifest()
            if AppRuntimeEnvironment.isRunningUITests {
                supportedAdvancedFeatures = []
            } else {
                supportedAdvancedFeatures = (try? await WLEDAdvancedSettingsService.shared.fetchSupportedAdvancedFeatures(for: device)) ?? []
            }
            manifest = loadedManifest
            isLoading = false
            if selectedCategoryID == nil,
               let initialCategoryID,
               nativeAdvancedCategories(from: loadedManifest).contains(where: { $0.id == initialCategoryID }) {
                selectedCategoryID = initialCategoryID
                draft = nil
                ledOutputDraft = nil
                pinInfo = nil
                matrixInfo = nil
                securityAboutInfo = nil
                usermodsDraft = nil
                lastSaveStatus = "Settings"
                onCategoryDetailActiveChange(true)
                publishHeaderStatus()
                await reloadCurrentDraft()
                return
            }
            publishHeaderStatus()
        } catch {
            isLoading = false
            message = "Could not load the advanced settings definitions."
            messageIsError = true
            publishHeaderStatus()
        }
    }

    @MainActor
    private func selectCategory(
        _ category: WLEDSettingsCategoryDescriptor,
        searchSection: String? = nil,
        searchFieldKey: String? = nil
    ) {
        categoryLoadTask?.cancel()
        searchTargetCategoryID = searchSection == nil ? nil : category.id
        searchTargetSection = searchSection
        searchTargetFieldKey = searchFieldKey
        if let searchSection {
            expandedSectionIDs.insert("\(category.id)|\(searchSection)")
        }
        withAnimation(categoryNavigationAnimation) {
            selectedCategoryID = category.id
            draft = nil
            ledOutputDraft = nil
            pinInfo = nil
            matrixInfo = nil
            securityAboutInfo = nil
            usermodsDraft = nil
            lastSaveStatus = "Settings"
            onCategoryDetailActiveChange(true)
            publishHeaderStatus()
        }

        // The deterministic UI-test device is intentionally offline. The
        // category shell and navigation can be verified without live reads.
        guard !AppRuntimeEnvironment.isRunningUITests else {
            isLoading = false
            message = nil
            return
        }

        categoryLoadTask = Task { @MainActor in
            await reloadCurrentDraft()
        }
    }

    @MainActor
    private func reloadCurrentDraft() async {
        guard let targetCategoryID = selectedCategoryID else { return }
        isLoading = true
        message = nil
        do {
            let loadedDraft = try await WLEDAdvancedSettingsService.shared.fetchDraft(
                categoryID: targetCategoryID,
                for: device
            )
            guard !Task.isCancelled else { return }

            var loadedLEDOutputDraft: WLEDLEDOutputDraft?
            var loadedPinInfo: WLEDPinInfo?
            var loadedMatrixInfo: WLEDMatrixInfo?
            var loadedSecurityInfo: WLEDSecurityAboutInfo?
            var loadedUsermodsDraft: WLEDUsermodsDraft?

            switch targetCategoryID {
            case "led-hardware":
                loadedLEDOutputDraft = try await WLEDAdvancedSettingsService.shared.fetchLEDOutputDraft(for: device)
            case "pin-info":
                loadedPinInfo = try await WLEDAdvancedSettingsService.shared.fetchPinInfo(for: device)
            case "2d-configuration":
                loadedMatrixInfo = try await WLEDAdvancedSettingsService.shared.fetchMatrixInfo(for: device)
            case "sync-interfaces":
                loadedPinInfo = try? await WLEDAdvancedSettingsService.shared.fetchPinInfo(for: device)
            case "security-updates":
                loadedSecurityInfo = try? await WLEDAdvancedSettingsService.shared.fetchSecurityAboutInfo(for: device)
            case "usermods":
                loadedPinInfo = try? await WLEDAdvancedSettingsService.shared.fetchPinInfo(for: device)
                loadedUsermodsDraft = try? await WLEDAdvancedSettingsService.shared.fetchUsermodsDraft(for: device)
            default:
                break
            }

            guard !Task.isCancelled, selectedCategoryID == targetCategoryID else { return }
            draft = loadedDraft
            ledOutputDraft = loadedLEDOutputDraft
            pinInfo = loadedPinInfo
            matrixInfo = loadedMatrixInfo
            securityAboutInfo = loadedSecurityInfo
            usermodsDraft = loadedUsermodsDraft
            isLoading = false
            lastSaveStatus = loadedDraft.category.readOnly
                ? "Read Only"
                : "Settings"
            publishHeaderStatus()
        } catch is CancellationError {
            return
        } catch {
            guard selectedCategoryID == targetCategoryID else { return }
            isLoading = false
            message = "Could not load this WLED category."
            messageIsError = true
            publishHeaderStatus()
        }
    }

    @MainActor
    private func saveCurrentDraft() async -> Bool {
        guard !isSaving, let draft else { return false }
        let validationErrors = draft.validationErrors()
        if let validationMessage = draft.category.fields.compactMap({ validationErrors[$0.key] }).first {
            expandSectionsContainingErrors()
            message = validationMessage
            messageIsError = true
            publishHeaderStatus()
            return false
        }
        if let validationMessage = ledOutputDraft?.validationErrors().values.first {
            expandSectionsContainingErrors()
            message = validationMessage
            messageIsError = true
            publishHeaderStatus()
            return false
        }

        isSaving = true
        message = nil
        publishHeaderStatus()

        do {
            let result: WLEDSettingsSaveResult
            if draft.category.id == "usermods" {
                result = try await WLEDAdvancedSettingsService.shared.saveUsermods(
                    settingsDraft: draft,
                    usermodsDraft: usermodsDraft ?? WLEDUsermodsDraft(modules: []),
                    for: device
                )
            } else {
                result = try await WLEDAdvancedSettingsService.shared.saveDraft(draft, for: device)
            }
            let outputResult: WLEDSettingsSaveResult?
            if let ledOutputDraft, ledOutputDraft.isDirty {
                outputResult = try await WLEDAdvancedSettingsService.shared.saveLEDOutputDraft(ledOutputDraft, for: device)
            } else {
                outputResult = nil
            }
            self.draft = try await WLEDAdvancedSettingsService.shared.fetchDraft(categoryID: draft.category.id, for: device)
            if draft.category.id == "led-hardware" {
                self.ledOutputDraft = try await WLEDAdvancedSettingsService.shared.fetchLEDOutputDraft(for: device)
            }
            if draft.category.id == "usermods" {
                self.usermodsDraft = try await WLEDAdvancedSettingsService.shared.fetchUsermodsDraft(for: device)
            }
            isSaving = false
            let savedKeys = result.savedKeys.union(outputResult?.savedKeys ?? [])
            let sideEffects = result.sideEffects + (outputResult?.sideEffects ?? [])
            let combinedResult = WLEDSettingsSaveResult(
                savedKeys: savedKeys,
                sideEffects: sideEffects,
                requiresRefresh: result.requiresRefresh || (outputResult?.requiresRefresh ?? false)
            )
            lastSaveStatus = combinedResult.statusText
            message = savedKeys.isEmpty ? "No native changes to save yet. Use the WLED page for this field until its native codec is added." : combinedResult.statusText
            messageIsError = false
            publishHeaderStatus()
            return true
        } catch {
            isSaving = false
            message = error.localizedDescription
            messageIsError = true
            publishHeaderStatus()
            return false
        }
    }

    @MainActor
    private func restartDevice() async {
        guard !isRestarting else { return }
        isRestarting = true
        message = nil
        publishHeaderStatus()

        let commandOutcome = await sendRestartCommandWithShortWindow()
        switch commandOutcome {
        case .completed, .timedOut:
            lastSaveStatus = "Restarting..."
            message = "Restart command sent. Waiting for WLED to come back online."
            messageIsError = false
            publishHeaderStatus()

            let didReconnect = await waitForRestartRecovery()
            isRestarting = false
            lastSaveStatus = didReconnect ? "Saved" : "Settings"
            message = didReconnect
                ? "WLED restarted and is reachable again."
                : "Restart command sent. WLED did not respond before the app stopped waiting; refresh or re-enter this category if values look stale."
            messageIsError = false
            publishHeaderStatus()
        case .failed(let errorMessage):
            isRestarting = false
            message = errorMessage
            messageIsError = true
            publishHeaderStatus()
        }
    }

    private func sendRestartCommandWithShortWindow() async -> RestartCommandOutcome {
        await withTaskGroup(of: RestartCommandOutcome.self) { group in
            group.addTask {
                do {
                    try await WLEDAPIService.shared.rebootDevice(device)
                    return .completed
                } catch {
                    if Self.isExpectedRestartDisconnect(error) {
                        return .completed
                    }
                    return .failed(error.localizedDescription)
                }
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: restartCommandWindowNanos)
                return .timedOut
            }

            let outcome = await group.next() ?? .timedOut
            group.cancelAll()
            return outcome
        }
    }

    @MainActor
    private func factoryResetDevice() async {
        guard canStartFactoryReset else { return }
        isFactoryResetting = true
        factoryResetConfirmationText = ""
        message = nil
        lastSaveStatus = "Resetting..."
        publishHeaderStatus()

        let commandOutcome = await sendFactoryResetCommandWithShortWindow()
        switch commandOutcome {
        case .completed, .timedOut:
            isFactoryResetting = false
            lastSaveStatus = "Setup Required"
            message = "Factory reset sent. WLED will restart as a setup access point."
            messageIsError = false
            publishHeaderStatus()
            onFactoryResetComplete()
        case .failed(let errorMessage):
            isFactoryResetting = false
            lastSaveStatus = "Settings"
            message = "Factory reset could not be sent: \(errorMessage)"
            messageIsError = true
            publishHeaderStatus()
        }
    }

    private func sendFactoryResetCommandWithShortWindow() async -> RestartCommandOutcome {
        await withTaskGroup(of: RestartCommandOutcome.self) { group in
            group.addTask {
                do {
                    try await WLEDAdvancedSettingsService.shared.factoryReset(device)
                    return .completed
                } catch {
                    if Self.isExpectedRestartDisconnect(error) {
                        return .completed
                    }
                    return .failed(error.localizedDescription)
                }
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: restartCommandWindowNanos)
                return .timedOut
            }

            let outcome = await group.next() ?? .timedOut
            group.cancelAll()
            return outcome
        }
    }

    private func waitForRestartRecovery() async -> Bool {
        try? await Task.sleep(nanoseconds: restartProbeInitialDelayNanos)

        let deadline = Date().addingTimeInterval(restartProbeMaxSeconds)
        while Date() < deadline {
            if Task.isCancelled { return false }
            do {
                await WLEDAPIService.shared.invalidateStateCache(for: device.id)
                _ = try await WLEDAPIService.shared.getState(for: device)
                return true
            } catch {
                try? await Task.sleep(nanoseconds: restartProbeIntervalNanos)
            }
        }

        return false
    }

    nonisolated private static func isExpectedRestartDisconnect(_ error: Error) -> Bool {
        if let apiError = error as? WLEDAPIError {
            switch apiError {
            case .timeout, .deviceOffline, .deviceUnreachable:
                return true
            case .networkError(let nested):
                return isExpectedRestartDisconnect(nested)
            default:
                return false
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        return false
    }

    private func discardChanges() {
        draft?.reset()
        ledOutputDraft?.reset()
        usermodsDraft?.reset()
        message = nil
        lastSaveStatus = "Settings"
        publishHeaderStatus()
    }

    private func expandSectionsContainingErrors() {
        guard let draft else { return }
        let errorKeys = Set(draft.validationErrors().keys)
        for group in draft.category.groupedFields {
            if group.fields.contains(where: { errorKeys.contains($0.key) }) {
                expandedSectionIDs.insert("\(draft.category.id)|\(group.section)")
            }
        }
        if !(ledOutputDraft?.validationErrors().isEmpty ?? true) {
            expandedSectionIDs.insert("\(draft.category.id)|LED outputs")
            expandedSectionIDs.insert("\(draft.category.id)|LED outputs:")
        }
    }

    private func closeCategory() {
        if hasUnsavedChanges {
            showUnsavedBackConfirmation = true
            return
        }
        performCloseCategory()
    }

    private func performCloseCategory() {
        categoryLoadTask?.cancel()
        searchTargetCategoryID = nil
        searchTargetSection = nil
        searchTargetFieldKey = nil
        withAnimation(categoryNavigationAnimation) {
            selectedCategoryID = nil
            onCategoryDetailActiveChange(false)
        }

        message = nil
        lastSaveStatus = "Settings"
        onHeaderChromeChange(.settings)
        onHeaderActionsChange(.none)
        publishHeaderStatus()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard selectedCategoryID == nil else { return }
            draft = nil
            ledOutputDraft = nil
            pinInfo = nil
            matrixInfo = nil
            securityAboutInfo = nil
            usermodsDraft = nil
            onHeaderChromeChange(.settings)
            onHeaderActionsChange(.none)
        }
    }

    private var hasUnsavedChanges: Bool {
        (draft?.isDirty ?? false) || (ledOutputDraft?.isDirty ?? false) || (usermodsDraft?.isDirty ?? false)
    }

    private var currentSideEffects: [WLEDSettingsSideEffect] {
        var effects: [WLEDSettingsSideEffect] = []
        for effect in draft?.sideEffects ?? [] where !effects.contains(effect) {
            effects.append(effect)
        }
        for effect in ledOutputDraft?.sideEffects ?? [] where !effects.contains(effect) {
            effects.append(effect)
        }
        for effect in usermodDraftSideEffects where !effects.contains(effect) {
            effects.append(effect)
        }
        return effects
    }

    private var usermodDraftSideEffects: [WLEDSettingsSideEffect] {
        guard draft?.category.id == "usermods" else { return [] }
        let changedGlobalPin = draft?.changedFields.contains { ["SDA", "SCL", "MOSI", "MISO", "SCLK", "RBT"].contains($0.key) } ?? false
        let changedAudioHardware = usermodsDraft?.changedFields.contains { field in
            field.moduleName == "AudioReactive"
                && (field.section == "Analog microphone" || field.section == "Digital microphone")
        } ?? false
        return changedGlobalPin || changedAudioHardware ? [.reboot] : []
    }

    private var currentCategoryIsReadOnly: Bool {
        guard let selectedCategoryID else { return false }
        return manifest?.category(id: selectedCategoryID)?.readOnly
            ?? ["pin-info", "2d-configuration"].contains(selectedCategoryID)
    }

    private var canSaveCurrentCategory: Bool {
        hasUnsavedChanges
            && !currentCategoryIsReadOnly
            && !isSaving
            && !isRestarting
            && !isFactoryResetting
            && (draft?.validationErrors().isEmpty ?? true)
            && (ledOutputDraft?.validationErrors().isEmpty ?? true)
    }

    private var canStartFactoryReset: Bool {
        draft?.category.id == "security-updates"
            && !hasUnsavedChanges
            && !isSaving
            && !isRestarting
            && !isFactoryResetting
    }

    private var shouldShowRestartButton: Bool {
        lastSaveStatus == "Restart Required" && !hasUnsavedChanges && !isSaving
    }

    private var topRightActionEnabled: Bool {
        shouldShowRestartButton ? !isRestarting : canSaveCurrentCategory
    }

    private var requiresRiskySaveConfirmation: Bool {
        currentSideEffects.contains(.wifiReconnect)
            || currentSideEffects.contains(.ledReinit)
            || currentSideEffects.contains(.segmentRebuild)
            || currentSideEffects.contains(.securityLockout)
    }

    private var riskySaveConfirmationTitle: String {
        if currentSideEffects.contains(.securityLockout) {
            return "Save Security Changes?"
        }
        if currentSideEffects.contains(.wifiReconnect) {
            return "Save Network Changes?"
        }
        return "Save Hardware Changes?"
    }

    private var riskySaveConfirmationMessage: String {
        if currentSideEffects.contains(.securityLockout) {
            return "These changes can restrict access to WLED settings or firmware updates. Confirm the replacement PIN or passphrase before continuing."
        }
        if currentSideEffects.contains(.wifiReconnect) {
            return "The device may disconnect or move to a new address. Make sure WiFi recovery or physical access is available before continuing."
        }
        return "WLED may rebuild LED outputs or segments. The lights can turn off briefly, and a restart may be required."
    }

    private var headerActionTitle: String {
        if isFactoryResetting { return "Resetting..." }
        if isRestarting { return "Restarting..." }
        if isSaving { return "Saving..." }
        if currentCategoryIsReadOnly {
            return "Read Only"
        }
        if shouldShowRestartButton {
            return "Restart Required"
        }
        if canSaveCurrentCategory {
            return "Save"
        }
        return "Advanced Settings"
    }

    private func topRightAction() {
        if shouldShowRestartButton {
            showRestartConfirmation = true
        } else if requiresRiskySaveConfirmation {
            showRiskySaveConfirmation = true
        } else {
            Task { await saveCurrentDraft() }
        }
    }

    private func publishHeaderStatus() {
        let status: String
        if isFactoryResetting {
            status = "Resetting..."
        } else if isRestarting {
            status = "Restarting..."
        } else if isSaving {
            status = "Saving..."
        } else if hasUnsavedChanges {
            status = "Unsaved Changes"
        } else {
            status = lastSaveStatus
        }
        if lastPublishedHeaderStatus != status {
            lastPublishedHeaderStatus = status
            onHeaderStatusChange(status)
        }
        publishHeaderChrome()
    }

    private func publishHeaderChrome() {
        guard selectedCategoryID != nil else {
            _ = publishHeaderChromeIfNeeded(.settings)
            onHeaderActionsChange(.none)
            return
        }

        let chrome = EmbeddedSettingsHeaderChrome(
            backTitle: "Settings",
            backAccessibilityLabel: "Back to advanced settings categories",
            headerTitle: headerActionTitle,
            headerActionEnabled: topRightActionEnabled,
            headerAccessibilityLabel: currentCategoryIsReadOnly
                ? "Read-only advanced settings"
                : (shouldShowRestartButton ? "Restart WLED" : "Save advanced settings")
        )
        if publishHeaderChromeIfNeeded(chrome) {
            onHeaderActionsChange(
                EmbeddedSettingsHeaderActions(
                    back: { closeCategory() },
                    primary: { topRightAction() }
                )
            )
        }
    }

    private func publishHeaderChromeIfNeeded(_ chrome: EmbeddedSettingsHeaderChrome) -> Bool {
        guard lastPublishedHeaderChrome != chrome else { return false }
        lastPublishedHeaderChrome = chrome
        onHeaderChromeChange(chrome)
        return true
    }
}

private struct WLEDAdvancedCategoryRow: View {
    let category: WLEDSettingsCategoryDescriptor
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(AppTypography.style(.headline, weight: .semibold))
                .foregroundColor(theme.settingsText(.primary))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(category.title)
                    .font(AppTypography.style(.headline, weight: .semibold))
                    .foregroundColor(theme.settingsText(.primary))
                SettingsDescriptionText(markdown: summary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(theme.settingsText(.secondary))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .settingsDetailControlBackground(cornerRadius: 10)
    }

    private var summary: String {
        WLEDSettingsExperiencePolicy.categorySummary(category.id)
    }

    private var icon: String {
        switch category.id {
        case "wifi-network": return "wifi"
        case "led-hardware": return "lightbulb"
        case "pin-info": return "pin"
        case "2d-configuration": return "rectangle.grid.2x2"
        case "user-interface": return "paintbrush"
        case "dmx-output": return "cable.connector"
        case "sync-interfaces": return "arrow.triangle.2.circlepath"
        case "time-macros": return "clock"
        case "usermods": return "puzzlepiece"
        case "security-updates": return "lock.shield"
        default: return "slider.horizontal.3"
        }
    }
}

private struct AdvancedSettingsGroupHeading: View {
    let group: AdvancedSettingsGroupDescriptor
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: group.systemImage)
                .font(AppTypography.style(.subheadline, weight: .semibold))
                .foregroundColor(theme.settingsText(.primary))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(group.title)
                    .font(AppTypography.style(.headline, weight: .semibold))
                    .foregroundColor(theme.settingsText(.primary))
                    .accessibilityAddTraits(.isHeader)
                SettingsDescriptionText(markdown: group.summary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }
}

private struct WLEDPinInfoTable: View {
    let pins: [WLEDPinInfoPin]
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            WLEDPinInfoHeaderRow()
            ForEach(Array(pins.enumerated()), id: \.element.id) { index, pin in
                WLEDPinInfoTableRow(pin: pin, isAlternate: index.isMultiple(of: 2))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.22), lineWidth: 1)
        )
    }
}

private struct WLEDPinInfoHeaderRow: View {
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        HStack(spacing: 0) {
            Text("Pin")
                .frame(width: 78, alignment: .center)
            Divider()
                .overlay(Color.white.opacity(0.16))
            Text("Used by")
                .frame(width: 126, alignment: .center)
            Divider()
                .overlay(Color.white.opacity(0.16))
            Text("Pin Notes")
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .font(AppTypography.style(.subheadline, weight: .semibold))
        .foregroundColor(theme.settingsText(.primary))
        .padding(.vertical, 10)
        .background(Color.white.opacity(colorScheme == .dark ? 0.13 : 0.18))
    }
}

private struct WLEDPinInfoTableRow: View {
    let pin: WLEDPinInfoPin
    let isAlternate: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        HStack(spacing: 0) {
            Text("GPIO\(pin.gpio)")
                .frame(width: 78, alignment: .center)

            Divider()
                .overlay(Color.white.opacity(0.12))

            HStack(spacing: 6) {
                if let stateText = pin.stateText {
                    Circle()
                        .fill(stateText == "On" ? Color.green.opacity(0.88) : Color.white.opacity(0.34))
                        .frame(width: 12, height: 12)
                }
                Text(pin.displayOwner)
                    .foregroundColor(pin.isAllocated ? theme.settingsText(.primary) : Color(red: 0.0, green: 0.54, blue: 0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(width: 126, alignment: .center)

            Divider()
                .overlay(Color.white.opacity(0.12))

            Text(pin.noteText)
                .foregroundColor(theme.settingsText(.primary))
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .font(AppTypography.style(.subheadline, weight: .medium))
        .foregroundColor(theme.settingsText(.primary))
        .frame(minHeight: 44)
        .background(
            (isAlternate
                ? Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12)
                : Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08))
            )
    }
}

private struct WLEDMatrixPanelRow: View {
    let panel: WLEDMatrixPanel
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Panel \(panel.index)")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundColor(theme.settingsText(.primary))
                Spacer()
                Text(panel.dimensionsText)
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(theme.settingsText(.secondary))
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)
                ],
                spacing: 8
            ) {
                WLEDMatrixPanelMetric(label: "1st LED", value: panel.firstLEDText)
                WLEDMatrixPanelMetric(label: "Orientation", value: panel.orientationText)
                WLEDMatrixPanelMetric(label: "Layout", value: panel.layoutText)
                WLEDMatrixPanelMetric(label: "Offset X,Y", value: panel.offsetText)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.07 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.divider.opacity(0.72), lineWidth: 1)
        )
    }
}

private struct WLEDMatrixPanelMetric: View {
    let label: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppTypography.style(.caption, weight: .medium))
                .foregroundColor(theme.settingsText(.secondary))
            Text(value)
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(theme.settingsText(.primary))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WLEDAdvancedSideEffectsView: View {
    let effects: [WLEDSettingsSideEffect]

    var body: some View {
        if !effects.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(effects, id: \.self) { effect in
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(AppTypography.style(.caption, weight: .semibold))
                        Text(effect.displayName)
                            .font(AppTypography.style(.caption, weight: .medium))
                    }
                    .settingsForegroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WLEDMDNSAddressFieldRow: View {
    let field: WLEDSettingDescriptor
    @Binding var text: String
    let error: String?

    @Environment(\.colorScheme) private var colorScheme
    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local web address")
                .font(AppTypography.style(.subheadline, weight: .medium))
                .settingsForegroundStyle(.primary)

            HStack(spacing: 6) {
                Text("http://")
                    .font(AppTypography.style(.subheadline, weight: .medium))
                    .settingsForegroundStyle(.primary)

                WLEDAdvancedBufferedTextField(
                    placeholder: "device-name",
                    text: $text,
                    keyboardType: .URL,
                    alignment: .leading,
                    isDisabled: !field.isWritableByGenericConfig
                )

                Text(".local")
                    .font(AppTypography.style(.subheadline, weight: .medium))
                    .settingsForegroundStyle(.primary)
            }

            SettingsDescriptionText(
                markdown: "**Stable address:** Use letters, numbers, and hyphens."
            )

            if let error {
                Text(error)
                    .font(AppTypography.style(.caption))
                    .settingsForegroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct WLEDDottedIPAddressFieldRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let isDisabled: Bool
    let error: String?

    @Environment(\.colorScheme) private var colorScheme
    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.style(.subheadline, weight: .medium))
                .settingsForegroundStyle(.primary)

            WLEDAdvancedBufferedTextField(
                placeholder: placeholder,
                text: $text,
                keyboardType: .numbersAndPunctuation,
                alignment: .leading,
                isDisabled: isDisabled
            )

            SettingsDescriptionText(
                markdown: "**Dotted format:** Example `\(placeholder)`. Use `0.0.0.0` for automatic addressing."
            )

            if let error {
                Text(error)
                    .font(AppTypography.style(.caption))
                    .settingsForegroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct WLEDSecretFieldRow: View {
    let field: WLEDSettingDescriptor
    let state: WLEDSecretDraftState?
    let replacementText: Binding<String>
    let canReplace: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(field.label)
                    .font(AppTypography.style(.subheadline, weight: .medium))
                    .settingsForegroundStyle(.primary)
                Spacer()
                Text(status)
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .settingsForegroundStyle(.primary)
            }

            if canReplace {
                SecureField("Leave blank to preserve", text: replacementText)
                    .textFieldStyle(.plain)
                    .font(AppTypography.style(.subheadline))
                    .settingsForegroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
                Text(replacementHint)
                    .font(AppTypography.style(.caption))
                    .settingsForegroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                SettingsDescriptionText(
                    markdown: "**Secret hidden:** Edit it on the WLED page until native saving is verified."
                )
            }
        }
    }

    private var status: String {
        if case .replace = state {
            return "Will Replace"
        }
        if case .clear = state {
            return "Will Clear"
        }
        if case .preserve(let configured) = state, configured {
            return "Configured"
        }
        return "Write-only"
    }

    private var replacementHint: String {
        switch field.key {
        case "PIN":
            return "Secret values are never displayed. Enter exactly 4 digits to replace; leave blank to preserve the current WLED value."
        case "OP":
            return "Secret values are never displayed. Enter 1-32 characters to replace; leave blank to preserve the current WLED value."
        default:
            return "Secret values are never displayed. Enter 8-63 characters to replace; leave blank to preserve the current WLED value."
        }
    }
}

private struct WLEDUsermodModuleEditor: View {
    @Binding var module: WLEDUsermodModuleDraft

    private var groupedFieldIDs: [(section: String, fieldIDs: [String])] {
        var sections: [(section: String, fieldIDs: [String])] = []
        for field in module.fields {
            let section = field.section
            if let existingIndex = sections.firstIndex(where: { $0.section == section }) {
                sections[existingIndex].fieldIDs.append(field.id)
            } else {
                sections.append((section, [field.id]))
            }
        }
        return sections
    }

    private var moduleDescription: String {
        module.name == "AudioReactive"
            ? "Configure the microphone input and audio-sync behavior used by music-reactive effects."
            : "Controls exposed by this installed WLED extension."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(module.name)
                    .font(AppTypography.style(.headline, weight: .semibold))
                    .settingsForegroundStyle(.primary)
                Spacer()
                Text("Editable")
                    .font(AppTypography.style(.caption2, weight: .semibold))
                    .settingsForegroundStyle(.secondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.white.opacity(0.10), in: Capsule())
            }

            Text(moduleDescription)
                .font(AppTypography.style(.caption))
                .settingsForegroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(groupedFieldIDs, id: \.section) { group in
                VStack(alignment: .leading, spacing: 12) {
                    Text(group.section)
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .settingsForegroundStyle(.primary)

                    ForEach(group.fieldIDs, id: \.self) { fieldID in
                        if let index = module.fields.firstIndex(where: { $0.id == fieldID }) {
                            WLEDUsermodFieldEditor(field: $module.fields[index])
                        }
                    }
                }
                .padding(.top, 2)
                .overlay(alignment: .top) {
                    Divider().overlay(Color.white.opacity(0.16))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct WLEDUsermodFieldEditor: View {
    @Binding var field: WLEDUsermodFieldDraft

    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        switch field.kind {
        case .boolean:
            Toggle(field.label, isOn: Binding(
                get: { field.boolValue },
                set: { field.setBoolValue($0) }
            ))
            .settingsToggleStyle()

        case .number, .text:
            valueEditor

        case .numberArray:
            arrayEditor

        case .unsupported:
            VStack(alignment: .leading, spacing: 5) {
                InfoRow(label: field.label, value: field.unsupportedValue ?? "Not supported")
                SettingsDescriptionText(
                    markdown: "**WLED page required:** This value has no safe native control yet."
                )
            }
        }
    }

    @ViewBuilder
    private var valueEditor: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(field.label)
                .font(AppTypography.style(.subheadline, weight: .medium))
                .settingsForegroundStyle(.primary)

            if let options = pickerOptions {
                Picker(field.label, selection: $field.value) {
                    ForEach(options, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(theme.surfaceMuted.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                TextField("", text: $field.value)
                    .settingsTextFieldChrome(theme: theme)
                    .keyboardType(field.kind == .number ? .numbersAndPunctuation : .default)
                    .textInputAutocapitalization(field.kind == .text ? .sentences : .never)
                    .autocorrectionDisabled(field.kind == .number)
            }

            if let helpText {
                Text(helpText)
                    .font(AppTypography.style(.caption))
                    .foregroundColor(helpText.contains("restart") ? .orange.opacity(0.92) : .white.opacity(0.88))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var arrayEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(field.label)
                .font(AppTypography.style(.subheadline, weight: .medium))
                .settingsForegroundStyle(.primary)

            LazyVGrid(
                columns: [GridItem(.flexible(minimum: 110), spacing: 10), GridItem(.flexible(minimum: 110), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(field.arrayValues.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(arrayValueLabel(index))
                            .font(AppTypography.style(.caption, weight: .medium))
                            .settingsForegroundStyle(.secondary)
                        TextField("", text: Binding(
                            get: { field.arrayValues.indices.contains(index) ? field.arrayValues[index] : "" },
                            set: { value in
                                guard field.arrayValues.indices.contains(index) else { return }
                                field.arrayValues[index] = value
                            }
                        ))
                        .settingsTextFieldChrome(theme: theme)
                        .keyboardType(.numbersAndPunctuation)
                    }
                }
            }

            if let helpText {
                Text(helpText)
                    .font(AppTypography.style(.caption))
                    .settingsForegroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var pickerOptions: [(value: String, label: String)]? {
        let options: [(String, String)]
        switch field.formName {
        case "AudioReactive:digitalmic:type":
            options = [
                ("0", "Generic Analog"),
                ("1", "Generic I2S"),
                ("2", "ES7243"),
                ("3", "SPH0654"),
                ("4", "Generic I2S with MCLK"),
                ("5", "Generic PDM"),
                ("6", "ES8388"),
                ("254", "Network receive only")
            ]
        case "AudioReactive:config:AGC":
            options = [("0", "Off"), ("1", "Normal"), ("2", "Vivid"), ("3", "Lazy")]
        case "AudioReactive:frequency:scale":
            options = [
                ("0", "None"),
                ("1", "Logarithmic (Loudness)"),
                ("2", "Linear (Amplitude)"),
                ("3", "Square Root (Energy)")
            ]
        case "AudioReactive:sync:mode":
            options = [("0", "Off"), ("1", "Send"), ("2", "Receive")]
        default:
            return nil
        }

        if options.contains(where: { $0.0 == field.value }) {
            return options.map { ($0.0, $0.1) }
        }
        return [(field.value, "Current value: \(field.value)")] + options.map { ($0.0, $0.1) }
    }

    private func arrayValueLabel(_ index: Int) -> String {
        guard field.formName == "AudioReactive:digitalmic:pin[]" else {
            return "Value \(index + 1)"
        }
        let labels = ["I2S data", "I2S word select", "I2S clock", "I2S master clock"]
        return labels.indices.contains(index) ? labels[index] : "Pin \(index + 1)"
    }

    private var helpText: String? {
        switch field.formName {
        case "AudioReactive:digitalmic:type":
            return "Changing microphone type requires a WLED restart."
        case "AudioReactive:digitalmic:pin[]":
            return "Use only GPIOs wired to the I2S microphone. Master clock accepts -1, 0, 1, or 3 on this ESP32 build."
        case "AudioReactive:analogmic:pin":
            return "Set to -1 when no analog microphone is connected."
        case "AudioReactive:config:squelch":
            return "Suppresses low-level background noise before effects react."
        case "AudioReactive:config:gain":
            return "Raises or lowers microphone sensitivity."
        case "AudioReactive:config:AGC":
            return "Automatically adjusts gain as sound levels change."
        case "AudioReactive:dynamics:rise", "AudioReactive:dynamics:fall":
            return "Used by music-reactive effects only, in milliseconds."
        case "AudioReactive:sync:port":
            return "UDP port used for AudioReactive sync between WLED devices."
        default:
            return nil
        }
    }
}

private struct WLEDLEDOutputEditor: View {
    let index: Int
    @Binding var output: WLEDLEDOutput
    let canRemove: Bool
    let validationErrors: [String: String]
    let onRemove: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Output \(index + 1)")
                    .font(AppTypography.style(.headline, weight: .semibold))
                    .settingsForegroundStyle(.primary)
                Spacer()
                if canRemove {
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .font(AppTypography.style(.subheadline, weight: .semibold))
                            .settingsForegroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove output \(index + 1)")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("LED type")
                    .font(AppTypography.style(.subheadline, weight: .medium))
                    .settingsForegroundStyle(.primary)
                Picker("LED type", selection: $output.type) {
                    ForEach(ledTypeOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                if let error = validationErrors["output-\(index)-type"] {
                    WLEDOutputErrorText(error)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("GPIO pins")
                    .font(AppTypography.style(.subheadline, weight: .medium))
                    .settingsForegroundStyle(.primary)
                WLEDOutputTextField(
                    placeholder: "16 or 16, 17",
                    text: $output.pins,
                    keyboardType: .numbersAndPunctuation
                )
                if let error = validationErrors["output-\(index)-pins"] {
                    WLEDOutputErrorText(error)
                }
            }

            LazyVGrid(columns: twoColumns, alignment: .leading, spacing: 10) {
                WLEDOutputNumberField(title: "Length", value: $output.length, error: validationErrors["output-\(index)-length"])
                WLEDOutputNumberField(title: "Start", value: $output.start, error: validationErrors["output-\(index)-start"])
                WLEDOutputNumberField(title: "Skip first", value: $output.skip, error: validationErrors["output-\(index)-skip"])
                WLEDOutputNumberField(title: "Frequency", value: $output.frequency, error: nil)
                WLEDOutputNumberField(title: "Output limit mA", value: $output.maxPowerMilliamps, error: validationErrors["output-\(index)-maxpwr"])
            }

            WLEDOutputCurrentField(
                value: $output.currentMilliamps,
                error: validationErrors["output-\(index)-current"]
            )

            VStack(alignment: .leading, spacing: 10) {
                Picker("Color order", selection: $output.colorOrder) {
                    ForEach(colorOrderOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)

                Picker("Swap", selection: $output.whiteChannelSwap) {
                    ForEach(whiteSwapOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)

                Picker("Auto-calculate white", selection: $output.autoWhiteMode) {
                    ForEach(autoWhiteOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)

                Picker("Driver", selection: $output.driverType) {
                    Text("Default / RMT").tag(0)
                    Text("I2S").tag(1)
                }
                .pickerStyle(.menu)
                .tint(.white)
            }

            Toggle("Reverse direction", isOn: $output.reverse)
                .settingsToggleStyle()
            Toggle("Refresh when off", isOn: $output.refreshWhenOff)
                .settingsToggleStyle()
            Toggle("Use per-output limiter", isOn: $output.perOutputLimiter)
                .settingsToggleStyle()

            SettingsDescriptionText(
                markdown: "**Start:** First virtual LED. **Length:** LED count. **Skip:** Unused pixels before the strip."
            )
        }
        .padding(12)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var twoColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 110), spacing: 10),
            GridItem(.flexible(minimum: 110), spacing: 10)
        ]
    }

    private var ledTypeOptions: [(value: Int, label: String)] {
        let known: [(Int, String)] = [
            (22, "WS281x"),
            (24, "WS281x 400kHz"),
            (30, "SK6812 / WS2814 RGBW"),
            (31, "TM1814"),
            (32, "WS2805 RGBCW"),
            (33, "TM1914"),
            (34, "SM16825 RGBCW"),
            (41, "WS2811 White"),
            (42, "PWM CCT"),
            (44, "PWM RGBW"),
            (45, "PWM RGBCCT"),
            (46, "PWM RGB"),
            (50, "WS2801"),
            (51, "APA102"),
            (52, "LPD8806"),
            (80, "DDP RGB Network"),
            (88, "E1.31 RGB Network")
        ]
        if known.contains(where: { $0.0 == output.type }) {
            return known.map { ($0.0, "\($0.1) (\($0.0))") }
        }
        return [(output.type, "Current custom type \(output.type)")] + known.map { ($0.0, "\($0.1) (\($0.0))") }
    }

    private var colorOrderOptions: [(value: Int, label: String)] {
        [
            (0, "GRB"),
            (1, "RGB"),
            (2, "BRG"),
            (3, "RBG"),
            (4, "BGR"),
            (5, "GBR")
        ]
    }

    private var whiteSwapOptions: [(value: Int, label: String)] {
        [
            (0, "None"),
            (1, "W & B"),
            (2, "W & G"),
            (3, "W & R"),
            (4, "WW & CW")
        ]
    }

    private var autoWhiteOptions: [(value: Int, label: String)] {
        [
            (0, "None"),
            (1, "Brighter"),
            (2, "Accurate"),
            (3, "Dual"),
            (4, "Max"),
            (255, "Use global")
        ]
    }
}

private struct WLEDOutputCurrentField: View {
    @Binding var value: Int
    let error: String?

    @Environment(\.colorScheme) private var colorScheme
    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    private var isCustom: Bool {
        !Self.presets.contains(where: { $0.value == value })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("mA/LED")
                .font(AppTypography.style(.subheadline, weight: .medium))
                .settingsForegroundStyle(.primary)
            Picker("mA/LED", selection: Binding(
                get: { isCustom ? -1 : value },
                set: { selected in
                    if selected != -1 {
                        value = selected
                    }
                }
            )) {
                ForEach(Self.presets, id: \.value) { preset in
                    Text(preset.label).tag(preset.value)
                }
                Text("Custom").tag(-1)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(theme.surfaceMuted.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if isCustom {
                WLEDOutputNumberField(title: "Custom current mA", value: $value, error: error)
            } else if let error {
                WLEDOutputErrorText(error)
            }

            SettingsDescriptionText(
                markdown: "**Power estimate only:** Informs limiting and diagnostics; it does not force current draw."
            )
        }
    }

    private static let presets: [(value: Int, label: String)] = [
        (55, "55mA (typ. 5V WS281x)"),
        (35, "35mA (eco WS2812)"),
        (30, "30mA (typ. 12V)"),
        (12, "12mA (WS2815)"),
        (15, "15mA (seed/fairy pixels)")
    ]
}

private struct WLEDColorOrderOverrideEditor: View {
    let index: Int
    @Binding var colorOverride: WLEDColorOrderOverride
    let validationErrors: [String: String]
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Override \(index + 1)")
                    .font(AppTypography.style(.headline, weight: .semibold))
                    .settingsForegroundStyle(.primary)
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .settingsForegroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove color order override \(index + 1)")
            }

            LazyVGrid(columns: twoColumns, alignment: .leading, spacing: 10) {
                WLEDOutputNumberField(title: "Start", value: $colorOverride.start, error: validationErrors["override-\(index)-start"])
                WLEDOutputNumberField(title: "Length", value: $colorOverride.length, error: validationErrors["override-\(index)-length"])
            }

            VStack(alignment: .leading, spacing: 10) {
                Picker("Color order", selection: $colorOverride.colorOrder) {
                    ForEach(colorOrderOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)

                Picker("Swap", selection: $colorOverride.whiteChannelSwap) {
                    ForEach(whiteSwapOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var twoColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 110), spacing: 10),
            GridItem(.flexible(minimum: 110), spacing: 10)
        ]
    }

    private var colorOrderOptions: [(value: Int, label: String)] {
        [
            (0, "GRB"),
            (1, "RGB"),
            (2, "BRG"),
            (3, "RBG"),
            (4, "BGR"),
            (5, "GBR")
        ]
    }

    private var whiteSwapOptions: [(value: Int, label: String)] {
        [
            (0, "None"),
            (1, "W & B"),
            (2, "W & G"),
            (3, "W & R"),
            (4, "WW & CW")
        ]
    }
}

private struct WLEDAdvancedBufferedTextField: View {
    var placeholder: String = ""
    @Binding var text: String
    let keyboardType: UIKeyboardType
    let alignment: TextAlignment
    let isDisabled: Bool

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool
    @State private var localText: String
    @State private var commitTask: Task<Void, Never>?

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }
    private let commitDelayNanos: UInt64 = 360_000_000

    init(
        placeholder: String = "",
        text: Binding<String>,
        keyboardType: UIKeyboardType,
        alignment: TextAlignment,
        isDisabled: Bool
    ) {
        self.placeholder = placeholder
        self._text = text
        self.keyboardType = keyboardType
        self.alignment = alignment
        self.isDisabled = isDisabled
        self._localText = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        TextField(placeholder, text: $localText)
            .keyboardType(keyboardType)
            .multilineTextAlignment(alignment)
            .settingsTextFieldChrome(theme: theme)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .disabled(isDisabled)
            .focused($isFocused)
            .onChange(of: localText) { _, _ in
                scheduleCommit()
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    commitNow()
                }
            }
            .onChange(of: text) { _, newValue in
                if !isFocused, localText != newValue {
                    localText = newValue
                }
            }
            .onSubmit(commitNow)
            .onDisappear {
                commitNow()
                commitTask?.cancel()
            }
    }

    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: commitDelayNanos)
            guard !Task.isCancelled else { return }
            commitNow()
        }
    }

    private func commitNow() {
        commitTask?.cancel()
        if text != localText {
            text = localText
        }
    }
}

private struct WLEDOutputNumberField: View {
    let title: String
    @Binding var value: Int
    let error: String?

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool
    @State private var text: String
    @State private var commitTask: Task<Void, Never>?

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    init(title: String, value: Binding<Int>, error: String?) {
        self.title = title
        self._value = value
        self.error = error
        self._text = State(initialValue: String(value.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.style(.caption, weight: .medium))
                .settingsForegroundStyle(.secondary)
            TextField("", text: $text)
            .settingsTextFieldChrome(theme: theme)
            .keyboardType(.numbersAndPunctuation)
            .focused($isFocused)
            .onChange(of: text) { _, _ in
                scheduleCommit()
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    commitNow()
                }
            }
            .onChange(of: value) { _, newValue in
                if !isFocused, text != String(newValue) {
                    text = String(newValue)
                }
            }
            .onSubmit(commitNow)
            .onDisappear {
                commitNow()
                commitTask?.cancel()
            }

            if let error {
                WLEDOutputErrorText(error)
            }
        }
    }

    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 360_000_000)
            guard !Task.isCancelled else { return }
            commitNow()
        }
    }

    private func commitNow() {
        commitTask?.cancel()
        let nextValue = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        if value != nextValue {
            value = nextValue
        }
    }
}

private struct WLEDOutputTextField: View {
    let placeholder: String
    @Binding var text: String
    let keyboardType: UIKeyboardType

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool
    @State private var localText: String
    @State private var commitTask: Task<Void, Never>?

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    init(placeholder: String, text: Binding<String>, keyboardType: UIKeyboardType) {
        self.placeholder = placeholder
        self._text = text
        self.keyboardType = keyboardType
        self._localText = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        TextField(placeholder, text: $localText)
            .settingsTextFieldChrome(theme: theme)
            .keyboardType(keyboardType)
            .disableAutocorrection(true)
            .focused($isFocused)
            .onChange(of: localText) { _, _ in
                scheduleCommit()
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    commitNow()
                }
            }
            .onChange(of: text) { _, newValue in
                if !isFocused, localText != newValue {
                    localText = newValue
                }
            }
            .onSubmit(commitNow)
            .onDisappear {
                commitNow()
                commitTask?.cancel()
            }
    }

    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 360_000_000)
            guard !Task.isCancelled else { return }
            commitNow()
        }
    }

    private func commitNow() {
        commitTask?.cancel()
        if text != localText {
            text = localText
        }
    }
}

private struct WLEDOutputErrorText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(AppTypography.style(.caption2))
            .settingsForegroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
