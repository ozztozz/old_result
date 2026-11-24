import os
import re
import sys
import time
import json
import argparse
from pathlib import Path
import requests
from bs4 import BeautifulSoup
from google import genai
from google.genai import types


ROOT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_INPUT = ROOT_DIR / "database" / "kulup_listesi_guncel.json"
DEFAULT_JSONL = ROOT_DIR / "database" / "kulup_bilgileri.jsonl"
DEFAULT_JSON = ROOT_DIR / "database" / "kulup_bilgileri.json"


def load_env_key(key_name: str) -> str:
    for fname in (".env", "env"):
        p = ROOT_DIR / fname
        if not p.exists():
            continue
        val = None
        for line in p.read_text(encoding="utf-8").splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                if k.strip() == key_name:
                    val = v.strip().strip('"').strip("'")
        if val:
            return val
    return os.environ[key_name]


def serper_post(endpoint: str, query: str, serper_key: str, num: int = 10) -> dict:
    resp = requests.post(
        f"https://google.serper.dev/{endpoint}",
        headers={
            "X-API-KEY": serper_key,
            "Content-Type": "application/json",
        },
        json={"q": query, "gl": "tr", "hl": "tr", "num": num},
        timeout=15,
    )
    if resp.status_code in (400, 401, 402, 403, 429):
        raise RuntimeError(f"SERPER_STOP:{resp.status_code}:{resp.text[:200]}")
    resp.raise_for_status()
    return resp.json()


def fetch_page_text(url: str, max_chars: int = 4000) -> str:
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


def kulup_bilgisi_getir(
    kulup_id: int,
    kulup_adi: str,
    sehir: str | None,
    serper_key: str,
    client: genai.Client,
) -> dict:
    sehir_str = (sehir or "").strip()
    core_name = re.sub(
        r"\b(Gençlik\s+Ve\s+Spor\s+Kulübü|Spor\s+Kulübü\s+Derneği|Spor\s+Kulübü|Kulübü|Derneği)\b",
        "",
        kulup_adi,
        flags=re.IGNORECASE,
    ).strip() or kulup_adi

    q_search = f"{core_name} {sehir_str} yüzme instagram facebook iletişim".strip()
    q_places = f"{core_name} {sehir_str} yüzme".strip()

    search_data = serper_post("search", q_search, serper_key, num=10)
    places_data = serper_post("places", q_places, serper_key, num=5)

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
            txt = fetch_page_text(u)
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
    "kulup_adi": "{kulup_adi}",
    "sehir": {json.dumps(sehir_str or None, ensure_ascii=False)},
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
    for attempt in range(4):
        try:
            response = client.models.generate_content(
                model="gemini-flash-lite-latest",
                contents=prompt,
                config=types.GenerateContentConfig(
                    temperature=0.0,
                    response_mime_type="application/json",
                ),
            )
            data = json.loads(response.text)
            data["kulup_id"] = kulup_id
            data["kulup_adi"] = kulup_adi
            data["sehir"] = sehir_str or None
            return data
        except Exception as e:
            last_err = e
            wait_s = 2 ** (attempt + 1)
            time.sleep(wait_s)
    raise last_err


def export_summary_json(jsonl_path: Path, json_path: Path) -> int:
    rows = []
    if jsonl_path.exists():
        for line in jsonl_path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                rows.append(json.loads(line))
    json_path.write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
    return len(rows)


def main():
    parser = argparse.ArgumentParser(description="Kulüp iletişim ve sosyal medya bilgisi toplayıcı")
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output-jsonl", type=Path, default=DEFAULT_JSONL)
    parser.add_argument("--output-json", type=Path, default=DEFAULT_JSON)
    parser.add_argument("--limit", type=int, default=20, help="Bu çalıştırmada işlenecek maksimum kulüp sayısı (0 = sınırsız)")
    parser.add_argument("--min-athletes", type=int, default=2, help="En az sporcu sayısı filtresi")
    parser.add_argument("--delay", type=float, default=0.3, help="İstekler arası bekleme (sn)")
    args = parser.parse_args()

    clubs = json.loads(args.input.read_text(encoding="utf-8"))
    clubs = [c for c in clubs if c.get("toplam_sporcu_sayisi", 0) >= args.min_athletes]

    done_ids = set()
    if args.output_jsonl.exists():
        for line in args.output_jsonl.read_text(encoding="utf-8").splitlines():
            if line.strip():
                try:
                    done_ids.add(json.loads(line).get("kulup_id"))
                except Exception:
                    pass

    pending = [c for c in clubs if c["id"] not in done_ids]
    if args.limit > 0:
        pending = pending[: args.limit]

    print(f"Toplam uygun kulüp: {len(clubs)} | Önceden işlenen: {len(done_ids)} | Bu turda işlenecek: {len(pending)}")
    if not pending:
        export_summary_json(args.output_jsonl, args.output_json)
        return

    serper_key = load_env_key("SERPER_API_KEY")
    client = genai.Client(api_key=load_env_key("GEMINI_API_KEY"))

    processed = 0
    with args.output_jsonl.open("a", encoding="utf-8") as f:
        for idx, c in enumerate(pending, 1):
            cid = c["id"]
            cname = c["kulup_adi"]
            cil = c.get("il")
            try:
                res = kulup_bilgisi_getir(cid, cname, cil, serper_key, client)
                res["son_yaris_tarihi"] = c.get("son_yaris_tarihi")
                res["toplam_sporcu_sayisi"] = c.get("toplam_sporcu_sayisi")
                f.write(json.dumps(res, ensure_ascii=False) + "\n")
                f.flush()
                processed += 1
                found_fields = [k for k in ("adres", "telefon", "web_sitesi", "google_maps_url", "instagram", "facebook") if res.get(k)]
                print(f"[{idx}/{len(pending)}] {cname} ({cil}, {c.get('son_yaris_tarihi')}) -> {found_fields}")
                time.sleep(args.delay)
            except RuntimeError as e:
                if str(e).startswith("SERPER_STOP:"):
                    print(f"Serper limiti/hatası nedeniyle durduruldu: {e}")
                    break
                print(f"[{idx}/{len(pending)}] HATA {cname}: {e}")
            except Exception as e:
                print(f"[{idx}/{len(pending)}] HATA {cname}: {e}")

    total_saved = export_summary_json(args.output_jsonl, args.output_json)
    print(f"\nTamamlandı. Bu tur işlenen: {processed}, Toplam kayıtlı: {total_saved}")
    print(f"Çıktı: {args.output_json}")


if __name__ == "__main__":
    main()
