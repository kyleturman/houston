import SwiftUI

struct LoadingOverlay: View {
    let message: String
    @State private var isVisible = false
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            // Loading card
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color.foreground["000"]))
                    .scaleEffect(1.5)
                
                Text(message)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(Color.foreground["000"])
                    .multilineTextAlignment(.center)
            }
            .frame(width: 200, height: 180)
            .background(Color.background["100"])
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
            .scaleEffect(isVisible ? 1.0 : 0.8)
            .opacity(isVisible ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
    }
}
