function toggleTheme() {
  const html = document.documentElement;
  const icon = document.getElementById("darkModeToggle")?.querySelector("img");
  const currentTheme = html.getAttribute("data-bs-theme") || "light";
  const newTheme = currentTheme === "dark" ? "light" : "dark";

  html.setAttribute("data-bs-theme", newTheme);
  localStorage.setItem("theme", newTheme);

  if (icon) {
    icon.src = newTheme === "dark" ? "../icons/sun.svg" : "../icons/moon.svg";
  }
}

document.addEventListener("DOMContentLoaded", () => {
  const toggleBtn = document.getElementById("darkModeToggle");
  const icon = toggleBtn?.querySelector("img");
  const storedTheme = localStorage.getItem("theme") || "light";

  document.documentElement.setAttribute("data-bs-theme", storedTheme);

  if (icon) {
    icon.src = storedTheme === "dark" ? "../icons/sun.svg" : "../icons/moon.svg";
  }

  if (toggleBtn) {
    toggleBtn.addEventListener("click", toggleTheme);
  }
});
