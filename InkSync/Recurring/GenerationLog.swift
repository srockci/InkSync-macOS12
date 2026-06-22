import Foundation

struct GenerationLog: Codable, Identifiable {
    let id: UUID
    let ruleId: UUID
    let ruleTitle: String
    let scheduledTime: Date
    let actualTime: Date
    var success: Bool
    var createdItemId: String?
    var errorMessage: String?
    var isCatchup: Bool

    init(
        id: UUID = UUID(),
        ruleId: UUID,
        ruleTitle: String,
        scheduledTime: Date,
        actualTime: Date = Date(),
        success: Bool = false,
        createdItemId: String? = nil,
        errorMessage: String? = nil,
        isCatchup: Bool = false
    ) {
        self.id = id
        self.ruleId = ruleId
        self.ruleTitle = ruleTitle
        self.scheduledTime = scheduledTime
        self.actualTime = actualTime
        self.success = success
        self.createdItemId = createdItemId
        self.errorMessage = errorMessage
        self.isCatchup = isCatchup
    }

    enum CodingKeys: String, CodingKey {
        case id, ruleId, ruleTitle, scheduledTime, actualTime
        case success, createdItemId, errorMessage, isCatchup
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.ruleId = try c.decode(UUID.self, forKey: .ruleId)
        self.ruleTitle = try c.decode(String.self, forKey: .ruleTitle)
        self.scheduledTime = try c.decode(Date.self, forKey: .scheduledTime)
        self.actualTime = try c.decode(Date.self, forKey: .actualTime)
        self.success = try c.decode(Bool.self, forKey: .success)
        self.createdItemId = try c.decodeIfPresent(String.self, forKey: .createdItemId)
        self.errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        self.isCatchup = try c.decodeIfPresent(Bool.self, forKey: .isCatchup) ?? false
    }
}
