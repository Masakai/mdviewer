# Changelog

All notable changes to MDViewer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [1.3.0] — 2026-09-23

### Fixed
- Live reload no longer stops after the first save. Most editors (VS Code, vim, TextEdit, and MDViewer itself) save by replacing the file, and the watcher kept following the old, deleted copy, so every later change was missed. MDViewer now follows the file to its new copy on each save.
- Live reload now picks up a file that disappears for a while and comes back, such as during a git branch switch or a cloud sync.
- Opening another document while one was already open could shut down the new document's watcher, so live reload never started for it, and leaked the old file descriptor. Switching documents while a save was in progress could also leave live reload following the previous file. Both are fixed.
- The preview now recovers on its own when WebKit's rendering process crashes. Previously it stayed blank until the app was restarted, while the sidebar kept working.
- Reload in the preview's context menu now redraws the current document instead of showing a blank page.
- If a document keeps crashing the preview (four crashes in a row, each within ten seconds of the last), MDViewer stops reloading it, clears the preview and shows a message. Editing the file, reloading it or reopening it tries again.
- The preview no longer turns white when a render fails or produces no output, for example when the file is read while still being written. The previous output stays on screen, and when there is no output the sidebar keeps its headings as well.

Thanks to @harasuke for these fixes ([#2](https://github.com/Masakai/mdviewer/pull/2)).

---

## [1.2.3] — 2026-08-02

### Fixed
- Closing all windows now quits the app instead of leaving the process running in the background. Clicking the Dock icon while the app has no open windows now opens a new document, matching standard macOS behavior.

---

## [1.2.2] — 2026-07-29

### Fixed
- New document editing and preview no longer go out of sync. The editor's separate internal text buffer could momentarily revert to the previously open file's content right after creating a new document, so saving could write stale content instead of what was typed. The editor now binds directly to the document's text state instead of maintaining a duplicate copy.
- The preview pane now clears immediately when starting a new document, instead of continuing to display the previously open file's rendered content.

---

## [1.2.1] — 2026-07-19

### Added
- Help window: open "MDViewer Help" from the Help menu for a live-rendered reference covering all Markdown syntax and every Mermaid diagram type (flowchart, sequence, class, state, ER, Gantt, pie, user journey, mindmap, timeline)

---

## [1.2.0] — 2026-07-19

### Added
- New Markdown file creation: ⌘N, the toolbar "New" button, or the "New File" button on the welcome screen all start a blank document in split-view editor mode
- Saving a new (untitled) document now shows a save panel (⌘S falls back to Save As when no file is associated yet)
- Unsaved-change guard also applies to ⌘N: creating a new document while there are unsaved edits prompts Save / Discard / Cancel before discarding

---

## [1.1.2] — 2026-06-14

### Changed
- Internal code formatting only: the entire Swift codebase was reformatted with SwiftFormat to enforce the 4-space indentation convention. No functional or behavioral changes.

---

## [1.1.1] — 2026-06-12

### Fixed
- Local images stored alongside the Markdown file are now rendered correctly. Relative image paths are served through the `mdviewer-local://` scheme handler instead of `file://`, which the WebView sandbox had been blocking (images previously appeared as broken links).

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
