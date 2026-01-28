import SwiftUI

struct AgentInstructionsSection: View {
    @Binding var agentInstructions: String
    @Binding var isExpanded: Bool
    
    var body: some View {
        Section {
            DisclosureGroup("Agent Instructions", isExpanded: $isExpanded) {
                TextEditor(text: $agentInstructions)
                    .frame(minHeight: 100)
                    .font(.footnote)
            }
        }
    }
}
