import SwiftUI

private enum TasksPresentation: String, CaseIterable, Identifiable {
    case list = "列表"
    case quadrants = "四象限"
    var id: Self { self }
}

private enum TasksScope: String, CaseIterable, Identifiable {
    case active = "待处理"
    case all = "全部"
    case inbox = "收集箱"
    case processed = "已处理"
    var id: Self { self }

    func includes(_ task: TaskItem) -> Bool {
        switch self {
        case .active: task.needsAction
        case .all: true
        case .inbox: task.isUnscheduled && task.needsAction
        case .processed: task.isCompleted || task.isCancelled
        }
    }
}

/// One task collection with two presentations. The legacy blueprint library is a secondary destination.
struct TasksHubView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @Binding var showsBlueprintLibrary: Bool
    let onSelect: (TaskItem) -> Void
    let onAddTask: () -> Void

    @State private var presentation: TasksPresentation = .list
    @State private var scope: TasksScope = .active

    private var visibleTasks: [TaskItem] {
        store.tasks.filter(scope.includes).sorted {
            if $0.needsAction != $1.needsAction { return $0.needsAction }
            if ($0.dueDate ?? .distantFuture) != ($1.dueDate ?? .distantFuture) {
                return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
            }
            return $0.createdAt > $1.createdAt
        }
    }

    var body: some View {
        Group {
            if showsBlueprintLibrary {
                VStack(alignment: .leading, spacing: 0) {
                    Button("返回事项", systemImage: "chevron.left") { showsBlueprintLibrary = false }
                        .buttonStyle(.plain)
                        .foregroundStyle(preferences.accentColor)
                        .padding(.horizontal, AppSpacing.x8)
                        .padding(.top, AppSpacing.x4)
                    BlueprintsView()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.x6) {
                        header
                        controls
                        if presentation == .list {
                            if visibleTasks.isEmpty {
                                ContentUnavailableView(
                                    scope == .active ? "没有待处理事项" : "这里还没有事项",
                                    systemImage: "checklist",
                                    description: Text(scope == .inbox ? "新任务若暂不安排日期，会出现在收集箱。" : "添加一项任务，之后可在列表、四象限或蓝图中查看。")
                                )
                                .frame(maxWidth: .infinity, minHeight: 300)
                            } else {
                                TaskList(tasks: visibleTasks, onSelect: onSelect)
                            }
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: AppSpacing.x4), GridItem(.flexible(), spacing: AppSpacing.x4)], spacing: AppSpacing.x4) {
                                ForEach(Quadrant.allCases) { quadrant in
                                    QuadrantPanel(quadrant: quadrant,
                                                  tasks: visibleTasks.filter { $0.quadrant == quadrant },
                                                  onSelect: onSelect)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 1120, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, AppSpacing.x8)
                    .padding(.vertical, AppSpacing.x8)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.x4) {
            VStack(alignment: .leading, spacing: AppSpacing.x2) {
                Text("YOUR TASKS")
                    .font(AppTypography.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(preferences.accentColor)
                Text("事项").font(AppTypography.largeTitle)
                Text("任务是基础；列表、四象限和蓝图是同一批任务的不同视图。")
                    .font(AppTypography.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            AppButton(title: "新建事项", systemImage: "plus", size: .prominent,
                      tint: preferences.accentColor, action: onAddTask)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: AppSpacing.x3) {
            HStack(spacing: AppSpacing.x4) {
                Picker("展示方式", selection: $presentation) {
                    ForEach(TasksPresentation.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                Spacer()
                Button("蓝图库", systemImage: "point.3.connected.trianglepath.dotted") {
                    showsBlueprintLibrary = true
                }
                .help("查看已有蓝图和任务树")
            }
            HStack(spacing: AppSpacing.x2) {
                ForEach(TasksScope.allCases) { option in
                    Button(option.rawValue) { scope = option }
                        .buttonStyle(.plain)
                        .font(AppTypography.callout.weight(scope == option ? .semibold : .regular))
                        .foregroundStyle(scope == option ? preferences.accentColor : .secondary)
                        .padding(.horizontal, AppSpacing.x3)
                        .frame(height: 32)
                        .background(scope == option ? preferences.accentColor.opacity(0.11) : .clear,
                                    in: RoundedRectangle(cornerRadius: AppRadius.small))
                        .accessibilityAddTraits(scope == option ? [.isSelected] : [])
                }
                Spacer()
                Text("\(visibleTasks.count) 项")
                    .font(AppTypography.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppSpacing.x4)
        .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).stroke(AppColors.border))
    }
}

#Preview("事项 · 列表与四象限") {
    let store = TaskStore(inMemory: true)
    store.add(TaskItem(title: "整理发布清单", quadrant: .doNow))
    store.add(TaskItem(title: "规划下周任务", quadrant: .schedule))
    return TasksHubView(showsBlueprintLibrary: .constant(false), onSelect: { _ in }, onAddTask: {})
        .environmentObject(store)
        .environmentObject(AppPreferences())
        .frame(width: 1000, height: 700)
}
