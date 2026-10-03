// Arquivo: frontend/assets/js/tela_busca.js
(() => {
  "use strict";
  const form = document.getElementById("scan-form");
  const mode = document.getElementById("scan-mode");
  const sheet = document.getElementById("confirm-sheet");
  const summary = document.getElementById("scan-summary");
  const confirmButton = document.getElementById("confirm-scan");
  let lastTrigger = null;
  let submitting = false;
  const submitError = document.getElementById("scan-submit-error");

  function syncMode() {
    document.querySelectorAll(".conditional-fields").forEach((group) => {
      group.hidden = group.dataset.mode !== mode.value;
    });
  }

  function getConfiguration() {
    const data = new FormData(form);
    const configuration = {};
    for (const key of ["Tld", "Busca", "Excluir"]) configuration[key] = String(data.get(key) || "").trim();
    configuration.Tld = configuration.Tld.toLowerCase();
    if (configuration.Busca === "Combinacoes") {
      configuration.Caracteres = Number(data.get("Caracteres"));
      configuration.Alfabeto = String(data.get("Alfabeto"));
    } else if (configuration.Busca === "Padrao") configuration.Padrao = String(data.get("Padrao") || "").trim();
    else configuration.Dicionario = String(data.get("Dicionario") || "");
    const rawLimit = String(data.get("Limite") || "").trim();
    configuration.Limite = rawLimit === "" ? Number.NaN : Number(rawLimit);
    return configuration;
  }

  function validate(configuration) {
    if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/.test(configuration.Tld)) return "Digite uma extensão de domínio válida usando letras minúsculas, números ou hífens internos.";
    if (!Number.isSafeInteger(configuration.Limite) || configuration.Limite < 0 || configuration.Limite > 2000000000) return "Informe um limite inteiro entre 0 e 2.000.000.000. Use 0 somente se quiser percorrer todas as combinações.";
    if (configuration.Busca === "Combinacoes") {
      if (!Number.isInteger(configuration.Caracteres) || configuration.Caracteres < 1 || configuration.Caracteres > 12) return "O tamanho deve estar entre 1 e 12 caracteres.";
      const alphabets = { Letras: "abcdefghijklmnopqrstuvwxyz", LetrasNumeros: "abcdefghijklmnopqrstuvwxyz0123456789", Consoantes: "bcdfghjklmnpqrstvwxyz", Vogais: "aeiou", Numeros: "0123456789" };
      const available = [...(alphabets[configuration.Alfabeto] || "")].filter((character) => !configuration.Excluir.toLowerCase().includes(character)).length;
      if (available === 0) return "Os caracteres excluídos removem todas as opções do alfabeto selecionado.";
    }
    if (configuration.Busca === "Padrao") {
      if (!configuration.Padrao || configuration.Padrao.length > 63 || !/^[0XCVAa-z1-9-]+$/.test(configuration.Padrao) || configuration.Padrao.startsWith("-") || configuration.Padrao.endsWith("-")) return "Use somente 0, X, C, V, A, letras minúsculas, números de 1 a 9 e hífen interno.";
      const excluded = configuration.Excluir.toLowerCase().replace(/[^a-z0-9]/g, "");
      if ([...configuration.Padrao].some((character) => "abcdefghijklmnopqrstuvwxyz123456789".includes(character) && excluded.includes(character))) return "O padrão contém um caractere fixo que também foi excluído.";
      const wildcards = { X: "abcdefghijklmnopqrstuvwxyz", C: "bcdfghjklmnpqrstvwxyz", V: "aeiou", A: "abcdefghijklmnopqrstuvwxyz0123456789", 0: "0123456789" };
      if ([...configuration.Padrao].some((character) => wildcards[character] && ![...wildcards[character]].some((option) => !configuration.Excluir.toLowerCase().includes(option)))) return "Os caracteres excluídos removem todas as opções de um curinga do padrão.";
    }
    if (configuration.Busca === "Dicionario" && !configuration.Dicionario) return "Selecione um arquivo de dicionário existente.";
    return "";
  }

  function describe(configuration) {
    const suffix = `.${configuration.Tld}`;
    const search = configuration.Busca === "Combinacoes"
      ? `${configuration.Caracteres} caracteres · ${configuration.Alfabeto}`
      : configuration.Busca === "Padrao" ? `Padrão ${configuration.Padrao}` : configuration.Dicionario;
    const excluded = configuration.Excluir ? configuration.Excluir.toLowerCase().replace(/[^a-z0-9]/g, "").split("").filter((value, index, all) => all.indexOf(value) === index).join(" ") : "Nenhum";
    const limit = configuration.Limite === 0 ? "Todas as combinações" : `${configuration.Limite.toLocaleString("pt-BR")} nomes no máximo`;
    return `${search} · ${suffix} · Excluir: ${excluded} · Limite: ${limit}`;
  }

  mode.addEventListener("change", syncMode);
  syncMode();

  document.getElementById("open-confirmation").addEventListener("click", () => {
    const configuration = getConfiguration();
    const error = validate(configuration);
    if (error) { window.DomainUI.showToast(error); return; }
    if (document.getElementById("scan-state").classList.contains("is-active")) {
      window.DomainUI.showToast("Já existe uma varredura em andamento.");
      return;
    }
    lastTrigger = document.activeElement;
    summary.textContent = `Configuração: ${describe(configuration)}. Os arquivos atuais de resultados e log serão apagados antes do início.`; submitError.hidden = true; submitError.textContent = "";
    sheet.showModal();
  });

  document.getElementById("cancel-scan").addEventListener("click", () => { if (!submitting) sheet.close(); });
  sheet.addEventListener("cancel", (event) => { if (submitting) event.preventDefault(); });
  sheet.addEventListener("close", () => { submitError.hidden = true; lastTrigger?.focus(); });
  confirmButton.addEventListener("click", async () => {
    const configuration = getConfiguration();
    const error = validate(configuration);
    if (error) { sheet.close(); window.DomainUI.showToast(error); return; }
    if (submitting) return;
    submitting = true;
    confirmButton.disabled = true;
    document.getElementById("cancel-scan").disabled = true;
    confirmButton.textContent = "Iniciando…";
    submitError.hidden = true;
    submitError.textContent = "";
    sheet.dataset.submitting = "true";
    try {
      const result = await window.DomainApi.startScan(configuration);
      sheet.close();
      window.DomainUI.showGlobalState("");
      window.DomainUI.showToast("Varredura iniciada. Os resultados serão atualizados conforme o scanner confirmar cada lote.");
      window.dispatchEvent(new CustomEvent("domain:scan-started"));
      window.DomainUI.navigate("resultados");
    } catch (error) {
      submitError.textContent = error.message || "Não foi possível iniciar a varredura.";
      submitError.hidden = false;
      submitError.focus();
    } finally {
      submitting = false;
      delete sheet.dataset.submitting;
      confirmButton.disabled = false;
      document.getElementById("cancel-scan").disabled = false;
      confirmButton.textContent = "Confirmar e iniciar";
    }
  });

  window.dispatchEvent(new CustomEvent("domain:screen-ready", { detail: { screen: "busca" } }));
})();
