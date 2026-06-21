import SwiftUI

struct LedgerCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            #if os(macOS)
            NewWindowButton()
            Divider()
            #endif

            Button("New Project") {
                NotificationCenter.default.post(name: .createProject, object: nil)
            }
            .keyboardShortcut("p", modifiers: .command)

            Button("New Transaction") {
                NotificationCenter.default.post(name: .createTransaction, object: nil)
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("New Item") {
                NotificationCenter.default.post(name: .createItem, object: nil)
            }
            .keyboardShortcut("i", modifiers: .command)

            Button("New Space") {
                NotificationCenter.default.post(name: .createSpace, object: nil)
            }
            .keyboardShortcut("s", modifiers: .command)
        }

        // Suppress default Print menu item so Cmd+P is free for New Project
        CommandGroup(replacing: .printItem) { }

        CommandGroup(replacing: .textEditing) {
            Button("Find on Page") {
                NotificationCenter.default.post(name: .toggleFindOverlay, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings") {
                NotificationCenter.default.post(name: .showSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        #if os(macOS)
        CommandGroup(after: .appInfo) {
            Button("Check for Updates...") {
                SparkleUpdateController.shared.checkForUpdates()
            }
        }
        #endif
    }
}

#if os(macOS)
private struct NewWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Window") {
            openWindow(id: "main")
        }
        .keyboardShortcut("n", modifiers: .command)
    }
}
#endif
