# -*- coding: utf-8 -*-
"""
Firebase Cloud Messaging (FCM) Servisi

Canlı müsabakalardaki yeni sonuçlar için ilgili `live_meet_<id>` topic'ine
push bildirimi gönderir. Service account dosyası yoksa veya firebase-admin
kurulu değilse canlı tarama akışını kesmeden sessizce uyarı loglar.
"""

import logging
import os
import threading
import time
from pathlib import Path
from typing import Dict, Optional

logger = logging.getLogger("fcm_service")

_init_lock = threading.Lock()
_firebase_app = None
_firebase_init_attempted = False
_last_sent_by_meet: Dict[int, float] = {}

BASE_DIR = Path(__file__).resolve().parent.parent
DEFAULT_CREDENTIALS_PATH = BASE_DIR / "firebase-service-account.json"
MIN_COOLDOWN_SECONDS = 45


def _ensure_firebase_initialized() -> bool:
    global _firebase_app, _firebase_init_attempted
    if _firebase_app is not None:
        return True
    if _firebase_init_attempted:
        return False

    with _init_lock:
        if _firebase_app is not None:
            return True
        if _firebase_init_attempted:
            return False
        _firebase_init_attempted = True

        try:
            import firebase_admin
            from firebase_admin import credentials
        except ImportError:
            logger.warning(
                "firebase-admin paketi kurulu değil; push bildirimleri pasif. "
                "Kurmak için: pip install firebase-admin"
            )
            return False

        cred_path_env = os.getenv("FIREBASE_CREDENTIALS_PATH", "").strip()
        cred_path = Path(cred_path_env) if cred_path_env else DEFAULT_CREDENTIALS_PATH
        if not cred_path.exists():
            logger.warning(
                f"Firebase service account dosyası bulunamadı ({cred_path}); "
                "push bildirimleri gönderilmeyecek."
            )
            return False

        try:
            if not firebase_admin._apps:
                cred = credentials.Certificate(str(cred_path))
                _firebase_app = firebase_admin.initialize_app(cred)
            else:
                _firebase_app = firebase_admin.get_app()
            return True
        except Exception as exc:
            logger.error(f"Firebase Admin başlatılamadı: {exc}")
            return False


def send_live_meet_notification(
    live_meet_id: int,
    title: str,
    body: str,
    extra_data: Optional[Dict[str, str]] = None,
) -> bool:
    """`live_meet_<id>` topic'ine canlı yarış bildirimi gönderir."""
    if not _ensure_firebase_initialized():
        return False

    now = time.monotonic()
    last_ts = _last_sent_by_meet.get(live_meet_id, 0.0)
    if now - last_ts < MIN_COOLDOWN_SECONDS:
        return False

    try:
        from firebase_admin import messaging

        data_payload: Dict[str, str] = {
            "type": "live_meet_update",
            "live_meet_id": str(live_meet_id),
            "title": title,
            "body": body,
        }
        if extra_data:
            for k, v in extra_data.items():
                data_payload[str(k)] = str(v)

        topic = f"live_meet_{live_meet_id}"
        message = messaging.Message(
            topic=topic,
            notification=messaging.Notification(title=title, body=body),
            data=data_payload,
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    channel_id="live_races_channel",
                    priority="high",
                ),
            ),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound="default"),
                ),
            ),
        )
        msg_id = messaging.send(message)
        _last_sent_by_meet[live_meet_id] = now
        logger.info(f"FCM bildirimi gönderildi (topic={topic}, id={msg_id})")
        return True
    except Exception as exc:
        logger.error(f"FCM bildirim gönderme hatası (live_meet_id={live_meet_id}): {exc}")
        return False
