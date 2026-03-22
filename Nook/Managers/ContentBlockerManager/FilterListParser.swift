//
//  FilterListParser.swift
//  Nook
//
//  Parses ABP/uBO filter list syntax into categorized rules:
//  NetworkRule (URL blocking), CosmeticRule (CSS hiding), ScriptletRule (##+js directives).
//

import Foundation

// MARK: - Rule Types

struct NetworkRule: Sendable {
    let pattern: String       // Original ABP pattern
    let regex: String         // Converted regex for WKContentRuleList
    let isException: Bool     // @@-prefixed exception rules
    let isThirdParty: Bool
    let isFirstParty: Bool
    let isStrictParty: Bool   // $strict1p or $strict3p (exact domain match)
    let resourceTypes: [String]?  // image, script, etc.
    let domains: DomainConstraint?
    let redirectResource: String?  // $redirect resource name
    let isRedirectRule: Bool  // $redirect-rule (only redirect if already blocked)
    let isImportant: Bool     // $important flag
    let isBadFilter: Bool     // $badfilter flag
    let removeparam: String?  // $removeparam value
    let methods: [String]?    // $method=GET|POST
    let toDomains: [String]?  // $to= domain list
    let denyallowDomains: [String]?  // $denyallow= domain list

    struct DomainConstraint: Sendable {
        let ifDomains: [String]    // Apply only on these domains
        let unlessDomains: [String] // Don't apply on these domains
    }
}

struct ProceduralCosmeticRule: Sendable {
    let selector: String      // Base CSS selector
    let operations: [(type: String, arg: String)]  // Procedural pseudo-class chain
    let domains: [String]     // Domain constraints
    let isException: Bool
}

struct RemoveParamRule: Sendable {
    let pattern: String       // URL pattern to match
    let regex: String         // Converted regex
    let paramPattern: String  // Parameter name/pattern to remove
    let isException: Bool
    let domains: DomainConstraint?

    struct DomainConstraint: Sendable {
        let ifDomains: [String]
        let unlessDomains: [String]
    }
}

struct CosmeticRule: Sendable {
    let selector: String      // CSS selector to hide
    let domains: [String]     // Empty = global
    let isException: Bool     // #@# exception
}

struct ScriptletRule: Sendable {
    let name: String          // e.g. "json-prune"
    let args: [String]        // Arguments to the scriptlet
    let domains: [String]     // Domains to apply on
    let isException: Bool
}

// MARK: - Parser

enum FilterListParser {

    struct ParseResult: Sendable {
        var networkRules: [NetworkRule] = []
        var cosmeticRules: [CosmeticRule] = []
        var scriptletRules: [ScriptletRule] = []
        var proceduralCosmeticRules: [ProceduralCosmeticRule] = []
        var removeParamRules: [RemoveParamRule] = []
        var errorCount: Int = 0
    }

    static func parse(_ text: String) -> ParseResult {
        var result = ParseResult()
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty, comments, directives
            if trimmed.isEmpty || trimmed.hasPrefix("!") || trimmed.hasPrefix("[") {
                continue
            }

            // Scriptlet rules: domain##+js(name, args...)
            if let scriptletRule = parseScriptletRule(trimmed) {
                result.scriptletRules.append(scriptletRule)
                continue
            }

            // Procedural cosmetic rules (must check before standard cosmetic)
            if let proceduralRule = parseProceduralCosmeticRule(trimmed) {
                result.proceduralCosmeticRules.append(proceduralRule)
                continue
            }

            // Cosmetic rules: domain##selector or domain#@#selector
            if let cosmeticRule = parseCosmeticRule(trimmed) {
                result.cosmeticRules.append(cosmeticRule)
                continue
            }

            // Network rules
            if let networkRule = parseNetworkRule(trimmed) {
                // Separate removeparam rules
                if let removeparam = networkRule.removeparam {
                    let domainConstraint: RemoveParamRule.DomainConstraint?
                    if let d = networkRule.domains {
                        domainConstraint = RemoveParamRule.DomainConstraint(ifDomains: d.ifDomains, unlessDomains: d.unlessDomains)
                    } else {
                        domainConstraint = nil
                    }
                    result.removeParamRules.append(RemoveParamRule(
                        pattern: networkRule.pattern,
                        regex: networkRule.regex,
                        paramPattern: removeparam,
                        isException: networkRule.isException,
                        domains: domainConstraint
                    ))
                } else {
                    result.networkRules.append(networkRule)
                }
            } else {
                result.errorCount += 1
            }
        }

        return result
    }

    // MARK: - Procedural Cosmetic Rule Parsing

    private static func parseProceduralCosmeticRule(_ line: String) -> ProceduralCosmeticRule? {
        // Check for procedural pseudo-classes
        let proceduralPseudos = [":has-text(", ":xpath(", ":style(", ":matches-css(", ":matches-css-before(", ":matches-css-after(", ":min-text-length(", ":others(", ":upward(", ":remove()", ":remove-attr(", ":remove-class(", ":matches-attr(", ":matches-path(", ":matches-prop(", ":watch-attr("]

        // Must have ## or #@# separator and a procedural pseudo
        let isException: Bool
        let separatorRange: Range<String.Index>?

        if line.contains("##+js(") || line.contains("#@#+js(") { return nil }

        if let range = line.range(of: "#@#") {
            isException = true
            separatorRange = range
        } else if let range = line.range(of: "##") {
            isException = false
            separatorRange = range
        } else {
            return nil
        }

        guard let sepRange = separatorRange else { return nil }

        let selector = String(line[sepRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !selector.isEmpty else { return nil }

        // Check if this contains any procedural pseudos
        let hasProcedural = proceduralPseudos.contains { selector.contains($0) }
        guard hasProcedural else { return nil }

        let domainPart = String(line[line.startIndex..<sepRange.lowerBound])
        let domains = domainPart.isEmpty ? [] : domainPart.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }

        // Parse the procedural chain
        let operations = parseProceduralOperations(selector)

        // Extract the base CSS selector (everything before the first procedural pseudo)
        let baseSelector = extractBaseSelector(selector)

        return ProceduralCosmeticRule(
            selector: baseSelector,
            operations: operations,
            domains: domains,
            isException: isException
        )
    }

    private static func parseProceduralOperations(_ selector: String) -> [(type: String, arg: String)] {
        var operations: [(type: String, arg: String)] = []
        var remaining = selector

        // Find and extract each procedural operation
        let operatorNames = [":has-text", ":xpath", ":style", ":matches-css", ":matches-css-before", ":matches-css-after", ":min-text-length", ":others", ":upward", ":remove", ":remove-attr", ":remove-class", ":matches-attr", ":matches-path", ":matches-prop", ":watch-attr", ":not"]

        while true {
            var earliest: (name: String, range: Range<String.Index>)? = nil
            for opName in operatorNames {
                if let range = remaining.range(of: opName + "(") {
                    if earliest == nil || range.lowerBound < earliest!.range.lowerBound {
                        earliest = (name: opName, range: range)
                    }
                }
                // Handle :remove() with no args
                if opName == ":remove", let range = remaining.range(of: ":remove()") {
                    if earliest == nil || range.lowerBound < earliest!.range.lowerBound {
                        earliest = (name: ":remove", range: range)
                    }
                }
            }

            guard let found = earliest else { break }

            if found.name == ":remove" && remaining[found.range].hasSuffix(")") {
                operations.append((type: "remove", arg: ""))
                remaining = String(remaining[found.range.upperBound...])
                continue
            }

            // Find matching closing parenthesis
            let afterOpen = found.range.upperBound
            var depth = 1
            var idx = afterOpen
            while idx < remaining.endIndex && depth > 0 {
                if remaining[idx] == "(" { depth += 1 }
                else if remaining[idx] == ")" { depth -= 1 }
                if depth > 0 { idx = remaining.index(after: idx) }
            }

            if depth == 0 {
                let arg = String(remaining[afterOpen..<idx])
                let type = String(found.name.dropFirst()) // Remove leading ':'
                operations.append((type: type, arg: arg))
                remaining = String(remaining[remaining.index(after: idx)...])
            } else {
                break
            }
        }

        return operations
    }

    private static func extractBaseSelector(_ selector: String) -> String {
        let operatorPrefixes = [":has-text(", ":xpath(", ":style(", ":matches-css(", ":matches-css-before(", ":matches-css-after(", ":min-text-length(", ":others(", ":upward(", ":remove()", ":remove-attr(", ":remove-class(", ":matches-attr(", ":matches-path(", ":matches-prop(", ":watch-attr(", ":not("]

        var earliest = selector.endIndex
        for prefix in operatorPrefixes {
            if let range = selector.range(of: prefix) {
                if range.lowerBound < earliest {
                    earliest = range.lowerBound
                }
            }
        }

        let base = String(selector[selector.startIndex..<earliest]).trimmingCharacters(in: .whitespaces)
        return base.isEmpty ? "*" : base
    }

    // MARK: - Scriptlet Parsing

    private static func parseScriptletRule(_ line: String) -> ScriptletRule? {
        // Format: domain1,domain2##+js(scriptlet-name, arg1, arg2)
        // Exception: domain1,domain2#@#+js(scriptlet-name, arg1, arg2)
        let isException: Bool
        let separatorRange: Range<String.Index>?

        if let range = line.range(of: "#@#+js(") {
            isException = true
            separatorRange = range
        } else if let range = line.range(of: "##+js(") {
            isException = false
            separatorRange = range
        } else {
            return nil
        }

        guard let sepRange = separatorRange else { return nil }

        let domainPart = String(line[line.startIndex..<sepRange.lowerBound])
        let domains = domainPart.isEmpty ? [] : domainPart.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }

        // Extract the js(...) content
        let jsStart = isException ? line.index(sepRange.lowerBound, offsetBy: 7) : line.index(sepRange.lowerBound, offsetBy: 6)
        guard jsStart < line.endIndex else { return nil }
        var jsContent = String(line[jsStart...])
        // Remove trailing )
        if jsContent.hasSuffix(")") {
            jsContent.removeLast()
        }

        let parts = splitScriptletArgs(jsContent)
        guard !parts.isEmpty else { return nil }

        let name = parts[0].trimmingCharacters(in: .whitespaces)
        let args = Array(parts.dropFirst()).map { $0.trimmingCharacters(in: .whitespaces) }

        return ScriptletRule(name: name, args: args, domains: domains, isException: isException)
    }

    private static func splitScriptletArgs(_ s: String) -> [String] {
        // Split by comma, but respect quotes
        var result: [String] = []
        var current = ""
        var inQuote = false
        var quoteChar: Character = "\""

        for ch in s {
            if !inQuote && (ch == "\"" || ch == "'") {
                inQuote = true
                quoteChar = ch
                continue
            }
            if inQuote && ch == quoteChar {
                inQuote = false
                continue
            }
            if !inQuote && ch == "," {
                result.append(current)
                current = ""
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty || !result.isEmpty {
            result.append(current)
        }
        return result
    }

    // MARK: - Cosmetic Rule Parsing

    private static func parseCosmeticRule(_ line: String) -> CosmeticRule? {
        let isException: Bool
        let separatorRange: Range<String.Index>?

        // Don't match scriptlet rules
        if line.contains("##+js(") || line.contains("#@#+js(") {
            return nil
        }

        if let range = line.range(of: "#@#") {
            isException = true
            separatorRange = range
        } else if let range = line.range(of: "##") {
            isException = false
            separatorRange = range
        } else {
            return nil
        }

        guard let sepRange = separatorRange else { return nil }

        let domainPart = String(line[line.startIndex..<sepRange.lowerBound])
        let selector = String(line[sepRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        guard !selector.isEmpty else { return nil }

        // Check for uBlock-specific procedural cosmetic filters that require JS execution.
        // Standard CSS :has() is supported natively in Safari 15.4+ and passes through.
        let proceduralPseudos = [":has-text(", ":xpath(", ":style(", ":matches-css(", ":matches-css-before(", ":matches-css-after(", ":min-text-length(", ":others(", ":upward(", ":remove()", ":remove-attr(", ":remove-class(", ":matches-attr(", ":matches-path(", ":matches-prop(", ":watch-attr(", ":not("]
        let hasProcedural = proceduralPseudos.contains { selector.contains($0) }
        if hasProcedural {
            // Parse as procedural cosmetic rule instead of standard CSS
            // This will be handled by ProceduralCosmeticEngine
            return nil  // Handled separately in parse() via parseProceduralCosmeticRule
        }

        let domains = domainPart.isEmpty ? [] : domainPart.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }

        return CosmeticRule(selector: selector, domains: domains, isException: isException)
    }

    // MARK: - Network Rule Parsing

    private static func parseNetworkRule(_ line: String) -> NetworkRule? {
        var text = line
        var isException = false

        // Exception rules start with @@
        if text.hasPrefix("@@") {
            isException = true
            text = String(text.dropFirst(2))
        }

        // Split by $ for options
        var patternPart: String
        var optionsPart: String?

        if let dollarIdx = findOptionsSeparator(text) {
            patternPart = String(text[text.startIndex..<dollarIdx])
            optionsPart = String(text[text.index(after: dollarIdx)...])
        } else {
            patternPart = text
        }

        // Skip empty patterns
        guard !patternPart.isEmpty else { return nil }

        // Skip regex patterns that are too complex
        if patternPart.hasPrefix("/") && patternPart.hasSuffix("/") && patternPart.count > 2 {
            // Raw regex — use as-is (strip slashes)
            let inner = String(patternPart.dropFirst().dropLast())
            return buildNetworkRule(regex: inner, pattern: patternPart, isException: isException, options: optionsPart)
        }

        // Convert ABP pattern to regex
        guard let regex = abpPatternToRegex(patternPart) else { return nil }
        return buildNetworkRule(regex: regex, pattern: patternPart, isException: isException, options: optionsPart)
    }

    /// Find the $ that separates pattern from options.
    private static func findOptionsSeparator(_ text: String) -> String.Index? {
        guard let lastDollar = text.lastIndex(of: "$") else { return nil }

        // For raw regex patterns /regex/$options or /regex/:
        // The pattern part is between the first and last /
        // The $ separator is only valid if it comes after the closing /
        if text.hasPrefix("/") {
            // Find the closing / of the regex (search from end, skip the last $ area)
            let beforeDollar = text[text.startIndex..<lastDollar]
            if let closingSlash = beforeDollar.lastIndex(of: "/"), closingSlash > text.startIndex {
                // $ is after closing / — valid separator
                return lastDollar
            }
            // No closing / found before $ — the $ is inside the regex, not a separator
            // But check: is this actually a regex or just a URL path like /ads/stuff$option?
            // Raw regex requires both opening AND closing /
            // A plain path like /foo/bar$option has the $ as separator
            let afterDollar = String(text[text.index(after: lastDollar)...])
            let looksLikeOptions = afterDollar.contains(",") ||
                ["script", "image", "stylesheet", "font", "media", "popup", "xmlhttprequest",
                 "websocket", "subdocument", "other", "ping", "document",
                 "third-party", "3p", "first-party", "1p", "domain=", "important",
                 "redirect", "badfilter", "removeparam", "match-case", "~"]
                .contains(where: { afterDollar.lowercased().hasPrefix($0) })
            if looksLikeOptions {
                return lastDollar
            }
            return nil
        }

        return lastDollar
    }

    private static func buildNetworkRule(regex: String, pattern: String, isException: Bool, options: String?) -> NetworkRule? {
        var isThirdParty = false
        var isFirstParty = false
        var isStrictParty = false
        var resourceTypes: [String]? = nil
        var domains: NetworkRule.DomainConstraint? = nil
        var redirectResource: String? = nil
        var isRedirectRule = false
        var isImportant = false
        var isBadFilter = false
        var removeparam: String? = nil
        var methods: [String]? = nil
        var toDomains: [String]? = nil
        var denyallowDomains: [String]? = nil

        if let opts = options {
            let parsed = parseOptions(opts)
            isThirdParty = parsed.thirdParty
            isFirstParty = parsed.firstParty
            isStrictParty = parsed.strictParty
            resourceTypes = parsed.resourceTypes.isEmpty ? nil : parsed.resourceTypes
            if !parsed.ifDomains.isEmpty || !parsed.unlessDomains.isEmpty {
                domains = NetworkRule.DomainConstraint(ifDomains: parsed.ifDomains, unlessDomains: parsed.unlessDomains)
            }
            redirectResource = parsed.redirectResource
            isRedirectRule = parsed.isRedirectRule
            isImportant = parsed.isImportant
            isBadFilter = parsed.isBadFilter
            removeparam = parsed.removeparam
            methods = parsed.methods
            toDomains = parsed.toDomains
            denyallowDomains = parsed.denyallowDomains

            // Skip rules with unsupported options
            if parsed.unsupported { return nil }
        }

        return NetworkRule(
            pattern: pattern,
            regex: regex,
            isException: isException,
            isThirdParty: isThirdParty,
            isFirstParty: isFirstParty,
            isStrictParty: isStrictParty,
            resourceTypes: resourceTypes,
            domains: domains,
            redirectResource: redirectResource,
            isRedirectRule: isRedirectRule,
            isImportant: isImportant,
            isBadFilter: isBadFilter,
            removeparam: removeparam,
            methods: methods,
            toDomains: toDomains,
            denyallowDomains: denyallowDomains
        )
    }

    // MARK: - ABP Pattern → Regex

    static func abpPatternToRegex(_ pattern: String) -> String? {
        var p = pattern
        var result = ""

        // Handle anchor patterns
        let hasStartAnchor = p.hasPrefix("||")
        let hasExactStart = p.hasPrefix("|") && !hasStartAnchor
        let hasEndAnchor = p.hasSuffix("|")

        if hasStartAnchor {
            p = String(p.dropFirst(2))
            // || means "starts at domain boundary"
            result += "^[^:]+:(//)?([^/]+\\.)?"
        } else if hasExactStart {
            p = String(p.dropFirst())
            result += "^"
        }

        if hasEndAnchor {
            p = String(p.dropLast())
        }

        // Escape regex special chars, convert ABP wildcards
        for ch in p {
            switch ch {
            case "*":
                result += ".*"
            case "^":
                // Separator: non-alphanumeric, non-percent, non-underscore, non-dot, non-hyphen.
                // WebKit url-filter doesn't support alternation (|), so we use a character class
                // instead of the standard ([^...] | $) pattern. This slightly over-matches
                // (requires a separator char rather than accepting end-of-string) but is safe
                // because URLs virtually always have a separator after the domain.
                result += "[^a-zA-Z0-9_.%-]"
            case ".":
                result += "\\."
            case "+":
                result += "\\+"
            case "?":
                result += "\\?"
            case "{", "}", "(", ")", "[", "]":
                result += "\\\(ch)"
            case "\\":
                result += "\\\\"
            default:
                result += String(ch)
            }
        }

        if hasEndAnchor {
            result += "$"
        }

        // Validate the regex is not empty or trivially matching everything
        if result.isEmpty || result == ".*" {
            return nil
        }

        return result
    }

    // MARK: - Options Parsing

    private struct ParsedOptions {
        var thirdParty: Bool = false
        var firstParty: Bool = false
        var strictParty: Bool = false
        var resourceTypes: [String] = []
        var ifDomains: [String] = []
        var unlessDomains: [String] = []
        var unsupported: Bool = false
        var redirectResource: String? = nil
        var isRedirectRule: Bool = false
        var isImportant: Bool = false
        var isBadFilter: Bool = false
        var removeparam: String? = nil
        var methods: [String]? = nil
        var toDomains: [String]? = nil
        var denyallowDomains: [String]? = nil
    }

    private static let supportedResourceTypes: Set<String> = [
        "script", "image", "stylesheet", "font",
        "media", "popup", "xmlhttprequest", "websocket",
        "subdocument", "other", "ping", "document"
    ]

    private static let wkResourceTypeMap: [String: String] = [
        "script": "script",
        "image": "image",
        "stylesheet": "style-sheet",
        "font": "font",
        "media": "media",
        "popup": "popup",
        "xmlhttprequest": "fetch",
        "websocket": "websocket",
        "subdocument": "document",
        "ping": "ping",
        "document": "document"
    ]

    private static func parseOptions(_ opts: String) -> ParsedOptions {
        var result = ParsedOptions()
        let parts = opts.components(separatedBy: ",")

        for part in parts {
            let opt = part.trimmingCharacters(in: .whitespaces).lowercased()

            if opt == "third-party" || opt == "3p" {
                result.thirdParty = true
            } else if opt == "~third-party" || opt == "~3p" || opt == "first-party" || opt == "1p" {
                result.firstParty = true
            } else if opt == "strict1p" {
                result.firstParty = true
                result.strictParty = true
            } else if opt == "strict3p" {
                result.thirdParty = true
                result.strictParty = true
            } else if opt == "important" {
                result.isImportant = true
            } else if opt == "badfilter" {
                result.isBadFilter = true
            } else if opt.hasPrefix("domain=") {
                let domainList = String(opt.dropFirst(7))
                for domain in domainList.components(separatedBy: "|") {
                    if domain.hasPrefix("~") {
                        result.unlessDomains.append(String(domain.dropFirst()))
                    } else {
                        result.ifDomains.append(domain)
                    }
                }
            } else if opt.hasPrefix("redirect-rule=") {
                result.redirectResource = String(opt.dropFirst(14))
                result.isRedirectRule = true
            } else if opt.hasPrefix("redirect=") {
                result.redirectResource = String(opt.dropFirst(9))
            } else if opt.hasPrefix("removeparam=") {
                result.removeparam = String(opt.dropFirst(12))
            } else if opt == "removeparam" {
                result.removeparam = "*"  // Remove all params
            } else if opt.hasPrefix("method=") {
                result.methods = String(opt.dropFirst(7)).components(separatedBy: "|")
            } else if opt.hasPrefix("to=") {
                result.toDomains = String(opt.dropFirst(3)).components(separatedBy: "|")
            } else if opt.hasPrefix("denyallow=") {
                result.denyallowDomains = String(opt.dropFirst(10)).components(separatedBy: "|")
            } else if supportedResourceTypes.contains(opt) {
                if let mapped = wkResourceTypeMap[opt] {
                    result.resourceTypes.append(mapped)
                }
            } else if opt.hasPrefix("~") {
                // Negated resource type — ignore
            } else if opt == "match-case" {
                // Supported but no special action needed at parse time
            } else if opt.hasPrefix("csp=") || opt.hasPrefix("permissions=") || opt.hasPrefix("replace=") || opt.hasPrefix("header=") {
                // WebKit hard limits — cannot implement
                result.unsupported = true
            }
        }

        return result
    }
}
