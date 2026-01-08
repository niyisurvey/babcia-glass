import SwiftUI
import Presentation
import Common
import Core
import UIKit

enum RoomImageAction {
    case scan
    case verify
}

struct ManualToggleIntent: Identifiable {
    let id = UUID()
    let taskID: UUID
    let markComplete: Bool
}

struct RoomDetailView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    let roomID: UUID

    @State private var showingCameraMenu = false
    @State private var showingSourceMenu = false
    @State private var showingManualOverrideConfirm = false
    @State private var showingImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var imagePickerAction: RoomImageAction = .scan
    @State private var pendingManualToggle: ManualToggleIntent?

    private var room: Room? {
        appViewModel.rooms.first { $0.id == roomID }
    }

    var body: some View {
        Group {
            if let room {
                GeometryReader { proxy in
                    // Use a stable screen-based height so background alignment cannot “flip” due to layout negotiation.
                    let heroHeight = min(UIScreen.main.bounds.height * 0.55, 420)
                    ZStack {
                        roomDetailBackground(character: room.character)

                        ScrollView {
                            VStack(spacing: BabciaSpacing.sectionGap) {
                                RoomHeroHeader(
                                    room: room,
                                    backgroundColor: roomDetailBaseColor,
                                    height: heroHeight
                                )

                                VStack(alignment: .leading, spacing: BabciaSpacing.sectionGap) {
                                    RoomModeSummary(room: room, modeCharacter: appViewModel.settings.selectedCharacter)

                                    if let advice = room.babciaAdvice, !advice.isEmpty {
                                        AdviceCard(message: advice)
                                    }

                                    if room.tasks.isEmpty {
                                        EmptyTasksCard()
                                    } else {
                                        VerificationSummaryCard(room: room)

                                        TaskList(room: room) { task, markComplete in
                                            if markComplete {
                                                pendingManualToggle = ManualToggleIntent(taskID: task.id, markComplete: true)
                                            } else {
                                                appViewModel.setManualTask(roomID: room.id, taskID: task.id, isCompleted: false)
                                            }
                                        }

                                        if let lastVerified = room.lastVerifiedAt {
                                            Text("Last verified: \(lastVerified.formatted(date: .abbreviated, time: .shortened))")
                                                .font(.babcia(.caption))
                                                .foregroundColor(.secondary)
                                        }

                                        if room.manualOverrideAvailable {
                                            ManualOverrideCard(
                                                isTrusted: appViewModel.settings.selectedCharacter == .wellnessX,
                                                onOverride: { showingManualOverrideConfirm = true }
                                            )
                                        }
                                    }

                                    AutoScanCard(room: room)

                                    RoomStatsBar(room: room)
                                }
                                .babciaScreenPadding()
                            }
                        }
                        // Remove the NavigationStack's automatic top inset so the hero sits flush.
                        .contentMargins(.top, -proxy.safeAreaInsets.top, for: .scrollContent)
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingCameraMenu = true
                        } label: {
                            Image(systemName: BabciaIcon.camera.systemName)
                        }
                        .accessibilityLabel("Room camera options")
                    }
                }
                .confirmationDialog("Room Camera", isPresented: $showingCameraMenu) {
                    Button("Verify Room") {
                        imagePickerAction = .verify
                        showingSourceMenu = true
                    }
                    Button("Change Baseline") {
                        imagePickerAction = .scan
                        showingSourceMenu = true
                    }
                }
                .confirmationDialog("Select Source", isPresented: $showingSourceMenu) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take Photo") {
                            imagePickerSource = .camera
                            showingImagePicker = true
                        }
                    }
                    Button("Choose Photo") {
                        imagePickerSource = .photoLibrary
                        showingImagePicker = true
                    }
                    if room.imageSource == .homeAssistant {
                        Button("Home Assistant Snapshot") {
                            if imagePickerAction == .scan {
                                appViewModel.scanHomeAssistant(roomID: room.id)
                            } else {
                                appViewModel.verifyHomeAssistant(roomID: room.id)
                            }
                        }
                    }
                }
                .sheet(isPresented: $showingImagePicker) {
                    ImagePicker(sourceType: imagePickerSource) { image in
                        let source: CaptureSource = imagePickerSource == .camera ? .camera : .manual
                        switch imagePickerAction {
                        case .scan:
                            appViewModel.scanRoom(roomID: room.id, image: image, captureSource: source)
                        case .verify:
                            appViewModel.verifyRoom(roomID: room.id, image: image, captureSource: source)
                        }
                    }
                }
                .alert(item: $pendingManualToggle) { intent in
                    let messageText = appViewModel.settings.selectedCharacter == .wellnessX
                        ? "Trusted mode grants XP immediately for manual checks."
                        : "Manual checks do not grant XP until Babcia verifies."
                    return Alert(
                        title: Text("Mark as done?"),
                        message: Text(messageText),
                        primaryButton: .default(Text("Mark")) {
                            appViewModel.setManualTask(roomID: room.id, taskID: intent.taskID, isCompleted: intent.markComplete)
                        },
                        secondaryButton: .cancel()
                    )
                }
                .alert("Manual override", isPresented: $showingManualOverrideConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Override", role: .destructive) {
                        appViewModel.manualOverride(roomID: room.id)
                    }
                } message: {
                    let messageText = appViewModel.settings.selectedCharacter == .wellnessX
                        ? "Trusted mode grants XP immediately for manual completions."
                        : "Babcia prefers a real scan. Manual override logs self-declared completion and grants no XP."
                    Text(messageText)
                }
            } else {
                Text("Room not found")
                    .font(.babcia(.headingSm))
            }
        }
    }

    private var roomDetailBaseColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.043, green: 0.063, blue: 0.149) // ~ #0B1026
        }
        return Color(.systemBackground)
    }

    @ViewBuilder
    private func roomDetailBackground(character: BabciaCharacter) -> some View {
        // Use the semantic surface token so the page background adapts to dark/light and accessibility.
        roomDetailBaseColor
            .ignoresSafeArea()
    }
}

struct RoomHeroHeader: View {
    let room: Room
    let backgroundColor: Color
    let height: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backgroundColor

            heroImage
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: BabciaSpacing.xs) {
                        Text(room.name)
                            .font(.babcia(.displaySm))
                            .foregroundStyle(.primary)

                        Text(room.character.displayName)
                            .font(.babcia(.caption))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, BabciaSpacing.screenHorizontal)
                    .padding(.bottom, BabciaSpacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        if #available(iOS 26.0, *) {
                            // Use the existing babcia wrapper for Liquid Glass on modern iOS.
                            Color.clear.babciaGlassEffect(.regular)
                        } else {
                            // System Material fallback for adaptive vibrancy / legibility.
                            Rectangle()
                                .fill(.ultraThinMaterial)
                        }
                    }
                }
        }

        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .top)
    }



    private var heroImage: some View {
        ZStack {
            if let url = room.dreamVisionURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(room.character.portraitAssetName)
                            .resizable()
                            .scaledToFill()
                    }
                }
            } else {
                Image(room.character.portraitAssetName)
                    .resizable()
                    .scaledToFill()
            }
        }
    }
}

struct RoomModeSummary: View {
    let room: Room
    let modeCharacter: BabciaCharacter

    var body: some View {
        let accent = Color(hex: room.character.accentHex)
        HStack(spacing: BabciaSpacing.md) {
            Image(room.character.headshotAssetName)
                .resizable()
                .scaledToFill()
                .frame(width: BabciaSize.avatarMd, height: BabciaSize.avatarMd)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(accent, lineWidth: 2)
                )

            VStack(alignment: .leading, spacing: BabciaSpacing.xxs) {
                Text("Mode: \(modeCharacter.verificationModeName)")
                    .font(.babcia(.headingSm))
                Text(modeCharacter.verificationModeDescription)
                    .font(.babcia(.caption))
                    .foregroundColor(.secondary)
                Text("Room Babcia: \(room.character.displayName)")
                    .font(.babcia(.caption))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .babciaCardPadding()
        .babciaGlassCard()
        .babciaFullWidthLeading()
    }
}

struct VerificationSummaryCard: View {
    let room: Room

    private var verifiedCount: Int {
        room.tasks.filter { $0.verificationState == .verified }.count
    }

    private var manualCount: Int {
        room.tasks.filter { $0.verificationState == .manual }.count
    }

    private var pendingCount: Int {
        room.pendingTaskCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BabciaSpacing.sm) {
            Text("Verification")
                .font(.babcia(.headingSm))

            Text("Use the top camera button to verify or update the room baseline.")
                .font(.babcia(.caption))
                .foregroundColor(.secondary)

            HStack(spacing: BabciaSpacing.sm) {
                VerificationPill(title: "Verified", value: "\(verifiedCount)")
                VerificationPill(title: "Manual", value: "\(manualCount)")
                VerificationPill(title: "Pending", value: "\(pendingCount)")
            }
        }
        .babciaCardPadding()
        .babciaGlassCard()
        .babciaFullWidthLeading()
    }
}

struct VerificationPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: BabciaSpacing.xxs) {
            Text(value)
                .font(.babcia(.headingSm))
            Text(title)
                .font(.babcia(.caption))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, BabciaSpacing.sm)
        .padding(.vertical, BabciaSpacing.xs)
        .babciaGlassCard(style: .subtle, cornerRadius: BabciaCorner.chip, shadow: .none, fullWidth: false)
        .frame(maxWidth: .infinity, minHeight: BabciaSize.touchMin)
    }
}

struct AdviceCard: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.babcia(.bodyLg))
            .foregroundColor(.primary)
            .babciaCardPadding()
            .babciaGlassCard()
            .babciaFullWidthLeading()
    }
}

struct EmptyTasksCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: BabciaSpacing.sm) {
            Text("No tasks yet")
                .font(.babcia(.headingSm))

            Text("Use the top camera button to scan this room and generate tasks.")
                .font(.babcia(.caption))
                .foregroundColor(.secondary)
        }
        .babciaCardPadding()
        .babciaGlassCard()
        .babciaFullWidthLeading()
    }
}

struct TaskList: View {
    let room: Room
    let onToggle: (CleaningTask, Bool) -> Void
    @Namespace private var taskNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: BabciaSpacing.sm) {
            Text("Tasks")
                .font(.babcia(.headingSm))

            BabciaGlassGroup(spacing: 8) {
                ForEach(room.tasks) { task in
                    TaskRow(
                        task: task,
                        onToggle: { onToggle(task, $0) }
                    )
                    .babciaGlassEffectID(task.id, in: taskNamespace)
                }
            }
        }
        .babciaCardPadding()
        .babciaGlassCard()
        .babciaFullWidthLeading()
    }
}

struct TaskRow: View {
    let task: CleaningTask
    let onToggle: (Bool) -> Void

    private var isLocked: Bool {
        task.verificationState == .verified
    }

    var body: some View {
        HStack(spacing: BabciaSpacing.md) {
            Button(action: {
                guard !isLocked else { return }
                onToggle(!task.isCompleted)
            }) {
                Image(systemName: task.isCompleted ? BabciaIcon.taskComplete.systemName : BabciaIcon.taskPending.systemName)
                    .foregroundColor(task.isCompleted ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(isLocked)
            .accessibilityLabel(task.isCompleted ? "Mark task incomplete" : "Mark task complete")

            Text(task.title)
                .font(.babcia(.bodyLg))
                .foregroundColor(.primary)
                .strikethrough(task.isCompleted, color: .secondary)

            Spacer()

            let override = (task.verificationNote ?? "").localizedCaseInsensitiveContains("trusted") ? "Trusted" : nil
            TaskStatusChip(state: task.resolvedVerificationState, labelOverride: override)

            Text("+\(task.xpReward)")
                .font(.babcia(.caption))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, BabciaSpacing.xs)
        .animation(BabciaAnimation.springSubtle, value: task.isCompleted)
    }
}

struct TaskStatusChip: View {
    let state: TaskVerificationState
    let labelOverride: String?

    init(state: TaskVerificationState, labelOverride: String? = nil) {
        self.state = state
        self.labelOverride = labelOverride
    }

    private var label: String {
        if let labelOverride { return labelOverride }
        switch state {
        case .verified:
            return "Verified"
        case .manual:
            return "Manual"
        case .pending:
            return "Pending"
        }
    }

    private var tint: Color {
        switch state {
        case .verified:
            return .green
        case .manual:
            return .orange
        case .pending:
            return .secondary
        }
    }

    var body: some View {
        Text(label)
            .font(.babcia(.caption))
            .foregroundColor(tint)
            .padding(.horizontal, BabciaSpacing.sm)
            .padding(.vertical, BabciaSpacing.xxs)
            .babciaGlassCard(style: .subtle, cornerRadius: BabciaCorner.chip, shadow: .none, fullWidth: false)
            .frame(minWidth: BabciaSpacing.massive, minHeight: BabciaSize.touchMin)
    }
}

struct ManualOverrideCard: View {
    let isTrusted: Bool
    let onOverride: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BabciaSpacing.sm) {
            Text("Babcia is unsure")
                .font(.babcia(.headingSm))

            Text(isTrusted
                 ? "Trusted mode allows manual completion with XP."
                 : "Try a clearer scan using the top camera button, or manually override if you must. This is logged as self-declared.")
                .font(.babcia(.caption))
                .foregroundColor(.secondary)

            Button(action: onOverride) {
                Text("Manual override")
                    .font(.babcia(.captionBold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, BabciaSpacing.sm)
                    .padding(.vertical, BabciaSpacing.xs)
            }
            .babciaGlassButton()
            .accessibilityLabel("Manual override")
        }
        .babciaCardPadding()
        .babciaGlassCard()
        .babciaFullWidthLeading()
    }
}

struct AutoScanCard: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    let room: Room

    private var schedule: ScanSchedule {
        room.scanSchedule ?? ScanSchedule(cadence: .daily, enabled: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BabciaSpacing.md) {
            Text("Auto Scan")
                .font(.babcia(.headingSm))

            Toggle("Enable auto scan", isOn: Binding(
                get: { schedule.enabled },
                set: { appViewModel.updateRoomSchedule(roomID: room.id, enabled: $0, cadence: schedule.cadence) }
            ))
            .toggleStyle(SwitchToggleStyle(tint: .green))

            Picker("Cadence", selection: Binding(
                get: { schedule.cadence },
                set: { appViewModel.updateRoomSchedule(roomID: room.id, enabled: schedule.enabled, cadence: $0) }
            )) {
                ForEach(ScanCadence.allCases, id: \.self) { cadence in
                    Text(cadence.displayName).tag(cadence)
                }
            }
            .pickerStyle(.segmented)

            if let nextRun = schedule.nextRun {
                Text("Next scan: \(nextRun.formatted(date: .abbreviated, time: .shortened))")
                    .font(.babcia(.caption))
                    .foregroundColor(.secondary)
            } else {
                Text("Next scan will be scheduled after enabling.")
                    .font(.babcia(.caption))
                    .foregroundColor(.secondary)
            }

            Text(scheduleNote)
                .font(.babcia(.caption))
                .foregroundColor(.secondary)
        }
        .babciaCardPadding()
        .babciaGlassCard()
        .babciaFullWidthLeading()
    }

    private var scheduleNote: String {
        if room.imageSource == .homeAssistant {
            return "Home Assistant rooms can auto-scan in the background."
        }
        return "Manual rooms receive reminders to scan."
    }
}

struct RoomStatsBar: View {
    let room: Room

    var body: some View {
        HStack(spacing: BabciaSpacing.md) {
            StatPill(title: "XP", value: "\(room.totalXP)")
            StatPill(title: "Streak", value: "\(room.streak)d")
            StatPill(title: "Done", value: "\(room.completedTaskCount)")
        }
    }
}

struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: BabciaSpacing.xxs) {
            Text(value)
                .font(.babcia(.headingSm))
                .foregroundColor(.primary)
            Text(title)
                .font(.babcia(.caption))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, BabciaSpacing.sm)
        .padding(.vertical, BabciaSpacing.xs)
        .babciaGlassCard(style: .subtle, cornerRadius: BabciaCorner.chip, shadow: .none, fullWidth: false)
        .frame(maxWidth: .infinity, minHeight: BabciaSize.touchMin)
    }
}
