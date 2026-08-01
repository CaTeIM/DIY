# diag-proxy-corporativo.ps1
#
# Diagnostica COMO uma rede corporativa bloqueia um servico, separando as quatro
# camadas onde o bloqueio pode acontecer: DNS, TCP, TLS e proxy HTTP.
#
# Uso (nao precisa de admin):
#   pwsh -ExecutionPolicy Bypass -File .\diag-proxy-corporativo.ps1 > diag.txt 2>&1
#
# Testando o seu proprio team domain do Cloudflare Zero Trust:
#   pwsh -File .\diag-proxy-corporativo.ps1 -Alvos 'SEU-TIME.cloudflareaccess.com','cloudflare.com'
#
# Guia: ../../docs/cloudflare-browser-rdp.md
#
# Nao altera nada no sistema: so consulta DNS, abre TCP e le certificado TLS.

param(
    # Dominios que voce suspeita estarem bloqueados.
    [string[]] $Alvos = @('cloudflare.com'),

    # Dominios de referencia, que devem passar em qualquer rede corporativa.
    # Sem eles nao da para distinguir "bloqueio dirigido" de "rede ruim".
    [string[]] $Controles = @('github.com', 'example.com')
)

$ErrorActionPreference = 'SilentlyContinue'

# Nome diferente de $Alvos de proposito: variaveis do PowerShell sao
# case-insensitive, entao usar $alvos aqui sobrescreveria o parametro.
$listaAlvos = @()
foreach ($a in $Alvos)     { $listaAlvos += @{ Rotulo = "ALVO $a";     Nome = $a } }
foreach ($c in $Controles) { $listaAlvos += @{ Rotulo = "CONTROLE $c"; Nome = $c } }

function Format-Ips ($ips) {
    if ($ips.Count -eq 0) { return 'SEM-A-RECORD' }
    if ($ips.Count -le 2) { return ($ips -join ',') }
    return (($ips[0..1]) -join ',') + " (+$($ips.Count - 2))"
}

function Get-DnsLocal ($n) {
    $r = Resolve-DnsName -Name $n -Type A -ErrorAction SilentlyContinue
    if (-not $r) { return 'SEM-RESPOSTA' }
    return (Format-Ips @($r | Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress }))
}

function Get-DnsPublico ($n) {
    $r = Resolve-DnsName -Name $n -Type A -Server '1.1.1.1' -ErrorAction SilentlyContinue
    if (-not $r) { return 'BLOQUEADO/TIMEOUT' }
    return (Format-Ips @($r | Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress }))
}

function Get-DnsDoH ($n) {
    try {
        $u = "https://cloudflare-dns.com/dns-query?name=$n&type=A"
        $resp = Invoke-RestMethod -Uri $u -Headers @{ accept = 'application/dns-json' } -TimeoutSec 10 -ErrorAction Stop
        if (-not $resp.Answer) { return 'SEM-A-RECORD' }
        return (Format-Ips @($resp.Answer | Where-Object { $_.type -eq 1 } | ForEach-Object { $_.data }))
    } catch { return 'FALHA-DoH' }
}

function Test-Tcp443 ($n) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $ok = $c.ConnectAsync($n, 443).Wait(6000)
        $c.Close()
        if ($ok) { return 'OK' } else { return 'TIMEOUT' }
    } catch { return 'ERRO' }
}

function Get-TlsCert ($n) {
    $c = $null; $ssl = $null
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        if (-not $c.ConnectAsync($n, 443).Wait(6000)) { return @{ Status = 'TCP-TIMEOUT'; Emissor = '' } }
        $cb = [System.Net.Security.RemoteCertificateValidationCallback] { param($a, $b, $c, $d) return $true }
        $ssl = New-Object System.Net.Security.SslStream($c.GetStream(), $false, $cb)
        $ssl.AuthenticateAsClient($n)
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($ssl.RemoteCertificate)
        return @{ Status = 'TLS-OK'; Emissor = $cert.Issuer }
    } catch {
        return @{ Status = 'TLS-FALHOU'; Emissor = $_.Exception.Message }
    } finally {
        if ($ssl) { $ssl.Dispose() }
        if ($c) { $c.Close() }
    }
}

Write-Output "==================== AMBIENTE ===================="
Write-Output ("PowerShell : " + $PSVersionTable.PSVersion)
Write-Output ("Maquina    : " + $env:COMPUTERNAME)
Write-Output ""
Write-Output "Servidores DNS configurados:"
Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses } |
    ForEach-Object { "  {0}: {1}" -f $_.InterfaceAlias, ($_.ServerAddresses -join ', ') }
Write-Output ""
Write-Output "Proxy do sistema:"
$wi = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
Write-Output ("  WinINET ProxyEnable : " + $wi.ProxyEnable)
Write-Output ("  WinINET ProxyServer : " + $wi.ProxyServer)
Write-Output ("  WinINET AutoConfig  : " + $wi.AutoConfigURL)

Write-Output ""
Write-Output "==================== RESOLUCAO DNS ===================="
Write-Output "(local = DNS da rede | publico = 1.1.1.1 via UDP53 | DoH = via HTTPS)"
Write-Output ""
$linhas = @()
foreach ($a in $listaAlvos) {
    $linhas += [PSCustomObject]@{
        Alvo    = $a.Rotulo
        Local   = (Get-DnsLocal $a.Nome)
        Publico = (Get-DnsPublico $a.Nome)
        DoH     = (Get-DnsDoH $a.Nome)
    }
}
$linhas | Format-Table -AutoSize | Out-String -Width 200

Write-Output "==================== TCP 443 + TLS ===================="
$resultados = @()
foreach ($a in $listaAlvos) {
    $tcp = Test-Tcp443 $a.Nome
    $tls = Get-TlsCert $a.Nome
    $resultados += [PSCustomObject]@{ Alvo = $a.Rotulo; Tcp = $tcp; Tls = $tls.Status; Emissor = $tls.Emissor }
    Write-Output ("{0,-22} TCP443={1,-8} {2}" -f $a.Rotulo, $tcp, $tls.Status)
    if ($tls.Emissor) { Write-Output ("                       emissor: " + $tls.Emissor) }
}

Write-Output ""
Write-Output "==================== HTTP ===================="
foreach ($a in $listaAlvos) {
    try {
        $r = Invoke-WebRequest -Uri ("https://" + $a.Nome) -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        Write-Output ("{0,-22} HTTP {1}" -f $a.Rotulo, $r.StatusCode)
    } catch {
        $m = $_.Exception.Message
        if ($m.Length -gt 110) { $m = $m.Substring(0, 110) }
        Write-Output ("{0,-22} {1}" -f $a.Rotulo, $m)
    }
}

Write-Output ""
Write-Output "==================== VEREDITO ===================="

# Nomes distintos dos parametros: $Controles e tipado [string[]], entao reusar
# esse nome converteria os PSCustomObject em string e zeraria a propriedade .Tcp.
$listaReais     = @($resultados  | Where-Object { $_.Alvo -like 'ALVO*' })
$listaControles = @($resultados  | Where-Object { $_.Alvo -like 'CONTROLE*' })
$alvoOk         = @($listaReais     | Where-Object { $_.Tcp -eq 'OK' })
$ctrlOk         = @($listaControles | Where-Object { $_.Tcp -eq 'OK' })

if ($ctrlOk.Count -lt $listaControles.Count) {
    Write-Output "[!] Ate os dominios de CONTROLE falharam. Ha restricao ampla de internet"
    Write-Output "    (ou proxy autenticado obrigatorio). Verifique o proxy acima; um HTTP 407"
    Write-Output "    em tudo indica que falta autenticar no proxy, nao bloqueio de categoria."
}
elseif ($alvoOk.Count -eq 0) {
    Write-Output "[X] BLOQUEIO DIRIGIDO AO ALVO."
    Write-Output "    Os dominios de controle passam e nenhum alvo conecta."
}
elseif ($alvoOk.Count -lt $listaReais.Count) {
    Write-Output "[~] BLOQUEIO PARCIAL:"
    foreach ($r in $listaReais) { Write-Output ("      {0,-22} {1}" -f $r.Alvo, $r.Tcp) }
}
else {
    Write-Output "[OK] Nenhum bloqueio de rede detectado nos alvos."
}

# DNS sinkhole: resolvedor local devolve vazio/falso enquanto o DoH devolve o real
$divergentes = @($linhas | Where-Object {
    $_.Alvo -like 'ALVO*' -and $_.DoH -notmatch 'FALHA|SEM-' -and
    $_.Local -ne $_.DoH -and $_.Local -match 'SEM-|^0\.0\.0\.0|^127\.'
})
if ($divergentes.Count -gt 0) {
    Write-Output ""
    Write-Output "[!] DNS MANIPULADO: o resolvedor local devolve resposta vazia ou endereco"
    Write-Output "    falso, enquanto o DoH devolve o real. Isso e sinkhole de DNS por dominio."
}

# Inspecao TLS: emissor que nao e CA publica conhecida
$casPublicas = 'Let''s Encrypt|DigiCert|Amazon|Google Trust|Sectigo|GlobalSign|Entrust|GoDaddy|Microsoft|ISRG|Cloudflare|Baltimore|USERTrust'
$mitm = @($resultados | Where-Object { $_.Tls -eq 'TLS-OK' -and $_.Emissor -and $_.Emissor -notmatch $casPublicas })
if ($mitm.Count -gt 0) {
    Write-Output ""
    Write-Output "[!] INSPECAO TLS (MITM): certificado emitido por CA nao publica:"
    foreach ($m in $mitm) { Write-Output ("      {0,-22} {1}" -f $m.Alvo, $m.Emissor) }
}

Write-Output ""
Write-Output "==================== FIM ===================="
