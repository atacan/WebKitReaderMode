(function () {
  "use strict";

  if (window.__WebKitReaderMode) {
    return;
  }

  function isReadableScheme() {
    return (
      document.location.protocol === "http:" ||
      document.location.protocol === "https:" ||
      document.location.protocol === "file:"
    );
  }

  function serializedDocument() {
    var html = new XMLSerializer().serializeToString(document);
    if (html.indexOf("<frameset ") !== -1 || html.indexOf("<frameset>") !== -1) {
      return null;
    }

    var parsed = new DOMParser().parseFromString(html, "text/html");
    var base = parsed.createElement("base");
    base.setAttribute("href", document.location.href);

    if (!parsed.head) {
      var head = parsed.createElement("head");
      parsed.documentElement.insertBefore(head, parsed.body);
    }
    parsed.head.insertBefore(base, parsed.head.firstChild);

    return parsed;
  }

  function cspMetaTags() {
    var metas = document.querySelectorAll('meta[http-equiv="Content-Security-Policy"]');
    return Array.prototype.slice.call(metas)
      .map(function (node) {
        return node.getAttribute("content") || "";
      })
      .filter(Boolean);
  }

  function documentLanguage(article) {
    return (
      article.lang ||
      document.documentElement.getAttribute("lang") ||
      (document.querySelector('meta[http-equiv="Content-Language"]') || {}).content ||
      null
    );
  }

  function checkReadability() {
    if (!isReadableScheme() || !document.body) {
      return "unavailable";
    }

    try {
      return isProbablyReaderable(document) ? "available" : "unavailable";
    } catch (error) {
      return "unavailable";
    }
  }

  function extractArticle() {
    if (checkReadability() !== "available") {
      return null;
    }

    var parsed = serializedDocument();
    if (!parsed) {
      return null;
    }

    try {
      var article = new Readability(parsed, {
        debug: false
      }).parse();

      if (!article || !article.content) {
        return null;
      }

      return {
        url: document.location.href,
        domain: document.location.host,
        title: article.title || document.title || document.location.href,
        byline: article.byline || null,
        language: documentLanguage(article),
        direction: article.dir || document.dir || "auto",
        contentHTML: article.content,
        textContent: article.textContent || null,
        excerpt: article.excerpt || null,
        siteName: article.siteName || null,
        publishedTime: article.publishedTime || null,
        cspMetaTags: cspMetaTags()
      };
    } catch (error) {
      return null;
    }
  }

  Object.defineProperty(window, "__WebKitReaderMode", {
    configurable: false,
    enumerable: false,
    writable: false,
    value: Object.freeze({
      checkReadability: checkReadability,
      extractArticle: extractArticle
    })
  });
})();
