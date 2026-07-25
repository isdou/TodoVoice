import Foundation
import SwiftData

@Model
final class TodoItem: Identifiable {
    var title: String
    var createdAt: Date
    var dueDate: Date?
    var isCompleted: Bool
    var transcript: String
    var notificationId: String

    init(title: String, dueDate: Date? = nil, transcript: String = "") {
        self.title = title
        self.createdAt = .now
        self.dueDate = dueDate
        self.isCompleted = false
        self.transcript = transcript
        self.notificationId = UUID().uuidString
    }
}
