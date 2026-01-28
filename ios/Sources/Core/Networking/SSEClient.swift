import Foundation

/// A lightweight Server-Sent Events client using URLSession.
/// Supports auto-reconnect with backoff and line-by-line SSE parsing.
final class SSEClient: @unchecked Sendable {
    /// SSE event types supported by this client
    ///
    /// IMPORTANT: When adding new SSE events from the backend, you MUST add them here!
    /// If you forget, the event will silently become `.unknown` and not be processed.
    ///
    /// For global lifecycle events (notes/tasks/goals), you must also update:
    /// - `StateManager.swift` - Add event struct, publisher, and handleEvent() case
    ///
    /// See ios/CLAUDE.md "Adding New SSE Event Types" section for full instructions.
    enum EventType: String {
        // Agent chat events (per-chat/task streams)
        case welcome
        case start
        case chunk
        case done
        case message
        case processing  // Immediate feedback when user message received, before job starts
        case tool_call  // LLM is calling a tool (e.g., finalize_goal_creation)
        case tool_execution_start  // Tool execution started (for task activity status)
        case tool_execution_complete  // Tool execution completed
        case turn_start
        case turn_done
        case task_update
        case task_completed
        case goal_archived
        case think
        case keepalive  // Backend heartbeat to keep connection alive
        case error
        case unknown

        // Global lifecycle events (per-user stream for real-time resource updates)
        case note_created
        case note_updated
        case note_deleted
        case note_archived
        case task_created
        case task_updated
        case task_deleted
        case task_archived
        case goal_created
        case goal_updated
        case goal_deleted
        case feed_insights_ready  // Feed insights generated and ready for viewing
        case agent_history_deleted  // Agent session history deleted
        case agent_session_reset  // Current session was reset/cleared
    }

    struct Event: Sendable {
        let type: EventType
        let data: String
    }

    private let urlRequestProvider: () throws -> URLRequest
    private let onEvent: (Event) -> Void
    private let onOpen: (() -> Void)?
    private let onError: ((Error) -> Void)?

    private var task: URLSessionDataTask?
    private var isCancelled = false
    private var isCompleted = false // Track if task/goal is completed
    private var isStoppedIntentionally = false // Track intentional stop() calls

    // Reconnect backoff
    private var attempt = 0
    private let backoff: [TimeInterval] = [1, 2, 5, 10, 20]

    init(urlRequestProvider: @escaping () throws -> URLRequest,
         onEvent: @escaping (Event) -> Void,
         onOpen: (() -> Void)? = nil,
         onError: ((Error) -> Void)? = nil) {
        self.urlRequestProvider = urlRequestProvider
        self.onEvent = onEvent
        self.onOpen = onOpen
        self.onError = onError
    }

    func start() {
        isCancelled = false
        isCompleted = false
        isStoppedIntentionally = false
        connect()
    }

    func stop() {
        print("[SSEClient] Stopping stream intentionally")
        isCancelled = true
        isStoppedIntentionally = true
        task?.cancel()
        task = nil
    }

    private func connect() {
        guard !isCancelled && !isCompleted else { return }
        
        do {
            let req = try urlRequestProvider()
            let config = URLSessionConfiguration.default
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            config.waitsForConnectivity = false  // Fail fast instead of waiting
            config.timeoutIntervalForRequest = 10  // Reduced timeout for faster failure
            config.timeoutIntervalForResource = 0 // No timeout for streaming
            
            // Note: You may see "nw_socket_set_connection_idle setsockopt SO_CONNECTION_IDLE failed"
            // warnings in console. This is a harmless system-level warning from Apple's Network.framework
            // when it tries to set socket options not available on all network protocols. Cannot be suppressed.
            
            let delegate = StreamDelegate(onOpen: { [weak self] in
                self?.attempt = 0
                self?.onOpen?()
            }, onEvent: { [weak self] event in
                // Check for completion events
                if event.type == .task_completed || event.type == .goal_archived {
                    self?.isCompleted = true
                    print("[SSEClient] Task completed or Goal archived, stopping reconnection attempts")
                }
                self?.onEvent(event)
            }, onError: { [weak self] error in
                self?.handleError(error)
            })
            
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: req)
            self.task = task
            task.resume()
        } catch {
            handleError(error)
        }
    }

    private func scheduleReconnect() {
        guard !isCancelled && !isCompleted else { return }
        let delay = backoff[min(attempt, backoff.count - 1)]
        attempt += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }

    private func handleError(_ error: Error) {
        let nsError = error as NSError
        
        // Don't report intentional stops or reconnect
        if isStoppedIntentionally {
            print("[SSEClient] Ignoring error from intentional stop")
            return
        }
        
        // Check if this is a graceful closure - reconnect silently
        if let isGraceful = nsError.userInfo["GracefulClosure"] as? Bool, isGraceful {
            print("[SSEClient] Graceful closure, reconnecting silently...")
            scheduleReconnect()
            return
        }
        
        print("[SSEClient] Connection error: \(error.localizedDescription)")
        
        // Check if this is an HTTP error that indicates completion/termination
        if let statusCode = nsError.userInfo["HTTPStatusCode"] as? Int {
            // 422 Unprocessable Entity for completed/paused tasks - don't retry
            if statusCode == 422 {
                print("[SSEClient] Received 422 status, likely task completed - stopping reconnection")
                isCompleted = true
                onError?(error)
                return
            }
            
            // Other client errors (4xx) that shouldn't be retried
            if statusCode >= 400 && statusCode < 500 && statusCode != 429 { // 429 is rate limit, should retry
                print("[SSEClient] Received client error \(statusCode) - stopping reconnection")
                isCompleted = true
                onError?(error)
                return
            }
        }
        
        // Only report actual errors to error handler
        onError?(error)
        scheduleReconnect()
    }
}

private final class StreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let onOpen: @Sendable () -> Void
    private let onEvent: @Sendable (SSEClient.Event) -> Void
    private let onError: @Sendable (Error) -> Void

    private var buffer = Data()
    private var didOpen = false
    private var httpResponse: HTTPURLResponse?

    init(onOpen: @escaping @Sendable () -> Void,
         onEvent: @escaping @Sendable (SSEClient.Event) -> Void,
         onError: @escaping @Sendable (Error) -> Void) {
        self.onOpen = onOpen
        self.onEvent = onEvent
        self.onError = onError
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        httpResponse = response as? HTTPURLResponse
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if !didOpen {
            didOpen = true
            print("[SSEClient] Stream connection opened")
            onOpen()
        }
        buffer.append(data)
        processBuffer()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            let nsError = error as NSError
            
            // Check if this was an intentional cancellation
            if nsError.code == NSURLErrorCancelled && nsError.domain == NSURLErrorDomain {
                print("[SSEClient] Stream cancelled (intentional stop)")
                // Don't call onError for intentional cancellations
                return
            }
            
            print("[SSEClient] Stream error: \(error.localizedDescription)")
            // Create enhanced error with HTTP response if available
            if let httpResponse = self.httpResponse {
                let enhancedError = NSError(
                    domain: error._domain,
                    code: error._code,
                    userInfo: (error as NSError).userInfo.merging([
                        "HTTPStatusCode": httpResponse.statusCode,
                        "HTTPResponse": httpResponse
                    ]) { _, new in new }
                )
                onError(enhancedError)
            } else {
                onError(error)
            }
        } else {
            print("[SSEClient] Stream closed gracefully by server")
            // Server closed gracefully - this is normal, just trigger reconnect silently
            onError(NSError(domain: "SSEClient", code: -9999, userInfo: [
                NSLocalizedDescriptionKey: "Stream closed",
                "GracefulClosure": true
            ]))
        }
    }

    private func processBuffer() {
        // SSE frames are separated by double newlines. Lines start with "event:" and "data:".
        // We parse lines and emit events when a frame is complete.
        while let range = buffer.range(of: Data("\n\n".utf8)) {
            let frameData = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            if let frame = String(data: frameData, encoding: .utf8) {
                emit(frame: frame)
            }
        }
    }

    private func emit(frame: String) {
        var eventType: SSEClient.EventType = .unknown
        var dataLines: [String] = []
        for line in frame.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("event:") {
                let raw = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
                eventType = SSEClient.EventType(rawValue: String(raw)) ?? .unknown
            } else if line.hasPrefix("data:") {
                let datum = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                dataLines.append(String(datum))
            }
        }
        let data = dataLines.joined(separator: "\n")
        onEvent(.init(type: eventType, data: data))
    }
}
