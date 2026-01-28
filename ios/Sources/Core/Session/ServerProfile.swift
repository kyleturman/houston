import Foundation

struct ServerProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var baseURLString: String
    var email: String?

    var baseURL: URL? { URL(string: baseURLString) }

    init(id: UUID = UUID(), name: String, baseURL: URL, email: String? = nil) {
        self.id = id
        self.name = name
        self.baseURLString = baseURL.absoluteString
        self.email = email
    }
}
