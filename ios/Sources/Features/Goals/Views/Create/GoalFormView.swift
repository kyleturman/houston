import SwiftUI

struct GoalFormView: View {
    let goalData: GoalDataPreview
    var onCancel: () -> Void
    var onConfirm: (_ title: String, _ description: String, _ agentInstructions: String, _ learnings: [String], _ enabledMcpServers: [String], _ accentColor: String?) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) var themeManager
    
    @State private var title: String
    @State private var description: String
    @State private var agentInstructions: String
    @State private var learnings: [String]
    @State private var enabledMcpServers: [String]
    @State private var accentColor: String?
    @State private var showingColorPicker = false
    @State private var showAgentInstructions = false
    
    init(goalData: GoalDataPreview, onCancel: @escaping () -> Void, onConfirm: @escaping (_ title: String, _ description: String, _ agentInstructions: String, _ learnings: [String], _ enabledMcpServers: [String], _ accentColor: String?) -> Void) {
        self.goalData = goalData
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        
        _title = State(initialValue: goalData.title)
        _description = State(initialValue: goalData.description)
        _agentInstructions = State(initialValue: goalData.agentInstructions)
        _learnings = State(initialValue: goalData.learnings)
        _enabledMcpServers = State(initialValue: goalData.enabledMcpServers)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Details")) {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                AccentColorPickerButton(selectedColor: $accentColor, showingPicker: $showingColorPicker)
                
                Section(header: Text("Context & Learnings")) {
                    if learnings.isEmpty {
                        Text("No context extracted")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    } else {
                        ForEach(Array(learnings.enumerated()), id: \.offset) { index, learning in
                            HStack {
                                Text(learning)
                                    .font(.footnote)
                                Spacer()
                                Button {
                                    learnings.remove(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(Color.semantic["error"])
                                        .font(.footnote)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
                
                MCPServerSelectionSection(enabledMcpServers: $enabledMcpServers)
                
                AgentInstructionsSection(agentInstructions: $agentInstructions, isExpanded: $showAgentInstructions)                
            }
            .navigationTitle("Review Goal")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onConfirm(title, description, agentInstructions, learnings, enabledMcpServers, accentColor)
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showingColorPicker) {
                AccentColorPickerSheet(selectedColor: $accentColor)
                    .presentationDetents([.medium])
            }
            .onAppear {
                if accentColor == nil {
                    accentColor = themeManager.availableAccentColors.keys.sorted().first
                }
            }
        }
    }
    
}
