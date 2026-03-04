import SwiftUI

struct ListStateControls: View {
    @Binding var searchText: String
    var isSearchVisible: Bool
    var placeholder: String = "Search..."

    var body: some View {
        if isSearchVisible {
            SearchField(text: $searchText, placeholder: placeholder)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview("Visible Empty") {
    VStack {
        ListStateControls(searchText: .constant(""), isSearchVisible: true)
            .padding()
        Spacer()
    }
}

#Preview("Visible with Text") {
    VStack {
        ListStateControls(searchText: .constant("Pillow"), isSearchVisible: true)
            .padding()
        Spacer()
    }
}

#Preview("Hidden") {
    VStack {
        ListStateControls(searchText: .constant(""), isSearchVisible: false)
            .padding()
        Spacer()
    }
}
