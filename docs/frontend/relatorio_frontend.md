# relatorio_frontend.md

## Entrega

O DomainDash agora tem um painel local para configurar a busca, ver o estado do scanner, conferir os domínios da execução atual e consultar o log. A apresentação usa moldura de telefone no desktop, fundo colorido suave, navegação flutuante e tema claro. Em telas estreitas, a moldura desaparece. Conforme confirmado pelo mantenedor, o aplicativo foi testado e validado.

A interface consulta as saídas reais do script e pode iniciar o scanner original após confirmação. A confirmação é necessária porque o scanner apaga os arquivos atuais de resultado e log. A interface não oferece botão de cancelamento, pois o script não tem parada cooperativa segura.

A lista de resultados mostra até 500 nomes reais por vez, informa a quantidade total e permite copiar a lista visível. A tela de dicionário lista somente arquivos `.txt` realmente existentes.

## Arquivos entregues

- `docs/frontend/diagnostico_frontend.md`
- `docs/frontend/requisitos_frontend.md`
- `frontend/index.html`
- `frontend/assets/css/tokens.css`
- `frontend/assets/css/glass.css`
- `frontend/assets/css/componentes.css`
- `frontend/assets/css/telas.css`
- `frontend/assets/fonts/inter_variavel.woff2`
- `frontend/assets/icons/icones.svg`
- `frontend/assets/js/api.js`
- `frontend/assets/js/ui.js`
- `frontend/assets/js/app.js`
- `frontend/assets/js/tela_busca.js`
- `frontend/assets/js/tela_resultados.js`
- `frontend/assets/js/tela_log.js`
- `DomainDash.ps1`, host local aditivo permitido pela especificação.
- Este arquivo, `docs/frontend/relatorio_frontend.md`.

## Como iniciar e abrir

Requisito: PowerShell 7.6 ou superior. Inicie o comando abaixo na pasta do projeto. O host tenta reservar uma porta TCP alta disponível, com bind exclusivo em `127.0.0.1`, e abre o Google Chrome após obter a reserva. O terminal apresenta a URL exata da sessão. Se o Chrome não estiver instalado, abra essa URL manualmente. Feche a janela do servidor para parar o host local.

```powershell
pwsh -NoProfile -File .\DomainDash.ps1
```

A URL tem o formato `http://127.0.0.1:<porta>/`, com porta livre escolhida a cada início. Se 96 tentativas falharem, o host encerra sem servir a interface.

## Premissas e mudanças de backend

- O scanner existente continua sendo o motor de busca; sua lógica foi preservada.
- A interface só é acessível neste computador, por IPv4 `127.0.0.1`. Endereços remotos e cabeçalhos Host inválidos são rejeitados; não há CORS.
- Uma execução real substitui os arquivos anteriores. A folha de confirmação apresenta TLD, modalidade, padrão ou alfabeto, caracteres excluídos e limite.
- Progresso e dados são apresentados apenas quando observáveis no processo, log ou arquivos reais.
- Não há botão de parada: interromper o processo à força pode impedir a limpeza da trava do scanner.
- O host local `DomainDash.ps1` serve rotas para estado, lista de resultados, log, dicionários e inicialização supervisionada do scanner original. Ele reserva o socket TCP IPv4 exclusivo antes de servir HTTP e aceita apenas campos em lista permitida. A saída do console do scanner não é acumulada em buffers do servidor.
- A lógica do scanner existente foi preservada; sua identificação de autor foi atualizada para a distribuição. Resultados e logs são dados locais de execução, não parte do código-fonte.
- Não foram encontrados testes automatizados no projeto. As cópias de segurança permanecem fora da árvore distribuída.

## Verificação dos critérios de aceite

| Critério | Resultado | Evidência ou pendência |
|---|---|---|
| CA-01: Chrome sem erros ou avisos | Aprovado | Na última carga, não houve exceções JavaScript, avisos ou respostas HTTP de erro. Interface real aberta no Chrome instalado. |
| CA-02: zero hosts externos | Aprovado | Monitoramento do navegador mostrou zero pedidos a outros hosts. Uma varredura efetiva conserva os pedidos externos do scanner original. |
| CA-03: capturas desktop sem corte | Aprovado | Busca, Resultados e Log foram conferidos em 1920x1080 e 2560x1440. Moldura 430x932 centralizada; sem rolagem horizontal. |
| CA-04: vidro legível | Aprovado visualmente em Chromium | Navegação com transparência e desfoque sobre fundo colorido. Conteúdo permanece em superfície sólida. |
| CA-05: transparência reduzida | Aprovado por regra CSS | Fallback CSS remove desfoque e usa camadas opacas, inclusive folha e fundo escurecido. O navegador de validação não emulou nativamente essa preferência. |
| CA-06: movimento reduzido | Aprovado por emulação no Chrome | Duração de animação computada em 0,00001 s; animação de tela e deslocamentos desligados. |
| CA-07: contraste mínimo | Aprovado por cálculo e revisão | Cores de textos secundários/terciários e sucesso foram escurecidas; botão principal usa azul escuro com texto branco. |
| CA-08: teclado e foco | Aprovado por inspeção | Formulário semântico, rótulos, contorno de foco visível de 3 px, diálogo nativo e navegação por botões. Foco retorna ao acionador após fechar a folha. |
| CA-09: funções e estados | Validado pelo mantenedor | Estado, resultados, log, navegação, validações e confirmação foram exercitados; POST sem origem/token foi recusado (403). O mantenedor confirma que o aplicativo foi testado e validado. A preparação pública não repetiu uma busca real, que substituiria os arquivos locais de resultados e log. |
| CA-10: 60 quadros/s | Parcial | Navegação/transições revisadas visualmente; sem medição quantitativa de quadros. |
| CA-11: testes existentes | Não aplicável | Não foram encontrados testes automatizados. Os parsers PowerShell e JavaScript foram validados durante o desenvolvimento. |
| CA-12: limite de arquivos alterados | Aprovado | Nenhum dicionário de exemplo ou captura foi incluído no projeto. |

## Licenças

- Inter variável: distribuição do repositório oficial `rsms/inter`, SIL Open Font License 1.1. Referências: https://github.com/rsms/inter e https://github.com/rsms/inter/blob/master/misc/dist/help.txt. Não vendida isoladamente.
- Ícones: desenhos SVG locais originais sob CC0 1.0 Universal.
- Liquid Glass serve como referência de material; não foram copiadas imagens, logotipos ou fontes proprietárias.

## Pendências

1. O ciclo de busca real não foi repetido durante a preparação pública para evitar recriar arquivos locais; uma busca real depende de conectividade externa e substitui os arquivos atuais de resultados e log.
2. O scanner não expõe eventos estruturados de progresso ou cancelamento. A interface não inventa porcentagem.
3. O projeto não tem testes automatizados. Medição quantitativa de 60 fps e emulação nativa de transparência reduzida dependem de ferramentas dedicadas.
4. Servir a página local não exige internet; uma busca real depende da conectividade externa que o scanner já utiliza.
