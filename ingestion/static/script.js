(function () {
  "use strict";

  var doc = document;
  var win = window;
  var nav = navigator;
  var loc = win.location;

  var script = doc.currentScript || (function () {
    var all = doc.getElementsByTagName("script");
    return all[all.length - 1];
  })();
  if (!script) return;

  var site = script.getAttribute("data-site");
  if (!site) return;

  var endpoint = script.getAttribute("data-api") ||
    (script.src ? script.src.replace(/\/script\.js.*$/, "/event") : "/event");

  // Hard opt-outs before doing anything else.
  if (nav.doNotTrack === "1" || win.doNotTrack === "1" || nav.msDoNotTrack === "1") {
    if (script.getAttribute("data-respect-dnt") !== "false") {
      win.mcpa = function () {};
      return;
    }
  }

  // Headless / automation detection — skip client-side.
  if (nav.webdriver) return;
  if (win.__nightmare || win._phantom || win.callPhantom) return;
  if (/HeadlessChrome/.test(nav.userAgent || "")) return;
  if (loc.hostname === "localhost" && script.getAttribute("data-local") !== "true") {
    // Default: don't track on localhost. Override with data-local="true".
    return;
  }

  var MAX_PROP_KEYS = 20;
  var MAX_PAYLOAD_BYTES = 10 * 1024;

  function sanitizeProps(props) {
    if (!props || typeof props !== "object") return undefined;
    var out = {};
    var keys = Object.keys(props).slice(0, MAX_PROP_KEYS);
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i];
      var v = props[k];
      var t = typeof v;
      if (t === "string" || t === "number" || t === "boolean") {
        out[k] = v;
      }
    }
    return out;
  }

  function send(name, props) {
    var payload = {
      site: site,
      name: name,
      url: loc.href,
      referrer: doc.referrer || "",
      props: sanitizeProps(props)
    };

    var body;
    try {
      body = JSON.stringify(payload);
    } catch (_) {
      return;
    }
    if (body.length > MAX_PAYLOAD_BYTES) return;

    // Send as text/plain to stay in the CORS "simple request" set and
    // avoid OPTIONS preflights per event. Server treats the body as JSON
    // regardless of declared Content-Type.
    try {
      if (nav.sendBeacon) {
        var blob = new Blob([body], { type: "text/plain" });
        if (nav.sendBeacon(endpoint, blob)) return;
      }
    } catch (_) {}

    try {
      var xhr = new XMLHttpRequest();
      xhr.open("POST", endpoint, true);
      xhr.setRequestHeader("Content-Type", "text/plain");
      xhr.send(body);
    } catch (_) {}
  }

  var lastPath = null;

  function pageview() {
    var path = loc.pathname + loc.search + loc.hash;
    if (path === lastPath) return;
    lastPath = path;
    send("pageview", null);
  }

  // Public API: window.mcpa('track', 'name', {...}) or window.mcpa('pageview')
  function mcpa() {
    var args = Array.prototype.slice.call(arguments);
    var cmd = args.shift();
    if (cmd === "track") {
      send(args[0], args[1]);
    } else if (cmd === "pageview") {
      pageview();
    }
  }
  // Flush any calls queued before the script loaded.
  var queued = win.mcpa && win.mcpa.q;
  win.mcpa = mcpa;
  if (Array.isArray(queued)) {
    for (var i = 0; i < queued.length; i++) mcpa.apply(null, queued[i]);
  }

  // SPA hooks.
  var pushState = win.history.pushState;
  if (pushState) {
    win.history.pushState = function () {
      var r = pushState.apply(this, arguments);
      pageview();
      return r;
    };
    win.addEventListener("popstate", pageview);
  }

  // Kick off initial pageview once DOM is ready.
  if (doc.readyState === "complete" || doc.readyState === "interactive") {
    pageview();
  } else {
    doc.addEventListener("DOMContentLoaded", pageview);
  }
})();
