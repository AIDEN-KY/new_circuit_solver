$projectRoot = Split-Path -Parent $PSScriptRoot
$processFile = Join-Path $projectRoot "backend\runtime\processes.json"
if (-not (Test-Path -LiteralPath $processFile)) { Write-Host "未发现运行记录。"; exit 0 }
$items = Get-Content -LiteralPath $processFile -Raw | ConvertFrom-Json
foreach ($name in @("public","admin","tunnel")) {
    $processId = [int]$items.$name
    if ($processId -gt 0) { Stop-Process -Id $processId -ErrorAction SilentlyContinue }
}
Remove-Item -LiteralPath $processFile -Force
Write-Host "Circuit Solver 公网测试服务已停止。"
