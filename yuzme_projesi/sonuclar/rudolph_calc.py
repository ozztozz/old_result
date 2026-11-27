# -*- coding: utf-8 -*-
"""
DSV Rudolph-Punktetabelle (2025/2026) Hesaplama Modülü.

Resmi DSV 2025/2026 tablosuna göre yaş (8-18 ve 19+ Açık Yaş), cinsiyet,
branş, mesafe ve yüzülen süreye (santim/salise) göre 1-20 arası Rudolph puanını döndürür.
"""

import json
import os
from typing import Optional

_JSON_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rudolph_2025.json")

try:
    with open(_JSON_PATH, "r", encoding="utf-8") as _f:
        _RUDOLPH_TABLE = json.load(_f)
except Exception:
    _RUDOLPH_TABLE = {}

_STROKE_MAP = {
    "free": "FREE",
    "serbest": "FREE",
    "freestyle": "FREE",
    "back": "BACK",
    "sirt": "BACK",
    "sırt": "BACK",
    "sirtustu": "BACK",
    "sırtüstü": "BACK",
    "backstroke": "BACK",
    "breast": "BREAST",
    "kurbaga": "BREAST",
    "kurbağalama": "BREAST",
    "breaststroke": "BREAST",
    "fly": "FLY",
    "kelebek": "FLY",
    "butterfly": "FLY",
    "medley": "MEDLEY",
    "karisik": "MEDLEY",
    "karışık": "MEDLEY",
    "im": "MEDLEY",
}


def compute_rudolph_points(
    *,
    gender: Optional[str],
    age: Optional[int],
    stroke: Optional[str],
    distance: Optional[int],
    time_cs: Optional[int],
) -> Optional[int]:
    """
    Verilen sporcu ve yarış parametreleri için 1-20 arası Rudolph puanını döndürür.
    Yaş < 8, desteklenmeyen branş veya 1 puan barajının dışındaki süreler için None döner.
    """
    if not _RUDOLPH_TABLE or age is None or not distance or not time_cs or time_cs <= 0:
        return None
    if age < 8:
        return None

    g_raw = (gender or "").strip().upper()
    if g_raw in ("M", "E", "ERKEK", "MALE"):
        g_key = "M"
    elif g_raw in ("F", "K", "KADIN", "BAYAN", "FEMALE", "W"):
        g_key = "F"
    else:
        return None

    s_raw = (stroke or "").strip().lower()
    s_key = _STROKE_MAP.get(s_raw)
    if not s_key:
        return None

    age_key = str(age) if age <= 18 else "open"
    ev_key = f"{s_key}_{int(distance)}"

    thresholds = _RUDOLPH_TABLE.get(g_key, {}).get(age_key, {}).get(ev_key)
    if not thresholds:
        return None

    for pkt in range(20, 0, -1):
        limit_cs = thresholds.get(str(pkt))
        if limit_cs is not None and time_cs <= limit_cs:
            return pkt
    return None
