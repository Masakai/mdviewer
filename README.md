# MDViewer

A lightweight, native macOS Markdown viewer built for developers.

![Screenshot](docs/screenshot.png)

## Overview

MDViewer was created out of a simple need: a fast, minimal way to read `.md` files when working from the terminal with tools like Claude Code or Codex. It renders Markdown beautifully without the overhead of a browser or a full editor.

## Features

- **Instant rendering** — opens and renders Markdown files immediately
- **Live reload** — watches for file changes and re-renders as you save
- **Table of contents** — auto-generated sidebar from headings with smooth scroll
- **Syntax highlighting** — 27 languages via [Shiki v1](https://github.com/shikijs/shiki)
- **Math equations** — inline and block LaTeX via [KaTeX](https://github.com/KaTeX/KaTeX)
- **Mermaid diagrams** — flowcharts, sequence diagrams, Gantt charts, and more
- **Smart link handling** — local `.md` links open in-app; external links open in the browser
- **Export to PDF** — one-click PDF export preserving all styles
- **Signed & notarized** — Developer ID signing and Apple notarization

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon (M1 or later)

## Installation

1. Download the latest `MDViewer-x.x.x.zip` from the [Releases page](https://github.com/Masakai/mdviewer/releases/latest)
2. Unzip and drag `MDViewer.app` to your **Applications** folder
3. Double-click any `.md` file — or drop it onto the MDViewer icon in the Dock

## Building from source

Requires Xcode 15 or later.

```sh
git clone https://github.com/Masakai/mdviewer.git
cd mdviewer
open MDViewer.xcodeproj
```

Build and run with ⌘R. No Swift Package dependencies — all vendor libraries are bundled in `MDViewer/Resources/Web/vendor/`.

## Tech stack

| Layer | Technology |
|-------|-----------|
| UI framework | SwiftUI + AppKit |
| Rendering engine | WKWebView |
| Markdown parser | [marked](https://github.com/markedjs/marked) v12 |
| Syntax highlighting | [Shiki](https://github.com/shikijs/shiki) v1 |
| Math | [KaTeX](https://github.com/KaTeX/KaTeX) v0.16 |
| Diagrams | [Mermaid](https://github.com/mermaid-js/mermaid) v10 |
| File watching | `DispatchSource` (kqueue) |

## Open source libraries

All bundled libraries are MIT licensed. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for full license texts.

| Library | Version | License |
|---------|---------|---------|
| marked | 12.0.2 | MIT |
| Shiki | 1.x | MIT |
| KaTeX | 0.16.11 | MIT |
| Mermaid | 10.x | MIT |

## License

MDViewer is released under the [MIT License](LICENSE).

© 2026 Masanori Sakai
