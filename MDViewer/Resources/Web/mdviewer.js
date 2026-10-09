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
            const anchor = slugify(typeof raw === 'string' ? raw : text);
            headingsRef.push({ level: level, title: typeof raw === 'string' ? raw : text, anchor: anchor });
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

        processed = processed.replace(/\$\$([^$]+?)\$\$/gs, function (_, expr) {
            const placeholder = `MATHBLOCK_${mathBlocks.length}_END`;
            mathBlocks.push({ type: 'block', expr: expr.trim() });
            return placeholder;
        });

        processed = processed.replace(/\$([^$\n]+?)\$/g, function (_, expr) {
            const placeholder = `MATHINLINE_${mathBlocks.length}_END`;
            mathBlocks.push({ type: 'inline', expr: expr.trim() });
            return placeholder;
        });

        processed = processed.replace(/MDCODE_(\d+)_END/g, function (_, i) {
            return codeParts[Number(i)];
        });

        let html = marked.parse(processed, { renderer: renderer });

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

    // Link hover: notify Swift to display URL in status bar
    document.addEventListener('mouseover', function (e) {
        const link = e.target.closest('a[href]');
        if (link && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.linkHovered) {
            window.webkit.messageHandlers.linkHovered.postMessage(link.href || '');
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
            window.webkit.messageHandlers.linkClicked.postMessage(link.href);
        }
    });

})();
