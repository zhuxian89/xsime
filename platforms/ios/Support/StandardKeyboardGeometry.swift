import UIKit
import RimesCore

enum StandardKeyControl: String, CaseIterable {
    case space, backspace, enter, shift, numbers, language, emoji, buffer
    case symbols, separator, spelling, punctuation
}
enum StandardKeyboardMode: Equatable { case qwerty, nineKey, numeric, symbols }

struct StandardKeyboardGeometry {
    var keys: [(text: String, label: String, frame: CGRect)] = []
    var controls: [StandardKeyControl: CGRect] = [:]
    var height: CGFloat
    static func height(landscape: Bool, percent: Int = 100) -> CGFloat { (landscape ? 143 : 206) * CGFloat(min(130, max(100, percent))) / 100 }

    /// `chinese` swaps the number and symbol rows for the marks Chinese input types.
    static func make(width: CGFloat, mode: StandardKeyboardMode, landscape: Bool, chinese: Bool = false, numericNineGrid: Bool = false, availableHeight: CGFloat? = nil) -> Self {
        let height = max(1, availableHeight ?? height(landscape: landscape)), gap: CGFloat = landscape ? 5 : 6
        let rowGap: CGFloat = landscape ? 5 : 10, rowHeight = (height - rowGap * 3) / 4
        let width = max(1, width)
        var value = Self(height: height)
        func rect(_ x: CGFloat, _ row: Int, _ w: CGFloat, span: Int = 1) -> CGRect {
            CGRect(x: x, y: CGFloat(row) * (rowHeight + rowGap), width: max(1, w),
                   height: CGFloat(span) * rowHeight + CGFloat(span - 1) * rowGap)
        }
        if mode == .numeric && numericNineGrid {
            let unit = (width - gap * 3) / 4
            func cell(_ c: Int, _ r: Int, rows: Int = 1) -> CGRect { rect(CGFloat(c) * (unit + gap), r, unit, span: rows) }
            for digit in 1...9 { value.keys.append((String(digit), String(digit), cell((digit - 1) % 3, (digit - 1) / 3))) }
            value.keys.append(("0", "0", cell(1, 3))); value.keys.append((".", ".", cell(2, 3)))
            value.controls = [.numbers: cell(0, 3), .backspace: cell(3, 0), .symbols: cell(3, 1), .enter: cell(3, 2, rows: 2)]
            return value
        }
        if mode == .nineKey {
            let unit = (width - gap * 4) / 5
            func cell(_ column: Int, _ row: Int, columns: Int = 1, rows: Int = 1) -> CGRect {
                rect(CGFloat(column) * (unit + gap), row, CGFloat(columns) * unit + CGFloat(columns - 1) * gap, span: rows)
            }
            // A permanent, scrollable punctuation column; candidates remain available.
            value.controls = [.punctuation: cell(0, 0, rows: 3), .spelling: cell(1, 0),
                .backspace: cell(4, 0), .separator: cell(4, 1), .enter: cell(4, 2, rows: 2),
                .symbols: cell(0, 3)]
            let side = unit * 0.78
            value.controls[.numbers] = rect(unit + gap, 3, side)
            let languageX = 4 * (unit + gap) - gap - side
            value.controls[.language] = rect(languageX, 3, side)
            let spaceStart = unit + gap + side + gap
            value.controls[.space] = rect(spaceStart, 3, languageX - gap - spaceStart)
            for (digit, label, column, row) in [("2", "ABC", 2, 0), ("3", "DEF", 3, 0),
                ("4", "GHI", 1, 1), ("5", "JKL", 2, 1), ("6", "MNO", 3, 1),
                ("7", "PQRS", 1, 2), ("8", "TUV", 2, 2), ("9", "WXYZ", 3, 2)] {
                value.keys.append((digit, label, cell(column, row)))
            }
            return value
        }
        let unit = (width - 9 * gap) / 10
        let rows: [String] = mode == .qwerty ? ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
            : PunctuationLayout.rows(symbols: mode == .symbols, chinese: chinese)
        let sideWidth = max(unit, width * 0.115)
        for (row, letters) in rows.enumerated() {
            // As on iOS, the punctuation row of the number and symbol pages spans the
            // gap between the side keys: wider caps, evenly spaced, no empty ends.
            if mode != .qwerty && row == 2 && !letters.isEmpty {
                let count = CGFloat(letters.count), edge = gap * 2
                let span = width - 2 * (sideWidth + edge)
                let keyWidth = min(unit * 1.45, (span - gap * (count - 1)) / count)
                let space = count > 1 ? (span - keyWidth * count) / (count - 1) : 0
                let start = count > 1 ? sideWidth + edge : (width - keyWidth) / 2
                for (index, letter) in letters.enumerated() {
                    let key = String(letter)
                    value.keys.append((key, key, rect(start + CGFloat(index) * (keyWidth + space), row, keyWidth)))
                }
                continue
            }
            let occupied = CGFloat(letters.count) * unit + CGFloat(letters.count - 1) * gap
            let start = (width - occupied) / 2
            for (index, letter) in letters.enumerated() {
                let key = String(letter)
                // Lowercase by default, as on iOS; the surface capitalises while Shift is on.
                value.keys.append((key, key, rect(start + CGFloat(index) * (unit + gap), row, unit)))
            }
        }
        value.controls[mode == .qwerty ? .shift : .symbols] = rect(0, 2, sideWidth)
        value.controls[.backspace] = rect(width - sideWidth, 2, sideWidth)
        // Keep a wide Space, explicit language switch and host-labelled Return.
        // 123 | 中/英 | space | return, as in the nine-key layout. No emoji key.
        let weights: [(StandardKeyControl, CGFloat)] = [(.numbers, 0.85), (.language, 0.85), (.space, 6.4), (.enter, 1.9)]
        let footerUnit = (width - gap * CGFloat(weights.count - 1)) / 10
        var x: CGFloat = 0
        for (key, weight) in weights {
            value.controls[key] = rect(x, 3, footerUnit * weight)
            x += footerUnit * weight + gap
        }
        return value
    }
}
