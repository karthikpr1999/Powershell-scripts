# Replace with your actual company VPN Gateway public IP
$GatewayIP = "137.83.231.72" 

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