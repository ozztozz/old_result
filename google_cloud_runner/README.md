# Google Cloud Functions - TYF Canlı Start Listesi İşleyicisi

Bu servis, Google Cloud altyapısında (Cloud Functions gen2 veya Cloud Run) çalışarak PythonAnywhere'in harici indirme (proxy) kısıtlamasını tamamen çözer.

## Nasıl Çalışır?
1. Django arayüzünden (veya kullanıcının girdiği) TYF canlı yarış URL'si bu Cloud Function'a iletilir.
2. Cloud Function, Google sunucuları üzerinden `canli.tyf.gov.tr` sayfasına bağlanır ve tüm `StartList_*.pdf` dosyalarını bulup indirir.
3. Gemini Flash Lite (`gemini-flash-lite-latest`) ile PDF'leri paralel olarak ayrıştırır.
4. Elde edilen yapılandırılmış start listesi verisini doğrudan PythonAnywhere üzerindeki Django API'sine (`https://<user>.pythonanywhere.com/api/canli-aktar/`) POST eder.

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
   - **Environment**: 2nd gen
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
7. Oluşan HTTPS URL'sini `.env` dosyanıza `GOOGLE_CLOUD_FUNCTION_URL=...` olarak ekleyin.

---

## Django'dan Tetikleme Örneği:

```python
import requests

cf_url = "https://europe-west1-YOUR_PROJECT.cloudfunctions.net/tyf-startlist-parser"
payload = {
    "event_url": "https://canli.tyf.gov.tr/istanbul/cs-1005380/",
    "django_api_url": "https://your-domain.pythonanywhere.com/api/canli-aktar/"
}

response = requests.post(cf_url, json=payload, timeout=300)
print(response.json())
```

