import SwiftUI

private enum SettingsPane: String {
    case general
    case about
}

struct SettingsView: View {
    @AppStorage("selectedSettingsPane") private var selectedPane: SettingsPane = .general
    @State private var hoveredPane: SettingsPane?

    let settings: AppSettings
    let recorder: MouseButtonRecorder

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)

            ScrollView {
                Group {
                    switch selectedPane {
                    case .general:
                        GeneralSettingsView(settings: settings, recorder: recorder)
                    case .about:
                        AboutSettingsView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
            }
            .id(selectedPane)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 470)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.indigo)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Kaygan")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.bottom, 18)

            sidebarButton("General", systemImage: "gearshape", pane: .general)
            sidebarButton("About", systemImage: "info.circle", pane: .about)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .frame(width: 180)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.04))
    }

    private func sidebarButton(_ title: String, systemImage: String, pane: SettingsPane) -> some View {
        Button {
            selectedPane = pane
        } label: {
            Label(title, systemImage: systemImage)
                .font(.body.weight(selectedPane == pane ? .semibold : .regular))
                .foregroundStyle(selectedPane == pane ? Color.indigo : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    selectedPane == pane
                        ? Color.indigo.opacity(0.14)
                        : Color.primary.opacity(hoveredPane == pane ? 0.05 : 0),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedPane == pane ? .isSelected : [])
        .onHover { hoveredPane = $0 ? pane : nil }
    }
}

private struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    let recorder: MouseButtonRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("General")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                Text("Activation")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mouse button")
                                .font(.body.weight(.medium))
                            Text(settings.isButtonConfigured ? buttonName : "Default (\(buttonName))")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Button(recorder.isCapturing ? "Cancel" : "Detect…") {
                            if recorder.isCapturing {
                                recorder.cancel()
                            } else {
                                recorder.start()
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    if recorder.isCapturing {
                        Text("Press a middle or side button… Esc cancels.")
                            .font(.footnote)
                            .foregroundStyle(.indigo)
                    } else if !settings.isButtonConfigured {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            Text("This default may not work with your mouse.")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .settingsCard()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Scrolling")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Speed")
                                .font(.body.weight(.medium))
                            Spacer()
                            Text(speedName)
                                .foregroundStyle(.secondary)
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
                        .tint(.indigo)
                        .accessibilityLabel("Speed")
                        .accessibilityValue(Text(speedName))
                    }
                    .padding(.bottom, 16)

                    Divider()

                    HStack {
                        Text("Reverse scrolling direction")
                            .font(.body.weight(.medium))
                            .accessibilityHidden(true)
                        Spacer()
                        Toggle("Reverse scrolling direction", isOn: reverse)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(.indigo)
                            .accessibilityLabel("Reverse scrolling direction")
                    }
                    .padding(.vertical, 14)

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Click to toggle scrolling")
                                .font(.body.weight(.medium))
                            Text("Click once to start, again to stop.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityHidden(true)
                        Spacer()
                        Toggle("Click to toggle scrolling", isOn: toggle)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(.indigo)
                            .accessibilityLabel("Click to toggle scrolling")
                            .accessibilityHint("Click once to start, again to stop.")
                    }
                    .padding(.top, 14)
                }
                .padding(16)
                .settingsCard()
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
        VStack(alignment: .leading, spacing: 24) {
            Text("About")
                .font(.title2.weight(.semibold))

            HStack(alignment: .top, spacing: 18) {
                Image(systemName: "cursorarrow")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.indigo)
                    .frame(width: 48, height: 48)
                    .background(Color.indigo.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Kaygan")
                        .font(.title3.weight(.semibold))

                    if let version {
                        Text("Version \(version)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Text("Scroll by moving your mouse while holding or toggling a button.")
                        .padding(.top, 8)
                }
            }
            .padding(20)
            .settingsCard()
        }
    }
}

private struct SettingsCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.07))
            }
    }
}

private extension View {
    func settingsCard() -> some View {
        modifier(SettingsCard())
    }
}
