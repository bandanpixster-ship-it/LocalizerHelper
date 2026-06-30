# LocalizerHelper

![GitHub Repo stars](https://img.shields.io/github/stars/bandanpixster-ship-it/LocalizerHelper?style=flat-square)
![GitHub license](https://img.shields.io/github/license/bandanpixster-ship-it/LocalizerHelper?style=flat-square)

> **LocalizerHelper** is a macOS‑only SwiftUI application that helps developers audit, visualise, and edit localisation files (`.strings` and `.xcstrings`) within Xcode projects. It provides an intuitive tree view of your project, extracts Swift string literals, and highlights missing or untranslated entries across all supported languages. The tool is designed for speed, reliability, and an excellent developer experience.

---

## ✨ Features

- **Full Project Explorer** – Browse the complete folder hierarchy of any Xcode project, including hidden files, while respecting exclusion rules (`Pods`, `DerivedData`, `.git`).
- **Swift String Extraction** – List every string literal in a selected Swift file with interpolation placeholders, line numbers and raw source snippets. Automatically filters out string literals representing image/color names (e.g. `Image`, `Color`, `UIImage`, `UIColor`, `.image`, `.color` contexts) and hex colors (e.g., `#f023ff`, `#fff`) to focus on translatable text.
- **Comprehensive localisation parsing** – Parse both legacy `.strings` and modern `.xcstrings` catalogs, de‑duplicate entries (last‑wins), and build a unified localisation catalogue.
- **Robust audit engine** – Detect:
  - Missing translations (empty values).
  - Untranslated copies (values identical to the English source).
  - Missing language files.
  - Duplicate keys across different tables.
- **Ignore list per project** – Mark specific keys to be ignored for the `untranslated_copy` rule; persisted in the app’s support folder.
- **Background scanning** – Fast, cancellable scans that run on a background queue, keeping the UI responsive.
- **CLI translation helper** – `translator.py` script for batch translation via Google Translate (useful for large projects).
- **Recent projects** – Automatically re‑opens the last opened project on launch.
- **Dark‑mode ready UI** – Native macOS materials, semantic colours and adaptive layout.

---

## 📦 Installation

```bash
# Clone the repo
git clone https://github.com/bandanpixster-ship-it/LocalizerHelper.git
cd LocalizerHelper

# Open the Xcode project
open LocalizerHelper.xcodeproj

# Build & run (requires macOS 12+ and Xcode 14+)
```

---

## 🛠️ Usage

1. **Open a project** – Click the **Open Project** button in the toolbar and select the folder containing your Xcode project.
2. **Explore the tree** – The sidebar shows a collapsible file tree. Selecting a folder aggregates localisation data; selecting a Swift file shows extracted literals.
3. **Audit view** – Errors appear with red badges, warnings with orange, and OK entries with green. Use the context menu to ignore a key.
4. **Edit localisation entries** – Double‑click a row to edit its value directly within the UI.
5. **CLI translation** – Run the bundled script to auto‑translate:
   ```bash
   python3 translator.py <source‑lang> <target‑lang> <path/to/.strings>
   ```

---

## 🐞 Known Issues

- **Large projects may cause UI lag** during initial scan. This is mitigated by background processing but can still be noticeable on very deep folder structures.
- **Interpolation handling** is heuristic; extremely complex string interpolations may not render perfectly in the placeholder view.
- **File watcher** – Changes made to localisation files outside the app are not hot‑reloaded; you need to re‑scan the project.
- **Python translator** – Requires network access and a valid Google Translate API key for bulk translations; otherwise, it falls back to a simple placeholder implementation.

---

## ⚠️ Limitations & Model Hallucination Warning

- The app does **not** provide AI‑generated translations. If you integrate a local AI model for suggestion, remember that:
  - Small context windows can cause **hallucinations** – the model may invent translations that never existed in the source.
  - Models not trained on localisation data may produce inaccurate or culturally inappropriate output.
  - Always review AI‑suggested strings before committing them.
- The current implementation supports **macOS only**; iOS/iPadOS targets are planned for a future release.
- Only `.strings` and `.xcstrings` formats are parsed – other localisation formats (e.g., `.json`, `.xml`) are out of scope.

---

## 🤝 Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/awesome-feature`).
3. Implement your changes and ensure the project builds.
4. Open a Pull Request with a clear description of what you changed.

---

## 📜 License

This project is licensed under the **MIT License** – see the [LICENSE](LICENSE) file for details.

---

## 📌 Project Structure (high‑level)

```
LocalizerHelper/
├── App/                 # App entry point
├── Models/              # Data models (FileNode, LocalizationEntry, …)
├── Services/            # Scanners, parsers, auditors, updater
├── ViewModels/          # SwiftUI view‑models
├── Views/               # UI components (tree, detail panels, badges)
├── translate_text.py    # Helper script for text translation
└── translator.py        # CLI wrapper for Google Translate API
```

---

> **Happy localisation!**
