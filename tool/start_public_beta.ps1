param([int]$PublicPort = 8000, [int]$AdminPort = 8001)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$backendRoot = Join-Path $projectRoot "backend"
$runtimeRoot = Join-Path $backendRoot "runtime"
$pythonPath = Join-Path $backendRoot ".venv\Scripts\python.exe"
$envPath = Join-Path $backendRoot ".env"
$localCloudflared = Join-Path $PSScriptRoot "bin\cloudflared.exe"
$cloudflaredCommand = Get-Command cloudflared -ErrorAction SilentlyContinue
$cloudflared = if ($cloudflaredCommand) { $cloudflaredCommand.Source } elseif (Test-Path -LiteralPath $localCloudflared) { $localCloudflared } else { $null }

if (-not (Test-Path -LiteralPath $pythonPath)) { throw "Backend virtual environment not found." }
if (-not (Test-Path -LiteralPath $envPath)) { throw "backend/.env not found." }
if (-not $cloudflared) { throw "cloudflared not found. Install the official release first." }
New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null

# Load local secrets into this process without printing them.
foreach ($rawLine in Get-Content -LiteralPath $envPath -Encoding UTF8) {
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) { continue }
    $separator = $line.IndexOf("=")
    $name = $line.Substring(0, $separator).Trim()
    $value = $line.Substring($separator + 1).Trim()
    [Environment]::SetEnvironmentVariable($name, $value, "Process")
}

Push-Location $backendRoot
try {
    & $pythonPath -m app.backup_database --destination (Join-Path $backendRoot "backups") --keep 14
    $public = Start-Process -FilePath $pythonPath -ArgumentList @("-m","uvicorn","app.public_main:app","--host","127.0.0.1","--port","$PublicPort","--env-file",".env") -WorkingDirectory $backendRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $runtimeRoot "public.out.log") -RedirectStandardError (Join-Path $runtimeRoot "public.err.log")
    $admin = Start-Process -FilePath $pythonPath -ArgumentList @("-m","uvicorn","app.admin_main:app","--host","127.0.0.1","--port","$AdminPort","--env-file",".env") -WorkingDirectory $backendRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $runtimeRoot "admin.out.log") -RedirectStandardError (Join-Path $runtimeRoot "admin.err.log")
    $apiReady = $false
    foreach ($attempt in 1..30) {
        Start-Sleep -Milliseconds 500
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$PublicPort/api/v1/health" -TimeoutSec 2
            if ($health.status -eq "ok") { $apiReady = $true; break }
        } catch { }
    }
    if (-not $apiReady) { throw "Public API failed. See backend/runtime/public.err.log." }
    $tunnelOut = Join-Path $runtimeRoot "tunnel.out.log"
    $tunnelErr = Join-Path $runtimeRoot "tunnel.err.log"
    $tunnel = Start-Process -FilePath $cloudflared -ArgumentList @("tunnel","--url","http://127.0.0.1:$PublicPort","--no-autoupdate") -WorkingDirectory $backendRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput $tunnelOut -RedirectStandardError $tunnelErr
    @{public=$public.Id;admin=$admin.Id;tunnel=$tunnel.Id} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runtimeRoot "processes.json") -Encoding UTF8
    $deadline = (Get-Date).AddSeconds(30); $url = $null
    while ((Get-Date) -lt $deadline -and -not $url) {
        Start-Sleep -Milliseconds 500
        $tunnelLogs = @($tunnelOut, $tunnelErr) | Where-Object { Test-Path -LiteralPath $_ }
        if ($tunnelLogs.Count -gt 0) {
            $match = Select-String -Path $tunnelLogs -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' | Select-Object -Last 1
            if ($match) { $url = $match.Matches[0].Value }
        }
    }
    if (-not $url) { throw "Tunnel timed out. See backend/runtime/tunnel.err.log." }
    Write-Host "Public beta URL: $url" -ForegroundColor Green
    Write-Host "Local admin: http://127.0.0.1:$AdminPort/admin" -ForegroundColor Cyan
    Write-Host "Enter the public URL in App settings. It changes after tunnel restart."
}
catch {
    foreach ($process in @($public, $admin, $tunnel)) {
        if ($null -ne $process) { Stop-Process -Id $process.Id -ErrorAction SilentlyContinue }
    }
    throw
}
finally { Pop-Location }
