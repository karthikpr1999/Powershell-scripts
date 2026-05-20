# PowerShell Scripts

A collection of PowerShell utilities for network diagnostics, VPN health checks, system monitoring, and security tooling — built for a Windows/SAP enterprise environment.

---

## Table of Contents

- [Requirements](#requirements)
- [Scripts Overview](#scripts-overview)
  - [VPN Health Check](#1-vpn-healthcheckps1)
  - [Network Pulse Check](#2-pulse_check_networkps1)
  - [External Link Diagnostics](#3-gateway_external_link_testps1)
  - [Internal Link Diagnostics](#4-gateway_internal_link_testps1)
  - [User-Input Diagnostics](#5-user_input_linkps1--test1ps1)
  - [VPN UDP Port Test](#6-testps1)
  - [Password Generator](#7-random_password_generatorps1)
  - [Ticket Reminder](#8-ticket_remainderps1)
  - [LogicMonitor Hourly Check](#9-hourly_lm_emailps1)
- [Directory Structure](#directory-structure)
- [Output Files](#output-files)
- [Running Scripts](#running-scripts)

---

## Requirements

- **PowerShell 5.1+** (Windows PowerShell or PowerShell 7)
- **Windows 10 / Windows 11**
- **Administrator privileges** — recommended for VPN-HealthCheck.ps1 and UDP port tests
- Native Windows tools in PATH: `ping`, `tracert`, `nslookup`, `route`, `ipconfig`

No external modules or package installs are required.

---

## Scripts Overview

### 1. `VPN-HealthCheck.ps1`

The most comprehensive diagnostic tool in the repo. Runs a full suite of parallel network tests and generates timestamped HTML and JSON reports.

**What it tests:**
| Test | Target |
|------|--------|
| DNS resolution | External host (default: `google.com`) and Internal host (default: `cam.int.sap`) |
| Ping latency | External + Internal |
| TCP port 443 | External + Internal |
| HTTPS response code | External + Internal websites |
| Traceroute | External + Internal (run in parallel) |
| VPN adapter detection | All network interfaces |
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

---

### 2. `Pulse_Check_network.ps1`

Quick connectivity pulse across 13 well-known public and cloud endpoints. Useful for confirming general internet health before troubleshooting further.

**Targets tested:** google.com, cloudflare.com, microsoft.com, amazon.in, youtube.com, facebook.com, twitter.com, linkedin.com, github.com, netflix.com, and a few others.

**Features:**
- IPv4 and IPv6 tests per target
- MTU fragmentation check (MTU 1460)
- Color-coded console output: `[PASS]` / `[FAIL]` / `[FRAGMENTATION REQUIRED]`

**Usage:**
```powershell
.\Pulse_Check_network.ps1
```

No file output — results are displayed in the console only.

---

### 3. `gateway_external_link_test.ps1`

Runs ping, tracert, and nslookup against `google.com` and saves results to a timestamped text file. Quick external connectivity snapshot.

**Usage:**
```powershell
.\gateway_external_link_test.ps1
```

**Output:** `NetworkDiagnosticsForExternalLink<timestamp>.txt`

---

### 4. `Gateway_internal_link_test.ps1`

Same as above but targets the SAP internal hostname `search-corp.cyber.only.sap`. Useful for verifying internal DNS and routing while on VPN.

**Usage:**
```powershell
.\Gateway_internal_link_test.ps1
```

**Output:** `NetworkDiagnosticsForInternalLink<timestamp>.txt`

---

### 5. `user_input_link.ps1` / `test1.ps1`

Interactive diagnostic tools — prompts you for a hostname or IP, then runs ping, tracert, and nslookup against it and saves the output.

**Usage:**
```powershell
.\user_input_link.ps1
# Enter target when prompted: e.g. 8.8.8.8 or internal.server.sap
```

**Output:** `NetworkDiagnosticsForLink<timestamp>.txt`

> `test1.ps1` is functionally identical to `user_input_link.ps1`.

---

### 6. `test.ps1`

Tests UDP ports 500 and 4500 against a hardcoded VPN gateway IP (`137.83.231.72`). These are the standard IPSec/IKE ports used by enterprise VPNs.

**Usage:**
```powershell
.\test.ps1
```

Console output indicates whether each UDP port is reachable or blocked.

---

### 7. `Random_password_generator.ps1`

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

### 8. `ticket_remainder.ps1`

Sends a Windows system tray balloon notification + sound alert on a set interval to remind you to check the ticket queue. Runs in a loop until you press Ctrl+C.

**Default settings:** every 1 minute, title "Ticket Reminder", message "Check the ticket queue now."

**Usage:**
```powershell
.\ticket_remainder.ps1
```

To change the interval or message, edit the variables at the top of the script.

---

### 9. `Hourly_LM_email.ps1`

Opens the SAP LogicMonitor dashboard in your default browser and ensures Outlook is running, then logs each check. Runs on a recurring interval and shows balloon tip notifications.

**Usage:**
```powershell
.\Hourly_LM_email.ps1
```

**Log file:** `logic_monitor_logs/HourLogicMonitor.log`

---

## Directory Structure

```
Powershell_scripts/
├── VPN-HealthCheck.ps1                     # Full VPN diagnostic with HTML/JSON reports
├── Pulse_Check_network.ps1                 # Multi-target connectivity pulse check
├── gateway_external_link_test.ps1          # External link diagnostics (google.com)
├── Gateway_internal_link_test.ps1          # Internal link diagnostics (SAP host)
├── user_input_link.ps1                     # User-prompted diagnostics
├── test1.ps1                               # User-prompted diagnostics (duplicate)
├── test.ps1                                # VPN UDP port test
├── Random_password_generator.ps1           # Secure password generator
├── ticket_remainder.ps1                    # Ticket queue reminder
├── Hourly_LM_email.ps1                     # LogicMonitor + Outlook check
│
├── Internal_external_user_link_testing/    # Development/testing variants
│   ├── VPN-HealthCheck.ps1                 # Simplified VPN check (no reports)
│   ├── gateway_external_link_test.ps1
│   ├── Gateway_internal_link_test.ps1
│   ├── test_link.ps1
│   └── user_input_link.ps1                 # Enhanced version with error handling
│
├── Reports/                                # Auto-generated by VPN-HealthCheck.ps1
│   ├── VPN-HealthCheck-<timestamp>.html
│   └── VPN-HealthCheck-<timestamp>.json
│
└── logic_monitor_logs/
    └── HourLogicMonitor.log
```

---

## Output Files

| Script | Output File |
|--------|-------------|
| VPN-HealthCheck.ps1 | `Reports/VPN-HealthCheck-<timestamp>.html` + `.json` |
| gateway_external_link_test.ps1 | `NetworkDiagnosticsForExternalLink<timestamp>.txt` |
| Gateway_internal_link_test.ps1 | `NetworkDiagnosticsForInternalLink<timestamp>.txt` |
| user_input_link.ps1 / test1.ps1 | `NetworkDiagnosticsForLink<timestamp>.txt` |
| Hourly_LM_email.ps1 | `logic_monitor_logs/HourLogicMonitor.log` |
| Pulse_Check_network.ps1 | Console only |
| Random_password_generator.ps1 | Console only |
| ticket_remainder.ps1 | Console only |
| test.ps1 | Console only |

---

## Running Scripts

PowerShell may block scripts from running if the execution policy is restricted. To allow local scripts:

```powershell
# Check current policy
Get-ExecutionPolicy

# Allow local scripts (run as Administrator)
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
