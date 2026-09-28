import SwiftUI
import AppKit

private enum SettingsPane: String {
    // Keep the stored value stable so existing pane selection survives the label change.
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
    static let warning = Color.orange
    static let success = Color.green
    static let error = Color.red
}

struct SettingsView: View {
    @AppStorage("selectedSettingsPane") private var selectedPane: SettingsPane = .scrolling
    @FocusState private var focusedPane: SettingsPane?
    @State private var hoveredPane: SettingsPane?

    let settings: AppSettings
    let recorder: MouseButtonRecorder
    let navigation: NavigationEngine

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Group {
                switch selectedPane {
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
        .onChange(of: selectedPane) { _, _ in
            recorder.cancel()
        }
        .onDisappear {
            recorder.cancel()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            sidebarButton("Scrolling", systemImage: "arrow.up.and.down", pane: .scrolling)
            sidebarButton("Navigation", systemImage: "arrow.left.arrow.right", pane: .navigation)
            sidebarButton("About", systemImage: "info.circle", pane: .about)
                .padding(.top, 14)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 42)
        .padding(.bottom, 16)
        .frame(width: 180)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func sidebarButton(_ title: String, systemImage: String, pane: SettingsPane) -> some View {
        let isSelected = selectedPane == pane

        return Button {
            selectedPane = pane
            focusedPane = pane
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 13, weight: .medium))

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isSelected ? Palette.selection : Palette.hover.opacity(hoveredPane == pane ? 1 : 0),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focused($focusedPane, equals: pane)
        .focusEffectDisabled(focusedPane != pane)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hoveredPane = $0 ? pane : nil }
    }
}

private struct SettingsWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SettingsWindowChromeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? SettingsWindowChromeView)?.configureWindow()
    }
}

@MainActor
private final class SettingsWindowChromeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        guard let window else { return }

        window.styleMask.insert(.fullSizeContentView)
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
        VStack(alignment: .leading, spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Palette.tile, in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
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
            .padding(16)
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)

                Text(description)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                    .frame(height: 30, alignment: .topLeading)
            }

            Spacer(minLength: 8)

            Button(action: action) {
                HStack(spacing: 8) {
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
        VStack(alignment: .leading, spacing: 20) {
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
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text("Speed")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)

                    Spacer(minLength: 8)

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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityHidden(true)

                Spacer(minLength: 8)

                Toggle(title, isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Palette.accent)
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

private struct NavigationSettingsView: View {
    @Bindable var settings: AppSettings
    let recorder: MouseButtonRecorder
    @Bindable var navigation: NavigationEngine
    @State private var detectedButton: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaneHeader(
                systemImage: nil,
                title: "Navigation",
                detail: "Use the side buttons to move back and forward through history."
            )

            SettingsGroup {
                VStack(alignment: .leading, spacing: 18) {
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
    private var version: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    var body: some View {
        PaneHeader(
            systemImage: "cursorarrow",
            title: "Kaygan",
            detail: version.map { "Version \($0)" } ?? "Version unavailable"
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
