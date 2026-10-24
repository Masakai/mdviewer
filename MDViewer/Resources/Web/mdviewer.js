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

    // 見出しの目次用の文字列を作っている間だけ、拡張のトークンを HTML ではなく
    // 文字列として出す。'title' は目次の表示名、'anchor' はアンカーの元になる文字列
    let inlineTextMode = null;

    // marked の unescape と同じ処理（marked は公開していないので写した）。v1.7.6 と
    // 同じアンカーを作るため、目次用の文字列を marked と同じ手順で作る。
    function unescapeEntities(html) {
        return html.replace(/&(#(?:\d+)|(?:#x[0-9A-Fa-f]+)|(?:\w+));?/gi, function (_, name) {
            name = name.toLowerCase();
            if (name === 'colon') { return ':'; }
            if (name.charAt(0) === '#') {
                return name.charAt(1) === 'x'
                    ? String.fromCharCode(parseInt(name.substring(2), 16))
                    : String.fromCharCode(+name.substring(1));
            }
            return '';
        });
    }

    // marked は段落や地の文を切るたびに、残りの文字列で拡張の start() を呼ぶ。毎回
    // 先頭から探すと長い文書・段落で2乗の時間がかかるので、直前の結果を使い回す。
    // 新しい文字列が直前の文字列の末尾部分なら、見つけておいた位置をずらして返し、
    // その位置を過ぎたときだけ探し直す。find は位置か、見つからなければ -1 を返す。
    // 強調の中身やリストの項目は別の文字列として読まれるので、外側の文字列の結果が
    // 上書きされないよう、最近の数件を覚えておく。
    function memoizeStart(find) {
        const recent = []; // { src, at }。新しいものが先頭
        return function (src) {
            for (let i = 0; i < recent.length; i++) {
                const last = recent[i];
                if (src.length > last.src.length) { continue; }
                const offset = last.src.length - src.length;
                const isTail = last.src.startsWith(src.slice(0, 64), offset) &&
                    last.src.endsWith(src.slice(-64));
                if (isTail && (last.at === -1 || last.at >= offset)) {
                    // 使った結果は先頭に戻し、外側の文字列の結果が押し出されないようにする
                    recent.splice(i, 1);
                    recent.unshift(last);
                    return last.at === -1 ? undefined : last.at - offset;
                }
            }
            const at = find(src);
            recent.unshift({ src: src, at: at });
            if (recent.length > 8) { recent.pop(); }
            return at === -1 ? undefined : at;
        };
    }

    // marked.walkTokens は戻り値を concat で集めるので、トークン数の2乗のコピーが
    // 起きる。値を集めずに同じ順でたどる。
    function forEachToken(tokens, visit) {
        tokens.forEach(function (token) {
            visit(token);
            if (token.type === 'table') {
                token.header.forEach(function (cell) { forEachToken(cell.tokens, visit); });
                token.rows.forEach(function (row) {
                    row.forEach(function (cell) { forEachToken(cell.tokens, visit); });
                });
            } else if (token.type === 'list') {
                forEachToken(token.items, visit);
            } else if (token.tokens) {
                forEachToken(token.tokens, visit);
            }
        });
    }

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
            start: (function () {
                const findNewline = memoizeStart(function (src) {
                    const m = /\n {0,3}\[\^[^\]\s]+\]:/.exec(src);
                    return m ? m.index : -1;
                });
                return function (src) {
                    const at = findNewline(src);
                    return at === undefined ? undefined : at + 1;
                };
            })(),
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
            // 見出しの中の参照は、HTML と目次用の文字列とで何度か描画されるので、
            // 番号は描画の前に processAllTokens で振っておく。目次の表示名には出さず、
            // アンカーには v1.7.6 と同じく元の「[^1]」を使う。
            renderer: function (token) {
                if (inlineTextMode === 'title') { return ''; }
                if (inlineTextMode === 'anchor') { return token.raw; }
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
            forEachToken(tokens, visit);
            // 脚注の中の参照で番号が増えることがあるので長さを毎回見る
            for (let i = 0; i < numbered.length; i++) {
                forEachToken(numbered[i].tokens, visit);
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
    // トークンとして先に読むので、ここには来ない。描画1回ごとに作る。
    function createEmojiExtension() {
        return {
            name: 'emoji',
            level: 'inline',
            // marked はここで返した位置で地の文を切る。対応表にあるものの位置だけを
            // 返さないと、「https:」の「:」で切れて URL の自動リンクが効かなくなる。
            start: memoizeStart(function (src) {
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
                return -1;
            }),
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
            // 見出しのアンカーは v1.7.6 と同じくショートコードの文字列から作る
            renderer: function (token) {
                return inlineTextMode === 'anchor' ? token.raw : escapeHtml(token.text);
            }
        };
    }

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

        // 目次の表示名は絵文字にし、アンカーは v1.7.6 と同じく元のショートコードの
        // 文字列から作る（既存の文書内リンクや、Swift 側が原文から作る目次と合わせる）。
        // marked の renderer.heading は描画済みの文字列しか受け取れないので、見出しの
        // トークンごと受け取る拡張の描画で置き換える。
        const headingExtension = {
            name: 'heading',
            renderer: function (token) {
                const parser = this.parser;
                const plainText = function (mode) {
                    inlineTextMode = mode;
                    try {
                        return unescapeEntities(parser.parseInline(token.tokens, parser.textRenderer));
                    } finally {
                        inlineTextMode = null;
                    }
                };
                const level = token.depth;
                const text = parser.parseInline(token.tokens);
                const title = plainText('title');
                const anchor = slugify(plainText('anchor'));
                headingsRef.push({ level: level, title: title, anchor: anchor });
                return `<h${level} id="${anchor}">${text}</h${level}>\n`;
            }
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

        // 脚注の番号と定義は文書ごとなので、拡張ごと描画のたびに作り直す。
        // 定義が1つもない文書では、脚注の拡張は使わない。
        const markedExtensions = [{ extensions: [createEmojiExtension(), headingExtension] }];
        if (/\[\^[^\]\s]+\]:/.test(processed)) {
            markedExtensions.unshift(createFootnoteExtension());
        }
        const markdownParser = new marked.Marked(...markedExtensions);
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
                // 図は非同期に描かれるので、描き終えたら図の中の文字も含めて検索し直す
                const hasDiagrams = contentEl.querySelector('.mermaid') !== null;
                const diagramsDone = function () {
                    if (hasDiagrams) { refreshSearch(); }
                };
                Promise.resolve(mermaid.run({ querySelector: '.mermaid' })).then(diagramsDone, function (e) {
                    console.warn('Mermaid render error:', e);
                    diagramsDone();
                });
            } catch (e) {
                console.warn('Mermaid render error:', e);
            }
        }

        notifyHeadings(headingsRef);

        notifyRenderComplete();

        // 描画で検索のハイライトが消えるので、検索中なら同じ語で数え直す
        refreshSearch();
    }

    // -- ページ内検索（⌘F の検索バー）
    // WKWebView の find は一致したかどうかしか返さず件数が取れない。件数と
    // 「何件目か」とハイライトの位置がずれないよう、検索はすべてここで行う。
    // 一致した部分は <mark> で囲む（CSS Custom Highlight API は Safari 17.2 からで、
    // macOS 14.0 の WebKit では使えない）。
    const SEARCH_HIT_CLASS = 'mdviewer-search-hit';
    const SEARCH_CURRENT_CLASS = 'mdviewer-search-current';
    // 画面に見えない文字（KaTeX の読み上げ用 MathML など）と、<mark> を入れられない
    // 場所（SVG の <text>、Mermaid が図に置き換える前のソース）は数えない
    const SEARCH_SKIP_SELECTOR = '.katex-mathml, script, style, noscript, template';
    const SEARCH_BLOCK_SELECTOR = 'p, li, h1, h2, h3, h4, h5, h6, td, th, pre, blockquote, div, section, dt, dd, figcaption, caption, #content';
    const SVG_NS = 'http://www.w3.org/2000/svg';

    let searchQuery = '';
    let searchHits = [];    // 一致ごとの <mark> の配列。1件が複数の要素にまたがることがある
    let searchIndex = -1;

    function escapeRegExp(text) {
        return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    }

    function searchStatus() {
        return { current: searchIndex + 1, total: searchHits.length };
    }

    function notifySearchStatus() {
        const status = searchStatus();
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.searchResultsChanged) {
            window.webkit.messageHandlers.searchResultsChanged.postMessage(status);
        }
        return status;
    }

    function removeSearchMarks() {
        const contentEl = document.getElementById('content');
        const parents = new Set();
        contentEl.querySelectorAll('mark.' + SEARCH_HIT_CLASS).forEach(function (mark) {
            parents.add(mark.parentNode);
            mark.replaceWith(...mark.childNodes);
        });
        // 分割したテキストノードをつなぎ直し、次の検索で語が途中で切れないようにする
        parents.forEach(function (parent) { parent.normalize(); });
        searchHits = [];
        searchIndex = -1;
    }

    // 画面に見えているテキストノードを、文書の順に集める
    function collectVisibleText(root) {
        const visibility = new Map();
        const isVisible = function (el) {
            if (!visibility.has(el)) {
                visibility.set(el, el.getClientRects().length > 0 &&
                    window.getComputedStyle(el).visibility === 'visible');
            }
            return visibility.get(el);
        };
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode: function (node) {
                const parent = node.parentElement;
                if (!parent || parent.namespaceURI === SVG_NS || parent.closest(SEARCH_SKIP_SELECTOR)) {
                    return NodeFilter.FILTER_REJECT;
                }
                if (parent.closest('.mermaid') && !parent.closest('svg')) {
                    return NodeFilter.FILTER_REJECT;
                }
                return isVisible(parent) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
            }
        });

        // ブロックの境目には空白でも語でもない文字を挟み、段落をまたいで一致させない
        let text = '';
        const segments = [];
        let previousBlock = null;
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
            const block = node.parentElement.closest(SEARCH_BLOCK_SELECTOR);
            if (previousBlock !== null && block !== previousBlock) { text += '\u0000'; }
            previousBlock = block;
            segments.push({ node: node, start: text.length, end: text.length + node.data.length });
            text += node.data;
        }
        return { text: text, segments: segments };
    }

    // 一致した範囲を <mark> で囲む。テキストノードを分割するので、後ろの一致から
    // 処理して、前の一致の位置がずれないようにする。
    function markMatches(segments, matches) {
        const hits = [];
        let segIndex = segments.length - 1;
        for (let i = matches.length - 1; i >= 0; i--) {
            const match = matches[i];
            const marks = [];
            while (segIndex >= 0 && segments[segIndex].start >= match.end) { segIndex--; }
            for (let s = segIndex; s >= 0 && segments[s].end > match.start; s--) {
                const seg = segments[s];
                const from = Math.max(match.start, seg.start) - seg.start;
                const to = Math.min(match.end, seg.end) - seg.start;
                if (from >= to) { continue; }
                seg.node.splitText(to);
                const piece = seg.node.splitText(from);
                const mark = document.createElement('mark');
                mark.className = SEARCH_HIT_CLASS;
                piece.parentNode.replaceChild(mark, piece);
                mark.appendChild(piece);
                marks.unshift(mark);
            }
            hits.unshift(marks);
        }
        return hits;
    }

    function findMatches(text, query) {
        // 改行などで折り返された語も見つかるよう、検索語の空白は空白の並びに一致させる
        const words = query.trim().split(/\s+/).map(escapeRegExp);
        const pattern = new RegExp(words.join('\\s+'), 'giu');
        const matches = [];
        let m;
        while ((m = pattern.exec(text)) !== null) {
            matches.push({ start: m.index, end: m.index + m[0].length });
        }
        return matches;
    }

    // 検索語で一致を数え直してハイライトする。index は選ぶ一致（範囲外なら丸める）、
    // null なら画面の上端より下にある最初の一致を選ぶ。
    function runSearch(index, scroll) {
        removeSearchMarks();
        if (!searchQuery.trim()) { return searchStatus(); }
        const collected = collectVisibleText(document.getElementById('content'));
        searchHits = markMatches(collected.segments, findMatches(collected.text, searchQuery));
        if (searchHits.length === 0) { return searchStatus(); }

        if (index === null) {
            const below = searchHits.findIndex(function (marks) {
                return marks[0].getBoundingClientRect().bottom > 0;
            });
            index = below === -1 ? 0 : below;
        }
        selectSearchHit(Math.min(index, searchHits.length - 1), scroll);
        return searchStatus();
    }

    function selectSearchHit(index, scroll) {
        if (searchIndex >= 0 && searchHits[searchIndex]) {
            searchHits[searchIndex].forEach(function (mark) { mark.classList.remove(SEARCH_CURRENT_CLASS); });
        }
        searchIndex = index;
        const marks = searchHits[index];
        marks.forEach(function (mark) { mark.classList.add(SEARCH_CURRENT_CLASS); });
        if (scroll) { marks[0].scrollIntoView({ block: 'center' }); }
    }

    function moveSearch(step) {
        if (searchHits.length === 0) { return notifySearchStatus(); }
        const count = searchHits.length;
        selectSearchHit(((searchIndex + step) % count + count) % count, true);
        return notifySearchStatus();
    }

    // 描画し直した後に、同じ語・同じ番号で数え直す。読んでいる位置は動かさない。
    function refreshSearch() {
        if (!searchQuery.trim()) { return; }
        runSearch(Math.max(searchIndex, 0), false);
        notifySearchStatus();
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

        // 検索バーの検索。どれも { current, total } を返し、searchResultsChanged でも
        // Swift に知らせる（描画し直したときの数え直しも同じ経路で届く）。
        search: function (query) {
            searchQuery = query;
            runSearch(null, true);
            return notifySearchStatus();
        },

        searchNext: function () { return moveSearch(1); },

        searchPrevious: function () { return moveSearch(-1); },

        clearSearch: function () {
            searchQuery = '';
            removeSearchMarks();
            return searchStatus();
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
