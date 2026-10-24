// MDViewer JS Bridge
// Handles Markdown rendering and Swift <-> JS communication.

(function () {
    'use strict';

    // -- Shiki highlighter (resolved async on page load)
    let shikiHighlighter = null;

    // Headings of the render #content is showing, re-reported when a render
    // keeps the previous content. Null until this page has drawn one, so a
    // freshly loaded page never reports an empty list over the sidebar.
    let displayedHeadings = null;

    if (window.__shikiReady) {
        window.__shikiReady.then(function (h) { shikiHighlighter = h; });
    }

    // -- Mermaid init (must run before DOMContentLoaded diagrams)
    if (typeof mermaid !== 'undefined') {
        mermaid.initialize({
            startOnLoad: false,
            theme: 'default',
            securityLevel: 'loose'
        });
    }

    function slugify(text) {
        return text
            .toLowerCase()
            .replace(/[^\w\s-]/g, '')
            .replace(/\s+/g, '-')
            .replace(/-+/g, '-')
            .trim();
    }

    function escapeHtml(str) {
        return str
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    // Copy button shown on hover at the top-right of every code block.
    const COPY_ICON = '<svg class="icon-copy" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true">' +
        '<path fill="currentColor" d="M5 1.5A1.5 1.5 0 0 1 6.5 0h6A1.5 1.5 0 0 1 14 1.5v8a1.5 1.5 0 0 1-1.5 1.5h-6A1.5 1.5 0 0 1 5 9.5v-8zm1.5-.5a.5.5 0 0 0-.5.5v8a.5.5 0 0 0 .5.5h6a.5.5 0 0 0 .5-.5v-8a.5.5 0 0 0-.5-.5h-6z"/>' +
        '<path fill="currentColor" d="M2 4.5A1.5 1.5 0 0 1 3.5 3H4v1h-.5a.5.5 0 0 0-.5.5v8a.5.5 0 0 0 .5.5h6a.5.5 0 0 0 .5-.5V12h1v.5A1.5 1.5 0 0 1 9.5 14h-6A1.5 1.5 0 0 1 2 12.5v-8z"/></svg>';
    const CHECK_ICON = '<svg class="icon-check" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true">' +
        '<path fill="currentColor" d="M13.78 3.97a.75.75 0 0 1 0 1.06l-6.5 6.5a.75.75 0 0 1-1.06 0l-3-3a.75.75 0 1 1 1.06-1.06l2.47 2.47 5.97-5.97a.75.75 0 0 1 1.06 0z"/></svg>';
    const COPY_BUTTON = '<button type="button" class="code-copy-button" title="Copy" aria-label="Copy code">' +
        COPY_ICON + CHECK_ICON + '</button>';

    function wrapCodeBlock(preHtml, lang) {
        const label = lang ? `<span class="code-lang-label">${escapeHtml(lang)}</span>` : '';
        return `<div class="code-block-wrapper">${label}${COPY_BUTTON}${preHtml}</div>`;
    }

    function highlightCode(code, lang) {
        const fallback = function () {
            return wrapCodeBlock(`<pre><code>${escapeHtml(code)}</code></pre>`, lang);
        };

        if (!shikiHighlighter) { return fallback(); }

        try {
            const loaded = shikiHighlighter.getLoadedLanguages();
            const resolvedLang = loaded.includes(lang) ? lang : 'text';

            const html = shikiHighlighter.codeToHtml(code, {
                lang: resolvedLang,
                themes: { light: 'github-light', dark: 'github-dark' }
            });

            return wrapCodeBlock(html, lang);
        } catch (_) {
            return fallback();
        }
    }

    // Copies text to the clipboard. navigator.clipboard may be unavailable
    // for local pages, so fall back to execCommand on a temporary textarea.
    async function copyText(text) {
        if (navigator.clipboard && navigator.clipboard.writeText) {
            try {
                await navigator.clipboard.writeText(text);
                return true;
            } catch (_) { /* fall through to the fallback */ }
        }
        const area = document.createElement('textarea');
        area.value = text;
        area.setAttribute('readonly', '');
        area.style.position = 'fixed';
        area.style.opacity = '0';
        document.body.appendChild(area);
        area.select();
        let ok = false;
        try { ok = document.execCommand('copy'); } catch (_) { ok = false; }
        document.body.removeChild(area);
        return ok;
    }

    // Base directory for resolving relative image paths, served via the
    // mdviewer-local:// custom scheme. Set by Swift through setBaseURL().
    let localBaseURL = null;

    // Rewrite relative image sources (and other local resources) to the
    // mdviewer-local:// scheme so the Swift scheme handler can serve them.
    // Absolute URLs (http, https, data, file, the scheme itself) are left alone.
    function rewriteLocalResources(root) {
        if (!localBaseURL) { return; }

        const isAbsolute = function (src) {
            return /^[a-z][a-z0-9+.-]*:/i.test(src) || src.startsWith('//') || src.startsWith('#');
        };

        root.querySelectorAll('img[src]').forEach(function (img) {
            const src = img.getAttribute('src');
            if (!src || isAbsolute(src)) { return; }
            // Encode each path segment but preserve slashes.
            const encoded = src.split('/').map(encodeURIComponent).join('/');
            const path = encoded.startsWith('/') ? encoded.slice(1) : encoded;
            img.setAttribute('src', localBaseURL + path);
        });
    }

    // 脚注の参照を描画した HTML（見出しの目次用の文字列から除くのに使う）
    const FOOTNOTE_REF_HTML = /<sup class="footnote-ref">[\s\S]*?<\/sup>/g;

    // 脚注定義の続きの行としては取り込まない、別のブロックの始まり
    const FOOTNOTE_BLOCK_START = /^ {0,3}(?:#{1,6}(?:\s|$)|>|[-*+](?:\s|$)|\d{1,9}[.)](?:\s|$)|`{3,}|~{3,}|\[\^[^\]\s]+\]:|(?:\*[ \t]*){3,}$|(?:-[ \t]*){3,}$|(?:_[ \t]*){3,}$)/;

    // 脚注（GitHub と同じ [^label] 記法）の marked 拡張。描画1回ごとに作る。
    // 定義は文書のどこに書いてもよく、本文で参照された順に番号を振って文書末に
    // 一覧を出す。id には slugify が出さない「:」を含め、見出しのアンカーと
    // 衝突しないようにする。
    function createFootnoteExtension() {
        const footnotes = new Map(); // 小文字にしたラベル → { tokens, number, refCount }
        const numbered = [];         // 番号順

        const labelKey = function (label) { return label.toLowerCase(); };
        const refId = function (fn, n) {
            return n === 1 ? `fnref:${fn.number}` : `fnref:${fn.number}:${n}`;
        };

        const definition = {
            name: 'footnoteDefinition',
            level: 'block',
            // 段落の途中から定義の行が始まったら、段落をそこで切らせる。marked は
            // 先頭1文字を除いた文字列を渡すので、改行の直後だけを行頭とみなす。
            // 行の途中を返すと「本文[^1]: 続き」のような段落が割れてしまう。
            start: function (src) {
                const m = /\n {0,3}\[\^[^\]\s]+\]:/.exec(src);
                return m ? m.index + 1 : undefined;
            },
            tokenizer: function (src) {
                const head = /^ {0,3}\[\^([^\]\s]+)\]:[ \t]*/.exec(src);
                if (!head) { return undefined; }

                // 1行目の残りと、4文字以上字下げした行（間の空行を含む）、
                // 段落の遅延継続の行を定義の中身とする
                const lines = [];
                let pendingBlanks = 0;
                let rawLength = 0;
                let pos = head[0].length;
                while (pos < src.length) {
                    const nl = src.indexOf('\n', pos);
                    const next = nl === -1 ? src.length : nl + 1;
                    const line = src.slice(pos, nl === -1 ? src.length : nl);
                    if (lines.length === 0) {
                        lines.push(line);
                    } else if (/^[ \t]*$/.test(line)) {
                        pendingBlanks += 1;
                        pos = next;
                        continue;
                    } else if (/^(?: {4}|\t)/.test(line)) {
                        for (; pendingBlanks > 0; pendingBlanks--) { lines.push(''); }
                        lines.push(line.replace(/^(?: {4}|\t)/, ''));
                    } else if (pendingBlanks === 0 && lines[lines.length - 1] !== '' &&
                               !FOOTNOTE_BLOCK_START.test(line)) {
                        lines.push(line);
                    } else {
                        break;
                    }
                    rawLength = next;
                    pos = next;
                }

                // リストの中に書かれても、中身は段落として組む
                const top = this.lexer.state.top;
                this.lexer.state.top = true;
                const tokens = this.lexer.blockTokens(lines.join('\n'), []);
                this.lexer.state.top = top;

                // 同じラベルが2回定義されたら最初のものを使う
                const key = labelKey(head[1]);
                if (!footnotes.has(key)) {
                    footnotes.set(key, { tokens: tokens, number: 0, refCount: 0 });
                }
                return { type: 'footnoteDefinition', raw: src.slice(0, rawLength) };
            },
            // 定義の位置には何も出さず、文書末の一覧にまとめる
            renderer: function () { return ''; }
        };

        // 定義のない参照は拡張では扱わず、文字のまま残す。ブロックをすべて
        // 読んでからインラインを読むので、定義が参照より後ろにあっても分かる。
        const reference = {
            name: 'footnoteRef',
            level: 'inline',
            tokenizer: function (src) {
                const m = /^\[\^([^\]\s]+)\]/.exec(src);
                if (!m || !footnotes.has(labelKey(m[1]))) { return undefined; }
                return { type: 'footnoteRef', raw: m[0], key: labelKey(m[1]) };
            },
            // 見出しの中の参照は、HTML と目次用の文字列とで2回描画されるので、
            // 番号は描画の前に processAllTokens で振っておく
            renderer: function (token) {
                return `<sup class="footnote-ref"><a href="#fn:${token.number}" id="${token.id}" data-footnote-ref>${token.number}</a></sup>`;
            }
        };

        // 本文の参照を先頭から順に数え、続いて脚注の中の参照を脚注の順に数える
        const numberReferences = function (tokens) {
            const visit = function (token) {
                if (token.type !== 'footnoteRef') { return; }
                const fn = footnotes.get(token.key);
                if (fn.number === 0) {
                    numbered.push(fn);
                    fn.number = numbered.length;
                }
                fn.refCount += 1;
                token.number = fn.number;
                token.id = refId(fn, fn.refCount);
            };
            marked.walkTokens(tokens, visit);
            // 脚注の中の参照で番号が増えることがあるので長さを毎回見る
            for (let i = 0; i < numbered.length; i++) {
                marked.walkTokens(numbered[i].tokens, visit);
            }
        };

        // 文書末の脚注一覧。processAllTokens で最後に足したトークンを描画する。
        const list = {
            name: 'footnotes',
            renderer: function () {
                if (numbered.length === 0) { return ''; }
                const parser = this.parser;
                const items = numbered.map(function (fn) {
                    let backrefs = '';
                    for (let n = 1; n <= fn.refCount; n++) {
                        const sup = n === 1 ? '' : `<sup>${n}</sup>`;
                        backrefs += ` <a href="#${refId(fn, n)}" class="footnote-backref" data-footnote-backref aria-label="Back to reference ${fn.number}">↩${sup}</a>`;
                    }
                    // 戻りリンクは最後の段落の末尾に置く（GitHub と同じ）
                    const body = parser.parse(fn.tokens);
                    const lastParagraphEnd = /<\/p>\n?$/;
                    const html = lastParagraphEnd.test(body)
                        ? body.replace(lastParagraphEnd, `${backrefs}</p>\n`)
                        : `${body}<p>${backrefs.trim()}</p>\n`;
                    return `<li id="fn:${fn.number}">\n${html}</li>\n`;
                });
                return `<section class="footnotes" data-footnotes>\n<ol>\n${items.join('')}</ol>\n</section>\n`;
            }
        };

        return {
            extensions: [definition, reference, list],
            hooks: {
                processAllTokens: function (tokens) {
                    numberReferences(tokens);
                    tokens.push({ type: 'footnotes', raw: '' });
                    return tokens;
                }
            }
        };
    }

    // 絵文字ショートコード（:smile:）。対応表は vendor/gemoji.js。
    // 対応表は Object.prototype を持たないが、:constructor: などを確実に弾くため
    // 自身のプロパティだけを見る。
    function emojiFor(name) {
        const table = window.MDViewerEmoji;
        return table && Object.prototype.hasOwnProperty.call(table, name) ? table[name] : undefined;
    }

    const isAsciiAlnum = function (ch) { return /^[A-Za-z0-9]$/.test(ch); };

    // 前後が英数字のもの（12:30:45 の「:30:」など）、直前がコロンのもの（A:::cls: など。
    // ただし :smile::heart: のように絵文字が続く場合は変換する）、対応表にない名前は
    // 文字のまま残す。コードや数式、URL、生の HTML の中は marked がそれぞれの
    // トークンとして先に読むので、ここには来ない。
    const emojiExtension = {
        name: 'emoji',
        level: 'inline',
        // marked はここで返した位置で地の文を切る。対応表にあるものの位置だけを
        // 返さないと、「https:」の「:」で切れて URL の自動リンクが効かなくなる。
        start: function (src) {
            const re = /:([a-z0-9_+-]+):/g;
            let m;
            while ((m = re.exec(src)) !== null) {
                const prev = src.charAt(m.index - 1);
                if (emojiFor(m[1]) !== undefined && !isAsciiAlnum(prev) && prev !== ':' &&
                    !isAsciiAlnum(src.charAt(re.lastIndex))) {
                    return m.index;
                }
                // 「12:30:smile:」の「:smile:」も見つけられるよう1文字だけ進める
                re.lastIndex = m.index + 1;
            }
            return undefined;
        },
        tokenizer: function (src, tokens) {
            const m = /^:([a-z0-9_+-]+):/.exec(src);
            if (!m) { return undefined; }
            const emoji = emojiFor(m[1]);
            if (emoji === undefined || isAsciiAlnum(src.charAt(m[0].length))) { return undefined; }
            const last = tokens[tokens.length - 1];
            if (last && last.type !== 'emoji') {
                const prev = last.raw.slice(-1);
                if (isAsciiAlnum(prev) || prev === ':') { return undefined; }
            }
            return { type: 'emoji', raw: m[0], text: emoji };
        },
        renderer: function (token) { return escapeHtml(token.text); }
    };

    // Sends the headings of what is on screen to the sidebar. Swift also builds
    // the sidebar from the raw text as soon as it changes; this message lands
    // afterwards and describes what was actually drawn.
    function notifyHeadings(headings) {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.headingsExtracted) {
            window.webkit.messageHandlers.headingsExtracted.postMessage(headings);
        }
    }

    // Tells Swift the renderer is alive and showing valid content, which clears
    // the crash-loop guard.
    function notifyRenderComplete() {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.renderComplete) {
            window.webkit.messageHandlers.renderComplete.postMessage(null);
        }
    }

    // Renders the Markdown. Exceptions are caught by the calling setContent.
    async function renderContent(markdown) {
        if (!shikiHighlighter && window.__shikiReady) {
            shikiHighlighter = await Promise.race([
                window.__shikiReady,
                new Promise(function (resolve) { setTimeout(function () { resolve(null); }, 8000); })
            ]);
        }

        const headingsRef = [];
        const renderer = new marked.Renderer();

        renderer.heading = function (text, level, raw) {
            // 目次用の文字列にも拡張の描画結果がそのまま入るので、脚注の参照を除く
            const title = (typeof raw === 'string' ? raw : text).replace(FOOTNOTE_REF_HTML, '');
            const anchor = slugify(title);
            headingsRef.push({ level: level, title: title, anchor: anchor });
            return `<h${level} id="${anchor}">${text}</h${level}>\n`;
        };

        renderer.code = function (code, lang) {
            if (lang === 'mermaid') {
                return `<div class="mermaid">${escapeHtml(code)}</div>`;
            }
            return highlightCode(code, lang);
        };

        // Pre-process math: protect $...$ from marked parsing
        const mathBlocks = [];
        let processed = markdown;

        // Set code aside first: a `$` in a shell snippet such as `cp $f $f.bak`
        // would otherwise be paired up and rendered as math.
        const codeParts = [];
        const stashCode = function (code) {
            codeParts.push(code);
            return `MDCODE_${codeParts.length - 1}_END`;
        };
        processed = processed
            .replace(/^ {0,3}(`{3,}|~{3,})[^\n]*\n[\s\S]*?(?:^ {0,3}\1[`~]*[ \t]*$|(?![\s\S]))/gm, stashCode)
            .replace(/(`+)(?!`)[\s\S]*?[^`]\1(?!`)/g, stashCode);

        // Set escapes aside too, so `\$` is a literal dollar sign. `\\` is
        // taken first in the same pass, so in `\\$` the `$` still opens math.
        const escapeParts = [];
        processed = processed.replace(/\\[\\$]/g, function (esc) {
            escapeParts.push(esc);
            return `MDESC_${escapeParts.length - 1}_END`;
        });
        const restoreEscapes = function (text) {
            return text.replace(/MDESC_(\d+)_END/g, function (_, i) {
                return escapeParts[Number(i)];
            });
        };

        processed = processed.replace(/\$\$([^$]+?)\$\$/gs, function (_, expr) {
            const placeholder = `MATHBLOCK_${mathBlocks.length}_END`;
            mathBlocks.push({ type: 'block', expr: restoreEscapes(expr.trim()) });
            return placeholder;
        });

        // Pandoc's rule for inline math: the opening `$` is followed by a
        // non-space, the closing `$` is preceded by a non-space and not
        // followed by a digit. Prices such as `$7,463 and $356` stay text.
        processed = processed.replace(/\$(?=[^\s$])([^$\n]*?[^\s$])\$(?!\d)/g, function (_, expr) {
            const placeholder = `MATHINLINE_${mathBlocks.length}_END`;
            mathBlocks.push({ type: 'inline', expr: restoreEscapes(expr) });
            return placeholder;
        });

        // marked turns the restored `\$` into `$` and `\\` into `\`.
        processed = restoreEscapes(processed);

        processed = processed.replace(/MDCODE_(\d+)_END/g, function (_, i) {
            return codeParts[Number(i)];
        });

        // 脚注の番号と定義は文書ごとなので、拡張ごと描画のたびに作り直す
        const markdownParser = new marked.Marked(createFootnoteExtension(), { extensions: [emojiExtension] });
        let html = markdownParser.parse(processed, { renderer: renderer });

        // Restore math
        if (typeof katex !== 'undefined') {
            mathBlocks.forEach(function (m, i) {
                const blockPh = new RegExp(`MATHBLOCK_${i}_END`, 'g');
                const inlinePh = new RegExp(`MATHINLINE_${i}_END`, 'g');
                try {
                    const rendered = katex.renderToString(m.expr, {
                        displayMode: m.type === 'block',
                        throwOnError: false
                    });
                    html = html.replace(blockPh, rendered).replace(inlinePh, rendered);
                } catch (e) {
                    html = html.replace(blockPh, escapeHtml(m.expr))
                               .replace(inlinePh, escapeHtml(m.expr));
                }
            });
        }

        const contentEl = document.getElementById('content');

        // #content is the only element in <body>, so replacing it with an
        // empty string turns the page white. If marked returned nothing
        // (a failed read, a file caught mid-write), keep the previous
        // render. Only clear when the document is genuinely empty.
        //
        // Tested with a regex rather than trim(), which would copy the whole
        // rendered HTML just to check it for emptiness.
        const hasContent = /\S/;
        if (!hasContent.test(html) && hasContent.test(markdown)) {
            // The previous render stays on screen. Swift has already rebuilt the
            // sidebar from the new text, which has no headings, so report the
            // ones still shown — and the renderer did complete a render.
            if (displayedHeadings !== null) {
                notifyHeadings(displayedHeadings);
            }
            notifyRenderComplete();
            return;
        }

        contentEl.innerHTML = html;
        displayedHeadings = headingsRef;

        // Resolve relative image paths against the Markdown file's directory
        rewriteLocalResources(contentEl);

        // Render Mermaid diagrams
        if (typeof mermaid !== 'undefined') {
            try {
                mermaid.run({ querySelector: '.mermaid' });
            } catch (e) {
                console.warn('Mermaid render error:', e);
            }
        }

        notifyHeadings(headingsRef);

        notifyRenderComplete();
    }

    // -- Public MDViewer API (called from Swift via evaluateJavaScript)
    window.MDViewer = {

        setContent: async function (markdown) {
            try {
                await renderContent(markdown);
            } catch (e) {
                // Swallowing the exception would leave the preview white while
                // Swift believes the render succeeded. Log it and tell Swift.
                console.error('MDViewer render error:', e);
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.renderFailed) {
                    window.webkit.messageHandlers.renderFailed.postMessage(
                        String(e && e.message ? e.message : e)
                    );
                }
            }
        },

        // isDark comes from Swift: theme names such as "nord" or "dracula"
        // are dark without saying so.
        setTheme: function (themeName, isDark) {
            const link = document.getElementById('theme-css');
            if (link) {
                link.href = `themes/${themeName}.css`;
            }
            // Toggle Shiki dark-theme class
            document.body.classList.toggle('dark-theme', isDark);

            // Update mermaid theme
            if (typeof mermaid !== 'undefined') {
                mermaid.initialize({
                    startOnLoad: false,
                    theme: isDark ? 'dark' : 'default',
                    securityLevel: 'loose'
                });
            }
        },

        // Font stacks are built in Swift (PreviewFont): { body, heading, code }.
        setFonts: function (fonts) {
            const style = document.documentElement.style;
            style.setProperty('--body-font', fonts.body);
            style.setProperty('--heading-font', fonts.heading);
            style.setProperty('--code-font', fonts.code);
        },

        setFontSize: function (size) {
            document.documentElement.style.setProperty('--font-size', size + 'px');
        },

        scrollToAnchor: function (anchorId) {
            const el = document.getElementById(anchorId);
            if (el) {
                el.scrollIntoView({ behavior: 'smooth', block: 'start' });
                el.classList.add('heading-anchor-target');
                setTimeout(function () {
                    el.classList.remove('heading-anchor-target');
                }, 2000);
            }
        },

        findText: function (text) {
            if (window.find) {
                window.find(text, false, false, true, false, true, false);
            }
        },

        setBaseURL: function (url) {
            // Store the base for relative image resolution. We do NOT set a
            // <base> element, since that would also redirect the renderer's own
            // relative resources (theme CSS, vendor scripts) and break them.
            localBaseURL = url;

            // Re-resolve any images already in the DOM (base may arrive after content).
            const contentEl = document.getElementById('content');
            if (contentEl) { rewriteLocalResources(contentEl); }
        }
    };

    // Track scroll position and notify Swift
    let scrollTimer = null;
    window.addEventListener('scroll', function () {
        if (scrollTimer) clearTimeout(scrollTimer);
        scrollTimer = setTimeout(function () {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.scrollPositionChanged) {
                window.webkit.messageHandlers.scrollPositionChanged.postMessage({
                    y: window.scrollY,
                    height: document.body.scrollHeight
                });
            }
        }, 100);
    });

    // Link hover: notify Swift to display URL in status bar. The raw href is
    // sent because link.href resolves against renderer.html inside the app
    // bundle; Swift resolves it against the Markdown file's directory.
    document.addEventListener('mouseover', function (e) {
        const link = e.target.closest('a[href]');
        if (link && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.linkHovered) {
            window.webkit.messageHandlers.linkHovered.postMessage(link.getAttribute('href') || '');
        }
    });
    document.addEventListener('mouseout', function (e) {
        const link = e.target.closest('a[href]');
        if (link && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.linkHovered) {
            window.webkit.messageHandlers.linkHovered.postMessage('');
        }
    });

    // Copy button: copies the text of the code block's <pre>
    document.addEventListener('click', function (e) {
        const button = e.target.closest('.code-copy-button');
        if (!button) return;

        const pre = button.parentElement.querySelector('pre');
        if (!pre) return;

        copyText(pre.textContent).then(function (ok) {
            if (!ok) return;
            button.classList.add('copied');
            button.title = 'Copied';
            clearTimeout(button._copiedTimer);
            button._copiedTimer = setTimeout(function () {
                button.classList.remove('copied');
                button.title = 'Copy';
            }, 1500);
        });
    });

    // Link click: fragment links scroll in-page; all others handled by Swift
    document.addEventListener('click', function (e) {
        const link = e.target.closest('a[href]');
        if (!link) return;

        const href = link.getAttribute('href');
        if (!href) return;

        if (href.startsWith('#')) return;

        e.preventDefault();
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.linkClicked) {
            window.webkit.messageHandlers.linkClicked.postMessage(href);
        }
    });

})();
