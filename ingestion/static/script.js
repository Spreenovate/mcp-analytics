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

  // Self-exclude (?mcpa_exclude=1 sets, =0 unsets). Builders can opt themselves
  // out of their own analytics by visiting once with the param. Stored in
  // localStorage so it survives navigation but not browser data clears.
  try {
    var s = loc.search || "";
    if (s.indexOf("mcpa_exclude=1") !== -1) win.localStorage.setItem("mcpa_exclude", "1");
    if (s.indexOf("mcpa_exclude=0") !== -1) win.localStorage.removeItem("mcpa_exclude");
    if (win.localStorage.getItem("mcpa_exclude") === "1") {
      win.mcpa = function () {};
      return;
    }
  } catch (_) { /* private mode etc. — keep tracking */ }

  var MAX_PROP_KEYS = 20;
  var MAX_PAYLOAD_BYTES = 10 * 1024;

  // --- Persistent visitor id (mode=all) -----------------------------------
  // Opt-in via data-persistent="true". Cookie is first-party on the customer
  // site, not on t.mcp-analytics.com — meaning this tracker alone cannot
  // link a visitor across different customer domains. Good.
  var PERSISTENT = script.getAttribute("data-persistent") === "true";
  var COOKIE_NAME = "_mcpa_id";
  var COOKIE_TTL_DAYS = 730;

  function readCookie() {
    var m = doc.cookie.match(new RegExp("(?:^|; )" + COOKIE_NAME + "=([^;]+)"));
    return m ? m[1] : null;
  }
  function writeCookie(id) {
    var d = new Date();
    d.setTime(d.getTime() + COOKIE_TTL_DAYS * 86400000);
    var attrs = "; expires=" + d.toUTCString() + "; path=/; SameSite=Lax";
    if (loc.protocol === "https:") attrs += "; Secure";
    doc.cookie = COOKIE_NAME + "=" + id + attrs;
  }
  function genId() {
    if (win.crypto && typeof win.crypto.randomUUID === "function") {
      return win.crypto.randomUUID().replace(/-/g, "");
    }
    // Fallback: 32 hex chars from Math.random (weaker, still unique enough)
    var hex = "";
    for (var i = 0; i < 32; i++) hex += Math.floor(Math.random() * 16).toString(16);
    return hex;
  }
  function persistentVisitorId() {
    if (!PERSISTENT) return null;
    var id = readCookie();
    if (!id) {
      try { id = win.localStorage.getItem(COOKIE_NAME); } catch (_) {}
    }
    if (!id) id = genId();
    writeCookie(id);
    try { win.localStorage.setItem(COOKIE_NAME, id); } catch (_) {}
    return id;
  }

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

  function clientSignals() {
    var s = {};
    try {
      var tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
      if (tz) s.tz = tz;
    } catch (_) {}
    try {
      var lang = nav.language || (nav.languages && nav.languages[0]);
      if (lang) s.lang = String(lang).slice(0, 16);
    } catch (_) {}
    try {
      if (win.matchMedia) {
        if (win.matchMedia("(prefers-color-scheme: dark)").matches) s.cs = "dark";
        else if (win.matchMedia("(prefers-color-scheme: light)").matches) s.cs = "light";
      }
    } catch (_) {}
    try {
      // innerWidth/Height = real usable viewport. Cap to keep ints small.
      var vw = win.innerWidth | 0, vh = win.innerHeight | 0;
      if (vw > 0 && vw < 8192) s.vw = vw;
      if (vh > 0 && vh < 8192) s.vh = vh;
    } catch (_) {}
    return s;
  }

  function send(name, props, extra) {
    var payload = {
      site: site,
      name: name,
      url: loc.href,
      referrer: doc.referrer || "",
      props: sanitizeProps(props)
    };

    var sig = clientSignals();
    for (var k in sig) if (sig.hasOwnProperty(k)) payload[k] = sig[k];
    if (extra) {
      for (var k2 in extra) if (extra.hasOwnProperty(k2)) payload[k2] = extra[k2];
    }

    var vid = persistentVisitorId();
    if (vid) payload.visitor_id = vid;

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

  // Engagement state per page lifetime.
  var pageStart = 0;       // ms when current page became active
  var activeMs = 0;        // accumulated active milliseconds
  var maxScrollPct = 0;    // 0..100, max scroll depth reached
  var engagementSent = false;

  function now() { return Date.now ? Date.now() : new Date().getTime(); }

  function startEngagement() {
    pageStart = now();
    activeMs = 0;
    maxScrollPct = computeScrollPct();
    engagementSent = false;
  }

  function computeScrollPct() {
    try {
      var de = doc.documentElement, body = doc.body;
      var height = Math.max(de.scrollHeight, body ? body.scrollHeight : 0);
      var visible = win.innerHeight || de.clientHeight || 0;
      var scroll = win.scrollY || de.scrollTop || (body ? body.scrollTop : 0) || 0;
      if (height <= visible) return 100; // page fits viewport, treat as fully read
      var pct = ((scroll + visible) / height) * 100;
      if (pct < 0) pct = 0;
      if (pct > 100) pct = 100;
      return pct | 0;
    } catch (_) { return 0; }
  }

  function onScroll() {
    var p = computeScrollPct();
    if (p > maxScrollPct) maxScrollPct = p;
  }

  function tickActive() {
    if (!doc.hidden && pageStart > 0) {
      activeMs += now() - pageStart;
      pageStart = now();
    }
  }

  function flushEngagement() {
    if (engagementSent) return;
    tickActive();
    var seconds = Math.round(activeMs / 1000);
    if (seconds <= 0 && maxScrollPct <= 0) return;
    engagementSent = true;
    send("engagement", null, { es: seconds, sd: maxScrollPct });
  }

  function pageview() {
    var path = loc.pathname + loc.search + loc.hash;
    if (path === lastPath) return;
    if (lastPath !== null) flushEngagement(); // SPA nav: send engagement for old page
    lastPath = path;
    startEngagement();
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

  // Engagement listeners. visibilitychange pauses/resumes the active timer.
  // pagehide/beforeunload triggers the final beacon. We use both because
  // mobile browsers often skip beforeunload — pagehide is the modern guarantee.
  doc.addEventListener("visibilitychange", function () {
    if (doc.hidden) {
      tickActive();
      flushEngagement();
    } else {
      pageStart = now(); // resume the timer
    }
  });
  win.addEventListener("pagehide", flushEngagement);
  win.addEventListener("beforeunload", flushEngagement);
  win.addEventListener("scroll", onScroll, { passive: true });

  // Kick off initial pageview once DOM is ready.
  if (doc.readyState === "complete" || doc.readyState === "interactive") {
    pageview();
  } else {
    doc.addEventListener("DOMContentLoaded", pageview);
  }
})();
