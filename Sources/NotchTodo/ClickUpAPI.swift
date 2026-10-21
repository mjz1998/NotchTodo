import Foundation

struct ClickUpError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// ClickUp REST API v2 封装（个人 Token 直接放在 Authorization 头）
struct ClickUpAPI {
    let token: String
    private static let base = "https://api.clickup.com/api/v2"
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    @discardableResult
    private func send(_ method: String, _ path: String,
                      query: [URLQueryItem] = [],
                      body: [String: Any]? = nil) async throws -> Data {
        guard var comps = URLComponents(string: Self.base + path) else {
            throw ClickUpError(message: "无效的请求地址")
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw ClickUpError(message: "无效的请求地址") }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue(token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ClickUpError(message: "无效响应") }
        guard (200..<300).contains(http.statusCode) else {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let msg = obj?["err"] as? String ?? "请求失败"
            throw ClickUpError(message: "ClickUp \(http.statusCode)：\(msg)")
        }
        return data
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await send("GET", path, query: query)
        return try Self.decoder.decode(T.self, from: data)
    }

    func currentUser() async throws -> CUUser {
        let r: UserResponse = try await get("/user")
        return r.user
    }

    func teams() async throws -> [CUTeam] {
        let r: TeamsResponse = try await get("/team")
        return r.teams
    }

    /// 拉取分配给我的未关闭任务（含子任务），最多 5 页 * 100 条
    func myTasks(teamId: String, userId: Int) async throws -> [CUTask] {
        var all: [CUTask] = []
        for page in 0..<5 {
            let r: TasksResponse = try await get("/team/\(teamId)/task", query: [
                URLQueryItem(name: "assignees[]", value: String(userId)),
                URLQueryItem(name: "subtasks", value: "true"),
                URLQueryItem(name: "include_closed", value: "false"),
                URLQueryItem(name: "order_by", value: "due_date"),
                URLQueryItem(name: "page", value: String(page))
            ])
            all += r.tasks
            if r.lastPage == true || r.tasks.count < 100 { break }
        }
        return all
    }

    func listStatuses(listId: String) async throws -> [CUStatus] {
        let r: ListInfo = try await get("/list/\(listId)")
        return r.statuses
    }

    func updateTask(_ id: String, fields: [String: Any]) async throws {
        try await send("PUT", "/task/\(id)", body: fields)
    }

    func createTask(listId: String, name: String, assignee: Int?) async throws -> CUTask {
        var body: [String: Any] = ["name": name]
        if let assignee { body["assignees"] = [assignee] }
        let data = try await send("POST", "/list/\(listId)/task", body: body)
        return try Self.decoder.decode(CUTask.self, from: data)
    }

    func deleteTask(_ id: String) async throws {
        try await send("DELETE", "/task/\(id)")
    }
}
