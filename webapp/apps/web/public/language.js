// Language choice for pages that exist in English and German. Loaded with
// async so it never delays the first paint. A choice stored by the language
// switcher ("hush.language") always wins; without one, only a first visit to
// "/" from a device whose first language is German moves to the German page.
// The counterpart comes from the page's hreflang links; the script never
// redirects to the address it is already on, and deep links stay where they are.
(function () {
  try {
    var path = location.pathname;
    var current = /^\/de(\/|$)/.test(path) ? "de" : "en";
    var choice = localStorage.getItem("hush.language");
    var device = ((navigator.languages && navigator.languages[0]) || navigator.language || "").toLowerCase().slice(0, 2);
    if (!choice && path === "/" && device === "de") choice = "de";
    if (!choice || choice === current) return;
    var link = document.querySelector('link[rel="alternate"][hreflang="' + choice + '"]');
    var target = link && new URL(link.href).pathname;
    if (target && target !== path) location.replace(target + location.search + location.hash);
  } catch (error) { /* storage blocked or old browser: stay on this page */ }
})();
