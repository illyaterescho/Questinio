import Foundation

public struct ProjectCodeFile: Identifiable, Sendable, Equatable {
    public var id: String { path }
    public let path: String
    public let text: String
    public var lines: [String] { text.components(separatedBy: "\n") }
    public init(path: String, text: String) { self.path = path; self.text = text }
}
public struct CodeSearchResult: Sendable {
    public let context: String
    public let files: [String]
    public let exactLine: Int?
}
public struct ProjectCodeIndex: Sendable {
    public let files: [ProjectCodeFile]
    public let rootName: String?
    private let contentTokens: [String: Set<String>]
    private let pathTokens: [String: Set<String>]
    public init(files: [ProjectCodeFile], rootName: String? = nil) {
        let sorted = files.sorted { $0.path < $1.path }
        self.files = sorted; self.rootName = rootName
        contentTokens = Dictionary(uniqueKeysWithValues: sorted.map { ($0.path, Self.tokens($0.text)) })
        pathTokens = Dictionary(uniqueKeysWithValues: sorted.map { ($0.path, Self.tokens($0.path)) })
    }
    private init(files: [ProjectCodeFile], rootName: String?, contentTokens: [String: Set<String>], pathTokens: [String: Set<String>]) {
        self.files = files; self.rootName = rootName; self.contentTokens = contentTokens; self.pathTokens = pathTokens
    }
    public func replacing(path: String, text: String) -> Self {
        guard let existing = files.first(where: { $0.path == path }), existing.text != text else { return self }
        let updated = files.map { $0.path == path ? ProjectCodeFile(path: path, text: text) : $0 }
        var tokens = contentTokens; tokens[path] = Self.tokens(text)
        return Self(files: updated, rootName: rootName, contentTokens: tokens, pathTokens: pathTokens)
    }
    public static let extensions: Set<String> = ["ts", "tsx", "js", "jsx", "html", "css", "scss", "json", "py", "swift", "java", "cpp", "c", "h", "cs", "sql", "md", "vue", "svelte"]
    public static func load(root: URL) throws -> Self {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .isDirectoryKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { throw CopilotError.message("Не вдалося прочитати папку") }
        let excluded: Set<String> = ["node_modules", "dist", "build", "coverage", "Vendor", "vendor", "Pods", "tmp", "output", "submission", "venv", "__pycache__"]
        var files: [ProjectCodeFile] = []; var bytes = 0
        for case let url as URL in walker {
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true { walker.skipDescendants(); continue }
            if values.isDirectory == true { if excluded.contains(url.lastPathComponent) { walker.skipDescendants() }; continue }
            guard values.isRegularFile == true, extensions.contains(url.pathExtension.lowercased()), !["package-lock.json", "pnpm-lock.yaml", "yarn.lock"].contains(url.lastPathComponent) else { continue }
            guard (values.fileSize ?? 0) <= 2_000_000 else { continue }
            if files.count >= 5000 || bytes + (values.fileSize ?? 0) > 30_000_000 { throw CopilotError.message("Проєкт завеликий: виберіть папку однієї лабораторної (до 5000 файлів / 30 MB)") }
            guard let text = try? String(contentsOf: url, encoding: .utf8), !text.contains("\0") else { continue }
            files.append(ProjectCodeFile(path: String(url.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(root.path.count + 1)), text: text)); bytes += text.utf8.count
        }
        return Self(files: files, rootName: root.lastPathComponent)
    }
    public static func requestedLine(_ question: String) -> Int? {
        let patterns = [#"(?i)(?:ряд(?:ок|ку|ки|ка|ці)|стр[а-яі]*|line)\s*(?:№|#)?\s*(\d{1,6})"#, #"(?i)(\d{1,6})\s*[-–]?\s*(?:х|их|й|ий|ій|го|ого|му|ому|тому|том|ом|ти|ї|ої|а|та)?\s*(?:ряд[а-яіїє]*|стр[а-яіїє]*)"#]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern), let match = expression.firstMatch(in: question, range: NSRange(question.startIndex..., in: question)), let range = Range(match.range(at: 1), in: question), let value = Int(question[range]), value > 0 else { continue }
            return value
        }
        return nil
    }
    /// The lab a question is about: “лаба 5”, “5 лабі”, “5-й лабі”, “п’ятій лабі”, “лабораторній роботі №5”, “lab-05”.
    public static func labNumber(_ question: String) -> Int? {
        let words = ["перш": 1, "друг": 2, "трет": 3, "четверт": 4, "п.?ят": 5, "шост": 6, "сьом": 7, "восьм": 8, "дев.?ят": 9, "десят": 10]
        for (stem, number) in words where question.range(of: "(?i)(?:^|[^а-яіїє])" + stem + #"[а-яіїє]*\s+лаб"#, options: .regularExpression) != nil { return number }
        let patterns = [#"(?i)(?:lab[-_ ]*|лаб[а-яіїє]*\s*(?:роб[а-яіїє]*\s*)?(?:№\s*)?)(\d{1,2})"#, #"(?i)(\d{1,2})\s*[-–]?\s*(?:х|й|ий|ій|ої|ї|а|та|ому|му)?\s*лаб"#]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern), let match = expression.firstMatch(in: question, range: NSRange(question.startIndex..., in: question)), let range = Range(match.range(at: 1), in: question), let value = Int(question[range]) else { continue }
            return value
        }
        return nil
    }
    /// “що ти робив у 6 лабі”: asks about the lab as a whole, with no specific thing to search for.
    static func asksLabOverview(_ question: String, query: Set<String>) -> Bool {
        let value = question.lowercased()
        let asks = ["що було", "що там", "що в ", "що у ", "про що", "розкажи", "опиши", "яке завдання", "яка тема", "що за лаб"].contains(where: value.contains)
            || value.range(of: #"(?:що|чим)\b.*(?:робив|робила|робили|зроблено|реаліз|писав|писала|писали|займа)"#, options: .regularExpression) != nil
        guard asks else { return false }
        let generic: Set<String> = ["робив", "робила", "робили", "зробив", "зробила", "зробили", "зроблено", "писав", "писала", "писали", "займався", "займалась", "займалися", "було", "там", "розкажи", "опиши", "про", "завдання", "тема", "яка", "яке", "чим", "реалізовано", "реалізував", "реалізувала", "реалізували", "цій", "цю", "цієї", "lab"]
        let wordsAboutTheLab = ["лаб", "робот", "перш", "друг", "трет", "четверт", "ят", "шост", "сьом", "восьм", "десят"]
        return query.subtracting(generic).allSatisfy { token in Int(token) != nil || wordsAboutTheLab.contains(where: token.hasPrefix) }
    }
    /// The README and the shape of the code: classes, methods, inputs and test names, never whole files.
    private static func labOverview(name: String, files: [ProjectCodeFile], budget: Int) -> String {
        let head = "Огляд \(name). Опиши, що в ній реалізовано, лише за цими даними; номери рядків точні.\n"
        let readme = files.first { URL(fileURLWithPath: $0.path).lastPathComponent.lowercased() == "readme.md" }.map { "README:\n" + String($0.text.prefix(1200)) + "\n" } ?? ""
        let sources = files.filter { !["css", "scss", "json", "md", "html"].contains(URL(fileURLWithPath: $0.path).pathExtension.lowercased()) && !$0.path.hasSuffix("main.ts") }
            .sorted { ($0.path.contains(".spec.") ? 1 : 0, $0.path) < ($1.path.contains(".spec.") ? 1 : 0, $1.path) }
        let others = files.filter { $0.path.hasSuffix(".html") && !$0.path.hasSuffix("index.html") }.map(\.path)
        func outline(_ file: ProjectCodeFile, limit: Int) -> String {
            let rows = file.lines.enumerated().filter { outlinePattern.firstMatch(in: $0.element, range: NSRange($0.element.startIndex..., in: $0.element)) != nil }.prefix(limit)
            return ([file.path] + rows.map { "\($0.offset + 1): " + String($0.element.trimmingCharacters(in: .whitespaces).prefix(100)) }).joined(separator: "\n")
        }
        var result = ""
        for limit in [14, 8, 4, 2, 1, 0] {
            result = head + readme + sources.map { outline($0, limit: limit) }.joined(separator: "\n\n") + (others.isEmpty ? "" : "\n\nШаблони: " + others.joined(separator: ", "))
            guard result.count <= budget else { continue }
            // Method names alone say little about a small lab, so add whole files while they fit.
            for file in sources.filter({ !$0.path.contains(".spec.") }).sorted(by: { $0.text.count > $1.text.count }) {
                let block = "\n\nКод \(file.path):\n" + file.text
                if result.count + block.count <= budget { result += block }
            }
            return result
        }
        return String(result.prefix(budget))
    }
    private static let outlinePattern = try! NSRegularExpression(pattern: #"^\s*(?:(?:export|default|abstract|public|private|protected|static|async|override)\s+)*(?:(?:class|interface|type|enum|function|def|func|struct)\s+\w|(?:get|set)\s+\w+\s*\(|(?!if\b|for\b|while\b|switch\b|catch\b|return\b|function\b|constructor\b)\w+\s*\([^)]*\)\s*(?::\s*[^{=;]+)?\{\s*$)|^\s*@(?:Input|Output|Injectable|Component)\b|^\s*(?:describe|it|test)\s*\(|^\s*export\s+const\s+\w"#)
    /// Speech recognition writes a spoken “30-31” as 3031. Only a number past the end of the file is read this way.
    public static func spokenRange(_ number: Int, lineCount: Int) -> ClosedRange<Int>? {
        let digits = String(number)
        for cut in 1..<max(1, digits.count) {
            let tail = digits.dropFirst(cut)
            guard !tail.hasPrefix("0"), let first = Int(digits.prefix(cut)), let last = Int(tail), first < last, last <= lineCount, last - first <= 20 else { continue }
            return first...last
        }
        return nil
    }
    private static func tokens(_ value: String) -> Set<String> {
        Set(value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 3 && !["const", "let", "return", "this", "string", "number", "public", "private", "import", "from", "class", "void", "true", "false", "undefined", "код", "code", "function"].contains($0) })
    }
    public static func namedSymbol(_ question: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\b[A-Za-z_][A-Za-z0-9_]{3,}\b"#) else { return nil }
        return regex.matches(in: question, range: NSRange(question.startIndex..., in: question))
            .compactMap { Range($0.range, in: question).map { String(question[$0]) } }
            .first { symbol in symbol.dropFirst().contains(where: { $0.isUppercase }) || symbol.contains("_") }
    }
    public func matchVisible(source: String, visible: String) -> String? {
        let candidates = files.filter { source.contains(URL(fileURLWithPath: $0.path).lastPathComponent) }
        if candidates.count == 1 { return candidates[0].path }
        let query = Self.tokens(visible)
        guard query.count >= 4 else { return nil }
        let pool = candidates.isEmpty ? files : candidates
        let ranked = pool.map { ($0.path, (contentTokens[$0.path] ?? []).intersection(query).count) }.sorted { $0.1 > $1.1 }
        guard let first = ranked.first, first.1 >= 4, ranked.count == 1 || first.1 >= ranked[1].1 + 2 else { return nil }
        return first.0
    }
    public static func refersToCurrentCode(_ question: String) -> Bool {
        // A named method is a more precise target than the current cursor.
        let identifier = #"\b[a-z_][A-Za-z0-9_]*[A-Z][A-Za-z0-9_]*\b|\b[a-z_][A-Za-z0-9_]*\s*\("#
        if let expression = try? NSRegularExpression(pattern: identifier),
           expression.firstMatch(in: question, range: NSRange(question.startIndex..., in: question)) != nil { return false }
        let value = question.lowercased()
        return ["тут", "цей ", "ця ", "цю ", "цьому ", "цій ", "показан", "відкрит", "зараз", "ось ", "от ", "в цьому", "в цій", "на екрані", "current", "this ", "here", "shown"].contains { value.contains($0) }
    }
    public func search(question: String, active: String?, visible: String = "", focusLine: Int? = nil, focusedSymbol: String? = nil, budget: Int = 7000) -> CodeSearchResult {
        let line = Self.requestedLine(question)
        let local = Self.refersToCurrentCode(question) && line == nil && focusLine != nil
        var query = Self.tokens(question)
        for (stem, aliases) in [("дисперс", ["variance"]), ("асиметр", ["skewness"]), ("ексцес", ["kurtosis"]), ("довір", ["confidence_table", "confidence", "quantile"]), ("похиб", ["standard_errors", "se"]), ("емпір", ["ecdf"]), ("штер", ["sturges_classes"]), ("гістограм", ["build_histogram"]), ("логариф", ["log"]), ("обернен", ["inverse_cdf"]), ("дельт", ["delta_metric"])] where question.lowercased().contains(stem) { query.formUnion(aliases.flatMap { Self.tokens($0) }) }
        for (stem, aliases) in [("збереж", ["storage", "save", "persist"]), ("зберіг", ["storage", "save", "persist"]), ("перезавантаж", ["load", "storage", "json"]), ("вибран", ["favorites", "favorite"]), ("погод", ["weather"]), ("температур", ["temperature", "celsius", "fahrenheit"]), ("видал", ["remove", "delete"]), ("дода", ["add"]), ("завантаж", ["load"]), ("спостерігач", ["subject", "observable"])] where question.lowercased().contains(stem) { query.formUnion(aliases) }
        if !query.isDisjoint(with: ["апі", "api", "http", "https", "fetch", "request"]) || ["підключ", "запит"].contains(where: question.lowercased().contains) { query.formUnion(["api", "axios", "http", "https", "httpclient", "fetch", "apikey", "baseurl", "weatherapi"]) }
        var labNumber = Self.labNumber(question)
        // “у цій лабі” is the lab of the open file.
        if labNumber == nil, question.range(of: #"(?i)(?:цій|цю|цієї)\s+лаб"#, options: .regularExpression) != nil, let active, active.hasPrefix("lab-") { labNumber = Int(active.dropFirst(4).prefix(2)) }
        let scope = labNumber.map { number -> [ProjectCodeFile] in
            let name = String(format: "lab-%02d", number)
            return rootName?.lowercased() == name ? files : files.filter { $0.path.hasPrefix(name + "/") }
        } ?? files
        let named = scope.filter { question.localizedCaseInsensitiveContains($0.path) || question.localizedCaseInsensitiveContains(URL(fileURLWithPath: $0.path).lastPathComponent) }
        if let labNumber, rootName?.lowercased().hasPrefix("lab-") != true {
            let labName = String(format: "lab-%02d", labNumber)
            if scope.isEmpty {
                let labs = Set(files.compactMap { $0.path.split(separator: "/").first.map(String.init) }).filter { $0.hasPrefix("lab-") }.sorted()
                return CodeSearchResult(context: "Лабораторної \(labName) у папці немає. Є: \(labs.joined(separator: ", ")).", files: [], exactLine: line)
            }
            if line == nil, Self.asksLabOverview(question, query: query) {
                return CodeSearchResult(context: Self.labOverview(name: labName, files: scope, budget: budget), files: scope.map(\.path), exactLine: nil)
            }
        }
        var selected: [ProjectCodeFile]
        if line != nil {
            if named.count == 1 { selected = named }
            else if named.count > 1 { selected = named }
            else if let active, let file = scope.first(where: { $0.path == active }) { selected = [file] }
            else if scope.count == 1 { selected = scope }
            else { return CodeSearchResult(context: "Файл для номера рядка не визначено. Уточни лабораторну та файл; не вигадуй код рядка.", files: [], exactLine: line) }
        } else if local, let active, let file = scope.first(where: { $0.path == active }) { selected = [file] }
        else {
            let visibleTokens = Self.tokens(visible)
            let namedPaths = Set(named.map(\.path))
            let symbol = Self.namedSymbol(question)
            let declaration = symbol.flatMap { try? NSRegularExpression(pattern: #"(?m)\b(?:function|class|interface|type|const|let|def|func)\s+"# + NSRegularExpression.escapedPattern(for: $0) + #"\b"#) }
            let definitionPaths = Set(scope.filter { file in
                guard let declaration else { return false }
                return declaration.firstMatch(in: file.text, range: NSRange(file.text.startIndex..., in: file.text)) != nil
            }.map(\.path))
            let ranked = scope.map { file -> (ProjectCodeFile, Int) in
                let tokens = contentTokens[file.path] ?? []
                var score = tokens.intersection(query).count * 3
                score += (pathTokens[file.path] ?? []).intersection(query).count * 8
                if file.path == active && !question.lowercased().contains("де ") && !question.lowercased().contains("знайди") { score += 10 }
                if namedPaths.contains(file.path) { score += 40 }
                if definitionPaths.contains(file.path) { score += 80 }
                score += min(5, tokens.intersection(visibleTokens).count)
                return (file, score)
            }.sorted { $0.1 == $1.1 ? $0.0.path < $1.0.path : $0.1 > $1.1 }
            let directDefinition = ["визначено", "реалізовано", "що робить", "що повертає", "який return", "де в коді"].contains { question.lowercased().contains($0) }
            if directDefinition && definitionPaths.count == 1, let definition = ranked.first(where: { definitionPaths.contains($0.0.path) }) {
                selected = [definition.0]
            } else {
                selected = ranked.filter { $0.1 > 0 }.prefix(3).map { $0.0 }
            }
        }
        if selected.isEmpty, labNumber != nil, !scope.isEmpty {
            return CodeSearchResult(context: "У коді лабораторної прямих збігів не знайдено.\n" + Self.labOverview(name: String(format: "lab-%02d", labNumber ?? 0), files: scope, budget: budget), files: [], exactLine: line)
        }
        var remaining = max(500, budget); var blocks: [String] = []; var paths: [String] = []
        if line != nil && selected.count > 1 { blocks.append("Однакова назва файлу в кількох лабораторних. Уточни файл або поясни неоднозначність.") }
        for file in selected {
            let lines = file.lines
            var ranges: [ClosedRange<Int>] = []
            var target = line
            var spokenNote = ""
            if let line {
                if line > lines.count {
                    guard let spoken = Self.spokenRange(line, lineCount: lines.count) else { blocks.append("Файл \(file.path): \(lines.count) рядків; рядка \(line) немає."); paths.append(file.path); continue }
                    ranges = [max(1, spoken.lowerBound - 10)...min(lines.count, spoken.upperBound + 10)]
                    target = spoken.lowerBound
                    spokenNote = "«\(line)» у розпізнаному мовленні означає рядки \(spoken.lowerBound)–\(spoken.upperBound). "
                } else { ranges = [max(1, line - 10)...min(lines.count, line + 10)] }
            } else if local, file.path == active, let focusLine, (1...lines.count).contains(focusLine) {
                ranges = [max(1, focusLine - 4)...min(lines.count, focusLine + 8)]
            } else {
                let hits = lines.enumerated().filter { !Self.tokens($0.element).intersection(query).isEmpty }.prefix(3).map { $0.offset + 1 }
                if hits.isEmpty || file.text.count < remaining / 2 { ranges = [1...max(1, min(lines.count, 100))] }
                else { ranges = hits.map { max(1, $0 - 12)...min(lines.count, $0 + 18) } }
            }
            var numbers: Set<Int> = []
            for range in ranges { numbers.formUnion(range) }
            var block = "Файл: \(file.path) · повний файл має \(lines.count) рядків. "
            if local, file.path == active, let focusLine {
                block += "Поточна позиція: рядок \(focusLine). "
                if let focusedSymbol, !focusedSymbol.isEmpty { block += "Активний символ IDE: \(focusedSymbol). " }
            }
            block += spokenNote + "Фрагменти з точними номерами:\n"
            let order = target.map { target in numbers.sorted { abs($0 - target) < abs($1 - target) } } ?? numbers.sorted()
            var rows: [Int: String] = [:]; var used = block.count
            for number in order {
                let original = lines[number - 1]
                let content = String(original.prefix(1500)) + (original.count > 1500 ? " …[довгий рядок скорочено]" : "")
                let row = "\(number): \(content)\n"
                if used + row.count > remaining { continue }
                rows[number] = row; used += row.count
            }
            block += rows.keys.sorted().compactMap { rows[$0] }.joined()
            guard block.count <= remaining else { continue }
            blocks.append(block); paths.append(file.path); remaining -= block.count + 2
            if remaining < 150 { break }
        }
        return CodeSearchResult(context: blocks.joined(separator: "\n\n"), files: paths, exactLine: line)
    }
}
