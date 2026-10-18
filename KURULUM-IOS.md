# İnşaatSoft ERP — iPhone (iOS) uygulaması

İnşaatSoft ERP'nin iPhone uygulaması. Android uygulamasıyla aynı yöntemle çalışır: ekranları kendisi çizer (web görünümü kullanmaz), ne göstereceğini programın `/api/v1` adresinden öğrenir. Bu sayede KavisCloud'dan dağıtılan her İnşaatSoft güncellemesi, uygulama yeniden yüklenmeden telefondaki ekranlara da yansır.

**Sunucuda değişiklik gerekmez.** İnşaatSoft 1.2.2 ve KavisCloud iOS'u zaten tanıyor (giriş `platform=ios`, bağlı telefonlar listesinde iOS süzgeci, Uygulamalar'da "iOS (iPhone)" seçeneği).

## Uygulamada neler var

| Bölüm | Ayrıntı |
|---|---|
| Giriş | Firma No (KavisCloud'dan firma adresi bulunur) ya da program adresiyle bağlanma · e-posta + parola · Google Authenticator (ilk girişte; uygulama içinden kurulum ve yedek kodlar dahil) · KavisCloud geçici parolasının zorunlu değiştirilmesi |
| Face ID / Touch ID | Secure Enclave'de üretilen ECDSA P-256 anahtarıyla sunucu doğrulamalı giriş (özel anahtar telefondan çıkmaz). 5 dakikadan uzun arka planda kalınca yeniden kilitlenir |
| Genel bakış | Özet kartları, tahsilat / ödeme grafikleri, proje ilerlemeleri, yaklaşan işlemler, duyurular, hızlı işlemler |
| Menü | Web panelindeki menünün aynısı (yalnızca yetkili olunan bölümler), bölüm araması |
| Listeler | Arama, süzgeçler (proje, durum…), özet kartları, sonsuz kaydırma, sola kaydırınca işlemler (sil, tahsil et, okundu…) |
| Detaylar | Tüm alanlar, bağlı kayıtlar, taksit planı, teklifler, fotoğraf galerisi (yakınlaştırma), arama ve WhatsApp düğmeleri |
| Formlar | Metin, sayı, para, tarih, saat, seçim, aranabilir bağlı liste (il → ilçe → mahalle zinciri), çoklu seçim, onay kutusu, parola, fotoğraf (kamera / galeri; 2560 px'e küçültülür, konum bilgisi taşınmaz), PDF, kalem satırları (e-Fatura) |
| Raporlar | Tablolar ve sütun grafikleri |
| Bildirimler | Uygulama açıkken 30 sn'de bir; arka planda iOS'un izin verdiği aralıklarla. Vadesi gelen ödeme, çek, senet, kredi taksiti ve randevular; KavisCloud duyuruları. Bildirime dokununca ilgili ekran açılır |
| Ekip sohbeti | Web panelindeki sohbetle aynı kanallar |
| Canlı destek | KavisCloud destek ekibiyle yazışma, destek daveti |
| Diğer | KavisCloud pop-up duyuruları, bağlantı tanılama, zorunlu güncelleme (KavisCloud'daki en düşük sürüm), uygulama değiştiricide ekran içeriği gizlenir |

Yedekleme ve sunucu yönetimi, Android'de olduğu gibi uygulamada yer almaz (web panelinden yapılır).

## Gerekenler

- **Apple Developer Program** üyeliği (yıllık 99 USD) — App Store'a yüklemek için zorunludur.
- Derlemek için iki yoldan biri:
  - **Mac + Xcode 16 veya üstü** (önerilen), ya da
  - **Mac olmadan:** projeyi bir GitHub deposuna yükleyip ekteki GitHub Actions iş akışlarıyla derlemek ve TestFlight'a göndermek (aşağıda).

## 1. Paket kimliği (Bundle ID)

Uygulama `com.kavissoft.insaatsoft.ios` kimliğini kullanır. Android uygulaması `com.kavissoft.insaatsoft` kullandığı ve KavisCloud'da paket adı benzersiz olduğu için iOS'a ayrı bir kimlik verilmiştir. Değiştirmek isterseniz Xcode'da *InsaatSoft hedefi › Signing & Capabilities › Bundle Identifier* alanını değiştirin; KavisCloud'a da aynısını yazın.

KavisCloud adresi `InsaatSoft/App/Config.swift` içindeki `panelURL` değeridir (şu an `https://cloudsoft.kavissoft.com`).

## 2. Mac ve Xcode ile derleme

1. Zip'i açın, `InsaatSoft.xcodeproj` dosyasını Xcode 16 ile açın.
2. Sol üstte **InsaatSoft** hedefini seçin › **Signing & Capabilities** › *Team* olarak Apple Developer ekibinizi seçin. "Automatically manage signing" açık kalsın.
3. Bir iPhone bağlayıp ▶ ile çalıştırın. Face ID ve kamera yalnızca gerçek cihazda çalışır; simülatörde Firma No ve parola ile giriş denenebilir.
4. Yayın için: *Product › Archive* › Organizer'da **Distribute App › App Store Connect › Upload**.

Xcode 15 veya daha eski bir sürüm kullanıyorsanız projeyi XcodeGen ile yeniden üretin: `brew install xcodegen && xcodegen generate` (ekteki `project.yml`).

## 3. Mac olmadan (GitHub Actions)

1. Bu klasörü özel (private) bir GitHub deposuna yükleyin.
2. **iOS derleme denetimi** iş akışı her gönderimde uygulamayı imzasız olarak derler; kırmızı çıkarsa hata kaydı orada görünür.
3. App Store Connect'te *Users and Access › Integrations › App Store Connect API* bölümünden **App Manager** yetkili bir API anahtarı oluşturun, `.p8` dosyasını indirin.
4. Depoda *Settings › Secrets and variables › Actions* altına şu değerleri ekleyin:
   - `APPLE_TEAM_ID`: ekip kimliğiniz (developer.apple.com › Membership)
   - `ASC_KEY_ID`, `ASC_ISSUER_ID`: API anahtarı sayfasındaki değerler
   - `ASC_KEY_P8_BASE64`: `base64 -i AuthKey_XXXX.p8` çıktısı
5. *Actions › iOS TestFlight yükleme › Run workflow* ile sürüm numarasını girin. Uygulama imzalanıp App Store Connect'e yüklenir; birkaç dakika sonra TestFlight'ta görünür.

## 4. App Store Connect

1. **Apps › + › New App**: platform iOS, ad `İnşaatSoft ERP`, birincil dil Türkçe, Bundle ID `com.kavissoft.insaatsoft.ios`, SKU `insaatsoft-ios`.
2. **TestFlight**: yüklenen sürümü önce kendi ekibinize (Internal Testing) açıp deneyin.
3. **App Store sekmesi**: açıklama, anahtar kelimeler, ekran görüntüleri (6,7" ve 6,5" iPhone), destek adresi, gizlilik politikası adresi.
4. **App Privacy**: uygulama izleme yapmaz, reklam yoktur. Veriler yalnızca firmanın kendi İnşaatSoft sunucusuna gider. "Data Not Collected" ya da firmanın sunucusunda tutulan veriler için *Contact Info / User Content — App Functionality, Linked to user, Not used for tracking* seçilebilir.
5. **App Review Information**: Apple inceleme ekibi için mutlaka bir **demo hesabı** verin: Firma No, e-posta ve parola. Bu hesapta Google Authenticator zorunluluğu kapalı olsun (yoksa inceleme reddedilir). Notlara şunu yazın: *"Kurumsal bir uygulamadır; hesaplar firma yöneticisi tarafından açılır, uygulamadan hesap oluşturulmaz."* (Uygulamada hesap oluşturma olmadığı için hesap silme zorunluluğu uygulanmaz.)
6. Şifreleme sorusu: `ITSAppUsesNonExemptEncryption = NO` olarak işaretlidir (yalnızca standart HTTPS kullanılır).

İsterseniz yalnızca firma içi kullanım için App Store yerine **Unlisted App** (bağlantıyla indirilen, mağazada aranmayan) dağıtımı talep edebilirsiniz.

## 5. KavisCloud'a tanıtma

KavisCloud › **Uygulamalar › Yeni uygulama**:

| Alan | Değer |
|---|---|
| Ad | İnşaatSoft ERP (iPhone) |
| Sistem | iOS (iPhone) |
| Paket adı (Bundle ID) | `com.kavissoft.insaatsoft.ios` |
| Program | insaatsoft |
| Sürüm | 1.1.0 |
| App Store adresi | `https://apps.apple.com/tr/app/...` (yayına girince) |

- Uygulama Firma No ile firma ararken bu kaydı kullanır. Kayıt yoksa ya da durumu pasifse "Uygulama tanınmadı / kullanıma kapalı" yanıtı döner.
- **Yeni sürüm**: App Store'da yeni sürüm yayınlanınca KavisCloud'da sürüm numarasını güncelleyin. "Zorunlu güncelleme" işaretlenirse eski sürüm açılmaz, kullanıcı App Store'a yönlendirilir.
- **Bağlı telefonlar** listesinde iPhone'lar "iOS" olarak görünür; erişimi kesilen telefon parola doğru olsa da giremez.
- Firma bazında mobil uygulama kapatılırsa iPhone uygulaması da kapanır.

## 6. Personelin kullanımı

1. App Store'dan **İnşaatSoft ERP**'yi indirin.
2. Firma No'yu girin (yöneticiden alınır).
3. E-posta ve parola ile girin. Bu telefondan ilk girişte Google Authenticator kodu istenir. Hesapta Authenticator kurulu değilse ve yönetici izin verdiyse kurulum uygulama içinden yapılır; gösterilen yedek kodlar güvenli bir yere kaydedilmelidir.
4. Girişten sonra "Face ID ile giriş açılsın mı?" sorusuna **Aç** denirse sonraki girişler Face ID ile yapılır.
5. Bildirim izni verilmelidir (Ayarlar › İnşaatSoft › Bildirimler).

## Web paneliyle eşitlik (uygulama 1.1.0 + İnşaatSoft 1.2.3)

Uygulama 1.1.0, web panelinde yapılabilen işlemlerin tamamını telefondan yapar. Bunun için sunucuda **İnşaatSoft 1.2.3** kurulu olmalıdır (KavisCloud › Paketi Yükle ile dağıtılır). Eski sunucu sürümlerinde uygulama çalışmaya devam eder, yalnızca yeni ekranlar görünmez.

- **Toplu işlem:** listelerde sağ üstteki **Seç** ile kayıtlar işaretlenir; alttaki **İşlemler** menüsünden okundu / sil / hatırlatma gönder / aktif-pasif gibi işlemler seçilenlere uygulanır.
- **Süzgeçler:** seçim, tarih (takvimden) ve bağlı kayıt (proje, müşteri …) süzgeçleri; liste, detay, panel ve rapor ekranlarında.
- **Dosyalar:** belgeler, CSV dışa aktarma, raporlar, e-belge XML'i ve yedekler uygulama içinde açılır; sağ üstteki paylaş düğmesiyle **Dosyalar'a kaydet, yazdır, e-posta, AirDrop**. Bağlantılar 15 dakika geçerlidir ve kullanıcıya özeldir.
- **Formlar:** çoklu görsel yükleme, her türlü dosya (yetkili alanlarda), mevcut görselin önizlemesi ve kaldırılması.
- **İşlem sonuçları:** yeni portal parolası, Authenticator anahtarı, yedek kodlar, takvim bağlantısı gibi bir kez gösterilen bilgiler ayrı sayfada açılır; **Kopyala** ve **Takvime / Authenticator'a ekle** düğmeleriyle.
- **Genel arama:** Menü › büyüteç; proje, müşteri, daire, sözleşme no, telefon ile tüm kayıtlarda arama.
- **Yönetim:** kullanıcılar (tüm alanlar, ana yönetici yetkisi), giriş güvenliği, işlem kayıtları, genel ayarlar, web sitesi tasarımı (tüm sekmeler ve görseller), e-belge ve online ödeme ayarları, SMS / WhatsApp / e-posta ayarları, sunucu ve yedekleme (ana yönetici: yedek al, indir, geri yükle).
- Web panelinde kalanlar (güvenlik ve dosya boyutu nedeniyle): başka sistemden veri aktarımı, bulut yedek hesaplarının bağlanması, mali mühür yükleme.

## Güvenlik

- Yalnızca HTTPS (iOS App Transport Security; geçersiz sertifikalı sunucuya bağlanılmaz).
- Oturum anahtarları iOS Anahtar Zinciri'nde "yalnızca bu cihaz" olarak saklanır; iCloud yedeğine ve başka telefona taşınmaz.
- Erişim anahtarı 30 dakikalıktır; yenileme anahtarı her kullanımda değişir. Uygulama aynı anda tek yenileme yapar (sunucu eski anahtarın tekrar kullanılmasını çalınma sayıp oturumu kapatır).
- Face ID anahtarı Secure Enclave'dedir, cihazdaki yüz / parmak izi kayıtları değişince geçersiz olur; yüz verisi sunucuya gitmez.
- Uygulama değiştiricide ekran içeriği bulanıklaştırılır.
- Bir hesap aynı anda yalnızca bir telefonda açık olabilir (sunucu kuralı).

## Bilinen sınırlar ve sonraki adım

- **Anlık bildirim (push):** iOS arka planda sürekli sorgulamaya izin vermez. Bildirimler uygulama açıkken anında, kapalıyken iOS'un uygun gördüğü aralıklarla (genellikle 15 dakika ile birkaç saat arası) gelir. Uygulama kapalıyken de anında bildirim için sunucuya Apple Push Notification (APNs) gönderimi eklenmelidir. Bunun için İnşaatSoft'a cihaz jetonu kaydı ve bildirim oluşunca APNs'e istek atan küçük bir modül gerekir; uygulama tarafı buna hazırlanabilir.
- Uygulama arayüzü Türkçedir.

## Klasör yapısı

```
InsaatSoft.xcodeproj        Xcode projesi (Xcode 16, klasör eşitlemeli)
InsaatSoft/
  App/        Giriş noktası, sabitler (Config.swift: KavisCloud adresi)
  Core/       API istemcisi, oturum, Anahtar Zinciri, Face ID, KavisCloud, bildirimler
  Screens/    Sunucu tanımlı ekran çizici: liste, detay, panel, tablo, form; menü, sohbet, destek, hesap
  Auth/       Firma No, giriş, Authenticator, Face ID kilidi, parola değiştirme
  UI/         Renkler, simgeler, ortak bileşenler
  Assets.xcassets, PrivacyInfo.xcprivacy
Support/      Info.plist, ExportOptions.plist
.github/workflows/  Derleme denetimi ve TestFlight yükleme
project.yml   XcodeGen tanımı (eski Xcode için)
```
