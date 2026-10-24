import Foundation
import Testing
@testable import PennyworthCore

@Suite struct CalculatorTests {
    private func value(_ text: String) throws -> Double {
        try Calculator.evaluate(text).value
    }

    @Test func followsPrecedenceAndAssociativity() throws {
        #expect(try value("24*7") == 168)
        #expect(try value("1 + 2 * 3") == 7)
        #expect(try value("(1 + 2) * 3") == 9)
        #expect(try value("10 - 4 - 3") == 3)
        #expect(try value("2^3^2") == 512)
        #expect(try value("-2^2") == -4)
        #expect(try value("2^-1") == 0.5)
        #expect(try value("7 % 3") == 1)
        #expect(try value("2 ** 10") == 1024)
        #expect(try value("--3") == 3)
    }

    @Test func supportsImplicitMultiplication() throws {
        #expect(try value("2(3+4)") == 14)
        #expect(try value("(1+1)(2+3)") == 10)
        #expect(abs(try value("2pi") - 2 * .pi) < 1e-12)
        #expect(abs(try value("2e") - 2 * M_E) < 1e-12)
    }

    @Test func supportsFunctionsAndConstants() throws {
        #expect(try value("sqrt(16)") == 4)
        #expect(try value("max(1, 5, 3)") == 5)
        #expect(try value("round(2.5) + floor(1.9) + ceil(1.1)") == 6)
        #expect(try value("log(1000)") == 3)
        #expect(abs(try value("sin(pi/2)") - 1) < 1e-12)
        #expect(try value("5!") == 120)
        #expect(try value("π") == .pi)
    }

    @Test func readsNumberFormats() throws {
        #expect(try value("1.5e3") == 1500)
        #expect(try value("2E-2") == 0.02)
        #expect(try value(".5 + .5") == 1)
        #expect(try value("0xff + 1") == 256)
        #expect(try value("0b101") == 5)
        #expect(try value("6 × 7 ÷ 2 − 1") == 20)
    }

    @Test func countsOperationsSoLoneNumbersCanBeIgnored() throws {
        #expect(try Calculator.evaluate("2048").operationCount == 0)
        #expect(try Calculator.evaluate("-5").operationCount == 0)
        #expect(try Calculator.evaluate("pi").operationCount == 0)
        #expect(try Calculator.evaluate("1+1").operationCount == 1)
        #expect(try Calculator.evaluate("sqrt(2)").operationCount == 1)
    }

    @Test func rejectsWhatIsNotMath() {
        #expect(throws: Calculator.Failure.syntax) { try Calculator.evaluate("1 +") }
        #expect(throws: Calculator.Failure.syntax) { try Calculator.evaluate("(1 + 2") }
        #expect(throws: Calculator.Failure.syntax) { try Calculator.evaluate("7-zip?") }
        #expect(throws: Calculator.Failure.unknownName("password")) { try Calculator.evaluate("1password") }
        #expect(throws: Calculator.Failure.unknownName("safari")) { try Calculator.evaluate("safari") }
        #expect(throws: Calculator.Failure.unknownName("foo")) { try Calculator.evaluate("foo(2)") }
        #expect(throws: Calculator.Failure.undefined) { try Calculator.evaluate("1/0") }
        #expect(throws: Calculator.Failure.undefined) { try Calculator.evaluate("2.5!") }
        #expect(throws: Calculator.Failure.syntax) { try Calculator.evaluate("sqrt(1, 2)") }
    }
}

@Suite struct UnitConverterTests {
    private func convert(_ text: String) -> Double? {
        UnitConverter.convert(text)?.result
    }

    private func close(_ a: Double?, _ b: Double) -> Bool {
        guard let a else { return false }
        return abs(a - b) < 1e-9 * max(1, abs(b))
    }

    @Test func convertsData() {
        #expect(close(convert("3 GB in MB"), 3000))
        #expect(close(convert("3GB to mb"), 3000))
        #expect(close(convert("1 GiB in MiB"), 1024))
        #expect(close(convert("8 Mb in MB"), 1))
        #expect(close(convert("1 byte in b"), 8))
    }

    @Test func convertsEverydayUnits() {
        #expect(close(convert("100 f to c"), 37.77777777777778))
        #expect(close(convert("0 °C in °F"), 32))
        #expect(close(convert("5 km to mi"), 3.106855961174))
        #expect(close(convert("90 min in h"), 1.5))
        #expect(close(convert("2 days in hours"), 48))
        #expect(close(convert("1 week in days"), 7))
        #expect(close(convert("1 kg in lbs"), 2.2046226218488))
        #expect(close(convert("1 fl oz in ml"), 29.5735295625))
        #expect(close(convert("100 km/h in mph"), 62.137119223733))
        #expect(close(convert("1.5e3 m in km"), 1.5))
    }

    @Test func picksTheRightSeparatorWhenUnitsLookLikeIt() {
        #expect(close(convert("3 in in cm"), 7.62))
        #expect(close(convert("10 cm in in"), 3.937007874016))
        #expect(close(convert("2 in to cm"), 5.08))
    }

    @Test func rejectsMismatchedOrUnknownUnits() {
        #expect(convert("1 kg in m") == nil)
        #expect(convert("3 zorks in MB") == nil)
        #expect(convert("3 GB") == nil)
        #expect(convert("weather in paris") == nil)
        #expect(convert("GB in MB") == nil)
    }

    @Test func keepsTheTypedUnits() throws {
        let conversion = try #require(UnitConverter.convert("3 GB in MB"))
        #expect(conversion == .init(value: 3, unit: "GB", result: 3000, targetUnit: "MB"))
    }
}

@Suite struct CalculatorProviderTests {
    private func search(_ text: String) async -> [SearchResult] {
        await CalculatorProvider(locale: Locale(identifier: "en_US")).search(SearchQuery(text))
    }

    @Test func answersExplicitAndObviousCalculations() async throws {
        let result = try #require(await search("= 24*7").first)
        #expect(result.title == "168")
        #expect(result.action == .copyToClipboard("168"))
        #expect(result.alternateAction == .copyToClipboard("24*7 = 168"))
        #expect(result.autocomplete == "= 168")
        #expect(!result.isLearnable)

        #expect(await search("24*7").first?.title == "168")
        #expect(await search("=pi").first?.title == "3.14159265359")
    }

    @Test func staysQuietForOrdinaryQueries() async {
        for text in ["2048", "safari", "1password", "7-zip", "=", "= nonsense", "pi"] {
            #expect(await search(text).isEmpty, "\(text)")
        }
    }

    @Test func formatsForDisplayAndCopiesPlainNumbers() async throws {
        let big = try #require(await search("1234567 * 1000").first)
        #expect(big.title == "1,234,567,000")
        #expect(big.action == .copyToClipboard("1234567000"))
        #expect(await search("0.1 + 0.2").first?.title == "0.3")
        #expect(await search("1/3").first?.title == "0.333333333333")
        #expect(await search("2^60").first?.title == "1.152921505E18")
    }

    @Test func answersConversions() async throws {
        let result = try #require(await search("3 GB in MB").first)
        #expect(result.title == "3,000 MB")
        #expect(result.action == .copyToClipboard("3000"))
        #expect(result.alternateAction == .copyToClipboard("3 GB = 3000 MB"))
        #expect(await search("= 3 GB in MB").first?.title == "3,000 MB")
    }

    @Test func outranksApplications() async throws {
        let fake = try FakeApplications()
        try fake.app("24 Hour Clock.app")
        let apps = ApplicationProvider(scanner: ApplicationScanner(locations: [.init(fake.root, depth: 1)]))
        apps.reload()
        let engine = SearchEngine(providers: [apps, CalculatorProvider()])
        #expect(await engine.search("24*7").first?.id == "calculator")
    }
}
