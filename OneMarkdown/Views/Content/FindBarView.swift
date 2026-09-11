import SwiftUI

/// 正文查找条：输入即查找，⏎ 下一个，⇧⏎ 上一个，Esc 关闭。
struct FindBarView: View {
    @Environment(WorkspaceViewModel.self) private var vm
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var vm = vm
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("查找", text: $vm.findQuery)
                .textFieldStyle(.plain)
                .frame(width: 180)
                .focused($isFocused)
                .onSubmit { vm.findNext() }
                .onExitCommand { vm.closeFind() }
            Text(vm.findTotal == 0 ? (vm.findQuery.isEmpty ? "" : "无结果") : "\(vm.findCurrent)/\(vm.findTotal)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)
            Button { vm.findPrevious() } label: { Image(systemName: "chevron.up") }
                .disabled(vm.findTotal == 0)
                .help("上一个 (⌘⇧G)")
            Button { vm.findNext() } label: { Image(systemName: "chevron.down") }
                .disabled(vm.findTotal == 0)
                .help("下一个 (⌘G)")
            Button { vm.closeFind() } label: { Image(systemName: "xmark") }
                .help("关闭 (Esc)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .onAppear { isFocused = true }
    }
}
