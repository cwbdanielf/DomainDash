# diagnostico_frontend.md

## Diagnóstico da Fase 0

- Aplicativo: DomainDash.
- Aplicação: scanner `cacador-dominios.ps1`, executado com PowerShell 7.6 ou superior.
- Comando de execução existente: `pwsh -File .\cacador-dominios.ps1`; o script pergunta parâmetros quando executado interativamente.
- Aplicativo web: iniciar com `pwsh -NoProfile -File .\DomainDash.ps1`; o host local escuta somente em `127.0.0.1` e comunica-se com o scanner por rotas locais.
- Interface atual: menus e progresso no terminal. Parâmetros incluem TLD, modo de busca, tamanho/alfabeto, padrão, dicionário, caracteres excluídos, limite, concorrência e tamanho de lote.
- Dados: não há banco de dados nem modelos persistentes. Saídas são `dominios-disponiveis.txt` (um domínio por linha) e `cacador-dominios-log.txt` (mensagens com data e nível), na pasta definida pela execução.
- Autenticação, perfis e CORS: não há. A interface será limitada ao próprio computador e não terá CORS.
- Busca: combinações, padrão e dicionário. Não havia subpasta de dicionários; a interface listará somente arquivos `.txt` reais existentes.
- Dependências do scanner: RDAP publicado pela IANA, DNS e, quando aplicável, WHOIS. A execução de varredura precisa de conectividade externa, embora a interface e os arquivos estáticos funcionem sem CDN ou dependência de runtime.
- Front-end: página, estilos, ícones e scripts estáticos em `frontend/`; não há etapa de build. Não foram encontrados testes automatizados.
- A preparação para distribuição mantém cópias de segurança fora da árvore do projeto; elas não fazem parte dos arquivos distribuídos.
- Arquivos gerados pelo scanner: `dominios-disponiveis.txt` e `cacador-dominios-log.txt`; não são incluídos na distribuição.

## Pasta-base escolhida

`frontend/` contém a página e recursos estáticos. `docs/frontend/` contém diagnóstico, requisitos e relatório. O host local fica em `DomainDash.ps1`, na raiz, como exceção de backend permitida pela especificação. A lógica de busca do scanner foi preservada; sua identificação de autor foi atualizada para a distribuição pública.

## Premissas e decisões

1. A interface é uma única tela de operação com três áreas navegáveis: painel da busca, resultados atuais e log da execução. Não há recursos de negócio separados que justifiquem múltiplas telas.
2. O painel usa os mesmos argumentos aceitos pelo script original. A interface não acrescenta fonte de dados, endpoint do registro, filtros de domínio ou resultados inventados.
3. Uma varredura real apaga os arquivos de resultados e log anteriores na pasta selecionada. O botão principal apresenta uma folha de confirmação explícita antes de disparar o processo.
4. O progresso estruturado não existe no scanner. A interface mostra o estado real do processo e a quantidade total de linhas no arquivo de resultados, sem estimar percentual ou velocidade. A API fornece e a lista apresenta até 500 linhas por consulta para limitar memória; a contagem total e a existência de resultados truncados são explícitas.
5. Os resultados são apresentados como arquivo atual, não como histórico. O log existente é a única fonte histórica disponível e pode ser substituído no início da varredura.
6. O script não tem cancelamento cooperativo. A interface não oferece botão de parada nem encerra à força uma varredura, para não deixar trava ou arquivos em estado inconsistente.
7. O modo simulação não será exposto: apesar de não gravar a lista de resultados, o scanner atual escreve no log também durante a simulação.
8. Arquivos inexistentes, inclusive dicionários, não serão preenchidos com exemplos. Estados vazios explicam como o usuário pode usar conteúdo real.
9. O host local reserva uma porta IPv4 em `127.0.0.1` com bind exclusivo e mantém o socket reservado enquanto serve HTTP, evitando disputa de porta entre sondagem e inicialização.
10. O endereço publicado é exclusivamente `http://127.0.0.1:<porta>/`. Requisições de outros IPs, cabeçalhos Host diferentes, caminhos não permitidos e POST sem token de sessão/origem exatos são rejeitados. Não há acesso pela rede local, CORS ou leitura arbitrária de arquivos.
11. A ponte chama o script por processo separado, com parâmetros validados e lista permitida, preservando o uso independente do CLI. Apenas uma execução por servidor é permitida.
12. A operação conserva a localização atual dos arquivos, na raiz do projeto. A própria tela informa que executar uma busca real substitui os arquivos atuais.
13. O material Liquid Glass é aplicado somente aos controles e à navegação. Conteúdo, formulários e listas permanecem em superfícies sólidas.
14. O viewport de 430 x 932 é preservado em janela desktop, com moldura de aparelho; abaixo de 500 px, a moldura some e a aplicação ocupa a tela.
15. A cor de destaque é #007AFF e o idioma é português do Brasil. Não há tema escuro.
16. Uma fonte Inter variável obtida do repositório oficial e ícones SVG de traço desenhados localmente compõem os recursos locais. As licenças e fontes estão no relatório.
17. A rota HTTP local é uma adição nova, não uma API que já existia. Seu contrato é limitado a iniciar busca e ler status, arquivos de resultado/log e nomes de dicionários.

## Mudanças de backend previstas

O host `DomainDash.ps1` é um servidor HTTP sem dependências de runtime, com socket IPv4 loopback exclusivo e previamente reservado, seleção de porta com tentativas limitadas, arquivos estáticos permitidos, token/origem validados, endpoints locais de leitura e inicialização supervisionada do scanner. A lógica do script principal, banco de dados, ambiente e testes permanece inalterada. A ponte não aceita caminho de arquivo ou comando arbitrário do navegador. A identificação do autor no scanner foi atualizada para a distribuição; a lógica de busca permanece a mesma.