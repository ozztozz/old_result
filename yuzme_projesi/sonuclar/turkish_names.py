# -*- coding: utf-8 -*-
"""
turkish_names.py
================
Veritabanındaki sporcu isimlerinde Türkçe karakterlerden (İ/I, ı/i, Ş/S, Ğ/G, Ü/U, Ö/O, Ç/C),
Python'un standart .lower()/.upper()/.capitalize() fonksiyonlarının ürettiği hatalardan
(örn: 'İ'.lower() -> 'i\\u0307', 'ÇINAR'.capitalize() -> 'Çinar', 'Demir'.upper() -> 'DEMIR',
'ELIF' -> 'Elıf', 'Yilmaz' -> 'YİLMAZ') ve PDF/OCR kaynaklı imla bozulmalarından kaynaklanan
hataları düzeltir; aynı sporcunun Türkçe karakter farkıyla oluşmuş mükerrer kayıtlarını birleştirir.
"""

from __future__ import annotations

import os
import re
import sqlite3
import time
from collections import Counter, defaultdict
from typing import Any, Dict, List, Optional, Tuple

TR_UPPER_MAP = {
    "i": "İ",
    "ı": "I",
    "ç": "Ç",
    "ğ": "Ğ",
    "ö": "Ö",
    "ş": "Ş",
    "ü": "Ü",
}

TR_LOWER_MAP = {
    "İ": "i",
    "I": "ı",
    "Ç": "ç",
    "Ğ": "ğ",
    "Ö": "ö",
    "Ş": "ş",
    "Ü": "ü",
}

TR_FOLD_MAP = str.maketrans({
    "İ": "i", "I": "i", "ı": "i", "i": "i",
    "Ş": "s", "ş": "s",
    "Ğ": "g", "ğ": "g",
    "Ü": "u", "ü": "u",
    "Ö": "o", "ö": "o",
    "Ç": "c", "ç": "c",
    "Â": "a", "â": "a",
    "Î": "i", "î": "i",
    "Û": "u", "û": "u",
})

# Sadece I/İ/ı/i ve şapkalı ünlü farklarını katlayan harita
TR_I_FOLD_MAP = str.maketrans({
    "İ": "i", "I": "i", "ı": "i", "i": "i",
    "Â": "a", "â": "a",
    "Î": "i", "î": "i",
    "Û": "u", "û": "u",
})

# Doğrudan bilinen ilk isim düzeltmeleri (anahtar: tr_fold(isim) veya spesifik bozuk yazım)
KNOWN_FIRST_NAMES: Dict[str, str] = {
    # İ ile başlayanlar
    "ibrahim": "İbrahim", "ibrahimcan": "İbrahimcan", "iclal": "İclal",
    "idil": "İdil", "idris": "İdris", "iffet": "İffet", "ihsan": "İhsan",
    "ikbal": "İkbal", "iklim": "İklim", "ikra": "İkra", "ikranur": "İkranur",
    "ikrasu": "İkrasu", "ilay": "İlay", "ilayda": "İlayda", "ilbars": "İlbars",
    "ilber": "İlber", "ilbey": "İlbey", "ilbilge": "İlbilge", "ilgar": "İlgar",
    "ilhak": "İlhak", "ilhami": "İlhami", "ilhan": "İlhan",
    "ilimsu": "İlimsu", "ilkan": "İlkan", "ilkay": "İlkay", "ilkben": "İlkben",
    "ilke": "İlke", "ilkem": "İlkem", "ilker": "İlker", "ilkim": "İlkim",
    "ilkin": "İlkin", "ilknur": "İlknur", "ilkut": "İlkut", "ilsu": "İlsu",
    "ilter": "İlter", "ilteris": "İlteriş", "ilve": "İlve", "ilyada": "İlyada",
    "ilyas": "İlyas", "imay": "İmay", "imer": "İmer", "imge": "İmge",
    "imran": "İmran", "inal": "İnal", "inan": "İnan", "inanc": "İnanç",
    "ince": "İnce", "inci": "İnci", "incila": "İncila", "incisu": "İncisu",
    "insirah": "İnşirah", "ipek": "İpek", "ipeknur": "İpeknur", "ipeksu": "İpeksu",
    "irem": "İrem", "iremsu": "İremsu", "irena": "İrena", "irfan": "İrfan",
    "iris": "İris", "isa": "İsa", "ishak": "İshak", "iskender": "İskender",
    "islam": "İslam", "ismail": "İsmail", "ismet": "İsmet", "isra": "İsra",
    "istanbul": "İstanbul", "istem": "İstem", "iz": "İz", "izay": "İzay",
    "izem": "İzem", "izge": "İzge", "izgi": "İzgi", "izlin": "İzlin",
    "izmir": "İzmir", "izzet": "İzzet",
    # I ile başlayanlar
    "irmak": "Irmak", "isil": "Işıl", "isilay": "Işılay", "isilti": "Işıltı",
    "isik": "Işık", "isikhan": "Işıkhan", "isinsu": "Işınsu", "isin": "Işın",
    "ilgin": "Ilgın", "ilgim": "Ilgım", "ilgaz": "Ilgaz",
    "iltan": "Iltan", "itir": "Itır",
    "daniil": "Daniil", "belkis": "Belkıs",
    # Çok sık geçen ve Elıf/Alı/Denız/Emır gibi ı/i bozulmasına uğrayan isimler
    "elif": "Elif", "ali": "Ali", "deniz": "Deniz", "emir": "Emir",
    "derin": "Derin", "demir": "Demir", "nil": "Nil", "nehir": "Nehir",
    "nisa": "Nisa", "mina": "Mina", "selim": "Selim", "ecrin": "Ecrin",
    "miray": "Miray", "melis": "Melis", "beril": "Beril", "bilge": "Bilge",
    "emin": "Emin", "ceylin": "Ceylin", "hira": "Hira", "ekin": "Ekin",
    "hatice": "Hatice", "esila": "Esila", "salih": "Salih", "belinay": "Belinay",
    "melih": "Melih", "simay": "Simay", "aylin": "Aylin", "kadir": "Kadir",
    "hilal": "Hilal", "emirhan": "Emirhan", "elvin": "Elvin", "yasin": "Yasin",
    "bilal": "Bilal", "pelin": "Pelin", "selin": "Selin", "almina": "Almina",
    "timur": "Timur", "melike": "Melike", "aysima": "Aysima", "eliz": "Eliz",
    "nisanur": "Nisanur", "dilara": "Dilara", "minel": "Minel", "almila": "Almila",
    "gizem": "Gizem", "asil": "Asil", "nilay": "Nilay", "mavi": "Mavi",
    "nida": "Nida", "berfin": "Berfin", "alisa": "Alisa", "bedirhan": "Bedirhan",
    "zeliha": "Zeliha", "civan": "Civan", "atilla": "Atilla", "zeki": "Zeki",
    "amir": "Amir", "esin": "Esin", "nihan": "Nihan", "didem": "Didem",
    "sina": "Sina", "dilek": "Dilek", "alina": "Alina", "yasir": "Yasir",
    "hulusi": "Hulusi", "lavin": "Lavin", "havin": "Havin", "lalin": "Lalin",
    "narin": "Narin", "ayliz": "Ayliz", "simal": "Şimal", "samil": "Şamil",
    # İçinde ı/i, ş/s, ğ/g, ç/c, ö/o, ü/u bulunan yaygın Türkçe isimler
    "cinar": "Çınar", "pinar": "Pınar", "baris": "Barış", "yagiz": "Yağız",
    "yagizhan": "Yağızhan", "yagmur": "Yağmur", "kivanc": "Kıvanç", "kirac": "Kıraç",
    "kilic": "Kılıç", "kiymet": "Kıymet", "nazli": "Nazlı", "nazlican": "Nazlıcan",
    "asli": "Aslı", "aslihan": "Aslıhan", "asligul": "Aslıgül", "tarik": "Tarık",
    "cagri": "Çağrı", "cagil": "Çağıl", "cagla": "Çağla", "caglar": "Çağlar",
    "cagan": "Çağan", "cagatay": "Çağatay", "cagdas": "Çağdaş", "akin": "Akın",
    "alkin": "Alkın", "arkin": "Arkın", "barkin": "Barkın", "yalin": "Yalın",
    "yalkin": "Yalkın", "yalcin": "Yalçın", "taskin": "Taşkın", "askin": "Aşkın",
    "aydin": "Aydın", "bati": "Batı", "batihan": "Batıhan", "batikan": "Batıkan",
    "anil": "Anıl", "atil": "Atıl", "atilay": "Atılay", "fazil": "Fazıl",
    "firat": "Fırat", "sila": "Sıla", "silanur": "Sılanur", "sirma": "Sırma",
    "sitki": "Sıtkı", "yilmaz": "Yılmaz", "yildiz": "Yıldız", "yildiray": "Yıldıray",
    "yildirim": "Yıldırım", "hizir": "Hızır", "arik": "Arık", "sadik": "Sadık",
    "namik": "Namık", "kazim": "Kazım", "nazim": "Nazım", "asim": "Asım",
    "kasim": "Kasım", "hakki": "Hakkı", "rifat": "Rıfat", "riza": "Rıza",
    "ridvan": "Rıdvan", "sirri": "Sırrı", "tilsim": "Tılsım", "misra": "Mısra",
    "cansin": "Cansın", "sirac": "Sıraç", "beyazit": "Beyazıt",
    "ayse": "Ayşe", "aysegul": "Ayşegül", "aysenur": "Ayşenur", "aysen": "Ayşen",
    "cigdem": "Çiğdem", "gokce": "Gökçe", "gokcen": "Gökçen", "gokdeniz": "Gökdeniz",
    "gokhan": "Gökhan", "goksu": "Göksu", "goktug": "Göktuğ", "gokturk": "Göktürk",
    "gorkem": "Görkem", "gonul": "Gönül", "gozde": "Gözde", "gunes": "Güneş",
    "guney": "Güney", "gurkan": "Gürkan", "guven": "Güven", "gul": "Gül",
    "gulce": "Gülce", "gulcin": "Gülçin", "gulsen": "Gülşen", "gulsah": "Gülşah",
    "busra": "Büşra", "bunyamin": "Bünyamin", "huseyin": "Hüseyin", "hulya": "Hülya",
    "husnu": "Hüsnü", "suleyman": "Süleyman", "zumra": "Zümra", "ruya": "Rüya",
    "eylul": "Eylül", "eyup": "Eyüp", "oyku": "Öykü", "ozgur": "Özgür",
    "ozge": "Özge", "omer": "Ömer", "ozlem": "Özlem", "omur": "Ömür",
    "onder": "Önder", "ozan": "Ozan", "ozkan": "Özkan", "ozgu": "Özgü",
    "umit": "Ümit", "ulku": "Ülkü", "ugur": "Uğur", "tugba": "Tuğba",
    "tugce": "Tuğçe", "tugra": "Tuğra", "tugrul": "Tuğrul", "bugra": "Buğra",
    "bugrahan": "Buğrahan", "doga": "Doğa", "dogukan": "Doğukan", "dogu": "Doğu",
    "bogac": "Boğaç", "bogachan": "Boğaçhan", "yigit": "Yiğit", "yigithan": "Yiğithan",
    "ruzgar": "Rüzgar", "ertugrul": "Ertuğrul", "betul": "Betül", "begum": "Begüm",
    "bengu": "Bengü", "burcin": "Burçin", "aybuke": "Aybüke", "ayca": "Ayça",
    "acelya": "Açelya", "arman": "Arman", "armagan": "Armağan", "kagan": "Kağan",
    "oguz": "Oğuz", "oguzhan": "Oğuzhan", "onur": "Onur", "umut": "Umut",
    "utku": "Utku", "ufuk": "Ufuk", "uygar": "Uygar", "egemen": "Egemen",
    "mirac": "Miraç", "meric": "Meriç", "ates": "Ateş",
    "sevval": "Şevval", "seyma": "Şeyma", "sebnem": "Şebnem",
    "sule": "Şule", "sukru": "Şükrü", "sahin": "Şahin", "safak": "Şafak",
    "serife": "Şerife", "sirin": "Şirin",
}

# Spesifik bozuk ilk isim yazımlarının doğrudan karşılıkları
EXACT_FIRST_NAME_FIXES: Dict[str, str] = {
    "Tâhâ": "Taha",
    "Hûma": "Hüma",
    "Hilâl": "Hilal",
    "Ikrâ": "İkra",
    "Lâl": "Lal",
    "Eğemen": "Egemen",
    "Şila": "Sıla",
    "Danııl": "Daniil",
    "Marıa": "Maria",
    "Denıs": "Denis",
    "Ronı": "Roni",
}

# Soyadlarında Python .upper() veya ASCII/OCR kaynaklı bozulan yaygın soyadları
KNOWN_SURNAMES: Dict[str, str] = {
    "ibi": "İBİ", "ibis": "İBİŞ", "icli": "İÇLİ", "icke": "İÇKE",
    "icten": "İÇTEN", "icme": "İÇME", "irgin": "İRGİN", "islek": "İŞLEK",
    "isitemiz": "İŞİTEMİZ", "inal": "İNAL",
    "ide": "İDE", "idiz": "İDİZ", "ikinci": "İKİNCİ",
    "ildemir": "İLDEMİR", "iler": "İLER", "ileri": "İLERİ", "ilhan": "İLHAN",
    "ilkbahar": "İLKBAHAR", "ilkhan": "İLKHAN", "ilter": "İLTER", "ilce": "İLÇE",
    "ilcisulu": "İLÇİSULU", "imam": "İMAM", "imamoglu": "İMAMOĞLU", "iman": "İMAN",
    "imer": "İMER", "inalkac": "İNALKAÇ", "inan": "İNAN", "inanc": "İNANÇ",
    "ince": "İNCE", "incesu": "İNCESU", "incetahtaci": "İNCETAHTACI", "inci": "İNCİ",
    "ipbuken": "İPBÜKEN", "ipek": "İPEK", "ipkin": "İPKİN", "irengun": "İRENGÜN",
    "irgun": "İRGÜN", "iskender": "İSKENDER", "ismayil": "İSMAYİL", "ismail": "İSMAİL",
    "ispanoglu": "İSPANOĞLU", "iyidogan": "İYİDOĞAN", "iyimaya": "İYİMAYA", "izgi": "İZGİ",
    "isler": "İŞLER", "isleyen": "İŞLEYEN", "isleyici": "İŞLEYİCİ", "isman": "İŞMAN",
    "istemiz": "İŞTEMİZ", "isten": "İŞTEN", "iscan": "İŞCAN", "iseri": "İŞERİ",
    "iske": "İŞKE", "isli": "İŞLİ", "isme": "İŞME",
    "demir": "DEMİR", "ozdemir": "ÖZDEMİR", "akdemir": "AKDEMİR", "aydemir": "AYDEMİR",
    "candemir": "CANDEMİR", "tasdemir": "TAŞDEMİR", "dasdemir": "DAŞDEMİR",
    "gokdemir": "GÖKDEMİR", "karademir": "KARADEMİR", "kandemir": "KANDEMİR",
    "erdemir": "ERDEMİR", "aldemir": "ALDEMİR", "hasdemir": "HASDEMİR",
    "demirci": "DEMİRCİ", "demircan": "DEMİRCAN", "demirel": "DEMİREL",
    "demirbas": "DEMİRBAŞ", "demirtas": "DEMİRTAŞ", "demirhan": "DEMİRHAN",
    "demirkol": "DEMİRKOL", "demirkan": "DEMİRKAN", "demiryurek": "DEMİRYÜREK",
    "celik": "ÇELİK", "ozcelik": "ÖZÇELİK", "akcelik": "AKÇELİK", "ercelik": "ERÇELİK",
    "sahin": "ŞAHİN", "ozsahin": "ÖZŞAHİN", "ersahin": "ERŞAHİN", "aksahin": "AKŞAHİN",
    "simsek": "ŞİMŞEK", "cetin": "ÇETİN", "cetinkaya": "ÇETİNKAYA", "cetiner": "ÇETİNER",
    "tekin": "TEKİN", "oztekin": "ÖZTEKİN", "gultekin": "GÜLTEKİN", "aytekin": "AYTEKİN",
    "ertekin": "ERTEKİN", "alptekin": "ALPTEKİN", "cantekin": "CANTEKİN",
    "seckin": "SEÇKİN", "yetkin": "YETKİN", "keskin": "KESKİN", "pekin": "PEKİN",
    "ergin": "ERGİN", "engin": "ENGİN", "ersin": "ERSİN", "esin": "ESİN",
    "emin": "EMİN", "metin": "METİN", "ciftci": "ÇİFTÇİ", "ekinci": "EKİNCİ",
    "ekici": "EKİCİ", "degirmenci": "DEĞİRMENCİ", "cebeci": "CEBECİ", "cengiz": "CENGİZ",
    "deniz": "DENİZ", "ozdeniz": "ÖZDENİZ", "akdeniz": "AKDENİZ", "karadeniz": "KARADENİZ",
    "filiz": "FİLİZ", "yeliz": "YELİZ", "ediz": "EDİZ", "aziz": "AZİZ",
    "gedik": "GEDİK", "cevik": "ÇEVİK", "bilek": "BİLEK", "dilek": "DİLEK",
    "cicek": "ÇİÇEK", "yigit": "YİĞİT", "ozyigit": "ÖZYİĞİT", "akyigit": "AKYİĞİT",
    "eryigit": "ERYİĞİT", "basyigit": "BAŞYİĞİT",
    "sevim": "SEVİM", "devrim": "DEVRİM", "evrim": "EVRİM", "selim": "SELİM",
    "kerim": "KERİM", "melih": "MELİH", "semih": "SEMİH", "fatih": "FATİH",
    "nehir": "NEHİR", "besir": "BEŞİR", "zeki": "ZEKİ", "zengin": "ZENGİN",
    "sezgin": "SEZGİN", "bilgin": "BİLGİN", "bilgic": "BİLGİÇ", "dinc": "DİNÇ",
    "dincer": "DİNÇER", "sevinc": "SEVİNÇ", "erdinc": "ERDİNÇ", "kilic": "KILIÇ",
    "ozkilic": "ÖZKILIÇ", "akkilic": "AKKILIÇ", "erkilic": "ERKILIÇ",
    "yilmaz": "YILMAZ", "ozyilmaz": "ÖZYILMAZ", "akyilmaz": "AKYILMAZ", "eryilmaz": "ERYILMAZ",
    "yildiz": "YILDIZ", "ozyildiz": "ÖZYILDIZ", "akyildiz": "AKYILDIZ", "ayyildiz": "AYYILDIZ",
    "yildirim": "YILDIRIM", "ozyildirim": "ÖZYILDIRIM", "akyildirim": "AKYILDIRIM",
    "altin": "ALTIN", "altintop": "ALTINTOP", "altinkaya": "ALTINKAYA",
    "altintas": "ALTINTAŞ", "altinok": "ALTINOK", "altinay": "ALTINAY", "ozaltin": "ÖZALTIN",
    "aydin": "AYDIN", "ozaydin": "ÖZAYDIN", "akaydin": "AKAYDIN", "gunaydin": "GÜNAYDIN",
    "akin": "AKIN", "akinci": "AKINCI", "cakir": "ÇAKIR", "cakmak": "ÇAKMAK",
    "sari": "SARI", "sarikaya": "SARIKAYA", "saritas": "SARITAŞ", "sarigul": "SARIGÜL",
    "isik": "IŞIK", "ozisik": "ÖZIŞIK", "akisik": "AKIŞIK", "cinar": "ÇINAR",
    "pinar": "PINAR", "akpinar": "AKPINAR", "karapinar": "KARAPINAR", "ozpinar": "ÖZPINAR",
    "gurpinar": "GÜRPINAR", "taspinar": "TAŞPINAR",
    "baris": "BARIŞ", "yalcin": "YALÇIN", "yalcinkaya": "YALÇINKAYA",
    "ozturk": "ÖZTÜRK", "ozkan": "ÖZKAN", "ozcan": "ÖZCAN", "ozer": "ÖZER",
    "ozmen": "ÖZMEN", "ozbek": "ÖZBEK", "ozgul": "ÖZGÜL", "ozgur": "ÖZGÜR",
    "ozel": "ÖZEL", "oz": "ÖZ",
    "erdogan": "ERDOĞAN", "dogan": "DOĞAN", "aydogan": "AYDOĞAN", "aydogdu": "AYDOĞDU",
    "gundogdu": "GÜNDOĞDU", "akdogan": "AKDOĞAN", "ozdogan": "ÖZDOĞAN",
    "coskun": "COŞKUN", "koc": "KOÇ", "kocak": "KOÇAK", "karakoc": "KARAKOÇ",
    "guler": "GÜLER", "gunes": "GÜNEŞ", "gunduz": "GÜNDÜZ", "gungor": "GÜNGÖR",
    "gurbuz": "GÜRBÜZ", "gul": "GÜL", "guney": "GÜNEY", "guzel": "GÜZEL",
    "aktas": "AKTAŞ", "karatas": "KARATAŞ", "bektas": "BEKTAŞ",
    "tunc": "TUNÇ", "turk": "TÜRK", "turkmen": "TÜRKMEN", "senturk": "ŞENTÜRK",
    "erturk": "ERTÜRK", "akturk": "AKTÜRK", "canturk": "CANTÜRK", "basturk": "BAŞTÜRK",
    "ucar": "UÇAR", "unal": "ÜNAL", "unver": "ÜNVER", "unlu": "ÜNLÜ", "unsal": "ÜNSAL",
    "yuksel": "YÜKSEL", "kose": "KÖSE", "caliskan": "ÇALIŞKAN", "yasar": "YAŞAR",
    "avci": "AVCI", "balci": "BALCI", "yazici": "YAZICI", "ates": "ATEŞ",
    "coban": "ÇOBAN", "saglam": "SAĞLAM", "eroglu": "EROĞLU", "gokce": "GÖKÇE",
    "genc": "GENÇ", "bas": "BAŞ", "aygun": "AYGÜN", "karakus": "KARAKUŞ",
    "basaran": "BAŞARAN", "oguz": "OĞUZ", "akyuz": "AKYÜZ", "caglar": "ÇAĞLAR",
    "arikan": "ARIKAN", "atik": "ATİK", "cakici": "ÇAKICI", "taskin": "TAŞKIN",
    "sanli": "ŞANLI", "arici": "ARICI", "tanriverdi": "TANRIVERDİ",
    "hatipoglu": "HATİPOĞLU", "calik": "ÇALIK", "temiz": "TEMİZ",
    "taskiran": "TAŞKIRAN", "kazanci": "KAZANCI", "sagir": "SAĞIR",
    "hacioglu": "HACIOĞLU", "cakiroglu": "ÇAKIROĞLU", "calis": "ÇALIŞ",
    "yagci": "YAĞCI", "sayin": "SAYIN", "kizilkaya": "KIZILKAYA",
    "canli": "CANLI", "saygin": "SAYGIN", "kalayci": "KALAYCI",
    "basarir": "BAŞARIR", "sarioglu": "SARIOĞLU", "odabasi": "ODABAŞI",
}

EXACT_SURNAME_FIXES: Dict[str, str] = {
    "ÇOŞKUN": "COŞKUN",
    "ÇİFTCİ": "ÇİFTÇİ",
    "CİFTCİ": "ÇİFTÇİ",
    "CIFTCI": "ÇİFTÇİ",
    "ÇIFTÇI": "ÇİFTÇİ",
    "GÖKCE": "GÖKÇE",
    "TURĞUT": "TURGUT",
    "ÜĞÜR": "UĞUR",
    "EKMEKCİ": "EKMEKÇİ",
    "SAATCİ": "SAATÇİ",
    "ILÇİ": "İLÇİ",
}

TRUNCATED_NAME_FIXES = {
    "(. KESKİN": "Mustafa Rüzgar KESKİN",
    "(. AKDOĞAN": "İsmail Engin AKDOĞAN",
    "(. COŞKUN": "Mustafa Selim COŞKUN",
    "(. DEMİRYÜREK": "Dağhan Emir DEMİRYÜREK",
    "(. ARDAHANLIOĞLU": "Kerem ARDAHANLIOĞLU",
    "(. DOYĞUN": "Ahmet Furkan DOYĞUN",
    "(. AKKAYA": "Timaf Voseps AKKAYA",
    "(. GÖÇEBAKAN": "Bayram Alper GÖÇEBAKAN",
    "(. KARSAVURANOĞLU": "Ali Emir KARSAVURANOĞLU",
    "(. GÜRGAN": "Ramazan Timurhan GÜRGAN",
    "(. YOĞURTCUOĞLU": "Kaya YOĞURTCUOĞLU",
    "(. ALTINKAYA": "Mustafa Yağız ALTINKAYA",
    "(. DEĞİRMENCİ": "Ahmet Eren DEĞİRMENCİ",
    "(. SAPMAZTÜRK": "Mustafa Arda SAPMAZTÜRK",
    "(. KARAHANOĞULLARI": "Gülşen Naz KARAHANOĞULLARI",
}

# İçinde hem ince ünlü hem de kalın ünlülü kök bulunduran bileşik soyadı parçaları
# (Örn: ÖZKILIÇ, KILIÇER, TEKYILDIZ, ÖZYILDIZ, KIZILGÖZ gibi soyadlarında 'I' harfi doğrudur)
COMPOUND_BACK_ROOTS_IN_SURNAMES = (
    "KILIÇ", "YILDIZ", "YILDIRIM", "YILMAZ", "KIZIL", "ÇIRPI",
    "KIYI", "IŞIK", "IŞIL", "PINAR", "ÇINAR", "KIR", "ÇAKIR",
    "SARI", "ALTIN", "AYDIN", "YALÇIN", "AKIN", "TAŞKIN", "MIH",
    "KIŞ", "ÇIK", "BIYIK", "CHR", "SH", "PH", "TH", "W", "X", "Q",
)


def clean_combining_marks(s: str) -> str:
    """Python'un 'İ'.lower() çağrısında ürettiği 'i\\u0307' (combining dot above) hatasını temizler."""
    if not s:
        return ""
    s = s.replace("i\u0307", "i").replace("I\u0307", "İ").replace("ı\u0307", "i").replace("\u0307", "")
    return s


def tr_upper(s: str) -> str:
    """Türkçe karakter kurallarına uygun büyük harf dönüşümü."""
    s = clean_combining_marks(s)
    return "".join(TR_UPPER_MAP.get(ch, ch.upper()) for ch in s)


def tr_lower(s: str) -> str:
    """Türkçe karakter kurallarına uygun küçük harf dönüşümü."""
    s = clean_combining_marks(s)
    return "".join(TR_LOWER_MAP.get(ch, ch.lower()) for ch in s)


def tr_fold(s: str) -> str:
    """Arama ve tekilleştirme için Türkçe karakterleri ASCII küçük harfe indirger."""
    if not s:
        return ""
    s = clean_combining_marks(str(s)).translate(TR_FOLD_MAP).lower()
    s = re.sub(r"[^a-z0-9\s]", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def tr_i_fold(s: str) -> str:
    """Sadece I/İ/ı/i ve şapkalı ünlü farklarını indirger (diğer Türkçe harfleri korur)."""
    if not s:
        return ""
    return tr_lower(clean_combining_marks(str(s))).translate(TR_I_FOLD_MAP)


def normalize_comma_name(raw_name: str) -> str:
    """'SOYADI, İlk İsim' veya 'İlk İsim, SOYADI' formatını 'İlk İsim SOYADI' formatına çevirir."""
    if not raw_name or "," not in raw_name:
        return raw_name
    parts = [p.strip() for p in raw_name.split(",") if p.strip()]
    if len(parts) == 2:
        p0, p1 = parts[0], parts[1]
        if not p0.isupper() and p1.isupper():
            return f"{p0} {p1}"
        elif p0.isupper() and not p1.isupper():
            return f"{p1} {p0}"
        elif p0.isupper() and p1.isupper():
            return f"{p1} {p0}"
        else:
            return f"{p1} {p0}"
    return raw_name.replace(",", " ")


def fix_first_name_word(
    word: str,
    corpus_first_map: Optional[Dict[str, str]] = None
) -> str:
    """
    Tek bir ilk isim kelimesini Türkçeye uygun Title Case formatına dönüştürür ve
    Python .capitalize() / .lower() kaynaklı ı/i ve İ/I bozulmalarını onarır.
    """
    w = clean_combining_marks(word.strip())
    if not w:
        return ""

    if "-" in w:
        return "-".join(fix_first_name_word(p, corpus_first_map) for p in w.split("-") if p)

    if w in EXACT_FIRST_NAME_FIXES:
        return EXACT_FIRST_NAME_FIXES[w]

    folded = tr_fold(w)
    if not folded:
        return w

    # 1. Bilinen ilk isimler sözlüğü
    if folded in KNOWN_FIRST_NAMES:
        return KNOWN_FIRST_NAMES[folded]

    # 2. Türkçe büyük/küçük harf dönüşümü (Title Case)
    first_char = tr_upper(w[0])
    rest_chars = tr_lower(w[1:])
    candidate = first_char + rest_chars

    if candidate in EXACT_FIRST_NAME_FIXES:
        return EXACT_FIRST_NAME_FIXES[candidate]

    # 3. Veritabanı korpusundan öğrenilen spesifik bozuk yazım -> doğru yazım haritası
    if corpus_first_map and candidate in corpus_first_map:
        return corpus_first_map[candidate]

    # 4. Türkçenin Kesin İnce Ünlü Kuralı:
    # İnce ünlü (e, i, ö, ü) içeren ve kalın ünlü (a, o, u) içermeyen bir ilk isimde:
    # - Küçük 'ı' harfi bulunamaz ('ELIF' -> 'Elıf', 'DENIZ' -> 'Denız', 'SELIN' -> 'Selın' hatasıdır -> 'i' olur)
    # - Kelime başındaki 'I' harfi 'İ' olmalıdır ('Ipeksu' -> 'İpeksu', 'Ilknur' -> 'İlknur')
    has_front = any(v in candidate for v in ("e", "i", "ö", "ü", "E", "İ", "Ö", "Ü"))
    has_back = any(v in candidate for v in ("a", "o", "u", "A", "O", "U"))
    if has_front and not has_back:
        if "ı" in candidate[1:]:
            candidate = candidate[0] + candidate[1:].replace("ı", "i")
        if candidate.startswith("I"):
            candidate = "İ" + candidate[1:]

    if corpus_first_map and candidate in corpus_first_map:
        return corpus_first_map[candidate]

    return candidate


def fix_surname_word(
    word: str,
    corpus_last_map: Optional[Dict[str, str]] = None
) -> str:
    """
    Soyadı kelimesini Türkçeye uygun TAMAMI BÜYÜK HARF formatına dönüştürür ve
    Python .upper() kaynaklı 'i' -> 'I' (örn: DEMIR -> DEMİR, ÇELIK -> ÇELİK)
    veya 'Yilmaz' -> 'YİLMAZ', 'Avci' -> 'AVCİ' hatalarını onarır.
    """
    w = clean_combining_marks(word.strip())
    if not w:
        return ""

    if "-" in w:
        return "-".join(fix_surname_word(p, corpus_last_map) for p in w.split("-") if p)

    folded = tr_fold(w)
    if not folded:
        return w.upper()

    # 1. Bilinen soyadları sözlüğü
    if folded in KNOWN_SURNAMES:
        return KNOWN_SURNAMES[folded]

    # 2. Türkçe kurallarına göre büyük harfe çevir (küçük 'i' -> 'İ', 'ı' -> 'I')
    up = tr_upper(w)

    if up in EXACT_SURNAME_FIXES:
        return EXACT_SURNAME_FIXES[up]

    # 3. Veritabanı korpusundan öğrenilen spesifik bozuk soyadı -> doğru soyadı haritası
    if corpus_last_map and up in corpus_last_map:
        return corpus_last_map[up]

    # 4. Yaygın bileşik soyadı kök/ek düzeltmeleri
    up = re.sub(r"ALTİ", "ALTI", up)
    up = re.sub(r"YİLMAZ", "YILMAZ", up)
    up = re.sub(r"YİLDİZ", "YILDIZ", up)
    up = re.sub(r"YİLDİRİM", "YILDIRIM", up)
    up = re.sub(r"YİLDIRİM", "YILDIRIM", up)
    up = re.sub(r"KİLİÇ", "KILIÇ", up)
    up = re.sub(r"AYDİN", "AYDIN", up)
    up = re.sub(r"PİNAR", "PINAR", up)
    up = re.sub(r"ÇİNAR", "ÇINAR", up)

    compound_endings = [
        ("DEMIR", "DEMİR"),
        ("ÇELIK", "ÇELİK"),
        ("ŞAHIN", "ŞAHİN"),
        ("ŞIMŞEK", "ŞİMŞEK"),
        ("TEKIN", "TEKİN"),
        ("ÇETIN", "ÇETİN"),
        ("METIN", "METİN"),
        ("KESKIN", "KESKİN"),
        ("SEÇKIN", "SEÇKİN"),
        ("YETKIN", "YETKİN"),
        ("DENIZ", "DENİZ"),
        ("YIĞIT", "YİĞİT"),
        ("YİĞIT", "YİĞİT"),
        ("YIGIT", "YİĞİT"),
        ("ÇIÇEK", "ÇİÇEK"),
        ("DILEK", "DİLEK"),
        ("BILEK", "BİLEK"),
        ("ÇIFTÇI", "ÇİFTÇİ"),
        ("ÇİFTCİ", "ÇİFTÇİ"),
        ("DEMIRCI", "DEMİRCİ"),
        ("EKINCI", "EKİNCİ"),
        ("EKICI", "EKİCİ"),
    ]
    for bad_suf, good_suf in compound_endings:
        if up.endswith(bad_suf):
            up = up[: -len(bad_suf)] + good_suf
            break

    # 5. Kalın ünlülü Türkçe soyadlarında bozuk '-Cİ', '-Çİ', '-Lİ', '-SİZ', '-LİK', '-KİRAN' eklerinin onarımı
    # (Örn: KAZANCİ -> KAZANCI, BALTACİ -> BALTACI, YAĞLİ -> YAĞLI, DALKİRAN -> DALKIRAN)
    stem_before_2 = up[:-2] if len(up) > 2 else ""
    stem_has_front = any(v in stem_before_2 for v in ("E", "İ", "Ö", "Ü"))
    stem_has_back = any(v in stem_before_2 for v in ("A", "I", "O", "U"))
    if stem_has_back and not stem_has_front and not up.startswith("SAAT"):
        if up.endswith("Cİ"):
            up = up[:-2] + "CI"
        elif up.endswith("Çİ"):
            up = up[:-2] + "ÇI"
        elif up.endswith("Lİ") and len(up) >= 5 and not up.endswith("ALİ"):
            up = up[:-2] + "LI"
        else:
            for bad_back_suf, good_back_suf in (
                ("SİZ", "SIZ"),
                ("LİK", "LIK"),
                ("KİRAN", "KIRAN"),
                ("DAYİ", "DAYI"),
                ("BAŞİ", "BAŞI"),
                ("SARİ", "SARI"),
                ("ÇAKİR", "ÇAKIR"),
                ("SAYİN", "SAYIN"),
                ("SAYGİN", "SAYGIN"),
                ("KARGİN", "KARGIN"),
                ("BARİN", "BARIN"),
                ("IŞİLDAK", "IŞILDAK"),
                ("SARİOĞLU", "SARIOĞLU"),
                ("HACİOĞLU", "HACIOĞLU"),
                ("ÇAKİROĞLU", "ÇAKIROĞLU"),
            ):
                if up.endswith(bad_back_suf):
                    up = up[: -len(bad_back_suf)] + good_back_suf
                    break

    # 6. İnce ünlülü soyadlarında 'I' -> 'İ' onarımı (bileşik kalın kök içermeyenler için):
    has_front_all = any(v in up for v in ("E", "İ", "Ö", "Ü"))
    has_aou = any(v in up for v in ("A", "O", "U"))
    if has_front_all and not has_aou and "I" in up:
        if not any(root in up for root in COMPOUND_BACK_ROOTS_IN_SURNAMES):
            up = up.replace("I", "İ")

    if corpus_last_map and up in corpus_last_map:
        return corpus_last_map[up]

    return up


def standardize_turkish_athlete_name(
    raw_name: str,
    corpus_first_map: Optional[Dict[str, str]] = None,
    corpus_last_map: Optional[Dict[str, str]] = None
) -> str:
    """
    Sporcu adını standart TYF formatına ('İlk İsimler SOYADI') ve doğru Türkçe karakterlere dönüştürür.
    """
    if not raw_name:
        return ""

    s = clean_combining_marks(str(raw_name)).strip()
    if "," in s:
        s = normalize_comma_name(s)

    s = re.sub(r"\s+", " ", s).strip()
    if s in TRUNCATED_NAME_FIXES:
        s = TRUNCATED_NAME_FIXES[s]

    # Okul / ferdi etiketlerini temizle
    s = re.sub(r"^\(\.\s*", "", s).strip()
    s = re.sub(r"^(?:\(?[TtFf][kKdD]\)?[\.\)]?\s*)+", "", s).strip()

    words = s.split()
    if not words:
        return ""
    if len(words) == 1:
        return fix_first_name_word(words[0], corpus_first_map)

    first_names = [fix_first_name_word(w, corpus_first_map) for w in words[:-1]]
    surname = fix_surname_word(words[-1], corpus_last_map)
    return " ".join(first_names + [surname])


def build_corpus_maps_from_names(names_with_weights: List[Tuple[str, int]]) -> Tuple[Dict[str, str], Dict[str, str]]:
    """
    Veritabanındaki mevcut tüm sporcu isimlerini tarayarak:
    1. Sadece I/İ/ı/i farkı olan kelimelerde (örn: Elif [1035] vs Elıf [9], YILMAZ [436] vs YİLMAZ [18])
       azınlıkta kalan bozuk yazımı baskın doğru yazıma eşler.
    2. Türkçe karakteri eksik (ASCII) olup çok nadir görülen yazımları (örn: Omer [6] vs Ömer [594],
       OZDEMIR [4] vs ÖZDEMİR [209]), en az 15 kat daha sık geçen Türkçe karakterli karşılığına eşler.
       Böylece TORUN vs TÖRÜN, ONUR vs ÖNÜR, CAN vs ÇAN gibi gerçek farklı soyadlarına dokunulmaz.
    """
    first_counts: Counter = Counter()
    last_counts: Counter = Counter()

    for raw_name, _ in names_with_weights:
        if not raw_name:
            continue
        s = clean_combining_marks(raw_name).strip()
        if "," in s:
            s = normalize_comma_name(s)
        words = s.split()
        if len(words) < 2:
            continue

        for fw in words[:-1]:
            tc = tr_upper(fw[0]) + tr_lower(fw[1:]) if fw else ""
            if len(tc) >= 2:
                first_counts[tc] += 1

        lw = tr_upper(words[-1])
        if len(lw) >= 2:
            last_counts[lw] += 1

    corpus_first: Dict[str, str] = {}
    corpus_last: Dict[str, str] = {}

    # A. Sadece I/İ/ı/i ve şapka farkı olan gruplar (kesin imla varyantları)
    first_by_ifold: Dict[str, List[Tuple[str, int]]] = defaultdict(list)
    for w, cnt in first_counts.items():
        first_by_ifold[tr_i_fold(w)].append((w, cnt))

    for _, variants in first_by_ifold.items():
        if len(variants) < 2:
            continue
        variants.sort(key=lambda kv: -kv[1])
        best_w, best_cnt = variants[0]
        if best_cnt < 5:
            continue
        for var_w, var_cnt in variants[1:]:
            if best_cnt >= max(3 * var_cnt, var_cnt + 4):
                corpus_first[var_w] = best_w

    last_by_ifold: Dict[str, List[Tuple[str, int]]] = defaultdict(list)
    for w, cnt in last_counts.items():
        last_by_ifold[tr_i_fold(w)].append((w, cnt))

    for _, variants in last_by_ifold.items():
        if len(variants) < 2:
            continue
        variants.sort(key=lambda kv: -kv[1])
        best_w, best_cnt = variants[0]
        if best_cnt < 5:
            continue
        for var_w, var_cnt in variants[1:]:
            if best_cnt >= max(3 * var_cnt, var_cnt + 4):
                corpus_last[var_w] = best_w

    # B. Ç/C, Ş/S, Ğ/G, Ö/O, Ü/U farkı olan gruplar (sadece nadir ASCII bozulmalarını baskın Türkçe kelimeye eşle)
    tr_diacritics = set("çğöşüÇĞÖŞÜ")

    first_by_fold: Dict[str, List[Tuple[str, int]]] = defaultdict(list)
    for w, cnt in first_counts.items():
        first_by_fold[tr_fold(w)].append((w, cnt))

    for _, variants in first_by_fold.items():
        if len(variants) < 2:
            continue
        variants.sort(key=lambda kv: -kv[1])
        best_w, best_cnt = variants[0]
        best_tr = sum(1 for c in best_w if c in tr_diacritics)
        if best_cnt < 20 or best_tr == 0:
            continue
        for var_w, var_cnt in variants[1:]:
            var_tr = sum(1 for c in var_w if c in tr_diacritics)
            if var_cnt <= 4 and var_tr < best_tr and best_cnt >= 15 * var_cnt:
                corpus_first[var_w] = best_w

    last_by_fold: Dict[str, List[Tuple[str, int]]] = defaultdict(list)
    for w, cnt in last_counts.items():
        last_by_fold[tr_fold(w)].append((w, cnt))

    for _, variants in last_by_fold.items():
        if len(variants) < 2:
            continue
        variants.sort(key=lambda kv: -kv[1])
        best_w, best_cnt = variants[0]
        best_tr = sum(1 for c in best_w if c in tr_diacritics)
        if best_cnt < 20 or best_tr == 0:
            continue
        for var_w, var_cnt in variants[1:]:
            var_tr = sum(1 for c in var_w if c in tr_diacritics)
            if var_cnt <= 4 and var_tr < best_tr and best_cnt >= 15 * var_cnt:
                corpus_last[var_w] = best_w

    return corpus_first, corpus_last


def resolve_default_db_path() -> str:
    """Projedeki olası veritabanı yollarını sırayla kontrol eder."""
    here = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(os.path.dirname(here))
    candidates = [
        os.path.join(project_root, "output", "yuzme_veritabani.db"),
        os.path.join(os.path.dirname(project_root), "database", "yuzme_veritabani.db"),
        os.path.join(project_root, "yuzme_projesi", "yuzme_veritabani.db"),
        os.path.expanduser(r"~\Downloads\yuzme_veritabani.db"),
    ]
    for p in candidates:
        if os.path.exists(p):
            return os.path.abspath(p)
    return os.path.abspath(candidates[0])


def repair_database_turkish_names(db_path: Optional[str] = None, dry_run: bool = False) -> Dict[str, Any]:
    """
    SQLite veritabanındaki `sporcular` tablosunda:
    1. Türkçe karakter hatalarını (İ/I, ı/i, ş/s, ğ/g, ü/u, ö/o, ç/c ve combining dot \\u0307) düzeltir.
    2. İsim düzeltmesi sonrasında aynı (sporcu_adi, dogum_yili) ile mükerrer oluşmuş
       sporcu profillerini tek sporcuda birleştirir.
    3. Birleştirilen sporcuların yarış sonuçlarını (yaris_sonuclari) ve kulüp tarihçelerini
       (sporcu_kulup_tarihce) ana kayda aktarır, mükerrer yarışları temizler ve sayaçları günceller.
    """
    target_db = db_path or resolve_default_db_path()
    if not os.path.exists(target_db):
        raise FileNotFoundError(f"Veritabanı dosyası bulunamadı: {target_db}")

    t0 = time.time()
    conn = sqlite3.connect(target_db)
    cur = conn.cursor()

    stats: Dict[str, Any] = {
        "db_path": target_db,
        "total_athletes": 0,
        "renamed_count": 0,
        "merged_duplicate_athletes": 0,
        "reassigned_races": 0,
        "deleted_duplicate_races": 0,
        "elapsed_sec": 0.0,
        "sample_renames": [],
        "sample_merges": [],
    }

    try:
        cur.execute("SELECT id, sporcu_adi, dogum_yili, yas_dogum_yili, cinsiyet, birincil_kulup_id, toplam_yaris_sayisi FROM sporcular")
        all_athletes = cur.fetchall()
        stats["total_athletes"] = len(all_athletes)

        # 1. Korpus haritalarını oluştur (Türkçe karakterli baskın yazımları öğren)
        names_weights = [(row[1] or "", int(row[6] or 1)) for row in all_athletes]
        corpus_first, corpus_last = build_corpus_maps_from_names(names_weights)

        # 2. Her sporcu için düzeltilmiş ismi hesapla ve (düzeltilmiş_isim, dogum_yili) bazında grupla
        groups: Dict[Tuple[str, str], List[Tuple[int, str, str, Any, str, str, Any, int]]] = defaultdict(list)
        name_updates: List[Tuple[str, int]] = []

        for aid, raw_name, byear, yas_byear, gender, club_id, race_cnt in all_athletes:
            orig_name = (raw_name or "").strip()
            fixed_name = standardize_turkish_athlete_name(orig_name, corpus_first, corpus_last)
            if not fixed_name:
                fixed_name = orig_name

            byear_key = str(byear or yas_byear or "").strip()
            group_key = (fixed_name, byear_key)
            groups[group_key].append((
                aid, orig_name, fixed_name, byear, yas_byear or "", gender or "", club_id, int(race_cnt or 0)
            ))

        # 3. İsim güncellemelerini ve mükerrer birleştirmeleri belirle
        merges_to_perform: List[Tuple[int, List[int], str]] = []

        for (fixed_name, byear_key), members in groups.items():
            if len(members) == 1:
                aid, orig_name, _, _, _, _, _, _ = members[0]
                if orig_name != fixed_name:
                    name_updates.append((fixed_name, aid))
                    stats["renamed_count"] += 1
                    if len(stats["sample_renames"]) < 100:
                        stats["sample_renames"].append((aid, orig_name, fixed_name))
            else:
                # Birden fazla sporcu kaydı düzeltme sonrasında aynı (sporcu_adi, dogum_yili) anahtarına düştü
                members_sorted = sorted(members, key=lambda m: (-m[7], m[0]))
                keep_member = members_sorted[0]
                keep_id = keep_member[0]
                remove_members = members_sorted[1:]
                remove_ids = [m[0] for m in remove_members]

                if keep_member[1] != fixed_name:
                    name_updates.append((fixed_name, keep_id))
                    stats["renamed_count"] += 1
                    if len(stats["sample_renames"]) < 100:
                        stats["sample_renames"].append((keep_id, keep_member[1], fixed_name))

                for rm in remove_members:
                    if len(stats["sample_merges"]) < 100:
                        stats["sample_merges"].append((rm[0], rm[1], keep_id, fixed_name, byear_key))

                merges_to_perform.append((keep_id, remove_ids, fixed_name))
                stats["merged_duplicate_athletes"] += len(remove_ids)

        if dry_run:
            stats["elapsed_sec"] = round(time.time() - t0, 2)
            conn.close()
            return stats

        cur.execute("BEGIN TRANSACTION;")

        # 4. İsim düzeltmelerini uygula
        if name_updates:
            cur.executemany("UPDATE sporcular SET sporcu_adi = ? WHERE id = ?", name_updates)

        # 5. Mükerrer sporcuları ana sporcu kaydında birleştir
        for keep_id, remove_ids, _ in merges_to_perform:
            for rem_id in remove_ids:
                cur.execute("UPDATE yaris_sonuclari SET sporcu_id = ? WHERE sporcu_id = ?", (keep_id, rem_id))
                stats["reassigned_races"] += cur.rowcount

                cur.execute(
                    """
                    UPDATE sporcular
                    SET dogum_yili = COALESCE(sporcular.dogum_yili, (SELECT dogum_yili FROM sporcular WHERE id = ?)),
                        cinsiyet = CASE WHEN sporcular.cinsiyet IS NULL OR sporcular.cinsiyet = ''
                                        THEN (SELECT cinsiyet FROM sporcular WHERE id = ?)
                                        ELSE sporcular.cinsiyet END,
                        birincil_kulup_id = COALESCE(sporcular.birincil_kulup_id, (SELECT birincil_kulup_id FROM sporcular WHERE id = ?))
                    WHERE id = ?
                    """,
                    (rem_id, rem_id, rem_id, keep_id)
                )

                cur.execute("UPDATE OR IGNORE sporcu_kulup_tarihce SET sporcu_id = ? WHERE sporcu_id = ?", (keep_id, rem_id))
                cur.execute("DELETE FROM sporcu_kulup_tarihce WHERE sporcu_id = ?", (rem_id,))
                cur.execute("DELETE FROM sporcular WHERE id = ?", (rem_id,))

        # 6. Birleştirme sonrası sadece birleştirilen sporcularda oluşabilecek mükerrer yarışları temizle
        if merges_to_perform:
            keep_ids = [k for k, _, _ in merges_to_perform]
            placeholders = ",".join("?" for _ in keep_ids)

            cur.execute("PRAGMA table_info(yaris_sonuclari)")
            ys_cols = {r[1] for r in cur.fetchall()}
            event_col = "event_id" if "event_id" in ys_cols else "musabaka_adi"

            cur.execute("DROP TABLE IF EXISTS temp_dup_races_after_tr_fix")
            cur.execute(
                f"""
                CREATE TEMP TABLE temp_dup_races_after_tr_fix AS
                SELECT id FROM (
                    SELECT id,
                           ROW_NUMBER() OVER (
                               PARTITION BY sporcu_id, {event_col}, COALESCE(yaris_no, ''), COALESCE(seans, ''), mesafe, stil, COALESCE(derece, '')
                               ORDER BY
                                   (CASE WHEN derece IS NOT NULL AND derece != 'Bekleniyor' THEN 1 ELSE 0 END) DESC,
                                   (CASE WHEN derece_saniye IS NOT NULL THEN 1 ELSE 0 END) DESC,
                                   (CASE WHEN puan IS NOT NULL AND puan != '' THEN 1 ELSE 0 END) DESC,
                                   id ASC
                           ) as rn
                    FROM yaris_sonuclari
                    WHERE sporcu_id IN ({placeholders})
                      AND {event_col} IS NOT NULL
                ) WHERE rn > 1
                """,
                keep_ids,
            )
            cur.execute("SELECT COUNT(*) FROM temp_dup_races_after_tr_fix")
            dup_race_cnt = cur.fetchone()[0]
            if dup_race_cnt > 0:
                cur.execute("DELETE FROM yaris_sonuclari WHERE id IN (SELECT id FROM temp_dup_races_after_tr_fix)")
                stats["deleted_duplicate_races"] = dup_race_cnt
            cur.execute("DROP TABLE IF EXISTS temp_dup_races_after_tr_fix")

            cur.execute(
                f"""
                UPDATE sporcular
                SET toplam_yaris_sayisi = (
                    SELECT COUNT(*) FROM yaris_sonuclari WHERE yaris_sonuclari.sporcu_id = sporcular.id
                )
                WHERE id IN ({placeholders})
                """,
                keep_ids,
            )
            cur.execute(
                f"""
                UPDATE sporcu_kulup_tarihce
                SET toplam_yaris_sayisi = (
                    SELECT COUNT(*) FROM yaris_sonuclari
                    WHERE yaris_sonuclari.sporcu_id = sporcu_kulup_tarihce.sporcu_id
                      AND yaris_sonuclari.kulup_id = sporcu_kulup_tarihce.kulup_id
                )
                WHERE sporcu_id IN ({placeholders})
                """,
                keep_ids,
            )

        conn.commit()
        stats["elapsed_sec"] = round(time.time() - t0, 2)
        return stats

    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
