// Page-feature glue. Lives in app/assets/javascripts/ so it's served as
// an external file (with a content digest by Propshaft) and the views
// can keep a strict CSP that forbids inline <script>. Each block is
// guarded by a feature-detect so loading on a page that doesn't use
// the feature is a no-op.
(function () {
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
    copyTargets.forEach(function (el) {
      el.addEventListener("click", function () { copy(el); });
      el.addEventListener("keydown", function (e) {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          copy(el);
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
