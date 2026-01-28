import SwiftUI

struct NoteComposeSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionManager.self) var session
    @Environment(NavigationViewModel.self) var navigationVM

    let initialGoal: Goal?
    let existingNote: Note?  // If editing an existing note
    let isRecoveryMode: Bool  // Recovery from failed save
    let initialContent: String?  // Pre-fill content (e.g., from Share Extension)
    var onCreated: ((Note) -> Void)?
    var onUpdated: ((Note) -> Void)?
    var onCreateFailed: ((Note, String) -> Void)?  // Callback for failed creates

    @State private var title: String = ""
    @State private var content: String = ""
    @State private var selectedGoal: Goal?  // Track the selected goal (can be removed)
    @State private var saving: Bool = false
    @State private var errorMessage: String?
    @State private var showAutoAssignHint: Bool = true
    @FocusState private var isFocused: Bool

    private var isEditing: Bool {
        existingNote != nil && !isRecoveryMode
    }

    init(initialGoal: Goal? = nil, existingNote: Note? = nil, isRecoveryMode: Bool = false, initialContent: String? = nil, initialErrorMessage: String? = nil, onCreated: ((Note) -> Void)? = nil, onUpdated: ((Note) -> Void)? = nil, onCreateFailed: ((Note, String) -> Void)? = nil) {
        self.initialGoal = initialGoal
        self.existingNote = existingNote
        self.isRecoveryMode = isRecoveryMode
        self.initialContent = initialContent
        self.onCreated = onCreated
        self.onUpdated = onUpdated
        self.onCreateFailed = onCreateFailed

        // Initialize selectedGoal
        self._selectedGoal = State(initialValue: initialGoal)

        // Initialize error message if in recovery mode
        self._errorMessage = State(initialValue: initialErrorMessage)

        // Initialize content from initialContent if provided
        self._content = State(initialValue: initialContent ?? "")
    }

    private var hasURL: Bool {
        detectURL(in: content) != nil
    }

    private var savingMessage: String {
        if hasURL {
            return "Saving link..."
        } else {
            return "Saving..."
        }
    }

    private var isSaveDisabled: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .padding([.horizontal, .top])
                }

                VStack(spacing: 12) {
                    TextField("Title (optional)", text: $title)
                        .font(.bodyLarge)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    ZStack(alignment: .topLeading) {
                        if content.isEmpty {
                            Text("What's on your mind?")
                                .font(.bodyLarge)
                                .foregroundColor(Color.foreground["500"])
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }
                        
                        TextEditor(text: $content)
                            .font(.bodyLarge)
                            .focused($isFocused)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .immediateKeyboard()
                .background(Color.background["100"])
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                            .padding(.horizontal, -12)
                            .font(.bodyLarge.weight(.semibold))
                            .disabled(saving)
                            .foregroundColor(Color.foreground["200"])
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                            .font(.bodyLarge.weight(.semibold))
                            .disabled(saving)
                            .foregroundColor(Color.foreground["200"])
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        } else {
                            Text(isEditing ? "Update note" : "Save note")
                                .font(.bodyLarge.weight(.semibold))
                                .foregroundColor(isSaveDisabled ? Color.foreground["500"] : Color.accent(selectedGoal))
                        }
                    }
                    .padding(.horizontal, 4)
                    .disabled(isSaveDisabled)
                }
            }
            .safeAreaInset(edge: .bottom, alignment: .leading) {
                // Show goal pill if saving to a goal
                if let goal = selectedGoal {
                    HStack(spacing: 8) {
                        Label("Adding to \(goal.title)", systemImage: "target")
                            .font(.caption)
                            .foregroundColor(Color.accent(goal))
                        
                        Spacer()

                        // X button to remove goal
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedGoal = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(Color.foreground["000"].opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.accent(goal), lineWidth: 0.5)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if showAutoAssignHint {
                    HStack {
                        Label("Note will auto-assign to relevant goal", systemImage: "target")
                            .font(.caption)
                            .foregroundColor(Color.foreground["500"])
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear {
                // Pre-fill fields if editing
                if let note = existingNote {
                    print("📝 Editing note - title: \(note.title ?? "nil"), content length: \(note.content?.count ?? 0)")
                    self.title = note.title ?? ""
                    self.content = note.content ?? ""
                    self.selectedGoal = initialGoal
                } else {
                    print("📝 Creating new note")
                }

                // Focus the content editor immediately (keyboard already triggered by immediateKeyboard())
                self.isFocused = true
                
                // Hide auto-assign hint after a few seconds
                Task {
                    try? await Task.sleep(for: .seconds(6))
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAutoAssignHint = false
                        }
                    }
                }
            }
        }
    }

    private func detectURL(in text: String) -> String? {
        // Simple URL detection using NSDataDetector
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        return matches.first?.url?.absoluteString
    }

    @MainActor
    private func save() async {
        errorMessage = nil
        saving = true
        defer { saving = false }

        guard let base = session.serverURL else {
            errorMessage = "Missing server configuration"
            return
        }

        if isEditing {
            // Update existing note
            guard let noteId = existingNote?.id else { return }

            // Show loading toast
            let toastId = ToastManager.shared.showLoading("Updating note...")

            // Close sheet immediately
            dismiss()

            // Update in background
            Task {
                let client = APIClient(baseURL: base, deviceTokenProvider: { session.deviceToken }, userTokenProvider: { session.userToken })
                do {
                    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let resource = try await client.updateNote(
                        id: noteId,
                        title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                        content: content,
                        goalId: selectedGoal?.id
                    )
                    let updatedNote = Note.from(resource: resource)

                    // Call callback with updated note
                    onUpdated?(updatedNote)

                    // Update toast to success
                    await MainActor.run {
                        ToastManager.shared.updateToast(id: toastId, message: "Note updated", type: .success)
                    }
                } catch {
                    print("Failed to update note: \(error)")

                    // Update toast to error
                    await MainActor.run {
                        ToastManager.shared.updateToast(id: toastId, message: "Failed to update note", type: .error)
                    }
                }
            }
        } else {
            // Create new note
            // Create optimistic note immediately
            let optimisticNote = Note(
                id: UUID().uuidString,  // Temporary ID
                title: title.isEmpty ? nil : title,
                content: content,
                source: .user,
                createdAt: Date(),
                ogImage: nil,
                images: nil,
                goalId: selectedGoal?.id,
                metadata: nil
            )

            // Add to UI immediately (optimistic)
            onCreated?(optimisticNote)

            // Dismiss sheet immediately
            dismiss()

            // Show loading toast
            let toastId = ToastManager.shared.showLoading(hasURL ? "Saving link..." : "Saving note...")

            // Save to backend in background
            Task {
                let client = APIClient(baseURL: base, deviceTokenProvider: { session.deviceToken }, userTokenProvider: { session.userToken })
                do {
                    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let resource = try await client.createNote(
                        title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                        content: content,
                        goalId: selectedGoal?.id
                    )
                    let savedNote = Note.from(resource: resource)

                    // Update UI with real note (replaces optimistic)
                    onCreated?(savedNote)

                    // Show success toast with goal name
                    await MainActor.run {
                        // Find goal name if note was assigned to a goal
                        var successMessage = "Note saved"
                        if let goalId = savedNote.goalId,
                           let goal = navigationVM.goalsVM.goals.first(where: { $0.id == goalId }) {
                            successMessage = "Note saved to \(goal.title)"
                        }

                        ToastManager.shared.updateToast(id: toastId, message: successMessage, type: .success)
                    }
                } catch {
                    print("Failed to save note: \(error)")

                    // Extract error message from backend
                    var errorMessage = "Failed to save note"
                    if let apiError = error as? APIClient.APIError,
                       case .requestFailed(_, let message) = apiError,
                       let message = message,
                       let data = message.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let backendError = json["error"] as? String {
                        errorMessage = backendError
                    }

                    // Show error toast
                    await MainActor.run {
                        ToastManager.shared.updateToast(id: toastId, message: errorMessage, type: .error)

                        // Trigger recovery mode - parent will re-open sheet with note content
                        onCreateFailed?(optimisticNote, errorMessage)
                    }
                }
            }
        }
    }
}
