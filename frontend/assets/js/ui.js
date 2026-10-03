// Arquivo: frontend/assets/js/ui.js
(() => {
  "use strict";

  const titleByScreen = {
    busca: ["Sua próxima ideia começa aqui.", "Configure uma busca e acompanhe os nomes encontrados pelo scanner."],
    resultados: ["Nomes com potencial.", "Resultados da execução atual, diretamente do scanner."],
    log: ["Acompanhe cada etapa.", "Mensagens registradas pelo scanner local."],
  };

  function navigate(screenName) {
    const target = document.querySelector(`[data-screen="${screenName}"]`);
    if (!target || !titleByScreen[screenName]) return;
    const switchScreen = () => {
      document.querySelectorAll("[data-screen]").forEach((section) => {
        const active = section === target;
        section.hidden = !active;
        section.classList.toggle("is-active", active);
      });
      document.querySelectorAll("[data-navigate]").forEach((button) => {
        const active = button.dataset.navigate === screenName;
        button.classList.toggle("is-selected", active);
        if (active) button.setAttribute("aria-current", "page");
        else button.removeAttribute("aria-current");
      });
      const [title, subtitle] = titleByScreen[screenName];
      document.getElementById("screen-title").textContent = title;
      document.getElementById("screen-subtitle").textContent = subtitle;
      const region = document.getElementById("scroll-region");
      region.scrollTo({ top: 0, behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" });
      target.querySelector("h2")?.focus({ preventScroll: true });
      window.dispatchEvent(new CustomEvent("domain:screen-ready", { detail: { screen: screenName } }));
      window.dispatchEvent(new CustomEvent("domain:navigate", { detail: { screen: screenName } }));
    };
    if (document.startViewTransition && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      document.startViewTransition(switchScreen);
    } else switchScreen();
  }

  function showToast(message) {
    const toast = document.getElementById("toast");
    toast.textContent = message;
    toast.hidden = false;
    clearTimeout(showToast.timer);
    showToast.timer = setTimeout(() => { toast.hidden = true; }, 3200);
  }

  function showGlobalState(message) {
    const state = document.getElementById("global-state");
    state.textContent = message || "";
    state.hidden = !message;
  }

  function updateClock() {
    const now = new Date();
    document.getElementById("status-clock").textContent = new Intl.DateTimeFormat("pt-BR", { hour: "2-digit", minute: "2-digit", hour12: false }).format(now);
  }

  document.addEventListener("click", (event) => {
    const button = event.target.closest("[data-navigate]");
    if (button) navigate(button.dataset.navigate);
  });

  document.querySelectorAll(".glass-regular, .button, .icon-button").forEach((element) => {
    element.addEventListener("pointermove", (event) => {
      const rect = element.getBoundingClientRect();
      element.style.setProperty("--pointer-x", `${event.clientX - rect.left}px`);
      element.style.setProperty("--pointer-y", `${event.clientY - rect.top}px`);
    }, { passive: true });
  });

  const region = document.getElementById("scroll-region");
  region.addEventListener("scroll", () => region.classList.toggle("is-scrolled", region.scrollTop > 24), { passive: true });
  updateClock();
  setInterval(updateClock, 30000);

  window.DomainUI = Object.freeze({ navigate, showToast, showGlobalState });
})();
