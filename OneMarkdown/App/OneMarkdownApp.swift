import SwiftUI

@main
struct OneMarkdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel = WorkspaceViewModel()

    var body: some Scene {
        Window("OneMarkdown", id: "main") {
            MainWindowView()
                .environment(viewModel)
        }
        .defaultSize(width: 1180, height: 800)
        .commands {
            AppCommands(viewModel: viewModel)
        }
    }
}
