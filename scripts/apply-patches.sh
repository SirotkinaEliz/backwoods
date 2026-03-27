#!/bin/bash
# ==============================================================================
# Backwoods: Автоматический патч Telegram-iOS исходников
# ==============================================================================
# Этот скрипт запускается на macOS раннере в GitHub Actions.
# Он копирует модули Backwoods в дерево Telegram-iOS и патчит
# BUILD файлы + AppDelegate для интеграции VPN туннеля.
#
# Использование:
#   ./scripts/apply-patches.sh <telegram-ios-dir> <backwoods-dir>
#
# Пример:
#   ./scripts/apply-patches.sh ./telegram-ios ./backwoods
# ==============================================================================

set -euo pipefail

TELEGRAM_DIR="${1:?Ошибка: укажите путь к Telegram-iOS}"
BACKWOODS_DIR="${2:?Ошибка: укажите путь к Backwoods}"

echo "=============================================="
echo "  Backwoods Patch Script"
echo "  Telegram-iOS: $TELEGRAM_DIR"
echo "  Backwoods:    $BACKWOODS_DIR"
echo "=============================================="

# Проверка что Telegram-iOS существует
if [ ! -d "$TELEGRAM_DIR/Telegram" ]; then
    echo "❌ Ошибка: $TELEGRAM_DIR не похож на Telegram-iOS (нет папки Telegram/)"
    exit 1
fi

# ==============================================================================
# ШАГ 1: Копирование модулей Backwoods
# ==============================================================================
echo ""
echo ">>> Шаг 1: Копирование модулей..."

# Наши новые модули
for MODULE in TunnelKit WireGuardTransport TunnelManager TunnelUI SwiftSignalKitTestHelpers; do
    if [ -d "$BACKWOODS_DIR/submodules/$MODULE" ]; then
        echo "  Копирую: submodules/$MODULE"
        cp -r "$BACKWOODS_DIR/submodules/$MODULE" "$TELEGRAM_DIR/submodules/$MODULE"
    fi
done

# PacketTunnel расширение
echo "  Копирую: Telegram/PacketTunnel"
mkdir -p "$TELEGRAM_DIR/Telegram/PacketTunnel"
cp -r "$BACKWOODS_DIR/Telegram/PacketTunnel/"* "$TELEGRAM_DIR/Telegram/PacketTunnel/"

# Конфигурация туннеля
echo "  Копирую: backwoods-tunnel.json"
cp "$BACKWOODS_DIR/Telegram/backwoods-tunnel.json" "$TELEGRAM_DIR/Telegram/backwoods-tunnel.json"

# Entitlements
echo "  Копирую: Backwoods-App-Entitlements.plist"
cp "$BACKWOODS_DIR/Telegram/Backwoods-App-Entitlements.plist" "$TELEGRAM_DIR/Telegram/Backwoods-App-Entitlements.plist"

# Third-party (WireGuardKit BUILD)
echo "  Копирую: third-party/WireGuardKit"
mkdir -p "$TELEGRAM_DIR/third-party/WireGuardKit"
cp "$BACKWOODS_DIR/third-party/WireGuardKit/BUILD" "$TELEGRAM_DIR/third-party/WireGuardKit/BUILD"

# Тесты
echo "  Копирую: Tests/"
mkdir -p "$TELEGRAM_DIR/Tests"
cp -r "$BACKWOODS_DIR/Tests/"* "$TELEGRAM_DIR/Tests/"

echo "  ✅ Модули скопированы"

# ==============================================================================
# ШАГ 2: Патч Telegram/BUILD (основной BUILD файл приложения)
# ==============================================================================
echo ""
echo ">>> Шаг 2: Патч Telegram/BUILD..."

TELEGRAM_BUILD="$TELEGRAM_DIR/Telegram/BUILD"

if [ ! -f "$TELEGRAM_BUILD" ]; then
    echo "❌ Ошибка: $TELEGRAM_BUILD не найден"
    exit 1
fi

# Бэкап
cp "$TELEGRAM_BUILD" "$TELEGRAM_BUILD.backup"

# Патч через Python (надёжнее чем sed для сложных изменений)
PATCH_SCRIPT=$(mktemp)
cat << 'EOF' > "$PATCH_SCRIPT"
import re
import sys

build_path = sys.argv[1]

with open(build_path, "r") as f:
    content = f.read()

# PATCH A: Добавить TUNNEL_DEPS
tunnel_deps = '\n# Backwoods: VPN Tunnel dependencies\nTUNNEL_DEPS = [\n    "//submodules/TunnelKit:TunnelKit",\n    "//submodules/TunnelManager:TunnelManager",\n    "//submodules/TunnelUI:TunnelUI",\n]\n'

# Вставляем после load() блоков
load_matches = list(re.finditer(r'load\([^)]+\)\n', content))
if load_matches:
    insert_pos = load_matches[-1].end()
    content = content[:insert_pos] + tunnel_deps + content[insert_pos:]
else:
    content = tunnel_deps + content

# PATCH B: Добавить extension
if 'extensions = [' in content:
    content = content.replace(
        'extensions = [',
        'extensions = [\n        "//Telegram/PacketTunnel:PacketTunnelExtension",  # Backwoods VPN'
    )

# PATCH C: Добавить filegroup для ресурсов
resources_block = '''
# Backwoods: Embedded tunnel configuration
filegroup(
    name = "BackwoodsResources",
    srcs = [
        "backwoods-tunnel.json",
    ],
    visibility = ["//visibility:public"],
)
'''
content += resources_block

with open(build_path, "w") as f:
    f.write(content)

print("  ✅ Telegram/BUILD пропатчен")
EOF

python3 "$PATCH_SCRIPT" "$TELEGRAM_BUILD"
rm "$PATCH_SCRIPT"

# ==============================================================================
# ШАГ 3: Патч AppDelegate.swift
# ==============================================================================
echo ""
echo ">>> Шаг 3: Патч AppDelegate.swift..."

# Находим AppDelegate
APPDELEGATE=$(find "$TELEGRAM_DIR/Telegram" -name "AppDelegate.swift" -path "*/Telegram-iOS/*" | head -1)

if [ -z "$APPDELEGATE" ]; then
    # Пробуем другие пути
    APPDELEGATE=$(find "$TELEGRAM_DIR" -name "AppDelegate.swift" | head -1)
fi

if [ -z "$APPDELEGATE" ]; then
    echo "  ⚠️  AppDelegate.swift не найден — пропускаю (потребуется ручной патч)"
else
    echo "  Найден: $APPDELEGATE"
    cp "$APPDELEGATE" "$APPDELEGATE.backup"
    
    PATCH_SCRIPT2=$(mktemp)
    cat << 'EOF' > "$PATCH_SCRIPT2"
import sys

appdelegate_path = sys.argv[1]

with open(appdelegate_path, "r") as f:
    lines = f.readlines()

new_lines = []
import_added = False
init_added = False

for i, line in enumerate(lines):
    # Добавляем import TunnelManager после последнего import
    if not import_added and line.startswith("import ") and (i + 1 >= len(lines) or not lines[i + 1].startswith("import ")):
        new_lines.append(line)
        new_lines.append("import TunnelManager  // Backwoods VPN\n")
        import_added = True
        continue
    
    # Добавляем инициализацию туннеля в didFinishLaunchingWithOptions
    if not init_added and "didFinishLaunchingWithOptions" in line:
        new_lines.append(line)
        # Ищем открывающую скобку {
        j = i + 1
        while j < len(lines):
            new_lines.append(lines[j])
            if "{" in lines[j]:
                new_lines.append("\n")
                new_lines.append("        // Backwoods: Initialize VPN tunnel before anything else\n")
                new_lines.append("        BackwoodsTunnelBridge.shared.initialize()\n")
                new_lines.append("\n")
                init_added = True
                break
            j += 1
        continue
    
    new_lines.append(line)

# Если didFinishLaunching не найден, добавляем в конец класса
if not init_added:
    print("  ⚠️  didFinishLaunchingWithOptions не найден — добавляю инициализацию в init")
    # Попробуем найти init() или другую точку входа
    for i, line in enumerate(new_lines):
        if "override init()" in line or "required init" in line:
            # Находим следующую {
            for j in range(i, min(i + 5, len(new_lines))):
                if "{" in new_lines[j]:
                    new_lines.insert(j + 1, "\n        // Backwoods: Initialize VPN tunnel\n        BackwoodsTunnelBridge.shared.initialize()\n\n")
                    init_added = True
                    break
            break

with open(appdelegate_path, "w") as f:
    f.writelines(new_lines)

status = "✅" if (import_added and init_added) else "⚠️  частично"
print(f"  {status} AppDelegate.swift пропатчен (import: {import_added}, init: {init_added})")
EOF

    python3 "$PATCH_SCRIPT2" "$APPDELEGATE"
    rm "$PATCH_SCRIPT2"
fi

# ==============================================================================
# ШАГ 4: Обновить entitlements (добавить network extension capability)
# ==============================================================================
echo ""
echo ">>> Шаг 4: Настройка entitlements..."

# Находим существующие entitlements
EXISTING_ENTITLEMENTS=$(find "$TELEGRAM_DIR/Telegram" -name "*.entitlements" -not -path "*/PacketTunnel/*" | head -1)

if [ -n "$EXISTING_ENTITLEMENTS" ]; then
    echo "  Найден: $EXISTING_ENTITLEMENTS"
    cp "$EXISTING_ENTITLEMENTS" "$EXISTING_ENTITLEMENTS.backup"
    
    # Добавляем network extension entitlement через PlistBuddy
    if command -v /usr/libexec/PlistBuddy &> /dev/null; then
        /usr/libexec/PlistBuddy -c "Add :com.apple.developer.networking.networkextension array" "$EXISTING_ENTITLEMENTS" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Add :com.apple.developer.networking.networkextension:0 string packet-tunnel-provider" "$EXISTING_ENTITLEMENTS" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Add :com.apple.security.application-groups array" "$EXISTING_ENTITLEMENTS" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Add :com.apple.security.application-groups:0 string group.com.backwoods.app" "$EXISTING_ENTITLEMENTS" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Add :com.apple.developer.networking.vpn.api array" "$EXISTING_ENTITLEMENTS" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Add :com.apple.developer.networking.vpn.api:0 string allow-vpn" "$EXISTING_ENTITLEMENTS" 2>/dev/null || true
        echo "  ✅ Entitlements обновлены"
    else
        echo "  ⚠️  PlistBuddy не найден — используем Backwoods-App-Entitlements.plist"
    fi
else
    echo "  ⚠️  Существующие entitlements не найдены — используем Backwoods-App-Entitlements.plist"
fi

# ==============================================================================
# ШАГ 5: Добавить MockImplementations.swift (если не существует)
# ==============================================================================
echo ""
echo ">>> Шаг 5: Проверка mock-файлов..."

MOCK_FILE="$TELEGRAM_DIR/submodules/SwiftSignalKitTestHelpers/Sources/MockImplementations.swift"
if [ ! -f "$MOCK_FILE" ]; then
    echo "  ⚠️  MockImplementations.swift отсутствует — создаю..."
    mkdir -p "$(dirname "$MOCK_FILE")"
    cat > "$MOCK_FILE" << 'SWIFT_MOCK'
import Foundation
import TunnelKit
import SwiftSignalKit

// Backwoods: Mock implementations for testing

public final class MockPacketTunnelProvider: PacketTunnelProviding {
    public var setSettingsCallCount = 0
    public var cancelCallCount = 0
    public var reassertCallCount = 0
    
    public init() {}
    
    public func setTunnelNetworkSettings(_ tunnelNetworkSettings: Any?, completionHandler: ((Error?) -> Void)?) {
        setSettingsCallCount += 1
        completionHandler?(nil)
    }
    
    public func cancelTunnelWithError(_ error: Error?) {
        cancelCallCount += 1
    }
    
    public func reasserting(_ reasserting: Bool) {
        reassertCallCount += 1
    }
}

public final class MockTransportProvider: TransportProvider {
    public var transportIdentifier: String = "mock"
    public var currentStatus: TransportStatus = .disconnected
    public var startCallCount = 0
    public var stopCallCount = 0
    
    public init() {}
    
    public func start(provider: PacketTunnelProviding, configuration: TransportConfiguration) -> Signal<TransportStatus, TransportError> {
        startCallCount += 1
        return Signal { [weak self] subscriber in
            self?.currentStatus = .connecting
            subscriber.putNext(.connecting)
            
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                self?.currentStatus = .connected
                subscriber.putNext(.connected)
                subscriber.putCompletion()
            }
            
            return ActionDisposable {
                self?.currentStatus = .disconnected
            }
        }
    }
    
    public func stop() -> Signal<Void, TransportError> {
        stopCallCount += 1
        currentStatus = .disconnected
        return Signal { subscriber in
            subscriber.putNext(Void())
            subscriber.putCompletion()
            return EmptyDisposable
        }
    }
    
    public func handleAppMessage(_ data: Data) -> Signal<Data, TransportError> {
        return Signal { subscriber in
            subscriber.putNext(Data())
            subscriber.putCompletion()
            return EmptyDisposable
        }
    }
}

public final class MockVPNConnection: VPNConnectionProviding {
    public enum MockVPNStatus: Int {
        case invalid = 0
        case disconnected = 1
        case connecting = 2
        case connected = 3
        case reasserting = 4
        case disconnecting = 5
    }
    
    public var status: Int = MockVPNStatus.disconnected.rawValue
    public var startCallCount = 0
    public var stopCallCount = 0
    public var sendMessageCallCount = 0
    public var sendMessageResponse: Data?
    
    public init() {}
    
    public func startVPNTunnel() throws {
        startCallCount += 1
        status = MockVPNStatus.connecting.rawValue
    }
    
    public func stopVPNTunnel() {
        stopCallCount += 1
        status = MockVPNStatus.disconnecting.rawValue
    }
    
    public func sendProviderMessage(_ messageData: Data, responseHandler: ((Data?) -> Void)?) throws {
        sendMessageCallCount += 1
        responseHandler?(sendMessageResponse)
    }
}
SWIFT_MOCK
    echo "  ✅ MockImplementations.swift создан"
else
    echo "  ✓ MockImplementations.swift уже существует"
fi

# ==============================================================================
# ШАГ 6: Патч BrowserUI — замена приватных Bitbucket пакетов заглушками
# ==============================================================================
echo ""
echo ">>> Шаг 6: Патч BrowserUI (замена приватных Bitbucket пакетов)..."

cd "$TELEGRAM_DIR"

# 6a. Создаём заглушки NGCore и NicegramWallet
mkdir -p submodules/BrowserUI/Stubs

cat > submodules/BrowserUI/Stubs/NGCore.swift << 'SWIFT_NGCORE'
// Backwoods: stub replacement for NGCore (private Bitbucket package)
public enum UrlUtils {
    public static func refersToNicegramApplication(_ url: String) -> Bool {
        return false
    }
}
SWIFT_NGCORE

cat > submodules/BrowserUI/Stubs/NicegramWallet.swift << 'SWIFT_WALLET'
// Backwoods: stub replacement for NicegramWallet (private Bitbucket package)
import WebKit

public class WalletJsInjector {
    public init() {}
    public func inject(in webView: WKWebView, injectTonJs: Bool, currentChain: @escaping () -> Any?) {}
    public func handle(url: String) -> Bool { return false }
}
SWIFT_WALLET

echo "  ✅ Stub файлы созданы (NGCore, NicegramWallet)"

# 6b. Патч submodules/BrowserUI/BUILD — заменяем внешние deps на локальные стабы
BUILD_PATCH=$(mktemp)
cat << 'PYEOF' > "$BUILD_PATCH"
import sys

with open(sys.argv[1], 'r') as f:
    content = f.read()

old = 'NGDEPS = [\n    "@swiftpkg_nicegram_assistant_ios//:NGCore",\n    "@swiftpkg_nicegram_wallet_ios//:NicegramWallet",\n]'

new = '''swift_library(
    name = "NGCoreStub",
    module_name = "NGCore",
    srcs = ["Stubs/NGCore.swift"],
    visibility = ["//visibility:private"],
)

swift_library(
    name = "NicegramWalletStub",
    module_name = "NicegramWallet",
    srcs = ["Stubs/NicegramWallet.swift"],
    sdk_frameworks = ["WebKit"],
    visibility = ["//visibility:private"],
)

NGDEPS = [
    ":NGCoreStub",
    ":NicegramWalletStub",
]'''

if old in content:
    content = content.replace(old, new)
    with open(sys.argv[1], 'w') as f:
        f.write(content)
    print("  BrowserUI/BUILD пропатчен OK")
else:
    print("  WARN: BrowserUI/BUILD шаблон NGDEPS не найден — пробуем fuzzy...")
    # Попробуем найти по отдельным строкам
    import re
    pattern = r'NGDEPS\s*=\s*\[.*?swiftpkg_nicegram.*?\]'
    if re.search(pattern, content, re.DOTALL):
        content = re.sub(pattern, new, content, flags=re.DOTALL)
        with open(sys.argv[1], 'w') as f:
            f.write(content)
        print("  BrowserUI/BUILD пропатчен (fuzzy) OK")
    else:
        print("  WARN: BrowserUI/BUILD NGDEPS не найден — пропускаем")
PYEOF

python3 "$BUILD_PATCH" "submodules/BrowserUI/BUILD"
rm "$BUILD_PATCH"

# 6c. Удаляем приватные Bitbucket пакеты из Package.resolved
PKG_PATCH=$(mktemp)
cat << 'PYEOF' > "$PKG_PATCH"
import json

with open('Package.resolved') as f:
    data = json.load(f)

private_ids = {'nicegram-assistant-ios', 'nicegram-wallet-ios'}
before = len(data['pins'])
data['pins'] = [p for p in data['pins'] if p.get('identity') not in private_ids]
after = len(data['pins'])

with open('Package.resolved', 'w') as f:
    json.dump(data, f, indent=2)

print(f"  Package.resolved: удалено {before - after} приватных пакетов (осталось {after})")
PYEOF

python3 "$PKG_PATCH"
rm "$PKG_PATCH"

# 6d. Убираем nicegram-assistant-ios из Package.swift
sed -i '' '/mobyrix\/nicegram-assistant-ios/d' Package.swift
# Убираем пустые скобки если package dependencies стал пустым
python3 - << 'PYEOF'
with open('Package.swift') as f:
    content = f.read()
# Если dependencies: [ <пусто> ], упрощаем
import re
content = re.sub(r'dependencies:\s*\[\s*\]', 'dependencies: []', content)
with open('Package.swift', 'w') as f:
    f.write(content)
print("  Package.swift очищен OK")
PYEOF

# 6e. Убираем из MODULE.bazel use_repo()
sed -i '' '/"swiftpkg_nicegram_assistant_ios"/d' MODULE.bazel
sed -i '' '/"swiftpkg_nicegram_wallet_ios"/d' MODULE.bazel
echo "  MODULE.bazel очищен OK"

cd - > /dev/null
echo ">>> Шаг 6 завершён ✅"

# ==============================================================================
# ГОТОВО
# ==============================================================================
echo ""
echo "=============================================="
echo "  ✅ Все патчи применены!"
echo "=============================================="
echo ""
echo "  Изменённые файлы:"
echo "    - Telegram/BUILD"
echo "    - AppDelegate.swift"
echo "    - Entitlements"
echo "  Добавленные модули:"
echo "    - submodules/TunnelKit"
echo "    - submodules/WireGuardTransport"
echo "    - submodules/TunnelManager"
echo "    - submodules/TunnelUI"
echo "    - submodules/SwiftSignalKitTestHelpers"
echo "    - Telegram/PacketTunnel"
echo "    - third-party/WireGuardKit"
echo "    - Tests/"
echo ""
