import SwiftUI

@main struct KanbanApp: App {
    var body: some Scene {
        Window("", id: "main") {
            ContentView()
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .frame(minWidth: 760, minHeight: 440)
                .toolbar(removing: .title)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 700)
    }
}
