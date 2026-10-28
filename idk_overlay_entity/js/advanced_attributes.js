// advanced_attributes.js

document.addEventListener("DOMContentLoaded", function () {
  const toggle = document.getElementById("toggleAdvancedAttributes");
  const section = document.getElementById("advancedAttributesOptions");

  // Show/hide section when toggled
  toggle.addEventListener("change", () => {
    localStorage.setItem("toggleAdvancedAttributes", toggle.checked);
    section.style.display = toggle.checked ? "block" : "none";
    sendLabelOverlaySettings();
  });

  // Initialize toggle and section
  const showAdv = localStorage.getItem("toggleAdvancedAttributes");
  toggle.checked = showAdv === null ? true : showAdv === 'true';
  section.style.display = toggle.checked ? "block" : "none";

  // Handle each attribute toggle
  [
    "showPrice", "showSize", "showURL",
    "showStatus", "showOwner", "showType"
  ].forEach(id => {
    const checkbox = document.getElementById(id);
    if (checkbox) {
      const saved = localStorage.getItem(id);
      checkbox.checked = saved === null ? true : saved === 'true';

      checkbox.addEventListener("change", () => {
        localStorage.setItem(id, checkbox.checked);
        sendLabelOverlaySettings();
      });
    }
  });
});