import Foundation

struct APIResponse<T: Decodable>: Decodable {
    let code: Int
    let data: T?
    let message: String?
}

struct DeviceDTO: Decodable {
    let deviceId: String
    let alias: String
    let board: String?
    let lastSyncTime: Date?
    let isOnline: Bool?

    func toDevice() -> Device {
        Device(
            id: deviceId,
            alias: alias,
            lastSyncTime: lastSyncTime,
            isOnline: isOnline ?? false,
            syncedLists: []
        )
    }
}

struct TodoDTO: Decodable {
    let id: Int
    let title: String
    let description: String?
    let dueDate: String?
    let dueTime: String?
    let repeatType: String?
    let status: Int?
    let priority: Int
    let completed: Bool
    let deviceId: String
    let deviceName: String?
    let createDate: String?
    let updateDate: Int?

    func toTodoItem(listId: String, listName: String) -> TodoItem? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let parsedDueDate = dueDate.flatMap { dateFormatter.date(from: $0) }

        dateFormatter.dateFormat = "HH:mm"
        let parsedDueTime = dueTime.flatMap { dateFormatter.date(from: $0) }

        let parsedLastModified: Date
        if let ts = updateDate {
            parsedLastModified = Date(timeIntervalSince1970: TimeInterval(ts))
        } else if let create = createDate {
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            parsedLastModified = dateFormatter.date(from: create) ?? Date()
        } else {
            parsedLastModified = Date()
        }

        return TodoItem(
            id: "\(id)",
            title: title,
            notes: description,
            isCompleted: completed,
            dueDate: parsedDueDate,
            dueTime: parsedDueTime,
            priority: priority,
            listId: listId,
            listName: listName,
            lastModified: parsedLastModified,
            source: .remote
        )
    }

    static func fromTodoItem(_ item: TodoItem, deviceId: String) -> [String: Any] {
        var dict: [String: Any] = [
            "title": item.title,
            "completed": item.isCompleted,
            "status": item.isCompleted ? 1 : 0,
            "priority": item.priority,
            "deviceId": deviceId
        ]
        if let notes = item.notes {
            dict["description"] = notes
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        if let dueDate = item.dueDate {
            dict["dueDate"] = dateFormatter.string(from: dueDate)
        }
        dateFormatter.dateFormat = "HH:mm"
        if let dueTime = item.dueTime {
            dict["dueTime"] = dateFormatter.string(from: dueTime)
        }
        return dict
    }
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(Int)
    case decodingError(Error)
    case networkError(Error)
    case unexpectedResponse(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 URL"
        case .invalidResponse:
            return "服务器响应无效"
        case .unauthorized:
            return "API Key 无效或已过期"
        case .serverError(let code):
            return "服务器错误: \(code)"
        case .decodingError(let error):
            return "数据解析失败: \(error.localizedDescription)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .unexpectedResponse(let code, let body):
            return "意外响应: HTTP \(code), body: \(body ?? "nil")"
        }
    }
}

final class RealAPIClient: APIClient {
    private let session: URLSession
    private let baseURL: String
    private let apiKey: String
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(apiKey: String? = nil, baseURL: String? = nil) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        self.apiKey = apiKey ?? AppConfig.shared.apiKey
        self.baseURL = baseURL ?? AppConfig.shared.apiURL

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    func fetchDevices() async throws -> [Device] {
        guard let url = URL(string: "\(baseURL)/devices") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        let bodyString = String(data: data, encoding: .utf8)

        switch httpResponse.statusCode {
        case 200...299:
            do {
                let apiResponse = try decoder.decode(APIResponse<[DeviceDTO]>.self, from: data)
                if apiResponse.code == 0, let deviceDTOs = apiResponse.data {
                    return deviceDTOs.map { $0.toDevice() }
                } else {
                    throw APIError.serverError(apiResponse.code)
                }
            } catch let error as APIError {
                throw error
            } catch {
                throw APIError.decodingError(error)
            }
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.unexpectedResponse(httpResponse.statusCode, bodyString)
        }
    }

    func fetchTodos(deviceId: String, status: String?) async throws -> [TodoItem] {
        var urlComponents = URLComponents(string: "\(baseURL)/todos")!
        var queryItems = [URLQueryItem(name: "deviceId", value: deviceId)]
        if let status = status {
            queryItems.append(URLQueryItem(name: "status", value: status))
        }
        urlComponents.queryItems = queryItems

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            let apiResponse = try decoder.decode(APIResponse<[TodoDTO]>.self, from: data)
            if apiResponse.code == 0, let todoDTOs = apiResponse.data {
                return todoDTOs.compactMap { $0.toTodoItem(listId: deviceId, listName: $0.deviceName ?? "") }
            } else {
                throw APIError.serverError(apiResponse.code)
            }
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func createTodo(_ todo: TodoItem, deviceId: String) async throws -> TodoItem {
        let url = URL(string: "\(baseURL)/todos")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let dict = TodoDTO.fromTodoItem(todo, deviceId: deviceId)
        request.httpBody = try JSONSerialization.data(withJSONObject: dict)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            let apiResponse = try decoder.decode(APIResponse<TodoDTO>.self, from: data)
            if apiResponse.code == 0, let todoDTO = apiResponse.data {
                return todoDTO.toTodoItem(listId: deviceId, listName: todoDTO.deviceName ?? "") ?? todo
            } else {
                throw APIError.serverError(apiResponse.code)
            }
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func updateTodo(_ todo: TodoItem) async throws -> TodoItem {
        let url = URL(string: "\(baseURL)/todos/\(todo.id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let dict = TodoDTO.fromTodoItem(todo, deviceId: "")
        request.httpBody = try JSONSerialization.data(withJSONObject: dict)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            let apiResponse = try decoder.decode(APIResponse<TodoDTO>.self, from: data)
            if apiResponse.code == 0, let todoDTO = apiResponse.data {
                return todoDTO.toTodoItem(listId: todo.listId, listName: todo.listName) ?? todo
            } else {
                throw APIError.serverError(apiResponse.code)
            }
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func deleteTodo(id: String, deviceId: String) async throws {
        let url = URL(string: "\(baseURL)/todos/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299, 404:
            return
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func markComplete(todoId: String, completed: Bool) async throws {
        let action = completed ? "complete" : "incomplete"
        let url = URL(string: "\(baseURL)/todos/\(todoId)/\(action)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
}