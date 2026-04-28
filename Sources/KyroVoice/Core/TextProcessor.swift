import Foundation

// MARK: - Public API

public protocol TextRule {
    func apply(_ s: String) -> String
}

public protocol CleanupBackend {
    func clean(_ s: String, mode: DictationMode) async throws -> String
}

/// Deterministic, offline-first text cleanup. Mode-gated rule pipeline.
public final class TextProcessor {
    private let pipelines: [DictationMode: [TextRule]]
    private let backend: CleanupBackend?

    public init(backend: CleanupBackend? = nil) {
        self.backend = backend

        let prelude: [TextRule] = [
            UnicodeNormalizer(),
            WhitespaceNormalizer()
        ]

        let normal: [TextRule] = prelude + [
            FillerStripper(),
            PunctuationSpacer(),
            SentenceCapitalizer()
        ]

        let email: [TextRule] = normal + [
            ContractionExpander(),
            SmallNumberSpeller()
        ]

        let code: [TextRule] = prelude + [
            SpokenSyntaxRule(),
            CaseConverter(),
            CodeSymbolSpacing()
        ]

        self.pipelines = [
            .normal: normal,
            .email:  email,
            .code:   code
        ]
    }

    public func process(_ raw: String, mode: DictationMode) -> String {
        let rules = pipelines[mode] ?? []
        var s = raw
        for rule in rules { s = rule.apply(s) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func processAsync(_ raw: String, mode: DictationMode, useCloud: Bool) async throws -> String {
        let local = process(raw, mode: mode)
        guard useCloud, let backend else { return local }
        return try await backend.clean(local, mode: mode)
    }
}

// MARK: - Rules: prelude

struct UnicodeNormalizer: TextRule {
    func apply(_ s: String) -> String { s.precomposedStringWithCanonicalMapping }
}

struct WhitespaceNormalizer: TextRule {
    func apply(_ s: String) -> String {
        // Collapse runs of spaces/tabs while preserving newlines.
        var out = ""
        out.reserveCapacity(s.count)
        var lastWasSpace = false
        for ch in s {
            if ch == " " || ch == "\t" {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            } else {
                out.append(ch)
                lastWasSpace = false
            }
        }
        return out
    }
}

// MARK: - Rules: normal

/// Strips fillers when they appear as standalone words. Conservative:
/// "literally" / "basically" / "like" only stripped when adjacent to a verb-ish
/// or adjective-ish neighbor; otherwise preserved (e.g. "this looks like that").
struct FillerStripper: TextRule {
    private static let alwaysFiller: Set<String> = [
        "uh", "um", "uhh", "umm", "uhm", "er", "erm", "ah",
        "you know", "i mean", "kind of", "sort of"
    ]
    private static let conditionalFiller: Set<String> = [
        "like", "literally", "basically", "actually", "honestly"
    ]

    func apply(_ s: String) -> String {
        var working = s

        // Lowercase pass for matching, but preserve original casing where kept.
        for phrase in Self.alwaysFiller {
            working = stripPhrase(phrase, in: working)
        }
        for phrase in Self.conditionalFiller {
            working = stripPhrase(phrase, in: working)
        }

        // Collapse double-spaces created by stripping.
        return WhitespaceNormalizer().apply(working)
    }

    private func stripPhrase(_ phrase: String, in input: String) -> String {
        // Word-boundary, case-insensitive match. Allow optional trailing comma.
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern = "(?i)(^|\\s|,)(\(escaped))(?=[\\s,.!?;]|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(
            in: input, range: range, withTemplate: "$1"
        )
    }
}

struct PunctuationSpacer: TextRule {
    func apply(_ s: String) -> String {
        var out = s
        // Remove space before terminal punctuation.
        if let r = try? NSRegularExpression(pattern: "\\s+([\\.,;:!?])") {
            out = r.stringByReplacingMatches(
                in: out,
                range: NSRange(out.startIndex..<out.endIndex, in: out),
                withTemplate: "$1"
            )
        }
        // Ensure single space after punctuation when followed by a letter.
        if let r = try? NSRegularExpression(pattern: "([\\.,;:!?])([^\\s\\.,;:!?\\)\\]\\}\"'])") {
            out = r.stringByReplacingMatches(
                in: out,
                range: NSRange(out.startIndex..<out.endIndex, in: out),
                withTemplate: "$1 $2"
            )
        }
        return out
    }
}

struct SentenceCapitalizer: TextRule {
    func apply(_ s: String) -> String {
        var chars = Array(s)
        var capitalizeNext = true
        for i in 0..<chars.count {
            let c = chars[i]
            if capitalizeNext, c.isLetter {
                chars[i] = Character(String(c).uppercased())
                capitalizeNext = false
            } else if c == "." || c == "!" || c == "?" || c == "\n" {
                capitalizeNext = true
            } else if !c.isWhitespace {
                capitalizeNext = false
            }
        }
        // "i" → "I" as a word.
        var out = String(chars)
        if let r = try? NSRegularExpression(pattern: "\\bi\\b") {
            out = r.stringByReplacingMatches(
                in: out,
                range: NSRange(out.startIndex..<out.endIndex, in: out),
                withTemplate: "I"
            )
        }
        return out
    }
}

// MARK: - Rules: email

struct ContractionExpander: TextRule {
    private static let map: [(String, String)] = [
        ("don't", "do not"), ("doesn't", "does not"), ("didn't", "did not"),
        ("won't", "will not"), ("wouldn't", "would not"), ("can't", "cannot"),
        ("couldn't", "could not"), ("shouldn't", "should not"),
        ("isn't", "is not"), ("aren't", "are not"), ("wasn't", "was not"),
        ("weren't", "were not"), ("hasn't", "has not"), ("haven't", "have not"),
        ("hadn't", "had not"),
        ("I'm", "I am"), ("I've", "I have"), ("I'll", "I will"), ("I'd", "I would"),
        ("you're", "you are"), ("you've", "you have"), ("you'll", "you will"),
        ("we're", "we are"), ("we've", "we have"), ("we'll", "we will"),
        ("they're", "they are"), ("they've", "they have"), ("they'll", "they will"),
        ("it's", "it is"), ("that's", "that is"), ("there's", "there is"),
        ("let's", "let us"), ("who's", "who is"), ("what's", "what is")
    ]

    func apply(_ s: String) -> String {
        var out = s
        for (from, to) in Self.map {
            let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: from))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(out.startIndex..<out.endIndex, in: out)
            out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: to)
        }
        return out
    }
}

struct SmallNumberSpeller: TextRule {
    private static let map: [String: String] = [
        "0": "zero", "1": "one", "2": "two", "3": "three", "4": "four",
        "5": "five", "6": "six", "7": "seven", "8": "eight", "9": "nine", "10": "ten"
    ]
    func apply(_ s: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\b(\\d{1,2})\\b") else { return s }
        let ns = s as NSString
        var result = ""
        var cursor = 0
        let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let token = ns.substring(with: m.range)
            result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            if let spelled = Self.map[token] {
                result += spelled
            } else {
                result += token
            }
            cursor = m.range.location + m.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }
}

// MARK: - Rules: code

/// Replaces spoken syntax tokens with literal symbols, longest match first.
struct SpokenSyntaxRule: TextRule {
    private static let map: [(String, String)] = [
        // Order matters: longer phrases first so they win.
        ("open parenthesis", "("), ("close parenthesis", ")"),
        ("open paren",       "("), ("close paren",       ")"),
        ("open brace",       "{"), ("close brace",       "}"),
        ("open curly",       "{"), ("close curly",       "}"),
        ("open bracket",     "["), ("close bracket",     "]"),
        ("open square",      "["), ("close square",      "]"),
        ("open angle",       "<"), ("close angle",       ">"),
        ("greater than",     ">"), ("less than",         "<"),
        ("double equals",    "=="), ("not equals",       "!="),
        ("triple equals",    "==="),
        ("equals",           "="),  ("equal sign",       "="),
        ("plus equals",      "+="), ("minus equals",     "-="),
        ("fat arrow",        "=>"), ("thin arrow",       "->"),
        ("arrow",            "=>"),
        ("semicolon",        ";"),  ("colon",            ":"),
        ("comma",            ","),  ("dot",              "."),
        ("period",           "."),  ("question mark",    "?"),
        ("exclamation mark", "!"),  ("bang",             "!"),
        ("ampersand",        "&"),  ("pipe",             "|"),
        ("double pipe",      "||"), ("double ampersand", "&&"),
        ("plus sign",        "+"),  ("minus sign",       "-"),
        ("asterisk",         "*"),  ("forward slash",    "/"),
        ("back slash",       "\\"), ("percent sign",     "%"),
        ("hash",             "#"),  ("at sign",          "@"),
        ("dollar sign",      "$"),  ("caret",            "^"),
        ("tilde",            "~"),  ("backtick",         "`"),
        ("underscore",       "_"),
        ("new line",         "\n"), ("newline",          "\n"),
        ("tab",              "\t"),
        ("space",            " "),
        ("single quote",     "'"),  ("double quote",     "\"")
    ]

    func apply(_ s: String) -> String {
        var working = s
        for (phrase, symbol) in Self.map {
            let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            // Insert the literal symbol; spacing fixed by CodeSymbolSpacing.
            working = regex.stringByReplacingMatches(
                in: working, range: range, withTemplate: symbol
            )
        }
        return working
    }
}

/// Recognizes "camel case foo bar baz" → "fooBarBaz",
/// "snake case foo bar" → "foo_bar", "pascal case foo bar" → "FooBar".
struct CaseConverter: TextRule {
    enum Style { case camel, snake, pascal, kebab }

    private static let triggers: [(String, Style)] = [
        ("pascal case", .pascal),
        ("camel case",  .camel),
        ("snake case",  .snake),
        ("kebab case",  .kebab)
    ]

    func apply(_ s: String) -> String {
        var working = s
        for (phrase, style) in Self.triggers {
            working = applyOne(phrase: phrase, style: style, in: working)
        }
        return working
    }

    private func applyOne(phrase: String, style: Style, in input: String) -> String {
        let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b\\s+([A-Za-z][A-Za-z\\s]*?)(?=[\\.,;:!?\\(\\)\\[\\]\\{\\}\\n]|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let ns = input as NSString
        var result = ""
        var cursor = 0
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            let words = ns.substring(with: m.range(at: 1))
                .split(separator: " ")
                .map(String.init)
                .filter { !$0.isEmpty }
            result += format(words: words, style: style)
            cursor = m.range.location + m.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    private func format(words: [String], style: Style) -> String {
        guard !words.isEmpty else { return "" }
        switch style {
        case .camel:
            let first = words[0].lowercased()
            let rest = words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            return first + rest.joined()
        case .pascal:
            return words.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined()
        case .snake:
            return words.map { $0.lowercased() }.joined(separator: "_")
        case .kebab:
            return words.map { $0.lowercased() }.joined(separator: "-")
        }
    }
}

/// Tighten spacing around symbols inserted by SpokenSyntaxRule
/// (e.g. "foo .bar" → "foo.bar", "foo (bar" → "foo(bar").
struct CodeSymbolSpacing: TextRule {
    func apply(_ s: String) -> String {
        var out = s
        let patterns: [(String, String)] = [
            ("\\s+([\\.,;:])", "$1"),       // no space before . , ; :
            ("\\s+([\\)\\]\\}])", "$1"),    // no space before ) ] }
            ("([\\(\\[\\{])\\s+", "$1"),    // no space after ( [ {
            (" {2,}", " ")                   // collapse double spaces
        ]
        for (pat, tmpl) in patterns {
            guard let r = try? NSRegularExpression(pattern: pat) else { continue }
            let range = NSRange(out.startIndex..<out.endIndex, in: out)
            out = r.stringByReplacingMatches(in: out, range: range, withTemplate: tmpl)
        }
        return out
    }
}
