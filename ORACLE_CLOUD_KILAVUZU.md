# Oracle Cloud Sunucu Yönetim ve Kullanım Kılavuzu

Bu kılavuz, Oracle Cloud üzerinde çalışan **Yüzme Projesi (Sonuçlar & Canlı Takip)** ve **Kulüp Yönetim Sistemi** altyapısını yönetmeniz, kod güncellemelerini yayınlamanız, servisleri izlemeniz ve canlı yarışları taratmanız için gereken tüm bilgileri ve komutları içerir.

---

## 1. Sunucu Bilgileri ve Bağlantı

- **Sunucu IP Adresi:** `130.61.177.72`
- **Varsayılan Kullanıcı:** `ubuntu`
- **Web Adresleri:**
  - 🏊 **Yüzme Projesi:** [https://yuzme.duckdns.org](https://yuzme.duckdns.org) *(veya http://130.61.177.72)*
  - 🏆 **Kulüp Yönetim Sistemi:** [https://fkalpha.duckdns.org](https://fkalpha.duckdns.org)

### SSH ile Sunucuya Bağlanma
Bilgisayarınızın terminalinden (PowerShell veya Bash):
```bash
ssh -i /path/to/your-private-key.key ubuntu@130.61.177.72
```

---

## 2. Dizin Yapısı ve Mimarisi

Sunucu üzerinde iki ana proje bağımsız Gunicorn servisleri ve ortak Nginx ters vekili (reverse proxy) üzerinden çalışmaktadır:

| Proje | Dizin | Sanal Ortam (venv) | Veritabanı | Systemd Servisi |
| :--- | :--- | :--- | :--- | :--- |
| **Yüzme Projesi** | `/home/ubuntu/app/yuzme_projesi` | `/home/ubuntu/app/venv` | `/home/ubuntu/database/yuzme_veritabani.db` | `yuzme.service` |
| **Kulüp Yönetimi** | `/home/ubuntu/kulup_yonetim/swim_club_project` | `/home/ubuntu/kulup_yonetim/venv` | `/home/ubuntu/kulup_yonetim/swim_club_project/db.sqlite3` | `kulup.service` |
| **Yedekler** | `/home/ubuntu/backups/` | - | Otomatik gzip'li SQLite .db yedekleri | Cron job (`backup_db.sh`) |

---

## 3. En Çok Kullanılan Servis Komutları (Hızlı Başvuru)

### Servis Durumlarını İnceleme
```bash
# Yüzme projesi durumu
sudo systemctl status yuzme

# Kulüp yönetim projesi durumu
sudo systemctl status kulup

# Nginx web sunucusu durumu
sudo systemctl status nginx
```

### Servisleri Yeniden Başlatma (Restart)
Kod güncellemesi, ayar değişikliği veya kilitlenme durumunda:
```bash
# Sadece Yüzme projesini yeniden başlat
sudo systemctl restart yuzme

# Sadece Kulüp yönetim projesini yeniden başlat
sudo systemctl restart kulup

# Nginx'i yeniden başlat
sudo systemctl restart nginx
```

### Canlı Logları Takip Etme
Uygulamada bir hata olduğunda canlı log akışını görmek için:
```bash
# Yüzme projesinin canlı Django/Gunicorn logları (çıkmak için Ctrl+C)
journalctl -u yuzme -f

# Kulüp yönetim projesinin logları
journalctl -u kulup -f

# Nginx erişim ve hata logları
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log
```

---

## 4. Yeni Kod Güncellemesini Canlıya Alma (Deployment)

Yerelde yaptığınız değişiklikleri sunucuya çekip aktif etmek için aşağıdaki adımları sırayla çalıştırın:

### Yüzme Projesi Güncelleme
```bash
# 1. Proje ana dizinine gidin
cd /home/ubuntu/app

# 2. Git güncellemelerini çekin
git pull origin main  # veya origin master

# 3. Sanal ortama girin
source venv/bin/activate

# 4. Yeni Python kütüphanesi eklendiyse yükleyin
pip install -r requirements.txt
pip install -r google_cloud_runner/requirements.txt

# 5. Django dizinine geçip statik dosyaları derleyin
cd yuzme_projesi
python manage.py collectstatic --noinput

# 6. Veritabanı şema değişikliği (migration) varsa uygulayın
python manage.py migrate

# 7. Servisi yeniden başlatın
sudo systemctl restart yuzme
```

---

## 5. TYF Canlı Yarış Takibi ve Tarama

Canlı yarış taraması iki farklı yöntemle yürütülebilir:

### Yöntem A: Web Arayüzünden (Önerilen)
1. Tarayıcınızda [https://yuzme.duckdns.org/canli-yarislar/](https://yuzme.duckdns.org/canli-yarislar/) sayfasına gidin.
2. **"Yeni Canlı Yarış Ekle"** butonuna basarak TYF canlı linkini (örn: `https://canli.tyf.gov.tr/ankara/cs-1005675/`) yapıştırın.
3. Listede yarışın yanındaki **"Tara"** (`▶`) butonuna tıklayın.
4. Terminal simgesine (`>_`) tıklayarak ilerlemeyi ve Gemini'nin ayrıştırdığı serileri canlı modal penceresinden takip edin.

### Yöntem B: Terminalden Manuel Tarayıcı Çalıştırma
Gerektiğinde veya toplu taramalarda SSH terminali üzerinden doğrudan runner'ı tetikleyebilirsiniz:
```bash
cd /home/ubuntu/app
source venv/bin/activate

# Bekleyen tüm canlı yarışları arka planda rutin tara
python google_cloud_runner/main.py --base-url http://127.0.0.1

# Ya da doğrudan tekil bir TYF linkini test ederek tara
python google_cloud_runner/main.py --url "https://canli.tyf.gov.tr/ankara/cs-1005675/" --base-url http://127.0.0.1
```

> [!NOTE]
> Projede **Gemini Kota Koruması** devrededir. `.env` dosyanızda `GEMINI_API_KEY` kotası dolduğunda otomatik olarak `GEMINI_API_KEY_2` devreye girer.

---

## 6. Veritabanı Yedekleme ve Kurtarma

Sunucuda otomatik yedekleme cron servisi tanımlıdır.

### Manuel Yedek Alma
Herhangi bir büyük işlem veya güncelleme öncesi anında yedek almak için:
```bash
bash /home/ubuntu/scripts/backup_db.sh
```
Yedekler `/home/ubuntu/backups/` dizininde tarih-saat damgasıyla gzip sıkıştırmalı olarak saklanır (`yuzme_YYYYMMDD_HHMMSS.db.gz`). 7 günden eski yedekler otomatik temizlenir.

### Yedeği Geri Yükleme (Restore)
Olası bir veri kaybında yedeği geri yüklemek için:
```bash
# 1. Yüzme servisini durdurun
sudo systemctl stop yuzme

# 2. Seçtiğiniz yedeği açın
gunzip -c /home/ubuntu/backups/yuzme_20261029_120000.db.gz > /home/ubuntu/database/yuzme_veritabani.db

# 3. Dosya izinlerini ubuntu kullanıcısına verin
sudo chown ubuntu:ubuntu /home/ubuntu/database/yuzme_veritabani.db

# 4. Servisi tekrar başlatın
sudo systemctl start yuzme
```

---

## 7. Sık Karşılaşılan Sorunlar ve Çözümleri

### 1. Web Sitesinde "502 Bad Gateway" Hatası
- **Sebep:** Gunicorn servisi durmuş veya bir hata nedeniyle başlamamış olabilir.
- **Çözüm:**
  ```bash
  sudo systemctl status yuzme
  journalctl -u yuzme -n 50 --no-pager
  sudo systemctl restart yuzme
  ```

### 2. Disk Doluluğu Kontrolü
Oracle Always Free sunucularında disk dolarsa veritabanı kilitlenebilir:
```bash
# Disk kullanım oranını kontrol et
df -h /

# Bellek ve işlemci durumunu izle
free -m
htop
```

### 3. Nginx Ayarlarını Test Etme
Nginx yapılandırmasını değiştirdiğinizde servisi yeniden başlatmadan önce syntax hatası olup olmadığını test edin:
```bash
sudo nginx -t
sudo systemctl reload nginx
```

