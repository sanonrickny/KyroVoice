import Foundation

// ponytail: one runnable check for the whole text pipeline instead of a test
// target. Run with `./.build/release/KyroVoice --self-check`; it asserts and
// exits without ever starting the UI. Every case below is a bug that shipped.
enum TextProcessorSelfCheck {
    static func run() -> Never {
        let p = TextProcessor()
        var failures = 0

        func expect(_ input: String, _ mode: DictationMode, _ want: String,
                    _ note: String, line: UInt = #line) {
            let got = p.process(input, mode: mode)
            if got != want {
                failures += 1
                print("FAIL (line \(line)) \(note)")
                print("   in:   \(input)")
                print("   want: \(want)")
                print("   got:  \(got)")
            }
        }

        // Multi-grapheme uppercase used to trap the process via
        // Character(String(c).uppercased()). These must not crash.
        expect("ßeta test", .normal, "SSeta test", "sharp s at sentence start")
        expect("\u{FB01}nd it", .normal, "FInd it", "fi ligature at sentence start")
        expect("\u{0149}ope", .normal, "\u{02BC}Nope", "apostrophe-n at sentence start")

        // Digits must survive the punctuation spacer and number speller.
        expect("version 3.5 at 9:30", .normal, "Version 3.5 at 9:30", "decimals and times intact")
        expect("meet at 9:30 in room 3.5", .email, "Meet at 9:30 in room 3.5", "email mode leaves numerics alone")
        expect("send it to foo@bar.com", .normal, "Send it to foo@bar.com", "email address intact")

        // Real words must not be stripped as filler.
        expect("I actually finished it", .normal, "I actually finished it", "actually is content")
        expect("what kind of car is that", .normal, "What kind of car is that", "kind of is content")
        expect("do you know where it is", .normal, "Do you know where it is", "you know is content")
        expect("this looks like that", .normal, "This looks like that", "like is content")
        // ...but true disfluencies still go, without leaving an orphan comma.
        expect("um the build is green", .normal, "The build is green", "um stripped")
        expect("Ah, the sunset was nice", .normal, "The sunset was nice", "ah plus comma stripped")

        // Code mode: longest-phrase-first and template escaping.
        expect("x plus equals one", .code, "x += one", "plus equals beats equals")
        expect("y minus equals two", .code, "y -= two", "minus equals beats equals")
        expect("a double pipe b", .code, "a || b", "double pipe beats pipe")
        expect("a double ampersand b", .code, "a && b", "double ampersand beats ampersand")
        expect("path back slash n", .code, "path \\ n", "backslash survives the template")
        expect("cost dollar sign five", .code, "cost $ five", "dollar sign survives the template")

        if failures == 0 {
            print("TextProcessor self-check: all checks passed")
            exit(0)
        }
        print("TextProcessor self-check: \(failures) failure(s)")
        exit(1)
    }
}
