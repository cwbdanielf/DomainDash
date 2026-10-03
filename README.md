# DomainDash

O DomainDash é uma ferramenta local para gerar candidatos a nomes de domínio e verificar a disponibilidade informada pelos serviços de registro. Inclui um scanner em PowerShell e uma interface web local.

> A indicação de disponibilidade é apenas informativa e pode mudar. Confirme sempre diretamente com um registrador antes de tentar registrar um domínio.

## Requisitos

- PowerShell 7.6 ou superior.
- Conexão à internet para consultas do scanner. As consultas usam RDAP e, conforme o TLD, DNS e WHOIS.
- Para abrir a interface, um navegador instalado. O host tenta abrir o Google Chrome; se não estiver disponível, abra manualmente o endereço exibido no terminal.

## Iniciar o DomainDash

No PowerShell, a partir da pasta do projeto:

```powershell
pwsh -NoProfile -File .\DomainDash.ps1
```

O host escolhe uma porta local e escuta somente em `127.0.0.1`. Feche a janela do terminal para encerrar o host. Uma busca real apaga/substitui os arquivos atuais de resultados e log; a interface solicita confirmação antes de iniciar.

## Usar o scanner no terminal

Para iniciar o modo interativo:

```powershell
pwsh -NoProfile -File .\cacador-dominios.ps1
```

O scanner também aceita parâmetros para execuções sem interação. Consulte os parâmetros e exemplos no cabeçalho de `cacador-dominios.ps1`. Uma busca real faz consultas externas e substitui as saídas anteriores.

No modo de dicionário, coloque seus arquivos `.txt` UTF-8 na pasta `dicionarios` ao lado do scanner; uma palavra por linha. Essa pasta pode ser criada pelo scanner quando necessária.

## Arquivos de execução

As execuções geram `dominios-disponiveis.txt` e `cacador-dominios-log.txt` na pasta do projeto. O scanner também pode usar uma trava temporária e remover saídas legadas. Esses arquivos são dados locais e estão excluídos do Git; não são parte do código-fonte.

## Licenças

O projeto é disponibilizado sob a licença MIT (consulte `LICENSE`). A fonte Inter incluída mantém sua licença própria SIL Open Font License 1.1 em `LICENSE-Inter.txt`; ela não é relicenciada pela licença do projeto. Os ícones SVG originais são dedicados ao domínio público sob CC0 1.0.

## Documentação

- [Diagnóstico da interface](docs/frontend/diagnostico_frontend.md)
- [Requisitos da interface](docs/frontend/requisitos_frontend.md)
- [Relatório da interface](docs/frontend/relatorio_frontend.md)
