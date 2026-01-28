import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// UIKit wrapper for Share Extension - presents SwiftUI view
class ShareViewController: UIViewController {
    private var hostingController: UIHostingController<ShareExtensionView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Extract shared content
        extractSharedContent { [weak self] url, text in
            guard let self = self else { return }

            // Create SwiftUI view with extracted content
            let shareView = ShareExtensionView(
                sharedURL: url,
                sharedText: text,
                extensionContext: self.extensionContext
            )

            // Wrap in UIHostingController
            let hosting = UIHostingController(rootView: shareView)
            self.hostingController = hosting

            // Add as child view controller
            self.addChild(hosting)
            self.view.addSubview(hosting.view)
            hosting.view.frame = self.view.bounds
            hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            hosting.didMove(toParent: self)
        }
    }

    private func extractSharedContent(completion: @escaping (String?, String?) -> Void) {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else {
            completion(nil, nil)
            return
        }

        // Check for URL first
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { (url, error) in
                DispatchQueue.main.async {
                    if let shareURL = url as? URL {
                        completion(shareURL.absoluteString, nil)
                    } else {
                        completion(nil, nil)
                    }
                }
            }
        }
        // Check for text
        else if itemProvider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            itemProvider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { (text, error) in
                DispatchQueue.main.async {
                    if let shareText = text as? String {
                        completion(nil, shareText)
                    } else {
                        completion(nil, nil)
                    }
                }
            }
        }
        else {
            completion(nil, nil)
        }
    }
}

// MARK: - SwiftUI View

struct Goal: Identifiable {
    let id: String
    let title: String
}

struct ShareExtensionView: View {
    let sharedURL: String?
    let sharedText: String?
    let extensionContext: NSExtensionContext?

    @State private var noteText: String = ""
    @State private var selectedGoalId: String?
    @State private var goals: [Goal] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var saveSuccess = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if saveSuccess {
                    successView
                } else {
                    contentForm
                }
            }
            .navigationTitle("Save to Houston")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancel()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(isSaving || (sharedURL == nil && sharedText == nil))
                }
            }
        }
        .onAppear {
            loadGoals()
            // Pre-fill note with shared text if available
            if let text = sharedText {
                noteText = text
            }
        }
    }

    private var contentForm: some View {
        Form {
            // Shared content preview
            Section("Content") {
                if let url = sharedURL {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(url)
                            .font(.body)
                            .lineLimit(2)
                    }
                }
                if let text = sharedText {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(text)
                            .font(.body)
                            .lineLimit(3)
                    }
                }
            }

            // Note field
            Section("Add Note (Optional)") {
                TextEditor(text: $noteText)
                    .frame(minHeight: 80)
            }

            // Goal selection
            Section("Associate with Goal (Optional)") {
                if goals.isEmpty {
                    Text("No goals found")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Goal", selection: $selectedGoalId) {
                        Text("None").tag(nil as String?)
                        ForEach(goals) { goal in
                            Text(goal.title).tag(goal.id as String?)
                        }
                    }
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Saved!")
                .font(.title2.bold())

            if let goalTitle = goals.first(where: { $0.id == selectedGoalId })?.title {
                Text("Added to \(goalTitle)")
                    .foregroundStyle(.secondary)
            }

            Button("Done") {
                closeExtension()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadGoals() {
        isLoading = true
        Task {
            do {
                let client = try IntentAPIClient.create()
                let goalResources = try await client.listGoals()
                await MainActor.run {
                    goals = goalResources.map { Goal(id: $0.id, title: $0.attributes.title) }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load goals: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                let client = try IntentAPIClient.create()

                // Build note content
                var content = ""
                if let url = sharedURL {
                    content += url
                }
                if !noteText.isEmpty {
                    if !content.isEmpty {
                        content += "\n\n"
                    }
                    content += noteText
                }
                if let text = sharedText, content.isEmpty {
                    content = text
                }

                // Create note
                _ = try await client.createNote(
                    title: nil,
                    content: content,
                    goalId: selectedGoalId
                )

                await MainActor.run {
                    isSaving = false
                    saveSuccess = true

                    // Auto-close after showing success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        closeExtension()
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "ShareExtension", code: 0))
    }

    private func closeExtension() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
