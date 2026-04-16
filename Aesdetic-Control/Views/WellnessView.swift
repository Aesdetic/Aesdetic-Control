//
//  WellnessView.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import SwiftUI
import UIKit
import CoreLocation

struct WellnessView: View {
    @EnvironmentObject private var viewModel: WellnessViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDate: Date = Date()
    @State private var entry: WellnessEntrySnapshot = .empty(for: Date())
    @State private var isLoadingEntry: Bool = false
    @State private var saveTask: Task<Void, Never>? = nil
    @State private var isDatePickerPresented: Bool = false
    @State private var isMorningExpanded: Bool = false
    @State private var isIdentityExpanded: Bool = false
    @State private var isPrioritiesExpanded: Bool = false
    @State private var isEveningExpanded: Bool = false
    @State private var isTomorrowPlanExpanded: Bool = false
    @State private var lastCompletionStates: [Bool] = []
    @State private var lastIntegrationSignature: String = ""
    @State private var hasAutoExpanded: Bool = false
    @State private var rollingStartDate: Date = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
    @State private var contentMode: WellnessContentMode = .daily
    @State private var overviewStats: WellnessReviewStats? = nil
    @State private var dayPhase: WellnessDayPhase = .morning
    @State private var phaseRefreshTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()
    @State private var isSleepTimePickerPresented: Bool = false
    @State private var isWakeTimePickerPresented: Bool = false

    private let weatherSummary = "23C Sunny"
    private let showInspoBackgroundPreview = false
    private let showDecorativeTree = true
    private var topSafeAreaInset: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return 0
        }
        return window.safeAreaInsets.top
    }

    var body: some View {
        ZStack {
            AppBackground()

            if showInspoBackgroundPreview {
                WellnessInspoBackground()
                    .ignoresSafeArea()
            }
            if showDecorativeTree {
                LowPolyMapleTree()
                    .frame(width: 120, height: 160)
                    .opacity(0.16)
                    .padding(.trailing, 24)
                    .padding(.bottom, 130)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .allowsHitTesting(false)
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section(header: dayStripHeader) {
                            contentBody

                            Color.clear
                                .frame(height: showDecorativeTree ? 160 : 40)
                        }
                    }
                    .padding(.bottom, 12)
                    .background(Color.clear)
                }
                .background(Color.clear)
                .refreshable {
                    await viewModel.refreshData()
                    await reloadEntry(for: selectedDate)
                }
                .onChange(of: completionStates) { _, newValue in
                    guard contentMode == .daily else { return }
                    autoScrollIfNeeded(previous: lastCompletionStates, current: newValue, proxy: proxy)
                    lastCompletionStates = newValue
                }
            }
        }
        .sheet(isPresented: $isDatePickerPresented) {
            WellnessDatePickerSheet(selectedDate: $selectedDate)
        }
        .sheet(isPresented: $isSleepTimePickerPresented) {
            WellnessTimePickerSheet(
                title: "Sleep time",
                selectedTime: $entry.sleepTime,
                referenceDate: selectedDate,
                defaultHour: 22,
                defaultMinute: 0
            )
        }
        .sheet(isPresented: $isWakeTimePickerPresented) {
            WellnessTimePickerSheet(
                title: "Wake time",
                selectedTime: $entry.wakeTime,
                referenceDate: selectedDate,
                defaultHour: 7,
                defaultMinute: 0
            )
        }
        .onAppear {
            ensureRollingRangeIncludesSelected()
            refreshDayPhase()
            Task {
                await reloadEntry(for: selectedDate)
                lastCompletionStates = completionStates
                scheduleInitialExpand()
            }
        }
        .onChange(of: selectedDate) { _, newValue in
            ensureRollingRangeIncludesSelected()
            refreshDayPhase()
            saveEntryNow()
            Task {
                await reloadEntry(for: newValue)
                lastCompletionStates = completionStates
            }
        }
        .onChange(of: contentMode) { _, newValue in
            Task { await reloadOverviewStats(for: newValue) }
        }
        .onChange(of: entry) { _, _ in
            scheduleSave()
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                refreshDayPhase()
            }
        }
        .onReceive(phaseRefreshTimer) { _ in
            refreshDayPhase()
        }
    }

    private var dayStripHeader: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayTitle)
                        .font(AppTypography.display(size: 40, weight: .bold, relativeTo: .largeTitle))
                        .foregroundColor(WellnessTheme.textPrimary)
                    Text(dateSubtitle)
                        .font(AppTypography.style(.caption, weight: .semibold))
                        .foregroundColor(WellnessTheme.textSecondary)
                }
                Spacer()
                Button(action: { isDatePickerPresented = true }) {
                    Image(systemName: "calendar")
                        .font(AppTypography.style(.title3, weight: .semibold))
                        .foregroundColor(WellnessTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 2)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(dayStripItems) { item in
                            switch item {
                            case .day(let day):
                                let dayNumber = Calendar.current.component(.day, from: day)
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        contentMode = .daily
                                    }
                                    selectedDate = day
                                }) {
                                    Text("\(dayNumber)")
                                        .font(AppTypography.style(.footnote, weight: .semibold))
                                        .foregroundColor(isSelected(day) ? WellnessTheme.textPrimary : WellnessTheme.textSecondary)
                                        .frame(width: 30, height: 24)
                                        .padding(.vertical, 6)
                                        .overlay(alignment: .bottom) {
                                            Rectangle()
                                                .fill(isSelected(day) ? WellnessTheme.textPrimary : Color.clear)
                                                .frame(height: 2)
                                        }
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .id(dateKey(for: day))
                            case .weekOverview(let weekEnd):
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        contentMode = .overview(kind: .week, endingAt: weekEnd)
                                    }
                                }) {
                                    Image(systemName: "chart.bar")
                                        .font(AppTypography.style(.caption, weight: .semibold))
                                        .foregroundColor(WellnessTheme.textSecondary)
                                        .frame(width: 28, height: 28)
                                        .background(WellnessTheme.surfaceStrong)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .id(weekKey(for: weekEnd))
                            case .monthOverview(let monthStart):
                                Button(action: {
                                    let monthEnd = Calendar.current.date(byAdding: .day, value: -1, to: monthStart) ?? monthStart
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        contentMode = .overview(kind: .month, endingAt: monthEnd)
                                    }
                                }) {
                                    Image(systemName: "calendar")
                                        .font(AppTypography.style(.caption, weight: .semibold))
                                        .foregroundColor(WellnessTheme.textSecondary)
                                        .frame(width: 28, height: 28)
                                        .background(WellnessTheme.surfaceStrong)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .id(monthKey(for: monthStart))
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    proxy.scrollTo(dateKey(for: selectedDate), anchor: .center)
                }
                .onChange(of: selectedDate) { _, newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(dateKey(for: newValue), anchor: .center)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, topSafeAreaInset + 12)
        .padding(.bottom, 18)
        .background(Color.clear.ignoresSafeArea(edges: .top))
    }

    private var morningCheckinContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sleep time")
                    .font(AppTypography.style(.footnote, weight: .semibold))
                    .foregroundColor(WellnessTheme.textSecondary)
                HStack {
                    Button(action: { isSleepTimePickerPresented = true }) {
                        Text(entry.sleepTime.map { Self.timeFormatter.string(from: $0) } ?? "Not set")
                            .font(AppTypography.style(.footnote, weight: .semibold))
                            .foregroundColor(WellnessTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .disabled(entry.isLocked)
                    Spacer()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Wake time")
                    .font(AppTypography.style(.footnote, weight: .semibold))
                    .foregroundColor(WellnessTheme.textSecondary)
                HStack {
                    Button(action: { isWakeTimePickerPresented = true }) {
                        Text(entry.wakeTime.map { Self.timeFormatter.string(from: $0) } ?? "Not set")
                            .font(AppTypography.style(.footnote, weight: .semibold))
                            .foregroundColor(WellnessTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .disabled(entry.isLocked)
                    Spacer()
                    Button("Use Health") {
                        Task { await hydrateWakeTime(force: true) }
                    }
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(WellnessTheme.textPrimary)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(WellnessTheme.textPrimary)
                            .frame(height: 1)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Sleep quality")
                    .font(AppTypography.style(.footnote, weight: .semibold))
                    .foregroundColor(WellnessTheme.textSecondary)
                RatingDots(rating: $entry.sleepQuality, maxRating: 10, isLocked: entry.isLocked)
            }

            HStack {
                Text("Woke on time")
                    .font(AppTypography.style(.footnote, weight: .semibold))
                    .foregroundColor(WellnessTheme.textSecondary)
                Spacer()
                Button(action: { entry.wokeOnTime.toggle() }) {
                    CheckDot(isOn: entry.wokeOnTime)
                }
                .buttonStyle(.plain)
                .disabled(entry.isLocked)
            }

            HStack {
                Text("Sunrise lamp used")
                    .font(AppTypography.style(.footnote, weight: .semibold))
                    .foregroundColor(WellnessTheme.textSecondary)
                Spacer()
                CheckDot(isOn: entry.sunriseLampUsed)
            }

        }
    }

    private var intentionsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            WellnessLineTextField(text: $entry.identityIntentionText, placeholder: "Who do you want to be today?", isLocked: entry.isLocked)
            WellnessLineTextField(text: $entry.intentionText, placeholder: "What do you want to achieve today?", isLocked: entry.isLocked)
            WellnessLineTextField(text: $entry.smallestNextStepText, placeholder: "Smallest next step", isLocked: entry.isLocked)

            Text("Brain dump")
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(WellnessTheme.textSecondary)

            WellnessTextEditor(
                text: $entry.brainDumpText,
                placeholder: "Everything on your mind, without filters...",
                isLocked: entry.isLocked
            )
        }
    }

    private var prioritiesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Most important task")
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(WellnessTheme.textSecondary)
            TaskRow(
                index: 1,
                text: $entry.mainTaskText,
                durationMinutes: $entry.mainTaskDurationMinutes,
                isCompleted: $entry.mainTaskDone,
                isPrimary: true,
                isLocked: entry.isLocked
            )

            Text("Secondary tasks")
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(WellnessTheme.textSecondary)
            TaskRow(
                index: 2,
                text: $entry.secondaryTaskOneText,
                durationMinutes: $entry.secondaryTaskOneDurationMinutes,
                isCompleted: $entry.secondaryTaskOneDone,
                isPrimary: false,
                isLocked: entry.isLocked
            )
            TaskRow(
                index: 3,
                text: $entry.secondaryTaskTwoText,
                durationMinutes: $entry.secondaryTaskTwoDurationMinutes,
                isCompleted: $entry.secondaryTaskTwoDone,
                isPrimary: false,
                isLocked: entry.isLocked
            )
        }
    }

    private var eveningContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Productivity")
                    .font(AppTypography.style(.footnote, weight: .semibold))
                    .foregroundColor(WellnessTheme.textSecondary)
                RatingDots(rating: $entry.productivityRating, maxRating: 10, isLocked: entry.isLocked)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("How did your day go?")
                    .font(AppTypography.style(.footnote, weight: .semibold))
                    .foregroundColor(WellnessTheme.textSecondary)
                RatingDots(rating: $entry.dayMoodRating, maxRating: 10, isLocked: entry.isLocked)
            }

            WellnessTextEditor(text: $entry.dayRecapText, placeholder: eveningPrompt, isLocked: entry.isLocked)
            WellnessLineTextField(text: $entry.adjustTomorrowText, placeholder: "What should you adjust tomorrow?", isLocked: entry.isLocked)
        }
    }

    private var tomorrowPlanContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlanTaskRow(
                index: 1,
                text: $entry.tomorrowTaskOneText,
                durationMinutes: $entry.tomorrowTaskOneDurationMinutes,
                isLocked: entry.isLocked
            )
            PlanTaskRow(
                index: 2,
                text: $entry.tomorrowTaskTwoText,
                durationMinutes: $entry.tomorrowTaskTwoDurationMinutes,
                isLocked: entry.isLocked
            )
            PlanTaskRow(
                index: 3,
                text: $entry.tomorrowTaskThreeText,
                durationMinutes: $entry.tomorrowTaskThreeDurationMinutes,
                isLocked: entry.isLocked
            )
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        ZStack(alignment: .top) {
            if contentMode == .daily {
                dailySections
                    .transition(.opacity)
            }
            if case .overview(let kind, let endingAt) = contentMode {
                overviewContent(kind: kind, endingAt: endingAt)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: contentMode)
    }

    private var dailySections: some View {
        VStack(spacing: 0) {
            stackedSection(
                id: "morning",
                title: "Morning check-in",
                subtitle: "How did you sleep and wake today?",
                background: WellnessTheme.sectionBlue,
                isExpanded: $isMorningExpanded,
                verticalPadding: 28
            ) {
                morningCheckinContent
            }

            stackedSection(
                id: "identity",
                title: "Identity and intention",
                subtitle: "Anchor the day in who you want to be.",
                background: WellnessTheme.sectionSand,
                isExpanded: $isIdentityExpanded,
                subtitleColor: WellnessTheme.textPrimary.opacity(0.7),
                showsTopSeparator: true,
                verticalPadding: 22
            ) {
                intentionsContent
            }

            stackedSection(
                id: "priorities",
                title: "Priorities",
                subtitle: "Choose your main focus and support tasks.",
                background: WellnessTheme.sectionSandDeep,
                isExpanded: $isPrioritiesExpanded,
                showsTopSeparator: true,
                verticalPadding: 20
            ) {
                prioritiesContent
            }

            stackedSection(
                id: "evening",
                title: "Evening reflection",
                subtitle: "Close the loop on how your day went.",
                background: WellnessTheme.sectionPeachDeep,
                isExpanded: $isEveningExpanded,
                showsTopSeparator: true,
                verticalPadding: 20
            ) {
                eveningContent
            }

            stackedSection(
                id: "tomorrow",
                title: "Tomorrow plan",
                subtitle: "Set up tomorrow’s priorities. Reminders are created automatically.",
                background: WellnessTheme.sectionSunset,
                isExpanded: $isTomorrowPlanExpanded,
                showsTopSeparator: true,
                verticalPadding: 20
            ) {
                tomorrowPlanContent
            }
        }
    }

    private func stackedSection(
        id: String,
        title: String,
        subtitle: String,
        background: Color,
        isExpanded: Binding<Bool>,
        subtitleColor: Color = WellnessTheme.textSecondary,
        showsTopSeparator: Bool = false,
        verticalPadding: CGFloat = 22,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.35)) {
                    toggleSection(isExpanded)
                }
            }) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(AppTypography.style(.headline, weight: .semibold))
                            .foregroundColor(WellnessTheme.textPrimary)

                        Text(subtitle)
                            .font(AppTypography.style(.footnote))
                            .foregroundColor(subtitleColor)
                            .lineSpacing(1.5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(AppTypography.style(.caption, weight: .semibold))
                        .foregroundColor(WellnessTheme.textSecondary)
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(alignment: .top) {
            if showsTopSeparator {
                Rectangle()
                    .fill(WellnessTheme.sectionSeparator)
                    .frame(height: 0.5)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: isExpanded.wrappedValue)
        .id(id)
    }

    private enum DayStripItem: Hashable, Identifiable {
        case day(Date)
        case weekOverview(Date)
        case monthOverview(Date)

        var id: String {
            switch self {
            case .day(let date):
                return "day-\(WellnessView.dayKeyFormatter.string(from: date))"
            case .weekOverview(let date):
                return "week-\(WellnessView.dayKeyFormatter.string(from: date))"
            case .monthOverview(let date):
                return "month-\(WellnessView.monthKeyFormatter.string(from: date))"
            }
        }
    }


    private var completionStates: [Bool] {
        [
            entry.sleepTime != nil || entry.wakeTime != nil || entry.sleepQuality > 0,
            !entry.intentionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !entry.brainDumpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !entry.mainTaskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !entry.dayRecapText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !entry.tomorrowTaskOneText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ]
    }

    private func overviewContent(kind: WellnessOverviewKind, endingAt: Date) -> some View {
        let days = daysForOverview(kind: kind, endingAt: endingAt)
        let title = kind == .week ? "Weekly overview" : "Monthly overview"
        let range = overviewRangeTitle(endingAt: endingAt, days: days)

        return VStack(alignment: .leading, spacing: 16) {
            Text(range)
                .font(AppTypography.style(.footnote, weight: .semibold))
                .foregroundColor(WellnessTheme.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(AppTypography.style(.headline, weight: .semibold))
                    .foregroundColor(WellnessTheme.textPrimary)

                if let stats = overviewStats {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Days tracked \(stats.daysTracked)/\(days)")
                        Text("Main tasks completed \(stats.mainTasksCompleted)")
                        Text("Secondary tasks completed \(stats.secondaryTasksCompleted)")
                        Text("Avg sleep \(stats.averageSleepQuality, specifier: "%.1f")/10")
                        Text("Avg mood \(stats.averageMood, specifier: "%.1f")/10")
                        Text("Avg productivity \(stats.averageProductivity, specifier: "%.1f")/10")
                        Text("Woke on time \(stats.wokeOnTimeCount)")
                        Text("Sunrise used \(stats.sunriseUsedCount)")
                    }
                    .font(AppTypography.style(.caption, weight: .medium))
                    .foregroundColor(WellnessTheme.textPrimary)
                } else {
                    Text("Not enough data yet.")
                        .font(AppTypography.style(.caption, weight: .medium))
                        .foregroundColor(WellnessTheme.textSecondary)
                }
            }

            Button("Back to daily") {
                contentMode = .daily
            }
            .font(AppTypography.style(.footnote, weight: .semibold))
            .foregroundColor(WellnessTheme.textPrimary)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(WellnessTheme.textPrimary)
                    .frame(height: 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WellnessTheme.sectionSand)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WellnessTheme.sectionSeparator)
                .frame(height: 0.5)
        }
    }

    private func autoScrollIfNeeded(previous: [Bool], current: [Bool], proxy: ScrollViewProxy) {
        guard !previous.isEmpty else { return }
        let ids = ["morning", "identity", "priorities", "evening", "tomorrow"]
        for index in 0..<min(previous.count, current.count) {
            if previous[index] == false && current[index] == true {
                let nextIndex = min(index + 1, ids.count - 1)
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(ids[nextIndex], anchor: .top)
                }
                break
            }
        }
    }

    private var dayTitle: String {
        Self.dayFormatter.string(from: selectedDate)
    }

    private var dateSubtitle: String {
        let isToday = Calendar.current.isDateInToday(selectedDate)
        let timeText = isToday ? Self.timeFormatter.string(from: Date()) : "All day"
        return "\(Self.dateFormatter.string(from: selectedDate)) • \(timeText) • \(weatherSummary)"
    }

    private var eveningPrompt: String {
        let productivity = entry.productivityRating
        let mood = entry.dayMoodRating
        let lowProductivity = productivity <= 5
        let lowMood = mood <= 5

        if lowProductivity && lowMood {
            return "What blocked you from what you want to achieve today?"
        }
        if lowProductivity && !lowMood {
            return "What happened today that made you feel great?"
        }
        if !lowProductivity && lowMood {
            return "What moved you forward today?"
        }
        return "What are you grateful for today?"
    }

    private var dayStripItems: [DayStripItem] {
        let calendar = Calendar.current
        var items: [DayStripItem] = []
        for day in rollingDates {
            let dayNumber = calendar.component(.day, from: day)
            if dayNumber == 1 {
                items.append(.monthOverview(day))
            }
            items.append(.day(day))
            if calendar.component(.weekday, from: day) == 1 {
                items.append(.weekOverview(day))
            }
        }
        return items
    }

    private var rollingDates: [Date] {
        let calendar = Calendar.current
        return (0..<30).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: rollingStartDate)
        }
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    private func dateKey(for date: Date) -> String {
        Self.dayKeyFormatter.string(from: date)
    }

    private func weekKey(for date: Date) -> String {
        "week-\(Self.dayKeyFormatter.string(from: date))"
    }

    private func monthKey(for date: Date) -> String {
        "month-\(Self.monthKeyFormatter.string(from: date))"
    }

    private func ensureRollingRangeIncludesSelected() {
        let calendar = Calendar.current
        let start = rollingStartDate
        let end = calendar.date(byAdding: .day, value: 29, to: start) ?? start
        if selectedDate < start || selectedDate > end {
            rollingStartDate = calendar.date(byAdding: .day, value: -14, to: selectedDate) ?? selectedDate
        }
    }

    private func reloadOverviewStats(for mode: WellnessContentMode) async {
        guard case .overview(let kind, let endingAt) = mode else {
            await MainActor.run { overviewStats = nil }
            return
        }
        let days = daysForOverview(kind: kind, endingAt: endingAt)
        let stats = await viewModel.loadReviewStats(endingAt: endingAt, days: days)
        await MainActor.run { overviewStats = stats }
    }

    private func daysForOverview(kind: WellnessOverviewKind, endingAt: Date) -> Int {
        switch kind {
        case .week:
            return 7
        case .month:
            return Calendar.current.range(of: .day, in: .month, for: endingAt)?.count ?? 30
        }
    }

    private func overviewRangeTitle(endingAt: Date, days: Int) -> String {
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: endingAt) ?? endingAt
        return "\(Self.rangeFormatter.string(from: start)) - \(Self.rangeFormatter.string(from: endingAt))"
    }

    private func refreshDayPhase() {
        Task {
            let now = Date()
            let phase = await resolveDayPhase(for: now)
            await MainActor.run {
                dayPhase = phase
                WellnessTheme.setPhase(phase)
            }
        }
    }

    private func resolveDayPhase(for date: Date) async -> WellnessDayPhase {
        if let sunset = await resolveSunsetTime(for: date) {
            let afternoonStart = sunset.addingTimeInterval(-2 * 3600)
            let eveningStart = sunset.addingTimeInterval(1 * 3600)
            if date >= eveningStart {
                return .evening
            }
            if date >= afternoonStart {
                return .afternoon
            }
            return .morning
        }

        let hour = Calendar.current.component(.hour, from: date)
        if hour >= 18 {
            return .evening
        }
        if hour >= 12 {
            return .afternoon
        }
        return .morning
    }

    private func resolveSunsetTime(for date: Date) async -> Date? {
        let status = CLLocationManager().authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return nil
        }
        guard let coordinate = await AutomationStore.shared.currentCoordinate() else {
            return nil
        }
        let startOfDay = Calendar.current.startOfDay(for: date)
        return SunriseSunsetCalculator.nextEventDate(
            event: .sunset,
            coordinate: coordinate,
            referenceDate: startOfDay,
            offsetMinutes: 0,
            timeZone: TimeZone.current
        )
    }

    private func scheduleSave() {
        guard !isLoadingEntry else { return }
        saveTask?.cancel()
        let snapshot = entry
        let signature = integrationSignature(for: snapshot)
        if signature != lastIntegrationSignature {
            lastIntegrationSignature = signature
            viewModel.queueIntegrationSync(for: snapshot)
        }
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await viewModel.saveEntry(snapshot)
        }
    }

    private func saveEntryNow() {
        guard !isLoadingEntry else { return }
        saveTask?.cancel()
        let snapshot = entry
        let signature = integrationSignature(for: snapshot)
        if signature != lastIntegrationSignature {
            lastIntegrationSignature = signature
            viewModel.queueIntegrationSync(for: snapshot)
        }
        Task {
            await viewModel.saveEntry(snapshot)
        }
    }

    private func reloadEntry(for date: Date) async {
        await MainActor.run { isLoadingEntry = true }
        let loadedEntry = await viewModel.loadEntry(for: date)
        await MainActor.run {
            entry = loadedEntry
            lastIntegrationSignature = integrationSignature(for: loadedEntry)
            DispatchQueue.main.async {
                isLoadingEntry = false
            }
        }
    }

    private func scheduleInitialExpand() {
        guard !hasAutoExpanded else { return }
        hasAutoExpanded = true
        collapseAllSections()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation(.easeInOut(duration: 0.25)) {
                isMorningExpanded = true
            }
        }
    }

    private func toggleSection(_ section: Binding<Bool>) {
        let wasExpanded = section.wrappedValue
        collapseAllSections()
        section.wrappedValue = !wasExpanded
    }

    private func collapseAllSections() {
        isMorningExpanded = false
        isIdentityExpanded = false
        isPrioritiesExpanded = false
        isEveningExpanded = false
        isTomorrowPlanExpanded = false
    }

    private func integrationSignature(for entry: WellnessEntrySnapshot) -> String {
        [
            entry.intentionText,
            entry.mainTaskText,
            entry.secondaryTaskOneText,
            entry.secondaryTaskTwoText,
            entry.tomorrowTaskOneText,
            entry.tomorrowTaskTwoText,
            entry.tomorrowTaskThreeText,
            entry.mainTaskDurationMinutes.description,
            entry.secondaryTaskOneDurationMinutes.description,
            entry.secondaryTaskTwoDurationMinutes.description,
            entry.tomorrowTaskOneDurationMinutes.description,
            entry.tomorrowTaskTwoDurationMinutes.description,
            entry.tomorrowTaskThreeDurationMinutes.description
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .joined(separator: "|")
    }

    private func hydrateWakeTime(force: Bool) async {
        if !force, entry.wakeTime != nil { return }
        if let wakeTime = await viewModel.fetchLatestWakeTime() {
            await MainActor.run {
                entry.wakeTime = wakeTime
            }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter
    }()

    private static let rangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let monthKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()
}

private enum WellnessOverviewKind: Hashable {
    case week
    case month
}

private enum WellnessContentMode: Hashable {
    case daily
    case overview(kind: WellnessOverviewKind, endingAt: Date)
}

private enum WellnessDayPhase: Hashable {
    case morning
    case afternoon
    case evening
}

private struct WellnessInspoBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            ZStack(alignment: .top) {
                Color(red: 0.753, green: 0.792, blue: 0.851) // #c0cad9
                    .frame(height: h * 0.40)
                Color(red: 0.792, green: 0.804, blue: 0.827) // #cacdd3
                    .frame(height: h * 0.20)
                    .offset(y: h * 0.40)
                Color(red: 0.835, green: 0.812, blue: 0.800) // #d5cfcc
                    .frame(height: h * 0.18)
                    .offset(y: h * 0.60)
                Color(red: 0.878, green: 0.824, blue: 0.773) // #e0d2c5
                    .frame(height: h * 0.06)
                    .offset(y: h * 0.78)
                Color(red: 0.914, green: 0.827, blue: 0.745) // #e9d3be
                    .frame(height: h * 0.05)
                    .offset(y: h * 0.84)
                Color(red: 0.918, green: 0.745, blue: 0.627) // #eabea0
                    .frame(height: h * 0.05)
                    .offset(y: h * 0.89)
                Color(red: 0.400, green: 0.392, blue: 0.427) // #66646d
                    .frame(height: h * 0.03)
                    .offset(y: h * 0.94)
                Color(red: 0.243, green: 0.275, blue: 0.310) // #3e464f
                    .frame(height: h * 0.03)
                    .offset(y: h * 0.97)
            }
        }
    }
}

private struct LowPolyMapleTree: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                // Ground shadow
                Ellipse()
                    .fill(Color.black.opacity(0.10))
                    .frame(width: w * 0.70, height: h * 0.12)
                    .offset(x: w * 0.20, y: h * 0.78)

                // Trunk (simple, seagull-like flat)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.52, y: h * 0.58))
                    path.addLine(to: CGPoint(x: w * 0.58, y: h * 0.58))
                    path.addLine(to: CGPoint(x: w * 0.64, y: h * 0.95))
                    path.addLine(to: CGPoint(x: w * 0.46, y: h * 0.95))
                    path.closeSubpath()
                }
                .fill(Color(red: 0.46, green: 0.36, blue: 0.28))

                // Crown pieces (flat triangles, no outlines)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.18, y: h * 0.52))
                    path.addLine(to: CGPoint(x: w * 0.52, y: h * 0.20))
                    path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.54))
                    path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.60))
                    path.closeSubpath()
                }
                .fill(Color(red: 0.92, green: 0.50, blue: 0.30))

                Path { path in
                    path.move(to: CGPoint(x: w * 0.22, y: h * 0.62))
                    path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.60))
                    path.addLine(to: CGPoint(x: w * 0.32, y: h * 0.84))
                    path.closeSubpath()
                }
                .fill(Color(red: 0.84, green: 0.40, blue: 0.26))

                Path { path in
                    path.move(to: CGPoint(x: w * 0.50, y: h * 0.60))
                    path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.86))
                    path.closeSubpath()
                }
                .fill(Color(red: 0.90, green: 0.44, blue: 0.28))
            }
        }
    }
}


private struct WellnessPalette {
    let background: Color
    let headerBackground: Color
    let surface: Color
    let surfaceStrong: Color
    let textPrimary: Color
    let textSecondary: Color
    let sectionBlue: Color
    let sectionGray: Color
    let sectionSand: Color
    let sectionSandDeep: Color
    let sectionPeach: Color
    let sectionPeachDeep: Color
    let sectionSunset: Color
    let sectionSunsetDeep: Color
    let sectionSeparator: Color
}

private enum WellnessTheme {
    private static var currentPhase: WellnessDayPhase = .morning
    private static let sharedText = GlassTheme.text(for: .light)

    static func setPhase(_ phase: WellnessDayPhase) {
        currentPhase = phase
    }

    // Blended palette: user-provided wellness colors softened toward AppBackground neutrals.
    private static let morning = WellnessPalette(
        background: Color.clear,
        headerBackground: Color(red: 0.780, green: 0.808, blue: 0.835), // neutral blue-gray
        surface: Color.white.opacity(0.58),
        surfaceStrong: Color.white.opacity(0.84),
        textPrimary: sharedText.pagePrimaryText,
        textSecondary: sharedText.pageSecondaryText.opacity(0.95),
        sectionBlue: Color(red: 0.816, green: 0.831, blue: 0.847),
        sectionGray: Color(red: 0.816, green: 0.831, blue: 0.847),
        sectionSand: Color(red: 0.851, green: 0.831, blue: 0.804),
        sectionSandDeep: Color(red: 0.871, green: 0.847, blue: 0.812),
        sectionPeach: Color(red: 0.890, green: 0.867, blue: 0.831),
        sectionPeachDeep: Color(red: 0.890, green: 0.867, blue: 0.831),
        sectionSunset: Color(red: 0.906, green: 0.875, blue: 0.831),
        sectionSunsetDeep: Color(red: 0.243, green: 0.275, blue: 0.310), // #3e464f
        sectionSeparator: Color.black.opacity(0.05)
    )

    private static let afternoon = WellnessPalette(
        background: Color.clear,
        headerBackground: Color(red: 0.773, green: 0.800, blue: 0.820),
        surface: Color.white.opacity(0.58),
        surfaceStrong: Color.white.opacity(0.84),
        textPrimary: sharedText.pagePrimaryText,
        textSecondary: sharedText.pageSecondaryText.opacity(0.98),
        sectionBlue: Color(red: 0.812, green: 0.824, blue: 0.835),
        sectionGray: Color(red: 0.812, green: 0.824, blue: 0.835),
        sectionSand: Color(red: 0.851, green: 0.824, blue: 0.792),
        sectionSandDeep: Color(red: 0.875, green: 0.839, blue: 0.800),
        sectionPeach: Color(red: 0.898, green: 0.859, blue: 0.816),
        sectionPeachDeep: Color(red: 0.898, green: 0.859, blue: 0.816),
        sectionSunset: Color(red: 0.906, green: 0.859, blue: 0.788),
        sectionSunsetDeep: Color(red: 0.243, green: 0.275, blue: 0.310),
        sectionSeparator: Color.black.opacity(0.055)
    )

    private static let evening = WellnessPalette(
        background: Color.clear,
        headerBackground: Color(red: 0.757, green: 0.784, blue: 0.812),
        surface: Color.white.opacity(0.56),
        surfaceStrong: Color.white.opacity(0.82),
        textPrimary: sharedText.pagePrimaryText.opacity(0.98),
        textSecondary: sharedText.pageSecondaryText.opacity(1.0),
        sectionBlue: Color(red: 0.800, green: 0.812, blue: 0.827),
        sectionGray: Color(red: 0.800, green: 0.812, blue: 0.827),
        sectionSand: Color(red: 0.843, green: 0.816, blue: 0.788),
        sectionSandDeep: Color(red: 0.867, green: 0.831, blue: 0.792),
        sectionPeach: Color(red: 0.886, green: 0.847, blue: 0.804),
        sectionPeachDeep: Color(red: 0.886, green: 0.847, blue: 0.804),
        sectionSunset: Color(red: 0.898, green: 0.851, blue: 0.780),
        sectionSunsetDeep: Color(red: 0.243, green: 0.275, blue: 0.310),
        sectionSeparator: Color.black.opacity(0.06)
    )

    private static var palette: WellnessPalette {
        switch currentPhase {
        case .morning:
            return morning
        case .afternoon:
            return afternoon
        case .evening:
            return evening
        }
    }

    static var background: Color { palette.background }
    static var headerBackground: Color { palette.headerBackground }
    static var surface: Color { palette.surface }
    static var surfaceStrong: Color { palette.surfaceStrong }
    static var textPrimary: Color { palette.textPrimary }
    static var textSecondary: Color { palette.textSecondary }
    static var sectionBlue: Color { palette.sectionBlue }
    static var sectionGray: Color { palette.sectionGray }
    static var sectionSand: Color { palette.sectionSand }
    static var sectionSandDeep: Color { palette.sectionSandDeep }
    static var sectionPeach: Color { palette.sectionPeach }
    static var sectionPeachDeep: Color { palette.sectionPeachDeep }
    static var sectionSunset: Color { palette.sectionSunset }
    static var sectionSunsetDeep: Color { palette.sectionSunsetDeep }
    static var sectionSeparator: Color { palette.sectionSeparator }
}

private struct RatingDots: View {
    @Binding var rating: Int
    let maxRating: Int
    let isLocked: Bool
    private let dotSize: CGFloat = 12
    private let spacing: CGFloat = 10

    var body: some View {
        let totalWidth = dotSize * CGFloat(maxRating) + spacing * CGFloat(maxRating - 1)

        HStack(spacing: spacing) {
            ForEach(1...maxRating, id: \ .self) { index in
                Circle()
                    .fill(index <= rating ? WellnessTheme.textPrimary : Color.clear)
                    .frame(width: dotSize, height: dotSize)
                    .overlay(
                        Circle()
                            .stroke(WellnessTheme.textSecondary.opacity(0.35), lineWidth: index <= rating ? 0 : 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isLocked else { return }
                        rating = index
                    }
            }
        }
        .frame(width: totalWidth, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !isLocked else { return }
                    let clampedX = min(max(0, value.location.x), totalWidth)
                    let rawIndex = Int((clampedX / totalWidth) * CGFloat(maxRating))
                    rating = min(maxRating, max(1, rawIndex + 1))
                }
        )
        .disabled(isLocked)
    }
}

private struct CheckDot: View {
    let isOn: Bool

    var body: some View {
        Circle()
            .fill(isOn ? WellnessTheme.sectionBlue : WellnessTheme.surface)
            .frame(width: 16, height: 16)
            .overlay(
                Circle()
                    .stroke(WellnessTheme.textSecondary.opacity(0.4), lineWidth: isOn ? 0 : 1)
            )
            .overlay(
                Image(systemName: "checkmark")
                    .font(AppTypography.style(.caption2, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(isOn ? 1 : 0)
            )
    }
}

private struct CapsulePicker<Option: Identifiable & Hashable & CustomStringConvertible>: View {
    let options: [Option]
    @Binding var selection: Option
    let isLocked: Bool

    var body: some View {
        HStack(spacing: 12) {
            ForEach(options) { option in
                Button(action: { selection = option }) {
                    Text(option.description)
                        .font(AppTypography.style(.caption, weight: .semibold))
                        .foregroundColor(selection == option ? WellnessTheme.textPrimary : WellnessTheme.textSecondary)
                        .padding(.vertical, 4)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(selection == option ? WellnessTheme.textPrimary : Color.clear)
                                .frame(height: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(isLocked)
            }
        }
    }
}

private struct WellnessTextEditor: View {
    @Binding var text: String
    let placeholder: String
    let isLocked: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(WellnessTheme.surface.opacity(0.55))
                .frame(minHeight: 110)
            TextEditor(text: $text)
                .font(AppTypography.style(.footnote, weight: .medium))
                .foregroundColor(WellnessTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .disabled(isLocked)
            if text.isEmpty {
                Text(placeholder)
                    .font(AppTypography.style(.footnote, weight: .medium))
                    .foregroundColor(WellnessTheme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
            }
        }
    }
}

private struct WellnessLineTextField: View {
    @Binding var text: String
    let placeholder: String
    let isLocked: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .font(AppTypography.style(.footnote, weight: .medium))
            .foregroundColor(WellnessTheme.textPrimary)
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(WellnessTheme.textSecondary.opacity(0.4))
                    .frame(height: 1)
            }
            .disabled(isLocked)
    }
}

private struct TaskRow: View {
    let index: Int
    @Binding var text: String
    @Binding var durationMinutes: Int
    @Binding var isCompleted: Bool
    let isPrimary: Bool
    let isLocked: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index).")
                .font(AppTypography.style(.footnote, weight: .semibold))
                .foregroundColor(WellnessTheme.textSecondary)
                .frame(width: 20, alignment: .leading)

            TextField(isPrimary ? "Most important task" : "Secondary task", text: $text)
                .font(AppTypography.style(.footnote, weight: isPrimary ? .semibold : .medium))
                .foregroundColor(WellnessTheme.textPrimary)
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(WellnessTheme.textSecondary.opacity(0.4))
                        .frame(height: 1)
                }
                .disabled(isLocked)

            DurationMenu(durationMinutes: $durationMinutes, isLocked: isLocked)

            Button(action: { isCompleted.toggle() }) {
                CheckDot(isOn: isCompleted)
            }
            .buttonStyle(.plain)
            .disabled(isLocked)
        }
    }
}

private struct PlanTaskRow: View {
    let index: Int
    @Binding var text: String
    @Binding var durationMinutes: Int
    let isLocked: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index).")
                .font(AppTypography.style(.footnote, weight: .semibold))
                .foregroundColor(WellnessTheme.textSecondary)
                .frame(width: 20, alignment: .leading)

            TextField("Tomorrow task", text: $text)
                .font(AppTypography.style(.footnote, weight: .medium))
                .foregroundColor(WellnessTheme.textPrimary)
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(WellnessTheme.textSecondary.opacity(0.4))
                        .frame(height: 1)
                }
                .disabled(isLocked)

            DurationMenu(durationMinutes: $durationMinutes, isLocked: isLocked)
        }
    }
}

private struct DurationMenu: View {
    @Binding var durationMinutes: Int
    let isLocked: Bool
    @State private var isInteracting: Bool = false
    @State private var fadeTask: Task<Void, Never>? = nil

    private let options: [Int] = [0, 15, 30, 45, 60, 90, 120, 150, 180]

    var body: some View {
        let arrowOpacity: Double = isInteracting ? 1 : 0.25

        HStack(spacing: 6) {
            Button(action: {
                step(-1)
                bumpArrowVisibility()
            }) {
                Image(systemName: "chevron.left")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(WellnessTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .opacity(arrowOpacity)
            .disabled(isLocked)

            Text(label(for: durationMinutes))
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(WellnessTheme.textPrimary)
                .frame(width: 78, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { _ in
                            bumpArrowVisibility()
                        }
                        .onEnded { value in
                            let stepCount = Int(round(value.translation.width / 32))
                            if stepCount != 0 {
                                step(stepCount < 0 ? 1 : -1, amount: abs(stepCount))
                            }
                            bumpArrowVisibility()
                        }
                )

            Button(action: {
                step(1)
                bumpArrowVisibility()
            }) {
                Image(systemName: "chevron.right")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(WellnessTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .opacity(arrowOpacity)
            .disabled(isLocked)
        }
        .animation(.easeInOut(duration: 0.2), value: isInteracting)
    }

    private func label(for value: Int) -> String {
        if value == 0 { return "No time" }
        if value < 60 { return "\(value) min" }
        let hours = value / 60
        let minutes = value % 60
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes) min"
    }

    private func step(_ delta: Int, amount: Int = 1) {
        guard let index = options.firstIndex(of: durationMinutes) else {
            durationMinutes = options.dropFirst().first ?? durationMinutes
            return
        }
        let nextIndex = max(0, min(options.count - 1, index + (delta * amount)))
        durationMinutes = options[nextIndex]
    }

    private func bumpArrowVisibility() {
        guard !isLocked else { return }
        fadeTask?.cancel()
        isInteracting = true
        fadeTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isInteracting = false
                }
            }
        }
    }
}

private struct WellnessDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date
    @State private var tempDate: Date = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker(
                    "Select date",
                    selection: $tempDate,
                    in: dateRange,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .tint(WellnessTheme.textPrimary)
                .padding(.horizontal, 16)

                Button("Go to date") {
                    selectedDate = tempDate
                    dismiss()
                }
                .font(AppTypography.style(.body, weight: .semibold))
                .foregroundColor(WellnessTheme.textPrimary)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(WellnessTheme.surfaceStrong)
                .clipShape(Capsule())

                Spacer()
            }
            .padding(.top, 12)
            .background(WellnessTheme.background)
            .navigationTitle("Pick a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                tempDate = selectedDate
            }
        }
    }

    private var dateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .year, value: -2, to: Date()) ?? Date()
        let end = calendar.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        return start...end
    }
}

private struct WellnessTimePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var selectedTime: Date?
    let referenceDate: Date
    let defaultHour: Int
    let defaultMinute: Int
    @State private var tempTime: Date = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker(
                    title,
                    selection: $tempTime,
                    displayedComponents: [.hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .tint(WellnessTheme.textPrimary)
                .padding(.horizontal, 16)

                Button("Set time") {
                    selectedTime = tempTime
                    dismiss()
                }
                .font(AppTypography.style(.body, weight: .semibold))
                .foregroundColor(WellnessTheme.textPrimary)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(WellnessTheme.surfaceStrong)
                .clipShape(Capsule())

                Spacer()
            }
            .padding(.top, 12)
            .background(WellnessTheme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                tempTime = selectedTime ?? defaultTime
            }
        }
    }

    private var defaultTime: Date {
        Calendar.current.date(bySettingHour: defaultHour, minute: defaultMinute, second: 0, of: referenceDate) ?? referenceDate
    }
}

private struct WellnessHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: WellnessViewModel
    @State private var entries: [WellnessEntrySummary] = []

    var body: some View {
        NavigationStack {
            ZStack {
                WellnessTheme.background
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        ForEach(entries) { item in
                            HistoryRow(item: item)
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                entries = await viewModel.loadHistory(limit: 60)
            }
        }
    }
}

private struct HistoryRow: View {
    let item: WellnessEntrySummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(moodColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(Self.dateFormatter.string(from: item.date))
                    .font(AppTypography.style(.footnote, weight: .semibold))
                    .foregroundColor(WellnessTheme.textPrimary)
                Text(item.summary)
                    .font(AppTypography.style(.caption, weight: .medium))
                    .foregroundColor(WellnessTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(1...5, id: \ .self) { index in
                    Circle()
                        .fill(index <= item.moodRating ? WellnessTheme.textPrimary.opacity(0.7) : WellnessTheme.surface)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(12)
        .background(WellnessTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var moodColor: Color {
        switch item.moodRating {
        case 5: return WellnessTheme.textPrimary
        case 4: return WellnessTheme.textPrimary.opacity(0.8)
        case 3: return WellnessTheme.textPrimary.opacity(0.6)
        case 2: return WellnessTheme.textPrimary.opacity(0.45)
        default: return WellnessTheme.textPrimary.opacity(0.3)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()
}

struct WellnessView_Previews: PreviewProvider {
    static var previews: some View {
        WellnessView()
            .environmentObject(WellnessViewModel())
    }
}
