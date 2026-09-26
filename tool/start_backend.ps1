param(
    [ValidateRange(1, 65535)]
    [int]$Port = 8000
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$backendRoot = Join-Path $projectRoot "backend"
$pythonPath = Join-Path $backendRoot ".venv\Scripts\python.exe"
$envPath = Join-Path $backendRoot ".env"

if (-not (Test-Path -LiteralPath $pythonPath)) {
    throw "未找到后端虚拟环境，请先按照 backend/README.md 完成安装。"
}
if (-not (Test-Path -LiteralPath $envPath)) {
    throw "未找到 backend/.env，请先复制 .env.example 并填写配置。"
}

# 只把本机配置加载到当前进程，不输出任何密钥内容。
foreach ($rawLine in Get-Content -LiteralPath $envPath -Encoding UTF8) {
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) {
        continue
    }
    $separator = $line.IndexOf("=")
    $name = $line.Substring(0, $separator).Trim()
    $value = $line.Substring($separator + 1).Trim()
    [Environment]::SetEnvironmentVariable($name, $value, "Process")
}

Push-Location $backendRoot
try {
    Write-Host "Circuit Solver 后端已启动：http://0.0.0.0:$Port"
    Write-Host "请保持此窗口开启；真机需填写电脑局域网IP，不能填写 localhost。"
    & $pythonPath -m uvicorn app.main:app --host 0.0.0.0 --port $Port
}
finally {
    Pop-Location
}
