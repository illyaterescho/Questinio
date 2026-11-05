import Foundation

public enum SpeechVocabulary {
    public static let profiles = ["General", "Frontend", "Backend", "Web", "CRM", "QA", "DevOps", "Mobile", "Data", "JavaScript", "Python", "Java", "CSharp", "PHP", "Go", "Cpp", "SQL", "Mathematics"]
    public static func label(_ profile: String) -> String {
        switch profile {
        case "General": "Усі теми"; case "Frontend": "Фронтенд"; case "Backend": "Бекенд"; case "Web": "Веб / фулстек"
        case "QA": "QA / тестування"; case "Mobile": "Мобільна розробка"; case "Data": "Data / ML"; case "JavaScript": "JavaScript / TypeScript"
        case "CSharp": "C# / .NET"; case "Cpp": "C++"; case "SQL": "SQL / бази даних"; case "Mathematics": "Математика"
        default: profile
        }
    }
    /// Tells the model which field ambiguous words belong to: «лід» in CRM is a lead.
    public static func hint(_ profile: String) -> String {
        profile == "General" || !profiles.contains(profile) ? "" : "Напрям розмови: \(label(profile)). Неоднозначні терміни тлумач у цьому напрямі."
    }
    public static func text(profile: String, custom: String) -> String {
        let terms: String
        switch profile {
        case "Mathematics": terms = "математична статистика, дисперсія, середнє, медіана, асиметрія, ексцес, довірчий інтервал, нульова гіпотеза, p-value, нормальний розподіл, рівномірний розподіл, експоненціальний розподіл, метод моментів, кореляція, регресія."
        case "JavaScript": terms = "JavaScript, TypeScript, Promise, async/await, callback, closure, event loop, React, Node.js, null, undefined, NaN, race condition, рейс кондишн, уникати, статична типізація, динамічна типізація."
        case "Python": terms = "Python, asyncio, coroutine, generator, decorator, GIL, list, tuple, dictionary, type hints, статична типізація, динамічна типізація."
        case "Frontend": terms = "фронтенд, HTML, CSS, JavaScript, TypeScript, DOM, React, Angular, Vue, Next.js, хук, useEffect, useState, стан, пропси, компонент, рендеринг, virtual DOM, SPA, SSR, Flexbox, Grid, адаптивна верстка, accessibility, Vite, webpack, CORS, localStorage, event loop, Promise."
        case "Backend": terms = "бекенд, API, REST, GraphQL, HTTP, статус-код, ендпоінт, мікросервіси, моноліт, Node.js, Express, NestJS, Spring, Django, ORM, індекс, транзакція, кешування, Redis, черга, Kafka, RabbitMQ, JWT, OAuth, автентифікація, авторизація, масштабування, ідемпотентність."
        case "Web": terms = "веб, фулстек, клієнт, сервер, HTTP, HTTPS, REST, API, cookie, сесія, JWT, CORS, DNS, CDN, кешування, React, Node.js, SQL, деплой, Docker, SPA, SSR, SEO, WebSocket, XSS, CSRF, SQL injection."
        case "CRM": terms = "CRM, Salesforce, HubSpot, Bitrix24, Zoho, Pipedrive, Dynamics 365, лід, угода, воронка продажів, pipeline, контакт, кастомні поля, сегментація, автоматизація, workflow, вебхук, інтеграція, API, імпорт, дедуплікація, конверсія, SLA, тікет, churn, Apex."
        case "QA": terms = "тестування, QA, тест-кейс, чек-лист, баг-репорт, severity, priority, регресія, smoke, юніт-тести, інтеграційні тести, e2e, Selenium, Playwright, Cypress, Postman, автоматизація, тест-план, Jira, мок, покриття, граничні значення, класи еквівалентності."
        case "DevOps": terms = "DevOps, CI/CD, Git, Docker, контейнер, образ, Kubernetes, под, деплой, GitHub Actions, Jenkins, Terraform, Ansible, AWS, Azure, GCP, Linux, Nginx, моніторинг, Prometheus, Grafana, логи, load balancer, secrets."
        case "Mobile": terms = "мобільна розробка, iOS, Android, Swift, SwiftUI, UIKit, Kotlin, Jetpack Compose, Flutter, Dart, React Native, життєвий цикл, ViewModel, MVVM, корутини, Combine, push-сповіщення, App Store, Google Play, Core Data, Room."
        case "Data": terms = "Data Science, машинне навчання, Python, pandas, NumPy, SQL, ETL, датасет, ознаки, модель, перенавчання, overfitting, регресія, класифікація, кластеризація, нейромережа, PyTorch, TensorFlow, accuracy, precision, recall, Spark."
        case "Java": terms = "Java, JVM, Spring Boot, Hibernate, JPA, Maven, Gradle, ООП, інтерфейс, абстрактний клас, колекції, HashMap, ArrayList, Stream API, лямбда, багатопоточність, synchronized, garbage collector, exception."
        case "CSharp": terms = "C#, .NET, ASP.NET Core, Entity Framework, LINQ, async/await, Task, делегат, подія, інтерфейс, generics, dependency injection, NuGet, garbage collector, value type, reference type, record."
        case "PHP": terms = "PHP, Laravel, Symfony, Composer, Eloquent, міграції, middleware, контролер, PDO, сесії, MySQL, namespace, trait, інтерфейс, PSR."
        case "Go": terms = "Go, Golang, горутина, канал, select, mutex, WaitGroup, context, інтерфейс, структура, slice, map, defer, panic, error, модулі, Gin."
        case "Cpp": terms = "C++, вказівник, посилання, пам'ять, new, delete, RAII, smart pointer, unique_ptr, shared_ptr, STL, vector, шаблони, віртуальні функції, конструктор, деструктор, move semantics, undefined behavior."
        case "SQL": terms = "SQL, PostgreSQL, MySQL, SELECT, JOIN, GROUP BY, HAVING, index, transaction, ACID, isolation, deadlock, індекс, транзакція."
        default: terms = "програмування, алгоритм, структура даних, масив, список, словник, хеш-таблиця, стек, черга, рекурсія, цикл, функція, метод, клас, об’єкт, інтерфейс, наслідування, поліморфізм, інкапсуляція, абстракція, ООП, патерн, компілятор, потік, асинхронність, race condition, рейс кондишн, API, REST, HTTP, JSON, база даних, SQL, транзакція, індекс, Git, Docker, Python, JavaScript, TypeScript, Java, C#, C++, Swift, Kotlin, Go, React, Angular, Node.js, Django, pandas, NumPy, null, exception, debug, статична типізація, динамічна типізація."
        }
        return String((terms + " " + custom).trimmingCharacters(in: .whitespacesAndNewlines).prefix(1500))
    }
}
public enum QuestionContextRouter {
    public static func isSelfContained(_ question: String) -> Bool {
        let normalized = question.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ProjectCodeIndex.namedSymbol(question) != nil { return true }
        let references = [" цей ", " ця ", " це ", " цього ", " цієї ", " тут", " там", " він ", " вона ", " воно ", " вони ", " раніше", " попередн", " той ", " такий ", " зараз"]
        if references.contains(where: { (" " + normalized + " ").contains($0) }) { return false }
        return ["що таке ", "чим відрізня", "поясни ", "яка різниця між ", "як працює "].contains { normalized.hasPrefix($0) }
    }
}
public struct SessionContext: Sendable {
    public struct Turn: Sendable, Equatable {
        public let speaker: String
        public let text: String
        public var rendered: String { "[\(speaker)] \(text)" }
    }
    public private(set) var turns: [Turn] = []
    public private(set) var archived = ""
    public var summary = ""
    public init() {}
    public mutating func append(speaker: String, text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        turns.append(Turn(speaker: speaker, text: String(text.prefix(12000))))
        while turns.count > 60 || turns.reduce(0, { $0 + $1.text.count }) > 24000 {
            archived += turns.removeFirst().rendered + "\n"
        }
        archived = String(archived.suffix(60000))
    }
    public var recent: String { turns.map(\.rendered).joined(separator: "\n") }
    public var questionSnapshot: Self {
        var snapshot = Self(); snapshot.summary = summary
        // Copy a bounded excerpt rather than the entire expanding archive into
        // every question in a 45-minute session. The journal holds the full text.
        var kept: [Turn] = []; var count = 0
        for turn in turns.reversed() {
            guard count + turn.text.count <= 10000 else { break }
            kept.insert(turn, at: 0); count += turn.text.count
        }
        snapshot.turns = kept; snapshot.archived = String(archived.suffix(2500))
        return snapshot
    }
    public mutating func consumeArchive(_ snapshot: String, summary: String) {
        guard archived.hasPrefix(snapshot) else { return }
        self.summary = String(summary.prefix(5000))
        archived.removeFirst(snapshot.count)
    }
    /// `rules` are the app's own per-question instructions: they are never cut, unlike the user-editable `prompt`.
    public func messages(prompt: String, rules: String = "", vacancy: String = "", history: [ChatMessage], question: String, code: String, topic: String, budget: Int, includeConversation: Bool = true) -> [ChatMessage] {
        let budget = max(1024, budget)
        let prompt = String(prompt.prefix(min(1400, budget / 2)))
        let system = prompt + (rules.isEmpty ? "" : "\n" + rules)
        let question = String(question.suffix(min(8000, budget / 4)))
        // Rules and the job posting come on top of the budget, so they never squeeze out the conversation.
        let vacancy = String(vacancy.prefix(2500))
        var left = budget + vacancy.count + (vacancy.isEmpty ? 0 : 20) - prompt.count - question.count - 100
        var blocks: [String] = []
        func add(_ label: String, _ text: String, maximum: Int, tail: Bool = false) {
            guard !text.isEmpty, left > label.count + 4 else { return }
            let count = min(maximum, left - label.count - 4)
            let value = tail ? String(text.suffix(count)) : String(text.prefix(count))
            blocks.append(label + "\n" + value); left -= label.count + value.count + 2
        }
        // Even “що таке X?” in an interview is answered for this job, so the posting is not tied to the conversation.
        add("Вакансія (дані):", vacancy, maximum: 2500)
        if includeConversation { add("Тема / умови розмови (дані):", topic, maximum: 1200) }
        add("Показаний код / OCR екрана (дані):", code, maximum: max(0, left * 70 / 100))
        if includeConversation {
            add("Пам’ять попередньої розмови (дані):", summary, maximum: min(4000, left / 2))
            add("Репліки розмови (дані):", String(archived.suffix(2000)) + "\n" + recent, maximum: max(0, left * 70 / 100), tail: true)
        }
        var kept: [ChatMessage] = []
        if includeConversation && recent.isEmpty {
            var index = history.count - 2
            while index >= 0 {
                let pair = Array(history[index...index + 1]); let size = pair.reduce(0) { $0 + $1.content.count }
                guard pair[0].role == "user", pair[1].role == "assistant", size <= left else { break }
                kept.insert(contentsOf: pair, at: 0); left -= size; index -= 2
            }
        }
        let user = blocks.joined(separator: "\n\n") + "\n\nПоточне питання (відповідай саме на нього):\n" + question
        return [ChatMessage(role: "system", content: system)] + kept + [ChatMessage(role: "user", content: user)]
    }
}
