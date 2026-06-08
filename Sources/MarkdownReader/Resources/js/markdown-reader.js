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
        MR.renderMermaid();
        MR.renderKaTeX();
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

    getScrollPosition() {
      return {
        x: window.scrollX || document.documentElement.scrollLeft,
        y: window.scrollY || document.documentElement.scrollTop
      };
    },

    renderMermaid() {
      const mermaidBlocks = document.querySelectorAll('code.language-mermaid, pre code.language-mermaid');
      if (mermaidBlocks.length === 0) return;
      if (typeof mermaid === 'undefined') return;

      const scriptTag = document.querySelector('script[src*="markdown-reader.js"]');
      const isDark = scriptTag ? scriptTag.dataset.isDark === 'true' : true;

      mermaid.initialize({
        startOnLoad: false,
        theme: isDark ? 'dark' : 'default',
        themeVariables: {
          primaryColor: 'var(--accent)',
          primaryTextColor: 'var(--ink)',
          primaryBorderColor: 'var(--border)',
          lineColor: 'var(--fg-muted)',
          secondaryColor: 'var(--bg-elevated)',
          tertiaryColor: 'var(--bg-subtle)'
        }
      });

      mermaidBlocks.forEach(block => {
        const pre = block.parentElement;
        if (!pre || pre.tagName !== 'PRE') return;
        const container = document.createElement('div');
        container.className = 'mermaid-container';
        const mermaidDiv = document.createElement('div');
        mermaidDiv.className = 'mermaid';
        mermaidDiv.textContent = block.textContent;
        container.appendChild(mermaidDiv);
        pre.replaceWith(container);
      });

      mermaid.run();
    },

    renderKaTeX() {
      const mathBlocks = document.querySelectorAll('code.language-math, code.language-latex, code.language-katex');
      if (mathBlocks.length === 0) return;
      if (typeof katex === 'undefined') return;

      mathBlocks.forEach(block => {
        const pre = block.parentElement;
        if (!pre || pre.tagName !== 'PRE') return;
        const mathContent = block.textContent;
        const isDisplay = true;
        const container = document.createElement('div');
        container.className = isDisplay ? 'katex-display' : 'katex-inline';
        try {
          katex.render(mathContent, container, {
            displayMode: isDisplay,
            throwOnError: false,
            output: 'html'
          });
        } catch (e) {
          container.textContent = mathContent;
        }
        pre.replaceWith(container);
      });
    },

    init() {
      MR.renderMermaid();
      MR.renderKaTeX();
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
