import SwiftUI

/// Category edits stay in a draft until Save; task names and state are never rewritten here.
struct CategoryEditor: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @AppDismiss private var dismiss
    let originalName: String?
    let originalSymbol: String
    var onSave: (String) -> Void = { _ in }
    var onDelete: () -> Void = {}
    @State private var name: String
    @State private var symbol: String
    @State private var showsIcons = false
    @State private var showsDelete = false
    @State private var showsDiscard = false
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    init(name: String? = nil, symbol: String = "tag", onSave: @escaping (String) -> Void = { _ in },
         onDelete: @escaping () -> Void = {}) {
        originalName = name
        originalSymbol = symbol
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: name ?? "")
        _symbol = State(initialValue: symbol)
    }

    private var hasChanges: Bool { name != (originalName ?? "") || symbol != originalSymbol }
    private func font(_ style: NSFont.TextStyle, weight: Font.Weight = .regular) -> Font {
        AppTypography.desktop(style, scale: preferences.fontScale, weight: weight, design: preferences.fontStyle.design)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.x5) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AppSpacing.x1) {
                    Text(originalName == nil ? "新建类别" : "编辑类别").font(font(.title2, weight: .semibold))
                    Text("名称与图标，让类别更容易辨认。")
                        .font(font(.callout)).foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                Button(action: cancel) { Image(systemName: "xmark").frame(width: 32, height: 32) }
                    .buttonStyle(.plain).foregroundStyle(AppColors.textSecondary)
                    .accessibilityLabel("关闭类别编辑")
            }
            HStack(spacing: AppSpacing.x4) {
                Button { showsIcons = true } label: {
                    Image(systemName: symbol).font(font(.largeTitle))
                        .frame(width: 64, height: 64)
                        .foregroundStyle(preferences.accentColor)
                        .background(preferences.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.card))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "pencil.circle.fill").font(font(.title3))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(preferences.accentColor, preferences.cardBackground)
                        }
                }
                .buttonStyle(.plain).accessibilityLabel("选择类别图标")
                VStack(alignment: .leading, spacing: AppSpacing.x1) {
                    Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "新类别" : name)
                        .font(font(.headline, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    Text("用于类别导航与任务类别选择器").font(font(.caption1)).foregroundStyle(AppColors.textSecondary)
                    Button("更换图标 ›") { showsIcons = true }.buttonStyle(.plain)
                        .font(font(.callout)).foregroundStyle(preferences.accentColor)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: AppSpacing.x2) {
                Text("类别名称").font(font(.callout, weight: .medium))
                TextField("例如：工作、阅读、健康", text: $name)
                    .textFieldStyle(.roundedBorder).font(font(.body))
                    .focused($nameFocused).onSubmit(save)
                    .accessibilityLabel("类别名称")
                if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(AppColors.danger).font(font(.caption1))
                        .accessibilityLabel("错误：\(error)")
                }
                Text(originalName == nil ? "创建后可在任务中选择此类别。" : "修改名称会同步更新该类别下的任务。")
                    .font(font(.caption1)).foregroundStyle(AppColors.textSecondary)
            }
            Divider()
            HStack(spacing: AppSpacing.x2) {
                if originalName != nil {
                    Button("删除类别…", role: .destructive) { showsDelete = true }.buttonStyle(.plain)
                        .foregroundStyle(AppColors.danger).font(font(.callout))
                }
                Spacer()
                Button("取消", action: cancel)
                Button(originalName == nil ? "创建类别" : "保存更改", action: save)
                    .buttonStyle(.borderedProminent).tint(preferences.accentColor)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppSpacing.x6).frame(width: 540)
        .appDialog(isPresented: $showsIcons) {
            CategoryIconPicker(selection: symbol, categoryName: name, recent: store.categoryAppearance.recent) { value in
                symbol = value
                store.categoryAppearance.recordRecent(value)
            }
        }
        .confirmationDialog("删除类别？", isPresented: $showsDelete) {
            Button("删除类别", role: .destructive) {
                if let originalName { store.deleteCategory(originalName) }
                onDelete()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            let count = store.tasks.filter { $0.category == originalName }.count
            Text("删除「\(originalName ?? name)」后，\(count) 项任务会移至“未分类”。任务内容与状态均保留。")
        }
        .confirmationDialog("放弃尚未保存的修改？", isPresented: $showsDiscard) {
            Button("放弃修改", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        }
        .onAppDialogCancel { if !showsDiscard && !showsDelete { cancel() } }
        .onChange(of: name) { _, _ in error = nil }
        .task { nameFocused = true }
    }

    private func cancel() {
        if hasChanges { showsDiscard = true } else { dismiss() }
    }

    private func save() {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { error = "请输入类别名称。"; return }
        guard !store.categories.contains(where: {
            $0 != originalName && $0.localizedCaseInsensitiveCompare(value) == .orderedSame
        }) else { error = "已有同名类别，请换一个名称。"; return }
        if let originalName {
            guard store.renameCategory(originalName, to: value) else { error = "类别已发生变化，请关闭后重试。"; return }
        } else {
            store.addCategory(value)
        }
        store.categoryAppearance.setSymbol(symbol, for: value)
        onSave(value)
        dismiss()
    }
}

/// The picker confirms into the editor draft; browsing never changes a saved category.
struct CategoryIconPicker: View {
    @EnvironmentObject private var preferences: AppPreferences
    @AppDismiss private var dismiss
    let categoryName: String
    let recent: [String]
    let onSelect: (String) -> Void
    @State private var selection: String
    @State private var query = ""
    @State private var group = "推荐"
    @FocusState private var focusedSymbol: String?
    @FocusState private var searchFocused: Bool

    init(selection: String, categoryName: String, recent: [String], onSelect: @escaping (String) -> Void) {
        _selection = State(initialValue: CategorySymbol.validated(selection))
        self.categoryName = categoryName
        self.recent = recent
        self.onSelect = onSelect
    }

    private func font(_ style: NSFont.TextStyle, weight: Font.Weight = .regular) -> Font {
        AppTypography.desktop(style, scale: preferences.fontScale, weight: weight, design: preferences.fontStyle.design)
    }
    private var matches: [CategorySymbol] {
        CategorySymbol.matching(query, group: group).filter { CategorySymbol.validated($0.id) == $0.id }
    }
    private var recentSymbols: [CategorySymbol] {
        recent.compactMap { value in CategorySymbol.all.first { $0.id == value } }
            .filter { CategorySymbol.validated($0.id) == $0.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.x4) {
            HStack(spacing: AppSpacing.x3) {
                Image(systemName: selection).font(font(.title2))
                    .foregroundStyle(preferences.accentColor)
                    .frame(width: 44, height: 44)
                    .background(preferences.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.control))
                VStack(alignment: .leading, spacing: AppSpacing.x1) {
                    Text("选择图标").font(font(.title2, weight: .semibold))
                    Text("为「\(categoryName.isEmpty ? "新类别" : categoryName)」选择一个容易辨认的符号")
                        .font(font(.caption1)).foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }
                    .buttonStyle(.plain).foregroundStyle(AppColors.textSecondary).accessibilityLabel("取消选择图标")
            }
            HStack(spacing: AppSpacing.x2) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppColors.textSecondary)
                TextField("搜索图标，例如：工作、书、旅行…", text: $query)
                    .textFieldStyle(.plain).focused($searchFocused).accessibilityLabel("搜索图标")
                if !query.isEmpty {
                    Button { query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("清除图标搜索")
                }
            }
            .font(font(.body)).padding(AppSpacing.x3)
            .background(preferences.pageBackground, in: RoundedRectangle(cornerRadius: AppRadius.small))
            .overlay { RoundedRectangle(cornerRadius: AppRadius.small).stroke(AppColors.border) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.x1) {
                    ForEach(CategorySymbol.groups, id: \.self) { groupButton($0) }
                }
                Picker("图标分组", selection: $group) {
                    ForEach(CategorySymbol.groups, id: \.self) { Text($0).tag($0) }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.x5) {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && group == "推荐" && !recentSymbols.isEmpty {
                        symbolSection("最近使用", symbols: recentSymbols)
                    }
                    if matches.isEmpty {
                        AppEmptyState(title: "没有找到匹配的图标", message: "试试“书”“生活”或英文符号名称。", systemImage: "magnifyingglass")
                    } else {
                        symbolSection(!query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "搜索结果" : group == "推荐" ? "常用推荐" : "\(group)图标", symbols: matches)
                    }
                }
                .padding(AppSpacing.x1)
            }
            .frame(height: 268)
            Divider()
            HStack(spacing: AppSpacing.x2) {
                Image(systemName: selection).foregroundStyle(preferences.accentColor).font(font(.title3))
                VStack(alignment: .leading) {
                    Text(CategorySymbol.all.first { $0.id == selection }?.title ?? "标签").font(font(.callout))
                    Text(selection).font(font(.caption1)).foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("已选图标：\(CategorySymbol.all.first { $0.id == selection }?.title ?? "标签")")
                Spacer()
                Button("取消") { dismiss() }
                Button("使用此图标") { onSelect(selection); dismiss() }
                    .buttonStyle(.borderedProminent).tint(preferences.accentColor).keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppSpacing.x6).frame(width: 600)
        .task { searchFocused = true }
    }

    private func groupButton(_ value: String) -> some View {
        Button { group = value; query = "" } label: {
            Text(value).font(font(.caption1, weight: group == value ? .medium : .regular))
                .padding(.horizontal, AppSpacing.x2).padding(.vertical, AppSpacing.x2)
                .background(group == value ? preferences.accentColor.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: AppRadius.small))
                .foregroundStyle(group == value ? preferences.accentColor : AppColors.textSecondary)
        }
        .buttonStyle(.plain).accessibilityAddTraits(group == value ? .isSelected : [])
    }

    private func symbolSection(_ title: String, symbols: [CategorySymbol]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.x2) {
            HStack { Text(title); Spacer(); Text("\(symbols.count) 个") }
                .font(font(.caption1)).foregroundStyle(AppColors.textSecondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: (AppTheme.minimumTouchTarget + AppSpacing.x2) * preferences.fontScale), spacing: AppSpacing.x2)], spacing: AppSpacing.x2) {
                ForEach(symbols) { item in
                    Button { selection = item.id } label: {
                        Image(systemName: item.id).font(font(.title2))
                            .frame(maxWidth: .infinity).frame(height: AppTheme.minimumTouchTarget * preferences.fontScale)
                            .foregroundStyle(selection == item.id ? preferences.accentColor : AppColors.textSecondary)
                            .background(selection == item.id ? preferences.accentColor.opacity(0.12) : preferences.pageBackground,
                                        in: RoundedRectangle(cornerRadius: AppRadius.small))
                            .overlay {
                                RoundedRectangle(cornerRadius: AppRadius.small)
                                    .stroke(selection == item.id ? preferences.accentColor : .clear)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                if selection == item.id {
                                    Image(systemName: "checkmark").font(font(.caption2))
                                        .foregroundStyle(preferences.accentColor).padding(AppSpacing.x1)
                                }
                            }
                    }
                    .buttonStyle(.plain).help(item.title)
                    .focused($focusedSymbol, equals: "\(title)-\(item.id)")
                    .onMoveCommand { direction in
                        guard let index = symbols.firstIndex(where: { $0.id == item.id }) else { return }
                        let gridWidth = 600 - 2 * AppSpacing.x6 - 2 * AppSpacing.x1
                        let columns = max(1, Int((gridWidth + AppSpacing.x2) / ((AppTheme.minimumTouchTarget + AppSpacing.x2) * preferences.fontScale + AppSpacing.x2)))
                        let offset: Int
                        switch direction {
                        case .left: offset = -1
                        case .right: offset = 1
                        case .up: offset = -columns
                        case .down: offset = columns
                        default: return
                        }
                        let next = index + offset
                        if symbols.indices.contains(next) { focusedSymbol = "\(title)-\(symbols[next].id)" }
                    }
                    .accessibilityLabel("\(item.title)，\(item.id)")
                    .accessibilityAddTraits(selection == item.id ? .isSelected : [])
                }
            }
        }
    }
}

struct CategoryEditorExample: View {
    @State private var showsEditor = false
    var body: some View {
        Button("新建类别与选择图标") { showsEditor = true }
            .appDialog(isPresented: $showsEditor) { CategoryEditor() }
    }
}

#Preview("类别编辑 · 浅色") {
    CategoryEditor(name: "需要持续跟进的长期学习与个人成长计划", symbol: "book")
        .environmentObject(TaskStore(inMemory: true)).environmentObject(AppPreferences())
}
#Preview("图标库 · 深色") {
    CategoryIconPicker(selection: "briefcase", categoryName: "工作", recent: ["briefcase", "book"]) { _ in }
        .environmentObject(AppPreferences()).preferredColorScheme(.dark)
}
