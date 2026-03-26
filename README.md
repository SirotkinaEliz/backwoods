# Backwoods

Кастомный iOS клиент Telegram со встроенным WireGuard VPN туннелем.

## Описание

Backwoods — это форк [Telegram-iOS](https://github.com/nicegram/nicegram-ios) со встроенным WireGuard VPN туннелем. Весь трафик приложения автоматически проходит через VPN сервер, без необходимости настройки прокси пользователем.

## Ключевые возможности

- 🔒 **Полный VPN туннель** — NEPacketTunnelProvider, весь трафик через WireGuard
- 🔄 **Автоподключение** — туннель запускается при старте приложения
- 🛡️ **Kill-switch** — `includeAllNetworks = true`, трафик без VPN блокируется
- 📱 **Работа в фоне** — `disconnectOnSleep = false`, VPN не отключается
- 🔁 **Автопереподключение** — при смене WiFi ↔ LTE, с exponential backoff
- 📊 **Статус в UI** — зелёный/жёлтый/красный индикатор в навигации
- 🛠 **Экран отладки** — логи, статус, переподключение

## Архитектура

```
┌────────────────────────────────────────────────┐
│                 Telegram App                    │
│  ┌──────────┐ ┌──────────────┐ ┌────────────┐ │
│  │ TunnelUI │ │TunnelManager │ │ TunnelKit  │ │
│  └──────────┘ └──────┬───────┘ └──────┬─────┘ │
│                      │                │        │
│               ┌──────┴────────────────┴─────┐  │
│               │  BackwoodsTunnelBridge       │  │
│               └──────────────┬───────────────┘  │
│                              │ IPC              │
├──────────────────────────────┼──────────────────┤
│        PacketTunnel Extension│                  │
│  ┌───────────────────────────┴───────────────┐  │
│  │         PacketTunnelProvider               │  │
│  │  ┌─────────────────────────────────────┐  │  │
│  │  │        WireGuardTransport            │  │  │
│  │  │  ┌───────────────────────────────┐  │  │  │
│  │  │  │     WireGuardKit (Go)          │  │  │  │
│  │  │  └───────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────┘  │
└────────────────────────────────────────────────┘
          │
          │ WireGuard UDP
          ▼
┌────────────────────┐
│  VPN Server (NL)   │
│  WireGuard + NAT   │
└────────────────────┘
```

## Модули

| Модуль | Описание |
|--------|----------|
| `TunnelKit` | Протоколы, конфигурация, константы, логирование, IPC |
| `WireGuardTransport` | WireGuardKit обёртка, реализация TransportProvider |
| `PacketTunnel` | NEPacketTunnelProvider расширение (отдельный процесс) |
| `TunnelManager` | Управление VPN из основного приложения |
| `TunnelUI` | Статус индикатор, экран настроек, просмотр логов |

## Требования

- macOS 14+ (для сборки)
- Xcode 15.2+
- Bazel 8.4.2
- Go 1.22+ (для wireguard-go)
- iOS 15.0+ (на устройстве)
- Apple Developer Account ($99/год) ИЛИ TrollStore

## Быстрый старт

### 1. Клонирование

```bash
git clone --recursive https://github.com/YOUR_ORG/backwoods.git
cd backwoods
```

### 2. Настройка сервера

```bash
# На VPS в Нидерландах (Ubuntu 22.04)
scp server/setup-wireguard-server.sh root@YOUR_VPS:~/
ssh root@YOUR_VPS
chmod +x setup-wireguard-server.sh
sudo ./setup-wireguard-server.sh
```

### 3. Конфигурация клиента

```bash
# Скопируйте JSON конфигурацию с сервера
scp root@YOUR_VPS:/etc/wireguard/peers/json/peer-01.json Telegram/backwoods-tunnel.json
```

### 4. Сборка

```bash
# Собрать WireGuardKit
cd submodules/wireguard-apple
xcodebuild archive -scheme WireGuardKit \
  -destination "generic/platform=iOS" \
  -archivePath build/ios \
  SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES
xcodebuild -create-xcframework \
  -framework build/ios.xcarchive/Products/Library/Frameworks/WireGuardKit.framework \
  -output ../../third-party/WireGuardKit/WireGuardKit.xcframework
cd ../..

# Собрать IPA
python3 build-system/Make/Make.py \
  --cacheDir="$HOME/bazel-cache" \
  build \
  --configurationPath="build-system/appstore-configuration.json" \
  --buildNumber="$(date +%Y%m%d%H%M)" \
  --configuration=release_arm64
```

### 5. Установка

- **TrollStore**: Перенесите IPA на устройство, откройте в TrollStore
- **AltStore**: Установите через AltStore с Apple ID разработчика

## Тестирование

```bash
# Юнит-тесты
bazel test //Tests:TunnelKitTests
bazel test //Tests:TunnelManagerTests
bazel test //Tests:WireGuardTransportTests

# Все тесты
bazel test //Tests:all
```

## Структура файлов

```
backwoods/
├── .github/workflows/build.yml      # CI/CD
├── Telegram/
│   ├── PacketTunnel/                 # Network Extension
│   │   ├── PacketTunnelProvider.swift
│   │   ├── Info.plist
│   │   ├── Entitlements.plist
│   │   └── BUILD
│   ├── Backwoods-App-Entitlements.plist
│   ├── backwoods-tunnel.json         # WireGuard конфиг
│   ├── BUILD-PATCHES.md             # Инструкции для BUILD
│   └── INTEGRATION-PATCHES.swift    # Инструкции для AppDelegate
├── submodules/
│   ├── TunnelKit/                    # Ядро
│   │   ├── Sources/
│   │   │   ├── TransportProtocol.swift
│   │   │   ├── TransportConfiguration.swift
│   │   │   ├── TunnelConstants.swift
│   │   │   ├── TunnelLogger.swift
│   │   │   └── TunnelIPCCodec.swift
│   │   └── BUILD
│   ├── WireGuardTransport/           # WireGuard адаптер
│   │   ├── Sources/
│   │   │   └── WireGuardTransport.swift
│   │   └── BUILD
│   ├── TunnelManager/                # Управление VPN
│   │   ├── Sources/
│   │   │   ├── TunnelManager.swift
│   │   │   ├── TunnelManagerSignals.swift
│   │   │   └── BackwoodsTunnelBridge.swift
│   │   └── BUILD
│   ├── TunnelUI/                     # UI компоненты
│   │   ├── Sources/
│   │   │   ├── TunnelStatusView.swift
│   │   │   └── TunnelSettingsController.swift
│   │   └── BUILD
│   └── SwiftSignalKitTestHelpers/    # Тестовые утилиты
│       ├── Sources/
│       │   ├── SignalTestHelpers.swift
│       │   └── MockImplementations.swift
│       └── BUILD
├── Tests/
│   ├── TunnelKitTests/
│   ├── TunnelManagerTests/
│   ├── WireGuardTransportTests/
│   └── BUILD
├── third-party/
│   └── WireGuardKit/
│       └── BUILD                     # XCFramework import
├── server/
│   └── setup-wireguard-server.sh     # Скрипт настройки VPN сервера
└── README.md
```

## Безопасность

- Приватные ключи WireGuard **никогда** не логируются
- Конфигурация хранится в iOS Keychain через App Groups
- Kill-switch блокирует трафик при отключённом VPN
- PresharedKey для дополнительной защиты от квантовых атак
- Логи автоматически ротируются (макс. 5 МБ)

## Ограничения Phase 1

- WireGuard трафик без обфускации (DPI может обнаружить)
- Один сервер (Нидерланды)
- Нет удалённого обновления конфигурации
- Нет UI для ввода конфигурации (только embedded)

## Roadmap

- **Phase 2**: Обфускация (wstunnel / shadowsocks transport)
- **Phase 3**: Удалённая ротация ключей
- **Phase 4**: Мультисервер с GeoDNS
- **Phase 5**: Полноценное админ-приложение

## Лицензия

GPLv2 (следует лицензии Telegram-iOS)
