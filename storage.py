"""Хранение подписчиков в JSON-файле."""

import json
from pathlib import Path

STORAGE_PATH = Path(__file__).parent / "subscribers.json"


def _load() -> set[int]:
    if not STORAGE_PATH.exists():
        return set()
    data = json.loads(STORAGE_PATH.read_text(encoding="utf-8"))
    return set(data.get("chat_ids", []))


def _save(chat_ids: set[int]) -> None:
    STORAGE_PATH.write_text(
        json.dumps({"chat_ids": sorted(chat_ids)}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def add_subscriber(chat_id: int) -> bool:
    """Добавить подписчика. Возвращает True, если это новая подписка."""
    chat_ids = _load()
    if chat_id in chat_ids:
        return False
    chat_ids.add(chat_id)
    _save(chat_ids)
    return True


def remove_subscriber(chat_id: int) -> bool:
    """Удалить подписчика. Возвращает True, если был подписан."""
    chat_ids = _load()
    if chat_id not in chat_ids:
        return False
    chat_ids.remove(chat_id)
    _save(chat_ids)
    return True


def get_subscribers() -> list[int]:
    return list(_load())
