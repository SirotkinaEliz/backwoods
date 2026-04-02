# GLUSH

Telegram с встроенным WireGuard VPN. Устанавливается на iPhone без App Store и без компьютера.

---

##  Установка на iPhone (без ПК, бесплатно)

### Что нужно знать заранее

| | SideStore |
|---|---|
| **iOS** | 16  26 |
| **Компьютер** |  Не нужен |
| **Стоимость** |  Бесплатно |
| **Переподписка** |  Автоматически каждые 7 дней |

---

## Шаг 1  Установи SideStore

> SideStore  это менеджер приложений, как App Store, но для IPA без Apple.

1. На iPhone открой **Safari** (именно Safari, не Chrome)
2. Зайди на **[sidestore.io](https://sidestore.io)**
3. Нажми кнопку **Install**  выбери способ установки
4. Разреши установку профиля: **Настройки  Основные  VPN и управление устройством  Доверять**
5. Открой приложение **SideStore**
6. При первом запуске SideStore попросит создать **пару**  нажми **Generate Pairing File** и следуй инструкции (это нужно один раз)

---

## Шаг 2  Добавь Source GLUSH в SideStore

1. В SideStore открой вкладку **Browse** (внизу)
2. Нажми **Sources**  кнопка **+** в правом верхнем углу
3. Вставь этот адрес:
   ```
   https://sirotkinaeliz.github.io/backwoods/apps.json
   ```
4. Нажми **Add Source**

---

## Шаг 3  Установи GLUSH

1. В списке приложений найди **GLUSH**
2. Нажми **Free**  **Install**
3. Дождись установки (~1 минута)

---

## Шаг 4  Запусти GLUSH

1. Открой **GLUSH** с главного экрана
2. При первом запуске появится запрос: **"GLUSH хочет добавить конфигурацию VPN"**  нажми **Разрешить**
3. VPN включится автоматически  в статусной строке появится иконка **VPN**
4. Готово   Telegram работает через зашифрованный туннель

---

## Автообновление

SideStore переподписывает GLUSH **автоматически каждые 7 дней** в фоне  ничего делать не нужно.

Когда выходит новая сборка GLUSH  в SideStore появится кнопка **Update**.

---

## Прямая ссылка на IPA

 **[Скачать GLUSH.ipa (последняя версия)](https://github.com/SirotkinaEliz/backwoods/releases/latest)**

---

## Частые вопросы

**Не появляется запрос VPN при первом запуске?**
Зайди в Настройки  Основные  VPN и управление устройством  GLUSH  Доверять  открой приложение заново.

**SideStore говорит "App expired"?**
Открой SideStore  нажми **Refresh All**  переподпишет.

**iOS 26  SideStore не работает?**
SideStore обновляется под новые iOS в течение 12 недель после релиза. Следи за обновлениями на [sidestore.io](https://sidestore.io).

**Можно без SideStore, прямо скачать IPA?**
Да, но для установки нужен будет Sideloadly на компьютере. Без компьютера  только через SideStore.

---

## Страница установки

 **[sirotkinaeliz.github.io/backwoods](https://sirotkinaeliz.github.io/backwoods)**

---

## Техническое

- Форк [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) `release-12.0`
- WireGuard через `wireguard-go` + `wireguard-apple`
- Сборка: GitHub Actions, Xcode 16.4, Bazel, iOS 18.5 SDK
- Bundle ID: `ph.telegra.Telegraph`
- Лицензия: GPLv2
