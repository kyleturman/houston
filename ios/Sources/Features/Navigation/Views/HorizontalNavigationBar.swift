import SwiftUI

struct HorizontalNavigationBar: View {
    var navigationVM: NavigationViewModel
    
    
    var body: some View {
        HStack(spacing: 0) {
            // Scrollable navigation items
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: -6) {
                        ForEach(navigationVM.navigationItems, id: \.uniqueId) { item in
                            NavigationTabButton(
                                item: item,
                                isSelected: navigationVM.selectedItem == item,
                                action: {
                                    navigationVM.selectItem(item)
                                }
                            )
                            .id(item.uniqueId)
                        }
                    }
                }
                .onChange(of: navigationVM.selectedItem) { _, newItem in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newItem.uniqueId, anchor: .leading)
                    }
                }
                .id(navigationVM.goalsVM.goals.map(\.id).joined())
                .padding(.horizontal, 8)
            }
            
            // Menu button
            IconButton(
                iconName: "line.3.horizontal",
                action: {
                    navigationVM.toggleSideMenu()
                }
            )
            .padding(.trailing, 16)
        }
        .background(navigationVM.showingSideMenu ? Color.clear : Color.background["000"])
    }
}

struct NavigationTabButton: View {
    let item: NavigationItem
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                // Show home icon for home tab
                if case .home = item {
                    Image(systemName: "house.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? Color.background["000"] : Color.foreground["300"])
                }
                
                Text(item.title)
                    .bodyLarge()
                    .foregroundColor(isSelected ? Color.background["000"] : Color.foreground["300"])
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? (accentColorForItem(item) ?? Color.foreground["000"]) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.leading, 6)
        .padding(.trailing, 5)
        .padding(.vertical, 8)
    }
    
    @MainActor
    private func accentColorForItem(_ item: NavigationItem) -> Color? {
        switch item {
        case .home:
            return nil
        case .goal(let goal):
            return Color.accent(goal)
        case .history:
            return nil
        }
    }
}