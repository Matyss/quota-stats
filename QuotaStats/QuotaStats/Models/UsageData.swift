import Foundation

struct UsageResponse: Codable {
    let gpt4: ModelUsage?
    let gpt35Turbo: ModelUsage?
    let startOfMonth: String?

    enum CodingKeys: String, CodingKey {
        case gpt4 = "gpt-4"
        case gpt35Turbo = "gpt-3.5-turbo"
        case startOfMonth
    }
}

struct ModelUsage: Codable {
    let numRequests: Int
    let numRequestsTotal: Int
    let numTokens: Int
    let maxRequestUsage: Int?
    let maxTokenUsage: Int?
}

struct QuotaInfo {
    let used: Int
    let limit: Int
    let resetDate: Date?

    var remaining: Int { limit - used }
    var percentage: Double { limit > 0 ? Double(used) / Double(limit) : 0 }
    var daysUntilReset: Int? {
        guard let resetDate else { return nil }
        return Calendar.current.dateComponents([.day], from: .now, to: resetDate).day
    }

    static let placeholder = QuotaInfo(used: 0, limit: 500, resetDate: nil)
}
