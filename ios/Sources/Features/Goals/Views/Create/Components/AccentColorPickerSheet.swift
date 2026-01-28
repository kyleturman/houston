import SwiftUI

struct AccentColorPickerSheet: View {
    @Binding var selectedColor: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) var themeManager
    
    @State private var selectedTab: PickerTab = .defaults
    @State private var customHex: String = ""
    
    enum PickerTab: String, CaseIterable {
        case defaults = "Defaults"
        case custom = "Custom"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented Control
                Picker("Color Type", selection: $selectedTab) {
                    ForEach(PickerTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Content based on selected tab
                switch selectedTab {
                case .defaults:
                    defaultColorsView
                case .custom:
                    customColorView
                }
                
                Spacer()
            }
            .navigationTitle("Accent Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            setupInitialState()
        }
    }
    
    private var defaultColorsView: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                ForEach(Array(themeManager.availableAccentColors.keys.sorted()), id: \.self) { colorName in
                    let colorHex = themeManager.availableAccentColors[colorName] ?? ""
                    let isSelected = selectedColor == colorName || selectedColor == colorHex
                    
                    Button {
                        selectedColor = colorName
                        dismiss()
                    } label: {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(ColorHelpers.color(from: colorHex) ?? Color.accent())
                            .frame(width: 48, height: 48)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSelected ? Color.accent() : Color.clear, lineWidth: 3)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.border["000"], lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
        }
    }
    
    private var customColorView: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                TextField("Enter hex color (e.g., #FF5733)", text: $customHex)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                // Preview square
                RoundedRectangle(cornerRadius: 12)
                    .fill(ColorHelpers.color(from: customHex) ?? Color.accent())
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.border["000"], lineWidth: 1)
                    )
            }
            .padding(.horizontal)
            
            Button {
                if !customHex.isEmpty && ColorHelpers.color(from: customHex) != nil {
                    selectedColor = customHex
                    dismiss()
                }
            } label: {
                Text("Save")
                    .font(.headline)
                    .foregroundColor(Color.background["000"])
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accent())
                    .cornerRadius(12)
            }
            .disabled(customHex.isEmpty || ColorHelpers.color(from: customHex) == nil)
            .padding(.horizontal)
            
            Spacer()
        }
        .padding(.top)
    }
    
    private func setupInitialState() {
        guard let currentColor = selectedColor else { return }
        
        // Check if current color is in defaults
        let availableColors = themeManager.availableAccentColors
        if availableColors.keys.contains(currentColor) || availableColors.values.contains(currentColor) {
            selectedTab = .defaults
        } else {
            selectedTab = .custom
            customHex = currentColor
        }
    }
}
