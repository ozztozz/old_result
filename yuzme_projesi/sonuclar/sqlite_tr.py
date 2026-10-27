# -*- coding: utf-8 -*-
"""
sqlite_tr.py
============
SQLite varsayılan olarak ASCII dışındaki (Türkçe) karakterlerde LIKE ve UPPER/LOWER
fonksiyonlarını büyük/küçük harf duyarsız (case-insensitive) çalıştırmaz.
Bu modül, SQLite veritabanı bağlantısına Türkçe uyumlu LIKE, UPPER ve LOWER
fonksiyonlarını ekler; böylece hem Türkçe karakterli ("ç, Ç, ğ, Ğ, ı, I, i, İ, ö, Ö, ş, Ş, ü, Ü")
hem de ASCII karşılıkları ("c, g, i, o, s, u") ile arama yapıldığında doğru sonuç döner.
"""

import re

# Türkçe karakterleri eşleştirme için küçük harf ASCII'ye katlar (fold eder)
TR_FOLD_MAP = {
    ord('İ'): 'i', ord('I'): 'i', ord('ı'): 'i', ord('i'): 'i',
    ord('Ş'): 's', ord('ş'): 's',
    ord('Ğ'): 'g', ord('ğ'): 'g',
    ord('Ü'): 'u', ord('ü'): 'u',
    ord('Ö'): 'o', ord('ö'): 'o',
    ord('Ç'): 'c', ord('ç'): 'c',
}

TR_LOWER_MAP = {
    ord('İ'): 'i', ord('I'): 'ı',
    ord('Ş'): 'ş', ord('Ğ'): 'ğ',
    ord('Ü'): 'ü', ord('Ö'): 'ö',
    ord('Ç'): 'ç',
}

TR_UPPER_MAP = {
    ord('i'): 'İ', ord('ı'): 'I',
    ord('ş'): 'Ş', ord('ğ'): 'Ğ',
    ord('ü'): 'Ü', ord('ö'): 'Ö',
    ord('ç'): 'Ç',
}


def tr_fold(s: str) -> str:
    """Metni Türkçe ve İngilizce duyarsızlaştırarak küçük harfe dönüştürür."""
    if not s:
        return ""
    return str(s).translate(TR_FOLD_MAP).lower()


def tr_lower(s: str) -> str:
    """Türkçe kurallarına uygun küçük harfe çevirir."""
    if not s:
        return ""
    return str(s).translate(TR_LOWER_MAP).lower()


def tr_upper(s: str) -> str:
    """Türkçe kurallarına uygun büyük harfe çevirir."""
    if not s:
        return ""
    return str(s).translate(TR_UPPER_MAP).upper()


def py_like(*args) -> bool:
    """
    SQLite LIKE operatörünün Türkçe ve harf duyarsız Python uygulaması.
    like(pattern, string) veya like(pattern, string, escape)
    """
    if len(args) < 2 or args[0] is None or args[1] is None:
        return False
    pattern = args[0]
    string = args[1]
    escape = args[2] if len(args) > 2 else None

    pat = tr_fold(pattern)
    target = tr_fold(string)

    # Hızlı yol 1: Tam eşleşme (wildcard veya escape yoksa)
    if '%' not in pat and '_' not in pat and not escape:
        return pat == target

    # Hızlı yol 2: %metin% (içerir / contains - iç kısımda wildcard yoksa)
    if pat.startswith('%') and pat.endswith('%') and not escape:
        inner = pat[1:-1]
        if '%' not in inner and '_' not in inner:
            return inner in target

    # Hızlı yol 3: %metin (ile biter / endswith)
    if pat.startswith('%') and not pat.endswith('%') and not escape:
        inner = pat[1:]
        if '%' not in inner and '_' not in inner:
            return target.endswith(inner)

    # Hızlı yol 4: metin% (ile başlar / startswith)
    if not pat.startswith('%') and pat.endswith('%') and not escape:
        inner = pat[:-1]
        if '%' not in inner and '_' not in inner:
            return target.startswith(inner)

    # Genel regex dönüşümü
    esc = tr_fold(escape) if escape else None
    if esc:
        pat = pat.replace(esc + '%', '\x01').replace(esc + '_', '\x02').replace(esc + esc, '\x03')

    # Wildcard'ları geçici yer tutuculara al
    pat = pat.replace('%', '\x04').replace('_', '\x05')

    # Regex özel karakterlerini kaçır
    pat = re.escape(pat)

    # SQL wildcard'larını regex'e çevir
    pat = pat.replace('\x04', '.*').replace('\x05', '.')

    # Escape edilen karakterleri geri yükle
    if esc:
        pat = pat.replace('\x01', '%').replace('\x02', '_').replace('\x03', re.escape(esc))

    return bool(re.search(r'\A' + pat + r'\Z', target, re.DOTALL))


def register_sqlite_tr_functions(sender=None, connection=None, **kwargs):
    """
    Django SQLite bağlantısına Türkçe uyumlu LIKE, UPPER ve LOWER fonksiyonlarını bağlar
    ve WAL modu/performans PRAGMA ayarlarını etkinleştirir.
    """
    conn = connection.connection if connection else None
    if conn and hasattr(conn, 'create_function'):
        try:
            conn.create_function('like', 2, py_like)
            conn.create_function('like', 3, py_like)
            conn.create_function('upper', 1, tr_upper)
            conn.create_function('lower', 1, tr_lower)
            
            # SQLite Concurrency & Hızlandırma PRAGMA'ları
            cur = conn.cursor()
            cur.execute("PRAGMA journal_mode=WAL;")
            cur.execute("PRAGMA synchronous=NORMAL;")
            cur.execute("PRAGMA cache_size=-64000;")
            cur.execute("PRAGMA temp_store=MEMORY;")
            cur.execute("PRAGMA mmap_size=268435456;")
        except Exception:
            pass

