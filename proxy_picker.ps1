# Proxy lists
$HttpList   = "https://github.com/TheSpeedX/PROXY-List/raw/refs/heads/master/http.txt"
$Socks4List = "https://github.com/TheSpeedX/PROXY-List/raw/refs/heads/master/socks4.txt"
$Socks5List = "https://github.com/TheSpeedX/PROXY-List/raw/refs/heads/master/socks5.txt"

$TimeoutSeconds = 3
$SampleSize = 500
$MaxRounds = 3
$TestUrl = "http://example.com"

# -------------------------
# Download and clean list
function Download-List($url) {
    try {
        (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15).Content `
            -split "`n" | ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match "^\d+\.\d+\.\d+\.\d+:\d+$" } | Get-Unique
    } catch {
        Write-Host "[-] Failed to download: $url"
        return @()
    }
}

# -------------------------
# Test HTTP proxy
function Test-HttpProxy($proxy) {
    try {
        $webProxy = New-Object System.Net.WebProxy("http://$proxy")
        $handler  = New-Object System.Net.Http.HttpClientHandler
        $handler.Proxy = $webProxy
        $handler.UseProxy = $true

        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)

        $resp = $client.GetAsync($TestUrl).Result
        if ($resp.StatusCode -eq 200) { return $proxy }
    } catch {}
    return $null
}

# -------------------------
# Test SOCKS proxy (TCP connect)
function Test-SocksProxy($proxy) {
    try {
        $parts = $proxy.Split(":")
        $tcp = New-Object System.Net.Sockets.TcpClient
        $res = $tcp.BeginConnect($parts[0], [int]$parts[1], $null, $null)
        $ok = $res.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000, $false)
        $tcp.Close()
        if ($ok) { return $proxy }
    } catch {}
    return $null
}

# -------------------------
# Find an open proxy (any type)
function Find-OpenProxy($list, $type) {
    for ($round = 1; $round -le $MaxRounds; $round++) {
        Write-Host "[*] $type round $round/$MaxRounds — sampling $SampleSize proxies..."
        $sample = $list | Get-Random -Count ([Math]::Min($SampleSize, $list.Count))
        
        foreach ($p in $sample) {
            if ($type -eq "HTTP") { $res = Test-HttpProxy $p } else { $res = Test-SocksProxy $p }
            if ($res) { return $res } # stop immediately once an open proxy is found
        }
    }
    return $null
}

# -------------------------
# Main

Write-Host "`n[+] Downloading proxy lists..."
$httpProxies   = Download-List $HttpList
$socks4Proxies = Download-List $Socks4List
$socks5Proxies = Download-List $Socks5List

Write-Host "[+] HTTP proxies   : $($httpProxies.Count)"
Write-Host "[+] SOCKS4 proxies : $($socks4Proxies.Count)"
Write-Host "[+] SOCKS5 proxies : $($socks5Proxies.Count)`n"

$httpResult   = Find-OpenProxy $httpProxies   "HTTP"
$socks4Result = Find-OpenProxy $socks4Proxies "SOCKS4"
$socks5Result = Find-OpenProxy $socks5Proxies "SOCKS5"

Write-Host "`n=============================="
if ($httpResult)   { Write-Host "✅ HTTP   : $httpResult"   } else { Write-Host "❌ HTTP   : No open proxy found" }
if ($socks4Result) { Write-Host "✅ SOCKS4 : $socks4Result" } else { Write-Host "❌ SOCKS4 : No open proxy found" }
if ($socks5Result) { Write-Host "✅ SOCKS5 : $socks5Result" } else { Write-Host "❌ SOCKS5 : No open proxy found" }
Write-Host "=============================="
