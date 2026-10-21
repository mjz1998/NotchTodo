import Foundation
import SwiftUI

@MainActor
final class TaskStore: ObservableObject {
    @Published var tasks: [CUTask] = []
    @Published var teams: [CUTeam] = []
    @Published var lists: [ListOption] = []          // 工作区内全部清单（分组）
    @Published var statusesByList: [String: [CUStatus]] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var hasToken = false

    @Published var teamId: String {
        didSet { UserDefaults.standard.set(teamId, forKey: "teamId") }
    }
    /// 新建任务时选中的分组，会记住上次的选择
    @Published var createListId: String {
        didSet { UserDefaults.standard.set(createListId, forKey: "defaultListId") }
    }

    private var api: ClickUpAPI?
    private var userId: Int?
    private var timer: Timer?
    private let tokenAccount = "apiToken"

    init() {
        teamId = UserDefaults.standard.string(forKey: "teamId") ?? ""
        createListId = UserDefaults.standard.string(forKey: "defaultListId") ?? ""
        if let t = Keychain.load(account: tokenAccount), !t.isEmpty {
            api = ClickUpAPI(token: t)
            hasToken = true
        }
        Task { @MainActor in await self.bootstrap() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    // MARK: - 分组

    /// 按清单分组；分组顺序按组内最早截止日期排列
    var groups: [TaskGroup] {
        var order: [String] = []
        var buckets: [String: [CUTask]] = [:]
        for t in tasks {
            let key = t.list?.id ?? "_none"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(t)
        }
        return order.map { key in
            let opt = lists.first { $0.id == key }
            let name = opt?.name ?? buckets[key]?.first?.list?.name ?? "未分组"
            return TaskGroup(id: key, name: name, path: opt?.path ?? "", tasks: buckets[key] ?? [])
        }
    }

    var createListName: String {
        lists.first { $0.id == createListId }?.name ?? "选择分组"
    }

    // MARK: - 账户

    func saveToken(_ raw: String) async -> Bool {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return false }
        let candidate = ClickUpAPI(token: token)
        do {
            let user = try await candidate.currentUser()
            Keychain.save(token, account: tokenAccount)
            api = candidate
            userId = user.id
            hasToken = true
            errorMessage = nil
            await bootstrap()
            return true
        } catch {
            errorMessage = "API Key 校验失败：\(error.localizedDescription)"
            return false
        }
    }

    func signOut() {
        Keychain.delete(account: tokenAccount)
        api = nil; userId = nil; hasToken = false
        tasks = []; teams = []; lists = []; statusesByList = [:]
    }

    private func bootstrap() async {
        guard let api else { return }
        do {
            if userId == nil { userId = try await api.currentUser().id }
            teams = try await api.teams()
            if teamId.isEmpty || !teams.contains(where: { $0.id == teamId }) {
                teamId = teams.first?.id ?? ""
            }
            await reloadLists()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 切换工作区时调用
    func switchTeam() async {
        lists = []
        tasks = []
        await reloadLists()
        await refresh()
    }

    func reloadLists() async {
        guard let api, !teamId.isEmpty else { return }
        do {
            lists = try await api.allLists(teamId: teamId)
            if !lists.contains(where: { $0.id == createListId }) {
                createListId = lists.first?.id ?? ""
            }
        } catch {
            errorMessage = "读取分组失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 读取

    func refresh() async {
        guard let api, let userId, !teamId.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await api.myTasks(teamId: teamId, userId: userId)
            tasks = Self.sorted(fetched)
            errorMessage = nil
            await preloadStatuses()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func sorted(_ list: [CUTask]) -> [CUTask] {
        list.sorted { a, b in
            switch (a.dueDateValue, b.dueDateValue) {
            case let (x?, y?): return x < y
            case (_?, nil):    return true
            default:           return false
            }
        }
    }

    private func preloadStatuses() async {
        let ids = Set(tasks.compactMap { $0.list?.id })
        for id in ids where statusesByList[id] == nil {
            _ = await statuses(for: id)
        }
    }

    func statuses(for listId: String) async -> [CUStatus] {
        if let cached = statusesByList[listId] { return cached }
        guard let api, let s = try? await api.listStatuses(listId: listId) else { return [] }
        statusesByList[listId] = s
        return s
    }

    // MARK: - 编辑

    func rename(_ task: CUTask, to newName: String) async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let api, !name.isEmpty, name != task.name,
              let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].name = name
        do { try await api.updateTask(task.id, fields: ["name": name]) }
        catch { errorMessage = error.localizedDescription; await refresh() }
    }

    func setStatus(_ task: CUTask, _ status: CUStatus) async {
        guard let api, let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].status = status
        do {
            try await api.updateTask(task.id, fields: ["status": status.status])
            if status.type == "closed" {
                withAnimation { tasks.removeAll { $0.id == task.id } }
            }
        } catch {
            errorMessage = error.localizedDescription
            await refresh()
        }
    }

    func toggleComplete(_ task: CUTask) async {
        guard let listId = task.list?.id else { return }
        let all = await statuses(for: listId)
        let target: CUStatus?
        if task.isDone {
            target = all.first { $0.type == "open" } ?? all.first
        } else {
            target = all.first { $0.type == "closed" } ?? all.first { $0.type == "done" }
        }
        guard let target else { errorMessage = "该清单没有可用的完成状态"; return }
        await setStatus(task, target)
    }

    /// 在当前选中的分组中新建任务
    func create(_ rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let api, !name.isEmpty else { return }
        guard !createListId.isEmpty else {
            errorMessage = "请先选择要添加到的分组"
            return
        }
        do {
            let t = try await api.createTask(listId: createListId, name: name, assignee: userId)
            withAnimation { tasks.insert(t, at: 0) }
            _ = await statuses(for: createListId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ task: CUTask) async {
        guard let api else { return }
        withAnimation { tasks.removeAll { $0.id == task.id } }
        do { try await api.deleteTask(task.id) }
        catch { errorMessage = error.localizedDescription; await refresh() }
    }
}
