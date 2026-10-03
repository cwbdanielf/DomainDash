# Arquivo: DomainDash.ps1
# Host local aditivo para frontend/index.html; nunca escuta fora de 127.0.0.1.
#Requires -Version 7.6
[CmdletBinding()]
param([switch]$SemAbrirNavegador)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Root = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$script:Frontend = Join-Path $script:Root 'frontend'
$script:Scanner = Join-Path $script:Root 'cacador-dominios.ps1'
$script:OutputPath = Join-Path $script:Root 'dominios-disponiveis.txt'
$script:LogPath = Join-Path $script:Root 'cacador-dominios-log.txt'
$script:DictionaryPath = Join-Path $script:Root 'dicionarios'
$script:MaxRequestBodyBytes = 7MB
$script:MaxDictionaryBytes = 5MB
$script:Loopback = [System.Net.IPAddress]::Parse('127.0.0.1')
$script:SessionToken = [Convert]::ToHexString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()
$script:ScanProcess = $null
$script:ScanExitCode = $null
$script:ScanStartedAt = $null
$script:ScanFailure = ''
$script:HttpListener = $null
$script:BoundPort = 0

function Send-HttpResponse {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [int]$Status,
        [string]$ContentType,
        [byte[]]$Body,
        [switch]$NoStore
    )
    $reason = switch ($Status) {
        200 { 'OK' } 201 { 'Created' } 202 { 'Accepted' } 400 { 'Bad Request' } 403 { 'Forbidden' }
        404 { 'Not Found' } 405 { 'Method Not Allowed' } 409 { 'Conflict' }
        413 { 'Payload Too Large' } 415 { 'Unsupported Media Type' } 500 { 'Internal Server Error' }
        default { 'Service Unavailable' }
    }
    $cache = if ($NoStore) { 'Cache-Control: no-store, max-age=0' } else { 'Cache-Control: no-cache' }
    $header = "HTTP/1.1 $Status $reason`r`nContent-Type: $ContentType`r`nContent-Length: $($Body.Length)`r`n$cache`r`nConnection: close`r`nX-Content-Type-Options: nosniff`r`nX-Frame-Options: DENY`r`nReferrer-Policy: no-referrer`r`nContent-Security-Policy: default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'`r`n`r`n"
    $headBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headBytes, 0, $headBytes.Length)
    if ($Body.Length -gt 0) { $Stream.Write($Body, 0, $Body.Length) }
    $Stream.Flush()
}

function Send-Json {
    param([System.Net.Sockets.NetworkStream]$Stream, [int]$Status, [object]$Data)
    $json = ConvertTo-Json -InputObject $Data -Depth 8 -Compress
    $body = [System.Text.UTF8Encoding]::new($false).GetBytes($json)
    Send-HttpResponse -Stream $Stream -Status $Status -ContentType 'application/json; charset=utf-8' -Body $body -NoStore
}

function Read-HttpRequest {
    param([System.Net.Sockets.NetworkStream]$Stream)
    $Stream.ReadTimeout = 5000
    $headerBytes = [System.Collections.Generic.List[byte]]::new()
    $matched = 0
    $delimiter = [byte[]](13, 10, 13, 10)
    while ($headerBytes.Count -lt 16384 -and $matched -lt 4) {
        $value = $Stream.ReadByte()
        if ($value -lt 0) { throw 'Conexão encerrada durante a leitura do cabeçalho.' }
        $b = [byte]$value
        $headerBytes.Add($b)
        if ($b -eq $delimiter[$matched]) { $matched++ }
        elseif ($b -eq $delimiter[0]) { $matched = 1 }
        else { $matched = 0 }
    }
    if ($matched -ne 4) { throw 'Cabeçalho HTTP incompleto ou muito longo.' }
    $headerText = [System.Text.Encoding]::ASCII.GetString($headerBytes.ToArray())
    $lines = $headerText -split "`r`n"
    $requestParts = $lines[0] -split ' ', 3
    if ($requestParts.Count -ne 3) { throw 'Linha inicial HTTP inválida.' }
    $headers = @{}
    foreach ($line in $lines | Select-Object -Skip 1) {
        if (-not $line) { break }
        $separator = $line.IndexOf(':')
        if ($separator -le 0) { throw 'Cabeçalho HTTP inválido.' }
        $name = $line.Substring(0, $separator).Trim().ToLowerInvariant()
        $value = $line.Substring($separator + 1).Trim()
        if ($headers.ContainsKey($name)) { throw 'Cabeçalho HTTP repetido.' }
        $headers[$name] = $value
    }
    $length = 0
    if ($headers.ContainsKey('content-length') -and -not [int]::TryParse($headers['content-length'], [ref]$length)) { throw 'Tamanho do corpo inválido.' }
    if ($length -lt 0) { throw 'Tamanho do corpo inválido.' }
    $requestPath = ($requestParts[1] -split '\?', 2)[0]
    $maxBodyLength = if ($requestPath -ceq '/api/dictionaries') { $script:MaxRequestBodyBytes } else { 16384 }
    if ($length -gt $maxBodyLength) { throw [System.IO.InvalidDataException]::new('Corpo HTTP excede o limite.') }
    if ($headers.ContainsKey('transfer-encoding')) { throw 'Transfer-Encoding não permitido.' }
    $bodyBytes = [byte[]]::new($length)
    $read = 0
    while ($read -lt $length) {
        $count = $Stream.Read($bodyBytes, $read, $length - $read)
        if ($count -le 0) { throw 'Conexão encerrada durante a leitura do corpo.' }
        $read += $count
    }
    return [pscustomobject]@{
        Method = $requestParts[0].ToUpperInvariant()
        Target = $requestParts[1]
        Version = $requestParts[2]
        Headers = $headers
        Body = [System.Text.UTF8Encoding]::new($false, $true).GetString($bodyBytes)
    }
}

function Get-ScanStatus {
    $scanning = $false
    if ($null -ne $script:ScanProcess) {
        try {
            if (-not $script:ScanProcess.HasExited) { $scanning = $true }
            else {
                $script:ScanExitCode = $script:ScanProcess.ExitCode
                if ($script:ScanExitCode -ne 0 -and -not $script:ScanFailure) { $script:ScanFailure = "O scanner encerrou com código $($script:ScanExitCode). Consulte o log da execução." }
            }
        } catch { $script:ScanFailure = 'Não foi possível consultar o processo de busca.' }
    }
    $lastRun = $null
    if ($null -ne $script:ScanStartedAt) {
        $lastRun = @{ startedAt = $script:ScanStartedAt; exitCode = $script:ScanExitCode }
        if (-not $scanning -and -not $script:ScanFailure -and $script:ScanStartedAt -and (Test-Path -LiteralPath $script:LogPath -PathType Leaf)) {
            $tail = Get-Content -LiteralPath $script:LogPath -Tail 30 -ErrorAction SilentlyContinue
            $failureLine = @($tail | Where-Object { $_ -match '\[ERROR\]' } | Select-Object -Last 1)
            if ($failureLine.Count -gt 0) { $script:ScanFailure = 'O scanner registrou um erro. Consulte o log da execução.' }
        }
        if ($script:ScanFailure) { $lastRun.exitCode = 1 }
    }
    return @{
        available = $true
        scanning = $scanning
        processId = if ($scanning) { $script:ScanProcess.Id } else { $null }
        lastRun = $lastRun
        message = $script:ScanFailure
    }
}

function Get-CurrentResults {
    $domains = [System.Collections.Generic.List[string]]::new()
    $total = 0L
    $displayLimit = 500
    if (Test-Path -LiteralPath $script:OutputPath -PathType Leaf) {
        foreach ($line in [System.IO.File]::ReadLines($script:OutputPath)) {
            $value = $line.Trim()
            if (-not $value) { continue }
            $total++
            if ($domains.Count -lt $displayLimit) { $domains.Add($value) }
        }
    }
    return @{ domains = $domains.ToArray(); total = $total; truncated = ($total -gt $domains.Count); scanning = (Get-ScanStatus).scanning }
}

function Get-CurrentLog {
    $text = ''
    if (Test-Path -LiteralPath $script:LogPath -PathType Leaf) {
        $file = Get-Item -LiteralPath $script:LogPath
        if ($file.Length -gt 1048576) {
            $all = [System.IO.File]::ReadAllLines($script:LogPath, [System.Text.Encoding]::UTF8)
            $text = ($all | Select-Object -Last 2500) -join "`n"
        } else {
            $text = [System.IO.File]::ReadAllText($script:LogPath, [System.Text.Encoding]::UTF8)
        }
    }
    return @{ text = $text; scanning = (Get-ScanStatus).scanning }
}

function Get-Dictionaries {
    $items = @()
    if (Test-Path -LiteralPath $script:DictionaryPath -PathType Container) {
        $items = @(Get-ChildItem -LiteralPath $script:DictionaryPath -Filter '*.txt' -File | Sort-Object Name | ForEach-Object { $_.Name })
    }
    return @{ dictionaries = $items }
}

function Save-DictionaryUpload {
    param([string]$JsonBody)
    try { $payload = ConvertFrom-Json -InputObject $JsonBody -AsHashtable -ErrorAction Stop }
    catch { return @{ Status = 400; Data = @{ error = 'Os dados do arquivo não são um JSON válido.' } } }
    if ($payload -isnot [System.Collections.IDictionary] -or @($payload.Keys | Where-Object { $_ -notin @('Name', 'ContentBase64') }).Count -gt 0) {
        return @{ Status = 400; Data = @{ error = 'Os dados do arquivo estão inválidos.' } }
    }
    $name = [string]$payload.Name
    $encoded = [string]$payload.ContentBase64
    if ($name.Length -lt 5 -or $name.Length -gt 128 -or $name -notmatch '^[\p{L}\p{N}][\p{L}\p{N} _().-]{0,123}\.txt$') {
        return @{ Status = 400; Data = @{ error = 'Use um nome simples de arquivo terminado em .txt.' } }
    }
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($name)
    if ($baseName.EndsWith(' ') -or $baseName.EndsWith('.') -or $baseName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
        return @{ Status = 400; Data = @{ error = 'Esse nome de arquivo é reservado pelo Windows.' } }
    }
    if (-not $encoded -or $encoded.Length -gt [int][math]::Ceiling($script:MaxDictionaryBytes / 3.0 * 4.0) + 4) {
        return @{ Status = 413; Data = @{ error = 'O dicionário está vazio ou excede o limite de 5 MiB.' } }
    }
    try { $bytes = [Convert]::FromBase64String($encoded) }
    catch { return @{ Status = 400; Data = @{ error = 'O conteúdo do dicionário está inválido.' } } }
    if ($bytes.Length -eq 0 -or $bytes.Length -gt $script:MaxDictionaryBytes) {
        return @{ Status = 413; Data = @{ error = 'O dicionário deve ter conteúdo e não pode exceder 5 MiB.' } }
    }
    try { $null = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes) }
    catch { return @{ Status = 400; Data = @{ error = 'O arquivo deve estar codificado em UTF-8.' } } }

    $temporary = $null
    try {
        [void](New-Item -ItemType Directory -Path $script:DictionaryPath -Force)
        $destination = Join-Path $script:DictionaryPath $name
        $temporary = Join-Path $script:DictionaryPath ('.upload-' + [guid]::NewGuid().ToString('N') + '.tmp')
        [System.IO.File]::WriteAllBytes($temporary, $bytes)
        [System.IO.File]::Move($temporary, $destination, $false)
        return @{ Status = 201; Data = @{ name = $name; message = 'Dicionário adicionado.' } }
    } catch [System.IO.IOException] {
        if (Test-Path -LiteralPath (Join-Path $script:DictionaryPath $name) -PathType Leaf) {
            return @{ Status = 409; Data = @{ error = 'Já existe um dicionário com esse nome. Escolha outro nome.' } }
        }
        return @{ Status = 500; Data = @{ error = 'Não foi possível salvar o dicionário na pasta do aplicativo.' } }
    } catch {
        return @{ Status = 500; Data = @{ error = 'Não foi possível salvar o dicionário na pasta do aplicativo.' } }
    } finally {
        if ($temporary -and (Test-Path -LiteralPath $temporary -PathType Leaf)) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function Start-RealScan {
    param([string]$JsonBody)
    if ($null -ne $script:ScanProcess) {
        try { if (-not $script:ScanProcess.HasExited) { return @{ Status = 409; Data = @{ error = 'Uma varredura já está em andamento.' } } } }
        catch { }
    }
    try { $configuration = ConvertFrom-Json -InputObject $JsonBody -AsHashtable -ErrorAction Stop }
    catch { return @{ Status = 400; Data = @{ error = 'A configuração enviada não é um JSON válido.' } } }
    if ($configuration -isnot [System.Collections.IDictionary]) { return @{ Status = 400; Data = @{ error = 'A configuração da busca está inválida.' } } }
    $allowed = @('Tld', 'Busca', 'Caracteres', 'Alfabeto', 'Padrao', 'Dicionario', 'Excluir', 'Limite')
    foreach ($key in $configuration.Keys) {
        if ($key -notin $allowed) { return @{ Status = 400; Data = @{ error = "Campo não permitido: $key" } } }
    }
    foreach ($required in @('Tld', 'Busca', 'Excluir', 'Limite')) {
        if (-not $configuration.Contains($required)) { return @{ Status = 400; Data = @{ error = "Campo obrigatório ausente: $required" } } }
    }
    $tld = [string]$configuration.Tld
    if ($tld.Length -gt 63 -or $tld -cnotmatch '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$') { return @{ Status = 400; Data = @{ error = 'A extensão informada é inválida.' } } }
    $mode = [string]$configuration.Busca
    if ($mode -notin @('Combinacoes', 'Padrao', 'Dicionario')) { return @{ Status = 400; Data = @{ error = 'O tipo de busca informado é inválido.' } } }
    $exclude = [string]$configuration.Excluir
    if ($exclude.Length -gt 36) { return @{ Status = 400; Data = @{ error = 'A lista de caracteres a excluir é muito longa.' } } }
    $limitValue = 0L
    if (-not [long]::TryParse([string]$configuration.Limite, [ref]$limitValue) -or $limitValue -lt 0 -or $limitValue -gt 2000000000) { return @{ Status = 400; Data = @{ error = 'O limite da busca é inválido.' } } }
    $excluded = [regex]::Replace($exclude.ToLowerInvariant(), '[^a-z0-9]', '')
    if ($mode -eq 'Combinacoes') {
        $length = 0
        if (-not $configuration.Contains('Caracteres') -or -not [int]::TryParse([string]$configuration.Caracteres, [ref]$length) -or $length -lt 1 -or $length -gt 12) { return @{ Status = 400; Data = @{ error = 'O tamanho deve ser um número entre 1 e 12.' } } }
        $alphabet = [string]$configuration.Alfabeto
        if ($alphabet -notin @('Letras', 'LetrasNumeros', 'Consoantes', 'Vogais', 'Numeros')) { return @{ Status = 400; Data = @{ error = 'O alfabeto selecionado é inválido.' } } }
        $symbols = switch ($alphabet) {
            'Letras' { 'abcdefghijklmnopqrstuvwxyz' }
            'LetrasNumeros' { 'abcdefghijklmnopqrstuvwxyz0123456789' }
            'Consoantes' { 'bcdfghjklmnpqrstvwxyz' }
            'Vogais' { 'aeiou' }
            'Numeros' { '0123456789' }
        }
        $usable = -join @($symbols.ToCharArray() | Where-Object { -not $excluded.Contains($_) })
        if (-not $usable) { return @{ Status = 400; Data = @{ error = 'Os caracteres excluídos removem todas as opções do alfabeto selecionado.' } } }
    }
    if ($mode -eq 'Padrao') {
        $pattern = [string]$configuration.Padrao
        if ($pattern.Length -lt 1 -or $pattern.Length -gt 63 -or $pattern -cnotmatch '^[0XCVAa-z1-9-]+$' -or $pattern.StartsWith('-') -or $pattern.EndsWith('-')) { return @{ Status = 400; Data = @{ error = 'O padrão informado contém caracteres inválidos.' } } }
        foreach ($character in $pattern.ToCharArray()) {
            $symbols = switch -CaseSensitive ([string]$character) {
                'X' { 'abcdefghijklmnopqrstuvwxyz' }
                'C' { 'bcdfghjklmnpqrstvwxyz' }
                'V' { 'aeiou' }
                'A' { 'abcdefghijklmnopqrstuvwxyz0123456789' }
                '0' { '0123456789' }
                default { '' }
            }
            if ($symbols) {
                $usable = -join @($symbols.ToCharArray() | Where-Object { -not $excluded.Contains($_) })
                if (-not $usable) { return @{ Status = 400; Data = @{ error = "Os caracteres excluídos removem todas as opções de '$character'." } } }
            } elseif ($character -ne '-' -and $excluded.Contains($character)) {
                return @{ Status = 400; Data = @{ error = "O caractere fixo '$character' foi excluído." } }
            }
        }
    }
    if ($mode -eq 'Dicionario') {
        $dictionary = [string]$configuration.Dicionario
        $known = @(Get-Dictionaries).dictionaries
        if (-not $dictionary -or $dictionary -notin $known) { return @{ Status = 400; Data = @{ error = 'Selecione um arquivo .txt existente na pasta de dicionários.' } } }
    }

    if ($mode -eq 'Combinacoes') { $alphabet = [string]$configuration.Alfabeto }
    if ($mode -eq 'Padrao') { $pattern = [string]$configuration.Padrao }
    if ($mode -eq 'Dicionario') { $dictionary = [string]$configuration.Dicionario }

    $pwsh = Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $pwsh) { return @{ Status = 500; Data = @{ error = 'PowerShell 7.6 ou superior não foi encontrado.' } } }
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $pwsh.Source
    $start.WorkingDirectory = $script:Root
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $false
    $start.RedirectStandardError = $false
    $start.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $start.Environment['POWERSHELL_TELEMETRY_OPTOUT'] = '1'
    $start.Environment['NO_COLOR'] = '1'
    $start.ArgumentList.Add('-NoLogo') | Out-Null
    $start.ArgumentList.Add('-NoProfile') | Out-Null
    $start.ArgumentList.Add('-NonInteractive') | Out-Null
    $start.ArgumentList.Add('-File') | Out-Null
    $start.ArgumentList.Add($script:Scanner) | Out-Null
    $start.ArgumentList.Add('-Pasta') | Out-Null
    $start.ArgumentList.Add($script:Root) | Out-Null
    $start.ArgumentList.Add('-SemInteracao') | Out-Null
    $start.ArgumentList.Add('-Tld') | Out-Null
    $start.ArgumentList.Add($tld) | Out-Null
    $start.ArgumentList.Add('-Busca') | Out-Null
    $start.ArgumentList.Add($mode) | Out-Null
    $start.ArgumentList.Add('-Excluir') | Out-Null
    $start.ArgumentList.Add($exclude) | Out-Null
    $start.ArgumentList.Add('-Limite') | Out-Null
    $start.ArgumentList.Add([string]$limitValue) | Out-Null
    if ($mode -eq 'Combinacoes') {
        $start.ArgumentList.Add('-Caracteres') | Out-Null
        $start.ArgumentList.Add([string]$length) | Out-Null
        $start.ArgumentList.Add('-Alfabeto') | Out-Null
        $start.ArgumentList.Add([string]$configuration.Alfabeto) | Out-Null
    } elseif ($mode -eq 'Padrao') {
        $start.ArgumentList.Add('-Padrao') | Out-Null
        $start.ArgumentList.Add($pattern) | Out-Null
    } else {
        $start.ArgumentList.Add('-Dicionario') | Out-Null
        $start.ArgumentList.Add($dictionary) | Out-Null
    }
    try {
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $start
        $script:ScanStartedAt = (Get-Date).ToString('o')
        $script:ScanExitCode = $null
        $script:ScanFailure = ''
        if (-not $process.Start()) { throw 'O scanner não foi iniciado.' }
        $null = $process.EnableRaisingEvents
        Register-ObjectEvent -InputObject $process -EventName Exited -Action {
            try {
                $script:ScanExitCode = $Event.Sender.ExitCode
                if ($script:ScanExitCode -ne 0) { $script:ScanFailure = "O scanner encerrou com código $($script:ScanExitCode). Consulte o log da execução." }
            } catch { $script:ScanFailure = 'O scanner encerrou; consulte o log da execução.' }
        } | Out-Null
        $script:ScanProcess = $process
        if ($process.HasExited) {
            $script:ScanExitCode = $process.ExitCode
            if ($script:ScanExitCode -ne 0) { $script:ScanFailure = "O scanner encerrou com código $($script:ScanExitCode). Consulte o log da execução." }
        }
        return @{ Status = 202; Data = @{ started = $true; processId = $process.Id; message = 'Varredura iniciada pelo scanner original.' } }
    } catch {
        $script:ScanFailure = $_.Exception.Message
        return @{ Status = 500; Data = @{ error = 'Não foi possível iniciar o scanner de domínios.' } }
    }
}

function Get-AssetResponse {
    param([string]$Path)
    $assets = @{
        '/' = @{ File = 'index.html'; Type = 'text/html; charset=utf-8' }
        '/index.html' = @{ File = 'index.html'; Type = 'text/html; charset=utf-8' }
        '/assets/css/tokens.css' = @{ File = 'assets/css/tokens.css'; Type = 'text/css; charset=utf-8' }
        '/assets/css/glass.css' = @{ File = 'assets/css/glass.css'; Type = 'text/css; charset=utf-8' }
        '/assets/css/componentes.css' = @{ File = 'assets/css/componentes.css'; Type = 'text/css; charset=utf-8' }
        '/assets/css/telas.css' = @{ File = 'assets/css/telas.css'; Type = 'text/css; charset=utf-8' }
        '/assets/js/api.js' = @{ File = 'assets/js/api.js'; Type = 'text/javascript; charset=utf-8' }
        '/assets/js/ui.js' = @{ File = 'assets/js/ui.js'; Type = 'text/javascript; charset=utf-8' }
        '/assets/js/app.js' = @{ File = 'assets/js/app.js'; Type = 'text/javascript; charset=utf-8' }
        '/assets/js/tela_busca.js' = @{ File = 'assets/js/tela_busca.js'; Type = 'text/javascript; charset=utf-8' }
        '/assets/js/tela_resultados.js' = @{ File = 'assets/js/tela_resultados.js'; Type = 'text/javascript; charset=utf-8' }
        '/assets/js/tela_log.js' = @{ File = 'assets/js/tela_log.js'; Type = 'text/javascript; charset=utf-8' }
        '/assets/icons/icones.svg' = @{ File = 'assets/icons/icones.svg'; Type = 'image/svg+xml; charset=utf-8' }
        '/assets/fonts/inter_variavel.woff2' = @{ File = 'assets/fonts/inter_variavel.woff2'; Type = 'font/woff2' }
    }
    if (-not $assets.ContainsKey($Path)) { return $null }
    $asset = $assets[$Path]
    $file = Join-Path $script:Frontend $asset.File
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes($file)
    if ($Path -in @('/', '/index.html')) {
        $html = [System.Text.Encoding]::UTF8.GetString($bytes).Replace('__APP_TOKEN__', $script:SessionToken)
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($html)
    }
    return @{ Type = $asset.Type; Bytes = $bytes }
}

function Process-Client {
    param([System.Net.Sockets.TcpClient]$Client)
    $stream = $Client.GetStream()
    try {
        $request = Read-HttpRequest $stream
        $remote = $Client.Client.RemoteEndPoint.Address
        $expectedHost = "127.0.0.1:$script:BoundPort"
        if (-not $remote.Equals($script:Loopback) -or -not $request.Headers.ContainsKey('host') -or $request.Headers['host'] -cne $expectedHost) {
            Send-Json $stream 403 @{ error = 'Acesso permitido somente por 127.0.0.1.' }
            return
        }
        $path = ($request.Target -split '\?', 2)[0]
        if ($path -eq '/api/scan' -or ($path -eq '/api/dictionaries' -and $request.Method -eq 'POST')) {
            if ($request.Method -ne 'POST') { Send-Json $stream 405 @{ error = 'Método não permitido.' }; return }
            $expectedOrigin = "http://127.0.0.1:$script:BoundPort"
            if (-not $request.Headers.ContainsKey('origin') -or $request.Headers['origin'] -cne $expectedOrigin -or -not $request.Headers.ContainsKey('x-app-token') -or $request.Headers['x-app-token'] -cne $script:SessionToken) {
                Send-Json $stream 403 @{ error = 'A confirmação de origem local não foi validada.' }
                return
            }
            if (-not $request.Headers.ContainsKey('content-type') -or $request.Headers['content-type'] -notlike 'application/json*') { Send-Json $stream 415 @{ error = 'O formato enviado deve ser JSON.' }; return }
            if ($path -ceq '/api/dictionaries') {
                $result = Save-DictionaryUpload $request.Body
                Send-Json $stream $result.Status $result.Data
                return
            }
            $result = Start-RealScan $request.Body
            Send-Json $stream $result.Status $result.Data
            return
        }
        if ($path.StartsWith('/api/')) {
            if ($request.Method -ne 'GET') { Send-Json $stream 405 @{ error = 'Método não permitido.' }; return }
            switch -CaseSensitive ($path) {
                '/api/status' { Send-Json $stream 200 (Get-ScanStatus); return }
                '/api/results' { Send-Json $stream 200 (Get-CurrentResults); return }
                '/api/log' { Send-Json $stream 200 (Get-CurrentLog); return }
                '/api/dictionaries' { Send-Json $stream 200 (Get-Dictionaries); return }
                default { Send-Json $stream 404 @{ error = 'Rota local não encontrada.' }; return }
            }
        }
        if ($request.Method -ne 'GET') { Send-Json $stream 405 @{ error = 'Método não permitido.' }; return }
        $asset = Get-AssetResponse $path
        if ($null -eq $asset) { Send-Json $stream 404 @{ error = 'Arquivo local não encontrado.' }; return }
        Send-HttpResponse -Stream $stream -Status 200 -ContentType $asset.Type -Body $asset.Bytes -NoStore
    } catch [System.IO.InvalidDataException] {
        try { Send-Json $stream 413 @{ error = 'O arquivo enviado excede o limite permitido.' } } catch { }
    } catch {
        try { Send-Json $stream 400 @{ error = 'A solicitação local não pôde ser interpretada.' } } catch { }
    } finally {
        $stream.Dispose()
        $Client.Dispose()
    }
}

function New-LoopbackListener {
    $random = [System.Security.Cryptography.RandomNumberGenerator]::GetInt32(49152, 65536)
    for ($attempt = 0; $attempt -lt 96; $attempt++) {
        $port = 49152 + (($random - 49152 + ($attempt * 137)) % 16384)
        $listener = [System.Net.Sockets.TcpListener]::new($script:Loopback, $port)
        try {
            $listener.Server.ExclusiveAddressUse = $true
            $listener.Server.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::ReuseAddress, $false)
            $listener.Start(32)
            $script:BoundPort = $port
            return $listener
        } catch [System.Net.Sockets.SocketException] {
            $listener.Stop()
            continue
        } catch {
            $listener.Stop()
            throw
        }
    }
    throw 'Não foi possível reservar uma porta IPv4 livre após 96 tentativas. O servidor não foi iniciado.'
}

if (-not (Test-Path -LiteralPath $script:Scanner -PathType Leaf)) { throw "Scanner original não encontrado: $script:Scanner" }
if (-not (Test-Path -LiteralPath $script:Frontend -PathType Container)) { throw "Pasta da interface não encontrada: $script:Frontend" }

try {
    $script:HttpListener = New-LoopbackListener
    $url = "http://127.0.0.1:$script:BoundPort/"
    Write-Host "DomainDash disponível em $url" -ForegroundColor Cyan
    Write-Host 'Acesso limitado a este computador. Feche esta janela para encerrar o servidor local.' -ForegroundColor DarkGray
    if (-not $SemAbrirNavegador) {
        $chromePaths = @(
            (Join-Path ${env:ProgramFiles} 'Google\Chrome\Application\chrome.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
            (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
        $chromeCommand = Get-Command -Name 'chrome.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        $chrome = if ($chromeCommand) { $chromeCommand.Source } else { $chromePaths | Select-Object -First 1 }
        if ($chrome) { Start-Process -FilePath $chrome -ArgumentList @($url) }
        else { Write-Warning 'O Chrome não foi encontrado. Abra manualmente a URL local exibida acima.' }
    }
    while ($script:HttpListener.Server.IsBound) {
        $client = $script:HttpListener.AcceptTcpClient()
        Process-Client $client
    }
} finally {
    if ($null -ne $script:HttpListener) { $script:HttpListener.Stop() }
    if ($null -ne $script:ScanProcess) {
        try {
            if (-not $script:ScanProcess.HasExited) { Write-Warning 'O servidor local foi fechado; a busca já iniciada continua no scanner original.' }
        } catch { }
    }
}
