// MDViewer JS Bridge
// Handles Markdown rendering and Swift <-> JS communication.

(function () {
    'use strict';

    // -- Shiki highlighter (resolved async on page load)
    let shikiHighlighter = null;

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

    function highlightCode(code, lang) {
        const fallback = function () {
            const label = lang ? `<span class="code-lang-label">${escapeHtml(lang)}</span>` : '';
            return `<div class="code-block-wrapper">${label}<pre><code>${escapeHtml(code)}</code></pre></div>`;
        };

        if (!shikiHighlighter) { return fallback(); }

        try {
            const loaded = shikiHighlighter.getLoadedLanguages();
            const resolvedLang = loaded.includes(lang) ? lang : 'text';

            const html = shikiHighlighter.codeToHtml(code, {
                lang: resolvedLang,
                themes: { light: 'github-light', dark: 'github-dark' }
            });

            if (lang) {
                return html
                    .replace('<pre ', `<div class="code-block-wrapper"><span class="code-lang-label">${escapeHtml(lang)}</span><pre `)
                    .replace('</pre>', '</pre></div>');
            }
            return html;
        } catch (_) {
            return fallback();
        }
    }

    // -- Public MDViewer API (called from Swift via evaluateJavaScript)
    window.MDViewer = {

        setContent: async function (markdown) {
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

        setTheme: function (themeName) {
            const link = document.getElementById('theme-css');
            if (link) {
                link.href = `themes/${themeName}.css`;
            }
            // Toggle Shiki dark-theme class
            const isDark = themeName.includes('dark');
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
