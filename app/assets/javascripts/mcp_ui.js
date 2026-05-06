// Page-feature glue. Lives in app/assets/javascripts/ so it's served as
// an external file (with a content digest by Propshaft) and the views
// can keep a strict CSP that forbids inline <script>. Each block is
// guarded by a feature-detect so loading on a page that doesn't use
// the feature is a no-op.
(function () {
  // mcpa() queue stub — the tracker script may load after this file (defer);
  // pushing to the queue ensures events aren't lost.
  var mcpa = window.mcpa = window.mcpa || function () {
    (window.mcpa.q = window.mcpa.q || []).push(arguments);
  };

  // --- Generic event-attr conventions ----------------------------------
  // Read data-prop-<name>="value" attributes off an element into a props
  // object. data-prop-foo-bar → { foo_bar: value }. Returns undefined when
  // there are no prop attrs so we don't emit empty objects.
  var readProps = function (el) {
    var props = {};
    var found = false;
    Array.from(el.attributes).forEach(function (a) {
      if (a.name.indexOf("data-prop-") === 0) {
        props[a.name.slice("data-prop-".length).replace(/-/g, "_")] = a.value;
        found = true;
      }
    });
    return found ? props : undefined;
  };

  // Page-load: <meta name="mcpa-track" content="event_name"
  //                  data-prop-reason="…"> fires once on load.
  var trackMeta = document.querySelector('meta[name="mcpa-track"]');
  if (trackMeta) {
    mcpa("track", trackMeta.getAttribute("content"), readProps(trackMeta));
  }

  // Click: <a data-track-click="event_name" data-prop-location="…">
  document.querySelectorAll("[data-track-click]").forEach(function (el) {
    el.addEventListener("click", function () {
      mcpa("track", el.getAttribute("data-track-click"), readProps(el));
    });
  });

  // First input on a field: <input data-track-input-once="event_name">
  document.querySelectorAll("[data-track-input-once]").forEach(function (el) {
    el.addEventListener("input", function () {
      mcpa("track", el.getAttribute("data-track-input-once"), readProps(el));
    }, { once: true });
  });

  // --- Click-to-copy (verify & verified pages) -------------------------
  var copyTargets = document.querySelectorAll(".copyable");
  if (copyTargets.length > 0) {
    var toast = document.getElementById("copy-toast");
    var toastTimer;
    var showToast = function (text) {
      if (!toast) return;
      toast.textContent = text;
      toast.hidden = false;
      toast.classList.add("show");
      clearTimeout(toastTimer);
      toastTimer = setTimeout(function () {
        toast.classList.remove("show");
        setTimeout(function () { toast.hidden = true; }, 200);
      }, 1400);
    };
    var copy = function (el) {
      var text = el.getAttribute("data-copy");
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(
          function () { showToast("Copied ✓"); },
          function () { showToast("Copy failed — select manually"); }
        );
      } else {
        var r = document.createRange();
        r.selectNode(el);
        window.getSelection().removeAllRanges();
        window.getSelection().addRange(r);
        try {
          document.execCommand("copy");
          window.getSelection().removeAllRanges();
          showToast("Copied ✓");
        } catch (e) {
          showToast("Copy failed");
        }
      }
    };
    var trackedCopy = false;
    var trackCopy = function (el) {
      if (trackedCopy) return;
      trackedCopy = true;
      var label = el.previousElementSibling && el.previousElementSibling.previousElementSibling
        ? el.previousElementSibling.previousElementSibling.textContent.trim()
        : "unknown";
      mcpa("track", "token_copied", { field: label });
    };
    copyTargets.forEach(function (el) {
      el.addEventListener("click", function () { copy(el); trackCopy(el); });
      el.addEventListener("keydown", function (e) {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          copy(el);
          trackCopy(el);
        }
      });
    });
  }

  // --- Disconnect-confirm (settings page) ------------------------------
  // Server-side authorization is the actual defence; this is UX only.
  var confirmButtons = document.querySelectorAll("button[data-confirm]");
  confirmButtons.forEach(function (btn) {
    btn.addEventListener("click", function (e) {
      if (!window.confirm(btn.getAttribute("data-confirm"))) {
        e.preventDefault();
      }
    });
  });
})();
