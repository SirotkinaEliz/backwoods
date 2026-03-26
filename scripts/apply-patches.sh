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
python3 << 'PYTHON_PATCH_SCRIPT'
import re
import sys

build_file = sys.argv[1] if len(sys.argv) > 1 else "Telegram/BUILD"

# Читаем файл
with open("TELEGRAM_BUILD_PATH", "r") as f:
    content = f.read()

# --- PATCH A: Добавить TUNNEL_DEPS в начало файла ---
tunnel_deps_block = '''
# Backwoods: VPN Tunnel dependencies
TUNNEL_DEPS = [
    "//submodules/TunnelKit:TunnelKit",
    "//submodules/TunnelManager:TunnelManager",
    "//submodules/TunnelUI:TunnelUI",
]

'''

# Вставляем после первых load() statements
load_pattern = r'(load\([^)]+\)\n)+'
match = re.search(load_pattern, content)
if match:
    insert_pos = match.end()
    content = content[:insert_pos] + tunnel_deps_block + content[insert_pos:]
else:
    # Если нет load(), вставляем в начало
    content = tunnel_deps_block + content

# --- PATCH B: Добавить PacketTunnel extension в ios_application ---
# Ищем блок extensions = [...] в ios_application
extensions_pattern = r'(extensions\s*=\s*\[)'
content = re.sub(
    extensions_pattern,
    r'\1\n        "//Telegram/PacketTunnel:PacketTunnelExtension",  # Backwoods VPN',
    content,
    count=1
)

# --- PATCH C: Добавить TUNNEL_DEPS к deps ios_application ---
# Ищем закрывающую ] deps в ios_application и добавляем + TUNNEL_DEPS
# Это сложнее, используем другой подход — добавляем в конец deps списка
deps_pattern = r'(\s+deps\s*=\s*\[[^\]]*)(,?\s*\])'
def add_tunnel_deps(match):
    deps_content = match.group(1)
    closing = match.group(2)
    # Добавляем перед закрывающей ]
    return deps_content + ',\n    ] + TUNNEL_DEPS  # Backwoods'

# Применяем только к первому вхождению deps в ios_application контексте
content_modified = False
lines = content.split('\n')
in_ios_app = False
brace_depth = 0
result_lines = []

for i, line in enumerate(lines):
    if 'ios_application(' in line:
        in_ios_app = True
        brace_depth = 0
    
    if in_ios_app:
        brace_depth += line.count('(') - line.count(')')
        if brace_depth <= 0 and in_ios_app and i > 0:
            in_ios_app = False
    
    # Добавляем TUNNEL_DEPS после deps блока в ios_application
    if in_ios_app and not content_modified and 'deps = [' in line:
        # Ищем конец deps блока
        j = i
        while j < len(lines) and ']' not in lines[j].split('deps')[0] if 'deps' in lines[j] else ']' not in lines[j]:
            j += 1
        if j < len(lines) and ']' in lines[j]:
            lines[j] = lines[j].replace('],', '] + TUNNEL_DEPS,  # Backwoods')
            lines[j] = lines[j].replace('])', '] + TUNNEL_DEPS)  # Backwoods')
            content_modified = True
    
    result_lines.append(line)

if content_modified:
    content = '\n'.join(lines)

# --- PATCH D: Добавить filegroup для ресурсов Backwoods ---
backwoods_resources = '''
# Backwoods: Embedded tunnel configuration
filegroup(
    name = "BackwoodsResources",
    srcs = [
        "backwoods-tunnel.json",
    ],
    visibility = ["//visibility:public"],
)
'''

content += '\n' + backwoods_resources

# Записываем результат
with open("TELEGRAM_BUILD_PATH", "w") as f:
    f.write(content)

print("  ✅ BUILD файл пропатчен")
PYTHON_PATCH_SCRIPT

# Заменяем placeholder на реальный путь и запускаем
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
