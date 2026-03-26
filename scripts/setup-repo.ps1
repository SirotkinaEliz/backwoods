# ==============================================================================
# Backwoods: Подготовка репозитория (Windows PowerShell)
# ==============================================================================
# Этот скрипт подготавливает Git репозиторий для push на GitHub.
# После push, GitHub Actions автоматически соберёт IPA.
#
# Использование:
#   .\scripts\setup-repo.ps1
#
# Требования:
#   - Git установлен (git --version)
#   - Аккаунт GitHub
# ==============================================================================

param(
    [string]$GitHubRepo = "",
    [switch]$SkipGitInit = $false
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  Backwoods: Подготовка репозитория" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# Проверка Git
try {
    $gitVersion = git --version
    Write-Host "  Git: $gitVersion" -ForegroundColor Green
} catch {
    Write-Host "  ❌ Git не установлен!" -ForegroundColor Red
    Write-Host "  Скачайте: https://git-scm.com/download/win" -ForegroundColor Yellow
    exit 1
}

# Определяем корневую папку проекта
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Write-Host "  Папка проекта: $ProjectRoot" -ForegroundColor Gray
Set-Location $ProjectRoot

# Инициализация Git (если нужно)
if (-not $SkipGitInit) {
    if (-not (Test-Path ".git")) {
        Write-Host ""
        Write-Host ">>> Шаг 1: Инициализация Git репозитория..." -ForegroundColor Yellow
        git init
        git branch -M main
        Write-Host "  ✅ Git репозиторий создан" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host ">>> Шаг 1: Git репозиторий уже существует" -ForegroundColor Green
    }
}

# Создание .gitignore
Write-Host ""
Write-Host ">>> Шаг 2: Создание .gitignore..." -ForegroundColor Yellow

$gitignore = @"
# Backwoods .gitignore

# macOS
.DS_Store
*.xcworkspace
*.xcuserdata
xcuserdata/
DerivedData/

# Bazel
bazel-*
.bazelrc.local

# Build outputs
build/
*.ipa
*.app

# IDE
.idea/
.vscode/settings.json
*.swp
*.swo

# Keys (НИКОГДА не коммитьте реальные ключи!)
*.p12
*.mobileprovision
*.pem

# Но шаблон конфигурации коммитим
!Telegram/backwoods-tunnel.json

# Go
vendor/

# Xcode
*.pbxuser
*.mode1v3
*.mode2v3
*.perspectivev3
*.xccheckout
*.moved-aside

# Temp
*.tmp
*.log
"@

Set-Content -Path ".gitignore" -Value $gitignore -Encoding UTF8
Write-Host "  ✅ .gitignore создан" -ForegroundColor Green

# Проверка структуры файлов
Write-Host ""
Write-Host ">>> Шаг 3: Проверка файлов проекта..." -ForegroundColor Yellow

$requiredFiles = @(
    ".github\workflows\build.yml",
    "scripts\apply-patches.sh",
    "submodules\TunnelKit\BUILD",
    "submodules\TunnelKit\Sources\TransportProtocol.swift",
    "submodules\TunnelKit\Sources\TransportConfiguration.swift",
    "submodules\TunnelKit\Sources\TunnelConstants.swift",
    "submodules\TunnelKit\Sources\TunnelLogger.swift",
    "submodules\TunnelKit\Sources\TunnelIPCCodec.swift",
    "submodules\WireGuardTransport\BUILD",
    "submodules\WireGuardTransport\Sources\WireGuardTransport.swift",
    "submodules\TunnelManager\BUILD",
    "submodules\TunnelManager\Sources\TunnelManager.swift",
    "submodules\TunnelManager\Sources\TunnelManagerSignals.swift",
    "submodules\TunnelManager\Sources\BackwoodsTunnelBridge.swift",
    "submodules\TunnelUI\BUILD",
    "submodules\TunnelUI\Sources\TunnelStatusView.swift",
    "submodules\TunnelUI\Sources\TunnelSettingsController.swift",
    "Telegram\PacketTunnel\PacketTunnelProvider.swift",
    "Telegram\PacketTunnel\Info.plist",
    "Telegram\PacketTunnel\Entitlements.plist",
    "Telegram\PacketTunnel\BUILD",
    "Telegram\Backwoods-App-Entitlements.plist",
    "Telegram\backwoods-tunnel.json",
    "third-party\WireGuardKit\BUILD",
    "Tests\BUILD",
    "server\setup-wireguard-server.sh",
    "README.md"
)

$missing = @()
$found = 0

foreach ($file in $requiredFiles) {
    if (Test-Path $file) {
        $found++
    } else {
        $missing += $file
        Write-Host "  ❌ Не найден: $file" -ForegroundColor Red
    }
}

Write-Host "  Найдено: $found / $($requiredFiles.Count) файлов" -ForegroundColor $(if ($missing.Count -eq 0) { "Green" } else { "Yellow" })

if ($missing.Count -gt 0) {
    Write-Host "  ⚠️  Отсутствуют $($missing.Count) файл(ов)" -ForegroundColor Yellow
    Write-Host "  Убедитесь, что все модули были созданы." -ForegroundColor Yellow
}

# Добавление файлов в Git
Write-Host ""
Write-Host ">>> Шаг 4: Добавление файлов в Git..." -ForegroundColor Yellow

git add -A
$stagedFiles = (git diff --cached --name-only | Measure-Object -Line).Lines
Write-Host "  Файлов в staging: $stagedFiles" -ForegroundColor Green

# Первый коммит
Write-Host ""
Write-Host ">>> Шаг 5: Создание коммита..." -ForegroundColor Yellow

git commit -m "feat: Backwoods VPN tunnel - initial implementation

- TunnelKit: protocols, configuration, constants, logger, IPC
- WireGuardTransport: WireGuardKit adapter
- PacketTunnel: NEPacketTunnelProvider extension
- TunnelManager: VPN lifecycle, signals, bridge
- TunnelUI: status indicator, settings, logs viewer
- Tests: unit tests for all modules
- CI/CD: GitHub Actions automated build
- Server: WireGuard setup script" 2>$null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✅ Коммит создан" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Коммит уже существует или нечего коммитить" -ForegroundColor Yellow
}

# Настройка remote
Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  ✅ Репозиторий готов!" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Следующие шаги:" -ForegroundColor White
Write-Host ""
Write-Host "  1. Создайте репозиторий на GitHub:" -ForegroundColor White
Write-Host "     https://github.com/new" -ForegroundColor Blue
Write-Host "     Имя: backwoods (приватный)" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Подключите remote:" -ForegroundColor White
Write-Host "     git remote add origin https://github.com/ВАШЕ_ИМЯ/backwoods.git" -ForegroundColor Cyan
Write-Host ""
Write-Host "  3. Запушьте:" -ForegroundColor White
Write-Host "     git push -u origin main" -ForegroundColor Cyan
Write-Host ""
Write-Host "  4. Добавьте секрет TUNNEL_CONFIG_JSON:" -ForegroundColor White
Write-Host "     GitHub → Settings → Secrets → Actions → New secret" -ForegroundColor Gray
Write-Host "     Имя:      TUNNEL_CONFIG_JSON" -ForegroundColor Gray
Write-Host "     Значение:  содержимое peer-XX.json с сервера" -ForegroundColor Gray
Write-Host ""
Write-Host "  5. Запустите сборку:" -ForegroundColor White
Write-Host "     GitHub → Actions → Build Backwoods IPA → Run workflow" -ForegroundColor Gray
Write-Host ""
Write-Host "  6. Скачайте IPA:" -ForegroundColor White
Write-Host "     GitHub → Actions → последний запуск → Artifacts → Backwoods-xxx" -ForegroundColor Gray
Write-Host ""
Write-Host "  Подробная инструкция: см. ИНСТРУКЦИЯ.md" -ForegroundColor Yellow
Write-Host ""
