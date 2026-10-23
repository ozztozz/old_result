# Google Cloud Functions / Cloud Run - TYF Canlı Start & Sonuç Listesi Rutin Tarayıcısı

Bu servis, Google Cloud altyapısında (Cloud Functions gen2 veya Cloud Run) çalışarak TYF canlı yüzme yarışlarının start ve sonuç listelerini otomatik olarak ayrıştırır ve Django veritabanına aktarır.

---

## 🏗️ Mimari Mantığı (Pull Modeli / Rutin Tarama)

1. **Web Arayüzünden (PythonAnywhere) Cloud Run Tetiklenmez:**
   - Kullanıcı web arayüzünden canlı yarış linkini ekler veya var olan yarış için "Tara" butonuna basar.
   - Yarış durumu veritabanında `BEKLIYOR` olarak işaretlenir.
   - Web uygulamasından hiçbir harici HTTP çağrısı yapılmaz; bu sayede PythonAnywhere'deki istek zaman aşımı (timeout: 15-30 sn) ve proxy kısıtlamaları tamamen bertaraf edilir.

2. **Cloud Scheduler ile Periyodik Tarama (Pull):**
   - Cloud Scheduler belirli aralıklarla (ör: her 5 veya 10 dakikada bir) bu servisi tetikler (`GET` veya `POST`).
   - Servis Django API'sine (`https://ozztozz.pythonanywhere.com/api/canli-bekleyen-yarislar/`) sorgu atar.
   - Kuyrukta bekleyen yarış yoksa **0.5 saniyede 200 OK dönerek kapanır** (Cloud Run maliyeti ~0 TL olur).

3. **Akıllı Ayrıştırma & Mükerrerlik Koruması (ETag / SHA-256):**
   - Bekleyen yarış bulunduğunda durumu `ISLENIYOR` yapılır.
   - TYF canlı sonuç sayfasındaki tüm `StartList_*.pdf` ve `ResultList_*.pdf` bağlantıları taranır.
   - Her PDF indirilip hash/etag bilgisi `/api/canli-dosya-kontrol/` adresine sorulur.
   - Daha önce işlenmiş ve değişmemiş dosyalar **Gemini çağrısı yapılmadan atlanır** (%95 kota ve süre tasarrufu).
   - Yeni/güncellenen start listeleri Gemini Flash Lite ile çözümlenip `/api/canli-aktar/` adresine iletilir.
   - Yeni/güncellenen sonuç listelerinde, start listesindeki sporcuların veritabanı ID'leri Gemini promptuna enjekte edilerek $O(1)$ eşleştirme yapılır.
   - İşlem bitince durum `TAMAMLANDI` olarak güncellenir.

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
