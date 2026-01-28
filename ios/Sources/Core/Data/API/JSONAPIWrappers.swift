import Foundation

// MARK: - JSON:API Response Wrappers
//
// These generic wrappers decode JSON:API formatted responses from the backend.
// JSON:API spec: https://jsonapi.org/
//
// Example response:
// {
//   "data": { "id": "123", "type": "goal", "attributes": {...} }
// }
//
// Or for lists:
// {
//   "data": [
//     { "id": "123", "type": "goal", "attributes": {...} },
//     { "id": "456", "type": "goal", "attributes": {...} }
//   ]
// }

/// Wraps a JSON:API response containing a single resource
struct JSONAPISingle<T: Decodable>: Decodable {
    let data: T
}

/// Wraps a JSON:API response containing a list of resources
struct JSONAPIList<T: Decodable>: Decodable {
    let data: [T]
}

/// Pagination metadata for cursor-based pagination (notes, etc.)
struct CursorPaginationMeta: Decodable, Sendable {
    let has_more: Bool
    let next_cursor: String?
    let per_page: Int
    let count: Int
}

/// Wraps a JSON:API response containing a list of resources with cursor pagination metadata
struct JSONAPICursorPaginatedList<T: Decodable>: Decodable {
    let data: [T]
    let meta: CursorPaginationMeta
}
