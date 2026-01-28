import SwiftUI

struct NotesView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(StateManager.self) private var stateManager
    @Environment(NavigationViewModel.self) var navigationVM
    @State private var viewModel: NotesViewModel?

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Color.foreground["300"])
                        .font(.system(size: 16))

                    TextField("Search notes...", text: Binding(
                        get: { viewModel?.searchText ?? "" },
                        set: { viewModel?.updateSearch($0) }
                    ))
                    .textFieldStyle(.plain)
                    .foregroundColor(Color.foreground["000"])

                    if !(viewModel?.searchText.isEmpty ?? true) {
                        Button(action: {
                            viewModel?.updateSearch("")
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color.foreground["300"])
                                .font(.system(size: 16))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.background["100"])
                .cornerRadius(10)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            // Segmented control for source filter
            Picker("Source", selection: Binding(
                get: { viewModel?.selectedSource ?? .all },
                set: { viewModel?.updateSourceFilter($0) }
            )) {
                ForEach(NotesViewModel.NoteSourceFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)

            // Notes list
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel?.loading ?? true {
                        ProgressView()
                            .padding()
                    } else if let errorMessage = viewModel?.errorMessage {
                        VStack(spacing: 12) {
                            Text("Error loading notes")
                                .font(.headline)
                                .foregroundColor(Color.foreground["000"])

                            Text(errorMessage)
                                .font(.body)
                                .foregroundColor(Color.foreground["300"])
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    } else if viewModel?.filteredNotes.isEmpty ?? true {
                        VStack(spacing: 12) {
                            Text("No notes found")
                                .font(.headline)
                                .foregroundColor(Color.foreground["000"])

                            if !(viewModel?.searchText.isEmpty ?? true) {
                                Text("Try adjusting your search or filter")
                                    .font(.body)
                                    .foregroundColor(Color.foreground["300"])
                                    .multilineTextAlignment(.center)
                            } else {
                                Text("Create your first note using the + button")
                                    .font(.body)
                                    .foregroundColor(Color.foreground["300"])
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding()
                        .padding(.top, 40)
                    } else {
                        ForEach(viewModel?.filteredNotes ?? []) { note in
                            Button(action: {
                                navigationVM.openNote(id: note.id)
                            }) {
                                NoteCard(
                                    note: note,
                                    accentColor: Color.foreground["500"],
                                    goal: findGoal(for: note)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task {
                                        try? await viewModel?.deleteNote(note)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
        }
        .background(Color.background["000"])
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    navigationVM.openNoteCompose(goal: nil)
                }) {
                    Image(systemName: "plus")
                        .foregroundColor(Color.foreground["000"])
                }
            }
        }
        .refreshable {
            await viewModel?.refreshFromUI()
        }
        .onAppear {
            if viewModel == nil {
                viewModel = NotesViewModel(session: sessionManager)
                Task {
                    await viewModel?.load()
                }
            }
        }
        .onReceive(stateManager.dataRefreshNeededPublisher) { _ in
            Task {
                await viewModel?.load()
            }
        }
    }

    /// Find goal for a note (if it has a goalId)
    private func findGoal(for note: Note) -> Goal? {
        guard let goalId = note.goalId else { return nil }
        return navigationVM.goalsVM.goals.first { $0.id == goalId }
    }
}

#Preview {
    NavigationStack {
        NotesView()
    }
}
