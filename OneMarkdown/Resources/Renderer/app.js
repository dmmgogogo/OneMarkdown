/* OneMarkdown 渲染层：markdown-it + highlight.js + DOMPurify。
 * Swift 通过 callAsyncJavaScript 调用 window.OneMD.*，JS 通过 webkit.messageHandlers.bridge 回传。 */
(function () {
  'use strict';

  var content = document.getElementById('content');
  var currentDocId = null;
  var MAX_FIND_MATCHES = 5000;

  function post(msg) {
    try {
      window.webkit.messageHandlers.bridge.postMessage(msg);
    } catch (e) {
      /* 在普通浏览器里调试时没有 bridge */
    }
  }

  // 最先注册：vendor 缺失等初始化阶段的异常也要能上报，否则 Swift 侧只会看到白屏
  window.addEventListener('error', function (e) {
    post({ type: 'error', message: '渲染层脚本错误：' + (e && e.message ? e.message : '未知') });
  });

  /* ---------- markdown-it ---------- */

  var LANG_ALIAS = {
    curl: 'bash', sh: 'bash', shell: 'bash', zsh: 'bash', console: 'bash', 'shell-session': 'bash',
    yml: 'yaml', js: 'javascript', jsx: 'javascript', mjs: 'javascript', cjs: 'javascript',
    ts: 'typescript', tsx: 'typescript', py: 'python', py3: 'python',
    json5: 'json', jsonc: 'json', objc: 'objectivec', 'objective-c': 'objectivec',
    'c++': 'cpp', cc: 'cpp', h: 'c', hpp: 'cpp', kt: 'kotlin', kts: 'kotlin',
    rb: 'ruby', rs: 'rust', golang: 'go', cs: 'csharp', 'c#': 'csharp',
    ps: 'powershell', ps1: 'powershell', docker: 'dockerfile', md: 'markdown',
    text: 'plaintext', txt: 'plaintext', plain: 'plaintext', none: 'plaintext'
  };

  function normalizeLang(lang) {
    if (!lang) return '';
    var l = String(lang).trim().toLowerCase().split(/[\s{,]/)[0];
    return LANG_ALIAS[l] || l;
  }

  function githubSlug(s) {
    return String(s)
      .trim()
      .toLowerCase()
      .replace(/[^\p{L}\p{N}\s_-]/gu, '')
      .replace(/\s+/g, '-');
  }

  // shell 代码块：给行首命令名和 -x/--xx 选项补色（hljs 的 bash 语法不区分这些），只处理不在任何 span 内的文本
  function decorateShell(html) {
    var out = '';
    var depth = 0;
    var lineStart = true;
    var parts = html.split(/(<[^>]+>)/);
    for (var i = 0; i < parts.length; i++) {
      var seg = parts[i];
      if (!seg) continue;
      if (seg.charAt(0) === '<') {
        if (seg.charAt(1) === '/') depth--; else if (seg.charAt(seg.length - 2) !== '/') depth++;
        out += seg;
        continue;
      }
      if (depth === 0) {
        seg = seg.replace(/\n([ \t]*)([A-Za-z_][\w.\/-]*)(?=[ \t]|\n|$)/g, '\n$1<span class="hljs-built_in">$2</span>');
        if (lineStart) seg = seg.replace(/^([ \t]*)([A-Za-z_][\w.\/-]*)(?=[ \t]|\n|$)/, '$1<span class="hljs-built_in">$2</span>');
        seg = seg.replace(/(^|[ \t])(-{1,2}[A-Za-z][\w-]*)/g, '$1<span class="hljs-attr">$2</span>');
      }
      lineStart = seg.charAt(seg.length - 1) === '\n';
      out += seg;
    }
    return out;
  }

  var md = window
    .markdownit({
      html: true,
      linkify: true,
      breaks: false,
      typographer: false,
      highlight: function (str, lang) {
        var l = normalizeLang(lang);
        var langClass = l ? ' class="language-' + md.utils.escapeHtml(l) + '"' : '';
        if (l && window.hljs.getLanguage(l)) {
          try {
            var out = window.hljs.highlight(str, { language: l, ignoreIllegals: true }).value;
            if (l === 'bash') out = decorateShell(out);
            return '<pre class="hljs"' + (l ? ' data-lang="' + md.utils.escapeHtml(l) + '"' : '') + '><code' + langClass + '>' + out + '</code></pre>';
          } catch (e) {
            /* 回退到纯文本 */
          }
        }
        return '<pre class="hljs"' + (l ? ' data-lang="' + md.utils.escapeHtml(l) + '"' : '') + '><code' + langClass + '>' + md.utils.escapeHtml(str) + '</code></pre>';
      }
    })
    .use(window.markdownitFootnote)
    .use(window.markdownitTaskLists, { label: true, enabled: false })
    .use(window.markdownItAnchor, { slugify: githubSlug, uniqueSlugStartIndex: 1, tabIndex: false });

  // 只自动识别带协议的 URL 与邮箱；不做 fuzzy link，否则 "README.md" 会因 .md 是顶级域名被当成外链
  md.linkify.set({ fuzzyLink: false, fuzzyIP: false });

  // 表格加一层容器以便横向滚动
  var defaultTableOpen = md.renderer.rules.table_open || function (tokens, idx, options, env, self) { return self.renderToken(tokens, idx, options); };
  var defaultTableClose = md.renderer.rules.table_close || function (tokens, idx, options, env, self) { return self.renderToken(tokens, idx, options); };
  md.renderer.rules.table_open = function (tokens, idx, options, env, self) {
    return '<div class="omd-table-wrap">' + defaultTableOpen(tokens, idx, options, env, self);
  };
  md.renderer.rules.table_close = function (tokens, idx, options, env, self) {
    return defaultTableClose(tokens, idx, options, env, self) + '</div>';
  };

  var PURIFY_CONFIG = {
    USE_PROFILES: { html: true },
    ADD_ATTR: ['id', 'class', 'align', 'width', 'height', 'start', 'checked', 'disabled', 'type', 'open', 'data-lang', 'data-footnote-ref', 'data-footnote-backref'],
    FORBID_TAGS: ['script', 'iframe', 'object', 'embed', 'form', 'style', 'link', 'meta', 'base'],
    // 允许 file: 链接（本地图片/文档），其余沿用默认（http/https/mailto/相对路径）
    ALLOWED_URI_REGEXP: /^(?:(?:(?:f|ht)tps?|mailto|tel|file):|[^a-z]|[a-z+.\-]+(?:[^a-z+.\-:]|$))/i
  };

  /* ---------- 路径改写 ---------- */

  function rewriteURL(value, baseHref) {
    if (!value) return value;
    var v = String(value).trim();
    if (v === '' || v.charAt(0) === '#') return value;
    if (/^[a-z][a-z0-9+.\-]*:/i.test(v) || v.indexOf('//') === 0) return value;
    try {
      return new URL(v, baseHref).href;
    } catch (e) {
      return value;
    }
  }

  function rewriteResources(baseHref) {
    var nodes = content.querySelectorAll('img[src], video[src], audio[src], source[src], video[poster]');
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      if (el.hasAttribute('src')) el.setAttribute('src', rewriteURL(el.getAttribute('src'), baseHref));
      if (el.hasAttribute('poster')) el.setAttribute('poster', rewriteURL(el.getAttribute('poster'), baseHref));
    }
    var links = content.querySelectorAll('a[href]');
    for (var j = 0; j < links.length; j++) {
      var a = links[j];
      var href = a.getAttribute('href') || '';
      if (href.charAt(0) !== '#') a.setAttribute('href', rewriteURL(href, baseHref));
    }
    var imgs = content.querySelectorAll('img');
    for (var k = 0; k < imgs.length; k++) {
      (function (img) {
        img.loading = 'lazy';
        img.addEventListener(
          'error',
          function () {
            var span = document.createElement('span');
            span.className = 'omd-missing';
            var src = img.getAttribute('src') || '';
            try { src = decodeURIComponent(src.replace(/^file:\/\//, '')); } catch (e) { /* ignore */ }
            span.textContent = '图片未找到：' + src;
            span.title = src;
            if (img.parentNode) img.parentNode.replaceChild(span, img);
          },
          { once: true }
        );
      })(imgs[k]);
    }
  }

  /* ---------- 大纲 ---------- */

  function collectOutline() {
    var items = [];
    var heads = content.querySelectorAll('h1, h2, h3, h4, h5, h6');
    var seq = 0;
    var seen = Object.create(null);
    for (var i = 0; i < heads.length; i++) {
      var h = heads[i];
      if (h.closest('.footnotes')) continue;
      if (!h.id) h.id = 'omd-h-' + ++seq;
      // 原始 HTML 标题的显式 id 可能与 anchor 生成的 slug 重复，这里统一去重，保证大纲条目 id 唯一
      if (seen[h.id]) {
        var n = 1;
        while (seen[h.id + '-' + n]) n++;
        h.id = h.id + '-' + n;
      }
      seen[h.id] = true;
      items.push({
        level: parseInt(h.tagName.charAt(1), 10),
        text: (h.textContent || '').trim().slice(0, 200),
        id: h.id
      });
    }
    return items;
  }

  /* ---------- 渲染 ---------- */

  function render(p) {
    p = p || {};
    var t0 = performance.now();
    var sameDoc = p.docId === currentDocId;
    var prevScroll = window.scrollY;
    currentDocId = p.docId || null;

    var html;
    try {
      html = md.render(p.text || '');
    } catch (e) {
      post({ type: 'error', message: 'Markdown 解析失败：' + (e && e.message ? e.message : e) });
      html = '<pre>' + md.utils.escapeHtml(p.text || '') + '</pre>';
    }
    html = window.DOMPurify.sanitize(html, PURIFY_CONFIG);

    // 同一文档热重载时保留查找状态：重建 DOM 后重新收集匹配并恢复高亮
    var keepQuery = sameDoc ? findState.query : '';
    var keepIndex = findState.index;
    clearFind();
    content.innerHTML = html;
    rewriteResources(p.baseHref || document.baseURI);

    post({ type: 'outline', items: collectOutline() });

    if (sameDoc && p.preserveScroll) {
      window.scrollTo(0, prevScroll);
    } else {
      window.scrollTo(0, 0);
    }
    if (keepQuery) {
      findState.query = keepQuery;
      findState.matches = collectMatches(keepQuery);
      findState.index = findState.matches.length ? Math.min(Math.max(keepIndex, 0), findState.matches.length - 1) : -1;
      applyHighlights();
      post({ type: 'findResult', current: findState.index + 1, total: findState.matches.length });
    }
    post({ type: 'rendered', docId: currentDocId || '', ms: Math.round(performance.now() - t0) });
    return true;
  }

  function scrollToId(id) {
    if (!id) return false;
    var el = document.getElementById(id);
    if (!el) {
      // 兼容 URL 编码的锚点
      try { el = document.getElementById(decodeURIComponent(id)); } catch (e) { /* ignore */ }
    }
    if (!el) return false;
    var y = el.getBoundingClientRect().top + window.scrollY - 16;
    window.scrollTo({ top: Math.max(0, y), behavior: 'auto' });
    return true;
  }

  /* ---------- 页内锚点点击 ---------- */

  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (!a) return;
    var href = (a.getAttribute('href') || '').trim();
    if (href === '') {
      e.preventDefault(); // [text]() 这类空链接：什么都不做
      return;
    }
    if (href.charAt(0) === '#') {
      e.preventDefault();
      scrollToId(href.slice(1));
    }
  });

  /* ---------- 查找（CSS Custom Highlight API） ---------- */

  var findState = { query: '', matches: [], index: -1 };
  var supportsHighlight = typeof CSS !== 'undefined' && 'highlights' in CSS && typeof Highlight !== 'undefined';
  // 常驻两个 Highlight 对象，只增删其中的 Range：WebKit 对注册表 delete 不一定重绘，对 Range 变化会
  var allHighlight = supportsHighlight ? new Highlight() : null;
  var currentHighlight = supportsHighlight ? new Highlight() : null;
  if (supportsHighlight) {
    CSS.highlights.set('omd-find', allHighlight);
    CSS.highlights.set('omd-find-current', currentHighlight);
  }

  function collectMatches(query) {
    var q = query.toLowerCase();
    var ranges = [];
    var walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) {
        if (!n.nodeValue || !n.nodeValue.trim()) return NodeFilter.FILTER_SKIP;
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var node;
    while ((node = walker.nextNode())) {
      var text = node.nodeValue;
      var lower = text.toLowerCase();
      if (lower.length !== text.length) lower = text; // 极少数字符小写后长度变化，退化为区分大小写
      var i = 0;
      while ((i = lower.indexOf(q, i)) !== -1) {
        if (i + q.length > text.length) break;
        var r = new Range();
        r.setStart(node, i);
        r.setEnd(node, i + q.length);
        ranges.push(r);
        i += q.length;
        if (ranges.length >= MAX_FIND_MATCHES) return ranges;
      }
    }
    return ranges;
  }

  function applyHighlights() {
    if (!supportsHighlight) return;
    allHighlight.clear();
    currentHighlight.clear();
    for (var i = 0; i < findState.matches.length; i++) allHighlight.add(findState.matches[i]);
    if (findState.index >= 0 && findState.index < findState.matches.length) {
      currentHighlight.add(findState.matches[findState.index]);
    }
  }

  function find(query, direction) {
    query = query == null ? '' : String(query);
    if (!query) {
      clearFind();
      return { current: 0, total: 0 };
    }
    if (query !== findState.query) {
      findState.query = query;
      findState.matches = collectMatches(query);
      findState.index = -1;
      direction = 'next';
    }
    var n = findState.matches.length;
    var result;
    if (n === 0) {
      applyHighlights();
      result = { current: 0, total: 0 };
    } else {
      if (direction === 'prev') {
        findState.index = findState.index <= 0 ? n - 1 : findState.index - 1;
      } else {
        findState.index = findState.index >= n - 1 ? 0 : findState.index + 1;
      }
      applyHighlights();
      var rect = findState.matches[findState.index].getBoundingClientRect();
      if (rect.top < 0 || rect.bottom > window.innerHeight) {
        window.scrollTo({ top: rect.top + window.scrollY - window.innerHeight / 2, behavior: 'auto' });
      }
      result = { current: findState.index + 1, total: n };
    }
    post({ type: 'findResult', current: result.current, total: result.total });
    return result;
  }

  function clearFind() {
    findState.query = '';
    findState.matches = [];
    findState.index = -1;
    if (supportsHighlight) {
      allHighlight.clear();
      currentHighlight.clear();
    }
  }

  /* ---------- 对外接口 ---------- */

  window.OneMD = {
    render: render,
    scrollToHeading: scrollToId,
    find: find,
    clearFind: clearFind
  };

  post({ type: 'ready' });
})();
