# Türkiye Yüzme Sonuçları & Analiz Platformu (Django)

Bu Django projesi, Türkiye Yüzme Federasyonu'nun metin tabanlı ve taranmış (OCR) yarış sonuçlarından türetilen **482.362 bireysel yarış sonucunu**, **41.360 tekil sporcuyu** ve **4.242 kulübü** ilişkisel olarak sorgulayan, listeleyen ve analiz eden modern bir web uygulamasıdır.

---

## 🚀 Hızlı Başlangıç

1. Proje dizinine girin:
   ```bash
   cd yuzme_projesi
   ```

2. Geliştirme sunucusunu başlatın:
   ```bash
   python manage.py runserver
   ```

3. Tarayıcınızdan açın:
   - **Ana Sayfa:** [http://127.0.0.1:8000/](http://127.0.0.1:8000/)
   - **Sporcular:** [http://127.0.0.1:8000/sporcular/](http://127.0.0.1:8000/sporcular/)
   - **Kulüpler:** [http://127.0.0.1:8000/kulupler/](http://127.0.0.1:8000/kulupler/)
   - **Yarış Sonuçları Arama:** [http://127.0.0.1:8000/sonuclar/](http://127.0.0.1:8000/sonuclar/)
   - **Yönetim Paneli:** [http://127.0.0.1:8000/admin/](http://127.0.0.1:8000/admin/)

---

## 🔐 Yönetim Paneli Giriş Bilgileri

- **Kullanıcı Adı:** `admin`
- **Şifre:** `admin123`

---

## 📂 Sayfa Özellikleri

### 1. Ana Sayfa (`/`)
- Toplam yarış (482.362), sporcu (41.360), kulüp (4.242) ve transfer dönemi (59.460) kartları.
- Hızlı sporcu ve kulüp arama çubuğu.
- En çok yarışa katılan aktif yüzücüler ve en çok sporcusu olan kulüpler.

### 2. Sporcular Sayfaları (`/sporcular/` & `/sporcular/<id>/`)
- **Sporcu Listesi:** İsim, yaş, kulüp ve cinsiyet filtreleri, sayfalama (pagination).
- **Sporcu Detay Sayfası:**
  - Sporcu künyesi (yaş, cinsiyet, birincil kulüp, kariyer tarih aralığı).
  - **Kulüp Transfer Tarihçesi (Timeline):** Sporcunun hangi tarihler arasında hangi kulüpte yarıştığı, dönem sırası ve aktif kulüp etiketi.
  - **Kişisel En İyi Dereceler (PB):** 50m, 100m vb. branşlarda sporcunun yaptığı en iyi süreler ve yapıldığı müsabaka.
  - **Yarış Geçmişi:** Sayfalanmış kronolojik tüm yarış sonuçları tablosu.

### 3. Kulüpler Sayfaları (`/kulupler/` & `/kulupler/<id>/`)
- **Kulüp Listesi:** Kulüp adına göre arama, yarış ve sporcu sayısına göre sıralama.
- **Kulüp Detay Sayfası:**
  - Kulübün temsil ettiği sporcuların listesi (aktif/geçmiş dönem).
  - Kulübün katıldığı son yarışlar ve dereceler.

### 4. Yarış Sonuçları Arama Motoru (`/sonuclar/`)
- Branş (Serbest, Sırtüstü, Kurbağalama, Kelebek, Karışık), mesafe (50, 100, 200, 400, 800, 1500m), müsabaka, kulüp, sporcu adı ve cinsiyete göre çok kriterli filtreleme.

