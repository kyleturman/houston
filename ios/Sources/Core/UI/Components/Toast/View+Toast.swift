import SwiftUI

// MARK: - View Extension for Toast Container

extension View {
    /// Add toast container overlay to view hierarchy
    func withToastContainer() -> some View {
        self.overlay(alignment: .top) {
            ToastContainerView()
        }
    }
}
