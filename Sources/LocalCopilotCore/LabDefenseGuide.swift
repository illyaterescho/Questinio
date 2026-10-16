import Foundation
import CryptoKit

/// Reviewed oral-defense examples. Retrieved as local evidence, never executable
/// instructions or a substitute for the currently connected laboratory source.
public enum LabDefenseGuide {
    public static let reviewedFiles: [String: String] = [
        "math_statistics.py": "4f1d66458919ab963cf56dcb579c43198531742236d09cf0964b8d91279d131f",
        "data_processing.py": "8e1d6a796cde118c99f55f437ac61a388a7296b3bb7593a926f0815b3fe34e9e",
        "distributions.py": "a4e6017f38f0ec3cfa74858e5bf4e8bbeeaef499f508abbd6c42873f46ee56c8",
        "simulation.py": "933617b13709b96140d0c6e32d81d990047111088662979671c0a48a70fd26b2",
        "README.md": "f298e7820af9c30a76fddcb8a7dd7d7ff21d0bd6ede8649c5ceb2dd7b3874bb7",
        "LR2_REPORT.md": "925a66c6c81a35b9c08951198bdc65f85353e8b6f8840d2ceb65dfc9cd2d4487"
    ]
    public static func matchesReviewedSources(_ files: [ProjectCodeFile]) -> Bool {
        matchesFingerprints(files, expected: reviewedFiles)
    }
    static func matchesFingerprints(_ files: [ProjectCodeFile], expected: [String: String]) -> Bool {
        !expected.isEmpty && expected.allSatisfy { path, digest in
            guard let file = files.first(where: { $0.path == path }) else { return false }
            return SHA256.hash(data: Data(file.text.utf8)).map { String(format: "%02x", $0) }.joined() == digest
        }
    }
    public static func exactCard(question: String) -> Card? {
        // Preserve all words (especially negation), numbers and math operators.
        // A paraphrase or changed condition must go through grounded generation.
        let key = exactKey(question)
        return cards.first { exactKey($0.question) == key }
    }
    private static func exactKey(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
            .components(separatedBy: CharacterSet(charactersIn: "?!.;,:`*\"«»").union(.whitespacesAndNewlines))
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
    public struct Card: Sendable {
        public let id: Int
        public let question: String
        public let answer: String
        public let aliases: String
        public let source: String
    }
    public static let cards: [Card] = [
        Card(id: 1, question: "Чому для вибору закону розподілу недостатньо лише порівняти A та E?", answer: "A — асиметрія, E — ексцес; вони описують лише окремі властивості форми розподілу. Різні закони можуть мати схожі A та E, тому додатково порівнюємо емпіричну й теоретичну функції розподілу за статистикою D.", aliases: "асиметрія ексцес недостатньо форма два закони схожі", source: "distributions.py: analyze_data"),
        Card(id: 2, question: "Чому саме найменше D означає кращий закон?", answer: #"Бо \(D=\sup_x|F_n(x)-F(x)|\) — найбільша відстань між емпіричною й теоретичною функціями розподілу. Чим менше D, тим ближча модель до даних за цим критерієм. Це вибір серед перевірених моделей, а не доказ точного закону."#, aliases: "мінімальне найменша відстань де статистика краща модель", source: "distributions.py: calc_D, analyze_data"),
        Card(id: 3, question: "Чому у формулі D треба враховувати обидві сторони стрибка ECDF?", answer: #"Бо емпірична функція розподілу ступінчаста, і найбільша різниця може бути до або після стрибка. Для впорядкованих даних рахуємо \(D^+=\max_i(i/N-F(x_i))\), \(D^-=\max_i(F(x_i)-(i-1)/N)\), а потім \(D=\max(D^+,D^-)\)."#, aliases: "д плюс д мінус екдф есідіеф сходинка стрибок ліворуч праворуч", source: "distributions.py: calc_D"),
        Card(id: 4, question: "Чому в твоєму варіанті обрано Uniform, а не Normal?", answer: #"У контрольному прогоні очищених даних ліфта ЛР2 Uniform має \(D\approx0.103014\), а Normal — \(D\approx0.157374\). Тому серед трьох моделей обрано Uniform. Довірчі інтервали A/E узгоджуються з обома законами, тож самі A/E їх тут не розрізняють."#, aliases: "уніформ нормал рівномірний нормальний обраний вибрали 0.103 0.157", source: "README.md, LR2_REPORT.md: очищений data/lr2_variant11.xlsx, заміна середнім періоду"),
        Card(id: 5, question: "Чому Exponential відкидається ще до аналізу D?", answer: "Для Exponential теоретично A=2 та E=6, а в очищених даних ліфта ці значення не входять у відповідні довірчі інтервали. Тому за формою ця модель не узгоджується з даними. Код усе одно обчислює D для всіх допустимих моделей; Exponential тут має D≈0.240365.", aliases: "експоненціальний експоненшал відхиляємо відкинули 2 6", source: "distributions.py: analyze_data; README.md"),
        Card(id: 6, question: "Що фізично означають параметри a і b для Uniform?", answer: #"a і b — нижня та верхня межі інтервалу рівномірної моделі. Усередині нього щільність стала: \(f(x)=1/(b-a)\). Це межі обраної моделі, а не доведені фізичні межі всіх можливих очікувань ліфта."#, aliases: "а бе межі границі рівномірного параметри зміст", source: "distributions.py: pdf, estimate_parameters"),
        Card(id: 7, question: "Чому a і b не дорівнюють просто мінімальному і максимальному значенню вибірки?", answer: #"Бо в цій програмі використано оцінювання за моментами: \(\hat a=\bar x-\sqrt3S\), \(\hat b=\bar x+\sqrt3S\). Параметри обчислюються через вибіркове середнє і S, а не через min та max."#, aliases: "метод моментів мінімум максимум оцінка меж не min max", source: "distributions.py: estimate_parameters"),
        Card(id: 8, question: "Чому параметри з реальних даних стають θ₀?", answer: #"Оцінені за реальними даними параметри фіксуємо як \(\theta_0\) моделі, з якої генеруємо штучні вибірки. У симуляції це відомий еталон, але для реального процесу вони залишаються оцінками, а не відомими істинними параметрами."#, aliases: "тета нуль тета нульове еталонні початкові параметри реальних", source: "gui.py, simulation.py: run_experiment"),
        Card(id: 9, question: "У чому різниця між θ₀ і θ̂?", answer: #"\(\theta_0\) — фіксований еталонний параметр моделі симуляції. \(\hat\theta\) — його оцінка за конкретною випадковою вибіркою, тому вона змінюється від вибірки до вибірки."#, aliases: "тета нуль тета з шапочкою тета хат оцінка еталон різниця", source: "simulation.py: run_experiment"),
        Card(id: 10, question: "Навіщо взагалі генерувати штучні вибірки, якщо в нас уже є реальні дані?", answer: #"Щоб перевірити метод оцінювання в контрольованих умовах, де параметри \(\theta_0\) відомі. Тоді можемо виміряти похибку оцінок, їхній розкид і частку помилкових відхилень гіпотези."#, aliases: "синтетичні вибірки навіщо симуляція контрольовані умови", source: "simulation.py: run_experiment"),
        Card(id: 11, question: "Чому використовується метод зворотної функції?", answer: #"Це спосіб генерації, реалізований за завданням лабораторної: беремо базове \(U\in[0,1)\) і обчислюємо \(X=F^{-1}(U)\). Так отримуємо випадкову величину потрібного закону через його обернену функцію розподілу."#, aliases: "обернена інверсна функція inverse cdf метод генерації", source: "distributions.py: inverse_cdf; simulation.py: generate_sample; LR2_REPORT.md"),
        Card(id: 12, question: "Чому не можна просто використати готовий random.uniform?", answer: #"Математично готовий генератор Uniform придатний, але в цій лабораторній треба показати саме алгоритм оберненого перетворення. Тому генератор дає лише базове U, а \(X=a+(b-a)U\) обчислюємо самі."#, aliases: "готовий генератор рандом уніформ random.uniform numpy fit", source: "simulation.py: generate_sample; README.md"),
        Card(id: 13, question: "Чому для Uniform формула саме X=a+(b-a)U?", answer: #"\(U\in[0,1)\), множення на \(b-a\) задає потрібну ширину, а додавання a зсуває інтервал. Тому \(X=a+(b-a)U\) має рівномірний закон на інтервалі від a до b."#, aliases: "формула генерації розтягує зсуває ікс а бе ю", source: "distributions.py: inverse_cdf"),
        Card(id: 14, question: "Чому seed=42 не впливає на теоретичний результат?", answer: "Seed задає відтворювану послідовність псевдовипадкових чисел. Він змінює конкретні вибірки й числові результати експерименту, але не заданий закон розподілу та його теоретичні характеристики.", aliases: "сід сiд зерно 42 відтворюваність random seed", source: "simulation.py: default_rng, validate_seed"),
        Card(id: 15, question: "У чому різниця між N і R?", answer: "N — кількість спостережень в одній вибірці. R — кількість повторень експерименту, тобто скільки таких вибірок генеруємо для кожного N.", aliases: "ен ер обсяг розмір вибірки кількість повторень різниця", source: "simulation.py: run_experiment"),
        Card(id: 16, question: "Чому при N=1000 оцінки стабільніші, ніж при N=50?", answer: #"Більша вибірка зменшує випадкові коливання оцінок. У використаних формулах SE спадає як \(1/\sqrt N\), тому за N=1000 очікуваний розкид менший, ніж за N=50."#, aliases: "1000 50 оцінки стабільніші точність великий обсяг", source: "distributions.py: theoretical_parameter_se"),
        Card(id: 17, question: "Що показує SE?", answer: "SE — стандартна похибка оцінки параметра: типовий масштаб її випадкових коливань між вибірками. У програмі є теоретичне SE за θ₀ та оцінене SE, обчислене з параметрів конкретної вибірки.", aliases: "ес і сі стандартна похибка standard error значення", source: "distributions.py: theoretical_parameter_se, parameter_standard_errors"),
        Card(id: 18, question: "Чим SE відрізняється від SD θ̂?", answer: #"Теоретичне SE — розкид оцінки, передбачений формулою моделі. \(SD(\hat\theta)\) — емпіричний розкид оцінок за R симуляціями. Окремо програма рахує середнє оцінене SE за цими вибірками."#, aliases: "se sd есі есді тета хат розкид теоретична емпірична різниця", source: "simulation.py: theoretical_se_at_theta0, sd_theta_hat, mean_estimated_se"),
        Card(id: 19, question: "Навіщо порівнювати теоретичний SE і емпіричний SD?", answer: "Щоб перевірити, чи формула стандартної похибки описує фактичний розкид оцінок у симуляціях. Їхня близькість підтримує придатність формули для цього експерименту; помітна різниця потребує перевірки наближення та реалізації.", aliases: "se sd порівняння звірити відповідність формули фактичний розкид", source: "simulation.py: run_experiment; LR2_REPORT.md"),
        Card(id: 20, question: "Чому mean(t) має бути близьким до нуля?", answer: #"У правильній моделі за малого зміщення оцінки очікуємо, що \(t=(\theta_0-\hat\theta)/SE(\hat\theta)\) у середньому буде близьким до нуля. Це орієнтир перевірки: сама незміщеність оцінки ще не гарантує точний нуль після ділення на випадкове SE."#, aliases: "середнє т mean t нуль зміщення нормування", source: "simulation.py: mean_t, ts"),
        Card(id: 21, question: "Чому SD(t) має бути близьким до 1?", answer: #"Ділення на SE приводить розкид статистики до масштабу одиниці. Для точного \(t_\nu\) при \(\nu>2\) стандартне відхилення дорівнює \(\sqrt{\nu/(\nu-2)}\), а не рівно 1. У нашому експерименті Uniform близькість SD(t) до 1 — перевірка наближення."#, aliases: "sd t есді т одиниця розкид статистики нормування", source: "simulation.py: sd_t; наближений T-експеримент Uniform"),
        Card(id: 22, question: "Чому reject H₀ % має бути близьким до α·100%?", answer: "За правильної H₀ і коректно відкаліброваного критерію ймовірність хибного відхилення дорівнює α. Тому очікуємо частку поблизу α·100%, але не точний збіг. Для Uniform критерій наближений, а R=400 додатково дає випадковий шум і крок частки 0.25%.", aliases: "reject h0 відсоток відхилень альфа частка 1 відсоток", source: "simulation.py: reject_percent; LR2_REPORT.md"),
        Card(id: 23, question: "Що означає помилка першого роду?", answer: "Це відхилення нульової гіпотези H₀, коли вона насправді правильна. У симуляції вибірки генеруємо з параметром θ₀, тому хибне відхилення H₀ про цей параметр є помилкою першого роду.", aliases: "перший рід type i error хибне відхилення", source: "simulation.py: run_experiment"),
        Card(id: 24, question: "Чому для α=0.01 рівень довіри γ=0.99?", answer: #"Бо рівень довіри пов'язаний із рівнем значущості формулою \(\gamma=1-\alpha\). За \(\alpha=0.01\) отримуємо \(\gamma=0.99\), тобто 99%."#, aliases: "альфа гамма 0.01 0.99 довіра значущість", source: "simulation.py: gamma; math_statistics.py: confidence_table"),
        Card(id: 25, question: "Що таке число ступенів вільності ν=N-1?", answer: #"Після оцінювання середнього сума відхилень від нього дорівнює нулю, тому незалежними залишаються N−1 відхилень. У програмі \(\nu=N-1\) використано для квантиля Стьюдента; для Uniform це частина прийнятого наближення."#, aliases: "ню ню ен мінус один ступені свободи вільності", source: "simulation.py: nu, tcrit"),
        Card(id: 26, question: "Чому використовується саме T-розподіл, а не нормальний?", answer: "Коли невідоме стандартне відхилення оцінюємо за вибіркою, класична статистика середнього нормальної вибірки має розподіл Стьюдента. У цій програмі квантиль Стьюдента застосовано й до оцінок параметрів Uniform як навчальне наближення; точного T-розподілу для них це не гарантує.", aliases: "t тест т критерій стьюдент замість нормального невідома дисперсія", source: "simulation.py: tcrit; LR2_REPORT.md; NIST confidence limits for the mean"),
        Card(id: 27, question: "Що буде, якщо збільшити R з 400 до 4000?", answer: #"Теоретично більше повторень зменшить шум підсумків симуляції: похибка Монте-Карло спадає приблизно як \(1/\sqrt R\). Окремі оцінки за фіксованого N точнішими від цього не стануть. Зараз код дозволяє лише R від 200 до 500, тому 4000 потребує зміни перевірки вводу."#, aliases: "4000 збільшення r ер повторень монте карло", source: "simulation.py: run_experiment, validation 200<=r<=500"),
        Card(id: 28, question: "Що буде, якщо збільшити N, але залишити R=400?", answer: "Оцінки в кожній вибірці зазвичай стануть точнішими, бо збільшиться її обсяг. Кількість повторень залишиться R=400; стабільність підсумків Монте-Карло через число повторень окремо не покращиться.", aliases: "збільшення n незмінне r 400 розмір обсяг повторення", source: "simulation.py: run_experiment"),
        Card(id: 29, question: "Чому RMSE зменшується зі збільшенням N?", answer: #"\(RMSE=\sqrt{\operatorname{mean}((\hat\theta-\theta_0)^2)}\) враховує і зміщення, і випадковий розкид оцінки. Для використаних оцінок за більшого N очікуємо меншу похибку. У скінченній симуляції монотонне зменшення кожного результату не гарантоване."#, aliases: "рмсе ер ем ес і середньоквадратична похибка збільшення n", source: "simulation.py: delta_metric"),
        Card(id: 30, question: "Чому δ(N) у твоїй програмі треба пояснювати обережно?", answer: "Бо методичка не задає окремої формули δ. У програмі δ(N) визначено як емпіричний RMSE оцінки відносно θ₀; це робоче визначення реалізації. Без заданого порога δ не можна назвати потрібний обсяг вибірки.", aliases: "дельта ен delta n методичка робоча формула поріг", source: "simulation.py: delta_metric, required_n; LR2_REPORT.md"),
        Card(id: 31, question: "Що буде, якщо дані після очищення сильно зміняться?", answer: "Зміняться вибіркові характеристики, оцінки параметрів і відстані D; може змінитися й обраний закон. Тому висновок про модель завжди пов'язуємо з конкретними даними та способом очищення.", aliases: "зміна очищення дані інший закон результат", source: "data_processing.py; distributions.py: analyze_data"),
        Card(id: 32, question: "Чому очищення даних критично важливе перед вибором закону?", answer: "Технічна аномалія може різко спотворити середнє, дисперсію, A/E та вибір моделі. У ЛР2 таким записом є 900 секунд, але причину корекції визначаємо за журналом подій, а не лише за величиною числа.", aliases: "перед вибором очистити аномалія спотворює технічний збій", source: "data_processing.py; README.md: LR2 cleaning"),
        Card(id: 33, question: "Чому 900 секунд у вас замінюється, а не лишається?", answer: "У ЛР2 журнал пов'язує 900 с о 13:30 зі збоєм датчика дверей/обліку; значення також перевищує межу 73 с. Тому в контрольному прогоні його трактовано як технічний запис і замінено середнім дня 42.81818182 с. Самого перевищення межі недостатньо, щоб довести помилку.", aliases: "900 дев'ятсот девʼятсот секунд 13:30 73 датчик лишати заміна", source: "data_processing.py; README.md; LR2_REPORT.md"),
        Card(id: 34, question: "Що буде, якщо 900 вважати реальною подією?", answer: "Тоді треба залишити його та повторно обчислити характеристики й порівняння законів. Середнє, дисперсія та A/E суттєво зміняться; модель теж може змінитися. Висновок залежить від обґрунтованого трактування події.", aliases: "900 дев'ятсот реальна подія залишити наслідки", source: "README.md: raw/cleaned statistics; distributions.py"),
        Card(id: 35, question: "Чому після очищення ви не просто видаляєте рядки?", answer: "Заміна середнім відповідного періоду доби зберігає часову сітку та кількість спостережень. Це обраний спосіб контрольного прогону, а не єдиний допустимий: програма також підтримує видалення. Заміна може зменшити варіативність і не відновлює справжнє втрачене значення.", aliases: "видалення рядків імпутація часовий ряд середнє періоду доби", source: "data_processing.py: clean_data; README.md")
    ]

    // Small deterministic lexical retrieval, independent of model startup and
    // ordered by rare shared terms. Full matching answers remain in the prompt.
    public static func matching(_ question: String, limit: Int = 2) -> [Card] {
        let query = tokens(question)
        guard !query.isEmpty else { return [] }
        let documents = cards.map { tokens($0.question + " " + $0.aliases) }
        let normalized = tokens(question).sorted().joined(separator: " ")
        let ranked = cards.enumerated().compactMap { i, card -> (Card, Double)? in
            let shared = documents[i].intersection(query)
            let distinctive: Set<String> = ["se", "sd", "rmse", "seed", "тетан", "тетао", "дельт", "ecdf", "uniform", "exponential", "900", "4000"]
            guard shared.count >= 2 || (query.count <= 2 && !shared.intersection(distinctive).isEmpty) else { return nil }
            let exact = tokens(card.question).sorted().joined(separator: " ") == normalized
            let score = shared.reduce(0.0) { sum, term in
                let frequency = documents.filter { $0.contains(term) }.count
                return sum + log(1 + Double(cards.count) / Double(frequency))
            } / sqrt(Double(max(1, documents[i].count)))
            return (card, score + (exact ? 100 : 0))
        }.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 > $1.1 }
        guard let best = ranked.first, best.1 >= 0.45 else { return [] }
        return ranked.filter { $0.1 >= max(0.45, best.1 * 0.55) }.prefix(max(0, limit)).map(\.0)
    }
    public static func context(question: String) -> String {
        let selected = matching(question)
        guard !selected.isEmpty else { return "" }
        return "Перевірені зразки коротких відповідей для захисту ЛР2 (дані довідки):\n" + selected.map {
            "Питання: \($0.question)\nВідповідь: \($0.answer)\nДжерело: \($0.source)"
        }.joined(separator: "\n\n")
    }
    private static func tokens(_ text: String) -> Set<String> {
        var text = text.lowercased().replacingOccurrences(of: "θ₀", with: " тетануль ").replacingOccurrences(of: "θ̂", with: " тетаоцінка ")
        text = text.replacingOccurrences(of: #"\b(?:тета\s+(?:нуль|нульове)|theta0)\b"#, with: "тетануль", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\bтета\s+(?:з\s+шапочкою|хат)\b"#, with: "тетаоцінка", options: .regularExpression)
        text = text.replacingOccurrences(of: "α", with: " альфа ").replacingOccurrences(of: "γ", with: " гамма ").replacingOccurrences(of: "ν", with: " ню ").replacingOccurrences(of: "δ", with: " дельта ")
        let stop: Set<String> = ["чому", "саме", "таке", "означає", "буде", "якщо", "того", "коли", "тому", "навіщо", "взагалі", "просто", "можна", "треба", "нашій", "наша", "наших", "твоєму", "твоїй", "програмі", "поясни", "поясніть", "будь", "ласка", "лише", "лишається", "має", "бути", "при", "для", "між", "що", "чим", "про", "так", "але", "його", "вона", "вони", "вже", "та", "не", "нас", "вас", "тільки", "the", "why"]
        return Set(text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter {
            !stop.contains($0) && ($0.count >= 3 || ["a", "e", "d", "n", "r", "t", "sd", "se", "a0", "b0"].contains($0) || Int($0) != nil)
        }.map { $0.count >= 6 && $0.unicodeScalars.contains(where: { $0.value > 127 }) ? String($0.prefix(5)) : $0 })
    }
}
