# ==========================================
# QUICK VPN CONNECTIVITY VALIDATION
# ==========================================

# -------- CONFIGURATION LOADING --------
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "   VPN CONNECTIVITY VALIDATION SETUP"     -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

$ConfigPath = Join-Path $PSScriptRoot "VPN-HealthCheck.config.json"
$SavedCfg   = $null

if (Test-Path $ConfigPath) {
    try {
        $SavedCfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        Write-Host "  Config loaded from: $ConfigPath" -ForegroundColor DarkGray
        Write-Host ""
    } catch {
        Write-Host "  [WARNING] Could not parse config file — using built-in defaults." -ForegroundColor Yellow
        Write-Host ""
    }
}

function Read-Input {
    param([string]$Prompt, [string]$Default)
    $display = if ($Default) { "$Prompt [default: $Default]" } else { $Prompt }
    $value   = (Read-Host $display).Trim()
    if ([string]::IsNullOrEmpty($value)) { $Default } else { $value }
}

$defExtHost = if ($SavedCfg -and $SavedCfg.ExternalHost)    { $SavedCfg.ExternalHost    } else { "google.com" }
$defIntHost = if ($SavedCfg -and $SavedCfg.InternalHost)    { $SavedCfg.InternalHost    } else { "cam.int.sap" }
$defExtSite = if ($SavedCfg -and $SavedCfg.ExternalWebSite) { $SavedCfg.ExternalWebSite } else { "https://www.google.com" }
$defIntSite = if ($SavedCfg -and $SavedCfg.InternalWebSite) { $SavedCfg.InternalWebSite } else { "https://wiki.one.int.sap" }

$ExternalHost    = Read-Input "External hostname or IP  (e.g. google.com)"  $defExtHost
$InternalHost    = Read-Input "Internal hostname or IP  (e.g. cam.int.sap)" $defIntHost
$ExternalWebSite = Read-Input "External website URL     (e.g. https://...)" $defExtSite
$InternalWebSite = Read-Input "Internal website URL     (e.g. https://...)" $defIntSite

# Ensure website values start with https:// if the user omitted the scheme
foreach ($var in @('ExternalWebSite','InternalWebSite')) {
    $val = (Get-Variable $var).Value
    if ($val -and $val -notmatch '^https?://') {
        Set-Variable $var "https://$val"
    }
}

# Persist values so next run pre-fills them
[ordered]@{
    ExternalHost    = $ExternalHost
    InternalHost    = $InternalHost
    ExternalWebSite = $ExternalWebSite
    InternalWebSite = $InternalWebSite
} | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8

Write-Host ""
Write-Host "  Config saved to: $ConfigPath" -ForegroundColor DarkGray
Write-Host ""

# ---- Report timestamp (shared by HTML + JSON) ----
$RunDate    = Get-Date
$Stamp      = $RunDate.ToString("yyyyMMdd_HHmmss")
$ReportsDir = Join-Path $PSScriptRoot "Reports"
if (-not (Test-Path $ReportsDir)) { New-Item -ItemType Directory -Path $ReportsDir | Out-Null }

$Results   = [System.Collections.Generic.List[PSCustomObject]]::new()
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Add-Result {
    param([string]$Test, [bool]$Passed, [string]$Detail = "", [double]$DurationMs = 0)
    $Results.Add([PSCustomObject]@{
        Test       = $Test
        Status     = if ($Passed) { "PASS" } else { "FAIL" }
        Detail     = $Detail
        DurationMs = [math]::Round($DurationMs, 0)
    })
}

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "   VPN CONNECTIVITY VALIDATION STARTED"   -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  External Host : $ExternalHost"
Write-Host "  Internal Host : $InternalHost"
Write-Host "  External Site : $ExternalWebSite"
Write-Host "  Internal Site : $InternalWebSite"
Write-Host ""

# ==========================================
# ADMIN CHECK
# ==========================================
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Host "[WARNING] Not running as Administrator. Some results may be incomplete." -ForegroundColor Yellow
    Write-Host ""
}

# ==========================================
# VPN ADAPTER INFORMATION
# ==========================================
Write-Host "========== VPN ADAPTER DETAILS ==========" -ForegroundColor Cyan

# Get-NetIPConfiguration skips PPP/RAS adapters (F5 VPN); WMI covers all IP-enabled interfaces
$VpnAdapters = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=TRUE" |
    Where-Object { $_.Description -match "PANGP|GlobalProtect|VPN|_Common_" }

if ($VpnAdapters) {
    $VpnAdapters | ForEach-Object {
        $ipv4 = ($_.IPAddress | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' }) -join ', '
        $dns  = ($_.DNSServerSearchOrder -join ', ')
        [PSCustomObject]@{
            InterfaceAlias = $_.Description
            IPv4Address    = $ipv4
            DNSServers     = $dns
        }
    } | Format-Table -AutoSize
    Add-Result "VPN Adapter Detected" $true ($VpnAdapters.Description -join ", ")
} else {
    Write-Host "No VPN adapter found." -ForegroundColor Yellow
    Add-Result "VPN Adapter Detected" $false "No matching adapter"
}
Write-Host ""

# ==========================================
# FULL IP CONFIGURATION
# ==========================================
Write-Host "========== FULL IP CONFIGURATION ==========" -ForegroundColor Cyan
ipconfig /all
Write-Host ""

# ==========================================
# PARALLEL NETWORK TESTS (runspace pool)
# Each scriptblock returns { Passed; Detail; Display; DurationMs }
# ==========================================
Write-Host "========== RUNNING NETWORK TESTS IN PARALLEL ==========" -ForegroundColor Cyan
Write-Host "  DNS, Ping, TCP, and HTTPS running simultaneously..." -ForegroundColor Gray
Write-Host ""

$SB_DNS = {
    param($HostName)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $r  = Resolve-DnsName $HostName -ErrorAction SilentlyContinue
    $sw.Stop()
    if ($r) {
        $display = ($r | Select-Object -First 3 | Format-Table Name, Type, IPAddress -AutoSize | Out-String).Trim()
        [PSCustomObject]@{ Passed = $true;  Detail = $r[0].IPAddress; Display = $display; DurationMs = $sw.Elapsed.TotalMilliseconds }
    } else {
        [PSCustomObject]@{ Passed = $false; Detail = "No response";   Display = "  FAILED";  DurationMs = $sw.Elapsed.TotalMilliseconds }
    }
}

$SB_Ping = {
    param($HostName)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $r  = Test-Connection -ComputerName $HostName -Count 4 -ErrorAction SilentlyContinue
    $sw.Stop()
    if ($r) {
        $avg     = ($r | Measure-Object -Property Latency -Average).Average
        $display = ($r | Format-Table Address, Latency -AutoSize | Out-String).Trim()
        [PSCustomObject]@{ Passed = $true;  Detail = "Avg $([math]::Round($avg,0))ms"; Display = $display; DurationMs = $sw.Elapsed.TotalMilliseconds }
    } else {
        [PSCustomObject]@{ Passed = $false; Detail = "No response"; Display = "  FAILED"; DurationMs = $sw.Elapsed.TotalMilliseconds }
    }
}

$SB_TCP = {
    param($HostName, $Port)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $ar  = $tcp.BeginConnect($HostName, $Port, $null, $null)
        $ok  = $ar.AsyncWaitHandle.WaitOne(3000)
        $sw.Stop()
        if ($ok -and $tcp.Connected) {
            $tcp.Close()
            [PSCustomObject]@{ Passed = $true;  Detail = "Port $Port open";                  DurationMs = $sw.Elapsed.TotalMilliseconds }
        } else {
            $tcp.Close()
            [PSCustomObject]@{ Passed = $false; Detail = "Port $Port blocked or timeout";    DurationMs = $sw.Elapsed.TotalMilliseconds }
        }
    } catch {
        $sw.Stop()
        [PSCustomObject]@{ Passed = $false; Detail = $_.Exception.Message;                   DurationMs = $sw.Elapsed.TotalMilliseconds }
    }
}

$SB_HTTPS = {
    param($Uri)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        $sw.Stop()
        [PSCustomObject]@{ Passed = $true;  Detail = "HTTP $($r.StatusCode)";  DurationMs = $sw.Elapsed.TotalMilliseconds }
    } catch {
        $sw.Stop()
        [PSCustomObject]@{ Passed = $false; Detail = $_.Exception.Message;     DurationMs = $sw.Elapsed.TotalMilliseconds }
    }
}

$Pool = [RunspaceFactory]::CreateRunspacePool(1, 8)
$Pool.Open()

$JobDefs = @(
    [PSCustomObject]@{ Key = "DNS_Ext";   SB = $SB_DNS;   Args = @($ExternalHost)     }
    [PSCustomObject]@{ Key = "DNS_Int";   SB = $SB_DNS;   Args = @($InternalHost)      }
    [PSCustomObject]@{ Key = "Ping_Ext";  SB = $SB_Ping;  Args = @($ExternalHost)      }
    [PSCustomObject]@{ Key = "Ping_Int";  SB = $SB_Ping;  Args = @($InternalHost)      }
    [PSCustomObject]@{ Key = "TCP_Ext";   SB = $SB_TCP;   Args = @($ExternalHost, 443) }
    [PSCustomObject]@{ Key = "TCP_Int";   SB = $SB_TCP;   Args = @($InternalHost, 443) }
    [PSCustomObject]@{ Key = "HTTPS_Ext"; SB = $SB_HTTPS; Args = @($ExternalWebSite)   }
    [PSCustomObject]@{ Key = "HTTPS_Int"; SB = $SB_HTTPS; Args = @($InternalWebSite)   }
)

$ActiveJobs = foreach ($Def in $JobDefs) {
    $PS = [PowerShell]::Create()
    $PS.RunspacePool = $Pool
    $null = $PS.AddScript($Def.SB)
    $Def.Args | ForEach-Object { $null = $PS.AddArgument($_) }
    [PSCustomObject]@{ Key = $Def.Key; PS = $PS; Handle = $PS.BeginInvoke() }
}

$R = @{}
foreach ($J in $ActiveJobs) {
    try {
        $out       = $J.PS.EndInvoke($J.Handle)
        $R[$J.Key] = if ($out.Count -gt 0) { $out[0] } else {
            [PSCustomObject]@{ Passed = $false; Detail = "No output from runspace"; Display = "  NO OUTPUT"; DurationMs = 0 }
        }
    } catch {
        $msg       = $_.Exception.InnerException.Message ?? $_.Exception.Message
        $R[$J.Key] = [PSCustomObject]@{ Passed = $false; Detail = $msg; Display = "  ERROR: $msg"; DurationMs = 0 }
    }
    $J.PS.Dispose()
}
$Pool.Close()
$Pool.Dispose()

# ---- Display: DNS ----
Write-Host "========== DNS TESTS ==========" -ForegroundColor Cyan
Write-Host ""
Write-Host "External DNS ($ExternalHost):"
Write-Host $R["DNS_Ext"].Display
Add-Result "DNS External ($ExternalHost)" ([bool]$R["DNS_Ext"].Passed) $R["DNS_Ext"].Detail $R["DNS_Ext"].DurationMs

Write-Host ""
Write-Host "Internal DNS ($InternalHost):"
Write-Host $R["DNS_Int"].Display
Add-Result "DNS Internal ($InternalHost)" ([bool]$R["DNS_Int"].Passed) $R["DNS_Int"].Detail $R["DNS_Int"].DurationMs
Write-Host ""

# ---- Display: Ping ----
Write-Host "========== PING TESTS ==========" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ping External ($ExternalHost):"
Write-Host $R["Ping_Ext"].Display
Add-Result "Ping External ($ExternalHost)" ([bool]$R["Ping_Ext"].Passed) $R["Ping_Ext"].Detail $R["Ping_Ext"].DurationMs

Write-Host ""
Write-Host "Ping Internal ($InternalHost):"
Write-Host $R["Ping_Int"].Display
Add-Result "Ping Internal ($InternalHost)" ([bool]$R["Ping_Int"].Passed) $R["Ping_Int"].Detail $R["Ping_Int"].DurationMs
Write-Host ""

# ---- Display: TCP ----
Write-Host "========== TCP PORT 443 TESTS ==========" -ForegroundColor Cyan
Write-Host ""
foreach ($Entry in @(
    [PSCustomObject]@{ Key = "TCP_Ext"; Host = $ExternalHost }
    [PSCustomObject]@{ Key = "TCP_Int"; Host = $InternalHost }
)) {
    $Res   = $R[$Entry.Key]
    $Color = if ($Res.Passed) { "Green" } else { "Red" }
    $State = if ($Res.Passed) { "OPEN"  } else { "BLOCKED/UNREACHABLE" }
    Write-Host ("TCP 443 -> {0} :  {1}  ({2})  [{3:N0} ms]" -f $Entry.Host, $State, $Res.Detail, $Res.DurationMs) -ForegroundColor $Color
    Add-Result "TCP 443 ($($Entry.Host))" ([bool]$Res.Passed) $Res.Detail $Res.DurationMs
}
Write-Host ""

# ---- Display: HTTPS ----
Write-Host "========== HTTPS TESTS ==========" -ForegroundColor Cyan
foreach ($Entry in @(
    [PSCustomObject]@{ Key = "HTTPS_Ext"; Site = $ExternalWebSite }
    [PSCustomObject]@{ Key = "HTTPS_Int"; Site = $InternalWebSite }
)) {
    $Res   = $R[$Entry.Key]
    $Color = if ($Res.Passed) { "Green" } else { "Red" }
    $Icon  = if ($Res.Passed) { "SUCCESS" } else { "FAILED" }
    Write-Host ""
    Write-Host "Testing: $($Entry.Site)"
    Write-Host ("  {0}  ({1})  [{2:N0} ms]" -f $Icon, $Res.Detail, $Res.DurationMs) -ForegroundColor $Color
    Add-Result "HTTPS $($Entry.Site)" ([bool]$Res.Passed) $Res.Detail $Res.DurationMs
}
Write-Host ""

# ==========================================
# PARALLEL TRACEROUTE
# ==========================================
Write-Host "========== TRACEROUTE TESTS ==========" -ForegroundColor Cyan
Write-Host "  Both traceroutes running in parallel..." -ForegroundColor Gray
Write-Host ""

$TraceExt = Start-Job { param($h) tracert -d -w 1000 $h } -ArgumentList $ExternalHost
$TraceInt = Start-Job { param($h) tracert -d -w 1000 $h } -ArgumentList $InternalHost

Write-Host "Traceroute -> $ExternalHost :"
Receive-Job $TraceExt -Wait | ForEach-Object { Write-Host $_ }
Write-Host ""
Write-Host "Traceroute -> $InternalHost :"
Receive-Job $TraceInt -Wait | ForEach-Object { Write-Host $_ }
Remove-Job $TraceExt, $TraceInt
Write-Host ""

# ==========================================
# ROUTING TABLE
# ==========================================
Write-Host "========== ROUTING TABLE ==========" -ForegroundColor Cyan
route print
Write-Host ""

# ==========================================
# SUMMARY
# ==========================================
$Stopwatch.Stop()
$TotalSec  = [math]::Round($Stopwatch.Elapsed.TotalSeconds, 1)
$PassCount = ($Results | Where-Object Status -eq "PASS").Count
$FailCount = ($Results | Where-Object Status -eq "FAIL").Count

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "   RESULTS SUMMARY"                        -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

foreach ($Item in $Results) {
    $Color = if ($Item.Status -eq "PASS") { "Green" } else { "Red" }
    $Line  = "  [{0}]  {1}" -f $Item.Status, $Item.Test
    if ($Item.Detail)     { $Line += "  —  $($Item.Detail)" }
    if ($Item.DurationMs) { $Line += "  [$($Item.DurationMs) ms]" }
    Write-Host $Line -ForegroundColor $Color
}

Write-Host ""
Write-Host ("  Total: {0} checks  |  {1} passed  |  {2} failed  |  Completed in {3}s" -f `
    $Results.Count, $PassCount, $FailCount, $TotalSec) -ForegroundColor Cyan
Write-Host ""

# ==========================================
# REPORT EXPORT — HTML
# ==========================================
$HtmlPath = Join-Path $ReportsDir "VPN-HealthCheck-$Stamp.html"

$RowsHtml = ($Results | ForEach-Object {
    $bg    = if ($_.Status -eq "PASS") { "#d4edda" } else { "#f8d7da" }
    $color = if ($_.Status -eq "PASS") { "#155724" } else { "#721c24" }
    $badge = if ($_.Status -eq "PASS") { "#28a745" } else { "#dc3545" }
    $dur   = if ($_.DurationMs) { "$($_.DurationMs) ms" } else { "—" }
    "<tr style='background:$bg;color:$color'>
      <td>$($_.Test)</td>
      <td style='text-align:center'><span style='background:$badge;color:#fff;padding:2px 8px;border-radius:4px;font-size:0.85em'>$($_.Status)</span></td>
      <td>$([System.Web.HttpUtility]::HtmlEncode($_.Detail))</td>
      <td style='text-align:right'>$dur</td>
    </tr>"
}) -join "`n"

$Html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>VPN Health Check — $($RunDate.ToString('yyyy-MM-dd HH:mm:ss'))</title>
<style>
  body { font-family: Segoe UI, Arial, sans-serif; margin: 0; background: #f0f2f5; }
  .header { background: linear-gradient(135deg,#0072C6,#00b4d8); color:#fff; padding:28px 36px; }
  .header h1 { margin:0 0 6px; font-size:1.5em; letter-spacing:1px; }
  .header p  { margin:3px 0; font-size:0.92em; opacity:.9; }
  .stats { display:flex; gap:20px; padding:22px 36px; flex-wrap:wrap; }
  .stat  { background:#fff; border-radius:8px; padding:16px 24px; flex:1; min-width:120px;
           box-shadow:0 1px 4px rgba(0,0,0,.1); text-align:center; }
  .stat .num  { font-size:2em; font-weight:700; }
  .stat .lbl  { font-size:0.8em; color:#666; margin-top:2px; }
  .pass .num  { color:#28a745; }
  .fail .num  { color:#dc3545; }
  .total .num { color:#0072C6; }
  .dur .num   { color:#6c757d; }
  table { width:calc(100% - 72px); margin:0 36px 36px; border-collapse:collapse;
          box-shadow:0 1px 4px rgba(0,0,0,.1); border-radius:8px; overflow:hidden; }
  th { background:#0072C6; color:#fff; padding:10px 14px; text-align:left; font-size:.88em; }
  td { padding:9px 14px; font-size:.9em; border-bottom:1px solid rgba(0,0,0,.06); }
  tr:last-child td { border-bottom:none; }
  .footer { text-align:center; padding:12px; font-size:.78em; color:#999; }
</style>
</head>
<body>
<div class="header">
  <h1>VPN Connectivity Health Check</h1>
  <p>Computer: <strong>$($env:COMPUTERNAME)</strong> &nbsp;|&nbsp; Run: $($RunDate.ToString('yyyy-MM-dd HH:mm:ss')) &nbsp;|&nbsp; Duration: ${TotalSec}s</p>
  <p>External: $ExternalHost / $ExternalWebSite &nbsp;|&nbsp; Internal: $InternalHost / $InternalWebSite</p>
</div>
<div class="stats">
  <div class="stat total"><div class="num">$($Results.Count)</div><div class="lbl">Total Checks</div></div>
  <div class="stat pass"><div class="num">$PassCount</div><div class="lbl">Passed</div></div>
  <div class="stat fail"><div class="num">$FailCount</div><div class="lbl">Failed</div></div>
  <div class="stat dur"><div class="num">${TotalSec}s</div><div class="lbl">Total Duration</div></div>
</div>
<table>
  <thead><tr><th>Test</th><th style="text-align:center">Status</th><th>Detail</th><th style="text-align:right">Duration</th></tr></thead>
  <tbody>
$RowsHtml
  </tbody>
</table>
<div class="footer">Generated by VPN-HealthCheck.ps1</div>
</body>
</html>
"@

$Html | Set-Content -Path $HtmlPath -Encoding UTF8

# ==========================================
# REPORT EXPORT — JSON (monitoring drop)
# ==========================================
$JsonPath = Join-Path $ReportsDir "VPN-HealthCheck-$Stamp.json"

[ordered]@{
    RunDate        = $RunDate.ToString("yyyy-MM-ddTHH:mm:ss")
    ComputerName   = $env:COMPUTERNAME
    ExternalHost   = $ExternalHost
    InternalHost   = $InternalHost
    ExternalSite   = $ExternalWebSite
    InternalSite   = $InternalWebSite
    TotalDurationSec = $TotalSec
    PassCount      = $PassCount
    FailCount      = $FailCount
    OverallStatus  = if ($FailCount -eq 0) { "PASS" } else { "FAIL" }
    Results        = @($Results | ForEach-Object {
        [ordered]@{
            Test       = $_.Test
            Status     = $_.Status
            Detail     = $_.Detail
            DurationMs = $_.DurationMs
        }
    })
} | ConvertTo-Json -Depth 5 | Set-Content -Path $JsonPath -Encoding UTF8

# ==========================================
# FINAL FOOTER
# ==========================================
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "   REPORTS SAVED"                          -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  HTML : $HtmlPath" -ForegroundColor Green
Write-Host "  JSON : $JsonPath" -ForegroundColor Green
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "   VPN CONNECTIVITY VALIDATION COMPLETED"  -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
