# GLUSH

Telegram со встроенным WireGuard VPN. Устанавливается на iPhone без App Store и **без компьютера**.

---

## Установка на iPhone (iOS 1626, без ПК, бесплатно)

### Шаг 1  Установи Scarlet

1. На iPhone открой **Safari** (только Safari, не Chrome)
2. Перейди на **usescarlet.com**
3. Нажми кнопку **Install**  появится предложение установить профиль
4. Нажми **Разрешить**  затем **Установить**
5. Перейди в **Настройки  Основные  VPN и управление устройством**
6. Найди сертификат Scarlet  нажми **Доверять**  **Доверять**
7. Открой приложение **Scarlet**  оно появится на рабочем столе

### Шаг 2  Добавь источник GLUSH

1. В Scarlet нажми вкладку **Sources** (или Repo / Добавить источник)
2. Нажми **+**  вставь адрес:
   \\\
   https://sirotkinaeliz.github.io/backwoods/apps.json
   \\\
3. Нажми **Add**

### Шаг 3  Установи GLUSH

1. В списке найди **GLUSH**
2. Нажми **Get** или **Install**
3. Подожди ~1 минуту

### Шаг 4  Запусти GLUSH

1. Открой GLUSH с рабочего стола
2. На запрос **Добавить конфигурацию VPN**  нажми **Разрешить**
3. VPN включится автоматически  готово 

---

## Важно знать

Scarlet (бесплатный) использует общие сертификаты. Apple иногда отзывает их  примерно раз в 13 месяца.
**Если приложение перестало открываться:**
1. Зайди снова на **usescarlet.com**  переустанови Scarlet
2. Открой Scarlet  найди GLUSH  нажми **Reinstall**

Это занимает 2 минуты, компьютер не нужен.

---

## Ссылки

- **Скачать IPA напрямую:** https://github.com/SirotkinaEliz/backwoods/releases/latest
- **Страница установки:** https://sirotkinaeliz.github.io/backwoods/
- **Source для Scarlet/AltStore:** https://sirotkinaeliz.github.io/backwoods/apps.json

---

## Техническое

- Форк Telegram-iOS release-12.0
- WireGuard через wireguard-go + wireguard-apple
- Сборка: GitHub Actions, Xcode 16.4, Bazel, iOS 18.5 SDK
- Bundle ID: ph.telegra.Telegraph
- Лицензия: GPLv2
