// Arquivo: frontend/assets/js/tela_log.js
(() => {
  "use strict";
  const content = document.getElementById("log-content");
  const state = document.getElementById("log-state");
  const caption = document.getElementById("log-caption");

  async function refresh() {
    state.hidden = false;
    state.textContent = "Consultando log da execução atual…";
    try {
      const data = await window.DomainApi.log();
      if (typeof data.text !== "string") throw new Error("O arquivo de log tem um formato inesperado.");
      content.textContent = data.text;
      caption.textContent = data.scanning ? "Scanner em execução · mensagens do arquivo atual" : "Mensagens registradas pelo scanner";
      state.textContent = data.text.trim() ? "" : "O arquivo de log atual ainda está vazio.";
      state.hidden = Boolean(data.text.trim());
      content.scrollTop = content.scrollHeight;
    } catch (error) {
      content.textContent = "";
      state.hidden = false;
      state.textContent = error.message || "Não foi possível ler o arquivo de log.";
    }
  }

  document.querySelector('[data-refresh="log"]').addEventListener("click", refresh);
  window.addEventListener("domain:refresh-log", refresh);
  window.addEventListener("domain:scan-started", refresh);
  window.addEventListener("domain:screen-ready", (event) => { if (event.detail.screen === "log") refresh(); });
  window.DomainLogScreen = Object.freeze({ refresh });
})();
