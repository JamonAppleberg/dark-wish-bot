#!/usr/bin/env python3
"""Telegram-бот с ежедневными саркастичными пожеланиями."""

import asyncio
import logging
import os
from datetime import time
from zoneinfo import ZoneInfo

from dotenv import load_dotenv
from telegram import Update
from telegram.ext import (
    Application,
    CommandHandler,
    ContextTypes,
)

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


def parse_excluded_user_id() -> int | None:
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


def main() -> None:
    if not TOKEN:
        raise SystemExit(
            "Не задан TELEGRAM_BOT_TOKEN. Скопируй .env.example в .env и вставь токен."
        )

    app = (
        Application.builder()
        .token(TOKEN)
        .build()
    )

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
    # Python 3.14+ не создаёт event loop в main thread автоматически
    try:
        asyncio.get_event_loop()
    except RuntimeError:
        asyncio.set_event_loop(asyncio.new_event_loop())
    main()
