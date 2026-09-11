import SwiftUI

/// 大纲：按标题层级缩进，点击跳转。
struct OutlineView: View {
    @Environment(WorkspaceViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        Group {
            if !vm.hasDocument {
                placeholder("打开文档后显示大纲")
            } else if vm.outline.isEmpty {
                placeholder("此文档没有标题")
            } else {
                let minLevel = vm.outline.map(\.level).min() ?? 1
                List(vm.outline, selection: $vm.selectedOutlineID) { item in
                    Text(item.text.isEmpty ? "（无标题）" : item.text)
                        .font(.system(size: item.level <= minLevel ? 13 : 12, weight: item.level <= minLevel ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, CGFloat(item.level - minLevel) * 14)
                        .help(item.text)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // 允许重复点击同一条目再次跳转
                            vm.selectedOutlineID = item.id
                            vm.scrollTo(item)
                        }
                }
                .listStyle(.sidebar)
            }
        }
        .onChange(of: vm.selectedOutlineID) { _, id in
            if let id, let item = vm.outline.first(where: { $0.id == id }) {
                vm.scrollTo(item)
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
