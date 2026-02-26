import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                Text("Projects")
                    .font(.title)
                    .foregroundStyle(.secondary)
                    .navigationTitle("Projects")
            }
            .tabItem {
                Label("Projects", systemImage: "house")
            }

            NavigationStack {
                Text("Inventory")
                    .font(.title)
                    .foregroundStyle(.secondary)
                    .navigationTitle("Inventory")
            }
            .tabItem {
                Label("Inventory", systemImage: "shippingbox")
            }

            NavigationStack {
                Text("Search")
                    .font(.title)
                    .foregroundStyle(.secondary)
                    .navigationTitle("Search")
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }

            NavigationStack {
                List {
                    NavigationLink("Firestore Test") {
                        FirestoreTestView()
                    }
                }
                .navigationTitle("Settings")
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .tint(BrandColors.primary)
    }
}

#Preview {
    MainTabView()
}
