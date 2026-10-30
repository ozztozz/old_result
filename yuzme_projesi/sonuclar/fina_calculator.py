# -*- coding: utf-8 -*-
"""
fina_calculator.py
==================
World Aquatics (eski adıyla FINA) resmi puanlama motoru.
Her yarış derecesi için resmi formül:
    P = floor(1000 * (B / T)^3)

B (Base Time): O branştaki resmi dünya rekoru / baz derece (saniye)
T (Time): Sporcunun derecesi (saniye)
"""

import math
import re
from typing import Optional, Any, Union


# World Aquatics 2024 / 2025 Resmi Baz Dereceleri (Saniye Cinsinden)
# LCM = 50m (Uzun Kulvar), SCM = 25m (Kısa Kulvar)
BASE_TIMES = {
    # -------------------------------------------------------------
    # 50 Metre Havuz (Uzun Kulvar / LCM)
    # -------------------------------------------------------------
    "50m": {
        "ERKEK": {
            ("Serbest", 50): 20.91,
            ("Serbest", 100): 46.40,
            ("Serbest", 200): 102.00,
            ("Serbest", 400): 220.07,
            ("Serbest", 800): 452.12,
            ("Serbest", 1500): 870.67,
            ("Sırtüstü", 50): 23.55,
            ("Sırtüstü", 100): 51.60,
            ("Sırtüstü", 200): 111.92,
            ("Kurbağalama", 50): 25.95,
            ("Kurbağalama", 100): 56.88,
            ("Kurbağalama", 200): 125.48,
            ("Kelebek", 50): 22.27,
            ("Kelebek", 100): 49.45,
            ("Kelebek", 200): 110.34,
            ("Karışık", 200): 114.00,
            ("Karışık", 400): 242.50,
        },
        "KADIN": {
            ("Serbest", 50): 23.61,
            ("Serbest", 100): 51.71,
            ("Serbest", 200): 112.23,
            ("Serbest", 400): 235.38,
            ("Serbest", 800): 484.79,
            ("Serbest", 1500): 920.48,
            ("Sırtüstü", 50): 26.86,
            ("Sırtüstü", 100): 57.13,
            ("Sırtüstü", 200): 123.14,
            ("Kurbağalama", 50): 29.16,
            ("Kurbağalama", 100): 64.13,
            ("Kurbağalama", 200): 137.55,
            ("Kelebek", 50): 24.43,
            ("Kelebek", 100): 55.18,
            ("Kelebek", 200): 121.81,
            ("Karışık", 200): 126.12,
            ("Karışık", 400): 264.38,
        }
    },
    # -------------------------------------------------------------
    # 25 Metre Havuz (Kısa Kulvar / SCM)
    # -------------------------------------------------------------
    "25m": {
        "ERKEK": {
            ("Serbest", 50): 20.16,
            ("Serbest", 100): 44.84,
            ("Serbest", 200): 99.37,
            ("Serbest", 400): 212.25,
            ("Serbest", 800): 440.46,
            ("Serbest", 1500): 846.88,
            ("Sırtüstü", 50): 22.11,
            ("Sırtüstü", 100): 48.33,
            ("Sırtüstü", 200): 105.63,
            ("Kurbağalama", 50): 24.95,
            ("Kurbağalama", 100): 55.28,
            ("Kurbağalama", 200): 120.16,
            ("Kelebek", 50): 21.75,
            ("Kelebek", 100): 47.78,
            ("Kelebek", 200): 106.85,
            ("Karışık", 100): 49.28,
            ("Karışık", 200): 109.63,
            ("Karışık", 400): 234.81,
        },
        "KADIN": {
            ("Serbest", 50): 22.93,
            ("Serbest", 100): 50.25,
            ("Serbest", 200): 110.31,
            ("Serbest", 400): 231.30,
            ("Serbest", 800): 477.42,
            ("Serbest", 1500): 908.24,
            ("Sırtüstü", 50): 25.25,
            ("Sırtüstü", 100): 54.89,
            ("Sırtüstü", 200): 118.94,
            ("Kurbağalama", 50): 28.37,
            ("Kurbağalama", 100): 62.36,
            ("Kurbağalama", 200): 134.57,
            ("Kelebek", 50): 24.38,
            ("Kelebek", 100): 54.05,
            ("Kelebek", 200): 119.61,
            ("Karışık", 100): 56.51,
            ("Karışık", 200): 121.86,
            ("Karışık", 400): 258.94,
        }
    }
}


def normalize_stroke(stil: Any) -> str:
    """Stil adını standart FINA stil adına çevirir."""
    if not stil:
        return "Serbest"
    s = str(stil).strip().lower()
    if "serbest" in s or "free" in s:
        return "Serbest"
    if "sırt" in s or "sirt" in s or "back" in s:
        return "Sırtüstü"
    if "kurbağa" in s or "kurbaga" in s or "breast" in s:
        return "Kurbağalama"
    if "kelebek" in s or "fly" in s:
        return "Kelebek"
    if "karışık" in s or "karisik" in s or "medley" in s or "im" in s:
        return "Karışık"
    return "Serbest"


def normalize_gender(cinsiyet: Any) -> str:
    """Cinsiyet bilgisini ERKEK veya KADIN olarak döndürür."""
    if not cinsiyet:
        return "ERKEK"
    c = str(cinsiyet).strip().upper()
    if c.startswith("K") or "GIRL" in c or "WOMEN" in c or "FEMALE" in c:
        return "KADIN"
    return "ERKEK"


def detect_course(text: Any) -> str:
    """Müsabaka adı, havuz bilgisi veya metinden havuz tipini (25m veya 50m) tespit eder."""
    if not text:
        return "50m"
    s = str(text).lower()
    if any(k in s for k in ["kısa kulvar", "kisa kulvar", "25m", "25 m", "scm"]):
        return "25m"
    if any(k in s for k in ["uzun kulvar", "50m", "50 m", "lcm"]):
        return "50m"
    return "50m"


def calculate_fina_points(
    cinsiyet: Any,
    mesafe: Any,
    stil: Any,
    derece_saniye: Optional[float],
    course: str = "50m"
) -> Optional[int]:
    """
    World Aquatics resmi formülü ile FINA puanını hesaplar:
    P = floor( 1000 * (B / T)^3 )
    
    Örnek:
        calculate_fina_points('Erkek', 50, 'Serbest', 25.50, course='50m') -> 545
    """
    if not derece_saniye or derece_saniye <= 0:
        return None

    try:
        dist = int(mesafe)
    except (TypeError, ValueError):
        return None

    g = normalize_gender(cinsiyet)
    st = normalize_stroke(stil)
    c = "25m" if "25" in str(course) else "50m"

    table = BASE_TIMES.get(c, {}).get(g, {})
    base_time = table.get((st, dist))

    if not base_time:
        # 100m Karışık 50m havuzda yüzülemez, ancak girilmişse 25m tablosundan al
        if st == "Karışık" and dist == 100:
            base_time = BASE_TIMES["25m"][g].get(("Karışık", 100))
        if not base_time:
            return None

    # FINA Formülü: 1000 * (Base / Time)^3
    ratio = base_time / float(derece_saniye)
    points = int(math.floor(1000.0 * (ratio ** 3)))
    return max(points, 0)

