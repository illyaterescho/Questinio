# Questionio

[English](README.md) · **Українська**

Безкоштовний локальний AI-асистент для зустрічей на macOS (Apple Silicon,
macOS 14+). Розшифровує дзвінок або мікрофон прямо на пристрої, знаходить
питання й потоково видає відповіді локальної LLM, за потреби спираючись на
вибрану папку з кодом. Без хмарних API, акаунтів і підписок.

> Папка з кодом, Xcode-схема та Swift-модуль досі мають стару назву
> `LocalCopilot` для сумісності.

## Можливості

- **Два аудіоканали**: звук застосунку/системи (Core Audio Tap або
  ScreenCaptureKit) і мікрофон розпізнаються окремо, тож завжди видно, хто говорив.
- **Розпізнавання мовлення на пристрої**: WhisperKit (Core ML), моделі small /
  base / large-v3-turbo. Під час розпізнавання мережевий fallback вимкнено.
- **Список питань**: питання фіксується після паузи разом із контекстом розмови
  на той момент; перервані й переформульовані питання відстежуються.
- **Локальні відповіді**: Ollama (`/api/chat`, потоково), підтримка моделей із thinking.
- **Контекст коду**: підключіть папку проєкту — до питань про код додаються
  релевантні фрагменти з точними номерами рядків («що робить рядок 129?»,
  «де визначено X?»). Опційно — читання редактора JetBrains через Accessibility.
- **Відображення**: Markdown, код і LaTeX через вбудовані marked + DOMPurify + KaTeX.
- **Історія**: SQLite + JSONL-журнал сесії, експорт і відновлення.

## Вимоги

- Xcode, Homebrew OpenSSL (для локального підпису), [Ollama](https://ollama.com)
  на `http://127.0.0.1:11434` з хоча б однією чат-моделлю, наприклад
  `ollama pull qwen3:4b`.
- Модель Whisper, яка завантажується один раз у Settings → Speech Recognition.

## Збірка

```sh
./scripts/setup-local-signing.sh  # один раз на Mac: постійний локальний підпис
./scripts/test.sh
./scripts/build.sh
open dist/Questionio.app
```

Ключ підпису зберігається в `~/Library/Application Support/Questionio/Signing`,
поза репозиторієм. Збірки локальні, без нотаризації.

## Дозволи

System Settings → Privacy & Security:

1. **Microphone** — для режимів Microphone / Both.
2. **Screen & System Audio Recording → System Audio Recording Only** — для
   Core Audio Tap (типово).
3. **Screen & System Audio Recording** — для контексту екрана та
   альтернативного аудіо через ScreenCaptureKit.

## Використання

- **Start** запускає захоплення; сірий текст проміжний, після паузи він підтверджується.
- **Generate Answer** відповідає на введений текст або останнє завершене питання.
  Будь-яке попереднє питання зі списку можна вибрати — відповідь отримає його контекст.
- Автовідповіді опційні; питання з вашого мікрофона не запускають генерацію,
  якщо це не ввімкнено.
- Гарячі клавіші: **⌃⌥⌘G** відповідь, **⌃⌥⌘R** старт/стоп, **⌃⌥⌘P** плаваюче вікно.

## Архітектура

- `Sources/LocalCopilotCore` — тестоване ядро: налаштування, SQLite-сховище,
  клієнт Ollama, обгортка WhisperKit, VAD, конвеєр мовлення, збирання транскрипту,
  виявлення питань і список питань, журнал сесії, індекс коду проєкту.
- `App/Audio` — мікрофон, системний звук, конвертація PCM у mono 16 kHz.
- `App/Services` — `ConversationManager` (головна view model), контекст
  проєкту / IDE / екрана, дозволи, гарячі клавіші, діагностика.
- `App/UI` — SwiftUI-екрани та веб-рендерер відповідей.
- `Vendor/argmax-oss-swift` — змінена копія WhisperKit (див. `THIRD_PARTY.md`).

## Локальні дані

`~/Library/Application Support/LocalCopilot/`: `settings.json`,
`history.sqlite`, `Sessions/*.jsonl`, `Models/`. Аудіозаписи не зберігаються;
надлишковий PCM тимчасово пишеться в приватну temp-папку й видаляється після
розпізнавання. History → Delete all видаляє відповіді та журнали сесій.

## Probe CLI

```sh
swift run LocalCopilotProbe                       # список моделей, тестова відповідь
swift run LocalCopilotProbe --download --variant openai_whisper-small
swift run LocalCopilotProbe --transcribe sample.wav
```

## Ліцензія

Див. `LICENSE` і `THIRD_PARTY.md`.
