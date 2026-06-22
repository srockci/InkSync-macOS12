import EventKit
import Foundation

extension EKReminder {
    func toTodoItem(listId: String, listName: String) -> TodoItem {
        TodoItem(
            id: calendarItemIdentifier,
            title: title ?? "",
            notes: notes,
            isCompleted: isCompleted,
            dueDate: dueDateComponents?.date,
            dueTime: nil,
            priority: 0,
            listId: listId,
            listName: listName,
            lastModified: lastModifiedDate ?? Date(),
            source: .local
        )
    }
}
