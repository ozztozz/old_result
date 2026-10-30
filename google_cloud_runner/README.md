# TYF Canlı Start ve Sonuç PDF Parser'ı

Bu modül, TYF canlı yüzme yarışlarının start ve sonuç PDF'lerini Gemini ile ayrıştırır. Aktif tarama ve kalıcı kayıt akışı Django ORM üzerinden [`sonuclar.live_db_runner`](../yuzme_projesi/sonuclar/live_db_runner.py) tarafından yürütülür.

---

## Mimari

1. `canli_tara` Django management command'ı yarışları DB'den seçer.
2. [`live_db_runner.py`](../yuzme_projesi/sonuclar/live_db_runner.py) PDF'leri indirir ve değişmeyen dosyaları DB metadata'sıyla atlar.
3. Bu modül PDF sayfalarını ayrıştırır.
4. Start listesindeki `sporcu_maskeli` değeri `YarisSonucu` kaydında saklanır.
5. Result listesi adayları doğrudan DB'den okur; `seri + kulvar` ve maskeli ad üzerinden eşleştirilir.

---

## 🚀 Dağıtım (Deployment)

### Yöntem A: Google Cloud Console (Web Arayüzü)

1. [Google Cloud Console - Cloud Functions](https://console.cloud.google.com/functions) sayfasına gidin.
2. **Create Function** butonuna tıklayın:
   - **Environment**: 2nd gen (veya Cloud Run)
   - **Function name**: `tyf-live-scanner`
   - **Region**: `europe-west1` (veya `europe-west3`)
   - **Trigger**: HTTPS (`Allow unauthenticated invocations` seçin)
   - **Runtime**: Python 3.11
   - **Entry point**: `tyf_startlist_handler`
   - **Timeout**: `600s` (veya `300s`)
   - **Memory**: `512MiB` (veya `1GiB`)
3. **Environment Variables (Ortam Değişkenleri)** sekmesine ekleyin:
   - `GEMINI_API_KEY`: `AIzaSy...` (Gemini API anahtarınız)
   - `DJANGO_BASE_URL`: `https://ozztozz.pythonanywhere.com`
4. Kod sekmesinde `main.py` ve `requirements.txt` dosyalarını yükleyip **Deploy** butonuna basın.
5. Dağıtım tamamlandığında oluşan HTTPS tetikleme adresini kopyalayın (örn: `https://tyf-live-scanner-xyz-ew.a.run.app`).

---

### Yöntem B: Google Cloud CLI (`gcloud`)

```bash
cd google_cloud_runner

gcloud functions deploy tyf-live-scanner \
  --gen2 \
  --runtime=python311 \
  --region=europe-west1 \
  --source=. \
  --entry-point=tyf_startlist_handler \
  --trigger-http \
  --allow-unauthenticated \
  --memory=512MiB \
  --timeout=540s \
  --set-env-vars GEMINI_API_KEY=YOUR_GEMINI_API_KEY,DJANGO_BASE_URL=https://ozztozz.pythonanywhere.com
```

---

## ⏰ Cloud Scheduler İle Otomatik Rutin Tarama Ayarı

Cloud Run fonksiyonunuzun belirli aralıklarla çalışması için:

1. [Google Cloud Console - Cloud Scheduler](https://console.cloud.google.com/cloudscheduler) sayfasına gidin.
2. **Create Job** butonuna tıklayın:
   - **Name**: `tyf-live-routine-scan`
   - **Region**: `europe-west1`
   - **Frequency (Cron)**: 
     - Hafta sonları veya yarış günleri: `*/5 * * * *` (Her 5 dakikada bir)
     - Standart tarama: `*/10 * * * *` (Her 10 dakikada bir)
   - **Timezone**: `Turkey (UTC+3)`
3. **Configure the execution (Hedef Ayarı)**:
   - **Target type**: `HTTP`
   - **URL**: Cloud Run fonksiyon URL'niz (Örn: `https://tyf-live-scanner-xyz-ew.a.run.app`)
   - **HTTP method**: `GET` (veya boş gövdeli `POST`)
4. **Create** butonuna basarak kaydedin.

Artık siz web sitesinden yeni bir yarış linki eklediğinizde veya "Tara"ya bastığınızda, Cloud Run ilk tetiklemede bekleyen yarışları otomatik çekecek, gerekli işlemleri yapıp kapanacaktır.

---

## 💻 Yerel (Local) ve Manuel Test

Cloud Run'a yüklemeden önce kendi bilgisayarınızda test etmek için:

```bash
# 1. Rutin tarama testi (PythonAnywhere üzerinde bekleyen yarışları sorgular):
python google_cloud_runner/main.py --base-url https://ozztozz.pythonanywhere.com

# 2. Yerel Django sunucunuz üzerinde test (her yarış için azami 1 PDF):
python google_cloud_runner/main.py --base-url http://127.0.0.1:8000 --limit 1

# 3. Belirli bir yarış linkini doğrudan test etme:
python google_cloud_runner/main.py --url https://canli.tyf.gov.tr/istanbul/cs-1005380/ --limit 2
```
