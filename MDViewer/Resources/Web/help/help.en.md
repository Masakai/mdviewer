# MDViewer Help

A reference for Markdown and Mermaid diagram syntax, with live-rendered examples. Use the sidebar to jump to a section.

---

## Headings

Six levels, `#` through `######`.

```
# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6
```

# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6

---

## Emphasis

```
*italic* or _italic_
**bold** or __bold__
***bold italic***
~~strikethrough~~
```

*italic* or _italic_
**bold** or __bold__
***bold italic***
~~strikethrough~~

---

## Lists

### Unordered

```
- Item one
- Item two
  - Nested item
- Item three
```

- Item one
- Item two
  - Nested item
- Item three

### Ordered

```
1. First step
2. Second step
   1. Sub-step
3. Third step
```

1. First step
2. Second step
   1. Sub-step
3. Third step

### Task list

```
- [x] Done
- [ ] Not done
```

- [x] Done
- [ ] Not done

---

## Links and images

```
[MDViewer on GitHub](https://github.com)
![Alt text](image.png)
```

[MDViewer on GitHub](https://github.com)

---

## Blockquotes

```
> A single-line quote.
>
> A quote can span
> multiple lines.
```

> A single-line quote.
>
> A quote can span
> multiple lines.

---

## Code

Inline code: `` `let x = 1` `` renders as `let x = 1`.

Fenced code block with a language tag for syntax highlighting:

````
```swift
func greet(name: String) -> String {
    "Hello, \(name)!"
}
```
````

```swift
func greet(name: String) -> String {
    "Hello, \(name)!"
}
```

---

## Tables

```
| Feature      | Supported |
| ------------ | --------- |
| Tables       | Yes       |
| Footnotes    | Yes       |
| Mermaid      | Yes       |
```

| Feature      | Supported |
| ------------ | --------- |
| Tables       | Yes       |
| Footnotes    | Yes       |
| Mermaid      | Yes       |

---

## Footnotes

A reference becomes a superscript number. Footnotes are numbered in the order they are referenced and listed at the end of the document, each with a ↩ link back to where it was referenced. The definition can go anywhere in the document; a reference without a definition stays as plain text.

```
Here is a footnote reference.[^1]

[^1]: This is the footnote content.
```

Here is a footnote reference.[^1]

[^1]: This is the footnote content.

---

## Emoji

Write an emoji by its shortcode between colons. Every shortcode for a Unicode emoji in GitHub's list is supported (1,913 shortcodes from [gemoji](https://github.com/github/gemoji) 4.1.0). GitHub's own image emoji such as `:octocat:` are not included.

```
Ship it :rocket: :+1: :white_check_mark:
```

Ship it :rocket: :+1: :white_check_mark:

Shortcodes inside code and math stay as they are, and so do unknown names such as `:foo:` and colons between letters or digits such as `12:30:45`.

---

## Horizontal rule

```
---
```

---

## Math (KaTeX)

Inline math: `$E = mc^2$` renders as $E = mc^2$.

Block math:

```
$$
\int_0^\infty e^{-x^2} \, dx = \frac{\sqrt{\pi}}{2}
$$
```

$$
\int_0^\infty e^{-x^2} \, dx = \frac{\sqrt{\pi}}{2}
$$

The LaTeX delimiters `\(...\)` (inline) and `\[...\]` (block) are off by default, because in Markdown `\(` and `\[` write a literal `(` and `[`. Turn on "Treat `\(` `\)` and `\[` `\]` as math delimiters" in Settings > General to render them as math. With it on, `\\(` is still text, and a `\[` with no `\]` before the next `\[` or blank line is still a bracket.

---

## Mermaid diagrams

MDViewer renders [Mermaid](https://mermaid.js.org) diagrams inside fenced code blocks tagged `mermaid`. Note: to *document* the syntax on this page, the outer fence below uses 4 backticks so the inner 3-backtick example stays literal — in your own files, 3 backticks around a `mermaid` block is all you need.

### Flowchart

````
```mermaid
flowchart LR
    A[Start] --> B{Decision}
    B -- Yes --> C[Do the thing]
    B -- No --> D[Skip it]
    C --> E[End]
    D --> E
```
````

```mermaid
flowchart LR
    A[Start] --> B{Decision}
    B -- Yes --> C[Do the thing]
    B -- No --> D[Skip it]
    C --> E[End]
    D --> E
```

### Sequence diagram

````
```mermaid
sequenceDiagram
    participant U as User
    participant A as App
    participant S as Server
    U->>A: Click "Save"
    A->>S: PUT /document
    S-->>A: 200 OK
    A-->>U: Show saved indicator
```
````

```mermaid
sequenceDiagram
    participant U as User
    participant A as App
    participant S as Server
    U->>A: Click "Save"
    A->>S: PUT /document
    S-->>A: 200 OK
    A-->>U: Show saved indicator
```

### Class diagram

````
```mermaid
classDiagram
    class DocumentViewModel {
        +String text
        +URL? fileURL
        +Bool isDirty
        +save()
        +newDocument()
    }
    class FileWatcher {
        +start(url)
        +stop()
    }
    DocumentViewModel --> FileWatcher
```
````

```mermaid
classDiagram
    class DocumentViewModel {
        +String text
        +URL? fileURL
        +Bool isDirty
        +save()
        +newDocument()
    }
    class FileWatcher {
        +start(url)
        +stop()
    }
    DocumentViewModel --> FileWatcher
```

### State diagram

````
```mermaid
stateDiagram-v2
    [*] --> Clean
    Clean --> Dirty: edit
    Dirty --> Clean: save
    Dirty --> [*]: discard
    Clean --> [*]: close
```
````

```mermaid
stateDiagram-v2
    [*] --> Clean
    Clean --> Dirty: edit
    Dirty --> Clean: save
    Dirty --> [*]: discard
    Clean --> [*]: close
```

### Entity relationship diagram

````
```mermaid
erDiagram
    DOCUMENT ||--o{ HEADING : contains
    DOCUMENT {
        string fileURL
        bool isDirty
    }
    HEADING {
        int level
        string title
        string anchor
    }
```
````

```mermaid
erDiagram
    DOCUMENT ||--o{ HEADING : contains
    DOCUMENT {
        string fileURL
        bool isDirty
    }
    HEADING {
        int level
        string title
        string anchor
    }
```

### Gantt chart

````
```mermaid
gantt
    title Release Plan
    dateFormat  YYYY-MM-DD
    section Design
    Spec review        :done,    des1, 2026-07-01, 3d
    section Build
    Implementation      :active,  dev1, 2026-07-04, 5d
    Code review          :         rev1, after dev1, 2d
    section Ship
    Notarize & release   :         rel1, after rev1, 1d
```
````

```mermaid
gantt
    title Release Plan
    dateFormat  YYYY-MM-DD
    section Design
    Spec review        :done,    des1, 2026-07-01, 3d
    section Build
    Implementation      :active,  dev1, 2026-07-04, 5d
    Code review          :         rev1, after dev1, 2d
    section Ship
    Notarize & release   :         rel1, after rev1, 1d
```

### Pie chart

````
```mermaid
pie title Editor usage
    "Viewer only" : 40
    "Editor mode" : 45
    "New file"    : 15
```
````

```mermaid
pie title Editor usage
    "Viewer only" : 40
    "Editor mode" : 45
    "New file"    : 15
```

### User journey

````
```mermaid
journey
    title Open and edit a file
    section Open
      Launch MDViewer: 5: User
      Open a file: 4: User
    section Edit
      Toggle editor mode: 4: User
      Type changes: 3: User
    section Save
      Press Cmd+S: 5: User
```
````

```mermaid
journey
    title Open and edit a file
    section Open
      Launch MDViewer: 5: User
      Open a file: 4: User
    section Edit
      Toggle editor mode: 4: User
      Type changes: 3: User
    section Save
      Press Cmd+S: 5: User
```

### Mindmap

````
```mermaid
mindmap
  root((MDViewer))
    Viewer
      Syntax highlighting
      Math (KaTeX)
      Mermaid diagrams
    Editor
      Split view
      New file
      Save / Save As
    Export
      PDF
      HTML
```
````

```mermaid
mindmap
  root((MDViewer))
    Viewer
      Syntax highlighting
      Math (KaTeX)
      Mermaid diagrams
    Editor
      Split view
      New file
      Save / Save As
    Export
      PDF
      HTML
```

### Timeline

````
```mermaid
timeline
    title MDViewer version history
    2026-05-05 : v1.0.3
    2026-05-22 : v1.1.0 : Editor mode
    2026-06-12 : v1.1.1 : Local image fix
    2026-07-19 : v1.2.0 : New file creation
```
````

```mermaid
timeline
    title MDViewer version history
    2026-05-05 : v1.0.3
    2026-05-22 : v1.1.0 : Editor mode
    2026-06-12 : v1.1.1 : Local image fix
    2026-07-19 : v1.2.0 : New file creation
```

---

## Tips for this app

- **Live preview**: while in editor mode (⌘E), the preview pane updates as you type.
- **Table of contents**: the sidebar (⌘⇧S) lists headings from the current document — including this one.
- **Theme**: pick a light or dark syntax theme from the toolbar palette icon for that window, or choose "Use Settings Theme" to go back. In Settings > Appearance, turn on "Follow System Appearance" to use a Light Theme and a Dark Theme that switch with the Mac.
- **Export**: render this or any document to PDF or HTML from the Export menu.
- **Updates**: Help > Check for Updates… asks GitHub for the latest release and tells you whether a newer version is out. If there is one, Open Release Page takes you to the download. MDViewer only connects when you choose the menu item, and it does not install updates itself.
