import CoreText
import Foundation

private struct LocalizationFailure: Error, CustomStringConvertible {
    let description: String
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw LocalizationFailure(description: message) }
}

/// Argument positions and conversion types must agree even if a translator
/// reorders explicitly numbered arguments. A stray percent is also rejected.
private func placeholders(in text: String) throws -> [Int: String] {
    let pattern = #"%(?:([1-9][0-9]*)\$)?[-+ #0']*(?:[0-9]+)?(?:\.[0-9]+)?(hh|ll|h|l|j|z|t|L)?([@diuoxXfFeEgGaAcCsSp%])"#
    let expression = try NSRegularExpression(pattern: pattern)
    let source = text as NSString
    let matches = expression.matches(in: text, range: NSRange(location: 0, length: source.length))
    var coveredPercents: Set<Int> = []
    var result: [Int: String] = [:]
    var nextPosition = 1
    for match in matches {
        let conversion = source.substring(with: match.range(at: 3))
        coveredPercents.insert(match.range.location)
        if conversion == "%" {
            try require(source.substring(with: match.range) == "%%", "Invalid literal percent in \(text)")
            coveredPercents.insert(match.range.location + 1)
            continue
        }
        let numbered = match.range(at: 1).location != NSNotFound
        let position = numbered ? Int(source.substring(with: match.range(at: 1)))! : nextPosition
        if !numbered { nextPosition += 1 }
        let length = match.range(at: 2).location == NSNotFound ? "" : source.substring(with: match.range(at: 2))
        let signature = length + conversion
        try require(result[position] == nil || result[position] == signature,
                    "Conflicting argument \(position) in \(text)")
        result[position] = signature
    }
    for index in 0..<source.length where source.character(at: index) == 37 {
        try require(coveredPercents.contains(index), "Unrecognized format placeholder in \(text)")
    }
    return result
}

@main
private enum SnakeLocalizationChecks {
    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("Localization check failed: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func run() throws {
        guard CommandLine.arguments.count == 3,
              let bundle = Bundle(path: CommandLine.arguments[2]) else {
            throw LocalizationFailure(description: "Expected project root and localization bundle arguments")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let english = try resourceTable("en", bundle: bundle)
        let chinese = try resourceTable("zh-Hans", bundle: bundle)
        let keys = Set(english.keys)
        try require(!keys.isEmpty && keys == Set(chinese.keys),
                    "English and Chinese resource keys differ: \(keys.symmetricDifference(Set(chinese.keys)).sorted())")
        for key in keys.sorted() {
            try require(!english[key]!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && !chinese[key]!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "Empty translation for \(key)")
            let englishArguments = try placeholders(in: english[key]!)
            let chineseArguments = try placeholders(in: chinese[key]!)
            try require(englishArguments == chineseArguments,
                        "Format argument mismatch for \(key)")
        }
        try checkEnumCoverage(keys)
        try checkLocales(bundle: bundle, english: english, chinese: chinese)
        try checkMissingTranslationFallback(bundle: bundle, english: english, chinese: chinese)
        try checkPresentationSources(root: root, keys: keys)
        try checkFontBudgets(root: root, bundle: bundle)
        print("PASS localization: \(keys.count) matching bilingual keys and format signatures, explicit locales and English fallback, all map/style/speed choices, UI literal scan and real pixel-font width budgets")
    }

    private static func resourceTable(_ language: String, bundle: Bundle) throws -> [String: String] {
        guard let directory = bundle.path(forResource: language, ofType: "lproj") else {
            throw LocalizationFailure(description: "Missing \(language).lproj in the resource bundle")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent("Localizable.strings"))
        guard let table = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else {
            throw LocalizationFailure(description: "Invalid \(language) string table")
        }
        return table
    }

    private static func checkEnumCoverage(_ keys: Set<String>) throws {
        for map in SnakeMap.allCases {
            for suffix in ["title", "subtitle"] {
                try require(keys.contains("map.\(map.rawValue).\(suffix)"), "Missing localization for map \(map.rawValue), \(suffix)")
            }
        }
        for appearance in SnakeAppearance.allCases {
            try require(keys.contains("appearance.\(appearance.rawValue)"), "Missing appearance \(appearance.rawValue)")
        }
        for speed in SnakeSpeed.allCases {
            try require(keys.contains("speed.\(speed.rawValue)"), "Missing speed \(speed.rawValue)")
        }
    }

    private static func checkLocales(bundle: Bundle, english: [String: String], chinese: [String: String]) throws {
        let cases: [(String, [String: String])] = [
            ("en_US", english), ("en_GB", english),
            ("zh_CN", chinese), ("zh_Hans_SG", chinese), ("zh_Hant_TW", chinese),
            ("fr_FR", english), ("ja_JP", english), ("ar_SA", english)
        ]
        for (identifier, expected) in cases {
            let strings = SnakeStrings(locale: Locale(identifier: identifier), bundle: bundle)
            for (key, value) in expected {
                try require(strings.text(key) == value, "\(identifier): bundle lookup failed for \(key)")
            }
            let range = strings.format("duration.range", 142, 156)
            try require(range == (identifier.hasPrefix("zh") ? "142–156分" : "142–156 min"),
                        "\(identifier): duration format did not substitute its integer arguments")
            let rest = strings.format("rest.message", "1:23:45")
            try require(rest.contains("1:23:45") && !rest.contains("%@"), "\(identifier): object substitution failed")
            let a11y = strings.format("duration.a11y", "Speed", 142, 156)
            try require(a11y.contains("Speed") && a11y.contains("142") && a11y.contains("156"),
                        "\(identifier): mixed object/integer substitution failed")
            try require(strings.text("__missing_localization_check__") == "__missing_localization_check__",
                        "\(identifier): missing-key fallback changed")
        }
    }

    private static func checkMissingTranslationFallback(bundle: Bundle, english: [String: String], chinese: [String: String]) throws {
        // Use a separate bundle path so previously loaded resource tables cannot
        // hide the missing translation through Foundation's lookup cache.
        let fixtureURL = FileManager.default.temporaryDirectory.appendingPathComponent("snake-localization-fallback-\(UUID().uuidString).bundle")
        try FileManager.default.copyItem(at: bundle.bundleURL, to: fixtureURL)
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        guard let fixture = Bundle(url: fixtureURL),
              let directory = fixture.path(forResource: "zh-Hans", ofType: "lproj") else {
            throw LocalizationFailure(description: "Could not prepare the missing-translation bundle")
        }
        var incompleteChinese = chinese
        incompleteChinese.removeValue(forKey: "setup.map")
        let table = try PropertyListSerialization.data(fromPropertyList: incompleteChinese, format: .binary, options: 0)
        try table.write(to: URL(fileURLWithPath: directory).appendingPathComponent("Localizable.strings"))
        let strings = SnakeStrings(locale: Locale(identifier: "zh_CN"), bundle: fixture)
        try require(strings.text("setup.map") == english["setup.map"], "A missing Chinese key did not fall back to its English translation")
        try require(strings.text("setup.speed") == chinese["setup.speed"], "A missing Chinese key changed other Chinese translations")
    }

    /// This is a guard against new visible/VoiceOver literals, not a SwiftUI
    /// layout test. Localized keys and numeric HUD formats are allowed; brand
    /// lettering remains invariant. Simulator screenshots verify actual layout.
    private static func checkPresentationSources(root: URL, keys: Set<String>) throws {
        let calls = try NSRegularExpression(pattern: #"\b(PixelLabel|PixelControlLabel|PixelText|Text|Label|Button|accessibilityLabel|accessibilityValue|accessibilityHint)\s*\("#)
        let literals = try NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#)
        let canonicalLabels = try NSRegularExpression(pattern: #"\b(?:map|appearance|speed)\.(?:label|title|subtitle)\b"#)
        for path in ["SnakeFocus/ContentView.swift", "SnakeFocus/PixelInterface.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            let utf16 = source as NSString
            for call in calls.matches(in: source, range: NSRange(location: 0, length: utf16.length)) {
                let start = call.range.location + call.range.length
                let argument = firstArgument(in: utf16, startingAt: start)
                let argumentRange = NSRange(location: 0, length: (argument as NSString).length)
                try require(canonicalLabels.firstMatch(in: argument, range: argumentRange) == nil,
                            "\(path): presentation uses a canonical Chinese enum label: \(argument)")
                for literal in literals.matches(in: argument, range: argumentRange) {
                    let raw = (argument as NSString).substring(with: literal.range)
                    let value = String(raw.dropFirst().dropLast())
                    let dynamicKey = value.hasPrefix("map.\\(") || value.hasPrefix("appearance.\\(") || value.hasPrefix("speed.\\(")
                    let brand = value == "SNAKE" && utf16.substring(with: call.range(at: 1)) == "PixelText"
                    let numeric = value.rangeOfCharacter(from: .letters) == nil || isNumericFormat(value)
                    try require(keys.contains(value) || dynamicKey || brand || numeric,
                                "\(path): unlocalized visible or accessibility literal \(raw)")
                }
            }
        }
    }

    private static func firstArgument(in source: NSString, startingAt start: Int) -> String {
        var depth = 0
        var quoted = false
        var escaped = false
        var end = start
        while end < source.length {
            let character = source.character(at: end)
            if quoted {
                if escaped { escaped = false }
                else if character == 92 { escaped = true }
                else if character == 34 { quoted = false }
            } else if character == 34 { quoted = true }
            else if character == 40 { depth += 1 }
            else if character == 41 {
                if depth == 0 { break }
                depth -= 1
            } else if character == 44 && depth == 0 { break }
            end += 1
        }
        return source.substring(with: NSRange(location: start, length: end - start))
    }

    private static func isNumericFormat(_ value: String) -> Bool {
        guard value.contains("%"), let signature = try? placeholders(in: value), !signature.isEmpty,
              signature.values.allSatisfy({ ["d", "i", "u"].contains($0) }) else { return false }
        let expression = try! NSRegularExpression(pattern: #"%(?:[1-9][0-9]*\$)?[0-9]*[diu]"#)
        let remainder = expression.stringByReplacingMatches(in: value, range: NSRange(location: 0, length: (value as NSString).length), withTemplate: "")
        return remainder.rangeOfCharacter(from: .letters) == nil
    }

    private static func checkFontBudgets(root: URL, bundle: Bundle) throws {
        let fontURL = root.appendingPathComponent("SnakeFocus/Fonts/FusionPixel/fusion-pixel-12px-monospaced-zh_hans.otf")
        var registrationError: Unmanaged<CFError>?
        try require(CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &registrationError),
                    "Could not load the bundled Fusion Pixel font: \(String(describing: registrationError))")
        let name = "Fusion-Pixel-12px-Mono-zh-Hans-Regular"
        func width(_ text: String, size: CGFloat) throws -> Double {
            let font = CTFontCreateWithName(name as CFString, size, nil)
            try require(CTFontCopyPostScriptName(font) as String == name, "Pixel-font measurement fell back to another font")
            let characters = Array(text.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            try require(CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count), "Pixel font is missing a visible glyph in \(text)")
            let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
            return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), nil, nil, nil)
        }
        func fits(_ text: String, size: CGFloat, budget: Double, context: String) throws {
            let measured = try width(text, size: size)
            try require(measured <= budget + 0.01, "\(context): \(text) is \(measured)pt, exceeds \(budget)pt at \(size)pt")
        }
        for locale in ["en_US", "zh_CN"] {
            let strings = SnakeStrings(locale: Locale(identifier: locale), bundle: bundle)
            // Four speed columns start at 334pt content width: 76pt per card,
            // with 8pt reserved for its horizontal text padding.
            for speed in SnakeSpeed.allCases {
                try fits(strings.text("speed.\(speed.rawValue)"), size: 18, budget: 68, context: "\(locale) speed")
                for map in SnakeMap.allCases {
                    let estimate = SnakeDurationEstimates.estimate(for: map, movesPerSecond: speed.movesPerSecond)
                    try fits(strings.format("duration.range", estimate.lowerMinutes, estimate.upperMinutes),
                             size: 12, budget: 68, context: "\(locale) \(map.rawValue) duration")
                }
            }
            // Conservative compact-screen contracts, independent of text
            // shrinking: 320pt screen minus page/panel/button padding.
            for appearance in SnakeAppearance.allCases {
                try fits(strings.text("appearance.\(appearance.rawValue)"), size: 18, budget: 135, context: "\(locale) appearance")
            }
            for key in ["action.pause", "action.resume", "action.restart"] {
                try fits(strings.text(key), size: 24, budget: 109, context: "\(locale) game control")
            }
            for key in ["action.cancel", "action.confirmRestart"] {
                try fits(strings.text(key), size: 18, budget: 84, context: "\(locale) confirmation control")
            }
            try fits(strings.text("restart.title"), size: 24, budget: 228, context: "\(locale) confirmation title")
            try fits(strings.text("rest.title"), size: 24, budget: 188, context: "\(locale) compact rest card")
            for key in ["game.clear", "game.over"] {
                try fits(strings.text(key), size: 24, budget: 188, context: "\(locale) compact end-state title")
            }
            try fits(strings.text("setup.start"), size: 24, budget: 256, context: "\(locale) compact start control")
        }
    }
}
