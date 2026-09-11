import SwiftUI

/// 无文档时的引导页。
struct EmptyStateView: View {
    @Environment(WorkspaceViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tertiary)
            Text("把 Markdown 文件拖到这里")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("或按 ⌘O 打开文件 / 文件夹")
                .font(.callout)
                .foregroundStyle(.tertiary)
            HStack(spacing: 10) {
                Button("打开文件…") { vm.showOpenPanel() }
                    .keyboardShortcut(.defaultAction)
                Button("打开文件夹…") { vm.showOpenFolderPanel() }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
