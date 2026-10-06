import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum SettingsPane: String {
    // Keep "general" assigned to Scrolling because earlier versions stored that value.
    case general = "permissions"
    case scrolling = "general"
    case navigation
    case about
}

// The settings window always draws on black, so the palette is fixed and does not follow
// the system appearance.
private enum Palette {
    static let canvasLevel = 48.0 / 255.0
    static let canvas = Color(white: canvasLevel)
    static let tile = Color(white: 0.275)
    static let selection = Color(white: 0.305)
    static let hover = Color(white: 0.24)
    static let textPrimary = Color(white: 0.97)
    static let textSecondary = Color(white: 0.68)
    static let accent = Color(white: 0.97)
    static let switchOn = Color(white: 0.48)
    static let warning = Color.orange
    static let success = Color.green
    static let error = Color.red
}

private enum SettingsSpacing {
    static let compact: CGFloat = 4
    static let inline: CGFloat = 8
    static let row: CGFloat = 12
    static let inset: CGFloat = 16
    static let section: CGFloat = 20
    static let spacious: CGFloat = 24
}

struct SettingsView: View {
    @AppStorage("selectedSettingsPane") private var selectedPane: SettingsPane = .general
    @State private var hoveredPane: SettingsPane?
    @State private var isKeyboardInputActive = false

    let settings: AppSettings
    let recorder: MouseButtonRecorder
    let navigation: NavigationEngine
    let generalSettings: GeneralSettingsModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Group {
                switch selectedPane {
                case .general:
                    GeneralSettingsView(
                        model: generalSettings,
                        settings: settings,
                        isKeyboardInputActive: isKeyboardInputActive
                    )
                case .scrolling:
                    ScrollingSettingsView(settings: settings, recorder: recorder)
                case .navigation:
                    NavigationSettingsView(settings: settings, recorder: recorder, navigation: navigation)
                case .about:
                    AboutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 30)
            .padding(.vertical, 22)
            .id(selectedPane)
        }
        .frame(width: 700, height: 520)
        .background(Palette.canvas)
        .preferredColorScheme(.dark)
        .background(SettingsWindowChrome().allowsHitTesting(false))
        .background {
            SettingsInputMonitor { isKeyboardInput in
                guard isKeyboardInputActive != isKeyboardInput else { return }
                isKeyboardInputActive = isKeyboardInput
            }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onAppear {
            isKeyboardInputActive = false
        }
        .onChange(of: selectedPane) { _, _ in
            recorder.cancel()
        }
        .onDisappear {
            recorder.cancel()
            isKeyboardInputActive = false
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: SettingsSpacing.compact) {
            sidebarButton("General", systemImage: "gearshape", pane: .general)
            sidebarButton("Scrolling", systemImage: "arrow.up.and.down", pane: .scrolling)
            sidebarButton("Navigation", systemImage: "arrow.left.arrow.right", pane: .navigation)
            sidebarButton("About", systemImage: "info.circle", pane: .about)
                .padding(.top, SettingsSpacing.inset)

            Spacer()
        }
        .padding(.horizontal, SettingsSpacing.inline)
        // Keep the first navigation row below the pane heading and clear of
        // the traffic lights, measuring the margin inward from the window's safe area.
        .safeAreaPadding(.top, 36)
        .padding(.bottom, SettingsSpacing.inset)
        .frame(width: 180)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func sidebarButton(_ title: String, systemImage: String, pane: SettingsPane) -> some View {
        let isSelected = selectedPane == pane

        return Button {
            selectedPane = pane
        } label: {
            HStack(spacing: SettingsSpacing.inline) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 13, weight: .medium))

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                isSelected ? Palette.selection : Palette.hover.opacity(hoveredPane == pane ? 1 : 0),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled(!isKeyboardInputActive)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hoveredPane = $0 ? pane : nil }
    }
}

@MainActor
private struct SettingsInputMonitor: NSViewRepresentable {
    let onInputModeChange: (Bool) -> Void

    func makeNSView(context: Context) -> SettingsInputMonitorView {
        let view = SettingsInputMonitorView()
        view.onInputModeChange = onInputModeChange
        return view
    }

    func updateNSView(_ view: SettingsInputMonitorView, context: Context) {
        view.onInputModeChange = onInputModeChange
    }

    static func dismantleNSView(_ view: SettingsInputMonitorView, coordinator: ()) {
        view.removeEventMonitor()
    }
}

@MainActor
private final class SettingsInputMonitorView: NSView {
    var onInputModeChange: ((Bool) -> Void)?

    private weak var monitoredWindow: NSWindow?
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installEventMonitorIfNeeded()
    }

    func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        monitoredWindow = nil
    }

    private func installEventMonitorIfNeeded() {
        guard let window else {
            removeEventMonitor()
            return
        }
        guard eventMonitor == nil || monitoredWindow !== window else { return }

        removeEventMonitor()
        monitoredWindow = window
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.isSettingsWindowEvent(event) else { return }
                self.onInputModeChange?(event.type == .keyDown)
            }
            return event
        }
    }

    private func isSettingsWindowEvent(_ event: NSEvent) -> Bool {
        guard let monitoredWindow, let eventWindow = event.window else { return false }
        return eventWindow === monitoredWindow || eventWindow.sheetParent === monitoredWindow
    }
}

private struct SettingsWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SettingsWindowChromeView()
    }

    func updateNSView(_: NSView, context: Context) {}
}

@MainActor
private final class SettingsWindowChromeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        guard let window else { return }

        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.backgroundColor = NSColor(calibratedWhite: Palette.canvasLevel, alpha: 1)
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
    }
}

private struct PaneHeader: View {
    let systemImage: String?
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsSpacing.row) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Palette.tile, in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: SettingsSpacing.compact) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)

                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SettingsSpacing.inset)
            .background(Palette.tile, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct DetectionBadge {
    let title: String
    let symbol: String?
    let color: Color
}

private struct ButtonDetectionRow: View {
    let title: String
    let description: String
    let badge: DetectionBadge
    let accessibilityHint: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: SettingsSpacing.row) {
            VStack(alignment: .leading, spacing: SettingsSpacing.compact) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)

                Text(description)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                    .frame(height: 30, alignment: .topLeading)
            }

            Spacer(minLength: SettingsSpacing.inline)

            Button(action: action) {
                HStack(spacing: SettingsSpacing.inline) {
                    if let symbol = badge.symbol {
                        Image(systemName: symbol)
                            .accessibilityHidden(true)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .tint(badge.color)
                            .accessibilityHidden(true)
                    }

                    Text(badge.title)
                        .lineLimit(1)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(badge.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minWidth: 144)
                .background(badge.color.opacity(0.13), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(badge.title))
            .accessibilityHint(Text(accessibilityHint))
        }
    }
}

private struct ScrollingSettingsView: View {
    @Bindable var settings: AppSettings
    let recorder: MouseButtonRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsSpacing.section) {
            PaneHeader(
                systemImage: nil,
                title: "Scrolling",
                detail: "Move your mouse while holding the configured button, or click it to toggle scrolling."
            )

            SettingsGroup {
                activation
            }

            SettingsGroup {
                scrolling
            }
        }
    }

    private var activation: some View {
        ButtonDetectionRow(
            title: "Mouse button",
            description: buttonDescription,
            badge: buttonStatus,
            accessibilityHint: buttonAccessibilityHint
        ) {
            if recorder.isCapturing {
                recorder.cancel()
            } else {
                recorder.start { button in
                    settings.button = button
                    settings.saveButton()
                }
            }
        }
    }

    private var buttonStatus: DetectionBadge {
        if recorder.isCaptureUnavailable {
            return DetectionBadge(title: "Detection unavailable", symbol: "xmark.circle.fill", color: Palette.error)
        }

        if recorder.isCapturing {
            return DetectionBadge(title: "Detecting…", symbol: nil, color: Palette.textSecondary)
        }

        if settings.button == 0 {
            return DetectionBadge(title: buttonName, symbol: "minus.circle.fill", color: Palette.textSecondary)
        }

        if settings.isButtonConfigured {
            return DetectionBadge(title: buttonName, symbol: "checkmark.circle.fill", color: Palette.success)
        }

        return DetectionBadge(title: "Default (\(buttonName))", symbol: "exclamationmark.triangle.fill", color: Palette.warning)
    }

    private var buttonAccessibilityHint: String {
        if recorder.isCapturing {
            return "Click to cancel detection. Press Escape to cancel."
        }

        if recorder.isCaptureUnavailable {
            return "Click to retry detection. The current button setting is unchanged."
        }

        return "Click to detect or change the scrolling button."
    }

    private var buttonDescription: String {
        if recorder.isCaptureUnavailable {
            return "Could not start detection. The current button is unchanged."
        }

        if recorder.isCapturing {
            return "Press a middle or side button… Esc cancels."
        }

        if settings.isButtonConfigured {
            return "Click the field to detect a different button."
        }

        return "This default may not work with your mouse."
    }

    private var scrolling: some View {
        VStack(alignment: .leading, spacing: SettingsSpacing.row) {
            VStack(alignment: .leading, spacing: SettingsSpacing.inline) {
                HStack(spacing: SettingsSpacing.row) {
                    Text("Speed")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)

                    Spacer(minLength: SettingsSpacing.inline)

                    Text(speedName)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityHidden(true)
                }

                Slider(
                    value: speed,
                    in: Double(AppSettings.minSpeed)...Double(AppSettings.maxSpeed),
                    step: 1
                ) {
                    Text("Speed")
                }
                .labelsHidden()
                .tint(Palette.accent)
                .accessibilityLabel("Speed")
                .accessibilityValue(Text(speedName))
            }

            SettingsToggleRow(title: "Reverse scrolling direction", isOn: reverse)

            SettingsToggleRow(
                title: "Click to toggle scrolling",
                isOn: toggle,
                caption: "Click the configured button once to start, and again to stop."
            )
        }
    }

    private var buttonName: String {
        settings.button == 0 ? "Disabled" : "Button \(settings.button)"
    }

    private var speed: Binding<Double> {
        Binding(
            get: { Double(settings.speed) },
            set: { value in
                settings.speed = Int32(value)
                settings.saveSpeed()
            }
        )
    }

    private var reverse: Binding<Bool> {
        Binding(
            get: { settings.reverse },
            set: { value in
                settings.reverse = value
                settings.saveReverse()
            }
        )
    }

    private var toggle: Binding<Bool> {
        Binding(
            get: { settings.toggle },
            set: { value in
                settings.toggle = value
                settings.saveToggle()
            }
        )
    }

    private var speedName: String {
        switch settings.speed {
        case 1: "Slowest"
        case 2: "Slow"
        case 3: "Normal"
        case 4: "Fast"
        case 5: "Fastest"
        default: "Normal"
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var caption: String? = nil
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsSpacing.compact) {
            HStack(spacing: SettingsSpacing.row) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityHidden(true)

                Spacer(minLength: SettingsSpacing.inline)

                Toggle(title, isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Palette.switchOn)
                    .accessibilityLabel(title)
                    .accessibilityHint(caption ?? "")
                    .disabled(disabled)
            }

            if let caption {
                Text(caption)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

private struct GeneralSettingsView: View {
    @Bindable var model: GeneralSettingsModel
    let settings: AppSettings
    let isKeyboardInputActive: Bool

    @State private var appToEdit: AppExclusion?
    @State private var appSelectionError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsSpacing.section) {
                PaneHeader(
                    systemImage: nil,
                    title: "General",
                    detail: "Manage Accessibility access and decide whether Kaygan opens when you sign in."
                )

                SettingsGroup {
                    accessibility
                }

                SettingsGroup {
                    launchAtLoginSection
                }

                SettingsGroup {
                    appExclusionsSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $appToEdit) { exclusion in
            AppExclusionEditor(
                exclusion: exclusion,
                settings: settings,
                isKeyboardInputActive: isKeyboardInputActive
            )
                .frame(width: 360)
                .fixedSize(horizontal: false, vertical: true)
        }
        .alert("Could Not Add App", item: $appSelectionError) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .onAppear {
            model.refreshAccessibility()
            model.refreshLoginItemStatus()
        }
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: SettingsSpacing.row) {
            HStack(spacing: SettingsSpacing.row) {
                VStack(alignment: .leading, spacing: SettingsSpacing.compact) {
                    Text("Accessibility")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)

                    Text("Kaygan uses this access to handle mouse gestures and post scroll and navigation events.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: SettingsSpacing.inline)

                if model.isAccessibilityTrusted {
                    Label("Enabled", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.success)
                        .accessibilityLabel("Accessibility")
                        .accessibilityValue("Enabled")
                } else {
                    GeneralActionButton(title: "Request Access") {
                        model.requestAccessibility()
                    }
                    .accessibilityHint("Ask macOS to let Kaygan use Accessibility features.")
                }
            }
        }
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: SettingsSpacing.row) {
            HStack(spacing: SettingsSpacing.row) {
                Text("Launch at login")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)

                Spacer(minLength: SettingsSpacing.inline)

                if model.launchAtLoginIsEnabled {
                    Label("Enabled", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.success)
                        .accessibilityLabel("Launch at login")
                        .accessibilityValue("Enabled")
                }

                if let actionTitle = model.launchAtLoginActionTitle {
                    GeneralActionButton(title: actionTitle) {
                        model.performLaunchAtLoginAction()
                    }
                }
            }

            if let errorMessage = model.launchAtLoginErrorMessage {
                Text("Could not update Login Items: \(errorMessage)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var appExclusionsSection: some View {
        VStack(alignment: .leading, spacing: SettingsSpacing.row) {
            HStack {
                Text("Disabled apps")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)

                Spacer()

                Button(action: chooseApplication) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add an app")
                .accessibilityLabel("Add an app")
            }

            Divider()
                .overlay(Palette.hover)

            if settings.appExclusions.isEmpty {
                Text("No apps added.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
            } else {
                LazyVStack(spacing: SettingsSpacing.row) {
                    ForEach(settings.appExclusions) { exclusion in
                        AppExclusionRow(
                            exclusion: exclusion,
                            onEdit: { appToEdit = exclusion },
                            onRemove: { settings.removeAppExclusion(bundleIdentifier: exclusion.bundleIdentifier) }
                        )
                    }
                }
            }
        }
    }

    @MainActor
    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "Add App"
        panel.message = "Choose an app to disable Kaygan features in."

        let completionHandler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            guard let selected = AppExclusion.selectedApplication(at: url) else {
                appSelectionError = "Kaygan needs an app with a bundle identifier to recognize it."
                return
            }

            guard !settings.appExclusions.contains(where: { $0.bundleIdentifier == selected.bundleIdentifier }) else {
                return
            }
            settings.saveAppExclusion(selected)
        }

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completionHandler)
        } else {
            panel.begin(completionHandler: completionHandler)
        }
    }

}

private struct GeneralActionButton: View {
    let title: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Capsule())
        }
        .buttonStyle(GeneralActionButtonStyle())
    }
}

private struct AppExclusionRow: View {
    let exclusion: AppExclusion
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: SettingsSpacing.inline) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: exclusion.applicationPath))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            Text(exclusion.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: SettingsSpacing.inline)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit \(exclusion.displayName)")
            .accessibilityLabel("Edit \(exclusion.displayName)")

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove \(exclusion.displayName)")
            .accessibilityLabel("Remove \(exclusion.displayName)")
        }
    }
}

private struct AppExclusionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var exclusion: AppExclusion

    private let settings: AppSettings
    private let isKeyboardInputActive: Bool

    init(exclusion: AppExclusion, settings: AppSettings, isKeyboardInputActive: Bool) {
        self.settings = settings
        self.isKeyboardInputActive = isKeyboardInputActive
        _exclusion = State(initialValue: exclusion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsSpacing.section) {
            HStack(spacing: SettingsSpacing.row) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: exclusion.applicationPath))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SettingsSpacing.compact) {
                    Text(exclusion.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text("Choose which Kaygan features to disable.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.textSecondary)
                }
            }

            VStack(spacing: SettingsSpacing.row) {
                exclusionToggle("Disable scrolling", isOn: $exclusion.scrollingDisabled)
                exclusionToggle("Disable navigation", isOn: $exclusion.navigationDisabled)
            }

            HStack(spacing: SettingsSpacing.inline) {
                Spacer()
                GeneralActionButton(title: "Cancel", role: .cancel) {
                    dismiss()
                }
                GeneralActionButton(title: "Save") {
                    settings.saveAppExclusion(exclusion)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .background(Palette.canvas)
    }

    private func exclusionToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isOn.wrappedValue ? Palette.success : Palette.textSecondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled(!isKeyboardInputActive)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isOn.wrappedValue ? "On" : "Off"))
        .accessibilityHint(Text("Toggle this app exclusion."))
    }
}

private struct GeneralActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Palette.selection.opacity(configuration.isPressed ? 0.72 : 1),
                in: Capsule()
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct NavigationSettingsView: View {
    @Bindable var settings: AppSettings
    let recorder: MouseButtonRecorder
    @Bindable var navigation: NavigationEngine
    @State private var detectedButton: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsSpacing.section) {
            PaneHeader(
                systemImage: nil,
                title: "Navigation",
                detail: "Use the side buttons to move back and forward through history."
            )

            SettingsGroup {
                VStack(alignment: .leading, spacing: SettingsSpacing.row) {
                    SettingsToggleRow(
                        title: "Enable side-button navigation",
                        isOn: navigationEnabled,
                        caption: "Go back or forward with your mouse’s side buttons."
                    )

                    SettingsToggleRow(
                        title: "Reverse button directions",
                        isOn: reverseNavigation,
                        disabled: !settings.navigationEnabled
                    )

                    if let statusMessage = navigation.statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }

            SettingsGroup {
                ButtonDetectionRow(
                    title: "Test side buttons",
                    description: testDescription,
                    badge: testStatus,
                    accessibilityHint: testAccessibilityHint
                ) {
                    if recorder.isCapturing {
                        recorder.cancel()
                    } else {
                        detectedButton = nil
                        recorder.start { button in
                            detectedButton = button
                        }
                    }
                }
            }
        }
    }

    private var testStatus: DetectionBadge {
        if recorder.isCaptureUnavailable {
            return DetectionBadge(title: "Detection unavailable", symbol: "xmark.circle.fill", color: Palette.error)
        }

        if recorder.isCapturing {
            return DetectionBadge(title: "Detecting…", symbol: nil, color: Palette.textSecondary)
        }

        if let detectedButton {
            if (4...5).contains(detectedButton) {
                return DetectionBadge(title: "Button \(detectedButton) detected", symbol: "checkmark.circle.fill", color: Palette.success)
            }

            return DetectionBadge(title: "Button \(detectedButton)", symbol: "exclamationmark.triangle.fill", color: Palette.warning)
        }

        return DetectionBadge(title: "Test buttons", symbol: "dot.radiowaves.left.and.right", color: Palette.textSecondary)
    }

    private var testDescription: String {
        if recorder.isCaptureUnavailable {
            return "Could not start button detection."
        }

        if recorder.isCapturing {
            return "Press a side button… Esc cancels."
        }

        if let detectedButton {
            return (4...5).contains(detectedButton)
                ? "Button \(detectedButton) is mapped to Navigation."
                : "Button \(detectedButton) is not mapped to Navigation."
        }

        return "Click Test buttons, then press a side button."
    }

    private var testAccessibilityHint: String {
        if recorder.isCapturing {
            return "Click to cancel the test. Press Escape to cancel."
        }

        if recorder.isCaptureUnavailable {
            return "Click to retry button detection."
        }

        return "Click to test which auxiliary mouse button Kaygan receives."
    }

    private var navigationEnabled: Binding<Bool> {
        Binding(
            get: { settings.navigationEnabled },
            set: { value in
                settings.navigationEnabled = value
                settings.saveNavigationEnabled()
            }
        )
    }

    private var reverseNavigation: Binding<Bool> {
        Binding(
            get: { settings.reverseNavigation },
            set: { value in
                settings.reverseNavigation = value
                settings.saveReverseNavigation()
            }
        )
    }
}

private struct AboutSettingsView: View {
    private static let sourceURL = URL(string: "https://github.com/aerz/Kaygan.app")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsSpacing.spacious) {
            HStack(spacing: SettingsSpacing.row) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SettingsSpacing.compact) {
                    Text("Kaygan")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)

                    Text("Mouse-driven scrolling and back/forward navigation.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Version \(version) (\(build))")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.textSecondary)
                }
            }

            Link("Source Code", destination: Self.sourceURL)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textPrimary)
                .padding(.leading, 66)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
