$HttpList   = "https://github.com/TheSpeedX/PROXY-List/raw/refs/heads/master/http.txt"
$Socks4List = "https://github.com/TheSpeedX/PROXY-List/raw/refs/heads/master/socks4.txt"
$Socks5List = "https://github.com/TheSpeedX/PROXY-List/raw/refs/heads/master/socks5.txt"

$Timeout = 6
$MaxThreads = 80
$TestUrl = "http://example.com"

Write-Host "`n[+] Downloading proxy lists..."

function Download-List($url) {
    try {
        (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20).Content `
            -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match ":" }
    } catch {
        Write-Host "[-] Failed to download: $url"
        return @()
    }
}

$httpProxies   = Download-List $HttpList
$socks4Proxies = Download-List $Socks4List
$socks5Proxies = Download-List $Socks5List

Write-Host "[+] HTTP proxies   : $($httpProxies.Count)"
Write-Host "[+] SOCKS4 proxies : $($socks4Proxies.Count)"
Write-Host "[+] SOCKS5 proxies : $($socks5Proxies.Count)`n"

function Test-HttpProxy($proxy) {
    try {
        $proxyUri = "http://$proxy"
        $webProxy = New-Object System.Net.WebProxy($proxyUri)

        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.Proxy = $webProxy
        $handler.UseProxy = $true

        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [TimeSpan]::FromSeconds($Timeout)

        $r = $client.GetAsync($TestUrl).Result
        if ($r.IsSuccessStatusCode) { return $proxy }
    } catch {}
}

function Test-SocksProxy($proxy) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $result = $tcp.BeginConnect($proxy.Split(":")[0], $proxy.Split(":")[1], $null, $null)
        $success = $result.AsyncWaitHandle.WaitOne(3000, $false)
        $tcp.Close()
        if ($success) { return $proxy }
    } catch {}
}

function Find-Alive($list, $type) {
    Write-Host "[+] Scanning $type proxies..."
    $jobs = @()
    $alive = @()

    foreach ($p in $list | Get-Random -Count ([Math]::Min(800, $list.Count))) {
        while ($jobs.Count -ge $MaxThreads) {
            $jobs = $jobs | Where-Object { $_.State -eq "Running" }
            Start-Sleep -Milliseconds 100
        }

        $jobs += Start-Job -ScriptBlock {
            param($proxy, $ptype, $timeout, $url)

            if ($ptype -eq "HTTP") {
                try {
                    $proxyUri = "http://$proxy"
                    $webProxy = New-Object System.Net.WebProxy($proxyUri)

                    $handler = New-Object System.Net.Http.HttpClientHandler
                    $handler.Proxy = $webProxy
                    $handler.UseProxy = $true

                    $client = New-Object System.Net.Http.HttpClient($handler)
                    $client.Timeout = [TimeSpan]::FromSeconds($timeout)

                    $r = $client.GetAsync($url).Result
                    if ($r.IsSuccessStatusCode) { return $proxy }
                } catch {}
            } else {
                try {
                    $ip = $proxy.Split(":")[0]
                    $port = $proxy.Split(":")[1]
                    $tcp = New-Object System.Net.Sockets.TcpClient
                    $res = $tcp.BeginConnect($ip, $port, $null, $null)
                    $ok = $res.AsyncWaitHandle.WaitOne(3000, $false)
                    $tcp.Close()
                    if ($ok) { return $proxy }
                } catch {}
            }
        } -ArgumentList $p, $type, $Timeout, $TestUrl
    }

    foreach ($job in $jobs) {
        $out = Receive-Job $job -Wait
        if ($out) { $alive += $out }
        Remove-Job $job
    }

    return $alive
}

$aliveHttp   = Find-Alive $httpProxies "HTTP"
$aliveSocks4 = Find-Alive $socks4Proxies "SOCKS4"
$aliveSocks5 = Find-Alive $socks5Proxies "SOCKS5"

Write-Host "`n=============================="

if ($aliveHttp.Count -gt 0) {
    $pick = Get-Random $aliveHttp
    Write-Host "✅ HTTP   : $pick"
} else {
    Write-Host "❌ HTTP   : None alive"
}

if ($aliveSocks4.Count -gt 0) {
    $pick = Get-Random $aliveSocks4
    Write-Host "✅ SOCKS4 : $pick"
} else {
    Write-Host "❌ SOCKS4 : None alive"
}

if ($aliveSocks5.Count -gt 0) {
    $pick = Get-Random $aliveSocks5
    Write-Host "✅ SOCKS5 : $pick"
} else {
    Write-Host "❌ SOCKS5 : None alive"
}

Write-Host "=============================="
