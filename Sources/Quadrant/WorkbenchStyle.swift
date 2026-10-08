import SwiftUI

/// The main-window chrome uses theme settings; all motion also respects the system accessibility setting.
struct WorkbenchPressStyle: ButtonStyle {
    var reduceMotion = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.975 : 1))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

extension View {
    /// Keeps icon-only controls easy to hit without changing their visible symbol size.
    func comfortableIconTarget(_ size: CGFloat = 40) -> some View {
        frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }
}

struct WorkbenchTopBar: View {
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.openSettings) private var openSettings
    let section: AppSection
    let onCommand: () -> Void
    let onAddTask: () -> Void
    let onAddCompleted: () -> Void
    let onAddWithAI: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Text("工作区")
                .foregroundStyle(.tertiary)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(section.rawValue)
                .fontWeight(.semibold)
            Spacer(minLength: 12)
            Button(action: onCommand) {
                Image(systemName: "magnifyingglass")
                    .comfortableIconTarget()
            }
            .help("搜索与快速操作")
            .accessibilityLabel("搜索与快速操作")
            Menu {
                Button("石墨", systemImage: "circle.lefthalf.filled") { setTheme(.stone) }
                Button("纸张", systemImage: "sun.max") { setTheme(.paper) }
                Button("墨色", systemImage: "moon.stars") { setTheme(.ink) }
                Divider()
                Button("更多皮肤设置", systemImage: "slider.horizontal.3") {
                    openSettings()
                }
            } label: {
                Label(preferences.resolvedPreset.rawValue, systemImage: "paintpalette")
            }
            .help("切换皮肤")
            SettingsLink {
                Image(systemName: "gearshape")
                    .comfortableIconTarget()
            }
            .help("应用设置")
            .accessibilityLabel("应用设置")
            AddTaskControl(
                onAddTask: onAddTask,
                onAddCompleted: onAddCompleted,
                onAddWithAI: onAddWithAI,
                shortcut: KeyboardShortcut("n", modifiers: .command)
            )
                .buttonStyle(.borderedProminent)
        }
        .font(.system(size: 13))
        .buttonStyle(WorkbenchPressStyle(reduceMotion: preferences.reduceMotion || systemReduceMotion))
        .padding(.horizontal, 25)
        .frame(height: 64)
        .background(preferences.cardBackground.opacity(0.82))
        .overlay(alignment: .bottom) { Rectangle().fill(.primary.opacity(0.07)).frame(height: 1) }
    }

    private func setTheme(_ preset: ThemePreset) {
        withAnimation(preferences.reduceMotion || systemReduceMotion ? nil : .easeInOut(duration: 0.3)) {
            preferences.automaticThemeRule = .manual
            preferences.themePreset = preset
            preferences.customAccentHex = ""
            preferences.customBackgroundHex = ""
            preferences.customCardHex = ""
        }
    }
}
