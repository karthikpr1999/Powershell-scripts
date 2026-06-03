# Set VPN_GATEWAY_IP environment variable, or pass as argument: .\test1.ps1 -GatewayIP "x.x.x.x"
param(
    [Parameter(Mandatory=$false)]
    [string]$GatewayIP = $env:VPN_GATEWAY_IP
)

if ([string]::IsNullOrWhiteSpace($GatewayIP)) {
    Write-Error "GatewayIP is required. Set the VPN_GATEWAY_IP environment variable or pass -GatewayIP."
    exit 1
}

# Validate IP format
if ($GatewayIP -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
    Write-Error "Invalid IP address format."
    exit 1
}

Write-Host "Testing UDP 500 and 4500 Socket Initialization..." -ForegroundColor Cyan

# Test UDP 500
$Udp500 = New-Object System.Net.Sockets.UdpClient
try {
    $Udp500.Connect($GatewayIP, 500)
    Write-Host "[+] UDP Port 500 socket initialized successfully to $GatewayIP" -ForegroundColor Green
} catch {
    Write-Host "[!] UDP Port 500 is locally blocked or restricted." -ForegroundColor Red
} finally { $Udp500.Close() }

# Test UDP 4500
$Udp4500 = New-Object System.Net.Sockets.UdpClient
try {
    $Udp4500.Connect($GatewayIP, 4500)
    Write-Host "[+] UDP Port 4500 socket initialized successfully to $GatewayIP" -ForegroundColor Green
} catch {
    Write-Host "[!] UDP Port 4500 is locally blocked or restricted." -ForegroundColor Red
} finally { $Udp4500.Close() }