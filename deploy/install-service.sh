#!/bin/bash
set -euo pipefail

BOT_DIR="${1:-/home/ec2-user/WishesBot/dark-wish-bot}"
SERVICE_NAME="dark-wish-bot"

cd "$BOT_DIR"

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Создан .env — заполни TELEGRAM_BOT_TOKEN:"
  echo "  nano $BOT_DIR/.env"
  exit 1
fi

if ! grep -qE '^TELEGRAM_BOT_TOKEN=.+[^[:space:]]' .env; then
  echo "Добавь TELEGRAM_BOT_TOKEN в .env"
  exit 1
fi

sudo cp deploy/dark-wish-bot.service "/etc/systemd/system/${SERVICE_NAME}.service"
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"
sudo systemctl status "$SERVICE_NAME" --no-pager

echo
echo "Логи: sudo journalctl -u $SERVICE_NAME -f"
