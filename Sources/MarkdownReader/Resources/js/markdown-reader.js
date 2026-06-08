(function() {
  const MR = {
    version: '2.0.0',

    scrollToHeading(id) {
      const el = document.getElementById(id);
      if (el) {
        el.scrollIntoView({ behavior: 'smooth', block: 'start' });
        el.classList.add('outline-highlight');
        setTimeout(() => {
          el.classList.add('fade-out');
          setTimeout(() => {
            el.classList.remove('outline-highlight', 'fade-out');
          }, 300);
        }, 1500);
      }
    },

    scrollToLine(lineNumber) {
      const target = document.querySelector(`[data-line="${lineNumber}"]`);
      if (target) {
        target.scrollIntoView({ behavior: 'smooth', block: 'center' });
        return true;
      }
      let closest = null;
      let minDiff = Infinity;
      document.querySelectorAll('[data-line]').forEach(el => {
        const diff = Math.abs(parseInt(el.dataset.line) - lineNumber);
        if (diff < minDiff) {
          minDiff = diff;
          closest = el;
        }
      });
      if (closest) {
        closest.scrollIntoView({ behavior: 'smooth', block: 'center' });
        return true;
      }
      return false;
    },

    replaceContent(html) {
      const content = document.getElementById('mr-content');
      if (content) {
        content.innerHTML = html;
        MR._searchHighlights = [];
        MR.renderMermaid();
        MR.renderKaTeX();
        MR.renderAdmonitions();
        if (typeof Prism !== 'undefined') {
          Prism.highlightAll();
        }
      }
    },

    getVisibleHeading() {
      const headings = document.querySelectorAll('h1[id], h2[id], h3[id], h4[id], h5[id], h6[id]');
      let visible = null;
      const scrollTop = window.scrollY || document.documentElement.scrollTop;
      const threshold = 100;
      for (let i = headings.length - 1; i >= 0; i--) {
        if (headings[i].getBoundingClientRect().top <= threshold) {
          visible = {
            id: headings[i].id,
            level: parseInt(headings[i].tagName.charAt(1)),
            title: headings[i].textContent.trim(),
            lineNumber: parseInt(headings[i].dataset.line || '0')
          };
          break;
        }
      }
      return visible;
    },

    getTopVisibleLine() {
      const elements = document.querySelectorAll('[data-line]');
      const threshold = 120;
      let best = null;
      let minDiff = Infinity;
      for (let i = elements.length - 1; i >= 0; i--) {
        const rect = elements[i].getBoundingClientRect();
        const diff = threshold - rect.top;
        if (diff >= 0 && diff < minDiff) {
          minDiff = diff;
          best = elements[i];
        }
      }
      if (best) {
        return parseInt(best.dataset.line) || 1;
      }
      return 1;
    },

    getScrollPosition() {
      return {
        x: window.scrollX || document.documentElement.scrollLeft,
        y: window.scrollY || document.documentElement.scrollTop
      };
    },

    _resolveThemeColors() {
      const scriptTag = document.querySelector('script[src*="markdown-reader.js"]');
      const isDark = scriptTag ? scriptTag.dataset.isDark === 'true' : true;

      // Mermaid strips var() refs (sanitizeDirective) and khroma needs hex for adjust/darken/invert.
      const style = getComputedStyle(document.documentElement);
      const resolve = (v) => {
        if (!v || !v.startsWith('var(')) return v;
        const inner = v.slice(4, v.lastIndexOf(')')).trim();
        const name = inner.includes(',') ? inner.slice(0, inner.indexOf(',')).trim() : inner;
        let resolved = style.getPropertyValue(name).trim();
        if (resolved.startsWith('var(')) resolved = resolve(resolved);
        return resolved || v;
      };

      // Canvas fillStyle converts CSS colors to #rrggbb but drops the alpha channel.
      // For rgba() values (common in theme borders/muted text), blend with the
      // surface background first so the result matches what users see on screen.
      const toHex = (cssColor) => {
        if (!cssColor || cssColor.startsWith('#')) return cssColor;
        const ctx = document.createElement('canvas').getContext('2d');
        ctx.fillStyle = cssColor;
        const result = ctx.fillStyle;
        // If rgba was converted to #rrggbb, alpha was lost — pre-blend it
        if (result.startsWith('#') && cssColor.includes('rgba')) {
          const match = cssColor.match(/rgba?\(\s*(\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)/);
          if (match) {
            const r = parseInt(match[1]), g = parseInt(match[2]), b = parseInt(match[3]), a = parseFloat(match[4]);
            const surface = isDark ? [24, 24, 26] : [255, 255, 255];
            const blended = [
              Math.round(surface[0] * (1 - a) + r * a),
              Math.round(surface[1] * (1 - a) + g * a),
              Math.round(surface[2] * (1 - a) + b * a)
            ];
            return '#' + blended.map(c => c.toString(16).padStart(2, '0')).join('');
          }
        }
        return result;
      };

      return {
        isDark,
        themeVariables: {
          primaryColor: toHex(resolve('var(--accent)')),
          primaryTextColor: toHex(resolve('var(--ink)')),
          primaryBorderColor: toHex(resolve('var(--border)')),
          lineColor: toHex(resolve('var(--fg-muted)')),
          secondaryColor: toHex(resolve('var(--bg-elevated)')),
          tertiaryColor: toHex(resolve('var(--bg-subtle)'))
        }
      };
    },

    _showMermaidError(container, msg) {
      container.innerHTML = '';
      const errBox = document.createElement('div');
      errBox.className = 'mermaid-error';
      errBox.innerHTML = '<strong>Mermaid</strong> — ' + msg;
      container.appendChild(errBox);
    },

    renderMermaid() {
      const mermaidBlocks = document.querySelectorAll('code.language-mermaid, pre code.language-mermaid');
      if (mermaidBlocks.length === 0) return;
      if (typeof mermaid === 'undefined') return;

      const { isDark, themeVariables } = MR._resolveThemeColors();

      mermaid.initialize({
        startOnLoad: false,
        securityLevel: 'loose',
        theme: isDark ? 'dark' : 'default',
        themeVariables
      });

      let idx = 0;
      mermaidBlocks.forEach(block => {
        const pre = block.parentElement;
        if (!pre || pre.tagName !== 'PRE') return;
        const source = block.textContent;
        const container = document.createElement('div');
        container.className = 'mermaid-container';
        container.dataset.mermaidSource = source;
        const id = 'mermaid-' + (++idx) + '-' + Math.random().toString(36).slice(2);
        mermaid.render(id, source).then(({ svg, bindFunctions }) => {
          container.innerHTML = svg;
          if (bindFunctions) bindFunctions(container);
        }).catch(err => {
          console.error('[MarkdownReader] mermaid.render error:', err);
          const detail = (err && err.message) ? String(err.message).substring(0, 200) : String(err).substring(0, 200);
          MR._showMermaidError(container, '渲染失败：' + detail);
        });
        pre.replaceWith(container);
      });
    },

    rerenderMermaid() {
      const containers = document.querySelectorAll('.mermaid-container');
      if (containers.length === 0) return;
      if (typeof mermaid === 'undefined') return;

      const { isDark, themeVariables } = MR._resolveThemeColors();

      mermaid.initialize({
        startOnLoad: false,
        securityLevel: 'loose',
        theme: isDark ? 'dark' : 'default',
        themeVariables
      });

      containers.forEach((container, idx) => {
        const source = container.dataset.mermaidSource;
        if (!source) return;
        const id = 'mermaid-re-' + idx + '-' + Math.random().toString(36).slice(2);
        container.innerHTML = '';
        mermaid.render(id, source).then(({ svg, bindFunctions }) => {
          container.innerHTML = svg;
          if (bindFunctions) bindFunctions(container);
        }).catch(err => {
          console.error('[MarkdownReader] mermaid rerender error:', err);
          const detail = (err && err.message) ? String(err.message).substring(0, 200) : String(err).substring(0, 200);
          MR._showMermaidError(container, '渲染失败：' + detail);
        });
      });
    },

    renderKaTeX() {
      const mathElements = document.querySelectorAll('code.language-math, code.language-latex, code.language-katex');
      if (mathElements.length === 0) return;
      if (typeof katex === 'undefined') return;

      mathElements.forEach(block => {
        const pre = block.parentElement;
        const isInline = !pre || pre.tagName !== 'PRE';
        const mathContent = block.textContent;

        if (isInline) {
          const span = document.createElement('span');
          span.className = 'katex-inline';
          try {
            katex.render(mathContent, span, {
              displayMode: false,
              throwOnError: false,
              output: 'html'
            });
          } catch (e) {
            span.textContent = mathContent;
          }
          block.replaceWith(span);
        } else {
          const container = document.createElement('div');
          container.className = 'katex-display';
          try {
            katex.render(mathContent, container, {
              displayMode: true,
              throwOnError: false,
              output: 'html'
            });
          } catch (e) {
            container.textContent = mathContent;
          }
          pre.replaceWith(container);
        }
      });
    },

    renderAdmonitions() {
      const blockquotes = document.querySelectorAll('blockquote');
      const types = {
        'note': { icon: 'ℹ', label: 'Note' },
        'tip': { icon: '💡', label: 'Tip' },
        'warning': { icon: '⚠', label: 'Warning' },
        'caution': { icon: '🔥', label: 'Caution' },
        'important': { icon: '❗', label: 'Important' }
      };
      blockquotes.forEach(bq => {
        const firstP = bq.querySelector('p');
        if (!firstP) return;
        const text = firstP.textContent.trim();
        for (const [type, config] of Object.entries(types)) {
          const prefix = '[' + type.charAt(0).toUpperCase() + type.slice(1) + ']';
          if (text.startsWith(prefix)) {
            bq.classList.add('admonition', 'admonition-' + type);
            const titleSpan = document.createElement('span');
            titleSpan.className = 'admonition-title';
            titleSpan.textContent = config.label;
            const rest = text.slice(prefix.length).trim();
            if (rest) {
              firstP.textContent = rest;
            } else {
              firstP.remove();
            }
            bq.insertBefore(titleSpan, bq.firstChild);
            break;
          }
        }
      });
    },

    _searchHighlights: [],

    highlightSearch(query, caseSensitive, wholeWord, currentIndex) {
      MR.clearSearchHighlight();
      if (!query) return 0;

      const content = document.getElementById('mr-content');
      if (!content) return 0;

      const flags = caseSensitive ? 'g' : 'gi';
      let pattern = query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      if (wholeWord) pattern = '\\b' + pattern + '\\b';

      let regex;
      try {
        regex = new RegExp(pattern, flags);
      } catch (e) {
        return 0;
      }

      const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT, null);
      const textNodes = [];
      while (walker.nextNode()) {
        textNodes.push(walker.currentNode);
      }

      const allMatches = [];

      textNodes.forEach(node => {
        const text = node.textContent;
        let match;
        while ((match = regex.exec(text)) !== null) {
          allMatches.push({
            node: node,
            index: match.index,
            length: match[0].length
          });
        }
      });

      // Sort by document position in REVERSE order for safe insertion.
      // Processing from end to start prevents surroundContents from
      // splitting text nodes and invalidating later match offsets.
      const sortedAllMatches = allMatches.slice().sort((a, b) => {
        const cmp = a.node.compareDocumentPosition(b.node);
        if (cmp & Node.DOCUMENT_POSITION_FOLLOWING) return 1;  // b comes first → process b before a
        if (cmp & Node.DOCUMENT_POSITION_PRECEDING) return -1; // a comes first → process a before b
        return b.index - a.index; // same node: higher index first
      });

      // Collect mark elements in document order for indexing
      const markElements = [];

      // Use Range API to wrap matches in <mark> elements
      for (const m of sortedAllMatches) {
        const range = document.createRange();
        try {
          range.setStart(m.node, m.index);
          range.setEnd(m.node, m.index + m.length);
        } catch (e) {
          continue;
        }

        const mark = document.createElement('mark');
        mark.className = 'mr-search-highlight';

        try {
          range.surroundContents(mark);
          markElements.unshift(mark); // prepend to maintain document order
        } catch (e) {
          // surroundContents fails when range crosses element boundaries — skip
          continue;
        }
      }

      // Assign sequential indices in document order
      markElements.forEach((mark, i) => {
        mark.dataset.searchIndex = i;
      });
      MR._searchHighlights = markElements;

      const matchCount = markElements.length;

      // Highlight current match
      if (currentIndex >= 0 && currentIndex < matchCount) {
        const currentMark = content.querySelector(`mark[data-search-index="${currentIndex}"]`);
        if (currentMark) {
          currentMark.classList.add('mr-search-current');
          currentMark.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
      }

      return matchCount;
    },

    setSearchCurrent(currentIndex) {
      const content = document.getElementById('mr-content');
      if (!content) return;
      const prev = content.querySelector('.mr-search-current');
      if (prev) prev.classList.remove('mr-search-current');
      if (currentIndex >= 0) {
        const mark = content.querySelector(`mark[data-search-index="${currentIndex}"]`);
        if (mark) {
          mark.classList.add('mr-search-current');
          mark.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
      }
    },

    clearSearchHighlight() {
      for (const mark of MR._searchHighlights) {
        const parent = mark.parentNode;
        if (parent) {
          while (mark.firstChild) {
            parent.insertBefore(mark.firstChild, mark);
          }
          parent.removeChild(mark);
          parent.normalize();
        }
      }
      MR._searchHighlights = [];
    },

    init() {
      MR.renderMermaid();
      MR.renderKaTeX();
      MR.renderAdmonitions();
      if (typeof Prism !== 'undefined') {
        Prism.highlightAll();
      }
    }
  };

  window.MR = MR;

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', MR.init);
  } else {
    MR.init();
  }
})();
