#!/bin/bash
set -euo pipefail

BOT_DIR="${1:-/home/ec2-user/WishesBot/dark-wish-bot}"
PIP_MIRROR="-i https://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com"

echo "==> Папка бота: $BOT_DIR"
cd "$BOT_DIR"

echo "==> Бэкап"
ts=$(date +%s)
cp -a bot.py "bot.py.bak.$ts" 2>/dev/null || true
cp -a wishes.py "wishes.py.bak.$ts" 2>/dev/null || true
cp -a .env ".env.bak.$ts" 2>/dev/null || true

echo "==> Запись bot.py"
cat > bot.py <<'EOF'
#!/usr/bin/env python3
"""Telegram-бот с ежедневными саркастичными пожеланиями."""

import asyncio
import logging
import os
from datetime import time
from typing import Optional
from zoneinfo import ZoneInfo

from dotenv import load_dotenv
from telegram import Update
from telegram.ext import (
    Application,
    CommandHandler,
    ContextTypes,
)
from telegram.request import HTTPXRequest

from storage import add_subscriber, get_subscribers, remove_subscriber
from wishes import generate_compliment, generate_genuine_compliment, generate_wish

load_dotenv()

logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger(__name__)

TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
DAILY_TIME = os.getenv("DAILY_TIME", "09:00")
TIMEZONE = os.getenv("TIMEZONE", "Europe/Moscow")
EXCLUDED_USER_ID = os.getenv("EXCLUDED_USER_ID")
PROXY_URL = os.getenv("PROXY_URL", "").strip() or None
CONNECT_TIMEOUT = float(os.getenv("CONNECT_TIMEOUT", "30"))
READ_TIMEOUT = float(os.getenv("READ_TIMEOUT", "30"))


def parse_excluded_user_id() -> Optional[int]:
    if not EXCLUDED_USER_ID:
        return None
    try:
        return int(EXCLUDED_USER_ID.strip())
    except ValueError:
        logger.warning("EXCLUDED_USER_ID задан некорректно: %s", EXCLUDED_USER_ID)
        return None


def parse_daily_time(value: str) -> time:
    hour, minute = map(int, value.split(":"))
    return time(hour=hour, minute=minute, tzinfo=None)


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    chat_id = update.effective_chat.id
    is_new = add_subscriber(chat_id)

    if is_new:
        text = (
            "Привет! Я буду каждый день присылать тебе пожелание с чёрным юмором "
            f"и сарказмом (обычно в {DAILY_TIME}, {TIMEZONE}).\n\n"
            "Команды:\n"
            "/wish — получить пожелание прямо сейчас\n"
            "/compliment — саркастичный комплимент\n"
            "/stop — отписаться от рассылки"
        )
    else:
        text = "Ты уже подписан. Жди пожеланий или жми /wish, если не терпится."

    await update.message.reply_text(text)


async def stop(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    removed = remove_subscriber(update.effective_chat.id)
    if removed:
        await update.message.reply_text(
            "Отписал. Без сарказма жить, конечно, скучнее, но решать тебе."
        )
    else:
        await update.message.reply_text("Ты и так не был подписан.")


async def wish(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(generate_wish())


async def compliment(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user = update.effective_user
    name = user.first_name if user else None
    excluded_id = parse_excluded_user_id()

    if excluded_id is not None and user and user.id == excluded_id:
        await update.message.reply_text(generate_genuine_compliment(name))
    else:
        await update.message.reply_text(generate_compliment(name))


async def broadcast_daily(context: ContextTypes.DEFAULT_TYPE) -> None:
    """Ежедневная рассылка всем подписчикам."""
    wish_text = generate_wish()
    subscribers = get_subscribers()

    if not subscribers:
        logger.info("Нет подписчиков для рассылки")
        return

    sent = 0
    for chat_id in subscribers:
        try:
            await context.bot.send_message(chat_id=chat_id, text=wish_text)
            sent += 1
        except Exception as exc:
            logger.warning("Не удалось отправить %s: %s", chat_id, exc)
            if "blocked" in str(exc).lower() or "deactivated" in str(exc).lower():
                remove_subscriber(chat_id)

    logger.info("Рассылка отправлена %d/%d подписчикам", sent, len(subscribers))


def create_proxy_request() -> HTTPXRequest:
    """Аналог AiohttpSession(proxy=...) из старых версий PTB."""
    return HTTPXRequest(
        proxy_url=PROXY_URL,
        connect_timeout=CONNECT_TIMEOUT,
        read_timeout=READ_TIMEOUT,
        write_timeout=READ_TIMEOUT,
        pool_timeout=CONNECT_TIMEOUT,
    )


def build_application() -> Application:
    builder = Application.builder().token(TOKEN)

    if PROXY_URL:
        request = create_proxy_request()
        builder = builder.request(request).get_updates_request(request)
        logger.info("Используется прокси: %s", PROXY_URL)
    else:
        builder = (
            builder.connect_timeout(CONNECT_TIMEOUT)
            .read_timeout(READ_TIMEOUT)
            .write_timeout(READ_TIMEOUT)
            .pool_timeout(CONNECT_TIMEOUT)
        )

    return builder.build()


def main() -> None:
    if not TOKEN:
        raise SystemExit(
            "Не задан TELEGRAM_BOT_TOKEN. Скопируй .env.example в .env и вставь токен."
        )

    app = build_application()

    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("stop", stop))
    app.add_handler(CommandHandler("wish", wish))
    app.add_handler(CommandHandler("compliment", compliment))

    daily_time = parse_daily_time(DAILY_TIME)
    tz = ZoneInfo(TIMEZONE)
    app.job_queue.run_daily(
        broadcast_daily,
        time=time(
            hour=daily_time.hour,
            minute=daily_time.minute,
            tzinfo=tz,
        ),
        name="daily_wish",
    )

    logger.info("Бот запущен. Ежедневная рассылка в %s (%s)", DAILY_TIME, TIMEZONE)
    app.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    try:
        asyncio.get_event_loop()
    except RuntimeError:
        asyncio.set_event_loop(asyncio.new_event_loop())
    main()
EOF

echo "==> Правка wishes.py (Python 3.9)"
python3 <<'PY'
from pathlib import Path
p = Path("wishes.py")
t = p.read_text(encoding="utf-8")
if "from typing import Optional" not in t:
    t = t.replace("from datetime import date\n", "from datetime import date\nfrom typing import Optional\n")
t = t.replace("name: str | None", "name: Optional[str]")
p.write_text(t, encoding="utf-8")
print("wishes.py ok")
PY

echo "==> .env"
[[ -f .env ]] || cp .env.example .env
grep -q '^PROXY_URL=' .env || echo 'PROXY_URL=socks5://127.0.0.1:10808' >> .env
grep -q '^CONNECT_TIMEOUT=' .env || echo 'CONNECT_TIMEOUT=30' >> .env
grep -q '^READ_TIMEOUT=' .env || echo 'READ_TIMEOUT=30' >> .env

if ! grep -qE '^TELEGRAM_BOT_TOKEN=.+[^[:space:]]' .env; then
  echo "!!! Добавь токен: nano .env"
fi

echo "==> requirements.txt для Python 3.9"
cat > requirements.txt <<'EOF'
python-telegram-bot[job-queue]==21.10
python-dotenv==1.0.1
EOF

echo "==> venv + pip"
[[ -d .venv ]] || python3 -m venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
pip install --upgrade pip $PIP_MIRROR
pip install --default-timeout=300 socksio typing_extensions exceptiongroup $PIP_MIRROR
pip install --default-timeout=300 -r requirements.txt $PIP_MIRROR

echo "==> Проверка прокси 10808"
if (ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null) | grep -q 10808; then
  echo "OK: порт 10808 слушается"
else
  echo "!!! Запусти прокси на 10808 (VPN/clash/v2ray)"
fi

echo
echo "=== ГОТОВО ==="
echo "nano .env          # если ещё не добавила токен"
echo "python bot.py      # запуск"
