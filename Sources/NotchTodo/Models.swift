import Foundation
import SwiftUI

struct CUUser: Decodable { let id: Int; let username: String? }
struct UserResponse: Decodable { let user: CUUser }

struct CUTeam: Decodable, Identifiable, Hashable { let id: String; let name: String }
struct TeamsResponse: Decodable { let teams: [CUTeam] }

struct CUStatus: Decodable, Hashable {
    let status: String
    let color: String?
    let type: String?          // open / custom / done / closed
}

struct CUListRef: Decodable, Hashable { let id: String; let name: String? }
struct CUPriority: Decodable, Hashable { let priority: String?; let color: String? }

struct CUTask: Decodable, Identifiable, Hashable {
    let id: String
    var name: String
    var status: CUStatus
    let dueDate: String?
    let url: String?
    let list: CUListRef?
    let priority: CUPriority?

    var isDone: Bool { status.type == "closed" || status.type == "done" }

    var dueDateValue: Date? {
        guard let s = dueDate, let ms = Double(s) else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }
}

struct TasksResponse: Decodable { let tasks: [CUTask]; let lastPage: Bool? }
struct ListInfo: Decodable { let statuses: [CUStatus] }

extension Color {
    init(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { self = .gray; return }
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { self = .gray; return }
        self = Color(red: Double((v >> 16) & 0xff) / 255,
                     green: Double((v >> 8) & 0xff) / 255,
                     blue: Double(v & 0xff) / 255)
    }
}

extension Date {
    var shortDueLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "今天" }
        if cal.isDateInTomorrow(self) { return "明天" }
        if cal.isDateInYesterday(self) { return "昨天" }
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: self)
    }
}
