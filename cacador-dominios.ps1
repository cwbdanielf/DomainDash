#Requires -Version 7.6
<#
.SYNOPSIS
    DomainDash - cwbdanielf
    Procura dominios sem registro (qualquer TLD) e mostra os achados na hora.
.DESCRIPTION
    Principios do script:
    - Pergunta o TLD, o tipo de busca e os parametros (ou recebe tudo por parametro).
    - Tres tipos de busca:
        Combinacoes : todos os nomes de N caracteres de um alfabeto, em ordem aleatoria.
        Padrao      : nomes que seguem um molde com curingas, em ordem aleatoria.
                      0 = numero, X = letra, C = consoante, V = vogal, A = letra ou numero.
                      Minusculas, 1 a 9 e hifen sao caracteres fixos. Exemplo: 0XXX0
        Dicionario  : palavras de um arquivo .txt da pasta "dicionarios".
    - FUNIL ANTI FALSO POSITIVO. Um dominio so e dado como livre se passar por todas as
      camadas abaixo. DNS sozinho nunca basta: ele nao enxerga dominio registrado sem
      servidores de nome, em quarentena, desativado ou reservado (a causa da maioria dos
      falsos positivos).
        1. Regras de sintaxe e nomes reservados do TLD (descarta sem consultar).
        2. RDAP do registro responde "nao existe" (404), duas vezes seguidas, por metodos
           diferentes (HEAD e GET).
        3. Veto do DNS: se o DNS responde que o nome existe, o RDAP e ignorado.
        4. Controle a cada lote: um dominio sabidamente registrado e um inexistente sao
           testados pelo mesmo caminho. Se o controle falhar (servidor instavel ou
           limitando), os achados do lote sao revalidados ou descartados.
      TLD sem RDAP: DNS com dupla confirmacao mais consulta WHOIS do registro. Se nem o
      WHOIS puder ser lido, o achado e marcado como "DNS apenas, nao confirmado".
    - Antes da busca, o script pergunta quais letras ou numeros EXCLUIR (por exemplo os que
      se confundem: g 6 q l e 1). Eles saem de todos os curingas, das combinacoes e dos
      dicionarios (palavra que contenha um caractere excluido e descartada).
    - Cada achado aparece na tela e entra no arquivo no mesmo instante.
    - A cada execucao real, os arquivos da execucao anterior sao apagados.
    - Se o servidor limitar as consultas (HTTP 429), o script reduz o ritmo sozinho.

    FORMATO DO DICIONARIO
    - Arquivo .txt em UTF-8, na pasta "dicionarios" ao lado do script.
    - Uma palavra por linha. Opcional: palavra;descricao (a descricao aparece na tela).
    - Linhas vazias e linhas iniciadas por # sao ignoradas.
    - Acentos e espacos sao removidos. So valem a-z, 0-9 e hifen (nao no inicio nem no fim).
.PARAMETER Tld
    TLD a pesquisar: si, com, com.br, ai... Se omitido, o script pergunta.
.PARAMETER Busca
    Combinacoes, Padrao ou Dicionario. Se omitido, o script pergunta.
.PARAMETER Caracteres
    Combinacoes: quantos caracteres antes do TLD (1 a 12).
.PARAMETER Alfabeto
    Combinacoes: Letras, LetrasNumeros, Consoantes, Vogais ou Numeros.
.PARAMETER Padrao
    Padrao: o molde, por exemplo 0XXX0.
.PARAMETER Dicionario
    Dicionario: nome do arquivo (com ou sem .txt) ou "todos".
.PARAMETER Excluir
    Letras e numeros a excluir da busca, por exemplo "g6ql e1" (espacos e virgulas sao ignorados).
    Se omitido, o script pergunta (Enter = nenhum).
.PARAMETER WhoisHost
    Servidor WHOIS (host ou host:porta) para TLD sem RDAP. Se omitido, e descoberto na IANA.
.PARAMETER Limite
    Maximo de nomes testados. 0 = todos ou ate Ctrl+C.
.PARAMETER Threads
    Consultas simultaneas. 0 = automatico (8 no RDAP, 64 no DNS). Cai sozinho se o servidor limitar.
.PARAMETER Simular
    Testa a logica com 30 nomes, sem apagar nem gravar arquivos.
.PARAMETER SemInteracao
    Nao pergunta nada e nao pausa no fim.
.EXAMPLE
    .\cacador-dominios.ps1
.EXAMPLE
    .\cacador-dominios.ps1 -Tld si -Busca Padrao -Padrao 0XXX0 -Limite 5000 -SemInteracao
#>
[CmdletBinding()]
param(
    [string]$Pasta = '',
    [string]$Tld = '',
    [ValidateSet('Combinacoes', 'Padrao', 'Dicionario')][string]$Busca = 'Combinacoes',
    [ValidateRange(1, 12)][int]$Caracteres = 5,
    [ValidateSet('Letras', 'LetrasNumeros', 'Consoantes', 'Vogais', 'Numeros')][string]$Alfabeto = 'Consoantes',
    [string]$Padrao = '',
    [string]$Dicionario = '',
    [string]$Excluir = '',
    [string]$PastaDicionarios = '',
    [ValidateRange(0, 2000000000)][long]$Limite = 0,
    [ValidateRange(0, 256)][int]$Threads = 0,
    [ValidateRange(0, 5000)][int]$TamanhoLote = 0,
    [string]$WhoisHost = '',
    [string[]]$Servidores = @('1.1.1.1', '8.8.8.8'),
    [string]$BootstrapUrl = 'https://data.iana.org/rdap/dns.json',
    [switch]$Simular,
    [switch]$SemInteracao
)

# ============================================================================
#  BLOCO PADRAO DE UX PARA SCRIPTS POWERSHELL  -  cwbdanielf
#  Versao 1.0
#
#  Copie este arquivo inteiro para dentro do script, logo apos o param().
#  Nao e modulo: cada script carrega sua propria copia e continua sendo um
#  arquivo unico que roda em qualquer pasta sem dependencias.
# ============================================================================

# ═══════════════════════════════════════════════════════════════════════════
#  INICIO DO BLOCO PADRAO  (v1.0)
# ═══════════════════════════════════════════════════════════════════════════

Set-StrictMode -Version Latest
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Global:UxLogPath   = $null
$Global:UxHasErrors = $false
$Script:UxVt        = $false

# ── Terminal virtual ───────────────────────────────────────────────────────
function Enable-VirtualTerminal {
    if ($env:NO_COLOR) { return $false }
    try {
        if (-not ('UxConsole.Native' -as [type])) {
            Add-Type -Namespace UxConsole -Name Native -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
'@ -ErrorAction Stop
        }
        $h = [UxConsole.Native]::GetStdHandle(-11)
        [uint32]$mode = 0
        if (-not [UxConsole.Native]::GetConsoleMode($h, [ref]$mode)) { return $false }
        return [UxConsole.Native]::SetConsoleMode($h, ($mode -bor 0x0004))
    } catch { return $false }
}
$Script:UxVt = Enable-VirtualTerminal

# ── Paleta ─────────────────────────────────────────────────────────────────
function ansi ([string]$Code) { if ($Script:UxVt) { "$([char]27)[$Code`m" } else { '' } }
function clr          { ansi '0'        }
function bold         { ansi '1'        }
function dim          { ansi '38;5;245' }
function col_ok       { ansi '38;5;114' }
function col_action   { ansi '38;5;221' }
function col_info     { ansi '38;5;81'  }
function col_error    { ansi '38;5;203' }
function col_warn     { ansi '38;5;215' }
function col_skip     { ansi '38;5;244' }
function col_head     { ansi '38;5;183' }
function col_bar_done { ansi '38;5;114' }
function col_bar_todo { ansi '38;5;239' }

# ── Formatadores ───────────────────────────────────────────────────────────
function Format-Tempo ([double]$Segundos) {
    if ($Segundos -lt 0 -or [double]::IsNaN($Segundos) -or [double]::IsInfinity($Segundos)) { $Segundos = 0 }
    $t = [TimeSpan]::FromSeconds([math]::Round($Segundos))
    if ($t.TotalHours -ge 1) { return ('{0:00}:{1:00}:{2:00}' -f [int]$t.TotalHours, $t.Minutes, $t.Seconds) }
    return ('{0:00}:{1:00}' -f $t.Minutes, $t.Seconds)
}

function Format-Tamanho ([double]$Bytes) {
    if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return ('{0:N0} B' -f $Bytes)
}

# ── Log unificado ──────────────────────────────────────────────────────────
function Start-Logging {
    param([string]$Caminho, [int]$MaxMB = 5)
    $Global:UxLogPath = $Caminho
    if ((Test-Path -LiteralPath $Caminho) -and ((Get-Item -LiteralPath $Caminho).Length -gt ($MaxMB * 1MB))) {
        $antigo = [IO.Path]::ChangeExtension($Caminho, '.old.txt')
        Move-Item -LiteralPath $Caminho -Destination $antigo -Force -ErrorAction SilentlyContinue
    }
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    @('=========================================================',
      " Sessao iniciada em: $ts",
      '=========================================================') |
        Out-File -LiteralPath $Caminho -Append -Encoding utf8
}

function Write-Log {
    param([string]$Message, [string]$Type = 'INFO')

    if ($Global:UxLogPath) {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $limpo = $Message -replace "$([char]27)\[[0-9;]*m", ''
        "[$ts] [$Type] $limpo" | Out-File -LiteralPath $Global:UxLogPath -Append -Encoding utf8
    }

    $icon = switch ($Type) {
        'SUCCESS' { [char]0x2714 } 'INFO' { [char]0x2139 } 'ACTION' { [char]0x2699 }
        'WARN'    { [char]0x26A0 } 'ERROR' { [char]0x2716 } 'SKIP'  { [char]0x21B7 }
        'HEADER'  { [char]0x25BA } default { ' ' }
    }
    $color = switch ($Type) {
        'SUCCESS' { col_ok } 'INFO' { col_info } 'ACTION' { col_action }
        'WARN'    { col_warn } 'ERROR' { col_error } 'SKIP' { col_skip }
        'HEADER'  { col_head } default { '' }
    }

    if ($Type -eq 'HEADER') {
        $rule = [string]::new([char]0x2500, 62)
        Write-Host ''
        Write-Host "  $(col_head)$icon $Message$(clr)"
        Write-Host "  $(dim)$rule$(clr)"
    } else {
        Write-Host "  $color$icon$(clr)  $Message"
        if ($Type -eq 'ERROR') { $Global:UxHasErrors = $true }
    }
}

# ── Cabecalho ──────────────────────────────────────────────────────────────
function Show-Header {
    param([string]$Titulo, [string]$Subtitulo, [switch]$SemLimpar)
    if (-not $SemLimpar) { Clear-Host }
    $rule = [string]::new([char]0x2500, 62)
    Write-Host ''
    Write-Host "  $(col_head)$(bold)$Titulo$(clr)"
    if ($Subtitulo) { Write-Host "  $(dim)$Subtitulo$(clr)" }
    Write-Host "  $(dim)$rule$(clr)"
    Write-Host ''
}

# ── Barra de progresso ─────────────────────────────────────────────────────
$Script:bPct = 0; $Script:bPos = ''; $Script:bIdx = 0; $Script:bTotal = 0
$Script:bName = ''; $Script:bStatus = ''; $Script:bExtra = ''

function Limpa-Linha {
    if ($Script:UxVt) { return "`r$([char]27)[2K" }
    return "`r$(' ' * 140)`r"
}

function Draw-Bar {
    $larg   = 28
    $cheio  = [math]::Min($larg, [math]::Round($larg * $Script:bPct / 100))
    $vazio  = $larg - $cheio
    $barF   = "$(col_bar_done)$([string]::new([char]0x2588, $cheio))$(clr)"
    $barE   = "$(col_bar_todo)$([string]::new([char]0x2591, $vazio))$(clr)"

    $corStatus = switch ($Script:bStatus) {
        'DONE' { col_ok } 'ERRO' { col_error } 'SKIP' { col_skip } default { col_action }
    }
    $txtStatus = if ($Script:bStatus) { "  $corStatus[$($Script:bStatus)]$(clr)" } else { '' }

    $maxLabel = 24
    $curto = if ($Script:bName.Length -gt $maxLabel) {
        [char]0x2026 + $Script:bName.Substring($Script:bName.Length - $maxLabel)
    } else { $Script:bName }

    $extra = if ($Script:bExtra) { "  $(dim)$($Script:bExtra)$(clr)" } else { '' }
    $linha = "  $barF$barE  $(bold)$($Script:bPct)%$(clr)  $(dim)[$($Script:bIdx)/$($Script:bTotal)]$(clr)  $(dim)$($Script:bPos)$(clr)$extra  $curto$txtStatus"
    Write-Host "$(Limpa-Linha)$linha" -NoNewline
}

function Emit-Live ([string]$Texto) {
    $t = $Texto.Trim()
    if ($t.Length -gt 96) { $t = $t.Substring(0, 95) + [char]0x2026 }
    Write-Host "$(Limpa-Linha)    $(dim)$t$(clr)"
    Draw-Bar
}

function Clear-Bar { Write-Host (Limpa-Linha) -NoNewline }

# ── Resumo ─────────────────────────────────────────────────────────────────
function Show-Resumo {
    param([hashtable[]]$Itens, [string]$Titulo = 'Resumo da Sessao')
    Write-Log $Titulo 'HEADER'
    $rule = [string]::new([char]0x2500, 48)
    $largura = 0
    foreach ($i in $Itens) { if ($i.Rotulo.Length -gt $largura) { $largura = $i.Rotulo.Length } }
    foreach ($i in $Itens) {
        $cor  = if ($i.ContainsKey('Cor')) { & $i.Cor } else { col_info }
        $icon = if ($i.ContainsKey('Icone')) { $i.Icone } else { ' ' }
        $rot  = $i.Rotulo.PadRight($largura)
        Write-Host "  $cor$icon$(clr)  $rot : $cor$($i.Valor)$(clr)"
    }
    Write-Host "  $(dim)$rule$(clr)"
    Write-Host ''
}

# ── Menu numerado ──────────────────────────────────────────────────────────
function Show-Menu {
    param([string]$Titulo, [string[]]$Opcoes, [int]$Padrao = 1)
    Write-Host ''
    Write-Host "  $(col_head)$Titulo$(clr)"
    Write-Host ''
    for ($i = 0; $i -lt $Opcoes.Count; $i++) {
        $n = $i + 1
        $marca = if ($n -eq $Padrao) { "$(col_action)>$(clr)" } else { ' ' }
        Write-Host "  $marca $(bold)[$n]$(clr) $($Opcoes[$i])"
    }
    Write-Host ''
    while ($true) {
        $r = Read-Host "  Escolha (Enter = $Padrao)"
        if ([string]::IsNullOrWhiteSpace($r)) { return $Padrao }
        $n = 0
        if ([int]::TryParse($r.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $Opcoes.Count) { return $n }
        Write-Log 'Opcao invalida.' 'WARN'
    }
}

# ── Confirmacao digitada, para acao destrutiva ─────────────────────────────
function Confirm-Digitado {
    param([string]$Mensagem, [string]$Palavra = 'CONFIRMAR')
    Write-Host ''
    Write-Host "  $(col_error)$(bold)$Mensagem$(clr)"
    Write-Host "  $(dim)Digite $(clr)$(bold)$Palavra$(clr)$(dim) para prosseguir, ou qualquer outra coisa para cancelar.$(clr)"
    $r = Read-Host '  '
    return ($r.Trim() -ceq $Palavra)
}

# ── Energia: impede o Windows de suspender durante o trabalho ──────────────
function Set-ManterAcordado {
    param([switch]$Desligar)
    try {
        if (-not ('UxPower.Native' -as [type])) {
            Add-Type -Namespace UxPower -Name Native -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);
'@ -ErrorAction Stop
        }
        # CONTINUOUS | SYSTEM_REQUIRED | AWAYMODE_REQUIRED
        $flags = if ($Desligar) { 0x80000000 } else { 0x80000000 -bor 0x00000001 -bor 0x00000040 }
        [void][UxPower.Native]::SetThreadExecutionState([uint32]$flags)
        return $true
    } catch { return $false }
}

# ── Encerramento padrao ────────────────────────────────────────────────────
function Wait-Fechar {
    param([switch]$SemInteracao)
    if ($SemInteracao) { return }
    Write-Host ''
    Write-Host "  $(dim)Pressione qualquer tecla para fechar...$(clr)"
    $null = [System.Console]::ReadKey($true)
}

# ═══════════════════════════════════════════════════════════════════════════
#  FIM DO BLOCO PADRAO
# ═══════════════════════════════════════════════════════════════════════════

$ErrorActionPreference = 'Stop'

# ── Funil de teste de um dominio (texto reaproveitado dentro das threads) ──
# Retorna: LIVRE, LIVRE_DNS (so DNS, nao confirmado), REGISTRADO, CONTRADICAO,
#          INCERTO, INVALIDO, LIMITE (HTTP 429) ou ERRO.
$TestarDominio = {
    param([string]$Dominio, [hashtable]$Cfg)
    $ProgressPreference = 'SilentlyContinue'

    $http = {
        param([string]$D, [string]$Metodo)
        try {
            $r = Invoke-WebRequest -Uri ($Cfg['Base'] + 'domain/' + $D) -Method $Metodo -SkipHttpErrorCheck -TimeoutSec 20 -MaximumRedirection 3 -UserAgent 'DomainDash/3.0'
            return [int]$r.StatusCode
        } catch { return 0 }
    }
    $dns = {
        param([string]$D, [string]$S)
        try {
            $null = Resolve-DnsName -Name $D -Type SOA -Server $S -DnsOnly -NoHostsFile -ErrorAction Stop
            return 'REGISTRADO'
        } catch {
            $id = [string]$_.FullyQualifiedErrorId
            if ($id -match 'RCODE_NAME_ERROR') { return 'LIVRE' }
            if ($id -match 'INFO_NO_RECORDS')  { return 'REGISTRADO' }
            return 'ERRO'
        }
    }
    $whois = {
        param([string]$D)
        $txt = ''
        try {
            $cli = [System.Net.Sockets.TcpClient]::new()
            if (-not $cli.ConnectAsync($Cfg['WhoisHost'], [int]$Cfg['WhoisPort']).Wait(8000)) { $cli.Dispose(); return 'ERRO' }
            $ns = $cli.GetStream(); $ns.ReadTimeout = 8000; $ns.WriteTimeout = 8000
            $b = [System.Text.Encoding]::ASCII.GetBytes("$D`r`n"); $ns.Write($b, 0, $b.Length)
            $txt = ([System.IO.StreamReader]::new($ns, [System.Text.Encoding]::UTF8)).ReadToEnd()
            $cli.Dispose()
        } catch { return 'ERRO' }
        if ($txt -match '(?i)(no match|not found|no entries found|no data found|no object found|nothing found|status:\s*(free|available)|is available|not registered|no such domain)') { return 'LIVRE' }
        if ($txt -match '(?i)(rate limit|too many|quota|exceeded|try again later|blocked)') { return 'LIMITE' }
        if ($txt -match '(?im)^\s*(domain( name)?|domain-name)\s*:') { return 'REGISTRADO' }
        return 'INCERTO'
    }

    if ($Cfg['Modo'] -eq 'RDAP') {
        # Camada 2: RDAP precisa dizer "nao existe" duas vezes, por metodos diferentes
        $c = & $http $Dominio 'Head'
        if ($c -eq 405 -or $c -eq 501) { $c = & $http $Dominio 'Get' }
        if ($c -eq 200 -or $c -eq 401) { return 'REGISTRADO' }
        if ($c -eq 429) { return 'LIMITE' }
        if ($c -eq 400 -or $c -eq 422) { return 'INVALIDO' }
        if ($c -ne 404) { return 'ERRO' }
        Start-Sleep -Milliseconds 400
        $c2 = & $http $Dominio 'Get'
        if ($c2 -eq 200 -or $c2 -eq 401) { return 'REGISTRADO' }
        if ($c2 -eq 429) { return 'LIMITE' }
        if ($c2 -ne 404) { return 'ERRO' }
        # Camada 3: o DNS so tem poder de veto
        if ($Cfg['DnsVeto']) {
            if ((& $dns $Dominio $Cfg['Servidores'][0]) -eq 'REGISTRADO') { return 'CONTRADICAO' }
        }
        return 'LIVRE'
    }

    # TLD sem RDAP: DNS em dois servidores + WHOIS do registro
    $s   = $Cfg['Servidores']
    $a   = & $dns $Dominio $s[0]
    $sec = $s[1]
    if ($a -eq 'ERRO') { $a = & $dns $Dominio $s[1]; $sec = $s[0] }
    if ($a -eq 'REGISTRADO') { return 'REGISTRADO' }
    if ($a -ne 'LIVRE') { return 'ERRO' }
    $b = & $dns $Dominio $sec
    if ($b -eq 'REGISTRADO') { return 'REGISTRADO' }
    if ($b -ne 'LIVRE') { return 'ERRO' }
    if ($Cfg['WhoisHost']) {
        $w = & $whois $Dominio
        if ($w -eq 'LIVRE') { return 'LIVRE' }
        if ($w -eq 'REGISTRADO') { return 'CONTRADICAO' }
        if ($w -eq 'LIMITE') { return 'LIMITE' }
        if ($w -eq 'ERRO') { return 'ERRO' }
        return 'INCERTO'
    }
    return 'LIVRE_DNS'
}
$txtTestar = $TestarDominio.ToString()

function Invoke-Consulta {
    param([string[]]$Dominios, [int]$Paralelo)
    $txt = $txtTestar; $cfg = $cfgBusca
    $Dominios | ForEach-Object -Parallel {
        $q = [scriptblock]::Create($using:txt)
        [pscustomobject]@{ Dominio = $_; Resultado = (& $q $_ $using:cfg) }
    } -ThrottleLimit $Paralelo
}

# ── Utilitarios ────────────────────────────────────────────────────────────
function Get-Mdc ([long]$x, [long]$y) {
    while ($y -ne 0) { $t = $x % $y; $x = $y; $y = $t }
    return $x
}

function Get-Rotulo ([long]$Indice) {
    if ($null -ne $Script:dicLista) { return $Script:dicLista[[int]$Indice] }
    $n = $Script:conjuntos.Count
    $chars = [char[]]::new($n)
    for ($i = $n - 1; $i -ge 0; $i--) {
        $s = $Script:conjuntos[$i]
        $chars[$i] = $s[[int]($Indice % $s.Count)]
        $Indice = [long][math]::Floor($Indice / $s.Count)
    }
    return (-join $chars)
}

function Format-Rotulo-Normalizado ([string]$Texto) {
    $p = $Texto.Trim().ToLowerInvariant().Normalize([System.Text.NormalizationForm]::FormD)
    $p = [regex]::Replace($p, '\p{Mn}', '')
    return ([regex]::Replace($p, '[\s_]', ''))
}

function Read-Dicionario {
    param([string]$Caminho, [string[]]$Proibidos)
    $itens = [System.Collections.Generic.List[object]]::new()
    $invalidas = 0; $excluidas = 0
    foreach ($linha in [System.IO.File]::ReadAllLines($Caminho, [System.Text.Encoding]::UTF8)) {
        $l = $linha.Trim()
        if ($l -eq '' -or $l.StartsWith('#')) { continue }
        $partes = $l.Split(';', 2)
        $p = Format-Rotulo-Normalizado $partes[0]
        $d = if ($partes.Count -gt 1) { $partes[1].Trim() } else { '' }
        if ($p.Length -lt 1 -or $p.Length -gt 63 -or $p -notmatch '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$') { $invalidas++; continue }
        $tem = $false
        foreach ($x in $Proibidos) { if ($p.Contains($x)) { $tem = $true; break } }
        if ($tem) { $excluidas++; continue }
        $itens.Add([pscustomobject]@{ Palavra = $p; Desc = $d })
    }
    return @{ Itens = $itens; Invalidas = $invalidas; Excluidas = $excluidas }
}

# ── Contadores e exibicao em tempo real ────────────────────────────────────
$Script:testados = [long]0; $Script:achados = [long]0; $Script:registrados = [long]0
$Script:invalidos = [long]0; $Script:indeterminados = [long]0; $Script:contradicoes = [long]0
$Script:incertos = [long]0; $Script:ignorados = [long]0; $Script:descartados = [long]0
$Script:pendentes = [System.Collections.Generic.List[string]]::new()
$Script:pendLote  = [System.Collections.Generic.List[string]]::new()
$Script:livresLote = [System.Collections.Generic.List[object]]::new()
$Script:listaInvalidos = [System.Collections.Generic.List[string]]::new()
$Script:viuLimite = $false; $Script:canarioFalhou = $false
$Script:alvo = [long]1; $Script:ultimo = ''; $Script:iniciou = $false
$Script:dicLista = $null; $Script:descricoes = @{}; $Script:conjuntos = $null
$Script:sufixo = ''; $Script:minLen = 1; $Script:reservados = @(); $Script:canario = ''

function Update-Barra {
    $seg  = [math]::Max(0.001, $tempo.Elapsed.TotalSeconds)
    $taxa = $Script:testados / $seg
    $eta  = if ($taxa -gt 0) { ($Script:alvo - $Script:testados) / $taxa } else { 0 }
    $Script:bIdx   = $Script:testados
    $Script:bTotal = $Script:alvo
    $Script:bPct   = [int][math]::Min(100, [math]::Floor(($Script:testados / [double]$Script:alvo) * 100))
    $Script:bName  = $Script:ultimo
    $Script:bPos   = Format-Tempo $seg
    $Script:bExtra = ('livres {0:N0}  {1:N1}/s  falta {2}' -f $Script:achados, $taxa, (Format-Tempo $eta))
    Draw-Bar
}

function Add-Achado ([string]$Dominio, [string]$Tag = '') {
    $Script:achados++
    if (-not $Simular) { [System.IO.File]::AppendAllText($arqLivres, "$Dominio`r`n") }
    $rotulo = $Dominio.Substring(0, $Dominio.Length - $Script:sufixo.Length)
    $desc = if ($Script:descricoes.ContainsKey($rotulo) -and $Script:descricoes[$rotulo]) { "   -   $($Script:descricoes[$rotulo])" } else { '' }
    $nota = if ($Tag -eq 'LIVRE_DNS') { '   (DNS apenas, nao confirmado)' } else { '' }
    $marca = if ($Simular) { ' (simulacao, nao gravado)' } else { '' }
    Clear-Bar
    Write-Log ("[{0:N0}]  {1}{2}{3}{4}" -f $Script:achados, $Dominio, $desc, $nota, $marca) 'SUCCESS'
    Update-Barra
}

function Register-Resultado {
    param($Item)
    if ($Script:canario -and $Item.Dominio -eq $Script:canario) {
        switch ($Item.Resultado) {
            'REGISTRADO' { }
            'LIMITE'     { $Script:viuLimite = $true }
            'ERRO'       { }
            default      { $Script:canarioFalhou = $true }
        }
        return
    }
    $Script:ultimo = $Item.Dominio
    switch ($Item.Resultado) {
        'LIVRE'       { $Script:testados++; $Script:livresLote.Add([pscustomobject]@{ Dominio = $Item.Dominio; Tag = 'LIVRE' }); return }
        'LIVRE_DNS'   { $Script:testados++; $Script:livresLote.Add([pscustomobject]@{ Dominio = $Item.Dominio; Tag = 'LIVRE_DNS' }); return }
        'REGISTRADO'  { $Script:testados++; $Script:registrados++ }
        'CONTRADICAO' { $Script:testados++; $Script:contradicoes++ }
        'INCERTO'     { $Script:testados++; $Script:incertos++ }
        'IGNORADO'    { $Script:testados++; $Script:ignorados++ }
        'INVALIDO'    { $Script:testados++; $Script:invalidos++; $Script:listaInvalidos.Add($Item.Dominio) }
        'LIMITE'      { $Script:viuLimite = $true; $Script:pendLote.Add($Item.Dominio); return }
        default       { $Script:pendLote.Add($Item.Dominio); return }
    }
    if (($Script:testados % 25) -eq 0) { Update-Barra }
}

# Camada 1: sintaxe e nomes reservados do TLD
function Test-Sintaxe ([string]$Rotulo) {
    if ($Rotulo.Length -lt $Script:minLen -or $Rotulo.Length -gt 63) { return $false }
    if ($Rotulo.StartsWith('-') -or $Rotulo.EndsWith('-')) { return $false }
    if ($Rotulo.Length -ge 4 -and $Rotulo.Substring(2, 2) -eq '--') { return $false }
    if ($Script:reservados -contains $Rotulo) { return $false }
    return $true
}

# Camada 4: controle. Um registrado conhecido e um inexistente passam pelo mesmo funil,
# antes/depois do lote e tambem DENTRO do lote (canarios espalhados entre os nomes).
function Test-Fonte {
    $sent = 'teste-inexistente-' + [guid]::NewGuid().ToString('N').Substring(0, 10) + $Script:sufixo
    $r1 = & $TestarDominio $sent $cfgBusca
    $r2 = if ($Script:canario) { & $TestarDominio $Script:canario $cfgBusca } else { 'REGISTRADO' }
    return (($r1 -eq 'LIVRE' -or $r1 -eq 'LIVRE_DNS') -and $r2 -eq 'REGISTRADO')
}

function Add-Canarios ([string[]]$Lista) {
    if (-not $Script:canario -or $Lista.Count -eq 0) { return $Lista }
    $qtd   = [math]::Max(2, [int][math]::Ceiling($Lista.Count / 20))
    $passo = [math]::Max(1, [int][math]::Floor($Lista.Count / $qtd))
    $saida = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Lista.Count; $i++) {
        if (($i % $passo) -eq 0) { $saida.Add($Script:canario) }
        $saida.Add($Lista[$i])
    }
    return $saida.ToArray()
}

# Confirma os achados do lote somente com a fonte comprovadamente confiavel
function Save-LivresLote {
    $suspeito = $Script:canarioFalhou
    $Script:canarioFalhou = $false
    if ($Script:livresLote.Count -eq 0) { return }
    $lista = $Script:livresLote.ToArray()
    $Script:livresLote.Clear()

    if (-not $suspeito) {
        if (Test-Fonte) {
            foreach ($i in $lista) { Add-Achado $i.Dominio $i.Tag }
            return
        }
        $suspeito = $true
    }

    # Fonte suspeita durante o lote: revalida os achados com controles embutidos
    $doms = @($lista | ForEach-Object { $_.Dominio })
    for ($tent = 1; $tent -le 3; $tent++) {
        $espera = 15 * $tent
        $Script:paralelo = [math]::Max(1, [int][math]::Floor($Script:paralelo / 2))
        Clear-Bar
        Write-Log "Controle falhou neste lote (servidor instavel ou limitando). Pausa de $espera s e revalidacao de $($doms.Count) achado(s), tentativa $tent de 3." 'WARN'
        Update-Barra
        Start-Sleep -Seconds $espera
        if (-not (Test-Fonte)) { continue }
        $falhaInterna = $false
        $mantem = @{}
        foreach ($r in @(Invoke-Consulta -Dominios (Add-Canarios $doms) -Paralelo $Script:paralelo)) {
            if ($r.Dominio -eq $Script:canario) {
                if ($r.Resultado -ne 'REGISTRADO' -and $r.Resultado -ne 'LIMITE' -and $r.Resultado -ne 'ERRO') { $falhaInterna = $true }
                continue
            }
            if ($r.Resultado -eq 'LIVRE' -or $r.Resultado -eq 'LIVRE_DNS') { $mantem[$r.Dominio] = $r.Resultado }
        }
        if ($falhaInterna) { continue }
        foreach ($i in $lista) {
            if ($mantem.ContainsKey($i.Dominio)) { Add-Achado $i.Dominio $mantem[$i.Dominio] }
            else { $Script:descartados++ }
        }
        return
    }
    foreach ($i in $lista) { $Script:descartados++; $Script:pendentes.Add($i.Dominio) }
    Clear-Bar
    Write-Log "Fonte nao confiavel: $($lista.Count) achado(s) deste lote descartado(s) por seguranca." 'WARN'
    Update-Barra
}

function Get-WhoisServidor ([string]$TldCompleto) {
    $ultimo = ($TldCompleto -split '\.')[-1]
    try {
        $cli = [System.Net.Sockets.TcpClient]::new()
        if (-not $cli.ConnectAsync('whois.iana.org', 43).Wait(8000)) { $cli.Dispose(); return '' }
        $ns = $cli.GetStream(); $ns.ReadTimeout = 8000
        $b = [System.Text.Encoding]::ASCII.GetBytes("$ultimo`r`n"); $ns.Write($b, 0, $b.Length)
        $txt = ([System.IO.StreamReader]::new($ns)).ReadToEnd()
        $cli.Dispose()
        $m = [regex]::Match($txt, '(?im)^whois:\s*(\S+)')
        if ($m.Success) { return $m.Groups[1].Value }
    } catch { }
    return ''
}

# ── Pastas e arquivos ──────────────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($Pasta)) {
    $Pasta = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
}
$raiz      = (Resolve-Path -LiteralPath $Pasta).Path
$arqLivres = Join-Path $raiz 'dominios-disponiveis.txt'
$arqTrava  = Join-Path $raiz 'cacador-dominios.lock'
$arqLog    = Join-Path $raiz 'cacador-dominios-log.txt'
if ([string]::IsNullOrWhiteSpace($PastaDicionarios)) { $PastaDicionarios = Join-Path $raiz 'dicionarios' }
$anteriores = @(
    $arqLivres, $arqLog, (Join-Path $raiz 'cacador-dominios-log.old.txt'),
    (Join-Path $raiz 'dominios-si-disponiveis.txt'), (Join-Path $raiz 'cacador-si-log.txt'),
    (Join-Path $raiz 'cacador-si-log.old.txt'), (Join-Path $raiz 'cacador-si-estado.json'),
    (Join-Path $raiz 'cacador-si-estado.json.tmp')
)
$travaCriada = $false
$tempo = [System.Diagnostics.Stopwatch]::new()
$apagados = @()
$cfgBusca = @{}

Show-Header -Titulo 'DomainDash  -  DOMINIOS LIVRES' -Subtitulo $(if ($Simular) { 'MODO SIMULAR - nada sera apagado ou gravado' } else { 'RDAP do registro, ou DNS quando o TLD nao tem RDAP' })

try {
    # Trava antes de apagar qualquer coisa: outra copia rodando nao pode perder seus arquivos
    if (-not $Simular -and (Test-Path -LiteralPath $arqTrava)) {
        $pidAntigo = 0
        [void][int]::TryParse(((Get-Content -LiteralPath $arqTrava -Raw -ErrorAction SilentlyContinue) ?? '').Trim(), [ref]$pidAntigo)
        if ($pidAntigo -gt 0 -and (Get-Process -Id $pidAntigo -ErrorAction SilentlyContinue)) {
            Write-Log "Ja existe outra copia rodando nesta pasta (PID $pidAntigo)." 'ERROR'
            Wait-Fechar -SemInteracao:$SemInteracao
            return
        }
        Remove-Item -LiteralPath $arqTrava -Force -ErrorAction SilentlyContinue
    }
    if (-not $Simular) {
        Set-Content -LiteralPath $arqTrava -Value $PID -Encoding ascii
        $travaCriada = $true
        foreach ($f in $anteriores) {
            if ([System.IO.Path]::GetDirectoryName($f) -ne $raiz) { continue }
            if (Test-Path -LiteralPath $f) {
                try {
                    Remove-Item -LiteralPath $f -Force
                    $apagados += [System.IO.Path]::GetFileName($f)
                } catch {
                    Write-Log "Nao foi possivel apagar $([System.IO.Path]::GetFileName($f)) (arquivo aberto em outro programa?). Feche e rode de novo." 'ERROR'
                    Wait-Fechar -SemInteracao:$SemInteracao
                    return
                }
            }
        }
    }
    Start-Logging -Caminho $arqLog
    if ($apagados.Count -gt 0) { Write-Log "Arquivos da execucao anterior apagados: $($apagados -join ', ')" 'ACTION' }

    # ── 1. TLD ─────────────────────────────────────────────────────────────
    Write-Log 'Configuracao' 'HEADER'
    $interativo = -not $SemInteracao
    if ($interativo -and -not $PSBoundParameters.ContainsKey('Tld')) {
        $tldsComuns = @('si', 'com', 'ai', 'io', 'com.br', 'net', 'org', 'dev', 'app')
        $rot = @($tldsComuns | ForEach-Object { ".$_" }) + @('Outro (digitar)')
        $esc = Show-Menu -Titulo 'TLD (extensao do dominio)' -Opcoes $rot -Padrao 1
        if ($esc -le $tldsComuns.Count) { $Tld = $tldsComuns[$esc - 1] }
        else { $Tld = Read-Host '  Digite o TLD (ex: info, co.uk)' }
    }
    if ([string]::IsNullOrWhiteSpace($Tld)) { $Tld = 'si' }
    $Tld = $Tld.Trim().ToLowerInvariant().TrimStart('.')
    if ($Tld -notmatch '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$') {
        Write-Log "TLD invalido: '$Tld'" 'ERROR'
        Wait-Fechar -SemInteracao:$SemInteracao
        return
    }
    $Script:sufixo = ".$Tld"

    # ── 2. Caracteres a excluir ────────────────────────────────────────────
    if ($interativo -and -not $PSBoundParameters.ContainsKey('Excluir')) {
        Write-Host ''
        Write-Host "  $(dim)Letras ou numeros que voce NAO quer na busca (ex: g6ql e1). Enter = nenhum.$(clr)"
        $Excluir = Read-Host '  Excluir'
    }
    $proibidos = @(([regex]::Replace($Excluir.ToLowerInvariant(), '[^a-z0-9]', '').ToCharArray()) | Sort-Object -Unique | ForEach-Object { [string]$_ })
    $strProib = -join $proibidos
    if ($proibidos.Count -gt 0) { Write-Log "Caracteres excluidos: $($proibidos -join ' ')" 'INFO' }
    else { Write-Log 'Caracteres excluidos: nenhum' 'INFO' }

    $Script:Filtrar = { param([string]$Simbolos) -join @($Simbolos.ToCharArray() | Where-Object { $strProib.IndexOf($_) -lt 0 }) }

    # ── 3. Tipo de busca ───────────────────────────────────────────────────
    if ($interativo -and -not $PSBoundParameters.ContainsKey('Busca')) {
        $esc = Show-Menu -Titulo 'Tipo de busca' -Padrao 1 -Opcoes @(
            'Combinacoes de um alfabeto (letras, numeros, consoantes, vogais...)',
            'Padrao com curingas (ex: 0XXX0 = numero, 3 letras, numero)',
            'Dicionario de palavras (arquivo .txt)')
        $Busca = @('Combinacoes', 'Padrao', 'Dicionario')[$esc - 1]
    }

    $SIMB = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $SIMB['0'] = '0123456789'; $SIMB['X'] = 'abcdefghijklmnopqrstuvwxyz'; $SIMB['C'] = 'bcdfghjklmnpqrstvwxyz'
    $SIMB['V'] = 'aeiou';      $SIMB['A'] = 'abcdefghijklmnopqrstuvwxyz0123456789'
    $NOMES = @{ '0' = 'numero'; 'X' = 'letra'; 'C' = 'consoante'; 'V' = 'vogal'; 'A' = 'letra ou numero' }

    $espaco = [System.Numerics.BigInteger]1
    $descBusca = ''

    if ($Busca -eq 'Combinacoes') {
        if ($interativo -and -not $PSBoundParameters.ContainsKey('Caracteres')) {
            while ($true) {
                $r = Read-Host '  Quantos caracteres antes do TLD (1 a 12, Enter = 5)'
                if ([string]::IsNullOrWhiteSpace($r)) { $Caracteres = 5; break }
                $v = 0
                if ([int]::TryParse($r.Trim(), [ref]$v) -and $v -ge 1 -and $v -le 12) { $Caracteres = $v; break }
                Write-Log 'Valor invalido. Digite um numero de 1 a 12.' 'WARN'
            }
        }
        $alfs = [ordered]@{
            'Letras'        = @{ Rotulo = 'Letras (a-z)';                Simbolos = $SIMB['X'] }
            'LetrasNumeros' = @{ Rotulo = 'Letras e numeros (a-z, 0-9)'; Simbolos = $SIMB['A'] }
            'Consoantes'    = @{ Rotulo = 'So consoantes (inclui y)';    Simbolos = $SIMB['C'] }
            'Vogais'        = @{ Rotulo = 'So vogais (a e i o u)';       Simbolos = $SIMB['V'] }
            'Numeros'       = @{ Rotulo = 'So numeros (0-9)';            Simbolos = $SIMB['0'] }
        }
        $chaves = @($alfs.Keys)
        if ($interativo -and -not $PSBoundParameters.ContainsKey('Alfabeto')) {
            $esc = Show-Menu -Titulo 'Alfabeto' -Opcoes @($chaves | ForEach-Object { $alfs[$_].Rotulo }) -Padrao 3
            $Alfabeto = $chaves[$esc - 1]
        }
        $simb = (& $Script:Filtrar $alfs[$Alfabeto].Simbolos).ToCharArray()
        if ($simb.Count -eq 0) {
            Write-Log 'Os caracteres excluidos eliminam todo o alfabeto escolhido.' 'ERROR'
            Wait-Fechar -SemInteracao:$SemInteracao
            return
        }
        $Script:conjuntos = [System.Collections.Generic.List[char[]]]::new()
        for ($i = 0; $i -lt $Caracteres; $i++) { $Script:conjuntos.Add($simb) }
        $descBusca = "Combinacoes de $Caracteres caracteres, alfabeto $($alfs[$Alfabeto].Rotulo) ($($simb.Count) simbolos: $(-join $simb))"
    }
    elseif ($Busca -eq 'Padrao') {
        if ($interativo -and [string]::IsNullOrWhiteSpace($Padrao)) {
            Write-Host ''
            Write-Host "  $(dim)0 = numero   X = letra   C = consoante   V = vogal   A = letra ou numero$(clr)"
            Write-Host "  $(dim)Minusculas, 1 a 9 e hifen sao caracteres fixos. Exemplos: 0XXX0   CVCV   ai-XXX$(clr)"
            $Padrao = Read-Host '  Padrao'
        }
        $Padrao = $Padrao.Trim()
        if ($Padrao.Length -lt 1 -or $Padrao.Length -gt 63) {
            Write-Log 'Padrao vazio ou maior que 63 caracteres.' 'ERROR'
            Wait-Fechar -SemInteracao:$SemInteracao
            return
        }
        $Script:conjuntos = [System.Collections.Generic.List[char[]]]::new()
        $resumo = [System.Collections.Generic.List[string]]::new()
        $erroPadrao = ''
        foreach ($ch in $Padrao.ToCharArray()) {
            $s = [string]$ch
            if ($SIMB.ContainsKey($s)) {
                $conj = (& $Script:Filtrar $SIMB[$s]).ToCharArray()
                if ($conj.Count -eq 0) { $erroPadrao = "Os caracteres excluidos eliminam todas as opcoes de '$s' ($($NOMES[$s]))."; break }
                $Script:conjuntos.Add($conj); $resumo.Add("[$($NOMES[$s])]")
            }
            elseif ($s -cmatch '^[a-z1-9-]$') {
                if ($strProib.Contains($s)) { $erroPadrao = "O caractere fixo '$s' do padrao esta na lista de excluidos."; break }
                $Script:conjuntos.Add([char[]]@($ch)); $resumo.Add("'$s'")
            }
            else { $erroPadrao = "Caractere '$s' nao e valido no padrao (use 0 X C V A, minusculas, 1 a 9 ou hifen)."; break }
        }
        if (-not $erroPadrao -and ($Padrao.StartsWith('-') -or $Padrao.EndsWith('-'))) { $erroPadrao = 'O padrao nao pode comecar nem terminar com hifen.' }
        if ($erroPadrao) {
            Write-Log $erroPadrao 'ERROR'
            Wait-Fechar -SemInteracao:$SemInteracao
            return
        }
        $descBusca = "Padrao $Padrao = $($resumo -join ' ')"
    }
    else {
        if (-not (Test-Path -LiteralPath $PastaDicionarios)) { [void](New-Item -ItemType Directory -Path $PastaDicionarios -Force) }
        $arqs = @(Get-ChildItem -LiteralPath $PastaDicionarios -Filter '*.txt' -File | Sort-Object Name)
        if ($arqs.Count -eq 0) {
            Write-Log "Nenhum dicionario encontrado em: $PastaDicionarios" 'WARN'
            Write-Log 'Formato: arquivo .txt (UTF-8) nessa pasta, uma palavra por linha.' 'INFO'
            Write-Log 'Opcional: palavra;descricao (a descricao aparece na tela junto do achado).' 'INFO'
            Write-Log 'Linhas vazias e linhas iniciadas por # sao ignoradas. Acentos e espacos sao removidos; so valem a-z, 0-9 e hifen.' 'INFO'
            Wait-Fechar -SemInteracao:$SemInteracao
            return
        }
        $contagens = @{}
        foreach ($a in $arqs) { $contagens[$a.Name] = @{ N = (Read-Dicionario -Caminho $a.FullName -Proibidos $proibidos).Itens.Count } }
        $escolhidos = @()
        if ([string]::IsNullOrWhiteSpace($Dicionario)) {
            if (-not $interativo) { Write-Log 'Informe -Dicionario (nome do arquivo ou "todos").' 'ERROR'; return }
            $rot = @($arqs | ForEach-Object { "{0}  ({1:N0} palavras)" -f $_.Name, $contagens[$_.Name].N }) + @('Todos os dicionarios juntos')
            $esc = Show-Menu -Titulo 'Dicionario' -Opcoes $rot -Padrao 1
            $escolhidos = if ($esc -gt $arqs.Count) { $arqs } else { @($arqs[$esc - 1]) }
        } elseif ($Dicionario.Trim().ToLowerInvariant() -eq 'todos') { $escolhidos = $arqs }
        else {
            $nome = $Dicionario.Trim(); if (-not $nome.ToLowerInvariant().EndsWith('.txt')) { $nome += '.txt' }
            $escolhidos = @($arqs | Where-Object { $_.Name -ieq $nome })
            if ($escolhidos.Count -eq 0) { Write-Log "Dicionario nao encontrado: $nome (pasta $PastaDicionarios)" 'ERROR'; Wait-Fechar -SemInteracao:$SemInteracao; return }
        }
        $vistos = [System.Collections.Generic.HashSet[string]]::new()
        $lista = [System.Collections.Generic.List[string]]::new()
        $totInv = 0; $totExc = 0
        foreach ($a in $escolhidos) {
            $d = Read-Dicionario -Caminho $a.FullName -Proibidos $proibidos
            $totInv += $d.Invalidas; $totExc += $d.Excluidas
            foreach ($it in $d.Itens) {
                if ($vistos.Add($it.Palavra)) { $lista.Add($it.Palavra); if ($it.Desc) { $Script:descricoes[$it.Palavra] = $it.Desc } }
            }
        }
        if ($lista.Count -eq 0) {
            Write-Log 'Nenhuma palavra utilizavel no(s) dicionario(s) escolhido(s).' 'ERROR'
            Wait-Fechar -SemInteracao:$SemInteracao
            return
        }
        $Script:dicLista = $lista.ToArray()
        $descBusca = "Dicionario: $(($escolhidos | ForEach-Object { $_.Name }) -join ', ') ($($lista.Count) palavras; $totInv invalidas e $totExc com caractere excluido descartadas)"
    }

    if ($null -ne $Script:dicLista) { $espaco = [System.Numerics.BigInteger]$Script:dicLista.Count }
    else { foreach ($c in $Script:conjuntos) { $espaco = $espaco * $c.Count } }
    if ($espaco -gt [System.Numerics.BigInteger]4000000000000000000) {
        Write-Log 'O espaco de combinacoes e grande demais. Reduza o tamanho ou use mais caracteres fixos.' 'ERROR'
        Wait-Fechar -SemInteracao:$SemInteracao
        return
    }
    $Espaco = [long]$espaco
    Write-Log $descBusca 'INFO'
    Write-Log ("Nomes possiveis: {0:N0}   |   TLD: .{1}" -f $Espaco, $Tld) 'INFO'

    # ── 4. Metodo de consulta (RDAP ou DNS) e autoteste ───────────────────
    Write-Log 'Verificando ambiente' 'HEADER'
    $ultimoLabel = ($Tld -split '\.')[-1]
    $base = $null; $origem = ''
    try {
        $boot = Invoke-RestMethod -Uri $BootstrapUrl -TimeoutSec 20 -UserAgent 'DomainDash/2.0'
        foreach ($svc in $boot.services) {
            if (@($svc[0]) -contains $ultimoLabel) {
                $urls = @($svc[1])
                $u = @($urls | Where-Object { $_ -like 'https://*' } | Select-Object -First 1)
                if ($u.Count -eq 0) { $u = @($urls[0]) }
                $base = ([string]$u[0]).TrimEnd('/') + '/'
                $origem = 'IANA'
                break
            }
        }
    } catch {
        Write-Log 'Lista RDAP da IANA indisponivel. Tentando enderecos conhecidos.' 'WARN'
        $conhecidos = @{ 'si' = 'https://rdap.register.si/'; 'com' = 'https://rdap.verisign.com/com/v1/'; 'net' = 'https://rdap.verisign.com/net/v1/' }
        if ($conhecidos.ContainsKey($ultimoLabel)) { $base = $conhecidos[$ultimoLabel]; $origem = 'embutido' }
    }

    # Regras do TLD (camada 1)
    $Script:minLen = if ($Tld -eq 'si') { 2 } else { 1 }
    $Script:reservados = if ($Tld -eq 'si') { @('113', '112', 'si', 'rs') } else { @() }

    $dnsDisponivel = [bool](Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)
    if ($base) {
        $cfgBusca = @{ Modo = 'RDAP'; Base = $base; Servidores = $Servidores; DnsVeto = $dnsDisponivel; WhoisHost = ''; WhoisPort = 43 }
        Write-Log "Metodo: RDAP do registro ($base, fonte $origem)" 'SUCCESS'
        if ($dnsDisponivel) { Write-Log "Camadas ativas: sintaxe, RDAP duas vezes, veto do DNS ($($Servidores[0])), controle por lote" 'INFO' }
        else { Write-Log 'Camadas ativas: sintaxe, RDAP duas vezes, controle por lote (veto do DNS indisponivel neste sistema)' 'WARN' }
        $threadsMax = if ($Threads -gt 0) { $Threads } else { 8 }
        if ($TamanhoLote -le 0) { $TamanhoLote = 100 }
    } else {
        if (-not $dnsDisponivel) {
            Write-Log "O TLD .$Tld nao tem RDAP e este Windows nao tem Resolve-DnsName." 'ERROR'
            Wait-Fechar -SemInteracao:$SemInteracao
            return
        }
        $wh = ''; $wp = 43
        if ($WhoisHost) {
            $partes = $WhoisHost.Split(':')
            $wh = $partes[0]; if ($partes.Count -gt 1) { [void][int]::TryParse($partes[1], [ref]$wp) }
        } else { $wh = Get-WhoisServidor $Tld }
        $cfgBusca = @{ Modo = 'DNS'; Base = ''; Servidores = $Servidores; DnsVeto = $false; WhoisHost = $wh; WhoisPort = $wp }
        Write-Log "O TLD .$Tld nao tem RDAP. Usando DNS em dois servidores ($($Servidores -join ' + '))." 'WARN'
        if ($wh) { Write-Log "Segunda fonte: WHOIS do registro ($wh)" 'INFO' }
        else { Write-Log 'Sem servidor WHOIS: achados serao marcados como "DNS apenas, nao confirmado" (DNS nao enxerga dominio registrado sem DNS, em quarentena ou reservado).' 'WARN' }
        $threadsMax = if ($Threads -gt 0) { $Threads } else { 64 }
        if ($TamanhoLote -le 0) { $TamanhoLote = 400 }
    }
    $Script:paralelo = $threadsMax

    # Autoteste: o funil completo precisa reconhecer um inexistente e um registrado
    $sentinela = 'teste-inexistente-' + [guid]::NewGuid().ToString('N').Substring(0, 10) + $Script:sufixo
    $rLivre = & $TestarDominio $sentinela $cfgBusca
    if (($rLivre -eq 'INCERTO' -or $rLivre -eq 'ERRO' -or $rLivre -eq 'LIMITE') -and $cfgBusca['Modo'] -eq 'DNS' -and $cfgBusca['WhoisHost']) {
        Write-Log "O WHOIS desse registro nao respondeu de forma utilizavel (resultado $rLivre). Seguindo sem ele: achados serao marcados como DNS apenas." 'WARN'
        $cfgBusca['WhoisHost'] = ''
        $rLivre = & $TestarDominio $sentinela $cfgBusca
    }
    if ($rLivre -ne 'LIVRE' -and $rLivre -ne 'LIVRE_DNS') {
        Write-Log "Autoteste falhou: um dominio inexistente retornou '$rLivre'. Verifique a rede, o TLD e o servidor." 'ERROR'
        Wait-Fechar -SemInteracao:$SemInteracao
        return
    }
    foreach ($nome in @('arnes', 'google', 'nic', 'example', 'iana', 'a')) {
        if ((& $TestarDominio ($nome + $Script:sufixo) $cfgBusca) -eq 'REGISTRADO') { $Script:canario = $nome + $Script:sufixo; break }
    }
    if ($Script:canario) { Write-Log "Autoteste ok: inexistente reconhecido; $($Script:canario) reconhecido como registrado (sera o controle de cada lote)" 'SUCCESS' }
    else { Write-Log 'Autoteste parcial: nao achei um dominio registrado conhecido neste TLD. O controle por lote usara so o inexistente.' 'WARN' }

    # ── 5. Ordem aleatoria sem repeticao ───────────────────────────────────
    $MulA = [System.Numerics.BigInteger]1; $AddB = [System.Numerics.BigInteger]0
    if ($null -eq $Script:dicLista -and $Espaco -gt 2) {
        $rng = [System.Random]::new()
        do { $cand = $rng.NextInt64(2, $Espaco) } while ((Get-Mdc $cand $Espaco) -ne 1)
        $MulA = [System.Numerics.BigInteger]$cand
        $AddB = [System.Numerics.BigInteger]$rng.NextInt64(0, $Espaco)
    }
    $Mod = [System.Numerics.BigInteger]$Espaco

    $Script:alvo = if ($Simular) { [math]::Min(30L, $Espaco) } elseif ($Limite -gt 0) { [math]::Min($Limite, $Espaco) } else { $Espaco }
    $lote = if ($Simular) { [int]$Script:alvo } else { [int]$TamanhoLote }

    # ── 6. Varredura ───────────────────────────────────────────────────────
    [void](Set-ManterAcordado)
    Write-Log ("Varredura de {0:N0} nomes  -  achados em tempo real" -f $Script:alvo) 'HEADER'
    if (-not $Simular) { Write-Log "Gravando em: $arqLivres" 'INFO' }
    $Script:iniciou = $true
    $tempo.Start()
    $Script:bStatus = ''
    Update-Barra

    $pos = [long]0
    while ($pos -lt $Script:alvo) {
        $n = [int][math]::Min([long]$lote, $Script:alvo - $pos)
        $validos = [System.Collections.Generic.List[string]]::new()
        for ($k = 0; $k -lt $n; $k++) {
            $idx = [long](($MulA * ($pos + $k) + $AddB) % $Mod)
            $rot = Get-Rotulo $idx
            if (Test-Sintaxe $rot) { $validos.Add($rot + $Script:sufixo) }
            else { Register-Resultado ([pscustomobject]@{ Dominio = ($rot + $Script:sufixo); Resultado = 'IGNORADO' }) }
        }

        $Script:pendLote.Clear(); $Script:viuLimite = $false
        $loteTeveLimite = $false
        if ($validos.Count -gt 0) {
            Invoke-Consulta -Dominios (Add-Canarios $validos.ToArray()) -Paralelo $Script:paralelo | ForEach-Object { Register-Resultado $_ }
        }
        if ($Script:viuLimite) { $loteTeveLimite = $true }

        $tentativa = 0
        while ($Script:pendLote.Count -gt 0 -and $tentativa -lt 3) {
            $tentativa++
            Clear-Bar
            if ($Script:viuLimite) {
                $Script:paralelo = [math]::Max(1, [int][math]::Floor($Script:paralelo / 2))
                $espera = 10 * $tentativa
                Write-Log "Limite de consultas do servidor (HTTP 429). Pausa de $espera s e ritmo reduzido para $($Script:paralelo) consultas simultaneas." 'WARN'
            } else {
                $espera = 3
            }
            Update-Barra
            Start-Sleep -Seconds $espera
            $repetir = $Script:pendLote.ToArray()
            $Script:pendLote.Clear(); $Script:viuLimite = $false
            Invoke-Consulta -Dominios (Add-Canarios $repetir) -Paralelo $Script:paralelo | ForEach-Object { Register-Resultado $_ }
            if ($Script:viuLimite) { $loteTeveLimite = $true }
        }
        foreach ($d in $Script:pendLote) {
            $Script:testados++; $Script:indeterminados++; $Script:pendentes.Add($d)
        }
        $Script:pendLote.Clear()

        # Camada 4: so confirma e mostra os achados do lote depois do controle
        Save-LivresLote

        if (-not $loteTeveLimite -and $Script:paralelo -lt $threadsMax) { $Script:paralelo++ }

        $pos += $n
        Update-Barra
    }
}
finally {
    Clear-Bar
    [void](Set-ManterAcordado -Desligar)
    if ($travaCriada) { Remove-Item -LiteralPath $arqTrava -Force -ErrorAction SilentlyContinue }

    if ($Script:iniciou) {
        if ($Script:pendentes.Count -gt 0) {
            $lista = ($Script:pendentes | Select-Object -First 30) -join ', '
            $resto = if ($Script:pendentes.Count -gt 30) { " e mais $($Script:pendentes.Count - 30)" } else { '' }
            Write-Log "Indeterminados (sem resposta confiavel, nao gravados): $lista$resto" 'SKIP'
        }
        if ($Script:listaInvalidos.Count -gt 0) {
            Write-Log "Rejeitados pelo registro como nome invalido ($($Script:listaInvalidos.Count)): $(($Script:listaInvalidos | Select-Object -First 15) -join ', ')" 'SKIP'
        }
        Show-Resumo -Itens @(
            @{ Rotulo = 'TLD';             Valor = ".$Tld ($($cfgBusca['Modo']))"; Icone = [char]0x2139; Cor = { col_info } }
            @{ Rotulo = 'Nomes testados';  Valor = ('{0:N0} de {1:N0}' -f $Script:testados, $Script:alvo); Icone = [char]0x2699; Cor = { col_info } }
            @{ Rotulo = 'Livres';          Valor = ('{0:N0}' -f $Script:achados);        Icone = [char]0x2714; Cor = { col_ok } }
            @{ Rotulo = 'Registrados';     Valor = ('{0:N0}' -f $Script:registrados);    Icone = [char]0x21B7; Cor = { col_skip } }
            @{ Rotulo = 'Nome invalido';   Valor = ('{0:N0}' -f $Script:invalidos);      Icone = [char]0x21B7; Cor = { col_skip } }
            @{ Rotulo = 'Fora da sintaxe'; Valor = ('{0:N0}' -f $Script:ignorados);      Icone = [char]0x21B7; Cor = { col_skip } }
            @{ Rotulo = 'Contradicoes';    Valor = ('{0:N0}' -f $Script:contradicoes);   Icone = [char]0x26A0; Cor = { col_warn } }
            @{ Rotulo = 'Incertos';        Valor = ('{0:N0}' -f $Script:incertos);       Icone = [char]0x26A0; Cor = { col_warn } }
            @{ Rotulo = 'Descartados';     Valor = ('{0:N0}' -f $Script:descartados);    Icone = [char]0x26A0; Cor = { col_warn } }
            @{ Rotulo = 'Indeterminados';  Valor = ('{0:N0}' -f $Script:indeterminados); Icone = [char]0x26A0; Cor = { col_warn } }
            @{ Rotulo = 'Tempo';           Valor = (Format-Tempo $tempo.Elapsed.TotalSeconds); Icone = [char]0x2139; Cor = { col_info } }
        )
        if (-not $Simular) { Write-Log "Dominios livres: $arqLivres" 'INFO' }
        Write-Log 'Confirme no registrador antes de comprar: "livre" no registro ainda pode ser nome indisponivel por regra do registrador.' 'INFO'
    }
    Write-Log "Log completo: $Global:UxLogPath" 'INFO'
    Wait-Fechar -SemInteracao:$SemInteracao
}