import Foundation

protocol APIClient {
    func fetchDevices() async throws -> [Device]
    func fetchTodos(deviceId: String, status: String?) async throws -> [TodoItem]
    func createTodo(_ todo: TodoItem, deviceId: String) async throws -> TodoItem
    func updateTodo(_ todo: TodoItem) async throws -> TodoItem
    func deleteTodo(id: String, deviceId: String) async throws
    func markComplete(todoId: String, completed: Bool) async throws
}

final class MockAPIClient: APIClient {
    private var mockTodos: [String: [TodoItem]] = [
        "dev1": [],
        "dev2": []
    ]

    func fetchDevices() async throws -> [Device] {
        try await Task.sleep(nanoseconds: 500_000_000)
        return [
            Device(
                id: "dev1",
                alias: "书房墨水屏",
                lastSyncTime: Date().addingTimeInterval(-120),
                isOnline: true,
                syncedLists: []
            ),
            Device(
                id: "dev2",
                alias: "办公室墨水屏",
                lastSyncTime: Date().addingTimeInterval(-300),
                isOnline: true,
                syncedLists: []
            )
        ]
    }

    func fetchTodos(deviceId: String, status: String?) async throws -> [TodoItem] {
        try await Task.sleep(nanoseconds: 300_000_000)
        return mockTodos[deviceId] ?? []
    }

    func createTodo(_ todo: TodoItem, deviceId: String) async throws -> TodoItem {
        try await Task.sleep(nanoseconds: 200_000_000)
        if mockTodos[deviceId] == nil {
            mockTodos[deviceId] = []
        }
        mockTodos[deviceId]?.append(todo)
        return todo
    }

    func updateTodo(_ todo: TodoItem) async throws -> TodoItem {
        try await Task.sleep(nanoseconds: 200_000_000)
        for (deviceId, todos) in mockTodos {
            if let index = todos.firstIndex(where: { $0.id == todo.id }) {
                mockTodos[deviceId]?[index] = todo
                return todo
            }
        }
        return todo
    }

    func deleteTodo(id: String, deviceId: String) async throws {
        try await Task.sleep(nanoseconds: 200_000_000)
        mockTodos[deviceId]?.removeAll { $0.id == id }
    }

    func markComplete(todoId: String, completed: Bool) async throws {
        try await Task.sleep(nanoseconds: 100_000_000)
    }
}