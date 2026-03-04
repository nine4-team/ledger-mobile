import SwiftUI

struct LedgerCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project") {
                NotificationCenter.default.post(name: .createProject, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Transaction") {
                NotificationCenter.default.post(name: .createTransaction, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("New Item") {
                NotificationCenter.default.post(name: .createItem, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Button("New Space") {
                NotificationCenter.default.post(name: .createSpace, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .option, .shift])
        }

        CommandGroup(replacing: .textEditing) {
            Button("Search") {
                NotificationCenter.default.post(name: .focusSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings") {
                NotificationCenter.default.post(name: .showSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
