# Questionio

Нова назва застосунку — Questionio. Папка вихідного коду, Xcode-схема,
Swift-модуль і каталог старих даних LocalCopilot збережені для сумісності.

## Захист коду у WebStorm

У Live session або Context / Code виберіть папку лабораторної. Окремий файл
вибирати не потрібно: Questionio шукає по всіх файлах папки й передає моделі
релевантні фрагменти. Шлях зберігається; індекс
перечитується кожні 8 секунд. UTF-8 файли читаються повністю: до 2 MB на файл,
5000 файлів / 30 MB на папку. Залежності, hidden folders, build/dist/coverage
та symlinks пропускаються. Модель отримує потрібні фрагменти з точними номерами.

«Точне читання WebStorm» потребує окремого Accessibility-дозволу та явного
увімкнення. Questionio читає тільки focused window com.jetbrains.WebStorm:
редактор, breadcrumbs, назву поточного методу, позицію курсора й, якщо WebStorm
надає її, видиму ділянку; AX-записів не виконує. Поки WebStorm відкритий,
Questionio оновлює файл кожні 3 секунди. Незбережений код редактора тимчасово
замінює файл у контексті питання. Запит «ця функція тут» прив’язується до
поточного методу й фрагмента біля курсора. Якщо кілька файлів однаково підходять
до питання про конкретний рядок, Questionio попросить уточнити файл.

«Що робить рядок 129?» працює і поза екраном. «Що робить цей рядок?» використовує
курсор, якщо WebStorm надає позицію. «Де у лабі 6 зберігається вибране?» шукає
по лабораторній. «Показати у WebStorm» відкриває знайдений файл; Go to Line
редактора дозволяє перейти до потрібного рядка.

Пошук коду вмикається для питань про рядок, відкриту функцію, файл, лабораторну,
реалізацію чи конкретний ідентифікатор, а також для пов’язаного уточнення.
Теоретичні питання без посилання на ваш код ідуть одразу до локальної моделі:
перед ними Questionio не перечитує редактор і не робить знімок екрана.
Терміни файлів індексуються при оновленні папки; для питання про номер рядка
передається короткий точний фрагмент. Час відповіді все одно залежить від
швидкості обраної локальної моделі.

Швидкий режим використовує встановлену qwen3.5:4b без thinking. Якщо її немає,
використовується обрана модель. Вимкнення повертає модель із Settings (тут 9B).
4B може відповісти швидше, але помилялася навіть у назві ключа зберігання. Для захисту
коду точніша 9B обрана основною. При відкритті Questionio автоматично завантажує
локальний Whisper, запускає встановлену Ollama.app, якщо вона вимкнена, і
прогріває вибрану модель. Точний код не
потребує Vision; знімки залишаються окремим fallback. Кеш можливостей моделі,
прогрів із робочим розміром контексту, keep_alive 2 год і фонове оновлення
прогріву кожні 10 хв зменшують затримку. Самодостатні питання не включають
попередню розмову; уточнення зберігають її, а пов’язані питання про код
повторно отримують точний знайдений фрагмент. Штучного ліміту відповіді немає;
контекст і ресурси моделі скінченні.

Whisper Large v3 Turbo та українська мова вибрані для розпізнавання. Словник
поповнюється назвами з відкритого файлу. Відоме спотворення «рейс кондишин»
виправляється на `race condition`; оригінальний текст залишається у Transcript.
Розпізнавання живого голосу все ще може помилятися: питання можна виправити
кнопкою-олівцем і повторити.

Попередній застосунок збережений у backups/LocalCopilot.app.disabled. Questionio
підписується постійним локальним сертифікатом; наступні збірки зберігають ту саму
ідентичність застосунку для дозволів macOS.

Нативний локальний асистент для Apple Silicon, macOS 14+. Реальні SwiftUI / AppKit,
ScreenCaptureKit, AVCaptureSession, WhisperKit Core ML, Ollama та SQLite.

## Запуск

```sh
open dist/Questionio.app
```

Проєкт: `LocalCopilot.xcodeproj`. Release ARM64 підписаний локально. Платний обліковий
запис Apple Developer не потрібен. Це локальний білд, без notarization для
поширення на інші комп'ютери.

```sh
./scripts/setup-local-signing.sh  # один раз на цьому Mac
./scripts/test.sh
./scripts/build.sh
open dist/Questionio.app
```

У репозиторії є вихідний код і змінена локальна копія WhisperKit. Локальні
моделі, приватний ключ підпису, історія розмов, тестові записи та готовий `.app`
не публікуються. На новому Mac потрібні Xcode, Homebrew OpenSSL та Ollama;
модель Whisper завантажується один раз у налаштуваннях застосунку, LLM — через
Ollama. Код не містить ваг моделей.

Перша збірка отримує SPM-залежності з GitHub. Кнопка **Download once & load**
завантажує безкоштовні багатомовні Whisper small/base та токенізатор із Hugging
Face. Під час розпізнавання мережевий fallback заборонений. Для цього Mac модель
small уже завантажена, займає близько 482 MB, шлях записано в налаштуваннях.

Ollama має працювати на `http://127.0.0.1:11434`. Якщо її сервер зупинено:

```sh
ollama serve
```

Список моделей читається з `/api/tags`, можливість thinking — з `/api/show`,
генерація — потоковий `/api/chat`. Немає хмарних API чи завантаження LLM.
Початкова модель нового профілю — `qwen3:4b`. У цьому середовищі її встановлений
шаблон іноді ігнорує `think=false` та повертає міркування в content. Програма
використовує Qwen `/no_think`, assistant prefix і парсер thinking-тегів, проте
поведінку самих ваг гарантувати неможливо. Для наскрізної перевірки явно вибрано
вже наявну `qwen3.5:4b`; встановлені моделі не змінені.

## Дозволи

У **System Settings → Privacy & Security** ввімкніть LocalCopilot у:

1. **Microphone**, для режимів Microphone / Both.
2. **Screen & System Audio Recording → System Audio Recording Only**, для нового Core Audio Tap (типово).
3. Верхній **Screen & System Audio Recording** потрібен для Context / Code, альтернативного ScreenCaptureKit та явного тесту приватності.

Core Audio Tap захоплює цифровий звук процесів, незалежно від навушників чи динаміків, і не потребує віртуального драйвера. Список програм для нього читається без запиту screen permission. Альтернативний ScreenCaptureKit використовує дисплейний фільтр для аудіо застосунків; програма
не реєструє screen output та не зберігає зображення екрана. Якщо macOS вимагає
перезапуск, закрийте LocalCopilot через **⌘Q** і відкрийте знову. Якщо програму
не видно у виборі файлу через «+», натисніть **⇧⌘G**, вставте
`/Users/illa/Desktop/ansverio/LocalCopilot/dist/`, Enter і виберіть `.app`.

Для локальних збірок один раз створіть ключ командою
`./scripts/setup-local-signing.sh`, після чого `./scripts/build.sh` підписує
кожну версію тим самим ключем. Ключ зберігається лише у вашій
`~/Library/Application Support/Questionio/Signing`, поза проєктом. Заміна або
видалення цього ключа змінить ідентичність застосунку й тоді macOS попросить
дозволи знову. Не потрібно вимикати SIP або Gatekeeper. Глобальні гарячі клавіші
працюють через Carbon.

## Використання

Для `lab1_iad_pharmacy` виберіть кореневу папку лабораторної. Після індексації
вмикається профіль «Захист ІАД · математична статистика» й словник Mathematics.
Математичні питання отримують перевірені формули ЛР1 та релевантні поточні файли,
навіть коли в питанні немає слова «код». Профіль розрізняє аптеку ЛР1 й ліфт ЛР2,
пояснює символи та припущення формул, а відповіді відображають LaTeX через KaTeX.
Він не читає вибраний у GUI лабораторної Excel/режим очищення: для неоднозначного
числового питання потрібна назва набору даних. Числа контрольного прогону
не вважаються поточним станом GUI. Профіль — перевірена довідка; після зміни
математичних домовленостей у лабораторній її теж слід оновити.

Для цього профілю додано [35 перевірених прикладів усного захисту](docs/DEFENSE_35_ANSWERS.md):
A/E і D, обидва боки ECDF, параметри Uniform, θ₀/θ̂, обернена функція, N/R,
SE/SD, T-експеримент, α/γ, RMSE/δ та очищення даних. Локальний пошук добирає
до двох релевантних прикладів, зокрема для перефразованих питань. Відповіді
налаштовано на 1–3 речення без вступів, із формулою за потреби. Ваги моделі не
змінюються: це довідка в контексті, а не нове навчання моделі; помилки LLM все ще можливі.
Для точного збігу з одним із 35 питань застосунок відразу видає перевірену відповідь
з позначкою «Перевірена відповідь». Цей шлях працює лише поки контрольні суми шести
перевірених файлів лабораторної збігаються; після змін використовується модель із
поточними файлами. Зміна умов питання, чисел, заперечення чи додаткова фраза також
повертає запит до моделі. Перефразування добирає приклади, але не гарантує готову відповідь.
Приклади враховують обмеження реалізації: R зараз дозволено в межах 200–500,
критерій для Uniform наближений, а δ є робочим RMSE. Явне питання про аптеку ЛР1
не отримує прикладів із числовими результатами ліфта ЛР2.

Перевірка відповідей встановленої моделі без аудіо й без запису історії:
`swift run LocalCopilotProbe --defense-eval` (усі 35) або
`swift run LocalCopilotProbe --defense-question 'Чим SE відрізняється від SD?'`.
Додайте `--use-reviewed`, щоб перевірити готові відповіді з контролем файлів, як у застосунку.
Вивід — JSONL із відповідями та часом першого токена/повної генерації.
Джерела й уточнення описані в [довідці профілю](docs/DEFENSE_GUIDE.md).

- Settings → Audio: виберіть **Core Audio Tap** (audio-only) або **ScreenCaptureKit**, потім **System Audio**, **Microphone** або **Both**;
  оновіть список застосунків і виберіть джерело, або всі програми.
- Whisper автоматично завантажується локально при відкритті програми; під час cold load показує Loading, потім Ready. Це не запуск мікрофона. Якщо модель ще не встановлена, завантажте її один раз у Settings → Speech Recognition.
  Для українських сесій рекомендується **Українська**: auto іноді плутає короткі
  українські фрази з російською. Англійські назви й IT-терміни розпізнаються в
  тому самому фрагменті, їхня точність залежить від вимови та моделі.
- Settings → AI Models: виберіть встановлену чат-модель.
- **Start** запускає звук. Якщо Both запускає лише одне джерело, інше показує
  точну помилку; працююче джерело та історія залишаються доступними.
- Сірий текст — проміжний. Після паузи фраза підтверджується. Automatic відповідає
  лише після завершення запитання; запитання користувача з мікрофона за замовчуванням
  не викликають генерацію. Це можна ввімкнути окремо.
- **Generate Answer** працює з введеним текстом, або останньою завершеною фразою.
  «Питання діалогу» показує до 600 останніх питань у межах поточної сесії,
  навіть коли Automatic answers вимкнено. Натискання запускає відповідь із
  збереженим на момент питання контекстом діалогу. У floating-вікні є меню питань.
  Перемикач Automatic answers вимкніть для відповідей лише за кліком.
  **Cancel** скасовує потік. Після готової відповіді зберігається наступне очікуване
  запитання, якщо воно надійшло під час генерації. Контекст включає попередні пари
  запитання/відповідь і обмежений фрагмент поточної розмови.
- **Stop** зупиняє джерела, завершує розпізнавання останньої фрази й запускає
  автовідповідь, якщо вона схожа на запит. **New session** очищає поточний контекст.
- Плаваюче вікно: кнопка в toolbar / menu bar, можна переміщати та змінювати розмір.
- **⌃⌥⌘G** — відповідь, **⌃⌥⌘R** — Start/Stop, **⌃⌥⌘P** — плаваюче вікно.
  У Hotkeys можна вимкнути реєстрацію; комбінації наразі фіксовані.
- Privacy → Request window capture exclusion встановлює AppKit `sharingType`.
  Це best-effort; macOS і деякі сервіси все одно можуть показати вікно.

Налаштування джерел, мови, VAD та фрагментів змінюйте при зупиненому захопленні.

## Тривалий діалог і перебивання

Проміжний текст формує чернетку питання. Після фіналізації звуку застосунок
залишає ще 1.4 s на продовження; фраза «чому ми ділимо на…» лишається чернеткою.
Продовження від того самого джерела об'єднується з питанням. Явні «стоп, краще…»,
«ні, точніше…» позначають попереднє питання перерваним або переформульованим.
Якщо автовідповідь на нього вже почалася, вона скасовується. Репліки з різних
аудіоканалів не зливаються. У спільному мікрофоні людей автоматично не розділяємо.

Поки відповідь не генерується, локальна модель додатково класифікує останню
репліку: нове питання, продовження, заміна, відмова або опис. Вона має повернути
дослівну цитату; застарілий результат і невірний JSON ігноруються. Запит має
8-секундний дедлайн і скасовується при новому мовленні чи запуску відповіді.
Це евристики й локальна модель, тому неявна зміна наміру все ще може помилятися;
усі питання залишаються доступними для ручного вибору зі статусами.

Повні завершені репліки, відповіді та позначки пропусків пишуться в локальний
текстовий журнал при Save history ON. «Зберегти діалог» експортує його, а
«Відновити останній» повертає діалог і питання після перезапуску. Під час довгого
сеансу модель отримує обмежений свіжий контекст і релевантні ранні репліки з
журналу; повний 45-хвилинний текст не поміщається в кожний запит до моделі.
Стискання пам'яті виконується після зупинки захоплення, щоб не конкурувати з ним.

План живого 45-хвилинного прогону: [docs/LIVE_DEFENSE_TEST.md](docs/LIVE_DEFENSE_TEST.md).
`swift test --filter DialogueReliabilityTests` програє 45 хвилин віртуального PCM
зі штучним декодером, перевіряє перебивання, повний журнал і перевантаження.
Це не перевірка живої точності Whisper, навушників чи нагріву протягом 45 хвилин.

## Архітектура

`Sources/LocalCopilotCore` містить тестовані SettingsManager, StorageManager
(actor / SQLite), OllamaService (actor / URLSession), SpeechRecognitionService
(actor / WhisperKit), VoiceActivityDetector, AudioBufferManager,
TranscriptAssembler, QuestionDetectionService, QuestionInbox, SessionJournal,
SpeechPipeline та ThinkingStreamParser.

`App/Audio` — MicrophoneManager, SystemAudioManager, AudioCaptureManager і
PCM-конвертер до mono float32 16 kHz. Мікрофон і системний звук не змішуються.
Підключення аудіопристроїв відстежується через AVAudioEngine notifications та
оновлення CoreAudio inventory. Система повторно підключає зупинені джерела;
зникнення вибраного застосунку не видаляє сеанс.

`App/Services` — ConversationManager (MVVM / MainActor, injection сервісів),
PermissionsManager, DiagnosticsManager, HotkeyManager. SpeechPipeline — actor
у тестованому core. Один декодер зберігає порядок завершених фрагментів;
під тиском відкидаються лише замінні previews, а не вікна з новими словами.
Черга тримає до 90 s семплів у RAM (без поточного декоду й активних буферів),
решту переносить у приватний тимчасовий кеш. При перевищенні 512 MB або
недоступному кеші показується помилка й захоплення зупиняється для обробки черги.
Текст вікна обмежено 24 000 символами на джерело, повний текст — у журналі.
UI не чекає inference синхронно; після двох повторних невдалих декодувань
фрагмент явно позначається як пропуск, а конвеєр продовжує роботу.

VAD базується на RMS; пауза типово 0.85 s, максимальне вікно 6 s, перекриття 0.5 s.
Проміжне розпізнавання виконується не частіше одного разу на вікно після 2 s
голосу. Фрази тривалістю 7–60 s після паузи повторно розпізнаються цілком;
цей результат виправляє помилки на межах коротких вікон і отримує пріоритет
у черзі декодера. Якщо повне розпізнавання порожнє, обробляються попередні вікна.
Для джерел без callbacks у тиші таймер додає нульове padding, щоб
закрити реальну фразу. Це low-latency chunked STT, не безперервний streaming SDK.
RMS VAD може реагувати на музику й фонові шуми. Whisper confidence/no-speech
фільтри зменшують галюцинації, але не виключають їх повністю.

## Локальні дані

`~/Library/Application Support/LocalCopilot/`:

- `settings.json` — налаштування, atomic writes.
- `history.sqlite` — завершені запитання й відповіді, без аудіозаписів.
- `Sessions/*.jsonl` — повні завершені репліки, відповіді та діагностика сесії.
- `Models/` — Whisper Core ML та токенізатор.

History → Delete all видаляє відповіді з SQLite та текстові журнали сесій.
Settings → Privacy → Save local history вимикає нові записи. Діагностичний журнал
залишається в оперативній пам'яті; його вміст можна скопіювати вручну.
При перевантаженні PCM тимчасово потрапляє в системну temp-папку
`questionio-speech-*` (папка 0700, файли 0600). Файли видаляються після декодування
і нормальної зупинки; залишки після збою старші за добу прибираються на запуску.
Повний аудіозапис захисту не ведеться. Модель не має shell-інструментів.

## Ручні acceptance-тести

1. **Microphone:** виберіть Microphone, українську мову, натисніть Start, промовте
   «Як працює асинхронне програмування?» і зробіть паузу 2 s. Шкала має рухатись,
   текст має перейти із сірого в підтверджений. Для авто-відповіді ввімкніть
   Answer from microphone. Stop має звільнити мікрофон.
2. **Selected app:** запустіть Zoom / Discord / браузер, оновіть Sources, виберіть
   його bundle ID. Програйте мовлення в цьому застосунку; звук з іншого застосунку
   не повинен потрапити до системної транскрипції. Для Safari/Chrome перевірте
   саме ваш сервіс, оскільки обробка аудіо helper-процесами залежить від застосунку.
3. **Both:** паралельно промовте свою фразу й відтворіть голос у вибраному застосунку.
   Повинні бути два окремі транскрипти. Немає acoustic echo cancellation: голос
   співрозмовника зі спікерів може потрапляти до фізичного мікрофона. Для чистого
   розділення користуйтеся навушниками.
4. **Automatic:** увімкніть режим, поставте завершене запитання, пауза 2 s.
   Має з'явитися одна потокова відповідь. Наступне «А чому?» має врахувати контекст.
   В Manual до натискання Generate Answer генерація не починається.
5. **Errors:** закрийте джерело, від'єднайте AirPods, відмовте дозволу одному джерелу.
   Інше джерело й текст мають зберегтися. Після повернення пристрою перевірте
   перепідключення. При вимкненій Ollama має бути помилка, без хмарного fallback.
6. **History:** дайте моделі завершити відповідь, перезапустіть програму, перевірте
   History. Continue додає вибрану пару до контексту. Delete all видаляє записи.
7. **UI:** перевірте світлу/темну тему, Copy, Cancel, три hotkeys, menu bar,
   resizing та Always on Top. Перевірте privacy mode реальним screen sharing;
   не покладайтеся на нього для секретної інформації.
8. **Endurance:** 30–60 хвилин реальної розмови, час від часу Generate/Cancel,
   зміна джерел лише після Stop. В Activity Monitor перевірте пам'ять та
   responsiveness. Такий довгий тест не підміняється коротким smoke test.
9. **Offline:** після завантаження моделі вимкніть мережу самостійно й повторіть
   Whisper + Ollama. Localhost має лишитись доступним.

Див. `VERIFICATION.md` для фактично виконаних перевірок і вимірювань.
Ліцензії та патч залежності описані в `THIRD_PARTY.md`.


## Оновлення повних відповідей, формул і моделей

- Типово `num_predict = -1`: застосунок не обрізає відповідь на 256/1024 токенах.
  Генерація триває до природного завершення моделі або Cancel; загальний 180 s
  timeout прибрано. Контекст (8192 токени за замовчуванням), RAM і сама модель
  залишаються скінченними; це не обіцянка математично нескінченного тексту.
- Settings → Answer Behavior → **Complete answers · no output token cap**.
  Старі налаштування мігруються зі збереженням моделі, джерел і modelPath;
  стандартний prompt замінено програмістським, власний prompt зберігається.
- Основне й плаваюче вікно показують Markdown-код, списки, таблиці та LaTeX
  через локальні Marked + DOMPurify + KaTeX. Підтримано `\( ... \)`,
  `\[ ... \]`, `$...$`, `$$...$$`; кодові блоки не обробляються як формули.
  Невалідний LaTeX може залишитися текстом. Рендерер не підтверджує правильність
  математики, яку вигадала LLM. Assets і шрифти у `.app`, без CDN.
- Встановлено `qwen2.5-coder:7b` (~4.7 GB) та `qwen3.5:9b` (~6.6 GB локальних
  ваг); обрано 9b. У контрольному запитанні 9b правильно дала порядок JS логів
  та формулу Амдала, але це не benchmark загальної якості. 9b повільніша;
  для швидких відповідей виберіть qwen3.5:4b. Усі моделі локальні та без API-квот.

### Приватне вікно / ghost mode

Settings → Privacy → **Request capture exclusion · experimental** застосовує
AppKit sharingType=.none до вікон застосунку. На цьому Mac парний full-display
тест ScreenCaptureKit показав плаваюче вікно при OFF та приховав при ON.
Це не гарантує однакової поведінки Zoom/Meet/Discord або майбутніх macOS.

Точний ручний тест: увімкніть прапорець, відкрийте Notes з видимою відповіддю,
почніть демонстрацію **всього екрана** у потрібному сервісі; з іншого пристрою
або облікового запису перевірте, що Notes відсутнє, хоча ви його бачите. Повторіть
з OFF, щоб переконатися, що тестова демонстрація справді охоплює це місце екрана.
Кнопка **Test full-display capture exclusion** робить один явний локальний
знімок поточного стану і записує шлях у Diagnostics. Звичайне аудіозахоплення
не створює знімків. Для надійного розділення можна демонструвати окреме вікно.

Постійний локальний підпис зберігає ідентичність Questionio при нових збірках.
Після першого переходу з ad hoc підпису macOS потрібно один раз оновити вже
надані дозволи. Далі збирайте через `./scripts/build.sh`, зберігаючи той самий
ключ підпису.

### Джерело звуку й навушники

У Live session виберіть **Захоплення** (System Audio / Microphone / Both) та
**Програма**. Рядок «Джерело» видно також у Notes разом із мікрофоном, типовим
виходом macOS, рівнями сигналу та Ghost ON/OFF. Зупиніть capture перед зміною
джерела. Фільтр програми охоплює всі її вікна/вкладки; вибір окремого вікна
або вкладки поки не підтримується. Вихід показує типовий пристрій macOS;
програми з власним маршрутом звуку можуть використовувати інший пристрій.

Мікрофон показує реальний input аудіодвигуна, включно з AirPods. Для автоматичної
відповіді на власний голос: Both/Microphone та Settings → Audio → Allow automatic
answers from microphone. Для співрозмовника достатньо System Audio. Ghost mode
змінює видимість вікна для capture і не зупиняє аудіо.

Типовий prompt відповідає коротко, одразу по суті, без вступів і зайвих порад.
На запит про код або докладне пояснення відповідь завершується повністю:
output cap залишається -1. Міграція v4 оновлює попередній типовий prompt,
зберігаючи власні prompts і вибрані джерела/моделі.

### Notes above full-screen apps

Ghost ON keeps Notes above other applications, including their full-screen
Spaces. It follows all Spaces and does not activate the main app when opened.
Ghost OFF disables joining other apps' full-screen Spaces. The Top setting
then applies only to ordinary desktop windows. While Ghost is ON, Top is
automatically enforced and its checkbox is disabled. Main and Settings windows
do not become full-screen overlays.

Implementation uses AppKit's [canJoinAllApplications](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications)
for the ghost panel, and fullScreenNone for normal mode. Capture exclusion
remains a separate macOS best-effort property; full-screen overlay does not
change audio capture.

### Ghost switch and ASR accuracy

The Ghost ON/OFF button is available in both Live session and Notes. It changes
capture exclusion and full-screen overlay behavior immediately.

Speech Recognition now offers Whisper Large v3 Turbo alongside small/base.
The installed Turbo model/tokenizer run locally; it is the free MIT-licensed
[Whisper model](https://huggingface.co/openai/whisper-large-v3-turbo) in the
[Argmax Core ML format](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3-v20240930_turbo).
It uses more memory than small; the first Core ML load can take over a minute.
Whisper status shows the loaded model family.

Known spoken IT spellings are corrected in the submitted question while the
raw Transcript is retained. Async spellings require both Promise and callback
anchors. A known malformed static-typing compound has a narrow correction.
A visible note indicates corrections; unclear words are not filled in arbitrarily.
Automatic detection now recognizes Ukrainian comparison questions beginning
with «чим», as well as «скільки», «навіщо», «у чому» and «в чому», without `?`.
The source bar explains when an utterance is not recognized as a question,
a repeated question is suppressed, or microphone auto-answer is disabled.

## Conversation and screen context

- Online listens to the selected application; your microphone is excluded by default. All windows of that application share one audio source, including browser tabs.
- Classroom uses the microphone and enables automatic answers. With the initial default input it prefers the available built-in MacBook microphone. Select another input before Start when needed. The speaking-pause button / Control-Option-Command-M pauses microphone recognition, discards unfinished microphone audio, and resumes on another press. This is manual turn separation, not automatic identification of people sharing a microphone.
- Custom preserves manual System/Microphone/Both settings; Both includes your microphone only with the capture-my-voice checkbox.
- Context / Code: set a topic, select a window and capture, or select a region / open a UTF-8 source file / paste code. Correct OCR manually when needed. Automatic capture updates the selected source every 5 seconds and before answering. Images stay in RAM and go only to the local model; Vision-capable models receive images, other models use OCR. qwen3.5:9b on this Mac supports Vision.
- Recent turns, current code and retrieved journal excerpts inform follow-up answers. Model context remains finite; summaries may lose details. Restore last dialogue recovers saved final text/questions and the connected project path; current code is reread from disk. New session clears active state while saved journals remain available.
- The answer pencil edits the recognized question and retries. General/JavaScript/Python/SQL vocabulary and custom terms condition ASR; set them before Start.
- Default audio-route or sample-rate changes reopen active audio sources. Silence means waiting for sound. Disconnecting an explicitly selected microphone may require choosing an available input.
