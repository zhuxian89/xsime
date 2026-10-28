import UIKit
#if KEYBOARD_LAYOUT_TESTS
@testable import RIMES
#endif
import RimesCore

/// Common marks stay beside the nine-key letters. Drag to reveal the rest;
/// UIScrollView cancels button tracking, so a scroll never types punctuation.
final class NineKeyPunctuationRail: UIScrollView {
    static let marks = ["，", "。", "？", "！", "、", "：", "；", "……", "/", "“", "”", "（", "）"]
    var onSelect: ((String) -> Void)?
    private(set) var buttons: [UIButton] = []
    var theme: StatusSkin = .rhino { didSet { updateTheme() } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "keyboard.nineKey.punctuation"
        layer.cornerRadius = 6; layer.cornerCurve = .continuous
        showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = true
        alwaysBounceVertical = true; delaysContentTouches = false
        for mark in Self.marks {
            let button = UIButton(type: .system)
            button.setTitle(mark, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 22)
            button.accessibilityLabel = mark
            button.accessibilityTraits.insert(.keyboardKey)
            button.accessibilityIdentifier = "keyboard.nineKey.mark.\(mark)"
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(mark) }, for: .touchUpInside)
            addSubview(button); buttons.append(button)
        }
        updateTheme()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func touchesShouldCancel(in view: UIView) -> Bool { true }
    private func updateTheme() {
        backgroundColor = theme.palette.functional
        for button in buttons { button.setTitleColor(theme.palette.ink, for: .normal) }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let rowHeight = max(32, bounds.height / 4)
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: 0, y: CGFloat(index) * rowHeight, width: bounds.width, height: rowHeight)
        }
        let size = CGSize(width: bounds.width, height: rowHeight * CGFloat(buttons.count))
        if contentSize != size { contentSize = size }
    }
}
