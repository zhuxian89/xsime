import SwiftUI
import RimesCore

struct KeyboardAppearanceView: View {
    @State private var value = KeyboardAppearanceConfiguration()
    @State private var theme: StatusSkin = .apple
    @State private var customName: String?
    @State private var error: String?
    private let store = KeyboardAppearanceStore()
    var body: some View {
        List {
            Section {
                Text("熟悉的键位，喜欢的外观").font(.headline)
                Text("宠物和键盘共用一套配色。26 键、9 键和并击一起换肤，并击的键位与间距保持不变。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("标准键盘") {
                Picker("键位布局", selection: Binding(get: { value.layout }, set: { value.layout = $0; useStandard() })) {
                    Text("26 键 · QWERTY").tag(OrdinaryKeyboardLayout.qwerty)
                    Text("9 键 · 全拼").tag(OrdinaryKeyboardLayout.nineKey)
                    Text("正交").tag(OrdinaryKeyboardLayout.orthogonal)
                }.pickerStyle(.segmented).accessibilityIdentifier("keyboardAppearance.layout")
                KeyboardAppearancePreview(layout: value.layout, theme: theme)
                    .padding(.vertical, 8).accessibilityIdentifier("keyboardAppearance.preview")
                Text(value.layout == .nineKey
                    ? "9 键用于全拼：输入字母组、选拼音、分隔音节、选择候选。导入方案须在包内提供配套九键编码，例如万象的 wanxiang_t9；双拼和五笔保持原布局。"
                    : value.layout == .orthogonal
                    ? "正交是双手对称的方格键盘（需启用并击扩展）。全拼和自然码支持并击；其他方案在同一键盘上逐键输入。"
                    : "QWERTY 错行排列，Shift 和删除键位于第三行两侧，空格键更宽。")
                    .font(.caption).foregroundStyle(.secondary)
                if let customName {
                    Text("已应用自定义布局：\(customName)").font(.subheadline)
                    Button("改用上方标准键盘") { useStandard() }
                }
            }
            Section {
                Picker(L("上滑数字和符号", "Swipe symbols"), selection: Binding(get: {
                    value.longPressSwipeSymbols ? (value.directSwipeSymbols ? 2 : 1) : 0
                }, set: { mode in
                    do { try store.saveSwipeSymbols(mode != 0, direct: mode == 2); value = store.load() }
                    catch { self.error = error.localizedDescription }
                })) {
                    Text(L("关闭", "Off")).tag(0)
                    Text(L("长按后上滑", "Hold then swipe")).tag(1)
                    Text(L("直接上滑", "Swipe directly")).tag(2)
                }.accessibilityIdentifier("keyboardAppearance.swipeSymbols")
                Toggle(L("数字九宫格", "Numeric keypad"), isOn: Binding(get: { value.numericNineGrid }, set: { value.numericNineGrid = $0; saveSizing() }))
                    .accessibilityIdentifier("keyboardAppearance.numericNineGrid")
                Stepper(L("竖屏高度", "Portrait height") + " \(value.portraitHeight)%", value: Binding(get: { value.portraitHeight }, set: { value.portraitHeight = $0; saveSizing() }), in: 100...130, step: 5)
                Stepper(L("横屏高度", "Landscape height") + " \(value.landscapeHeight)%", value: Binding(get: { value.landscapeHeight }, set: { value.landscapeHeight = $0; saveSizing() }), in: 100...130, step: 5)
            } header: { Text(L("普通键盘输入", "Standard keyboard input")) } footer: {
                Text(L("上滑后松手输入键角的数字或符号。数字九宫格只改变数字页；高度分别保存，下次打开键盘时生效。并击和自定义布局保持原尺寸。", "Release after swiping up to insert the alternate. The numeric keypad changes only the number page. Heights are saved per orientation and applied when the keyboard opens. Chord and custom layouts keep their dimensions."))
            }
            Section {
                Picker(L("按键样式", "Key style"), selection: Binding(get: { value.keyStyle }, set: { style in
                    do { try store.saveKeyStyle(style); value = store.load() }
                    catch { self.error = error.localizedDescription }
                })) {
                    Text(L("自动", "Auto")).tag(KeyboardKeyStyle.auto)
                    Text(L("扁平", "Flat")).tag(KeyboardKeyStyle.flat)
                    Text(L("经典（灰色功能键）", "Legacy (grey function keys)")).tag(KeyboardKeyStyle.legacy)
                }.accessibilityIdentifier("keyboardAppearance.keyStyle")
            } header: { Text(L("按键样式", "Key style")) } footer: {
                Text(L("部分 App 会以经典样式显示系统键盘：功能键为灰色，按键下方有细阴影。经典样式让键盘与之保持一致；自动目前等同于扁平。仅作用于苹果配色，下次打开键盘时生效。", "Some apps show the system keyboard in its legacy style: grey function keys and a thin shadow under each key. Legacy matches that look. Auto currently draws flat. Applies to the Apple theme and takes effect when the keyboard opens."))
            }
            Section("宠物与键盘配色") {
                Text(theme == .rhino ? "\(ProductBrand.name) 经典 · 象牙白、灰色与橙色" : "当前：\(theme.title)")
                    .font(.subheadline).fontWeight(.medium)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
                    ForEach(StatusSkin.themes) { item in
                        Button { selectTheme(item) } label: {
                            VStack(spacing: 7) {
                                ZStack(alignment: .topTrailing) {
                                    Group {
                                        if item.usesDot {
                                            Circle().fill(Color.secondary.opacity(0.45)).frame(width: 10, height: 10)
                                                .shadow(color: .secondary.opacity(0.4), radius: 5)
                                        }
                                        else { Text(item.glyph) }
                                    }.font(.system(size: 28)).frame(maxWidth: .infinity).frame(height: 34)
                                    if theme == item { Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(Color(uiColor: item.palette.accentText)) }
                                }
                                Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                                HStack(spacing: 4) {
                                    ForEach(0..<3) { index in
                                        let colors = [item.palette.key, item.palette.functional, item.palette.accent]
                                        RoundedRectangle(cornerRadius: 3).fill(Color(uiColor: colors[index])).frame(height: 10)
                                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.primary.opacity(0.1), lineWidth: 0.5))
                                    }
                                }
                            }
                            .foregroundStyle(Color(uiColor: item.palette.ink))
                            .padding(9).background(Color(uiColor: item.palette.background))
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                            .overlay(RoundedRectangle(cornerRadius: 11).stroke(theme == item ? Color(uiColor: item.palette.accent) : .clear, lineWidth: 2))
                        }.buttonStyle(.plain)
                            .accessibilityLabel(item.title).accessibilityAddTraits(theme == item ? .isSelected : [])
                            .accessibilityIdentifier("keyboardAppearance.theme.\(item.rawValue)")
                    }
                }.padding(.vertical, 4)
                Text("轻点键盘里的宠物，也能轮换配色。每套主题都有深色模式和按压反馈。")
                    .font(.caption).foregroundStyle(.secondary)
                NavigationLink { StatusSkinsView() } label: { Label("管理宠物轮换", systemImage: "arrow.triangle.2.circlepath") }
            }
            Section {
                NavigationLink { CustomKeyboardLayoutsView() } label: {
                    Label("自由排列与布局导入", systemImage: "square.grid.3x3")
                }
            } footer: { Text("修改在下一次打开键盘时生效。标准布局与自定义布局可以随时切换，保存的草稿会保留。") }
        }
        .navigationTitle("键盘布局与换肤")
        .onAppear {
            value = store.load(); customName = CustomLayoutStore().load().active?.name
            let saved = KeyboardThemeStore().load()
            theme = saved.revision == nil && value.skin == .rimes ? .rhino : saved.selection
        }
        .alert("无法保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func saveSizing() {
        do { try store.saveLayoutOptions(portrait: value.portraitHeight, landscape: value.landscapeHeight, numericNineGrid: value.numericNineGrid); value = store.load() }
        catch { value = store.load(); self.error = error.localizedDescription }
    }
    private func selectTheme(_ next: StatusSkin) {
        do { try KeyboardThemeStore().save(next); theme = next }
        catch { self.error = error.localizedDescription }
    }
    private func useStandard() {
        do { try CustomLayoutStore().apply(nil); customName = nil; try store.save(value) }
        catch { self.error = error.localizedDescription }
    }
}

private struct KeyboardAppearancePreview: View {
    var layout: OrdinaryKeyboardLayout
    var theme: StatusSkin
    private var skin: KeyboardSkin { theme.keyboardStyle }
    var body: some View {
        VStack(spacing: 7) {
            HStack { Text("你好"); Spacer(); Text("世界"); Spacer(); Text("输入"); Image(systemName: "chevron.down") }
                .font(.system(size: 15)).padding(.horizontal, 6).padding(.bottom, 4)
            GeometryReader { proxy in
                let geometry = StandardKeyboardGeometry.make(width: 393, mode: layout == .nineKey ? .nineKey : .qwerty, landscape: false)
                let scale = proxy.size.width / 393
                ZStack(alignment: .topLeading) {
                    ForEach(Array(geometry.keys.enumerated()), id: \.offset) { _, key in
                        cap(key.label, functional: false)
                            .frame(width: key.frame.width * scale, height: key.frame.height * scale)
                            .position(x: key.frame.midX * scale, y: key.frame.midY * scale)
                    }
                    ForEach(geometry.controls.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { action in
                        if let frame = geometry.controls[action] {
                            Group {
                                if action == .punctuation {
                                    VStack(spacing: 0) {
                                        ForEach(["，", "。", "？", "！"], id: \.self) { mark in
                                            Text(mark).frame(maxWidth: .infinity, maxHeight: .infinity)
                                        }
                                    }
                                    .background(Color(uiColor: theme.palette.functional))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                } else {
                                    cap(label(action), functional: layout == .qwerty && action != .space)
                                }
                            }
                                .frame(width: frame.width * scale, height: frame.height * scale)
                                .position(x: frame.midX * scale, y: frame.midY * scale)
                        }
                    }
                }
            }.aspectRatio(393.0 / 206.0, contentMode: .fit)
        }
        .padding(8)
        .foregroundStyle(Color(uiColor: theme.palette.ink))
        .background(Color(uiColor: theme.palette.background))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(layout == .qwerty ? "26 键布局预览" : "全拼 9 键布局预览")
    }
    private func label(_ action: StandardKeyControl) -> String {
        switch action {
        case .space: return layout == .nineKey ? "选定" : "空格"
        case .backspace: return "⌫"
        case .enter: return layout == .nineKey ? "确认" : "换行"
        case .shift: return "⇧"
        case .numbers: return "123"
        case .language: return layout == .nineKey ? "ABC" : "英"
        case .emoji: return "☺"
        case .buffer: return "Buffer"
        case .symbols: return "#+="
        case .separator: return "分隔"
        case .spelling: return "选拼音"
        case .punctuation: return "，。?!"
        }
    }
    private func cap(_ title: String, functional: Bool) -> some View {
        Text(title).font(.system(size: 16, weight: skin == .system ? .regular : .medium, design: skin == .system ? .default : .monospaced))
            .minimumScaleFactor(0.6).lineLimit(1).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: functional ? theme.palette.functional : theme.palette.key))
            .clipShape(RoundedRectangle(cornerRadius: skin == .system ? 5 : 6))
            .shadow(color: .black.opacity(0.22), radius: skin == .system ? 0 : 1, y: 1)
    }
}
