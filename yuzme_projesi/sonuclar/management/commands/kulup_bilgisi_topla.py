import json
import os
import re
import time
from datetime import datetime
from pathlib import Path

import requests
from bs4 import BeautifulSoup
from django.core.management.base import BaseCommand
from django.db import connection
from google import genai
from google.genai import types


def _load_env_key(key_name: str) -> str:
    if os.environ.get(key_name):
        return os.environ[key_name]
    base = Path(__file__).resolve().parents[4]  # /home/ubuntu/app or repo root
    for candidate in (base / ".env", base.parent / ".env", base / "env"):
        if not candidate.exists():
            continue
        val = None
        for line in candidate.read_text(encoding="utf-8").splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                if k.strip() == key_name:
                    val = v.strip().strip('"').strip("'")
        if val:
            return val
    raise RuntimeError(f"{key_name} bulunamadı (.env veya ortam değişkenlerinde tanımlayın)")


def _serper_post(endpoint: str, query: str, serper_key: str, num: int = 10) -> dict:
    last_err = None
    for attempt in range(3):
        try:
            resp = requests.post(
                f"https://google.serper.dev/{endpoint}",
                headers={"X-API-KEY": serper_key, "Content-Type": "application/json"},
                json={"q": query, "gl": "tr", "hl": "tr", "num": num},
                timeout=25,
            )
            if resp.status_code in (400, 401, 402, 403, 429):
                raise RuntimeError(f"SERPER_STOP:{resp.status_code}:{resp.text[:200]}")
            resp.raise_for_status()
            return resp.json()
        except (requests.exceptions.Timeout, requests.exceptions.ConnectionError) as e:
            last_err = e
            time.sleep(2 ** (attempt + 1))
    raise last_err


def _fetch_page_text(url: str, max_chars: int = 4000) -> str:
    try:
        r = requests.get(
            url,
            headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/128.0.0.0"},
            timeout=8,
        )
        if r.status_code != 200 or "text/html" not in r.headers.get("content-type", ""):
            return ""
        soup = BeautifulSoup(r.text, "html.parser")
        links = [a.get("href", "") for a in soup.find_all("a", href=True)]
        social_links = [
            l for l in links
            if any(d in l.lower() for d in ("instagram.com", "facebook.com", "maps.app.goo.gl", "google.com/maps"))
        ]
        for tag in soup(["script", "style", "noscript", "svg"]):
            tag.decompose()
        text = re.sub(r"\s+", " ", soup.get_text(" ", strip=True))
        extra = ("\nSayfa Sosyal/Harita Linkleri: " + ", ".join(dict.fromkeys(social_links[:10]))) if social_links else ""
        return text[:max_chars] + extra
    except Exception:
        return ""


def _fetch_club_info(kulup_adi: str, sehir: str | None, serper_key: str, client: genai.Client) -> dict:
    sehir_str = (sehir or "").strip()
    core_name = re.sub(
        r"\b(Gençlik\s+Ve\s+Spor\s+Kulübü|Spor\s+Kulübü\s+Derneği|Spor\s+Kulübü|Kulübü|Derneği)\b",
        "",
        kulup_adi,
        flags=re.IGNORECASE,
    ).strip() or kulup_adi

    q_search = f"{core_name} {sehir_str} yüzme instagram facebook iletişim".strip()
    q_places = f"{core_name} {sehir_str} yüzme".strip()

    search_data = _serper_post("search", q_search, serper_key, num=10)
    places_data = _serper_post("places", q_places, serper_key, num=5)

    organic = search_data.get("organic", [])
    places = places_data.get("places", [])
    kg = search_data.get("knowledgeGraph", {})

    page_context = ""
    skip_domains = (
        "instagram.com", "facebook.com", "youtube.com", "linkedin.com",
        "twitter.com", "x.com", "tyf.gov.tr", "wikipedia.org",
    )
    for item in organic:
        u = item.get("link", "")
        if u.startswith("http") and not any(d in u.lower() for d in skip_domains) and not u.lower().endswith(".pdf"):
            txt = _fetch_page_text(u)
            if txt:
                page_context = f"\n--- Web Sayfası ({u}) ---\n{txt}\n"
                break

    context_payload = {
        "knowledgeGraph": kg,
        "places": [
            {
                "title": p.get("title"),
                "address": p.get("address"),
                "phoneNumber": p.get("phoneNumber"),
                "website": p.get("website"),
                "cid": p.get("cid"),
                "google_maps_url": f"https://www.google.com/maps?cid={p['cid']}" if p.get("cid") else None,
            }
            for p in places[:5]
        ],
        "organic": [
            {"title": o.get("title"), "link": o.get("link"), "snippet": o.get("snippet")}
            for o in organic[:10]
        ],
    }

    sehir_label = sehir_str or "Türkiye"
    prompt = f"""
Aşağıdaki Google Arama ve Google Haritalar (Places) verilerini kullanarak Türkiye'nin {sehir_label} ilinde faaliyet gösteren "{kulup_adi}" adlı yüzme kulübünün bilgilerini çıkar.

KURALLAR:
- Yalnızca bu kulüple (veya kısa/marka adıyla, örn. "{core_name}") gerçekten eşleşen doğrulanmış kayıtları kullan.
- Alakasız başka şehirdeki veya farklı sektördeki sonuçları alma.
- Bulamadığın alanlar için null döndür, asla tahmin/uydurma yapma.
- google_maps_url için Places kaydında eşleşen kulübün `google_maps_url` değerini kullan.

Yanıtı sadece aşağıdaki JSON formatında ver:
{{
    "adres": "Tam açık adres veya null",
    "telefon": "Telefon numarası veya null",
    "web_sitesi": "Resmi web sitesi URL veya null",
    "google_maps_url": "Google Maps bağlantısı veya null",
    "instagram": "Resmi Instagram profil URL veya null",
    "facebook": "Resmi Facebook sayfası URL veya null"
}}

--- Google Verisi ---
{json.dumps(context_payload, ensure_ascii=False, indent=2)}
{page_context}
"""

    last_err = None
    for model_name in ("gemini-flash-lite-latest", "gemini-flash-latest"):
        for attempt in range(2):
            try:
                response = client.models.generate_content(
                    model=model_name,
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        temperature=0.0,
                        response_mime_type="application/json",
                    ),
                )
                return json.loads(response.text)
            except Exception as e:
                last_err = e
                time.sleep(2 ** (attempt + 1))
    raise last_err


class Command(BaseCommand):
    help = "Kulüplerin adres, telefon, web sitesi, Google Maps ve sosyal medya bilgilerini toplayıp veritabanına yazar."

    def add_arguments(self, parser):
        parser.add_argument("--limit", type=int, default=50, help="İşlenecek maksimum kulüp sayısı (0 = sınırsız)")
        parser.add_argument("--min-athletes", type=int, default=2, help="En az sporcu sayısı")
        parser.add_argument("--delay", type=float, default=0.3, help="İstekler arası bekleme (sn)")
        parser.add_argument("--force", action="store_true", help="Daha önce güncellenmiş kulüpleri de yeniden tara")

    def handle(self, *args, **options):
        serper_key = _load_env_key("SERPER_API_KEY")
        gemini_key = _load_env_key("GEMINI_API_KEY")
        client = genai.Client(api_key=gemini_key)

        limit = options["limit"]
        min_athletes = options["min_athletes"]
        delay = options["delay"]
        force = options["force"]

        with connection.cursor() as cur:
            where_extra = "" if force else "AND iletisim_guncellenme_tarihi IS NULL"
            limit_sql = f"LIMIT {int(limit)}" if limit > 0 else ""
            cur.execute(
                f"""
                SELECT id, kulup_adi, il, toplam_sporcu_sayisi, son_yaris_tarihi
                FROM kulupler
                WHERE okul_mu = 0
                  AND id != 2486
                  AND toplam_sporcu_sayisi >= %s
                  {where_extra}
                ORDER BY COALESCE(son_yaris_tarihi, '') DESC, toplam_sporcu_sayisi DESC, toplam_yaris_sayisi DESC
                {limit_sql}
                """,
                [min_athletes],
            )
            rows = cur.fetchall()

        self.stdout.write(f"İşlenecek kulüp sayısı: {len(rows)}")
        processed = 0
        for idx, (cid, cname, cil, sp_cnt, son_tarih) in enumerate(rows, 1):
            try:
                data = _fetch_club_info(cname, cil, serper_key, client)
                now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                with connection.cursor() as cur:
                    cur.execute(
                        """
                        UPDATE kulupler
                        SET adres = %s,
                            telefon = %s,
                            web_sitesi = %s,
                            google_maps_url = %s,
                            instagram = %s,
                            facebook = %s,
                            iletisim_guncellenme_tarihi = %s
                        WHERE id = %s
                        """,
                        [
                            data.get("adres"),
                            data.get("telefon"),
                            data.get("web_sitesi"),
                            data.get("google_maps_url"),
                            data.get("instagram"),
                            data.get("facebook"),
                            now_str,
                            cid,
                        ],
                    )
                processed += 1
                found = [k for k in ("adres", "telefon", "web_sitesi", "google_maps_url", "instagram", "facebook") if data.get(k)]
                self.stdout.write(f"[{idx}/{len(rows)}] {cname} ({cil}, {son_tarih}) -> {found}")
                self.stdout.flush()
                time.sleep(delay)
            except RuntimeError as e:
                if str(e).startswith("SERPER_STOP:"):
                    self.stderr.write(f"Serper limiti/hatası nedeniyle durduruldu: {e}")
                    break
                self.stderr.write(f"[{idx}/{len(rows)}] HATA {cname}: {e}")
            except Exception as e:
                self.stderr.write(f"[{idx}/{len(rows)}] HATA {cname}: {e}")

        self.stdout.write(self.style.SUCCESS(f"Tamamlandı. Güncellenen kulüp sayısı: {processed}"))
