(function () {
  "use strict";

  var themes = ["light", "dark", "sepia", "black"];
  var fontFamilies = ["systemSans", "systemSerif"];

  function removeMatching(prefix, upperBound) {
    for (var index = 1; index <= upperBound; index += 1) {
      document.body.classList.remove(prefix + index);
    }
  }

  function applyStyle(style) {
    themes.forEach(function (theme) {
      document.body.classList.remove(theme);
    });
    fontFamilies.forEach(function (family) {
      document.body.classList.remove(family);
    });
    removeMatching("font-scale-", 13);

    document.body.classList.add(style.theme || "light");
    document.body.classList.add(style.fontFamily || "systemSans");
    document.body.classList.add("font-scale-" + Math.min(Math.max(style.fontScale || 5, 1), 13));
  }

  Object.defineProperty(window, "__WebKitReaderModePage", {
    configurable: false,
    enumerable: false,
    writable: false,
    value: Object.freeze({
      applyStyle: applyStyle
    })
  });
})();
