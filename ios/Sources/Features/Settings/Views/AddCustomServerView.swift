import SwiftUI

/// View for adding a custom MCP server by providing name and URL.
/// Auto-detects authentication requirements.
struct AddCustomServerView: View {
    let viewModel: MCPIntegrationsViewModel
    let onServerAdded: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var serverName = ""
    @State private var serverURL = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    inputSection
                    connectButton
                    Spacer()
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Custom Server")
                .title()
                .foregroundColor(Color.foreground["000"])

            Text("Connect to any MCP server by providing its URL. Authentication requirements will be detected automatically.")
                .body()
                .foregroundColor(Color.foreground["200"])
        }
    }

    // MARK: - Input Fields

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Server Name")
                    .headline()
                    .foregroundColor(Color.foreground["000"])

                TextField("My Server", text: $serverName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Server URL")
                    .headline()
                    .foregroundColor(Color.foreground["000"])

                TextField("https://example.com/mcp", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                Text("Include the full URL to the MCP endpoint")
                    .caption()
                    .foregroundColor(Color.foreground["300"])
            }

            if let error = errorMessage {
                Text(error)
                    .caption()
                    .foregroundColor(Color.semantic["error"])
            }
        }
    }

    // MARK: - Connect Button

    private var connectButton: some View {
        Button(action: { Task { await addServer() } }) {
            HStack {
                if isConnecting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                }
                Text(isConnecting ? "Connecting..." : "Add Server")
                    .body()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canConnect ? Color.semantic["success"] : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .disabled(!canConnect || isConnecting)
    }

    // MARK: - Helpers

    private var canConnect: Bool {
        !serverName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func addServer() async {
        guard canConnect else { return }

        isConnecting = true
        errorMessage = nil

        do {
            guard let apiClient = viewModel.apiClient else {
                throw APIClient.APIError.requestFailed(statusCode: nil, message: "API client not available")
            }

            let result = try await apiClient.addCustomServer(
                name: serverName.trimmingCharacters(in: .whitespacesAndNewlines),
                url: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            if result.success {
                if result.status == "enabled" {
                    // Server added directly - dismiss and show success
                    dismiss()
                    ToastManager.shared.show("Connected to \(serverName) with \(result.toolsCount ?? 0) tools", type: .success)
                    await onServerAdded()
                } else if result.status == "available" {
                    // Server needs auth - dismiss and let user connect from list
                    dismiss()
                    ToastManager.shared.show("\(serverName) added. Tap to connect.", type: .info)
                    await onServerAdded()
                }
            } else {
                errorMessage = result.error ?? "Connection failed"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isConnecting = false
    }
}
