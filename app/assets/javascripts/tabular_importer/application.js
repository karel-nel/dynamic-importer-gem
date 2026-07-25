(function () {
  function initializeMappings(root) {
    root.querySelectorAll("[data-ti-mapping]").forEach(function (form) {
      if (form.dataset.tiInitialized) return;
      form.dataset.tiInitialized = "true";

      var selects = Array.from(form.querySelectorAll("[data-ti-mapping-select]"));
      var submit = form.querySelector("[data-ti-mapping-submit]");
      var required = JSON.parse(form.dataset.requiredColumns || "[]");

      function refresh() {
        var selected = selects.map(function (select) { return select.value; }).filter(Boolean);
        selects.forEach(function (select) {
          Array.from(select.options).forEach(function (option) {
            option.hidden = option.value !== "" && option.value !== select.value && selected.includes(option.value);
          });
          var index = selects.indexOf(select) + 1;
          form.querySelectorAll("tr").forEach(function (row) {
            var cell = row.children[index - 1];
            if (cell) cell.classList.toggle("ti-unused", select.value === "");
          });
        });
        var unique = new Set(selected).size === selected.length;
        var complete = required.every(function (key) { return selected.includes(key); });
        if (submit) submit.disabled = !(unique && complete);
      }

      selects.forEach(function (select) { select.addEventListener("change", refresh); });
      refresh();
    });
  }

  function initializeProgress(root) {
    root.querySelectorAll("[data-ti-progress]").forEach(function (container) {
      if (container.dataset.tiInitialized) return;
      container.dataset.tiInitialized = "true";
      var bar = container.querySelector("[data-ti-progress-bar]");
      var message = container.querySelector("[data-ti-progress-message]");
      var count = container.querySelector("[data-ti-progress-count]");

      function poll() {
        fetch(container.dataset.progressUrl, { headers: { Accept: "application/json" }, credentials: "same-origin" })
          .then(function (response) {
            if (!response.ok) throw new Error("Progress request failed");
            return response.json();
          })
          .then(function (data) {
            var percent = data.total > 0 ? Math.min(100, Math.round((data.current / data.total) * 100)) : 0;
            bar.style.width = percent + "%";
            bar.parentElement.setAttribute("aria-valuenow", percent);
            message.textContent = data.message || "Working…";
            count.textContent = data.total > 0 ? data.current + " of " + data.total : "";
            if (data.terminal || data.status === "ready") {
              window.location.reload();
            } else {
              window.setTimeout(poll, 1000);
            }
          })
          .catch(function () { window.setTimeout(poll, 2500); });
      }
      poll();
    });
  }

  function initialize() {
    initializeMappings(document);
    initializeProgress(document);
  }

  document.addEventListener("DOMContentLoaded", initialize);
  document.addEventListener("turbo:load", initialize);
})();
