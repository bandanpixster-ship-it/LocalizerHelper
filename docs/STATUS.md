# LocalizerHelper — Project Status & Progress Report

**Date:** June 30, 2026

Comprehensive audit of the repository against the product plan. All 7 phases are implemented.

---

## 1. Feature Completion Status

### Phase 0: Shell & Open Folder — Completed

- `NSOpenPanel` integration for folder selection.
- `ProjectScanner` recurses files and filters out `Pods`, `DerivedData`, `.git`, `build`, `.build`, and `Carthage`.
- Sidebar tree with collapsible folders, sorted directories-first then alphabetically.
- `FileKind` icons (folder, Swift, strings catalog, generic file).
- Context menu: "Open in Finder" on any tree node.

### Phase 1: Swift String Extraction — Completed

- Custom tokenizer `SwiftStringExtractor` (no SwiftSyntax dependency) extracts double-quoted and multiline string literals, tracking line numbers and source context.
- Interpolation-aware: `\(expr)` → `{expr}` in display pattern; `localizationTemplate` converts to printf-style `%1$@` for use as localization keys.
- **Context-aware filtering skips non-localizable strings:**
  - Image/Color calls: `Image("…")`, `Color("…")`, `UIImage(named:)`, `UIColor(named:)`, `.image("…")`, `.color("…")`, `NSImage`, `NSColor`
  - Hex color strings: `#fff`, `#f023ff` (3, 4, 6, or 8 hex digits)
  - Logging/print calls: `print()`, `debugPrint()`, `NSLog()`, `os_log()`, `Logger.debug/info/warning/error/critical/fault/notice/log()`, and any custom logger using those method names
- `SwiftStringsDetailView` shows pattern, raw snippet, line number, and whether the string is missing from the catalog.
- **Sorting** by line number, status (missing first), or pattern.
- **Filter** by all / missing / present.

### Phase 2: Localization Parsing — Completed

- `StringsParser` parses `.strings` files with full escape handling (`\n`, `\t`, `\r`, `\"`, `\\`) and comment skipping (`//`, `/* */`).
- **Multi-encoding detection:** UTF-8 → UTF-16 LE → UTF-16 BE → macOS Roman → ISO-Latin-1.
- `XCStringsParser` decodes Xcode String Catalog (`.xcstrings`) JSON format, including `comment` fields.
- `LocalizationCatalog` aggregates entries across all files; groups by key, file, and language.
- English base: `en.lproj` and `Base.lproj` both treated as `"en"`.
- Deduplication within one file: last occurrence wins (mirrors runtime).

### Phase 3: Audit & Detail UI — Completed

- `LocalizationAuditor` runs 4 rules:
  - `missing_translation` (Error): Value is empty in a language
  - `untranslated_copy` (Error): Value in language X matches English
  - `missing_language` (Warning): Key absent in a language entirely
  - `duplicate_across_files` (Warning): Same key in different table files
- `LocalizationDetailView` groups results by source file with per-key rows showing audit badges.
- **Row expansion**: language chips per translation (✓ / ✗ / ⚠), inline edit, AI batch-translate button.
- **Summary chips** in header: `N errors · N warnings · N ignored`.
- **Search:** text search with match-case toggle, whole-word toggle, and scope selector (All / Keys / Values / Translations).
- **Filter:** segmented picker (All / Errors / Warnings / Ignored / AI Ready).

### Phase 4: Ignore List & Project Store — Completed

- `GlobalIgnoreStore`: observable singleton persisting ignored keys to `~/Library/Application Support/LocalizerHelper/global_ignores.json`.
- Ignore entries support optional per-language scoping (ignore only in `de`, or in all languages).
- Ignore/unignore toggle available per row in `LocalizationDetailView`.
- `IgnoredKeysSettingsView`: table of all ignored keys with delete per row and "Clear All" option.
- Audit re-runs automatically whenever the ignore list changes.

### Phase 5: Polish & File Editing — Completed

- **Recent projects:** Auto-opens last project on launch via security-scoped bookmark (`last-project.bookmark`).
- **Background scan** with `Task` cancellation on re-open.
- **`LocalizationFileUpdater`:** Full read/write engine for `.strings` and `.xcstrings`:
  - Update translation values (regex for `.strings`; JSON edit for `.xcstrings`)
  - Add and delete keys
  - Insert/update/delete developer comments
  - Add new languages (creates `.lproj` folder + empty file for `.strings`; adds language block for `.xcstrings`)
  - Full escape handling on write
- **Create localization file:** `NSSavePanel` from within the app to create a new `.xcstrings` or `.strings` file.
- **`AddLanguageView`:** Dialog to pick language code and target file; explains what will happen before proceeding.

### Phase 6: AI & Translation — Completed

- **`TranslationService`** with 9 backends:
  - Cloud AI: Claude (Anthropic), OpenAI (GPT-4o mini), Google Gemini
  - Local AI: Ollama, LM Studio, MLX (OpenAI-compatible endpoints)
  - Free: Google Translate (unofficial), MyMemory, LibreTranslate
- **Fallback strategy:**
  - AI configured → try AI first, fall back to free chain on error
  - ≤2 words free chain: Google → MyMemory → LibreTranslate
  - 3+ words free chain: MyMemory → Google → LibreTranslate
- **Placeholder protection:** Swift interpolations (`\(expr)`) and printf-style markers (`%@`, `%d`, `%1$@`, etc.) tokenised to `__PH0__`, `__PH1__`, … before translation and restored after.
- **Batch translation:** Single AI API call translates one key to all target languages simultaneously.
- **Developer comment generation:** AI generates a contextual comment from the source Swift line and key name.
- **`BulkAddSheet`:** Batch-import Swift string literals into a localization file:
  - Checkbox selection of literals
  - Target file picker
  - Translation mode: None / Free / AI (batch)
  - Progress bar + result summary (X added, Y skipped as duplicates)
- **`AISettingsView`:**
  - Provider radio selection
  - API key input with visibility toggle and live "Test" button (idle / testing / success / failure)
  - Local server URL input with "Fetch Models" and model picker
  - API keys stored in Keychain; server URLs and model preference in UserDefaults
- **`LanguageOption.all`:** Dynamic language list from `Locale.availableIdentifiers`.

### Phase 7: Menu Commands & Settings — Completed

- **`AppCommands`** struct registers macOS menu bar items via `FocusedValues` bridge:
  - **File menu** (replaces default "New"):
    - Open Project… (Cmd+O)
    - Refresh Project (Cmd+R, disabled when no project or scanning)
  - **View menu** (new, between Window and Help):
    - View Localization File (Cmd+L) — single item or submenu for multiple files
    - Add Language…
    - Show All Strings (Cmd+1)
    - Show Errors Only (Cmd+2)
    - Show Warnings Only (Cmd+3)
    - Show Ignored Only (Cmd+4)
    - Show AI Ready Only (Cmd+5)
- **`FocusedValues` extensions** on `NavigationSplitView` in `ContentView` expose `projectViewModel` and `showAddLanguageAction` to the Commands layer.
- **Settings window** registered as a SwiftUI `Settings` scene; opens via Cmd+, or the app menu. Contains `AISettingsView` and `IgnoredKeysSettingsView`.

---

## 2. Known Gaps & Open Issues

| Area | Issue | Severity |
|------|-------|----------|
| `ContentView` | `viewModel.unreadableFiles` is tracked but never shown to the user — no alert, toast, or indicator when files fail to parse during scan | Medium |
| `ContentView` | `showsLocalizationDetail` returns `true` for all directories, so the audit filter picker appears in the header even when the directory is actually showing Swift string literals | Low |
| `ContentView` | When a directory contains both Swift files and localization entries, only Swift literals are shown — no way to switch to the localization view for that folder | Medium |
| `ContentView` | `print(...)` debug statements in `onAppear` (auto-open logic) — should use `Logger` or be removed | Cosmetic |
| `AppleTranslator.swift` | Apple on-device translation exists in source but is disabled — `NLTranslator` was unavailable in the build environment at time of implementation | Low |
| Menu commands | `CommandGroup(replacing: .newItem)` removes the default "New Window" item — acceptable for a single-window app, but worth noting | Cosmetic |

---

## 3. Deferred (Not Implemented)

- Export audit report (CSV, JSON, markdown)
- Swift literal ↔ localization key cross-reference (show which literals map to which keys)
- Apple on-device translation (infrastructure ready in `AppleTranslator.swift`, disabled)
- iOS / iPad targets

---

## 4. File Inventory

| File | Role |
|------|------|
| `LocalizerHelperApp.swift` | App entry point, scene registration, window sizing |
| `AppCommands.swift` | macOS menu bar (File + View menus) via `FocusedValues` |
| `AppleTranslator.swift` | On-device translation stub (disabled) |
| `AppleTranslateSupportedLanguages.swift` | Static list of ~40 Apple-supported language codes |
| `Models/FileNode.swift` | File tree node (URL-based identity) |
| `Models/FileKind.swift` | File type enum with URL factory |
| `Models/LocalizationEntry.swift` | `LocalizationKey`, `LocalizationEntry`, `LocalizationCatalog`, `LocalizationParsers` |
| `Models/SwiftStringLiteral.swift` | Extracted literal with pattern, line, interpolation info |
| `Models/AuditIssue.swift` | `AuditSeverity`, `AuditRuleID`, `AuditIssue`, `KeyAuditResult`, `SearchScope`, `DetailFilter` |
| `Models/LanguageOption.swift` | BCP-47 language picker data |
| `Models/GlobalIgnoreEntry.swift` | Ignored key model (key + optional language) |
| `Models/AISettings.swift` | `AIProvider` enum + `AISettings` singleton (Keychain + UserDefaults) |
| `Services/ProjectScanner.swift` | Recursive folder scan → `FileNode` tree |
| `Services/StringsParser.swift` | `.strings` parser (multi-encoding) |
| `Services/XCStringsParser.swift` | `.xcstrings` JSON parser |
| `Services/SwiftStringExtractor.swift` | Custom Swift literal tokenizer with smart filtering |
| `Services/LocalizationAuditor.swift` | 4-rule audit engine |
| `Services/ProjectStore.swift` | Project ID derivation + bookmark persistence |
| `Services/GlobalIgnoreStore.swift` | Observable singleton for global ignore list |
| `Services/LocalizationFileUpdater.swift` | Full read/write engine for `.strings` and `.xcstrings` |
| `Services/TranslationService.swift` | 6 AI + 3 free translation backends |
| `ViewModels/ProjectViewModel.swift` | `@MainActor @Observable` ViewModel (all app state) |
| `Views/ContentView.swift` | App shell: `NavigationSplitView`, toolbar, sheets, alerts |
| `Views/ProjectTreeView.swift` | Sidebar file tree with disclosure groups |
| `Views/LocalizationDetailView.swift` | Audit results with inline edit + AI translation |
| `Views/SwiftStringsDetailView.swift` | Swift literals with missing/present status + bulk add |
| `Views/AuditBadgeView.swift` | Severity badge (red/orange/secondary/green) |
| `Views/AuditSummaryView.swift` | Error/warning/ignored count chips |
| `Views/EmptySelectionView.swift` | Placeholder for no selection or loading |
| `Views/AddLanguageView.swift` | Add new language to localization files |
| `Views/BulkAddSheet.swift` | Batch import literals with optional translation |
| `Views/Settings/SettingsView.swift` | Settings tab container |
| `Views/Settings/AISettingsView.swift` | AI provider + API key configuration |
| `Views/Settings/IgnoredKeysSettingsView.swift` | Manage global ignored keys |
