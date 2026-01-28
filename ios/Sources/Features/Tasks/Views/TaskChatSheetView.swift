import SwiftUI

struct TaskChatSheetView: View {
    @Environment(SessionManager.self) var session
    @Environment(NavigationViewModel.self) var navigationVM
    let taskId: String

    @State private var task: AgentTaskModel?
    @State private var loading: Bool = true
    @State private var error: String?
    @State private var chatViewModel: ChatViewModel?
    @State private var selectedTab: TaskTab = .activity

    /// Binding for error alert that properly clears error when dismissed
    private var errorBinding: Binding<LocalizedErrorWrapper?> {
        Binding(
            get: { error.map { LocalizedErrorWrapper(message: $0) } },
            set: { _ in error = nil }
        )
    }

    enum TaskTab: String, CaseIterable {
        case activity = "Activity"
        case prompt = "Prompt"
    }

    var body: some View {
        VStack(spacing: 0) {
             Text(task?.title ?? "Task")
                .font(.title)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .padding(.top, 20)

            Picker("Tab", selection: $selectedTab) {
                ForEach(TaskTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 12)

            // Content based on selected tab
            switch selectedTab {
            case .activity:
                activityContent
            case .prompt:
                promptContent
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if chatViewModel == nil, let baseURL = session.serverURL {
                let client = APIClient(
                    baseURL: baseURL,
                    deviceTokenProvider: { session.deviceToken },
                    userTokenProvider: { session.userToken }
                )
                let dataSource = AgentChatDataSource(context: .task(id: taskId), client: client)
                chatViewModel = ChatViewModel(session: session, dataSource: dataSource)
            }
        }
        .task { await load() }
        .alert(item: errorBinding) { w in
            Alert(title: Text("Error"), message: Text(w.message), dismissButton: .default(Text("OK")))
        }
    }

    @ViewBuilder
    private var activityContent: some View {
        if let vm = chatViewModel {
            ChatView(
                viewModel: vm,
                showConversationHeaders: false
            )
            .environment(session)
            .environment(navigationVM)
        } else {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var promptContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let instructions = task?.instructions, !instructions.isEmpty {
                    Text(instructions)
                        .font(.body)
                        .foregroundStyle(Color.foreground["000"])
                } else {
                    Text("No prompt specified")
                        .font(.body)
                        .foregroundStyle(Color.foreground["100"])
                        .italic()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        guard let base = session.serverURL else { return }
        let client = APIClient(baseURL: base, deviceTokenProvider: { self.session.deviceToken }, userTokenProvider: { self.session.userToken })
        do {
            let res = try await client.getTask(id: taskId)
            self.task = AgentTaskModel.from(resource: res)
        } catch {
            self.error = "Failed to load task"
        }
    }
}

private struct LocalizedErrorWrapper: Identifiable { let id = UUID(); let message: String }
