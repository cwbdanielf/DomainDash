# requisitos_frontend.md

## 1. Escopo e premissas

Criar uma interface local para configurar e iniciar o scanner PowerShell existente, consultar o processo, ler a lista atual de domínios e consultar o log. A interface conserva as conexões RDAP, DNS e WHOIS que o scanner já usa.

- RF-01: utilizar apenas parâmetros e dados reais suportados pelo scanner e seus arquivos.
- RF-02: antes de uma busca real que substitui a lista e o log atuais, exigir confirmação explícita em folha.
- RF-03: não simular resultados, histórico ou progresso numérico; mostrar até 500 linhas reais, contagem total e aviso de truncamento.
- RF-04: mostrar estado real do processo, resultados, log e arquivos de dicionário existentes.
- RF-05: limitar o servidor a IPv4 loopback e limitar a interface ao computador local.
- Premissas completas: `docs/frontend/diagnostico_frontend.md`.

## 2. Mapa backend x telas

| Tela/área | Rotas locais | Dados exibidos | Ações permitidas |
|---|---|---|---|
| Busca | `GET /api/status`, `GET /api/dictionaries`, `GET /api/results`, `GET /api/log`, `POST /api/scan` | Estado real do processo, configuração, quantidade atual de resultados, log e nomes reais de dicionários | Configurar, confirmar, iniciar, navegar |
| Resultados | `GET /api/results`, `GET /api/status` | Domínios do arquivo atual, no máximo 500 linhas por resposta, quantidade total, estado do processo | Atualizar, copiar a lista visível, navegar |
| Log | `GET /api/log`, `GET /api/status` | Conteúdo real do log atual, estado do processo | Atualizar, navegar |
| Folha de confirmação | `POST /api/scan` | Efeito de substituição dos arquivos e configuração completa | Confirmar início ou voltar |

O novo host local define essas rotas. Campos enviados ao scanner são seus argumentos existentes: `Tld`, `Busca`, `Caracteres`, `Alfabeto`, `Padrao`, `Dicionario`, `Excluir`, `Limite`.

## 3. Arquitetura do front-end e estrutura de arquivos

Página única em HTML, CSS e JavaScript sem build. `frontend/` contém a página, estilos, fonte, sprite de ícones e scripts. Arquivos de tela: `tela_busca.js`, `tela_resultados.js`, `tela_log.js`. O arquivo `DomainDash.ps1`, na raiz, é a única adição ao backend existente, permitida para a ponte.

O host oferece status, resultados atuais, log, descoberta de dicionários e início de busca. A interface não lê caminhos arbitrários, não habilita CORS e não aceita comando do navegador.

## 4. Sistema de design

### Padrão de design obrigatório

Tema claro, destaque #007AFF, material Liquid Glass em navegação e controles, conteúdo sólido, tela de 430 x 932 px em moldura de aparelho no desktop e tela cheia abaixo de 500 px. Navegação flutuante em cápsula. Inter e ícones SVG locais. Raios concêntricos e espaçamento em múltiplos de 4 px.

### Instanciação para DomainDash

- Fundo externo em malha de cores e papel de parede abstrato gerados localmente, sem imagens remotas.
- Paleta: #FFFFFF, #F2F2F7, textos pretos/cinzentos, azul #007AFF, verde #34C759, laranja #FF9500 e vermelho #FF3B30. Cores funcionais escurecidas quando necessário para legibilidade.
- No máximo duas camadas de blur simultâneas; evitar blur em superfícies extensas com rolagem.
- Regular para navegação; clear somente em fundo rico; tinted para ação primária. Fallbacks opacos para navegador incompatível ou transparência reduzida.
- Tipografia Inter local na escala da especificação; hierarquia, espaçamento e título grande adequados à tela de telefone.
- Referências consultadas: Apple HIG Materials, https://developer.apple.com/design/human-interface-guidelines/materials, e overview Liquid Glass, https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass. A orientação confirma vidro em navegação e controles, separado da camada de conteúdo.

## 5. Componentes e variantes

Moldura, relógio e ícones locais de status, recorte superior e indicador inferior; título grande; abas Busca/Resultados/Log; botão primário e botões secundários/circulares; campos e seletores; cartões sólidos; lista de resultados; painel textual de log; estados carregando/vazio/erro; folha modal de confirmação; toast e foco de teclado visível. Alvos de interação com pelo menos 44 x 44 px.

## 6. Telas

### Busca
Objetivo: configurar uma busca existente. Exibe estado do scanner, aviso de substituição, tipo de pesquisa, configuração condicional e limite. Estados: pronta, enviando, ativa, entrada inválida ou servidor indisponível. Uma folha lista TLD, modalidade, configuração, caracteres excluídos e limite. O diálogo bloqueia fechamento durante envio.

### Resultados
Objetivo: mostrar o arquivo atual. Exibe total real, até 500 linhas, estado vazio/ativo e ação para copiar itens mostrados. Não cria histórico nem resultados.

### Log
Objetivo: consultar o log textual atual. Exibe estado do processo, conteúdo real, atualização e estados vazio/erro.

### Folha de confirmação
Objetivo: impedir substituição acidental. Informa que o scanner apaga lista e log anteriores, resume todos os parâmetros relevantes e oferece confirmar ou voltar.

## 7. Estados universais

- Carregando: texto de status acessível, sem percentual inventado.
- Vazio: explicar ausência de resultados ou arquivos, sem dados de exemplo.
- Erro de rede: manter conteúdo anterior e permitir nova consulta.
- Erro de dados: informar resposta malformada.
- Sem permissão: recusar POST sem origem e token da sessão local.
- Backend indisponível: informar que o servidor precisa ser iniciado.
- Busca ativa: derivada do processo real e dados parciais do arquivo.

## 8. Movimento e interação

Transições curtas com curva `linear()`, View Transitions quando disponível e fallback acessível. Destaque de ponteiro e microinterações. Reduzir movimento desativa animação e deslocamento. Polling só ocorre quando a página está visível e atualiza somente a área ativa durante varredura.

## 9. Acessibilidade e degradação

HTML semântico, labels, ordem lógica de teclado, foco visível, regiões de estado acessíveis e alvos de 44 px. Contraste mínimo 4,5:1 para texto normal e 3:1 para texto grande/ícones. Preferências de movimento, contraste e transparência são respeitadas. Sem `backdrop-filter`, os controles ficam opacos.

## 10. Desempenho

No máximo duas camadas de blur, sem blur em conteúdo extenso, atualização limitada ao necessário, fonte e ícones locais, sem CDN, dependências de runtime ou imagens remotas. Resposta de resultados limitada a 500 entradas para controlar memória; contagem total continua real.

## 11. Critérios de aceite testáveis

- CA-01: Chrome abre sem erro/aviso da aplicação.
- CA-02: nenhuma requisição do front-end para host externo.
- CA-03: as três áreas em 1920x1080 e 2560x1440 sem cortes nem rolagem horizontal.
- CA-04: vidro transparente e legível em Chromium.
- CA-05: `prefers-reduced-transparency` deixa as camadas opacas e legíveis.
- CA-06: `prefers-reduced-motion` remove animações/deslocamentos.
- CA-07: contraste mínimo conforme seção 9.
- CA-08: navegação por teclado, com foco visível.
- CA-09: status, resultados, log, formulários e confirmação funcionam com dados reais; provocar uma busca real é opcional se arriscar os arquivos atuais.
- CA-10: conferir movimento visual; medição de 60 fps depende de ferramenta dedicada.
- CA-11: testes preexistentes continuam passando; nenhum havia sido localizado no projeto.
- CA-12: arquivos novos limitados aos definidos na tabela de saída e ao host aditivo permitido; originais preservados.

## 12. Fora do escopo

Banco, histórico permanente, login, compra/reserva de domínio, mudanças no scanner original, cancelamento forçado, integração com registrador, API pública, acesso pela LAN, tema escuro ou resultados simulados.

## 13. Riscos e pendências

- Busca real substitui resultados e log; confirmação é obrigatória.
- Scanner não oferece progresso estruturado nem cancelamento cooperativo.
- RDAP/DNS/WHOIS dependem da conectividade que o scanner já usa.
- Requer PowerShell 7.6+.
- Host tenta bind exclusivo em endereço loopback, mantendo a mesma porta reservada enquanto opera; sem porta livre após tentativas, não inicia.
- Projeto original sem testes automatizados.
- Medição objetiva de 60 fps e emulação de preferência de transparência dependem das ferramentas disponíveis.