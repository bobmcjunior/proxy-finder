$ProxyListUrl = "https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/proxies.txt"
$Timeout = 6
$MaxThreads = 60

Write-Host "[+] Downloading proxy list..."
try {
    $proxyData = Invoke-WebRequest -Uri $ProxyListUrl -UseBasicParsing -TimeoutSec 15
} catch {
    Write-Host "[-] Failed to download proxy list"
    exit
}

$proxies = $proxyData.Content -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match ":" }
$proxies = $proxies | Get-Unique

Write-Host "[+] Loaded $($proxies.Count) proxies"
Write-Host "[+] Shuffling..."
$proxies = $proxies | Get-Random -Count $proxies.Count

$alive = New-Object System.Collections.Concurrent.ConcurrentBag[string]

function Test-Proxy {
    param($proxy)

    try {
        $proxyUri = "http://$proxy"
        $webProxy = New-Object System.Net.WebProxy($proxyUri)

        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.Proxy = $webProxy
        $handler.UseProxy = $true

        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [TimeSpan]::FromSeconds(6)

        $response = $client.GetAsync("http://example.com").Result
        if ($response.IsSuccessStatusCode) {
            return $proxy
        }
    } catch {
        return $null
    }
}

Write-Host "[+] Scanning proxies..."

$jobs = @()

foreach ($proxy in $proxies) {
    while ($jobs.Count -ge $MaxThreads) {
        $jobs = $jobs | Where-Object { $_.State -eq "Running" }
        Start-Sleep -Milliseconds 200
    }

    $jobs += Start-Job -ScriptBlock {
        param($p)
        try {
            $proxyUri = "http://$p"
            $webProxy = New-Object System.Net.WebProxy($proxyUri)

            $handler = New-Object System.Net.Http.HttpClientHandler
            $handler.Proxy = $webProxy
            $handler.UseProxy = $true

            $client = New-Object System.Net.Http.HttpClient($handler)
            $client.Timeout = [TimeSpan]::FromSeconds(6)

            $response = $client.GetAsync("http://example.com").Result
            if ($response.IsSuccessStatusCode) {
                Write-Output $p
            }
        } catch {}
    } -ArgumentList $proxy
}

$results = @()
foreach ($job in $jobs) {
    $out = Receive-Job $job -Wait
    if ($out) { $results += $out }
    Remove-Job $job
}

if ($results.Count -eq 0) {
    Write-Host "[-] No alive proxies found"
    exit
}

$chosen = Get-Random $results

Write-Host ""
Write-Host "=============================="
Write-Host "✅ ALIVE PROXY FOUND:"
Write-Host $chosen
Write-Host "=============================="
