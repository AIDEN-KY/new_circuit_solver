param([Parameter(Mandatory=$true)][string]$BackupPath, [switch]$Apply)
$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$backendRoot = Join-Path $projectRoot "backend"
$pythonPath = Join-Path $backendRoot ".venv\Scripts\python.exe"
$resolvedBackup = (Resolve-Path -LiteralPath $BackupPath).Path
Push-Location $backendRoot
try {
    & $pythonPath -m app.backup_database --verify $resolvedBackup
    if (-not $Apply) { Write-Host "仅完成校验。确认停止后端后，加 -Apply 才会恢复。"; exit 0 }
    $target = Join-Path $backendRoot "data\circuit_solver.db"
    $safety = "$target.before_restore_$(Get-Date -Format yyyyMMdd_HHmmss)"
    if (Test-Path -LiteralPath $target) { Copy-Item -LiteralPath $target -Destination $safety }
    Copy-Item -LiteralPath $resolvedBackup -Destination $target -Force
    & $pythonPath -m app.backup_database --verify $target
    Write-Host "数据库已恢复；恢复前副本：$safety"
}
finally { Pop-Location }
