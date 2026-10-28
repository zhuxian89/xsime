import XCTest
import UIKit
import RimesCore
@testable import RIMES

@MainActor final class StandardKeyboardRuntimeTests: XCTestCase {
    func testImportedSchemeWithRememberedNineKeyUsesAndSelectsQwerty() async throws {
        let defaults = UserDefaults.standard
        let preferenceKeys = ["keyboard-preferences-v1", "imported-rime-choice-v1"]
        let saved = preferenceKeys.map { defaults.object(forKey: $0) }
        let (window, keyboard) = host()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ImportedLayout-\(UUID())", isDirectory: true)
        let store = RimeSchemeStore(root: root)
        let package = RimeSchemePackage(id: UUID().uuidString, name: "Synthetic imported Pinyin",
            schemas: [.init(id: "layout_test_pinyin", name: "Synthetic imported Pinyin")],
            importedAt: Date(), sourceDigest: String(repeating: "a", count: 64), warnings: [])
        let user = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RimeImported/\(package.id)", isDirectory: true)
        defer {
            keyboard.developmentChoose(.pinyin); window.isHidden = true
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: user)
            for (key, value) in zip(preferenceKeys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        // Reuse the already compiled bundled engine, renamed into an isolated imported package.
        // This verifies import/layout routing without downloading a third-party dictionary.
        let resources = try XCTUnwrap(Bundle.main.url(forResource: "EngineData", withExtension: nil))
        let stage = store.stagingRoot.appendingPathComponent(package.id, isDirectory: true)
        try FileManager.default.createDirectory(at: store.stagingRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: resources, to: stage)
        let original = try String(contentsOf: stage.appendingPathComponent("build/rimes_pinyin.schema.yaml"), encoding: .utf8)
        try original.replacingOccurrences(of: "schema_id: rimes_pinyin", with: "schema_id: layout_test_pinyin")
            .write(to: stage.appendingPathComponent("build/layout_test_pinyin.schema.yaml"), atomically: true, encoding: .utf8)
        try store.publish(stagedURL: stage, package: package)
        let selection = RimeSchemeSelection(packageID: package.id, schemaID: package.schemas[0].id)

        keyboard.developmentOrdinaryAppearance(layout: .nineKey)
        XCTAssertEqual(keyboard.layoutViews.keys.standardMode, .nineKey)
        keyboard.developmentChooseImported(selection, store: store)
        XCTAssertEqual(keyboard.developmentImportedSelection, selection, "The imported engine really loaded; no built-in fallback.")
        XCTAssertEqual(keyboard.layoutViews.keys.standardMode, .qwerty)
        let actions = try layoutActions(keyboard)
        XCTAssertEqual(actions.qwerty.state, .on, "The menu must identify the actual imported-scheme layout.")
        XCTAssertEqual(actions.nineKey.state, .off)
        XCTAssertFalse(actions.qwerty.attributes.contains(.disabled))
        XCTAssertTrue(actions.nineKey.attributes.contains(.disabled), "Bundled nine-key decoding does not apply to imported schemas.")

        keyboard.developmentType("ni")
        XCTAssertEqual(keyboard.developmentRaw, "ni")
        let confirmed = try XCTUnwrap(keyboard.layoutViews.candidates.buttons.first?.currentTitle)
        let button = UIButton(); button.addAction(actions.qwerty, for: .touchUpInside)
        button.sendActions(for: .touchUpInside)
        await keyboard.developmentWaitForDelivery()
        XCTAssertEqual(keyboard.layoutProxy.native.text, confirmed, "The layout choice settles the existing candidate exactly once.")
        XCTAssertEqual(keyboard.developmentImportedSelection, selection, "Selecting QWERTY must keep the imported scheme.")
        XCTAssertEqual(KeyboardPreferenceStore().load().ordinaryLayout, .qwerty)
        XCTAssertEqual(keyboard.layoutViews.keys.standardMode, .qwerty)
        keyboard.developmentType("nihao")
        XCTAssertEqual(keyboard.developmentRaw, "nihao")
        keyboard.developmentSpaceKey.sendActions(for: .touchUpInside)
        await keyboard.developmentWaitForDelivery()
        XCTAssertEqual(keyboard.layoutProxy.native.text, confirmed + "你好")
        keyboard.developmentChoose(.pinyin)
        XCTAssertEqual(keyboard.layoutViews.keys.standardMode, .qwerty, "The explicitly chosen 26-key preference remains after leaving the import.")
    }

    func testUnsupportedBuiltInNineKeyPreferenceHasQwertyMenuSelection() throws {
        let (window, keyboard) = host(); defer { window.isHidden = true }
        for scheme in [InputScheme.ziranma, .wubi86, .english] {
            keyboard.developmentOrdinaryAppearance(layout: .nineKey)
            keyboard.developmentChoose(scheme)
            XCTAssertEqual(keyboard.layoutViews.keys.standardMode, .qwerty)
            let actions = try layoutActions(keyboard)
            XCTAssertEqual(actions.qwerty.state, .on)
            XCTAssertEqual(actions.nineKey.state, .off)
            XCTAssertTrue(actions.nineKey.attributes.contains(.disabled))
        }
        keyboard.developmentChoose(.pinyin)
        XCTAssertEqual(keyboard.layoutViews.keys.standardMode, .nineKey, "Temporary scheme restrictions preserve the nine-key preference.")
        let actions = try layoutActions(keyboard)
        XCTAssertEqual(actions.nineKey.state, .on)
        XCTAssertEqual(actions.qwerty.state, .off)
        XCTAssertFalse(actions.nineKey.attributes.contains(.disabled))
    }

    private func layoutActions(_ keyboard: KeyboardViewController) throws -> (qwerty: UIAction, nineKey: UIAction) {
        func actions(_ menu: UIMenu) -> [UIAction] {
            menu.children.flatMap { element in
                if let action = element as? UIAction { return [action] }
                if let child = element as? UIMenu { return actions(child) }
                return []
            }
        }
        let menu = try XCTUnwrap(keyboard.layoutViews.settings.menu)
        let choices = actions(menu)
        return (try XCTUnwrap(choices.first { $0.title == "26 键 · QWERTY" }),
                try XCTUnwrap(choices.first { $0.title == "9 键 · 全拼" }))
    }

    func testKeySoundsRemainIndependentOfHapticsAndDoNotClickForChordPreviewOrCommit() {
        let feedback = KeyboardFeedback()
        var clicks = 0, pulses = 0, time: TimeInterval = 0
        feedback.clock = { time }; feedback.playInputClick = { clicks += 1 }
        feedback.onFeedback = { _ in pulses += 1 }
        feedback.enabled = false
        feedback.send(.press)
        XCTAssertEqual(clicks, 1); XCTAssertEqual(pulses, 0)
        time = 0.1; feedback.send(.selection, combination: "aj")
        time = 0.2; feedback.send(.commit)
        XCTAssertEqual(clicks, 1)
        time = 0.3; feedback.send(.press); feedback.send(.press)
        XCTAssertEqual(clicks, 2)
        feedback.soundEnabled = false; feedback.enabled = true
        time = 0.4; feedback.send(.press)
        XCTAssertEqual(clicks, 2); XCTAssertEqual(pulses, 1)
        let (window, keyboard) = host(); defer { window.isHidden = true }
        XCTAssertEqual(keyboard.inputView?.enableInputClicksWhenVisible, true)
        XCTAssertEqual(keyboard.inputView?.allowsSelfSizing, true)
    }
    func testStandardGeometryFitsAndPlacesQwertyUtilitiesAtTheThirdRow() throws {
        for width: CGFloat in [310, 383, 842] {
            for mode in [StandardKeyboardMode.qwerty, .nineKey, .numeric, .symbols] {
                let geometry = StandardKeyboardGeometry.make(width: width, mode: mode, landscape: width > 600)
                let frames = geometry.keys.map(\.frame) + Array(geometry.controls.values)
                for (i, frame) in frames.enumerated() {
                    XCTAssertGreaterThan(frame.width, 20)
                    XCTAssertGreaterThanOrEqual(frame.minX, -0.01)
                    XCTAssertLessThanOrEqual(frame.maxX, width + 0.01)
                    XCTAssertLessThanOrEqual(frame.maxY, geometry.height + 0.01)
                    for other in frames.dropFirst(i + 1) { XCTAssertFalse(frame.intersects(other)) }
                }
                if mode == .qwerty {
                    XCTAssertEqual(geometry.keys.count, 26)
                    let z = try XCTUnwrap(geometry.keys.first { $0.text == "z" })
                    XCTAssertEqual(geometry.controls[.shift]?.minY, z.frame.minY)
                    XCTAssertEqual(geometry.controls[.backspace]?.minY, z.frame.minY)
                    XCTAssertGreaterThan(try XCTUnwrap(geometry.controls[.space]).width, width * 0.4)
                }
            }
        }
    }
    /// iOS Shift: one tap capitalises one letter, a quick second tap or a hold
    /// locks capitals, and a tap from the lock returns to lowercase.
    func testShiftCapitalisesOnceAndLocksOnDoubleTapOrHold() throws {
        let (window, keyboard) = host(); defer { window.isHidden = true }
        keyboard.developmentOrdinaryAppearance(layout: .qwerty)
        keyboard.developmentLanguage()
        keyboard.developmentTapShift(); keyboard.developmentType("a"); keyboard.developmentType("b")
        XCTAssertEqual(keyboard.layoutProxy.native.text, "Ab")
        keyboard.developmentTapShift(); keyboard.developmentTapShift()
        XCTAssertEqual(keyboard.developmentShiftState, "locked")
        keyboard.developmentType("c"); keyboard.developmentType("d")
        keyboard.developmentTapShift(); keyboard.developmentType("e")
        XCTAssertEqual(keyboard.layoutProxy.native.text, "AbCDe")
        keyboard.developmentHoldShift()
        keyboard.developmentType("f"); keyboard.developmentType("g")
        XCTAssertEqual(keyboard.layoutProxy.native.text, "AbCDeFG")
        keyboard.developmentTapShift()
        XCTAssertEqual(keyboard.developmentShiftState, "off")
    }
    /// Nine-key keeps symbols under the rail and language beside Space.
    func testStandardBottomRowsKeepUtilitiesAndSpace() throws {
        for width: CGFloat in [310, 383, 842] {
            for mode in [StandardKeyboardMode.qwerty, .nineKey] {
                let geometry = StandardKeyboardGeometry.make(width: width, mode: mode, landscape: width > 600)
                XCTAssertNil(geometry.controls[.emoji], "\(mode) still has an emoji key")
                let row = try [StandardKeyControl.numbers, .language, .space].map { try XCTUnwrap(geometry.controls[$0]) }
                let enter = try XCTUnwrap(geometry.controls[.enter])
                for frame in row { XCTAssertEqual(frame.maxY, geometry.height, accuracy: 0.01) }
                XCTAssertEqual(enter.maxY, geometry.height, accuracy: 0.01)
                XCTAssertLessThan(row[0].minX, row[1].minX)
                if mode == .nineKey {
                    XCTAssertLessThan(row[2].minX, row[1].minX)
                    XCTAssertEqual(geometry.controls[.punctuation]?.minX, 0)
                    XCTAssertEqual(geometry.controls[.symbols]?.minX, 0)
                } else { XCTAssertLessThan(row[1].minX, row[2].minX) }
                XCTAssertLessThan(row[2].minX, enter.minX)
            }
        }
    }
    func testNineKeyTypesSelectsSpellingAndDeletesInHostAndBuffer() throws {
        for buffered in [false, true] {
            let (window, keyboard) = host(); defer { window.isHidden = true }
            keyboard.developmentOrdinaryAppearance(layout: .nineKey)
            if buffered { keyboard.developmentBuffer("") }
            keyboard.developmentType("64426")
            XCTAssertEqual(keyboard.developmentRaw, "64426")
            XCTAssertEqual(keyboard.layoutViews.keys.standardMode, .nineKey)
            keyboard.developmentSelectNineKeySpelling("ni")
            XCTAssertEqual(keyboard.developmentRaw, "ni'426")
            keyboard.developmentBackspace(); XCTAssertEqual(keyboard.developmentRaw, "ni'42")
            keyboard.developmentType("6")
            let candidate = try XCTUnwrap(descendants(keyboard.layoutViews.candidates).first { $0.accessibilityLabel == "你好" } as? UIButton)
            candidate.sendActions(for: .touchUpInside)
            XCTAssertEqual(buffered ? keyboard.developmentBufferSource.text : keyboard.layoutProxy.native.text, "你好")
            XCTAssertTrue(keyboard.developmentRaw.isEmpty)
            if buffered { XCTAssertTrue(keyboard.layoutProxy.native.text.isEmpty) }
        }
    }
    func testNineKeyNumericAndEnglishSwitchesDoNotDecodeLiteralDigitsOrLetters() throws {
        let (window, keyboard) = host(); defer { window.isHidden = true }
        keyboard.developmentOrdinaryAppearance(layout: .nineKey)
        keyboard.developmentNumeric(); keyboard.developmentType("123")
        XCTAssertEqual(keyboard.layoutProxy.native.text, "123")
        XCTAssertTrue(keyboard.developmentRaw.isEmpty)
        keyboard.developmentNumeric(); keyboard.developmentLanguage(); keyboard.developmentType("abc")
        XCTAssertEqual(keyboard.layoutProxy.native.text, "123abc")
        XCTAssertEqual(keyboard.layoutViews.keys.standardMode, .qwerty)
        keyboard.developmentLanguage()
        XCTAssertEqual(keyboard.layoutViews.keys.standardMode, .nineKey)
    }
    func testAppliedCustomLayoutTakesPrecedenceOverNineKeyPreference() throws {
        let (window, keyboard) = host(); defer { window.isHidden = true }
        keyboard.developmentOrdinaryAppearance(layout: .nineKey)
        let custom = CustomKeyboardLayout.templates[0]
        keyboard.developmentSetCustomLayout(custom)
        keyboard.developmentChoose(.pinyin)
        XCTAssertEqual(keyboard.layoutViews.keys.customLayout, custom)
        XCTAssertNil(keyboard.layoutViews.keys.standardMode)
        keyboard.developmentType("nihao")
        let candidate = try XCTUnwrap(descendants(keyboard.layoutViews.candidates).first { $0.accessibilityLabel == "你好" } as? UIButton)
        candidate.sendActions(for: .touchUpInside)
        XCTAssertEqual(keyboard.layoutProxy.native.text, "你好")
        keyboard.developmentSetCustomLayout(nil)
        keyboard.developmentChoose(.pinyin)
        XCTAssertEqual(keyboard.layoutViews.keys.standardMode, .nineKey)
        keyboard.developmentType("64426")
        XCTAssertNotNil(descendants(keyboard.layoutViews.candidates).first { $0.accessibilityLabel == "你好" })
    }
    func testOrthogonalGridIsALayoutAnySchemeCanUseAndOnlyIsaac2026ResolvesChords() {
        let (window, keyboard) = host(); defer { window.isHidden = true }
        func orthogonal(_ scheme: InputScheme) -> KeySurface {
            keyboard.developmentChoose(scheme)
            keyboard.developmentOrdinaryAppearance(layout: .orthogonal); window.layoutIfNeeded()
            return keyboard.layoutViews.keys
        }
        let grid = orthogonal(.chord)
        XCTAssertTrue(grid.chordMode); XCTAssertTrue(grid.resolvesChords)
        XCTAssertEqual(grid.profile.outputEncoding, .ziranma)
        for scheme in [InputScheme.pinyin, .ziranma, .wubi86, .lingxiWubi, .english] {
            let tap = orthogonal(scheme)
            XCTAssertTrue(tap.chordMode, "\(scheme)"); XCTAssertFalse(tap.resolvesChords, "\(scheme)")
            XCTAssertEqual(tap.developmentKeyFrames, grid.developmentKeyFrames, "\(scheme) draws the same grid")
        }
        // Leaving the grid is a layout choice and keeps the scheme.
        keyboard.developmentChoose(.wubi86); keyboard.developmentOrdinaryAppearance(layout: .qwerty); window.layoutIfNeeded()
        XCTAssertFalse(keyboard.layoutViews.keys.chordMode)
        // isaac2026 on another layout types normally; picking it again returns to the grid.
        keyboard.developmentChoose(.chord); keyboard.developmentOrdinaryAppearance(layout: .qwerty); window.layoutIfNeeded()
        XCTAssertFalse(keyboard.layoutViews.keys.chordMode); XCTAssertFalse(keyboard.layoutViews.keys.resolvesChords)
        keyboard.developmentChoose(.chord); window.layoutIfNeeded()
        XCTAssertTrue(keyboard.layoutViews.keys.resolvesChords)
    }
    func testLegacyChordSchemeMigratesToOrthogonalLayoutOverItsEncoding() {
        let (window, keyboard) = host(); defer { window.isHidden = true }
        keyboard.developmentChoose(.chord); window.layoutIfNeeded()
        let keys = keyboard.layoutViews.keys
        XCTAssertTrue(keys.chordMode); XCTAssertTrue(keys.resolvesChords)
        XCTAssertEqual(keys.profile.outputEncoding, .ziranma, "The built-in chord profile was Ziranma-encoded.")
    }
    func testSkinChangesPreserveFramesAndChordMappingAcrossOrdinarySettings() {
        let (window, keyboard) = host(); defer { window.isHidden = true }
        keyboard.developmentOrdinaryAppearance(layout: .qwerty, skin: .system)
        window.layoutIfNeeded()
        let original = keyboard.layoutViews.keys.developmentKeyFrames
        keyboard.developmentOrdinaryAppearance(layout: .qwerty, skin: .rimes)
        window.layoutIfNeeded()
        XCTAssertEqual(keyboard.layoutViews.keys.developmentKeyFrames, original)
        for layout in ChordLayout.allCases {
            keyboard.developmentChoose(.chord); keyboard.developmentSetLayout(layout); window.layoutIfNeeded()
            let chord = keyboard.layoutViews.keys.developmentKeyFrames
            keyboard.developmentOrdinaryAppearance(layout: .orthogonal, skin: .system); window.layoutIfNeeded()
            XCTAssertEqual(keyboard.layoutViews.keys.developmentKeyFrames, chord)
            XCTAssertTrue(keyboard.layoutViews.keys.resolvesChords)
            XCTAssertEqual(keyboard.layoutViews.keys.skin, .system)
        }
    }
    func testSystemGlobeReservesItsRowWithoutShrinkingStandardKeys() {
        let (window, keyboard) = host(); defer { window.isHidden = true }
        let keys = keyboard.layoutViews.keys.developmentKeyFrames
        let space = keyboard.developmentSpaceKey.frame
        keyboard.layoutNeedsInputModeSwitchKey = true; keyboard.developmentContent(); window.layoutIfNeeded()
        XCTAssertFalse(keyboard.layoutViews.globe.isHidden)
        XCTAssertFalse(keyboard.layoutViews.bottom.isHidden)
        XCTAssertEqual(keyboard.layoutViews.keys.developmentKeyFrames, keys)
        XCTAssertEqual(keyboard.developmentSpaceKey.frame, space)
    }
    func testAppearanceStoreLeavesSchemeAndCustomLayoutFilesUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let custom = CustomLayoutStore(root: root)
        try custom.apply(CustomKeyboardLayout.templates[0])
        let before = try Data(contentsOf: root.appendingPathComponent("keyboard-layouts-v1.json"))
        let store = KeyboardAppearanceStore(root: root)
        XCTAssertEqual(store.load().layout, .qwerty); XCTAssertEqual(store.load().skin, .system)
        try store.save(.init(layout: .nineKey, skin: .rimes))
        let saved = store.load()
        XCTAssertEqual(saved.layout, .nineKey); XCTAssertEqual(saved.skin, .rimes); XCTAssertNotNil(saved.revision)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("keyboard-layouts-v1.json")), before)
    }
    func testChineseNumberAndSymbolPagesShowTheMarksTheyType() throws {
        for width: CGFloat in [310, 383, 842] {
            for mode in [StandardKeyboardMode.numeric, .symbols] {
                let geometry = StandardKeyboardGeometry.make(width: width, mode: mode, landscape: width > 600, chinese: true)
                XCTAssertEqual(geometry.keys.map(\.text), PunctuationLayout.rows(symbols: mode == .symbols, chinese: true).flatMap { $0.map(String.init) })
                XCTAssertEqual(geometry.keys.map(\.label), geometry.keys.map(\.text))
                let frames = geometry.keys.map(\.frame) + Array(geometry.controls.values)
                for (i, frame) in frames.enumerated() {
                    XCTAssertGreaterThan(frame.width, 20)
                    XCTAssertGreaterThanOrEqual(frame.minX, -0.01)
                    XCTAssertLessThanOrEqual(frame.maxX, width + 0.01)
                    for other in frames.dropFirst(i + 1) { XCTAssertFalse(frame.intersects(other)) }
                }
            }
        }
        for mode in [StandardKeyboardMode.qwerty, .nineKey] {
            XCTAssertEqual(StandardKeyboardGeometry.make(width: 393, mode: mode, landscape: false, chinese: true).keys.map(\.text),
                           StandardKeyboardGeometry.make(width: 393, mode: mode, landscape: false).keys.map(\.text))
        }
        let (window, keyboard) = host(); defer { window.isHidden = true }
        keyboard.developmentOrdinaryAppearance(layout: .qwerty); keyboard.developmentChoose(.pinyin)
        keyboard.developmentNumeric(); window.layoutIfNeeded()
        var frames = keyboard.layoutViews.keys.developmentKeyFrames
        XCTAssertNotNil(frames["，"]); XCTAssertNotNil(frames["“"]); XCTAssertNil(frames[","])
        // English keeps the half-width page, without leaving it.
        keyboard.developmentLanguage(); window.layoutIfNeeded()
        frames = keyboard.layoutViews.keys.developmentKeyFrames
        XCTAssertNotNil(frames[","]); XCTAssertNil(frames["，"])
        XCTAssertEqual(keyboard.layoutViews.keys.standardMode, .numeric)
    }
    func testSentenceMarkTypedFirstOnTheNumberPageReturnsToLetters() throws {
        for layout in [OrdinaryKeyboardLayout.qwerty, .nineKey] {
            let (window, keyboard) = host(); defer { window.isHidden = true }
            keyboard.developmentOrdinaryAppearance(layout: layout); keyboard.developmentChoose(.pinyin)
            let letters: StandardKeyboardMode = layout == .nineKey ? .nineKey : .qwerty
            let keys = keyboard.layoutViews.keys
            keyboard.developmentNumeric(); XCTAssertEqual(keys.standardMode, .numeric)
            keyboard.developmentType("，")
            XCTAssertEqual(keyboard.layoutProxy.native.text, "，"); XCTAssertEqual(keys.standardMode, letters)
            XCTAssertTrue(keyboard.developmentRaw.isEmpty)
            // Digits keep the page, and so does a mark that follows them.
            keyboard.developmentNumeric(); keyboard.developmentType("3"); keyboard.developmentType("。")
            XCTAssertEqual(keyboard.layoutProxy.native.text, "，3。"); XCTAssertEqual(keys.standardMode, .numeric)
            keyboard.developmentNumeric(); XCTAssertEqual(keys.standardMode, letters)
            // A mark that opens a pair stays for its partner.
            keyboard.developmentNumeric(); keyboard.developmentType("“"); keyboard.developmentType("”")
            XCTAssertEqual(keyboard.layoutProxy.native.text, "，3。“”"); XCTAssertEqual(keys.standardMode, .numeric)
            keyboard.developmentNumeric()
            // Looking at the symbol page first does not use up the visit.
            let symbols = try XCTUnwrap(keyboard.developmentStandardFunctions[.symbols] as? UIControl)
            keyboard.developmentNumeric(); symbols.sendActions(for: .touchUpInside); XCTAssertEqual(keys.standardMode, .symbols)
            symbols.sendActions(for: .touchUpInside); XCTAssertEqual(keys.standardMode, .numeric)
            keyboard.developmentType("？")
            XCTAssertEqual(keyboard.layoutProxy.native.text, "，3。“”？"); XCTAssertEqual(keys.standardMode, letters)
        }
        // English punctuation never leaves the page by itself.
        let (window, keyboard) = host(); defer { window.isHidden = true }
        keyboard.developmentOrdinaryAppearance(layout: .qwerty); keyboard.developmentChoose(.pinyin)
        keyboard.developmentLanguage(); keyboard.developmentNumeric(); keyboard.developmentType(",")
        XCTAssertEqual(keyboard.layoutProxy.native.text, ","); XCTAssertEqual(keyboard.layoutViews.keys.standardMode, .numeric)
    }
    func testNineKeyRailInsertsDirectlyAndPreservesCandidates() async throws {
        for buffered in [false, true] {
            let (window, keyboard) = host(); defer { window.isHidden = true }
            keyboard.developmentOrdinaryAppearance(layout: .nineKey); keyboard.developmentChoose(.pinyin)
            if buffered { keyboard.developmentBuffer("") }
            window.layoutIfNeeded(); keyboard.view.layoutIfNeeded()
            let rail = try XCTUnwrap(keyboard.developmentStandardFunctions[.punctuation] as? NineKeyPunctuationRail)
            let strip = keyboard.layoutViews.candidates
            func text() -> String { buffered ? keyboard.developmentBufferSource.text : keyboard.layoutProxy.native.text }
            XCTAssertFalse(rail.isHidden)
            XCTAssertEqual(Array(rail.buttons.prefix(4)).compactMap(\.currentTitle), ["，", "。", "？", "！"])
            rail.buttons[4].sendActions(for: .touchUpInside)
            XCTAssertEqual(text(), "、")
            XCTAssertEqual(keyboard.layoutViews.keys.standardMode, .nineKey)
            keyboard.developmentType("64426")
            let top = try XCTUnwrap(strip.buttons.first?.currentTitle)
            rail.buttons[0].sendActions(for: .touchUpInside)
            await keyboard.developmentWaitForDelivery()
            XCTAssertEqual(text(), "、" + top + "，"); XCTAssertTrue(keyboard.developmentRaw.isEmpty)
            XCTAssertEqual(keyboard.layoutViews.keys.standardMode, .nineKey)
            XCTAssertGreaterThan(rail.contentSize.height, rail.bounds.height)
            if buffered { XCTAssertTrue(keyboard.layoutProxy.native.text.isEmpty) }
            let image = UIGraphicsImageRenderer(bounds: keyboard.view.bounds).image { keyboard.view.layer.render(in: $0.cgContext) }
            let attachment = XCTAttachment(image: image); attachment.name = "nine-key-punctuation-\(buffered ? "buffer" : "host")"
            attachment.lifetime = .keepAlways; add(attachment)
            keyboard.developmentNumeric()
            XCTAssertTrue(rail.isHidden)
            rail.buttons[0].sendActions(for: .touchUpInside)
            XCTAssertEqual(text(), "、" + top + "，", "A hidden rail cannot insert into a different layout")
        }
    }
    private func host() -> (UIWindow, KeyboardViewController) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 900))
        let parent = UIViewController(); window.rootViewController = parent; window.makeKeyAndVisible()
        let keyboard = KeyboardViewController(); keyboard.layoutNeedsInputModeSwitchKey = false
        keyboard.loadViewIfNeeded(); keyboard.developmentResetPreferences()
        parent.addChild(keyboard); parent.view.addSubview(keyboard.view); keyboard.didMove(toParent: parent)
        parent.view.layoutIfNeeded(); keyboard.view.layoutIfNeeded()
        return (window, keyboard)
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
}
