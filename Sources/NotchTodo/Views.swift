import SwiftUI
import AppKit

// MARK: - 刘海形状（顶部直角、底部圆角）

struct NotchShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - 根视图

struct NotchRootView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var store: TaskStore

    var body: some View {
        let size = state.expanded ? state.expandedSize : state.collapsedSize
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(radius: state.expanded ? 22 : 10)
                    .fill(Color.black)
                if state.expanded {
                    ExpandedView(state: state, store: store)
                        .transition(.opacity)
                } else {
                    CollapsedView(state: state, store: store)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(NotchShape(radius: state.expanded ? 22 : 10))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: state.expanded)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - 收起态

struct CollapsedView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var store: TaskStore

    var body: some View {
        HStack {
            Image(systemName: "checklist")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            Text(store.hasToken ? "\(store.tasks.filter { !$0.isDone }.count)" : "–")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .frame(height: state.notchSize.height)
    }
}

// MARK: - 展开态

struct ExpandedView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var store: TaskStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !store.hasToken || state.showSettings {
                SettingsView(state: state, store: store)
            } else {
                addField
                if let err = store.errorMessage {
                    Text(err).font(.system(size: 10)).foregroundColor(.red).lineLimit(2)
                }
                taskList
            }
        }
        .padding(.top, state.notchSize.height + 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .foregroundColor(.white)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("ClickUp 待办").font(.system(size: 13, weight: .semibold))
            if store.hasToken {
                Text("\(store.tasks.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(.white.opacity(0.5))
            }
            if store.isLoading {
                ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 14, height: 14)
            }
            Spacer()
            IconButton(system: allCollapsed ? "chevron.down.2" : "chevron.up.2",
                       help: allCollapsed ? "全部展开" : "全部折叠") {
                let ids = Set(store.groups.map(\.id))
                state.collapsedGroups = allCollapsed ? [] : ids
            }
            IconButton(system: "arrow.clockwise", help: "刷新") {
                Task { @MainActor in
                    await store.refresh()
                    await store.reloadLists()
                }
            }
            IconButton(system: state.pinned ? "pin.fill" : "pin", help: "固定展开") {
                state.pinned.toggle()
            }
            IconButton(system: "gearshape", help: "设置") {
                state.showSettings.toggle()
            }
        }
    }

    private var allCollapsed: Bool {
        let ids = store.groups.map(\.id)
        return !ids.isEmpty && ids.allSatisfy { state.collapsedGroups.contains($0) }
    }

    // 新建：左边选分组，右边输入名称
    private var addField: some View {
        HStack(spacing: 6) {
            ListPickerMenu(store: store)
            Divider().frame(height: 14).overlay(Color.white.opacity(0.2))
            TextField("添加待办，回车创建", text: $state.newTaskName)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit {
                    let n = state.newTaskName
                    state.newTaskName = ""
                    let target = store.createListId
                    state.collapsedGroups.remove(target)   // 确保新任务所在分组是展开的
                    Task { @MainActor in await store.create(n) }
                }
                .onExitCommand {
                    state.newTaskName = ""
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
    }

    @ViewBuilder
    private var taskList: some View {
        if store.tasks.isEmpty && !store.isLoading {
            VStack {
                Spacer()
                Text("暂无待办 🎉").font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(store.groups) { group in
                        GroupHeaderView(group: group, store: store, ui: state)
                        if !state.collapsedGroups.contains(group.id) {
                            ForEach(group.tasks) { task in
                                TaskRowView(task: task, store: store, ui: state)
                                    .padding(.leading, 8)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 分组选择菜单（按空间 / 文件夹归类）

struct ListPickerMenu: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        Menu {
            if store.lists.isEmpty {
                Text("正在读取分组…")
            }
            ForEach(sections, id: \.path) { section in
                Section(section.path) {
                    ForEach(section.items) { opt in
                        Button {
                            store.createListId = opt.id
                        } label: {
                            if opt.id == store.createListId {
                                Label(opt.name, systemImage: "checkmark")
                            } else {
                                Text(opt.name)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "folder").font(.system(size: 10))
                Text(store.createListName).font(.system(size: 11)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8))
            }
            .foregroundColor(.white.opacity(0.75))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("选择新任务要添加到的分组")
    }

    private var sections: [(path: String, items: [ListOption])] {
        var order: [String] = []
        var map: [String: [ListOption]] = [:]
        for l in store.lists {
            if map[l.path] == nil { order.append(l.path) }
            map[l.path, default: []].append(l)
        }
        return order.map { ($0, map[$0] ?? []) }
    }
}

// MARK: - 分组标题

struct GroupHeaderView: View {
    let group: TaskGroup
    @ObservedObject var store: TaskStore
    @ObservedObject var ui: NotchState

    private var collapsed: Bool { ui.collapsedGroups.contains(group.id) }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .rotationEffect(.degrees(collapsed ? 0 : 90))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 10)
            Text(group.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Text("\(group.tasks.count)")
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(.white.opacity(0.45))
            if !group.path.isEmpty {
                Text(group.path)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            if group.id != "_none" {
                Button {
                    store.createListId = group.id
                } label: {
                    Image(systemName: store.createListId == group.id ? "plus.circle.fill" : "plus.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("新任务添加到「\(group.name)」")
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                if collapsed { ui.collapsedGroups.remove(group.id) }
                else { ui.collapsedGroups.insert(group.id) }
            }
        }
    }
}

struct IconButton: View {
    let system: String
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.white.opacity(0.75))
        .help(help)
    }
}

// MARK: - 单条任务

struct TaskRowView: View {
    let task: CUTask
    @ObservedObject var store: TaskStore
    @ObservedObject var ui: NotchState

    var body: some View {
        HStack(spacing: 8) {
            Button {
                Task { @MainActor in await store.toggleComplete(task) }
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: task.status.color))
            }
            .buttonStyle(.plain)
            .help(task.isDone ? "标记为未完成" : "标记为完成")

            if ui.editingId == task.id {
                TextField("任务名称", text: $ui.draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { commit() }
                    .onExitCommand { ui.editingId = nil }
            } else {
                Text(task.name)
                    .font(.system(size: 12))
                    .strikethrough(task.isDone)
                    .foregroundColor(task.isDone ? .white.opacity(0.4) : .white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { beginEdit() }
                    .help("双击编辑：\(task.name)")
            }

            Spacer(minLength: 4)

            if ui.pendingDeleteId == task.id {
                Button("删除") {
                    ui.pendingDeleteId = nil
                    Task { @MainActor in await store.delete(task) }
                }
                .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundColor(.red)
                Button("取消") { ui.pendingDeleteId = nil }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
            } else {
                if let due = task.dueDateValue {
                    Text(due.shortDueLabel)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(due < Date() && !task.isDone ? .red : .white.opacity(0.5))
                }
                statusPill
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(Color.white.opacity(ui.hoveredId == task.id ? 0.08 : 0)))
        .onHover { inside in
            if inside { ui.hoveredId = task.id }
            else if ui.hoveredId == task.id { ui.hoveredId = nil }
        }
        .contextMenu {
            Button("重命名") { beginEdit() }
            if let s = task.url, let url = URL(string: s) {
                Button("在 ClickUp 中打开") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button("删除…") { ui.pendingDeleteId = task.id }
        }
    }

    private var statusPill: some View {
        Button {
            showStatusMenu()
        } label: {
            Text(task.status.status.uppercased())
                .font(.system(size: 9, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color(hex: task.status.color).opacity(0.85)))
                .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .help("切换状态")
    }

    private func beginEdit() {
        ui.draft = task.name
        ui.editingId = task.id
    }

    private func showStatusMenu() {
        guard let listId = task.list?.id else { return }
        Task { @MainActor in
            let statuses = await store.statuses(for: listId)
            let menu = NSMenu()
            for s in statuses {
                let item = ClosureMenuItem(title: s.status.uppercased()) {
                    Task { @MainActor in await store.setStatus(task, s) }
                }
                item.state = (s.status == task.status.status) ? .on : .off
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    private func commit() {
        let n = ui.draft
        ui.editingId = nil
        Task { @MainActor in await store.rename(task, to: n) }
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func fire() { handler() }
}

// MARK: - 设置

struct SettingsView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var store: TaskStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ClickUp API Key").font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
            HStack {
                SecureField(store.hasToken ? "已保存（输入新的 Key 可替换）" : "pk_xxxxxxxx",
                            text: $state.tokenInput)
                    .textFieldStyle(.roundedBorder)
                Button(state.saving ? "验证中…" : "保存") {
                    state.saving = true
                    Task { @MainActor in
                        if await store.saveToken(state.tokenInput) {
                            state.tokenInput = ""
                            state.showSettings = false
                            state.pinned = false
                        }
                        state.saving = false
                    }
                }
                .disabled(state.tokenInput.isEmpty || state.saving)
            }
            Text("获取方式：ClickUp 左下角头像 → Settings → Apps → API Token。Key 仅保存在本机钥匙串。")
                .font(.system(size: 10)).foregroundColor(.white.opacity(0.45))

            if store.hasToken {
                Picker("工作区", selection: $store.teamId) {
                    ForEach(store.teams) { Text($0.name).tag($0.id) }
                }
                .onChange(of: store.teamId) { _ in Task { @MainActor in await store.switchTeam() } }
            }

            if let err = store.errorMessage {
                Text(err).font(.system(size: 10)).foregroundColor(.red).lineLimit(3)
            }

            Spacer(minLength: 0)

            HStack {
                if store.hasToken {
                    Button("退出登录") { store.signOut() }
                }
                Spacer()
                Button("退出应用") { NSApp.terminate(nil) }
                if store.hasToken {
                    Button("完成") { state.showSettings = false }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .font(.system(size: 12))
    }
}
