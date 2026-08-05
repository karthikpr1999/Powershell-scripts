# PowerShell Scripts

A collection of PowerShell utilities for network diagnostics, VPN health checks, system monitoring, and security tooling — built for a Windows/SAP enterprise environment.

---

## Table of Contents

- [Requirements](#requirements)
- [Scripts Overview](#scripts-overview)
  - [VPN Health Check](#1-vpn-healthcheckps1)
  - [Network Pulse Check](#2-pulse_check_networkps1)
  - [NSLookup Multi](#3-nslookup_multips1)
  - [Network Speed Monitor](#4-networkspeedmonitorps1)
  - [Ping Multi-Host](#5-ping-multi-host)
  - [External Link Diagnostics](#6-gateway_external_link_testps1)
  - [Internal Link Diagnostics](#7-gateway_internal_link_testps1)
  - [User-Input Diagnostics](#8-user_input_linkps1--test1ps1)
  - [VPN UDP Port Test](#9-testps1)
  - [Password Generator](#10-random_password_generatorps1)
  - [Ticket Reminder](#11-ticket_remainderps1)
  - [LogicMonitor Hourly Check](#12-hourly_lm_emailps1)
- [Directory Structure](#directory-structure)
- [Output Files](#output-files)
- [Running Scripts](#running-scripts)

---

## Requirements

- **PowerShell 5.1+** (Windows PowerShell or PowerShell 7)
- **Windows 10 / Windows 11**
- **Administrator privileges** — recommended for VPN-HealthCheck.ps1 and UDP port tests
- Native Windows tools in PATH: `ping`, `tracert`, `nslookup`, `route`, `ipconfig`, `curl.exe` (ships with Windows 10 1803+)

No external modules or package installs are required.

---

## Scripts Overview

### 1. `VPN-HealthCheck.ps1`

The most comprehensive diagnostic tool in the repo. Runs a full suite of parallel network tests and generates timestamped HTML, JSON, and TXT reports.

**What it tests:**

| Test | Target |
| ---- | ------ |
| DNS resolution | External host (default: `google.com`) and Internal host (default: `cam.int.sap`) |
| Ping latency | External + Internal |
| TCP port 443 | External + Internal |
| HTTPS response code | External + Internal websites |
| Traceroute | External + Internal (run in parallel) |
| Native ping + nslookup | External + Internal (full output captured to TXT) |
| VPN adapter detection | All network interfaces via .NET `NetworkInterface` API |
| Routing table | Full route print |

**Configuration:**
On first run, the script prompts for hostnames and URLs, then saves them to `VPN-HealthCheck.config.json` so you don't need to re-enter them each time.

**Usage:**

```powershell
# Run with defaults / saved config
.\VPN-HealthCheck.ps1

# Elevated (recommended for full results)
Start-Process powershell -Verb RunAs -ArgumentList "-File .\VPN-HealthCheck.ps1"
```

**Outputs:**

- `Reports/VPN-HealthCheck-<timestamp>.html` — styled pass/fail report for easy review
- `Reports/VPN-HealthCheck-<timestamp>.json` — machine-readable results for integration
- `Reports/VPN-HealthCheck-<timestamp>.txt` — full raw output of ping, traceroute, nslookup, and summary

---

### 2. `Pulse_Check_network.ps1`

Parallel connectivity pulse across multiple public and cloud endpoints. All targets are tested simultaneously using a RunspacePool — total run time equals the slowest single target, not all targets combined.

**Tests per target:**

- DNS resolution (A record via .NET)
- IPv4 reachability — 3 ICMP pings with average RTT and packet-loss %
- IPv6 reachability — skipped if no AAAA record exists
- MTU fragmentation probe — DF-bit ping at the requested MTU size

**Features:**

- Optional JSON config file (`Pulse_Check_network.config.json`) for custom targets and default MTU
- Extra-targets prompt — add ad-hoc hostnames/IPs without editing the script
- Color-coded per-target detail + summary table with pass/fail counts

**Usage:**

```powershell
.\Pulse_Check_network.ps1
# Optionally enter extra hosts when prompted, then MTU size (default: 1460)
```

No file output — results are displayed in the console only.

**Config file** (optional — copy from `Pulse_Check_network.config.example.json`):

```json
{
  "defaultMtu": 1460,
  "targets": ["google.com", "your-internal-host.corp"]
}
```

---

### 3. `NSLookup_multi.ps1`

Runs detailed DNS lookups and a curl verbose request for multiple URLs simultaneously using a RunspacePool. Useful for auditing DNS records and inspecting TLS/HTTP behaviour.

**DNS record types queried:** A, AAAA, CNAME, MX, TXT, PTR

**What curl captures:** TLS handshake details, request/response headers, HTTP status code, redirect chain — all via `curl.exe -v`.

**Usage:**

```powershell
.\NSLookup_multi.ps1
# Enter a custom DNS server IP, or press Enter to use the system DNS
# Enter URLs or hostnames (one per line or comma-separated), blank line to start
```

**Input examples:**

```text
https://google.com/search?q=test   <- full URL, hostname extracted automatically
github.com                         <- plain hostname
8.8.8.8                            <- IP address
```

Console output: per-target DNS record detail + curl verbose output, followed by a summary table.

---

### 4. `NetworkSpeedMonitor.ps1`

Real-time network throughput dashboard. Polls `Get-NetAdapterStatistics` every second, computes RX/TX Mbps, and renders a live in-place terminal display.

**Features:**

- Monitors Ethernet and Wi-Fi physical adapters only
- Automatically excludes virtual switches, VPN tunnels, Bluetooth, loopback
- Color-graded speed indicators: dim (idle) → green → yellow → red
- Per-category (Ethernet / Wi-Fi) totals row
- Handles hot-plug and adapter enable/disable events — adapter list refreshes each cycle
- Press Ctrl+C to exit cleanly

**Usage:**

```powershell
.\NetworkSpeedMonitor.ps1
# No parameters — runs until Ctrl+C
```

No file output — live console dashboard only.

---

### 5. Ping Multi-Host

Pings multiple hosts simultaneously using a RunspacePool, shows a live per-host progress bar, prints each host's summary as soon as it finishes, and exports results to a timestamped CSV.

**Features:**

- All hosts ping in parallel — total time equals one host's time
- Live `Ping 650 / 1000` counter per host updated every 200 ms
- Min / max / average latency and packet-loss % per host
- Auto-saves to `PingResults_<timestamp>.csv`

**Usage:**

```powershell
# Default hosts (google.com, cloudflare.com, 1.1.1.1, 8.8.8.8), 1000 pings each
.\Ping_multihosts\Ping-HostnameTest.ps1

# Custom hosts and ping count
.\Ping_multihosts\Ping-HostnameTest.ps1 -Hostnames "8.8.8.8","10.0.0.1" -PingCount 500

# Add delay between pings to avoid rate-limiting
.\Ping_multihosts\Ping-HostnameTest.ps1 -PingCount 200 -DelayMs 50
```

See [`Ping_multihosts/README.md`](Ping_multihosts/README.md) for full parameter reference and output examples.

---

### 6. `gateway_external_link_test.ps1`

Runs ping, tracert, and nslookup against `google.com` and saves results to a timestamped text file. Quick external connectivity snapshot.

**Usage:**

```powershell
.\gateway_external_link_test.ps1
```

**Output:** `NetworkDiagnosticsForExternalLink<timestamp>.txt`

---

### 7. `Gateway_internal_link_test.ps1`

Same as above but targets the SAP internal hostname `search-corp.cyber.only.sap`. Useful for verifying internal DNS and routing while on VPN.

**Usage:**

```powershell
.\Gateway_internal_link_test.ps1
```

**Output:** `NetworkDiagnosticsForInternalLink<timestamp>.txt`

---

### 8. `user_input_link.ps1` / `test1.ps1`

Interactive diagnostic tools — prompts you for a hostname or IP, then runs ping, tracert, and nslookup against it **in parallel** using a RunspacePool, and saves the output to a timestamped text file.

**Usage:**

```powershell
.\user_input_link.ps1
# Enter target when prompted: e.g. 8.8.8.8 or internal.server.sap
```

**Output:** `user_Link_<timestamp>.txt` (saved next to the script)

> `test1.ps1` is a variant that accepts the target via `-GatewayIP` parameter or `$env:VPN_GATEWAY_IP`.

---

### 9. `test.ps1`

Tests UDP ports 500 and 4500 against a configurable VPN gateway IP. These are the standard IPSec/IKE ports used by enterprise VPNs.

**Usage:**

```powershell
.\test.ps1 -GatewayIP "x.x.x.x"
# or
$env:VPN_GATEWAY_IP = "x.x.x.x"; .\test.ps1
```

Console output indicates whether each UDP port is reachable or blocked.

---

### 10. `Random_password_generator.ps1`

Generates cryptographically secure passwords using `System.Security.Cryptography.RandomNumberGenerator` (not `Get-Random`).

**Features:**

- Configurable length, count, and character classes
- Guaranteed inclusion of at least one character from each active class (uppercase, lowercase, digits, symbols)
- Entropy calculation and strength rating: Weak / Fair / Strong / Very Strong
- Minimum enforced length: 8 characters

**Usage:**

```powershell
.\Random_password_generator.ps1

# Prompts:
#   Length (default 12):
#   How many passwords (default 1):
#   Exclude symbols? (y/n):
#   Exclude numbers? (y/n):
#   Exclude uppercase? (y/n):
```

Output is displayed in the console with entropy and strength info.

---

### 11. `ticket_remainder.ps1`

Sends a Windows system tray balloon notification + sound alert on a set interval to remind you to check the ticket queue. Runs in a loop until you press Ctrl+C.

**Default settings:** every 1 minute, title "Ticket Reminder", message "Check the ticket queue now."

**Usage:**

```powershell
.\ticket_remainder.ps1
```

To change the interval or message, edit the variables at the top of the script.

---

### 12. `Hourly_LM_email.ps1`

Opens the SAP LogicMonitor dashboard in your default browser and ensures Outlook is running, then logs each check. Runs on a recurring interval and shows balloon tip notifications.

**Usage:**

```powershell
.\Hourly_LM_email.ps1
```

**Log file:** `logic_monitor_logs/HourLogicMonitor.log`

---

## Directory Structure

```text
Powershell_scripts/
├── VPN-HealthCheck.ps1                     # Full VPN diagnostic with HTML/JSON/TXT reports
├── Pulse_Check_network.ps1                 # Parallel multi-target connectivity pulse check
├── NSLookup_multi.ps1                      # Multi-URL DNS record lookup + curl verbose
├── NetworkSpeedMonitor.ps1                 # Real-time RX/TX Mbps dashboard
├── gateway_external_link_test.ps1          # External link diagnostics (google.com)
├── Gateway_internal_link_test.ps1          # Internal link diagnostics (SAP host)
├── user_input_link.ps1                     # User-prompted parallel diagnostics
├── test1.ps1                               # User-prompted diagnostics (gateway IP variant)
├── test.ps1                                # VPN UDP port test
├── Random_password_generator.ps1           # Secure password generator
├── ticket_remainder.ps1                    # Ticket queue reminder
├── Hourly_LM_email.ps1                     # LogicMonitor + Outlook check
│
├── Pulse_Check_network.config.example.json # Config template for Pulse_Check_network.ps1
├── VPN-HealthCheck.config.example.json     # Config template for VPN-HealthCheck.ps1
│
├── Ping_multihosts/                        # Parallel multi-host ping tool
│   ├── Ping-HostnameTest.ps1               # Main script
│   ├── README.md                           # Full usage and parameter reference
│   └── PingResults_<timestamp>.csv         # Auto-generated on each run (gitignored)
│
├── Internal_external_user_link_testing/    # Development/testing variants
│   ├── gateway_external_link_test.ps1
│   ├── Gateway_internal_link_test.ps1
│   └── user_input_link.ps1                 # Parallel RunspacePool version
│
├── Reports/                                # Auto-generated by VPN-HealthCheck.ps1 (gitignored)
│   ├── VPN-HealthCheck-<timestamp>.html
│   ├── VPN-HealthCheck-<timestamp>.json
│   └── VPN-HealthCheck-<timestamp>.txt
│
└── logic_monitor_logs/
    └── HourLogicMonitor.log                # Append-only log (gitignored)
```

---

## Output Files

| Script | Output |
| ------ | ------ |
| `VPN-HealthCheck.ps1` | `Reports/VPN-HealthCheck-<timestamp>.html` + `.json` + `.txt` |
| `Ping_multihosts/Ping-HostnameTest.ps1` | `Ping_multihosts/PingResults_<timestamp>.csv` |
| `gateway_external_link_test.ps1` | `NetworkDiagnosticsForExternalLink<timestamp>.txt` |
| `Gateway_internal_link_test.ps1` | `NetworkDiagnosticsForInternalLink<timestamp>.txt` |
| `user_input_link.ps1` | `user_Link_<timestamp>.txt` |
| `Hourly_LM_email.ps1` | `logic_monitor_logs/HourLogicMonitor.log` |
| `Pulse_Check_network.ps1` | Console only |
| `NSLookup_multi.ps1` | Console only |
| `NetworkSpeedMonitor.ps1` | Console only |
| `Random_password_generator.ps1` | Console only |
| `ticket_remainder.ps1` | Console only |
| `test.ps1` | Console only |

---

## Running Scripts

PowerShell may block scripts from running if the execution policy is restricted. To allow local scripts:

```powershell
# Check current policy
Get-ExecutionPolicy

# Allow local scripts (run once, as current user)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

To run any script:

```powershell
cd "C:\path\to\Powershell_scripts"
.\ScriptName.ps1
```

For scripts that require admin access (VPN checks, UDP port testing), right-click PowerShell and select **Run as Administrator**, or use:

```powershell
Start-Process powershell -Verb RunAs -ArgumentList "-File .\VPN-HealthCheck.ps1"
```
