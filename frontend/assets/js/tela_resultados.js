// Arquivo: frontend/assets/js/tela_resultados.js
(() => {
  "use strict";
  const list = document.getElementById("domain-list");
  const state = document.getElementById("results-state");
  const count = document.getElementById("results-count");
  const copy = document.getElementById("copy-results");
  let domains = [];

  async function refresh() {
    state.textContent = "Consultando arquivo de resultados…";
    state.hidden = false;
    try {
      const data = await window.DomainApi.results();
      if (!Array.isArray(data.domains) || data.domains.some((item) => typeof item !== "string") || !Number.isSafeInteger(data.total) || data.total < data.domains.length) throw new Error("O arquivo de resultados tem um formato inesperado.");
      domains = data.domains;
      const total = Number.isSafeInteger(data.total) ? data.total : domains.length;
      list.replaceChildren();
      const fragment = document.createDocumentFragment();
      for (const domain of domains) {
        const item = document.createElement("li");
        const name = document.createElement("span");
        name.className = "domain-name";
        name.textContent = domain;
        const tag = document.createElement("span");
        tag.className = "domain-tag";
        tag.textContent = "Encontrado";
        item.append(name, tag);
        fragment.append(item);
      }
      list.append(fragment);
      count.dataset.total = String(total);
      count.textContent = `${total.toLocaleString("pt-BR")} ${total === 1 ? "nome encontrado" : "nomes encontrados"}${data.truncated ? " · exibindo os primeiros 500" : ""}`;
      state.textContent = total ? "" : (data.scanning ? "A varredura ainda não encontrou nomes neste lote." : "O arquivo atual não contém domínios encontrados.");
      copy.setAttribute("aria-label", data.truncated ? `Copiar os primeiros ${domains.length} de ${total} domínios` : "Copiar lista completa");
      copy.disabled = domains.length === 0;
      state.hidden = total > 0;
    } catch (error) {
      state.hidden = false;
      state.textContent = error.message || "Não foi possível ler o arquivo de resultados.";
      count.textContent = "Resultados indisponíveis";
      copy.disabled = true;
    }
  }

  copy.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(domains.join("\n"));
      const more = domains.length < Number(document.getElementById("results-count").dataset.total || domains.length);
      window.DomainUI.showToast(`${domains.length.toLocaleString("pt-BR")} domínios copiados${more ? "; a lista exibida contém somente os primeiros 500." : "."}`);
    } catch {
      window.DomainUI.showToast("O navegador não permitiu copiar a lista.");
    }
  });
  document.querySelector('[data-refresh="results"]').addEventListener("click", refresh);
  window.addEventListener("domain:refresh-results", refresh);
  window.addEventListener("domain:scan-started", refresh);
  window.addEventListener("domain:screen-ready", (event) => { if (event.detail.screen === "resultados") refresh(); });
  window.DomainResultsScreen = Object.freeze({ refresh });
})();
