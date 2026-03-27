import Foundation

// MARK: - Shared

enum ProgressColor {
    static func forPercentage(_ pct: Double) -> (r: Double, g: Double, b: Double) {
        if pct < 0.5 { return (0.2, 0.8, 0.3) }  // green
        if pct < 0.8 { return (1.0, 0.6, 0.0) }   // orange
        return (1.0, 0.2, 0.2)                       // red
    }
}

func parseISO8601(_ string: String?) -> Date? {
    guard let string else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
}

// MARK: - Cursor

struct CursorUsageResponse: Codable {
    let gpt4: CursorModelUsage?
    let startOfMonth: String?

    enum CodingKeys: String, CodingKey {
        case gpt4 = "gpt-4"
        case startOfMonth
    }
}

struct CursorModelUsage: Codable {
    let numRequests: Int
    let maxRequestUsage: Int?
}

struct CursorQuota {
    let used: Int
    let limit: Int
    let resetDate: Date?

    var percentage: Double { limit > 0 ? Double(used) / Double(limit) : 0 }
    var daysUntilReset: Int? {
        guard let resetDate else { return nil }
        return Calendar.current.dateComponents([.day], from: .now, to: resetDate).day
    }
}

// MARK: - Claude Code

struct ClaudeUsageResponse: Codable {
    let fiveHour: ClaudeWindow?
    let sevenDay: ClaudeWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

struct ClaudeWindow: Codable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct ClaudeQuota {
    let fiveHourPct: Double
    let fiveHourReset: Date?
    let sevenDayPct: Double
    let sevenDayReset: Date?
}
