# -*- coding: utf-8 -*-
import hashlib
import json
import re
from typing import Any, Dict, Optional, Tuple
from django.http import HttpResponse, JsonResponse


STROKE_MAP = {
    'SERBEST': 'free',
    'SIRTUSTU': 'back',
    'SIRTÜSTÜ': 'back',
    'KURBAGALAMA': 'breast',
    'KURBAĞALAMA': 'breast',
    'KELEBEK': 'fly',
    'KARISIK': 'medley',
    'KARIŞIK': 'medley',
}


def map_stroke(stil: Optional[str]) -> str:
    """Türkçe stil adını standart API enum değerine çevirir."""
    if not stil:
        return 'other'
    normalized = stil.strip().upper()
    return STROKE_MAP.get(normalized, 'other')


def seconds_to_cs(val: Any) -> Optional[int]:
    """Saniye değerini (float, int veya '00:28.45' metin) tam sayı centisaniyeye çevirir."""
    if val is None:
        return None
    if isinstance(val, (int, float)):
        if val <= 0:
            return None
        return int(round(float(val) * 100))

    val_str = str(val).strip().upper()
    if not val_str or val_str in ('BEKLENIYOR', 'BEKLENİYOR', 'DNS', 'DQ', 'DNF', 'NT', 'NT.', '-'):
        return None

    # mm:ss.SS veya ss.SS formatını ayrıştır
    try:
        parts = val_str.replace(',', '.').split(':')
        if len(parts) == 3:  # hh:mm:ss.SS
            h, m, s = float(parts[0]), float(parts[1]), float(parts[2])
            tot = h * 3600 + m * 60 + s
            return int(round(tot * 100))
        elif len(parts) == 2:  # mm:ss.SS
            m, s = float(parts[0]), float(parts[1])
            tot = m * 60 + s
            return int(round(tot * 100))
        elif len(parts) == 1:  # ss.SS
            s = float(parts[0])
            if s > 0:
                return int(round(s * 100))
    except (ValueError, TypeError):
        return None
    return None


def map_result_status(derece: Optional[str], sira: Optional[str]) -> str:
    """Derece ve sıra metnine göre standart sonuç durumu döner."""
    d_norm = (derece or '').strip().upper()
    s_norm = (sira or '').strip().upper()

    if 'BEKLEN' in d_norm or 'BEKLEN' in s_norm:
        return 'WAITING'
    if any(tok in d_norm or tok in s_norm for tok in ('DNS', 'GIRMEDI', 'GİRMEDİ', 'BAŞLAMADI', 'BASLAMADI')):
        return 'DNS'
    if any(tok in d_norm or tok in s_norm for tok in ('DQ', 'DISK', 'DİSK', 'İPTAL', 'IPTAL')):
        return 'DQ'
    if any(tok in d_norm or tok in s_norm for tok in ('DNF', 'TERK', 'BİTİREMEDİ', 'BITIREMEDI')):
        return 'DNF'
    return 'OK'


def parse_qualifying_standard(baraj_text: Optional[str]) -> Optional[Dict[str, Any]]:
    """Baraj metnini (A1, A2, B1 vb.) ayrıştırıp nesne olarak döner."""
    if not baraj_text:
        return None
    b = baraj_text.strip().upper()
    if not b or b in ('-', 'HAYIR', 'GEÇMEDİ', 'GECMEDI', 'YOK', '0'):
        return None
    return {
        'passed': True,
        'badge': baraj_text.strip()
    }


def detect_course(text_or_event: Any) -> str:
    """Müsabaka adı veya kaynak metninden havuz tipini (25m / 50m) tespit eder."""
    raw = str(text_or_event or '').upper()
    if '25M' in raw or '25 M' in raw or 'KISA KULVAR' in raw:
        return 'SC'
    if '50M' in raw or '50 M' in raw or 'UZUN KULVAR' in raw:
        return 'LC'
    return 'LC'  # TYF varsayılanı genellikle 50m'dir


def api_response(data: Any, status: int = 200, request=None, cache_seconds: int = 0) -> HttpResponse:
    """
    Standart Mobil API JSON yanıtı üretir.
    ETag başlığı oluşturur; istemcinin If-None-Match başlığı eşleşirse 304 döner.
    """
    body_str = json.dumps(data, ensure_ascii=False)
    etag = f'"{hashlib.md5(body_str.encode("utf-8")).hexdigest()}"'

    if request and request.headers.get('If-None-Match') == etag:
        resp = HttpResponse(status=304)
        resp['ETag'] = etag
        resp['Access-Control-Allow-Origin'] = '*'
        return resp

    resp = HttpResponse(body_str, content_type='application/json; charset=utf-8', status=status)
    resp['ETag'] = etag
    resp['Access-Control-Allow-Origin'] = '*'
    resp['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
    resp['Access-Control-Allow-Headers'] = 'X-App-Key, Content-Type, If-None-Match, Authorization'

    if cache_seconds > 0:
        resp['Cache-Control'] = f'public, max-age={cache_seconds}'
    else:
        resp['Cache-Control'] = 'no-cache, must-revalidate'

    return resp


def api_error(code: str, message: str, status: int = 400) -> HttpResponse:
    """Standart hata nesnesi döndürür."""
    return api_response({'error': {'code': code, 'message': message}}, status=status)
