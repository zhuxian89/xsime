import UIKit
import RimesCore

/// One line that never wraps; drag horizontally to read the rest. Optional
/// block backgrounds and an overlay caret never change the text's own layout.
final class SingleLineTextView: UIScrollView, UIEditMenuInteractionDelegate {
    /// Resolve the action when the menu opens, without reading the clipboard or
    /// taking first responder away from the host app's text field.
    var makePasteAction: (() -> UIAction?)?
    private lazy var editMenu = UIEditMenuInteraction(delegate: self)
    private var pasteAction: UIAction?
    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        presentPasteMenu(at: gesture.location(in: self))
    }
    func presentPasteMenu(at point: CGPoint) {
        guard role == .input,
              let action = makePasteAction?() else { return }
        pasteAction = action
        editMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
    }
    func dismissPasteMenu() { editMenu.dismissMenu(); pasteAction = nil }
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard role == .input, let pasteAction else { return nil }
        return UIMenu(children: [pasteAction])
    }
    private let label = UILabel()
    private let caret = UIView()
    /// Holds the text, caret and block backgrounds, clipped to a rounded area just inside the
    /// frame so nothing ever covers the border or its corners, even mid-scroll.
    private let canvas = UIView(), canvasClip = CAShapeLayer()
    private static let clipInset: CGFloat = 2.5
    private let placeholderLabel = UILabel()
    /// Space for a stationary action drawn over the trailing edge of this line.
    var trailingAccessoryWidth: CGFloat = 0 { didSet { if oldValue != trailingAccessoryWidth { followedSignature = ""; setNeedsLayout() } } }
    /// Hint shown while the line is empty; never part of the text.
    var placeholder = "" { didSet { if placeholder != oldValue { placeholderLabel.text = placeholder; setNeedsLayout() } } }
    private var blockViews: [UIView] = []
    private var plain: String?
    private var focus: NSRange?
    private var followedSignature = ""
    private static let inset: CGFloat = 8
    /// Input accepts the typed text (outlined, with caret); output only displays.
    enum Role { case input, output }
    var role = Role.input { didSet { applyRole(); if let plain { text = plain } } }
    var font: UIFont = .systemFont(ofSize: 15) { didSet { if let plain, oldValue != font { text = plain } } }
    /// Three softly pulsing dots while a reply is on its way and nothing is readable yet.
    var waiting = false { didSet { if waiting != oldValue { updateWaiting() } } }
    private let dots = CAReplicatorLayer(), dot = CALayer()
    private func updateWaiting() {
        dots.isHidden = !waiting
        dot.removeAllAnimations()
        guard waiting else { return }
        accessibilityValue = L("等待回应", "Waiting for a reply")
        guard !UIAccessibility.isReduceMotionEnabled else { dot.opacity = 0.6; return }
        let pulse = CABasicAnimation(keyPath: "opacity"); pulse.fromValue = 0.2; pulse.toValue = 1
        let grow = CABasicAnimation(keyPath: "transform.scale"); grow.fromValue = 0.7; grow.toValue = 1.1
        let group = CAAnimationGroup(); group.animations = [pulse, grow]; group.duration = 0.5
        group.autoreverses = true; group.repeatCount = .infinity; group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.add(group, forKey: "pulse")
    }
    /// Shows the text as the model's thinking: dimmer, and read out as thinking.
    var thinking = false { didSet { if oldValue != thinking, let plain { text = plain } } }
    var text: String {
        get { label.attributedText?.string ?? "" }
        set {
            let color: UIColor = thinking ? .tertiaryLabel : role == .input ? .label : .secondaryLabel
            let value = NSMutableAttributedString(string: newValue, attributes: [.font: font, .foregroundColor: color])
            BufferBlockStyle.apply(to: value, ranges: blockRanges)
            label.attributedText = Self.oneLine(value); plain = newValue; setNeedsLayout()
        }
    }
    var attributedText: NSAttributedString? {
        get { label.attributedText }
        set { plain = nil; label.attributedText = newValue.map(Self.oneLine); setNeedsLayout() }
    }
    /// A line break would end the label's only line and break block measurement, so each
    /// one is shown as "↵" (a CR as a zero-width space). UTF-16 length is unchanged, so
    /// block and caret ranges still line up.
    private static func oneLine(_ text: NSAttributedString) -> NSAttributedString {
        let string = text.string as NSString
        guard string.rangeOfCharacter(from: .newlines).location != NSNotFound else { return text }
        let value = NSMutableAttributedString(attributedString: text)
        for index in 0..<string.length {
            switch string.character(at: index) {
            case 0x0D: value.replaceCharacters(in: NSRange(location: index, length: 1), with: "\u{200B}")
            case 0x0A, 0x0B, 0x0C, 0x85, 0x2028, 0x2029: value.replaceCharacters(in: NSRange(location: index, length: 1), with: "↵")
            default: break
            }
        }
        return value
    }
    /// Displayed UTF-16 block ranges and the emphasised block; set before the text.
    private(set) var blockRanges: [NSRange] = []
    private(set) var activeBlock: Int?
    func setBlocks(_ ranges: [NSRange], active: Int?) {
        let changed = ranges != blockRanges
        blockRanges = ranges; activeBlock = active
        // The gaps between blocks live in the text itself, so re-apply them even when the
        // characters are unchanged (e.g. a streamed reply settling into blocks).
        // Only when the new blocks fit the current text; otherwise the caller sets new text next.
        if changed, let plain, ranges.allSatisfy({ NSMaxRange($0) <= (plain as NSString).length }) { text = plain } else { setNeedsLayout() }
    }
    /// Tapping a block reports its index; a drag still scrolls. Nil disables block taps.
    var onTapBlock: ((Int) -> Void)? { didSet { updateTap() } }
    /// A tap where there are no blocks.
    var onTapBackground: (() -> Void)? { didSet { updateTap() } }
    private func updateTap() {
        let wanted = onTapBlock != nil || onTapBackground != nil
        guard wanted != (blockTap != nil) else { return }
        if wanted { let tap = UITapGestureRecognizer(target: self, action: #selector(tappedBlock(_:))); addGestureRecognizer(tap); blockTap = tap }
        else { blockTap.map(removeGestureRecognizer); blockTap = nil }
    }
    private var blockTap: UITapGestureRecognizer?
    @objc private func tappedBlock(_ tap: UITapGestureRecognizer) {
        let x = tap.location(in: self).x // content coordinates, like blockFrames
        if let index = blockIndex(at: x) { onTapBlock?(index) } else { onTapBackground?() }
    }

    /// The block under `x`, or the nearest one when the tap lands in a gap between blocks.
    func blockIndex(at x: CGFloat) -> Int? {
        guard !blockFrames.isEmpty else { return nil }
        if let hit = blockFrames.firstIndex(where: { $0.minX <= x && x <= $0.maxX }) { return hit }
        return blockFrames.indices.min { abs(blockFrames[$0].midX - x) < abs(blockFrames[$1].midX - x) }
    }
    /// UTF-16 caret position, shown only for the input role.
    var caretLocation: Int? { didSet {
        guard caretLocation != oldValue else { return }
        restartBlink(); setNeedsLayout()
    } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        addInteraction(editMenu)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.45
        addGestureRecognizer(hold)
        label.numberOfLines = 1; label.lineBreakMode = .byClipping
        canvas.isUserInteractionEnabled = false; canvas.layer.mask = canvasClip
        addSubview(canvas)
        canvas.addSubview(label)
        placeholderLabel.textColor = .placeholderText; placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.adjustsFontSizeToFitWidth = true; placeholderLabel.minimumScaleFactor = 0.7
        canvas.addSubview(placeholderLabel)
        caret.backgroundColor = tintColor; caret.layer.cornerRadius = 1; caret.isUserInteractionEnabled = false
        canvas.addSubview(caret)
        dot.backgroundColor = (tintColor ?? .systemBlue).cgColor; dot.opacity = 0.2
        dots.addSublayer(dot); dots.instanceCount = 3; dots.instanceDelay = 0.16
        dots.isHidden = true; layer.addSublayer(dots)
        showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
        alwaysBounceHorizontal = false; alwaysBounceVertical = false; bounces = true
        hideEdgeEffects()
        layer.cornerRadius = 7; layer.cornerCurve = .continuous
        applyRole()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SingleLineTextView, _: UITraitCollection) in view.applyRole(); view.setNeedsLayout() }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func tintColorDidChange() { super.tintColorDidChange(); applyRole(); setNeedsLayout() }
    private func applyRole() {
        caret.backgroundColor = tintColor
        dot.backgroundColor = (tintColor ?? .systemBlue).resolvedColor(with: traitCollection).cgColor
        switch role {
        case .input:
            backgroundColor = .systemBackground
            layer.borderWidth = 1; layer.borderColor = (tintColor ?? .systemBlue).withAlphaComponent(0.7).resolvedColor(with: traitCollection).cgColor
            accessibilityTraits = [.updatesFrequently]
        case .output:
            backgroundColor = .tertiarySystemFill
            layer.borderWidth = 0
            accessibilityTraits = [.staticText, .notEnabled]
        }
    }
    private func restartBlink() {
        caret.layer.removeAnimation(forKey: "blink")
        guard caretLocation != nil else { return }
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 1, 0, 0]; blink.keyTimes = [0, 0.5, 0.55, 1]
        blink.duration = 1.0; blink.repeatCount = .infinity; blink.beginTime = CACurrentMediaTime() + 0.5
        caret.layer.add(blink, forKey: "blink")
    }
    /// Keeps a UTF-16 range in view, only when text or range changed, so a
    /// manual drag stays where the user left it until the content moves on.
    func scrollRangeToVisible(_ range: NSRange) { focus = range; setNeedsLayout() }
    /// Shows the start once, then leaves scrolling to the user even as text grows.
    func scrollToStart() { focus = nil; followedSignature = ""; contentOffset = .zero }
    /// X of the boundary before `index`. Ends (and the caret) stop before a block
    /// gap that follows the previous character; starts sit after it.
    private func x(at index: Int, in text: NSAttributedString, beforeGap: Bool = true) -> CGFloat {
        let end = max(0, min(index, text.length))
        var width = text.attributedSubstring(from: NSRange(location: 0, length: end)).size().width
        if beforeGap, end > 0, let kern = text.attribute(.kern, at: end - 1, effectiveRange: nil) as? CGFloat { width -= kern }
        return Self.inset + width
    }
    /// Frames of the block backgrounds in content coordinates, for tests.
    private(set) var blockFrames: [CGRect] = []
    override func layoutSubviews() {
        super.layoutSubviews()
        // A closed Buffer has no row width yet. Insetting that empty rectangle
        // produces CGRect.null; rounding it makes CoreGraphics report NaNs on
        // every key. Do not shape text or create a path until a viewport exists.
        let visibleWidth = bounds.width - trailingAccessoryWidth
        guard visibleWidth.isFinite, visibleWidth > 2 * Self.clipInset,
              bounds.height.isFinite, bounds.height > 2 * Self.clipInset,
              contentOffset.x.isFinite else {
            canvasClip.path = CGMutablePath()
            caret.isHidden = true; blockFrames = []
            return
        }
        let width = ceil(label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: bounds.height)).width)
        label.frame = CGRect(x: Self.inset, y: 0, width: width, height: bounds.height)
        contentSize = CGSize(width: max(bounds.width, width + 2 * Self.inset + trailingAccessoryWidth), height: bounds.height)
        if contentOffset.y != 0 || contentOffset.x > contentSize.width - bounds.width {
            contentOffset = CGPoint(x: max(0, min(contentOffset.x, contentSize.width - bounds.width)), y: 0)
        }
        canvas.frame = CGRect(origin: .zero, size: contentSize)
        let size: CGFloat = 7
        dots.frame = CGRect(x: contentOffset.x + Self.inset + 6, y: (bounds.height - size) / 2, width: size * 5, height: size)
        dot.frame = CGRect(x: 0, y: 0, width: size, height: size); dot.cornerRadius = size / 2
        dots.instanceTransform = CATransform3DMakeTranslation(size * 1.8, 0, 0)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // The visible window, in canvas coordinates, moves with the scroll position.
        let window = CGRect(x: contentOffset.x, y: 0, width: visibleWidth, height: bounds.height).insetBy(dx: Self.clipInset, dy: Self.clipInset)
        canvasClip.frame = canvas.bounds
        canvasClip.path = UIBezierPath(roundedRect: window, cornerRadius: max(0, layer.cornerRadius - Self.clipInset)).cgPath
        CATransaction.commit()
        let attributed = label.attributedText ?? NSAttributedString()
        placeholderLabel.isHidden = attributed.length > 0 || placeholder.isEmpty
        placeholderLabel.font = font
        placeholderLabel.frame = CGRect(x: Self.inset + 4, y: 0, width: max(0, bounds.width - 2 * Self.inset - 4 - trailingAccessoryWidth), height: bounds.height)
        layoutBlocks(in: attributed)
        let lineHeight = max(0, min(bounds.height - 8, ceil((attributed.length > 0 ? (attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont) : nil)?.lineHeight ?? font.lineHeight) + 2))
        if role == .input, let caretLocation {
            caret.isHidden = false
            caret.frame = CGRect(x: x(at: caretLocation, in: attributed) - 1, y: (bounds.height - lineHeight) / 2, width: 2, height: lineHeight)
        } else { caret.isHidden = true }
        guard let focus else { return }
        let signature = "\(attributed.string)\u{0}\(focus.location)\u{0}\(bounds.width)"
        guard signature != followedSignature else { return }
        followedSignature = signature
        let target = x(at: NSMaxRange(focus), in: attributed)
        scrollRectToVisible(CGRect(x: max(0, target - 24), y: 0, width: 48 + trailingAccessoryWidth, height: bounds.height), animated: false)
    }
    private func layoutBlocks(in attributed: NSAttributedString) {
        while blockViews.count > blockRanges.count { blockViews.removeLast().removeFromSuperview() }
        while blockViews.count < blockRanges.count {
            let view = UIView(); view.isUserInteractionEnabled = false
            view.layer.cornerRadius = 5; view.layer.cornerCurve = .continuous
            canvas.insertSubview(view, belowSubview: label); blockViews.append(view)
        }
        blockFrames = []
        for (index, (range, view)) in zip(blockRanges, blockViews).enumerated() {
            let left = x(at: range.location, in: attributed, beforeGap: false), right = x(at: NSMaxRange(range), in: attributed)
            let frame = CGRect(x: left - 4, y: 5, width: max(8, right - left + 8), height: max(0, bounds.height - 10))
            view.frame = frame; blockFrames.append(frame)
            let active = index == activeBlock
            view.backgroundColor = active ? (tintColor ?? .systemBlue).withAlphaComponent(0.12)
                : role == .input ? UIColor.tertiarySystemFill : UIColor.systemBackground.withAlphaComponent(0.6)
            view.layer.borderWidth = active ? 1 : 0
            view.layer.borderColor = (tintColor ?? .systemBlue).resolvedColor(with: traitCollection).cgColor
        }
    }
}

extension UIScrollView {
    /// iOS 26+ blurs a scroll view's edges wherever floating chrome overlaps it, such as a
    /// host's search bar hovering over the top of the keyboard. Keyboard rows are controls,
    /// never content scrolling under a bar, so they stay sharp.
    func hideEdgeEffects() {
        guard #available(iOS 26, *) else { return }
        for effect in [topEdgeEffect, leftEdgeEffect, bottomEdgeEffect, rightEdgeEffect] { effect.isHidden = true }
    }
}
