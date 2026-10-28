# Changelog

All notable changes to MDViewer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### Added
- Find (⌘F) now searches the editor too. With the cursor in the editor, ⌘F counts and moves through the editor's matches, selecting each one; otherwise it works on the preview as before. Matches are highlighted in both the editor and the preview either way, and the pane that is not being searched keeps its scroll position. The search bar now sits above both panes. (Thanks to @sullo, #30)
- When the editor is being searched, the search bar has a Replace With field with Replace and Replace All buttons. Replace changes the selected match and moves to the next; Replace All changes every match, and one ⌘Z undoes it. Text is matched the same way as in the preview: case is ignored, and a space in the search text matches spaces or a line break but not a blank line.

## [1.8.1] — 2026-10-28

### Security
- A Markdown file could run JavaScript in the preview through HTML written in the document (such as an `<img>` with an `onerror` attribute) or through HTML in a Mermaid diagram's labels. The preview now removes scripts, event handler attributes and `javascript:` links from the document's HTML with DOMPurify 3.4.17 before showing it, and Mermaid runs with `securityLevel: 'strict'`. A Content Security Policy also keeps any script that is not part of MDViewer from running and blocks network requests from the page. Images from the web are still shown. (Thanks to @sullo, #28)
- Links in the preview open only `http`, `https`, `mailto` and `file` URLs. Links with other URL schemes, such as those that launch other apps, do nothing, and link URLs other than these are removed from the document's HTML.
- The preview no longer turns on WebKit's `allowFileAccessFromFileURLs`, which the renderer did not need.

## [1.8.0] — 2026-10-25

### Added
- File > Open Recent lists the files you opened or saved recently. Choosing one opens it the same way as File > Open…: in a new window if a document is showing (or brings its window to the front if it is already open), or in the current window if it shows the welcome screen. Clear Menu empties the list. Files with the same name in different folders are shown with their folder name, such as `README.md — docs`. Bringing an already open file to the front, from Open Recent or Finder, also moves it to the top of the list, and the list is read again whenever MDViewer becomes active. (Thanks to @sanderberents, #25)
- Document windows can be combined into tabs. Window > Merge All Windows, Move Tab to New Window and View > Show Tab Bar now work, and documents open as tabs when "Prefer tabs when opening documents" in System Settings > Desktop & Dock is set to Always (or In Full Screen while in full screen). The Help and Settings windows stay separate. (Thanks to @sanderberents, #26)
- File > Print… (⌘P) prints the document in the active window. ⌘P used to belong to Print… in the toolbar's Export menu, which now has no shortcut.
- Footnotes written as `[^1]` are now rendered as on GitHub: a superscript number in the text, a numbered list at the end of the document, and a ↩ link from each footnote back to the reference. Before, references were shown as plain text, and in Japanese text a definition could become a link that tried to open a file.
- Emoji shortcodes such as `:smile:` and `:+1:` are shown as emoji. Every GitHub shortcode for a Unicode emoji is supported, 1,913 in all (from gemoji 4.1.0); GitHub's own image emoji such as `:octocat:` are not. Shortcodes in code, math and URLs, unknown names, and times such as `12:30:45` are left as they are. Heading anchors are unchanged: `## :sparkles: Features` still links as `#sparkles-features`.
- The Find bar (⌘F) shows the selected match and the number of matches, such as "3/12", or "No Matches". Use the arrow buttons, or Return and Shift-Return, to move between matches. The search starts once you stop typing, and the count is updated when the document reloads. Hidden text, such as the MathML that KaTeX adds for screen readers, is not counted.

### Changed
- The editor in editor mode now uses the same font size as the preview's body text. Changing the size with the toolbar's − / + / reset buttons or View > Increase Font Size, Decrease Font Size and Reset Font Size (⌘+, ⌘−, ⌘0) resizes both the preview and the editor. The editor keeps the system monospaced typeface. Before, the editor text stayed at a small fixed size.
- Moving the Size slider in Settings > Appearance now resizes the preview and the editor in all open windows right away. Before, only windows opened afterwards used the new size. The toolbar buttons and ⌘+, ⌘− and ⌘0 still change only the active window, though the size they set is also saved and used for windows opened later and for the slider's position.

### Fixed
- View > Toggle Sidebar did nothing. It now shows and hides the sidebar of the active window, and stays in step with the toolbar button and with dragging the sidebar closed. (Thanks to @sanderberents, #24)
- Clicking a link to another Markdown file in a document opened the file again in a new tab even if it was already open. The window or tab that shows it is now brought to the front. Links to files that are not open still open as a tab of the front document window, whatever the system setting above.
- The toolbar button that shows and hides the sidebar was missing in every window except the first one, such as windows for files opened from Finder or with File > Open… while another document was showing. It now appears in all document windows.
- Opening a file from the welcome screen with File > Open… or File > Open Recent opened it a second time if it was already open in another window. That window is now brought to the front, and the welcome screen stays as it is.
- The menu bar had two View menus. MDViewer's items (Toggle Editor Mode, Toggle Sidebar, Find… and the font size items) are now in the standard View menu, together with the tab bar and full screen items.
- File > Close was not translated into Japanese.
- View > Increase Font Size, Decrease Font Size and Reset Font Size (⌘+, ⌘−, ⌘0) and Export > Export as PDF… and Export as HTML… (⇧⌘P, ⇧⌘E) did nothing when chosen from the menu bar. They now act on the active window. ⇧⌘P and ⇧⌘E are no longer also assigned to the same items in the toolbar's Export menu.
- View > Find… (⌘F) opened the search bar in every window. It now opens only in the active window or tab.
- When a window with both document tabs and welcome screen tabs was closed at once, MDViewer could quit instead of showing the welcome screen, depending on the order in which the tabs closed. It now shows the welcome screen if any of the closed tabs showed a document. When closing several tabs asks to save changes, the tab the question is about is brought to the front first.

---

## [1.7.6] — 2026-10-21

### Fixed
- Plain text with two dollar amounts on a line, such as `Income $7,463; Expenses $356,143;`, was rendered as inline math. Inline math now follows Pandoc's rule: the opening `$` must be followed by a non-space, and the closing `$` must be preceded by a non-space and not followed by a digit. `\$` is shown as a literal `$`, both in text and inside math. Note that `$ x $`, with spaces inside the dollar signs, is no longer treated as math. (Thanks to @Rodentia, #23)

---

## [1.7.5] — 2026-10-21

### Fixed
- Relative links in a document, such as `dir_name/file_name.md` or `../dir_name/file_name.md`, pointed into the app bundle (`MDViewer.app/Contents/Resources/`) instead of the open file's folder, so the linked document could not be opened. Links now resolve against the open file's folder, and the status bar shows the same path on hover. (Thanks to @ima-hima, #22)

---

## [1.7.4] — 2026-10-09

### Added
- Help > Check for Updates… opens the releases page on GitHub in your default browser. (Thanks to @sanderberents, #21)

---

## [1.7.3] — 2026-10-09

### Fixed
- A `$` inside a code block or inline code was paired with the next `$` and rendered as math. For example, `cp -p $f.conf $f.conf.bak` showed `f.conf` in italic math type. Code is now left as written; math outside code still renders. (#20)

---

## [1.7.2] — 2026-10-09

### Fixed
- Changing the theme from the toolbar no longer changes the theme in Settings > Appearance. The toolbar now changes only that window; the Settings choice applies to all windows and to windows opened later. The automatic GitHub Light/Dark switch that follows the system appearance now changes only the window, not the setting. (Thanks to @bganesh, #14)

---

## [1.7.1] — 2026-10-09

### Fixed
- The two switches in Settings > General had no effect. With the launch switch off, MDViewer now opens the welcome screen instead of reopening documents. Open documents are still recorded while it is off, so turning it back on restores them. With auto-reload off, an open document is no longer reloaded when the file changes on disk; ⌘R still reloads it. Both take effect without relaunching. The launch switch is renamed "Reopen documents from last time on launch", since it reopens every document that was open, not only the last one. (#18)
- Choosing a theme in Settings > Appearance now applies it to open windows right away, as the toolbar's theme menu does. Previously it applied only to windows opened afterwards. (#19)

---

## [1.7.0] — 2026-10-09

### Added
- Body text and headings can now use different fonts. Choose them under Settings > Appearance: Body Font lists the fonts installed on your Mac (System by default), and Heading Font defaults to Same as Body. Characters a chosen font does not have, such as Japanese, are shown in the default font. (Thanks to @bganesh, #16)

### Fixed
- The Code Font setting had no effect on the preview. It is now applied. Font changes in Settings also show up immediately in open windows.

---

## [1.6.2] — 2026-10-09

### Fixed
- The Solarized Light, Solarized Dark, Dracula and Nord themes could be chosen but had no effect, because their style sheets were missing. All four now work, with code blocks drawn on each theme's background. Code in Dracula and Nord is now highlighted with dark-theme colors, which previously happened only for themes with "Dark" in the name. (Thanks to @bganesh, #14)
- On macOS 27, the "Page Size" label in Settings > General wrapped onto two lines. It now fits on one line. (Thanks to @bganesh, #15)

---

## [1.6.1] — 2026-10-09

### Fixed
- While a window was being resized with the editor hidden, the preview flashed white for an instant on every step of the drag. The preview now keeps its last layout until the real size arrives, so it no longer flashes. (Thanks to @harasuke, #17)

---

## [1.6.0] — 2026-10-09

### Changed
- Closing the last document no longer quits MDViewer. The welcome screen is shown instead, so you can open another file without going back to Finder. Closing the welcome screen quits as before. (Thanks to @bganesh, #13)

### Fixed
- Windows opened with File > Open…, from Finder or the Dock, or restored at launch all appeared at the same spot toward the bottom-right of the screen, on top of each other. A new window now opens centered on the screen when no other document window is open, and otherwise cascades down and to the right from the front document window, wrapping back to the top-left when it would go off screen. (Thanks to @bganesh, #12)

---

## [1.5.3] — 2026-10-08

### Fixed
- When MDViewer was quit with several documents open, only one of them was restored at the next launch. MDViewer now remembers every open document and reopens all of them, each in its own window. A document whose window you closed before quitting is not restored. Files that no longer exist are skipped, and the welcome screen is shown if none remain. (Thanks to @bganesh, #11)

---

## [1.5.2] — 2026-10-08

### Fixed
- File > Open… replaced the document in the front window, discarding unsaved edits without asking. When a window already shows a document, the chosen file now opens in a new window, or the existing window is brought to the front if the file is already open. A window that has no document open (the welcome screen) still loads the file in place. (Thanks to @bganesh, #8)

---

## [1.5.1] — 2026-10-08

### Fixed
- File > New replaced the document in the front window, and with several windows open it cleared all of them. File > New now opens a new window and leaves the open documents untouched. A window that has no document open (the welcome screen) is still turned into the new document in place. (Thanks to @bganesh, #10)
- The editor mode is now set per window, so creating a new document no longer switches other windows to the editor.

---

## [1.5.0] — 2026-10-07

### Added
- A copy button appears at the top-right of a code block when you hover over it. Clicking it copies the code to the clipboard. The button is not included in printed pages, PDF exports, or HTML exports. (Thanks to @bganesh, #9)

---

## [1.4.5] — 2026-10-07

### Fixed
- Opening a file that was already open (from Finder by double-clicking or Cmd+Down, or from the Dock icon) created another window with the same file. MDViewer now brings the existing window to the front. (Thanks to @bganesh, #8)
- With several windows open, File > Open… showed the Open dialog once per window. Menu commands (Open, New, Reload, Save, Toggle Editor Mode) now act only on the front window. (Thanks to @bganesh, #8)

---

## [1.4.4] — 2026-10-07

### Fixed
- Opening several files at once from Finder (Cmd+Down) or by dropping them on the Dock icon opened only one or two of them. MDViewer now opens every file in its own window. (Thanks to @bganesh, #7)

---

## [1.4.3] — 2026-10-07

### Fixed
- The File menu had no "Close" item, so Cmd+W did not close the window. "Close" is back in the File menu with the Cmd+W shortcut. (Thanks to @bganesh, #6)

---

## [1.4.2] — 2026-10-02

### Fixed
- On macOS 26 and earlier, `.md` files could not be selected in the Open dialog (they were greyed out) when no app on the Mac declared a file type for Markdown, for example when VS Code was the only other Markdown app. MDViewer now declares the Markdown file type itself, and the Open dialog also accepts whatever type macOS assigns to the `.md` and `.markdown` extensions. (Thanks to @SamCyanide, #5)

---

## [1.4.1] — 2026-10-01

### Fixed
- After the preview crashed repeatedly and was reset, the window kept showing an empty preview with no explanation once the alert was dismissed. A banner above the preview now stays until a render succeeds, with a Try Again button that renders the text currently in the editor. The sidebar no longer lists the headings of the content that crashed. The alert now points to Try Again instead of telling you to reopen the file. (Thanks to @harasuke, #4)

---

## [1.4.0] — 2026-09-27

### Changed
- Mermaid is updated from 10.9.5 to 12.0.0 to fix known vulnerabilities in 10.9.5 (see Fixed). Flowcharts, state, class and other diagrams are now laid out with ELK and drawn with Mermaid's new "neo" look by default, so existing diagrams may be arranged and styled differently. UML use case diagrams are now available. Mermaid 12 needs the WebKit of Safari 17.4 or later; if Safari on your Mac is older, diagrams may not render.
- KaTeX is updated from 0.16.11 to 0.18.9 to fix a known vulnerability in 0.16.11 (GHSA-cg87-wmx4-v546). It only affects the `trust` option, which MDViewer does not enable, so MDViewer was not affected.
- The app now includes the full license texts of its bundled libraries (`THIRD_PARTY_NOTICES.md` in the app's resources), including the libraries bundled inside Mermaid.

### Fixed
- Math was drawn with fallback system fonts instead of KaTeX's own fonts, because the font files were not where KaTeX's stylesheet looked for them. KaTeX's fonts now load.
- The Mermaid update fixes known vulnerabilities in 10.9.5: a crafted diagram could inject HTML or CSS into the preview, or hang it (Gantt and XY charts).

---

## [1.3.1] — 2026-09-23

### Fixed
- When the open file disappeared for a moment and came back (a git branch switch, a cloud sync), the "file doesn't exist" alert stayed on screen even though the preview had already reloaded the file. The alert now closes once the file is read successfully again. If the file stays deleted, the alert remains.

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
