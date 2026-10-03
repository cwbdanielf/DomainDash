// Arquivo: frontend/assets/js/app.js
(() => {
  "use strict";
  let polling = false;
  let lastStatus = null;

  function setScanState(status) {
    const pill = document.getElementById("scan-state");
    const label = pill.lastElementChild;
    const exitCode = status.lastRun?.exitCode;
    const failed = !status.scanning && (Boolean(status.message) || (exitCode !== undefined && exitCode !== null && exitCode !== 0));
    let state;

    if (status.available === false) state = "unavailable";
    else if (status.scanning) state = "active";
    else if (failed) state = "error";
    else if (exitCode === 0) state = "complete";
    else state = "ready";

    pill.classList.toggle("is-ready", state === "ready");
    pill.classList.toggle("is-active", state === "active");
    pill.classList.toggle("is-complete", state === "complete");
    pill.classList.toggle("is-error", state === "error" || state === "unavailable");
    pill.classList.toggle("is-unavailable", state === "unavailable");
    const labelText = {
      ready: "Pronto",
      active: "Em andamento",
      complete: "Concluída",
      error: "Falha",
      unavailable: "Indisponível",
    }[state];
    if (label.textContent !== labelText) label.textContent = labelText;

    document.getElementById("open-confirmation").disabled = state === "active" || state === "unavailable";
    if (state === "unavailable") window.DomainUI.showGlobalState(status.message || "Servidor local indisponível. Inicie o aplicativo pelo comando do relatório.");
    else if (state === "error") window.DomainUI.showGlobalState(status.message || "O scanner terminou com erro. Consulte o log para ver a mensagem registrada.");
    else window.DomainUI.showGlobalState("");
  }

  async function refreshStatus() {
    try {
      const status = await window.DomainApi.status();
      setScanState(status);
      const finished = lastStatus?.scanning && !status.scanning;
      const activeScreen = document.querySelector("[data-screen]:not([hidden])")?.dataset.screen;
      if (finished) {
        window.dispatchEvent(new CustomEvent("domain:refresh-results"));
        window.dispatchEvent(new CustomEvent("domain:refresh-log"));
      } else if (status.scanning && activeScreen === "resultados") window.dispatchEvent(new CustomEvent("domain:refresh-results"));
      else if (status.scanning && activeScreen === "log") window.dispatchEvent(new CustomEvent("domain:refresh-log"));
      lastStatus = status;
      document.querySelectorAll("[data-refresh]").forEach((button) => { button.disabled = status.available === false; });
      document.querySelector('[data-refresh="results"]').disabled = status.available === false;
      document.querySelector('[data-refresh="log"]').disabled = status.available === false;
    } catch (error) {
      setScanState({ available: false, message: error.message });
    }
  }

  async function loadDictionaries(selectedName = "") {
    const select = document.getElementById("dictionary-select");
    const hint = document.getElementById("dictionary-hint");
    try {
      const response = await window.DomainApi.dictionaries();
      const dictionaries = Array.isArray(response.dictionaries) ? response.dictionaries : [];
      select.replaceChildren();
      if (dictionaries.length === 0) {
        const option = new Option("Nenhum arquivo encontrado", "");
        option.disabled = true;
        option.selected = true;
        select.add(option);
        hint.textContent = "A pasta de dicionários não contém arquivos .txt. Adicione um arquivo real para usar esta modalidade.";
        return;
      }
      for (const dictionary of dictionaries) select.add(new Option(dictionary, dictionary));
      if (selectedName && dictionaries.includes(selectedName)) select.value = selectedName;
      else if (dictionaries.length > 0 && !select.value) select.selectedIndex = 0;
      hint.textContent = `${dictionaries.length.toLocaleString("pt-BR")} ${dictionaries.length === 1 ? "arquivo disponível" : "arquivos disponíveis"} na pasta de dicionários.`;
    } catch (error) {
      select.replaceChildren(new Option("Lista indisponível", ""));
      hint.textContent = error.message || "Não foi possível consultar os dicionários.";
    }
  }

  function setupDictionaryUpload() {
    const input = document.getElementById("dictionary-file");
    const picker = document.getElementById("dictionary-pick");
    const drop = document.getElementById("dictionary-drop");
    const status = document.getElementById("dictionary-upload-status");
    let uploading = false;

    const upload = async (file) => {
      if (uploading) return;
      if (!file || !/\.txt$/i.test(file.name)) {
        status.textContent = "Escolha um arquivo com extensão .txt.";
        return;
      }
      if (file.size === 0 || file.size > 5 * 1024 * 1024) {
        status.textContent = "O arquivo deve ter conteúdo e não pode exceder 5 MiB.";
        return;
      }
      uploading = true;
      picker.disabled = true;
      drop.classList.add("is-uploading");
      status.textContent = "Lendo arquivo…";
      try {
        const buffer = await file.arrayBuffer();
        const bytes = new Uint8Array(buffer);
        let binary = "";
        for (let offset = 0; offset < bytes.length; offset += 0x8000) {
          binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
        }
        const contentBase64 = btoa(binary);
        await window.DomainApi.uploadDictionary(file.name, contentBase64);
        await loadDictionaries(file.name);
        status.textContent = `“${file.name}” foi adicionado e selecionado.`;
      } catch (error) {
        status.textContent = error.message || "Não foi possível adicionar o dicionário.";
      } finally {
        uploading = false;
        picker.disabled = false;
        drop.classList.remove("is-uploading");
        input.value = "";
      }
    };

    picker.addEventListener("click", () => input.click());
    input.addEventListener("change", () => upload(input.files[0]));
    for (const eventName of ["dragenter", "dragover"]) {
      drop.addEventListener(eventName, (event) => {
        event.preventDefault();
        if (!uploading) drop.classList.add("is-dragover");
      });
    }
    for (const eventName of ["dragleave", "dragend"]) {
      drop.addEventListener(eventName, (event) => {
        event.preventDefault();
        drop.classList.remove("is-dragover");
      });
    }
    drop.addEventListener("drop", (event) => {
      event.preventDefault();
      drop.classList.remove("is-dragover");
      if (event.dataTransfer?.files.length !== 1) {
        status.textContent = "Solte somente um arquivo .txt por vez.";
        return;
      }
      upload(event.dataTransfer.files[0]);
    });
  }

  function startPolling() {
    if (polling) return;
    polling = true;
    const tick = async () => {
      if (document.visibilityState === "visible") await refreshStatus();
      if (polling) window.pollTimer = setTimeout(tick, 1600);
    };
    tick();
  }

  window.addEventListener("domain:scan-started", () => { refreshStatus(); });
  document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") refreshStatus(); });
  document.querySelectorAll("[data-refresh]").forEach((button) => button.addEventListener("click", refreshStatus));
  loadDictionaries();
  setupDictionaryUpload();
  startPolling();
})();
