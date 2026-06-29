<p align="center">
  <h1 align="center">HarvestCo</h1>
  <p align="center">
    Sakin, tek dokunuşla oynanan bir çiftlik oyunu.<br/>
    Önce işi kendin yap — sonra emeğini botlarla otomatikleştir.
  </p>
</p>

---

## Oyunun Amacı

HarvestCo huzurlu (cozy) bir çiftlik oyunudur. Temel fikir:
**"Önce kendin yap, sonra otomatikleştir."**

Oyuna **tamamen elle** başlarsın — her toprağı tek tek dokunarak
sürer, eker, sular ve hasat edersin. Para biriktikçe her biri **tek bir işi**
otomatikleştiren **uzman botlar** satın alırsın (Süren, Eken, Sulayan, Hasatçı,
Temizleyici, Altın Avcısı). Her botun çalışacağı bölgeyi parmağınla **sürükleyerek
boyarsın**. Böylece elle yapılan yorucu iş, yavaş yavaş kendi kurduğun otomasyona dönüşür.

İçeriği zenginleştiren sistemler: 4 ürün + buğday→un işleme zinciri (değirmen),
depo/satış, pasif su kuyusu, altın ürünler, ve rastgele olaylar — gerçekten
yağan **yağmur**, gelip giden **UFO**, sürü halinde dalan **kuşlar** (korkulukla kovulur).

## Hedef

- **Platform:** Mobil (Android / iOS), dikey ekran
- **Kontrol:** Tek parmak / tek dokunuş
- **His:** Sakin, renkli, sıcak — "bir el daha oynayayım" hissi veren idle döngü
- **Durum:** Oynanabilir konsept prototip (mekanikler oturdu; sıradaki adım grafik/sanat güncellemesi)

## Geliştirilirken Ne Kullanıldı

- **Motor:** [Godot 4.3](https://godotengine.org/)
- **Dil:** GDScript
- **Render:** GL Compatibility (eski mobil cihaz uyumu)
- **Geliştirme ortamı:** [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
  ile yapay zekâ destekli geliştirme (stüdyo-ajan iş akışı)
- **Sürüm kontrolü:** Git

> Prototip kodu `prototypes/bot-orchestration-concept/` altında tek dosyada
> (`main.gd`) tutulur. Hızlı iterasyon için standartlar bilinçli olarak gevşektir;
> üretim koduna geçişte yeniden yazılacaktır.

## Nasıl Çalıştırılır

1. [Godot 4.3](https://godotengine.org/download/) indir ve aç.
2. `prototypes/bot-orchestration-concept/project.godot` dosyasını içe aktar.
3. **F5** ile çalıştır.

## Lisans

MIT — bkz. [LICENSE](LICENSE).
