import AppKit
import StampCore
import SwiftUI

/// 模板库：从工坊窗口滑出的面板，宽 920。印章都按实际大小显示，太长的缩小并标注。
struct TemplateLibraryView: View {
    @EnvironmentObject var store: StampStore
    @Environment(\.dismiss) private var dismiss
    @State private var category: StampTemplates.Category?
    @State private var query = ""
    @FocusState private var searching: Bool

    private var groups: [(StampTemplates.Category, [StampTemplates.Template])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return StampTemplates.Category.allCases.compactMap { c in
            guard category == nil || category == c else { return nil }
            let items = StampTemplates.templates(in: c).filter { t in
                q.isEmpty || [t.design.name, t.blurb, L(t.design.name), L(t.blurb)].contains { $0.lowercased().contains(q) }
                    || c.label.contains(q) || t.design.statement.bodyLines.joined().lowercased().contains(q)
            }
            return items.isEmpty ? nil : (c, items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("从模板开始")).font(Theme.round(17)).foregroundStyle(Theme.ink)
                    Text(L("%ld 个模板，挑一个开始；字、颜色、大小之后都能改", StampTemplates.library.count))
                        .font(Theme.body(12)).foregroundStyle(Theme.ink2)
                }
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink2)
                    TextField(L("搜：签证、复印、圆章…"), text: $query)
                        .textFieldStyle(.plain)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.ink)
                        .focused($searching)
                }
                .padding(.horizontal, 12)
                .frame(width: 200, height: 32)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous).fill(Color.white))
                .insetStroke(searching ? Theme.coralLine : Theme.line, width: searching ? 2 : 1, radius: Theme.Radius.field)
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.ink2)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Theme.chip))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(L("关闭"))
            }

            HStack(spacing: 6) {
                CategoryChip(title: L("全部"), selected: category == nil, height: 28, fontSize: 12,
                             count: StampTemplates.library.count) { category = nil }
                ForEach(StampTemplates.Category.allCases) { c in
                    CategoryChip(title: c.label, selected: category == c, height: 28, fontSize: 12,
                                 count: StampTemplates.templates(in: c).count) { category = c }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(groups, id: \.0) { c, items in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(c.label).font(Theme.round(15)).foregroundStyle(Theme.ink)
                                Text(c.blurb).font(Theme.body(12)).foregroundStyle(Theme.ink2)
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                                ForEach(items) { t in
                                    LibraryCard(template: t) { dismiss() }
                                }
                            }
                        }
                    }
                    if groups.isEmpty {
                        VStack(spacing: 10) {
                            Mascot(mood: .troubled, size: 56)
                            Text(L("没找到「%@」相关的模板", query)).font(Theme.body(13)).foregroundStyle(Theme.ink2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    }
                    Text(L("不提供仿公章样式（红圆 + 五角星 + 单位名）——这些章只用来声明你自己的复印件用途。"))
                        .font(Theme.body(11)).foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                }
                .padding(4)
            }
            .padding(-4)
        }
        .padding(EdgeInsets(top: 20, leading: 24, bottom: 24, trailing: 24))
        .frame(width: 920, height: 640)
        .background(Theme.paper)
    }
}

private struct LibraryCard: View {
    @EnvironmentObject var store: StampStore
    let template: StampTemplates.Template
    let done: () -> Void
    @State private var hovering = false

    var body: some View {
        let design = template.design
        let text = design.statement.stampText(date: Clock.now(), stampID: store.nextStampID)
        let width = StampRenderer.boundingSize(text, design: design).width
        let scale = min(1, 176 / max(width, 1))
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.well)
                StampAtScale(design: design, scale: scale, stampID: store.nextStampID)
                if scale < 1 {
                    Text(L("缩小到 %ld%%", Int((scale * 100).rounded())))
                        .font(Theme.body(10)).foregroundStyle(Theme.ink3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(EdgeInsets(top: 0, leading: 8, bottom: 6, trailing: 0))
                }
                if hovering {
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.well.opacity(0.82))
                    HStack(spacing: 6) {
                        Button(L("刻一枚")) {
                            store.addDesign(from: design)
                            done()
                        }
                        .buttonStyle(.mochi(.primary, height: 28))
                        Button(L("只换样子")) {
                            store.applyLook(of: design)
                            done()
                        }
                        .buttonStyle(.mochi(.outline, height: 28, padding: 10))
                    }
                }
            }
            .frame(height: 92)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L(design.name)).font(Theme.body(13, .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(design.sizeLabel).font(Theme.body(11)).foregroundStyle(Theme.ink3).lineLimit(1)
                }
                Text(L(template.blurb)).font(Theme.body(11)).foregroundStyle(Theme.ink2).lineLimit(1)
            }
            .padding(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(hovering ? Theme.coralLine : Theme.line, lineWidth: hovering ? 2 : 1))
        .compositingGroup().shadow(color: .warm(170, 70, 50, hovering ? 0.12 : 0), radius: 8, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
    }
}
