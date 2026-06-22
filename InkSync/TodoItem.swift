import Foundation

enum TodoSource: String, Codable, Equatable {
    case local
    case remote
}

struct TodoItem: Identifiable, Equatable, Codable {
    let id: String
    var title: String
    var notes: String?
    var isCompleted: Bool
    var dueDate: Date?
    var dueTime: Date?
    var priority: Int
    let listId: String
    let listName: String
    var lastModified: Date
    let source: TodoSource
    var cloudId: String?

    init(
        id: String,
        title: String,
        notes: String? = nil,
        isCompleted: Bool = false,
        dueDate: Date? = nil,
        dueTime: Date? = nil,
        priority: Int = 0,
        listId: String,
        listName: String,
        lastModified: Date = Date(),
        source: TodoSource = .local,
        cloudId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.priority = priority
        self.listId = listId
        self.listName = listName
        self.lastModified = lastModified
        self.source = source
        self.cloudId = cloudId
    }
}
