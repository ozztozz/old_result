/// TYF Takvim, Reglaman ve Milli Takım Kriterleri Haber Bandı Modeli
class TyfNewsItem {
  final int id;
  final String belgeTuru;
  final String baslik;
  final String revizyonEtiketi;
  final String tarihMetni;
  final String baslangicTarihi;
  final String bitisTarihi;
  final String sehirYer;
  final String havuz;
  final String yasGrubu;
  final int? minYas;
  final int? maxYas;
  final String ozet;
  final List<String> onemliNotlar;
  final int? eventId;
  final int barajSayisi;
  final String pdfUrl;
  final String sourceUrl;
  final String guncellenmeTarihi;

  const TyfNewsItem({
    required this.id,
    required this.belgeTuru,
    required this.baslik,
    this.revizyonEtiketi = '',
    this.tarihMetni = '',
    this.baslangicTarihi = '',
    this.bitisTarihi = '',
    this.sehirYer = '',
    this.havuz = '',
    this.yasGrubu = '',
    this.minYas,
    this.maxYas,
    this.ozet = '',
    this.onemliNotlar = const [],
    this.eventId,
    this.barajSayisi = 0,
    this.pdfUrl = '',
    this.sourceUrl = '',
    this.guncellenmeTarihi = '',
  });

  factory TyfNewsItem.fromJson(Map<String, dynamic> json) {
    final notesRaw = json['onemli_notlar'] as List<dynamic>? ?? const [];
    return TyfNewsItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      belgeTuru: (json['belge_turu'] as String?) ?? 'DUYURU',
      baslik: (json['baslik'] as String?) ?? '',
      revizyonEtiketi: (json['revizyon_etiketi'] as String?) ?? '',
      tarihMetni: (json['tarih_metni'] as String?) ?? '',
      baslangicTarihi: (json['baslangic_tarihi'] as String?) ?? '',
      bitisTarihi: (json['bitis_tarihi'] as String?) ?? '',
      sehirYer: (json['sehir_yer'] as String?) ?? '',
      havuz: (json['havuz'] as String?) ?? '',
      yasGrubu: (json['yas_grubu'] as String?) ?? '',
      minYas: (json['min_yas'] as num?)?.toInt(),
      maxYas: (json['max_yas'] as num?)?.toInt(),
      ozet: (json['ozet'] as String?) ?? '',
      onemliNotlar: notesRaw.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList(),
      eventId: (json['event_id'] as num?)?.toInt(),
      barajSayisi: (json['baraj_sayisi'] as num?)?.toInt() ?? 0,
      pdfUrl: (json['pdf_url'] as String?) ?? '',
      sourceUrl: (json['source_url'] as String?) ?? '',
      guncellenmeTarihi: (json['guncellenme_tarihi'] as String?) ?? '',
    );
  }

  String get turEtiketi {
    switch (belgeTuru.toUpperCase()) {
      case 'TAKVIM':
        return 'TAKVİM';
      case 'REGLAMAN':
        return 'REGLAMAN';
      case 'MILLI_TAKIM':
        return 'MİLLİ TAKIM';
      default:
        return 'DUYURU';
    }
  }
}
