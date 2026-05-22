# Changelog

All notable changes to MDViewer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [1.1.0] — 2026-05-22

### Added
- Split-view editor mode: toggle with ⌘E or the toolbar pencil button
- Left editor pane with monospaced text input and live preview on the right
- Save support: ⌘S saves changes to the current file (read-write sandbox entitlement)
- Unsaved-change guard: closing the window with unsaved changes prompts Save / Discard / Cancel

---

## [1.0.3] — 2026-05-05

### Added
- Export: default filename now inherits the source Markdown filename (e.g. `README.pdf` instead of `document.pdf`); percent-encoded characters (Japanese, spaces) are decoded correctly
- Title bar now displays the open filename instead of "MDViewer"

### Removed
- Page thumbnail sidebar removed; TOC sidebar only

---

## [1.0.2] — 2026-05-05

### Changed
- PDF export: replaced `WKWebView.createPDF()` (single-page) with `NSPrintOperation.runModal` to correctly apply print CSS and generate properly paginated multi-page PDFs

### Fixed
- PDF export hang-up resolved by switching to `NSPrintOperation.runModal`
- Sidebar: thumbnail tab temporarily hidden (TOC-only display)

---

## [1.0.1] — 2026-05-05

### Added
- PDF/print layout: `@media print` styles for A4 page size, margins, and page-break control
- Build and notarization script (`build-notarize.sh`)

### Fixed
- Shiki syntax highlighter: added try/catch with fallback and 8-second initialization timeout
- Removed redundant light-theme CSS overrides for Shiki (inline styles take precedence)

---

## [1.0.0] — 2026-05-04

### Added
- Initial release
- Markdown rendering via WKWebView + marked.js v12
- Syntax highlighting for 27 languages via Shiki v1 (github-light / github-dark dual themes)
- LaTeX math rendering via KaTeX v0.16 — inline `$…$` and block `$$…$$`
- Mermaid diagram support — flowcharts, sequence diagrams, Gantt charts
- Auto-generated table of contents sidebar from headings
- Page thumbnail sidebar (generated via PDFKit) — removed in v1.0.3
- Live file reload using `DispatchSource` (kqueue, 0.5 s debounce)
- Local image loading via custom `mdviewer-local://` URL scheme handler
- Theme switching — GitHub Light / GitHub Dark, follows macOS appearance
- Font size control — increase, decrease, reset (⌘+, ⌘−, ⌘0)
- PDF export via `WKWebView.createPDF()`
- HTML export
- Smart link handling — local `.md` links open in-app, external links open in browser
- In-page text search (⌘F)
- Japanese / English localization
- Developer ID signing and Apple notarization
- Landing page (English and Japanese) at https://masakai.github.io/mdviewer/
