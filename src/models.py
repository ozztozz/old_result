"""
src/models.py
Sorumluluk: Veri yapılarının tanımlanması ve validasyonu (Pydantic).
"""

from typing import Optional, Dict, List
from pydantic import BaseModel, Field

class CompetitionMetadata(BaseModel):
    """Müsabaka / Yarış Temel Bilgileri (Tüm dosya için geçerli meta veriler)."""
    dosya_adi: str = Field(..., description="Sonuç metin dosyasının adı")
    yaris_adi: str = Field(..., description="Yarış / Müsabaka Adı (örn: Analig Seçme Müsabakası)")
    yaris_yeri: str = Field(..., description="Yarış Yeri / Şehir (örn: ANKARA)")
    yaris_tarihi: str = Field(..., description="Yarış Tarihi / Tarih Aralığı (örn: 11. - 12.6.2024)")


class RaceBlockMetadata(BaseModel):
    """Yarış Bloğu Başlık Bilgileri (Her bir yarış başlangıcı)."""
    dosya_adi: str = Field(..., description="Sonuç dosyasının adı")
    sayfa_no: int = Field(..., description="Yarışın başladığı sayfa numarası")
    satir_no: int = Field(..., description="Yarış başlığının dosyadaki satır numarası")
    yaris_no: str = Field(..., description="Yarış Numarası (örn: 1)")
    cinsiyet: str = Field(..., description="Cinsiyet (örn: Kızlar, Erkekler, Bayanlar, Karma)")
    mesafe: str = Field(..., description="Mesafe (örn: 50, 100, 4 x 50m)")
    tur: str = Field(..., description="Yarış Türü / Stili (örn: Sırtüstü, Serbest, Kurbağalama, Kelebek, Karışık)")
    yas: str = Field(..., description="Yaş Grubu (örn: 8, 10, 11 - 12, 13+, Açık)")
    bayrak_mi: bool = Field(False, description="Bayrak yarışı mı? (4 x 50m vb.)")
    ham_baslik: str = Field(..., description="Orijinal yarış başlığı satırı")


class SwimmerResultLine(BaseModel):
    """Bireysel Yüzücü Sonuç Satırı Modeli."""
    dosya_adi: str = Field(..., description="Sonuç dosyasının adı")
    yaris_no: str = Field(..., description="Yarış numarası")
    sayfa_no: int = Field(..., description="Yer aldığı sayfa numarası")
    satir_no: int = Field(..., description="Sonuç satırının dosyadaki satır numarası")
    sira: str = Field(..., description="Sıra / Dereceleme (örn: 1, 10, td)")
    sporcu: str = Field(..., description="Sporcunun Adı Soyadı ((Tk),(Td),(Fd) temizlenmiş)")
    yas: Optional[str] = Field(None, description="Doğum yılı veya Yaş (örn: 14, 15)")
    kulup: str = Field(..., description="Kulüp veya Okul Adı ((Tk),(Td),(Fd) temizlenmiş)")
    derece: str = Field(..., description="Yarış derecesi / bitiriş süresi (örn: 5:10.26, 1:15.00)")
    derece_sn: Optional[float] = Field(None, description="Yarış derecesinin saniye cinsinden sayısal değeri (örn: 310.26, 75.00)")
    puan: Optional[str] = Field(None, description="AQUA/FINA puanı (örn: 436, 327)")
    baraj: Optional[str] = Field(None, description="Baraj geçme bilgisi (örn: KATILIM BARAJINI GEÇTİ)")
    is_tied: bool = Field(False, description="Sıra numarası olmayan beraberlik satırı mı?")
    zaman_kontrol: str = Field("GEÇERLİ", description="Önceki satırla zaman tutarlılık kontrolü durumu")
    uyari_notu: Optional[str] = Field(None, description="Varsa tutarsızlık veya uyarı açıklaması")
    ham_satir: str = Field(..., description="Orijinal sonuç satırı metni")



class DisqualificationMetadata(BaseModel):
    """Diskalifiye (DQ) ve Yarış Terk (DNF) Kaydı Modeli."""
    dosya_adi: str = Field(..., description="Sonuç dosyasının adı")
    yaris_no: str = Field(..., description="Yarış numarası")
    sayfa_no: int = Field(..., description="Yer aldığı sayfa numarası")
    satir_no: int = Field(..., description="Dosyadaki satır numarası")
    disk: str = Field("evet", description="Diskalifiye durumu (evet)")
    sporcu: str = Field(..., description="Sporcu veya takım adı")
    yas: Optional[str] = Field(None, description="Yaş / Doğum yılı (örn: 15, 12)")
    kulup: str = Field(..., description="Kulüp veya okul adı")
    gerekce: str = Field(..., description="Diskalifiye veya terk gerekçesi (örn: SW 10.2..., yarış terk)")
    zaman: Optional[str] = Field(None, description="Varsa kaydedilen ara zaman / süre")
    bayrak_mi: bool = Field(False, description="Bayrak takımı mı?")
    ham_satir: str = Field(..., description="Orijinal ilk satır metni")



class MeetInfo(BaseModel):
    """Genel Müsabaka / Yarışma Bilgisi."""
    name: str = ""                 # Müsabaka Adı (örn: "10 Yaş Ankara İl Baraj Geçme Müsabakası")
    location: str = ""             # Müsabakanın Yapıldığı Yer / Şehir (örn: "Ankara")
    date_range: str = ""           # Müsabaka Tarih Aralığı (örn: "22. - 23.3.2025")

class EventInfo(BaseModel):
    """Her bir PDF yarış kategorisinin meta verisi."""
    # Müsabaka Genel Bilgileri
    # Seans ve Yarış Bilgileri
    session: str = ""              # Örn: "1. GÜN SABAH SEANSI (22.03.2025)"
    race_number: str               # Örn: "1"
    gender: str                    # 'M' veya 'F'
    distance: int                  # 50, 100, 200, 400, 800, 1500
    stroke: str                    # 'Serbest', 'Sırtüstü', 'Kurbağalama', 'Kelebek', 'Karışık'
    age_group: str = ""            # Örn: "10 yaş", "14 yaş ve büyükler", "11 - 12"
    event_date: str = ""           # Bu spesifik yarışın tarihi (örn: "22.03.2025")
    event_time: str = ""           # Bu spesifik yarışın başlama saati (örn: "09:30")
    series: str = ""               # "Prelim", "Final" vb. (isteğe bağlı)
    is_relay: bool = False         # Bayrak yarışı mı? (örn: 4 x 50m)
    relay_count: Optional[int] = None # Bayrak sporcu sayısı (örn: 4)
    page_number: Optional[int] = None # Başladığı sayfa numarası

class RelaySwimmer(BaseModel):
    """Bayrak takımındaki tek bir yüzücünün bilgisi."""
    name: str                      # Sporcu Adı Soyadı
    name_raw: str = ""             # Belgeden okunan orijinal isim
    birth_year: Optional[int] = None # Doğum yılı
    split_time: Optional[str] = None # Bacak / Ara derecesi (örn: "45.29" veya "50.62")

class RelayResultEntry(BaseModel):
    """Bayrak yarışı takım sonucu ve takım sporcuları."""
    # Müsabaka / Organizasyon Bilgileri
    meet_name: str = ""
    meet_location: str = ""
    meet_date: str = ""
    page_number: Optional[int] = None # Bulunduğu sayfa numarası

    # Seans ve Kategori Bilgileri
    session: str = ""
    race_number: str
    gender: str                    # 'M', 'F', 'X'
    relay_count: int = 4           # 4
    distance: int                  # 50, 100 vb.
    stroke: str                    # Serbest, Karışık vb.
    age_group: str = ""
    race_date: str = ""
    race_time: str = ""

    # Takım ve Kulüp Bilgileri
    rank: Optional[int] = None     # Sıra
    team_name: str                 # Takım Adı (örn: "V.A.M.O.S" veya "Kulvar Spor Kulübü")
    club: str                      # Kulüp Adı
    participation_type: Optional[str] = None

    # Derece ve Puan
    time_txt: Optional[str] = None # Takım Derecesi
    time_sec: Optional[float] = None
    points: Optional[int] = None
    status: str = "OK"             # 'OK', 'DQ', 'DNS'
    dq_rule: str = ""
    dq_reason: str = ""

    # Takım Sporcuları
    swimmers: List[RelaySwimmer] = Field(default_factory=list)

class SwimmerResultEntry(BaseModel):
    """Yarış sonuç listesinden çıkarılan detaylı sporcu derecesi ve durumu."""
    # Müsabaka / Organizasyon Bilgileri
    meet_name: str = ""            # Müsabaka Adı (örn: "10 Yaş Ankara İl Baraj Geçme Müsabakası")
    meet_location: str = ""        # Müsabakanın Yapıldığı Yer (örn: "Ankara")
    meet_date: str = ""            # Müsabaka Tarih Aralığı (örn: "22. - 23.3.2025")
    page_number: Optional[int] = None # Bulunduğu sayfa numarası

    # Seans ve Kategori Bilgileri
    session: str = ""              # Seans Adı
    race_number: str               # Yarış No
    gender: str                    # Cinsiyet ('M' / 'F')
    distance: int                  # Mesafe (50, 100, 200 vb.)
    stroke: str                    # Stil (Serbest, Sırtüstü vb.)
    age_group: str = ""            # Yaş Grubu (örn: "10 yaş")
    race_date: str = ""            # Yarış Günü Tarihi (örn: "22.03.2025")
    race_time: str = ""            # Yarış Saati (örn: "09:30")

    # Sporcu ve Kulüp Bilgileri
    rank: Optional[int] = None     # Sıra no
    name: str                      # Sporcu Adı Soyadı (Düzeltilmiş / Temiz)
    name_raw: str = ""             # Belgeden okunan orijinal ham isim
    birth_year: int                # Doğum Yılı (örn: 2015)
    club: str                      # Kulüp / Okul Adı (Düzeltilmiş / Standart)
    club_raw: str = ""             # Belgeden okunan orijinal ham kulüp
    participation_type: Optional[str] = None # Katılım Türü: 'Takım' (Tk), 'Ferdi' (Fd), 'Takım Dışı' (Td)

    # Derece ve Puanlar
    time_txt: Optional[str] = None # Derece (örn: "1:17.22")
    time_sec: Optional[float] = None # Saniye (örn: 77.22)
    points: Optional[int] = None   # AQUA / FINA Puanı

    # Durum ve Ek Bilgiler
    qualified: bool = False        # "KATILIM BARAJINI GEÇTİ"
    status: str = "OK"             # 'OK', 'DQ', 'DNS', 'DNF'
    dq_rule: str = ""              # Diskalifiye Kuralı (örn: "SW 4.4")
    dq_reason: str = ""            # Diskalifiye Nedeni
    dq_clock: str = ""             # Diskalifiye Saati (örn: "09:42")

    row_times: List[str] = Field(default_factory=list) # Satırdaki ara süreler
    splits: Dict[str, str] = Field(default_factory=dict) # 400m+ split süreleri

class SwimmerEntry(BaseModel):
    """Start listesinden çıkarılan tek bir sporcu kaydı (Geriye uyumluluk için korundu)."""
    name_raw: str
    birth_year: int
    gender: str
    stroke: str
    distance: int
    race_number: str
    serie: str = ""
    series_total: str = ""
    start_line: int = 200
    club_raw: str
    entry_time_sec: Optional[float] = None
    entry_time_txt: Optional[str] = None
    
    # Web kazımadan beslenen dinamik alanlar (opsiyonel)
    event_url: Optional[str] = None
    event_title: Optional[str] = None
    event_location: Optional[str] = None
    event_date: Optional[str] = None

class RacePageInfo(BaseModel):
    """HTML sayfasından kazınan genel yarış bilgileri ve linkler."""
    title: str
    location: str
    date: str
    pdf_links: List[str] = Field(default_factory=list)
    start_list_links: List[str] = Field(default_factory=list)

class UnparsedLine(BaseModel):
    """Ayrıştırılamayan, atlanan veya kural dışı kalan satır bilgisi."""
    file_name: str = ""
    line_number: int               # Dosyadaki 1-indexed satır numarası
    raw_text: str                  # Ham metin
    reason: str = ""               # İşlenmeme sebebi
    meet_name: str = ""            # Bağlı olduğu yarış
    session: str = ""              # Bağlı olduğu seans
    event_title: str = ""          # Bağlı olduğu kategori başlığı
