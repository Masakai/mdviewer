// MDViewer JS Bridge
// Handles Markdown rendering and Swift <-> JS communication.

(function () {
    'use strict';

    // -- Mermaid init (must run before DOMContentLoaded diagrams)
    if (typeof mermaid !== 'undefined') {
        mermaid.initialize({
            startOnLoad: false,
            theme: 'default',
            securityLevel: 'loose'
        });
    }

    // -- marked.js configuration
    function buildMarked() {
        const renderer = new marked.Renderer();

        // Collect headings for TOC
        const headings = [];
        renderer.heading = function (text, level, raw) {
            const anchor = slugify(raw);
            headings.push({ level: level, title: raw, anchor: anchor });
            return `<h${level} id="${anchor}">${text}</h${level}>\n`;
        };

        // Code blocks: highlight.js + mermaid detection
        renderer.code = function (code, lang) {
            if (lang === 'mermaid') {
                return `<div class="mermaid">${escapeHtml(code)}</div>`;
            }
            if (typeof hljs !== 'undefined') {
                const highlighted = lang
                    ? hljs.highlight(code, { language: lang, ignoreIllegals: true }).value
                    : hljs.highlightAuto(code).value;
                const langLabel = lang ? `<span class="code-lang-label">${escapeHtml(lang)}</span>` : '';
                return `<pre>${langLabel}<code class="hljs">${highlighted}</code></pre>`;
            }
            return `<pre><code class="hljs">${escapeHtml(code)}</code></pre>`;
        };

        marked.use({
            renderer: renderer,
            gfm: true,
            breaks: false,
            pedantic: false,
        });

        return headings;
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

    // Pre-process KaTeX math before marked parses (to protect $ from being consumed)
    function renderKaTeX(html) {
        if (typeof katex === 'undefined') return html;

        // Block math: $$...$$
        html = html.replace(/\$\$([^$]+?)\$\$/gs, function (_, expr) {
            try {
                return katex.renderToString(expr.trim(), { displayMode: true, throwOnError: false });
            } catch (e) {
                return `<span class="katex-error">${escapeHtml(expr)}</span>`;
            }
        });

        // Inline math: $...$
        html = html.replace(/\$([^$\n]+?)\$/g, function (_, expr) {
            try {
                return katex.renderToString(expr.trim(), { displayMode: false, throwOnError: false });
            } catch (e) {
                return `<span class="katex-error">${escapeHtml(expr)}</span>`;
            }
        });

        return html;
    }

    // -- Public MDViewer API (called from Swift via evaluateJavaScript)
    window.MDViewer = {
        // Render markdown and update DOM
        setContent: function (markdown) {
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
                if (typeof hljs !== 'undefined') {
                    const highlighted = lang
                        ? hljs.highlight(code, { language: lang, ignoreIllegals: true }).value
                        : hljs.highlightAuto(code).value;
                    const langLabel = lang ? `<span class="code-lang-label">${escapeHtml(lang)}</span>` : '';
                    return `<pre>${langLabel}<code class="hljs">${highlighted}</code></pre>`;
                }
                return `<pre><code class="hljs">${escapeHtml(code)}</code></pre>`;
            };

            // Pre-process math: protect $...$ blocks from marked parsing
            const mathBlocks = [];
            let processed = markdown;

            // Extract block math
            processed = processed.replace(/\$\$([^$]+?)\$\$/gs, function (_, expr) {
                const placeholder = `MATHBLOCK_${mathBlocks.length}_END`;
                mathBlocks.push({ type: 'block', expr: expr.trim() });
                return placeholder;
            });

            // Extract inline math
            processed = processed.replace(/\$([^$\n]+?)\$/g, function (_, expr) {
                const placeholder = `MATHINLINE_${mathBlocks.length}_END`;
                mathBlocks.push({ type: 'inline', expr: expr.trim() });
                return placeholder;
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

            document.getElementById('content').innerHTML = html;

            // Render Mermaid diagrams
            if (typeof mermaid !== 'undefined') {
                try {
                    mermaid.run({ querySelector: '.mermaid' });
                } catch (e) {
                    console.warn('Mermaid render error:', e);
                }
            }

            // Notify Swift with heading list
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.headingsExtracted) {
                window.webkit.messageHandlers.headingsExtracted.postMessage(headingsRef);
            }

            // Notify Swift render complete
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.renderComplete) {
                window.webkit.messageHandlers.renderComplete.postMessage(null);
            }
        },

        // Switch theme CSS
        setTheme: function (themeName) {
            const link = document.getElementById('theme-css');
            if (link) {
                link.href = `themes/${themeName}.css`;
            }
            // Update mermaid theme
            if (typeof mermaid !== 'undefined') {
                const isDark = themeName.includes('dark') || themeName === 'dracula' || themeName === 'nord';
                mermaid.initialize({
                    startOnLoad: false,
                    theme: isDark ? 'dark' : 'default',
                    securityLevel: 'loose'
                });
            }
        },

        // Change font size via CSS variable
        setFontSize: function (size) {
            document.documentElement.style.setProperty('--font-size', size + 'px');
        },

        // Scroll to a heading anchor
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

        // Search text
        findText: function (text) {
            if (window.find) {
                window.find(text, false, false, true, false, true, false);
            }
        },

        // Set <base href> so relative links resolve against the opened file's directory
        setBaseURL: function (url) {
            let base = document.getElementById('mdviewer-base');
            if (!base) {
                base = document.createElement('base');
                base.id = 'mdviewer-base';
                document.head.insertBefore(base, document.head.firstChild);
            }
            base.href = url;
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

    // Link hover: notify Swift to display the URL in the status bar
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

    // Link click: fragment links scroll in-page; all others are opened by Swift
    document.addEventListener('click', function (e) {
        const link = e.target.closest('a[href]');
        if (!link) return;

        const href = link.getAttribute('href');
        if (!href) return;

        // Fragment-only links (#section) — let the browser scroll natively
        if (href.startsWith('#')) return;

        e.preventDefault();
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.linkClicked) {
            window.webkit.messageHandlers.linkClicked.postMessage(link.href);
        }
    });

})();
