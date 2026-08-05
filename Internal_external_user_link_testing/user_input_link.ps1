$Target = (Read-Host "Enter hostname or IP address").Trim()

if ($Target -notmatch '^[a-zA-Z0-9.\-:]+$' -or $Target.Length -eq 0) {
    Write-Error "Invalid hostname or IP address. Only alphanumeric characters, dots, hyphens, and colons are allowed."
    exit 1
}

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $PSScriptRoot "user_Link_$timestamp.txt"

@(
    "Network Test Results",
    "Target: $Target",
    "Date:   $(Get-Date)",
    "----------------------------------"
) | Add-Content -Path $outputFile

$SB_Ping = {
    param($h)
    try   { ping $h 2>&1 }
    catch { "ERROR: $_" }
}

$SB_Tracert = {
    param($h)
    try   { tracert -w 1000 $h 2>&1 }
    catch { "ERROR: $_" }
}

$SB_NSLookup = {
    param($h)
    try   { nslookup $h 2>&1 }
    catch { "ERROR: $_" }
}

$JobDefs = @(
    [PSCustomObject]@{ Label = "PING $Target";     SB = $SB_Ping;     Args = @($Target) }
    [PSCustomObject]@{ Label = "TRACERT $Target";  SB = $SB_Tracert;  Args = @($Target) }
    [PSCustomObject]@{ Label = "NSLOOKUP $Target"; SB = $SB_NSLookup; Args = @($Target) }
)

$Pool = [RunspaceFactory]::CreateRunspacePool(1, 3)
$Pool.Open()

$ActiveJobs = foreach ($Def in $JobDefs) {
    $PS = [PowerShell]::Create()
    $PS.RunspacePool = $Pool
    $null = $PS.AddScript($Def.SB)
    $Def.Args | ForEach-Object { $null = $PS.AddArgument($_) }
    [PSCustomObject]@{ Label = $Def.Label; PS = $PS; Handle = $PS.BeginInvoke() }
}

Write-Host ""
Write-Host "Running PING, TRACERT, and NSLOOKUP in parallel..." -ForegroundColor Cyan

# Print each job's output as soon as it finishes — faster tests appear before tracert completes
$Displayed = @{}
while ($Displayed.Count -lt $ActiveJobs.Count) {
    foreach ($J in $ActiveJobs) {
        if (-not $Displayed[$J.Label] -and $J.Handle.IsCompleted) {
            $Displayed[$J.Label] = $true
            Write-Host ""
            Write-Host "--- $($J.Label) ---" -ForegroundColor Cyan
            $J.Label | Add-Content -Path $outputFile
            try {
                $J.PS.EndInvoke($J.Handle) | ForEach-Object {
                    Write-Host $_
                    $_ | Add-Content -Path $outputFile
                }
            } catch {
                $msg = $_.Exception.InnerException.Message ?? $_.Exception.Message
                Write-Host "ERROR: $msg" -ForegroundColor Red
                "ERROR: $msg" | Add-Content -Path $outputFile
            }
            $J.PS.Dispose()
            "----------------------------------" | Add-Content -Path $outputFile
        }
    }
    if ($Displayed.Count -lt $ActiveJobs.Count) { Start-Sleep -Milliseconds 200 }
}

$Pool.Close()
$Pool.Dispose()

"Test completed at $(Get-Date)" | Add-Content -Path $outputFile
Write-Host ""
Write-Host "Done. Results saved to: $outputFile" -ForegroundColor Green
