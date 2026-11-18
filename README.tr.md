# NOCTURNE

macOS 14 ve üzeri için SwiftUI ve AppKit ile yazılmış müzik arşivi ve oynatıcı. Arayüz İngilizce ve Türkçedir (Settings → General → Language). YouTube Music bağlantıları ve Mac’teki ses dosyaları aynı yerel arşivde tutulur.

[English](README.md)

## Kurulum

1. Depoyu indirin ve klasöründe `./Scripts/release.sh` komutunu çalıştırın.
2. `dist/NOCTURNE.dmg` dosyasını açın ve NOCTURNE simgesini Applications klasörüne sürükleyin.
3. Uygulamayı Applications içinden açın.

Paket yerel ad hoc imza taşır. Apple Developer ID imzası ve noter onayı yoktur. İnternetten indirilen kopyalarda Gatekeeper açılış için kullanıcı onayı isteyebilir. Uygulama herhangi bir geliştirme aracı, API anahtarı veya yardımcı sunucu gerektirmez.

## İlk kullanım

- **Arama ve oynatma.** ⌘F ile aramayı açın ve şarkı ya da sanatçı adını yazın. Sonuçlar NOCTURNE’un kendi satırlarında görünür. Şarkıya bir kez tıklayınca resmî YouTube oynatıcısı ana pencereye yerleşir. Yerel çalma listeleri ve Songs ekranı da aynı oynatıcıyı kullanır.
- **Hesapsız arama.** Arama doğrudan YouTube'un anahtarsız arama uç noktasını kullanır ve sonuçlar uygulamanın kendi satırlarında görünür. YouTube'a ulaşılamazsa Wikidata ve TheAudioDB dizinleri yedek olarak aranır. Google hesabı yalnızca çalma listelerinin eşitlenmesinde kullanılır.
- **YouTube Music hesabı.** Settings → Google account → Sign in to YouTube Music ile uygulama içi pencerede bir kez oturum açın. Kitaplığınızdaki çalma listeleri (Beğenilenler dahil) API anahtarı olmadan kopyalanır; açılışta ve 30 dakikada bir yenilenir. Oturum çerezleri yalnızca bu Mac'teki WebKit deposunda durur.
- **Şarkı sözleri.** Alt çubuktaki kapağa tıklayınca Now Playing açılır ve sözler çalan satırı izler; bir satıra tıklamak o ana sarar. Sözler LRCLIB'den gelir; her şarkı için bulunmayabilir.
- **Arka plan.** Uygulama gizlendiğinde veya pencere küçültüldüğünde müzik çalmaya devam eder. Settings → Appearance → Background image ile içerik alanına kendi resminizi koyabilirsiniz.
- **Çalma listeleri.** Playlists → Link YouTube Music playlist ile (veya ⌘L) herkese açık bir YouTube / YouTube Music liste ya da albüm bağlantısı yapıştırın. Parçalar bir kereliğine yerel bir çalma listesine kopyalanır; hesap, API anahtarı ve sürekli eşitleme gerekmez. Playlists → Import Takeout playlists ile açılmış Google Takeout arşivinin çalma listeleri klasörünü veya CSV dosyalarını seçebilirsiniz. Dosyada video kimliği bulunan parçalar sırayla alınır. Başlığı dışa aktarılmayan kayıtların adı ilk oynatmada alınır.
- **Tek parça ekleme.** ⌘L ile paylaşılan bir YouTube şarkısının bağlantısını yapıştırabilirsiniz. Başlık, kanal ve kapak YouTube oEmbed yanıtından gelir.
- **Yerel dosyalar.** ⌘O ile macOS’un desteklediği ses dosyalarını seçin. AVFoundation gömülü başlığı, sanatçıyı, albümü, kapağı ve süreyi okur. Dosyalar kendi konumlarında kalır. Taşınan dosyayı yeni konumundan tekrar içe aktarabilirsiniz.
- **Listeler ve favoriler.** ⌘N ile liste oluşturun. Şarkının bağlam menüsünden listeye ekleyin veya sol kenar çubuğundaki listeye sürükleyin. Bir listenin içinde Move up, Move down ve Remove from playlist komutları kullanılabilir. Yeniden adlandırma ve silme için kenar çubuğundaki listeye sağ tıklayın.
- **Oynatıcılar.** Alt çubuk, genişletilmiş Now Playing ve ⇧⌘M ile açılan Mini Player aynı oturumu kullanır. Settings içinden mini pencereyi üstte tutabilir, görünümü veya Touch Bar düzenini değiştirebilirsiniz.
- **Depolama.** Arşiv, favoriler, listeler, arama ve dinleme geçmişi bu Mac’te SQLite ile saklanır. Settings → Show library storage in Finder veri klasörünü açar. Yerel albümler ve sanatçılar dosya etiketlerinden gruplanır. Geçmiş, oynatıcı gerçekten çalmaya başladığında kaydedilir.

## Katalog ve oynatma kapsamı

Arama, sonuç seçimi ve çalma listeleri SwiftUI ile sunulur. Explore, Charts ve oradan açılan liste, albüm, sanatçı ve tür sayfaları da YouTube Music'in anahtarsız veri uç noktasından okunup yerleşik arayüzde gösterilir; web sayfası açılmaz. YouTube videosu ana pencereye yerleştirilen görünür resmî oynatıcıda çalar. Yerel dosyalar AVPlayer kullanır. Reklam, kalite, bölge ve gömme izinlerini YouTube belirler. Bir kayıt gömülemiyorsa hata aynı uygulamada gösterilir.

## Google hesabıyla otomatik yenileme

Settings → Google account veya Playlists bölümünden bağlanılır. Bu dağıtımda geliştiriciye ait kayıtlı OAuth istemcisi bulunmuyor. Bağlanmak için YouTube Data API v3 etkinleştirilmiş bir Google Cloud projesine ait **Desktop app OAuth istemci JSON dosyası** gerekir. Dağıtıcı bu istemciyi Resources/GoogleOAuth.json olarak ekleyip paketi yeniden üretebilir, böylece son kullanıcı dosya seçmeden Google onay ekranına geçer. Google projesi test modundaysa hesabın test kullanıcısı olarak yetkilendirilmesi gerekebilir.

Google onay ekranı sistem tarayıcısında açılır. Uygulama salt okunur YouTube izni ister ve PKCE kullanır. Yenileme belirteci macOS Anahtar Zinciri’nde tutulur. Başarılı bağlantıdan sonra açılışta, uygulama açıkken her 30 dakikada ve “Sync now” komutuyla hesaba ait listeler ve parçalar güncellenir. Yalnızca tüm sayfalar başarıyla geldikten sonra yeni kopya SQLite’a yazılır. İnternet veya kota hatasında son kayıtlı kopya korunur. Google’dan gelen listeler ayrı gösterilir. NOCTURNE’daki yerel düzenlemeler Google’a gönderilmez. Disconnect yerel bağlantıyı ve hesaptan indirilen liste kopyalarını kaldırır. Kendi arşivinize eklenmiş parçalar korunur.

Eşitlemenin kapsamı YouTube Data API’nin kullanıcıya ait olarak bildirdiği listelerdir. YouTube Music’in otomatik miksleri, diğer hesapların kaydedilmiş listeleri ve dinleme önerileri bu çağrının kapsamına girmeyebilir. Uygulama kapalıyken eşitleme çalışmaz. Bu dağıtımda kişisel bir hesapla canlı onay ve eşitleme testi yapılmadı.

[Google masaüstü OAuth akışı](https://developers.google.com/identity/protocols/oauth2/native-app) · [YouTube listeleri](https://developers.google.com/youtube/data/guides/implementation/playlists) · [YouTube oynatıcı API’si](https://developers.google.com/youtube/iframe_api_reference) · [Wikidata YouTube video kimliği](https://www.wikidata.org/wiki/Property:P1651)

## Geliştirme

Package.swift dosyasını Xcode ile açabilir veya Apple Command Line Tools ile proje klasöründe şu komutları kullanabilirsiniz.

```sh
swift build
NOCTURNE_LIVE_TEST=1 NOCTURNE_NATIVE_TEST=1 NOCTURNE_PLAYER_TEST=1 NOCTURNE_CATALOG_TEST=1 swift test --no-parallel --disable-xctest -Xswiftc -gnone
./Scripts/release.sh
```

Paketleme betiği iki mimariyi ayrı derler, lipo ile birleştirir, yerel imza atar ve dist klasöründe uygulama ile disk görüntüsü oluşturur. Bu sürüm App Sandbox dışında çalışır ve özel entitlement kullanmaz. Uygulama ikonunun vektör çizimi Scripts/Icon.swift içindedir.

Kaynak dosyaları Sources/Nocturne içindedir. Library SQLite depolamasını, Provider ağ ve dosya erişimini, Session oynatma ile kuyruk durumunu, InlinePlayer ana pencereye yerleşen YouTube oturumunu ve TouchBar AppKit denetimlerini içerir. Dinleme sırasında ilerleme çizgisi ayrı bir gözlemlenebilir nesne ile güncellenir. Kapaklar en fazla 600 piksele örneklenir ve bellek önbelleği 20 MiB ile sınırlandırılır. Çalmayan YouTube oturumunda ilerleme zamanlayıcısı çalışmaz.

### Google istemcisi ve kota

Google Cloud Console'da bir proje oluşturup YouTube Data API v3 hizmetini etkinleştirin. Google Auth Platform altında kişisel kullanım için External seçin, kendi hesabınızı test kullanıcısı olarak ekleyin ve Data Access bölümüne youtube.readonly iznini ekleyin. Clients → Create client → Desktop app yolundan istemciyi oluşturup JSON dosyasını indirin. NOCTURNE'da Settings → Google account bu dosyayı kabul eder. Testing durumundaki projelerde bu izin için yedi gün sonra yeniden giriş gerekebilir.

Yerleşik arama ve YouTube oynatımı Google Data API arama kotasını kullanmaz. Google hesabı yalnızca çalma listelerinin salt okunur eşitlenmesine izin verir. playlists.list ve playlistItems.list sayfalarının her biri varsayılan günlük 10.000 birimlik genel kotadan bir birim kullanır. [Google kota tablosu](https://developers.google.com/youtube/data/determine_quota_cost)

1.2 sürümünde görünür YouTube oynatıcısı kenar çubuğunun altındadır. Takeout CSV aktarımı YouTube Data API kotasını kullanmaz.
