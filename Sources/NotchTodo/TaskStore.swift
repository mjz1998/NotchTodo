import Foundation
import SwiftUI

@MainActor
final class TaskStore: ObservableObject {
    @Published var tasks: [CUTask] = []
    @Published var teams: [CUTeam] = []
    @Published var statusesByList: [String: [CUStatus]] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var hasToken = false

    @Published var teamId: String {
        didSet { UserDefaults.standard.set(teamId, forKey: "teamId") }
    }
    @Published var defaultListId: String {
        didSet { UserDefaults.standard.set(defaultListId, forKey: "defaultListId") }
    }

    private var api: ClickUpAPI?
    private var userId: Int?
    private var timer: Timer?
    private let tokenAccount = "apiToken"

    init() {
        teamId = UserDefaults.standard.string(forKey: "teamId") ?? ""
        defaultListId = UserDefaults.standard.string(forKey: "defaultListId") ?? ""
        if let t = Keychain.load(account: tokenAccount), !t.isEmpty {
            api = ClickUpAPI(token: t)
            hasToken = true
        }
        Task { await bootstrap() }
        // 每 60 秒自动刷新
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    // MARK: - 账户

    /// 校验并保存 API Key，成功返回 true
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
        tasks = []; teams = []; statusesByList = [:]
    }

    private func bootstrap() async {
        guard let api else { return }
        do {
            if userId == nil { userId = try await api.currentUser().id }
            teams = try await api.teams()
            if teamId.isEmpty || !teams.contains(where: { $0.id == teamId }) {
                teamId = teams.first?.id ?? ""
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
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
            case (nil, _?):    return false
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
        tasks[idx].name = name                       // 乐观更新
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

    /// 勾选：切换到清单的完成状态；取消勾选：切回第一个 open 状态
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

    func create(_ rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let api, !name.isEmpty else { return }
        let listId = defaultListId.isEmpty ? (tasks.first?.list?.id ?? "") : defaultListId
        guard !listId.isEmpty else {
            errorMessage = "请先在设置中填写默认 List ID"
            return
        }
        do {
            let t = try await api.createTask(listId: listId, name: name, assignee: userId)
            withAnimation { tasks.insert(t, at: 0) }
            _ = await statuses(for: listId)
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
