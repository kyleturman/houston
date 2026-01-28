import Foundation

// MARK: - Response Validation
//
// Helpers for validating HTTP responses and decoding JSON.
// These eliminate the repeated guard patterns throughout APIClient.

extension APIClient {
    /// Validate HTTP response status code (200-299)
    /// - Parameters:
    ///   - data: Response data
    ///   - response: URL response
    /// - Returns: The validated data
    /// - Throws: APIError.requestFailed if status code is not 2xx
    func validateResponse(_ data: Data, _ response: URLResponse) throws -> Data {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.requestFailed(
                statusCode: (response as? HTTPURLResponse)?.statusCode,
                message: String(data: data, encoding: .utf8)
            )
        }
        return data
    }

    /// Validate HTTP response and decode to specified type
    /// - Parameters:
    ///   - type: The type to decode to
    ///   - data: Response data
    ///   - response: URL response
    ///   - decoder: JSONDecoder to use (default: standard)
    /// - Returns: Decoded object of type T
    /// - Throws: APIError.requestFailed or APIError.decodingFailed
    func validateAndDecode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        response: URLResponse,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        let validatedData = try validateResponse(data, response)
        do {
            return try decoder.decode(T.self, from: validatedData)
        } catch {
            APILogger.decodingError(error, context: String(describing: T.self), rawResponse: data)
            throw APIError.decodingFailed
        }
    }

    /// Validate HTTP response and decode with ISO8601 date strategy
    /// - Parameters:
    ///   - type: The type to decode to
    ///   - data: Response data
    ///   - response: URL response
    /// - Returns: Decoded object of type T
    /// - Throws: APIError.requestFailed or APIError.decodingFailed
    func validateAndDecodeWithDates<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        response: URLResponse
    ) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try validateAndDecode(type, from: data, response: response, decoder: decoder)
    }
}
