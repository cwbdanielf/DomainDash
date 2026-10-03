// Arquivo: frontend/assets/js/api.js
(() => {
  "use strict";

  const token = document.querySelector('meta[name="app-token"]')?.content || "";

  async function request(path, options = {}) {
    const headers = new Headers(options.headers || {});
    if (options.body !== undefined) {
      headers.set("Content-Type", "application/json");
      headers.set("X-App-Token", token);
    }
    const response = await fetch(path, {
      ...options,
      headers,
      cache: "no-store",
      credentials: "same-origin",
      redirect: "error",
    });
    const payload = await response.json().catch(() => null);
    if (!response.ok) {
      const message = payload?.error || `A solicitação falhou (${response.status}).`;
      const error = new Error(message);
      error.status = response.status;
      throw error;
    }
    if (!payload || typeof payload !== "object") {
      throw new Error("O serviço local retornou uma resposta inválida.");
    }
    return payload;
  }

  window.DomainApi = Object.freeze({
    status: () => request("/api/status"),
    results: () => request("/api/results"),
    log: () => request("/api/log"),
    dictionaries: () => request("/api/dictionaries"),
    startScan: (configuration) => request("/api/scan", {
      method: "POST",
      body: JSON.stringify(configuration),
    }),
  });
})();
