# Dark Wish Bot

Telegram-бот с ежедневными саркастичными пожеланиями и комплиментами.

## Возможности

- Ежедневная рассылка пожеланий с чёрным юмором
- `/wish` — пожелание по запросу
- `/compliment` — саркастичный комплимент (для одного пользователя — без сарказма)
- `/start` / `/stop` — подписка и отписка

## Запуск

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# заполни TELEGRAM_BOT_TOKEN и EXCLUDED_USER_ID
python bot.py
```

## Переменные окружения

| Переменная | Описание |
|---|---|
| `TELEGRAM_BOT_TOKEN` | Токен от @BotFather |
| `DAILY_TIME` | Время рассылки, например `09:00` |
| `TIMEZONE` | Часовой пояс, например `Europe/Moscow` |
| `EXCLUDED_USER_ID` | ID пользователя без саркастичных комплиментов |
