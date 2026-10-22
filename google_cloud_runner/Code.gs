/**
 * Google Apps Script (GAS) - TYF Canlı Proxy & İndirme Servisi
 * ==============================================================
 * GCP (Google Cloud Platform) hesabı veya kredi kartı gerektirmez!
 * script.google.com adresine gidip ücretsiz yapıştırarak Web App olarak dağıtabilirsiniz.
 * 
 * Kurulum:
 * 1. script.google.com adresine gidin -> Yeni Proje
 * 2. Bu kodları yapıştırın.
 * 3. Dağıt (Deploy) -> Yeni Dağıtım -> Tür: Web Uygulaması
 *    - Erişim: Herkes (Anyone)
 * 4. Verilen URL'yi PythonAnywhere ortamındaki .env dosyanıza ekleyin:
 *    GOOGLE_APPS_SCRIPT_URL=https://script.google.com/macros/s/.../exec
 */

function doGet(e) {
  // Proxy modu: Herhangi bir PDF dosyasını Google IP'si üzerinden çeker
  var fileUrl = e.parameter.url;
  if (!fileUrl) {
    return ContentService.createTextOutput(JSON.stringify({hata: "url parametresi eksik"})).setMimeType(ContentService.MimeType.JSON);
  }
  
  var resp = UrlFetchApp.fetch(fileUrl, {
    headers: {"User-Agent": "Mozilla/5.0"},
    muteHttpExceptions: true
  });
  
  return ContentService.createTextOutput(Utilities.base64Encode(resp.getContent()))
    .setMimeType(ContentService.MimeType.TEXT);
}

function doPost(e) {
  try {
    var data = JSON.parse(e.postData.contents);
    var eventUrl = data.event_url;
    
    var resp = UrlFetchApp.fetch(eventUrl, {
      headers: {"User-Agent": "Mozilla/5.0"},
      muteHttpExceptions: true
    });
    var html = resp.getContentText();
    
    // Sayfadaki StartList PDF linklerini ayıkla
    var regex = /href=["']([^"']*(?:startlist|start_list)[^"']*)["']/gi;
    var match;
    var startUrls = [];
    while ((match = regex.exec(html)) !== null) {
      var href = match[1];
      if (href.indexOf("http") !== 0) {
        var base = eventUrl.endsWith("/") ? eventUrl : eventUrl + "/";
        href = base + href;
      }
      if (startUrls.indexOf(href) === -1) {
        startUrls.push(href);
      }
    }
    
    return ContentService.createTextOutput(JSON.stringify({
      durum: "basarili",
      toplam_start_listesi: startUrls.length,
      start_listeleri: startUrls
    })).setMimeType(ContentService.MimeType.JSON);
    
  } catch (err) {
    return ContentService.createTextOutput(JSON.stringify({
      durum: "hata",
      mesaj: err.toString()
    })).setMimeType(ContentService.MimeType.JSON);
  }
}

