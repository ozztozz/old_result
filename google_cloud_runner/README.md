# Google Cloud Functions / Cloud Run - TYF Canlı Start & Sonuç Listesi İşleyicisi

Bu servis, Google Cloud altyapısında (Cloud Functions gen2 veya Cloud Run) çalışarak PythonAnywhere'in harici indirme (proxy) kısıtlamasını tamamen çözer.

## Temel Özellikler
1. **Çift Modlu Çalışma (`mod` parametresi):**
   - `start_listesi`: `StartList_*.pdf` dosyalarını indirir ve yarışmacıları serileriyle kaydeder.
   - `sonuc_listesi`: `ResultList_*.pdf` dosyalarını indirir. Django'dan mevcut start listesi sporcularını ve PK ID'lerini çekerek Gemini promptuna enjekte eder; sonuçları doğrudan $O(1)$ birincil anahtarla eşleştirip günceller.
2. **Akıllı ETag / SHA-256 Hash Kontrolü:**
   - Her PDF indirilip hash/etag bilgisi Django API'ye (`/api/canli-dosya-kontrol/`) sorulur.
   - Eğer dosya daha önce işlenmişse ve TYF tarafında değişmemişse Gemini çağrısı yapılmadan atlanır (Kota ve süre tasarrufu).
3. **Şehir & Tarih Ayrıştırma:**
   - HTML başlığından yarış adı, şehir, tarih aralığı (`24. - 26.4.2026` -> ISO başlangıç/bitiş) otomatik ayrıştırılır.
4. **Asenkron Webhook Desteği:**
   - PythonAnywhere timeout yemeden 200 ms içinde HTTP 202 döner, işlem bitince `callback_url` (`/api/canli-durum-guncelle/`) ile durumu Django'ya bildirir.

---

## 1 Komutla Canlıya Alma (Google Cloud CLI)

Eğer Google Cloud CLI (`gcloud`) yüklüyse:

```bash
cd google_cloud_runner

gcloud functions deploy tyf-startlist-parser \
  --gen2 \
  --runtime=python311 \
  --region=europe-west1 \
  --source=. \
  --entry-point=tyf_startlist_handler \
  --trigger-http \
  --allow-unauthenticated \
  --memory=512MiB \
  --timeout=300s \
  --set-env-vars GEMINI_API_KEY=YOUR_GEMINI_API_KEY
```

---

## Manuel Yükleme (Google Cloud Console Web Arayüzünden)

1. [Google Cloud Console](https://console.cloud.google.com/functions) sayfasına gidin.
2. **Create Function** butonuna tıklayın.
3. Ayarlar:
   - **Environment**: 2nd gen (veya Cloud Run)
   - **Function name**: `tyf-startlist-parser`
   - **Region**: `europe-west1` (veya `europe-west3`)
   - **Trigger**: HTTPS (Allow unauthenticated)
   - **Runtime**: Python 3.11
   - **Entry point**: `tyf_startlist_handler`
4. Kod sekmesinde:
   - `main.py` ve `requirements.txt` dosyalarını yapıştırın.
5. **Environment Variables**:
   - `GEMINI_API_KEY`: Sizin Gemini API anahtarınız.
6. **Deploy** butonuna tıklayın.
7. Oluşan HTTPS URL'sini `.env` dosyanıza `GOOGLE_CLOUD_FUNCTION_URL=https://...` olarak ekleyin.

---

## Django'dan Tetikleme Örneği:

```python
import requests

cf_url = "https://europe-west1-YOUR_PROJECT.cloudfunctions.net/tyf-startlist-parser"
payload = {
    "event_id": 5,
    "event_url": "https://canli.tyf.gov.tr/istanbul/cs-1005380/",
    "django_api_url": "https://your-domain.pythonanywhere.com/api/canli-aktar/",
    "callback_url": "https://your-domain.pythonanywhere.com/api/canli-durum-guncelle/",
    "async_mode": True,
    "mod": "sonuc_listesi",  # veya 'start_listesi'
    "limit": 3                # İsteğe bağlı test limiti
}

response = requests.post(cf_url, json=payload, timeout=10)
print(response.json())
```

