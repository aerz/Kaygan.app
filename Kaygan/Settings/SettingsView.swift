import SwiftUI
import AppKit

private enum SettingsPane: String {
    // Keep the stored value stable so existing pane selection survives the label change.
    case scrolling = "general"
    case about
}

// The settings window always draws on black, so the palette is fixed and does not follow
// the system appearance.
private enum Palette {
    static let canvasLevel = 48.0 / 255.0
    static let canvas = Color(white: canvasLevel)
    static let field = Color(white: 0.25)
    static let tile = Color(white: 0.275)
    static let selection = Color(white: 0.305)
    static let hover = Color(white: 0.24)
    static let hairline = Color(white: 0.31)
    static let fieldBorder = Color(white: 0.35)
    static let textPrimary = Color(white: 0.97)
    static let textSecondary = Color(white: 0.68)
    static let accent = Color(white: 0.97)
}

struct SettingsView: View {
    @AppStorage("selectedSettingsPane") private var selectedPane: SettingsPane = .scrolling
    @FocusState private var focusedPane: SettingsPane?
    @State private var hoveredPane: SettingsPane?

    let settings: AppSettings
    let recorder: MouseButtonRecorder

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Group {
                switch selectedPane {
                case .scrolling:
                    ScrollingSettingsView(settings: settings, recorder: recorder)
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
        .onChange(of: selectedPane) { _, pane in
            if pane == .about {
                recorder.cancel()
            }
        }
        .onDisappear {
            recorder.cancel()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            sidebarButton("Scrolling", systemImage: "arrow.up.and.down", pane: .scrolling)
            sidebarButton("About", systemImage: "info.circle", pane: .about)

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
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))

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

private struct SectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
    }
}

private struct FieldSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Palette.field, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Palette.fieldBorder)
            }
    }
}

private extension View {
    func fieldSurface() -> some View {
        modifier(FieldSurface())
    }
}

private struct ScrollingSettingsView: View {
    @Bindable var settings: AppSettings
    let recorder: MouseButtonRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PaneHeader(
                systemImage: nil,
                title: "Scrolling",
                detail: "Move your mouse while holding the configured button, or click it to toggle scrolling."
            )

            SectionDivider()

            activation

            SectionDivider()

            scrolling
        }
    }

    private var activation: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Mouse button")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)

                Spacer(minLength: 8)

                Button(recorder.isCapturing ? "Cancel" : "Detect…") {
                    if recorder.isCapturing {
                        recorder.cancel()
                    } else {
                        recorder.start()
                    }
                }
                .buttonStyle(.bordered)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
            }

            Text(settings.isButtonConfigured ? buttonName : "Default (\(buttonName))")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textPrimary)
                .fieldSurface()

            if recorder.isCapturing {
                Text("Press a middle or side button… Esc cancels.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
            } else if !settings.isButtonConfigured {
                Text("This default may not work with your mouse.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private var scrolling: some View {
        VStack(alignment: .leading, spacing: 20) {
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

            SectionDivider()

            switchRow("Reverse scrolling direction", isOn: reverse)

            SectionDivider()

            switchRow(
                "Click to toggle scrolling",
                isOn: toggle,
                caption: "Click the configured button once to start, and again to stop."
            )
        }
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityHidden(true)

                Spacer(minLength: 8)

                Toggle(title, isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Palette.accent)
                    .accessibilityLabel(title)
                    .accessibilityHint(caption ?? "")
            }

            if let caption {
                Text(caption)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
            }
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
