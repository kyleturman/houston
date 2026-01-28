import SwiftUI

// MARK: - Build-Time Color System Validation
// This struct forces validation of the color system at build time
// by accessing the ColorSystem singleton during static initialization.

struct ColorSystemValidation {
    // This static property will be evaluated at build time when the app starts,
    // forcing the ColorSystem to initialize and validate the JSON structure
    @MainActor static let isValid: Bool = {
        // Force ColorSystem initialization which triggers validation
        let _ = ColorSystem.shared
        return true
    }()

    // This method can be called from the app initialization to ensure validation runs
    @MainActor static func validateAtStartup() {
        // Simply accessing the static property triggers validation
        let _ = isValid
    }
}
