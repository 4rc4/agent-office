# Agent Office: piksel ofiste çalışan AI ajanlar (plan)

Tarih: 2026-10-28. Durum: **plan, henüz kod yok.** Onaydan sonra ayrı bir repoda yapılır
(Catudy'nin içine girmez; sebebi aşağıda).

---

## 1. Tek bakışta

- **Ne:** Windows'ta çalışan küçük bir masaüstü uygulaması. Piksel bir ofis; masalarda Claude,
  GPT ve Gemini "çalışan" olarak oturur. Sen tek bir istek yazarsın, Claude (beyin) işi böler,
  dağıtır, sonucu toplar.
- **Teknoloji:** Flutter (Windows) + SQLite. Oyun motoru yok; düz çizim, boşta %0 CPU.
- **Abonelikle nasıl çalışıyor:** Uygulama API anahtarı kullanmaz. Senin zaten giriş yaptığın
  resmi programları (`claude`, `codex`, `agy`) arka planda çalıştırır ve çıktılarını okur.
  Şifre/token'a hiç dokunmaz.
- **Claude:** `claude -p` (yazısız, komut satırı modu) ile uzun ömürlü tek bir "beyin" süreci.
- **GPT:** `codex exec --json` ile iş başına bir "işçi" süreci. ChatGPT girişiyle çalışır.
- **Gemini:** **Kötü haber.** Gemini CLI, Haziran 2026'dan beri bireysel Google hesaplarına
  (ücretsiz, AI Pro, Ultra) hizmet vermiyor. Yerine gelen Antigravity CLI (`agy`) var ama
  Google "üçüncü parti ajanların içinde sarmalamak desteklenmez" diyor; hesap kapanma riski.
  Bu yüzden v1'de Gemini masası **elle kullanılan danışman koltuğu**, otomatik işçi değil.
- **Tarayıcı izleme:** Ofisin kendi açtığı tek bir gizli Chrome'u ajanlara ödünç veriyoruz;
  masadaki monitöre tıklayınca o ajanın sayfasının ekran görüntüsü açılıyor.
- **Kullanım göstergeleri:** Duvar saatleri gibi 3 gösterge: 5 saatlik ve haftalık doluluk %.
  Claude ve Codex için resmi yoldan okunur; `agy` için yüzde yok, sadece "aç ve bak" tuşu.
- **Devam etme:** Her şey SQLite'ta. Bilgisayar kapansa bile açılışta yarım işler
  `--resume` ile kaldığı yerden sürer.
- **Fazlar:** 0 Deneme → 1 Çekirdek döngü → 2 Ofis penceresi → 3 Tepsi+otomatik başlatma+devam
  → 4 MCP+kullanım göstergeleri → 5 Tarayıcı izleme → 6 Gemini seçeneği + oyunlaştırma.
  Toplam ~22 odaklı gün, akşamları çalışınca 2-3 ay.

---

## 2. Ne yapıyoruz, ne yapmıyoruz

**Yapıyoruz**

- Tek istek → Claude planlar → GPT'ye (ve kendine) alt görev → Claude birleştirir → rapor.
- Tıklanabilir piksel ofis: masalar, beyaz tahta (görev panosu), kahve köşesi, posta kutusu.
- Ajan sana soru sorarsa veya izin isterse: kafasının üstünde konuşma balonu + tepside bildirim.
- Otomatik başlatma, tepsiye küçülme, tek örnek (ikinci kez açılmaz).
- Yarım kalan işi devam ettirme.

**Yapmıyoruz**

- API anahtarı, kredi, ücretli API: **yok.** `ANTHROPIC_API_KEY` ortamdan silinir, `claude --bare`
  asla kullanılmaz (o mod aboneliği yok sayıp API anahtarı ister).
- Token/şifre dosyası okumak, gizli kullanım adreslerine istek atmak: **yok.** Anthropic bunu
  açıkça yasaklıyor; bazı "usage tracker" programları bunu yapıyor, biz yapmayacağız.
- Uygulamayı başkalarına "Claude ile giriş yap" diye dağıtmak: **yok.** Kişisel, tek kullanıcılı,
  yerel bir araç. Kural böyle.
- Claude Agent SDK (programlama kütüphanesi) kullanmak: **yok.** Dokümanlarda API anahtarı
  gerektiriyor diye geçiyor. Biz sade `claude` programını çalıştırıyoruz.

---

## 3. Mimari

Kısa sözlük:

- **CLI:** komut satırı programı. Örn. terminale `claude` yazınca açılan şey.
- **Headless / `-p` modu:** CLI'ın ekransız çalışması. Soruyu veriyorsun, cevabı JSON satırları
  olarak basıyor. Bizim uygulama bu satırları okuyup animasyona çeviriyor.
- **MCP:** ajanın kullanabildiği "araç kutusu" standardı. Biz Claude'a kendi aracımızı veriyoruz,
  örn. `office_plan_submit` = "planı panoya yaz" düğmesi.
- **Oturum kimliği (session id):** ajanın sohbet kaydının adı. Saklarsan sonra "o sohbete geri dön"
  diyebiliyorsun. Devam etmenin anahtarı bu.

| Parça | İşi | Teknoloji | Aboneliği nasıl kullanır |
|---|---|---|---|
| Ofis uygulaması | Pencere, piksel çizim, tepsi, otomatik başlatma | Flutter 3.47+ (Windows), `window_manager`, `tray_manager`, `launch_at_startup`, `windows_single_instance` | Model çağrısı yapmaz |
| Çekirdek (office_core) | Görev panosu, durum makinesi, süreç yöneticisi, açılışta toparlama | Saf Dart, ayrı isolate; SQLite (`drift`) | Model çağrısı yapmaz |
| Claude beyin | Planlar, gözden geçirir, birleştirir | `claude -p --output-format stream-json --input-format stream-json --verbose --include-partial-messages --permission-mode auto --mcp-config office-mcp.json --append-system-prompt-file brain.md` | Senin `/login` ile girdiğin Pro/Max hesabı. Açılışta `apiKeySource == none` kontrolü |
| Ofis MCP sunucusu | Claude'un eli: `office_plan_submit`, `office_task_complete`, `office_ask_user`, `approve` | Uygulamanın içinde HTTP (127.0.0.1), `shelf` | Yok |
| GPT işçi | Net tanımlı kod işleri | `codex exec --json -C <repo> -s workspace-write -o <id>.md "<görev>"`; devam: `codex exec resume <thread_id>` | `codex login` (ChatGPT ile giriş). Plus/Pro |
| Codex kullanım okuyucu | 5 saat / hafta yüzdeleri | Tek uzun ömürlü `codex app-server --listen stdio://`, `account/rateLimits/read` + `updated` | Aynı giriş; deneysel protokol |
| Gemini koltuğu (v1: elle) | Danışman; masaya tıklayınca terminalde `agy` açılır, görev metni panoya kopyalanır | `agy` resmi kurulum; uygulama onu otomatik sürmez | Google AI Pro girişi `agy`'nin kendisinde |
| Tarayıcı izleme | Ajanların sayfasını küçük resim olarak göster | Ofisin açtığı `chrome --headless=new --remote-debugging-port=9222 --user-data-dir=...` + ajanlara `chrome-devtools-mcp --browserUrl` | Yok |
| Etkileşim yolu | İzin istekleri ve sorular → balon → senin tıkın | Dart; `--permission-prompt-tool mcp__office__approve` | Yok |

```
   [Sen]  prompt
     │
     ▼
 ┌──────────────── Ofis uygulaması (Flutter) ────────────────┐
 │  piksel ofis  ◄── olaylar ──  office_core (SQLite pano)   │
 │                                   │        ▲              │
 │                      stdin/stdout │        │ MCP (http)   │
 └───────────────────────────────────┼────────┼──────────────┘
                                     ▼        │
                     claude -p (beyin) ────────┘
                           │ alt görevler (pano üzerinden)
                           ▼
          codex exec --json (GPT)        agy (elle, terminal)
                           │
                  paylaşılan gizli Chrome (isteğe bağlı)
```

---

## 4. Bir prompt'un yolculuğu

1. Resepsiyon masasına isteği yazarsın, proje klasörünü seçersin. Pano'ya `kök görev: sırada`
   satırı yazılır. Zarf Claude'un masasına kayar.
2. **Bütçe kapısı:** Claude'un son bilinen kullanımı 5 saatlikte %85 veya haftalıkta %95 üstüyse
   görev "bütçe bekliyor" olur; Claude kahve makinesine yürür, balonunda saat sayar.
3. Beyin süreci yoksa açılır (yeni `--session-id`, veya bu proje için eski id varsa `--resume`).
   İlk olay `system/init` gelince session id **hemen** SQLite'a yazılır.
4. İstek, kurallarla birlikte tek bir mesaj olarak Claude'a gider: "Repoyu incele, planı
   `office_plan_submit` ile gönder; birbirinden bağımsız parçaları ayır; net tanımlı uygulama
   işini GPT'ye ver, gözden geçirmeyi kendin yap."
5. Claude okur, araştırır (Read/Grep otomatik izinli). Planı gönderir. Uygulama alt görevleri
   panoya yazar; beyaz tahtaya yapışkan notlar dizilir, her masaya kağıt uçak uçar.
6. Dağıtıcı: bağımlılığı bitmiş, koltuğu boş, bütçesi uygun alt görevi başlatır. GPT için
   `codex exec --json` açılır; `thread.started` gelince thread id saklanır.
7. İşçi çalışırken her olay (komut çalıştırdı, dosya değişti, sayfa açtı) hem panoya hem
   animasyona gider.
8. İşçi bitince: `git diff --stat` alınır, özet tek bir mesajla Claude'a döner: "Alt görev X
   bitti, dosyalar şunlar, diff burada."
9. Claude inceler. Beğenmezse aynı Codex konuşmasına geri bildirim gönderir (en fazla 2 deneme,
   sonra kırmızı balon: "insan lazım"). Beğenirse kabul eder.
10. Hepsi bitince Claude birleştirir, testleri koşar, `office_task_complete` der. Konfeti, +XP.
11. Sonuç posta kutusuna düşer: özet, değişen dosyalar, "editörde aç". Oraya yazdığın cevap aynı
    beyin oturumuna gider, bağlam kaybolmaz.
12. 5 dakika hareket yoksa beyin sürecinin stdin'i kapanır, süreç temiz çıkar (session id durur).
    Ofis uyur: CLI süreci yok, animasyon zamanlayıcısı durmuş, %0 CPU.

---

## 5. Görev panosu ve kaldığı yerden devam

**Tablo: tasks**
`id, parent_id, kind (root|subtask|follow_up), title, prompt, cwd, assignee (claude|gpt|gemini),
status, attempt, dispatch_token, depends_on, result_path, created_at, updated_at`

**Tablo: sessions**
`task_id, provider, session_ref (Claude session id / Codex thread id / agy conversation id),
launch_args, last_turn_state (idle|in_turn), updated_at`

Ayrıca `events` (ham JSON olaylar, 5 bin satırlık halka), `interactions` (bekleyen izin/soru
balonları), `usage_snapshots` (kullanım anlık görüntüleri, kaynak + zaman damgası), `xp`.

**Durumlar:** sırada → planlandı → atandı → çalışıyor → (izin bekliyor | kullanıcı bekliyor |
bütçe bekliyor) → inceleme → bitti | başarısız | insan lazım.

**Yeniden açılışta (reboot dahil):**

1. Bellekteki hiçbir şeye güvenme; her şeyi SQLite'tan kur (OpenAI Symphony'nin kuralı).
2. Ortam doktoru: `claude`, `codex`, `agy`, Chrome yolları `where.exe` ile bulunur ve saklanır
   (otomatik başlatmada PATH eski kalabilir). Girişler kontrol edilir.
3. Bitmemiş görevler yüklenir. "Bütçe bekliyor" olanlara zamanlayıcı kurulur.
4. Bekleyen balonlar yeniden gösterilir. Hiçbir şey kendiliğinden onaylanmaz.
5. Yarıda kalan Claude turu: `claude -p --resume <id>` + ortam değişkeni
   `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1` ve ek mesaj "Yeniden başlatıldın; panoyu ve
   `git status`'u kontrol et, bitmiş adımları tekrar yapma." `--resume` MCP ayarını
   geri getirmez, `--mcp-config` her seferinde tekrar verilir.
6. Yarıda kalan Codex: `codex exec resume <thread_id> "Yarıda kaldın, git status'a bak, devam et."`
7. Kayıt silinmişse (Claude 30 günde eski kayıtları temizler; ayarı 365'e çekeriz) yeni oturum
   açılır ve bağlam bizim panodaki özetlerden kurulur. Özetleri bu yüzden kendimiz tutuyoruz.

**Idempotans** (düz Türkçesi: aynı iş iki kez yapılmasın): her gönderimin `attempt` numarası ve
`dispatch_token`'ı var. Eski denemeden gelen sonuç tokena uymazsa kayda alınır, uygulanmaz.

**Dikkat:** Dosya ortasında yarıda kalan bir düzenlemeyi gözü kapalı sürdürmek en riskli an.
Varsayılan: bekleme durumları otomatik devam eder, yarım kod düzenlemesi ise "devam etmeye hazır"
durumuna gelir ve senden bir tık ister (görevi "otonom" işaretlemediysen).

---

## 6. Piksel ofis

**Sahne:** 320×180 piksel, tam sayı ölçekle büyütülür (960×540 veya 1280×720). Serbest boyut
yok (Impeller'ın Windows'ta boyut değişiminde RAM sıçratma hatası var, #191050).

- Sol duvar: resepsiyon (prompt kutusu + proje seçici), posta kutusu (sonuçlar).
- Orta: Claude'un köşe masası (büyük monitör), arkasında beyaz tahta (yapışkan notlar = alt
  görevler, renk = durum).
- Sağ: GPT masası (terminal ekranlı monitör). Kapı yanında Gemini danışman koltuğu, ziyaretçi
  kartı.
- Arka duvar: 3 gösterge (sağlayıcı başına), kahve makinesi (bekleyenler), dosya dolabı (olay
  günlüğü), ışık anahtarı (hepsini durdur/devam).

**Tıklanabilirler**

| Nesne | Açılan |
|---|---|
| Herhangi masa | Ajan paneli: sürüm, giriş durumu, session id, cwd, şu anki araç, bugünkü token, son 20 olay, Durdur |
| Beyaz tahta | Kanban: sırada / çalışıyor / bekliyor / inceleme / bitti; nota tıkla → prompt ve diff |
| Resepsiyon / posta kutusu | Yeni istek; sonuçlar listesi; cevap kutusu (devam soruları) |
| Konuşma balonu | İzin: araç adı + tam komut; "Bir kez izin ver / Bu görevde hep / Reddet" |
| Duvar göstergesi | Kullanım detayı: pencere başına %, sıfırlanma sayacı, kaynak, tazelik |
| Kahve makinesi | Bütçe bekleyenler + "şimdi dene" |
| Dosya dolabı | Olay günlüğü, filtre, dışa aktar |
| Masadaki monitör | Tarayıcı izleme (küçük resimler, büyüt) |
| Gemini koltuğu | Terminalde `agy` aç, görev metnini panoya kopyala, cevabı geri yapıştır |
| Işık anahtarı | Hepsini durdur / devam; "gece modu" (sabaha kadar yeni iş başlamaz) |
| Raftaki alet kutusu | Ayarlar: exe yolları, izin tavrı, paralellik, bütçe eşikleri, otomatik başlatma |

**Olay → animasyon**

| Olay | Ofiste görülen |
|---|---|
| `system/init` / `thread.started` | Kapıdan girer, oturur, monitör açılır |
| Metin akıyor | Yazan eller, "..." balonu |
| Okuma aracı (Read/Grep) | Öne eğilir, kağıtlar karışır |
| Düzenleme (Edit/Write, `file_change`) | Kalem simgesi, tepsiye dosya uçar, sayaç artar |
| Komut (Bash, `command_execution`) | Monitör yeşil terminal olur |
| Tarayıcı aracı | Monitörde küre; izleme açıksa küçük resim yenilenir |
| İzin / soru isteği | Ayağa kalkar, el kaldırır, sarı "?" balonu, lamba sarı; tepside bildirim |
| `office_plan_submit` | Tahtaya notlar tek tek yapışır, masalara kağıt uçak |
| Tur bitti | Esner, yeşil tik, kağıt Claude'un kutusuna uçar |
| Kök görev bitti | Konfeti, +XP, Claude ile GPT çak |
| Limit uyarısı / limit doldu | Ter damlası / kahve makinesine yürür, saat balonu |
| Hata / çökme (exit 143) | Kırmızı "!" balonu, kafa kaşır, lamba kırmızı yanıp söner |
| Bağlam sıkıştırma (`compacting`) | Kağıtları çekmeceye toplar (donma sanılmasın) |
| Alt ajan (subagent) | Yanına yarım boy stajyer gelir, bitince gider |
| 2 dk sessizlik / 10 dk sessizlik | Kahve kupası, zzz / ekran koruyucu, ışıklar kısılır, zamanlayıcı durur |

**Kullanım göstergeleri:** her değerin yanında "2 dk önce / 40 dk eski / bilinmiyor" etiketi.
Claude: 5 saat ve hafta çubukları (`/usage` raporu + `rate_limit_event`), modele göre token.
Codex: `account/rateLimits` ne döndürürse (pencere süresine göre etiketlenir; 5 saatlik pencere
2026'da bir açılıp bir kapandı, var sayma). `agy`: sadece token sayısı ve "`/usage` aç" tuşu.

**Tarayıcı izleme:** monitöre tıkla → o ajanın izole Chrome bağlamındaki sayfaların küçük
resmi (JPEG kalite 40, 320 px), pencere açıkken 2-3 sn'de bir yenilenir. "Büyüt" →
`Page.startScreencast` (her kare onaylanır), kapatınca durur. Chrome yalnızca tarayıcı gereken
iş gelince açılır, 10 dk boşta kalınca kapanır.

**Oyunlaştırma:** XP yalnızca sonuca bağlı, tokena değil (token ödüllendirmek aboneliği yakmayı
ödüllendirir). +10 kabul edilen alt görev, +25 biten kök görev, +5 gerçek hata bulan inceleme.
Seviyeler masa eşyası açar (bitki, poster, kedi). Seri: en az bir iş biten gün sayısı.

**ADHD dostu bildirim kuralı:** sadece üç şey bildirim yapar: izin/soru, kök görev bitti,
görev başarısız. Gerisi sessizce ofiste oynar.

---

## 7. Bilgisayarı yormamak için

- Oyun döngüsü yok. Flutter yalnızca istenince kare çizer; 100 ms'lik tek zamanlayıcı sadece bir
  şey hareket ederken çalışır, pencere küçülünce/arka plana geçince iptal olur. Flame
  kullanılmaz (her vsync'te tick atar, boş ofiste bile CPU yer).
- Tek sprite sayfası, `FilterQuality.none`, tam sayı ölçek. Gölgelendirici, parçacık yok
  (2 sn konfeti hariç).
- Boşta: hiçbir CLI süreci yok (beyin 5 dk sonra kapanır, id ile geri gelir). Hedef: 10 dk
  boşta **≤120 MB RAM, %0 CPU** (Faz 0'da gerçek PC'de ölçülür).
- Çalışırken dürüst sayılar: `claude.exe` ve `codex.exe` her biri 100-300 MB, Chrome ~150 MB +
  sekme başına ~50 MB. Üç ajan + Flutter derlemesi 8 GB RAM'de rahat olmaz.
- Varsayılan paralellik: beyin + 1 Codex. İkinci Claude işçisi kapalı. Alt ajan sınırı 2.
- Olay güdümlü: stdout borularından okunur, `~/.claude` ve `~/.codex` klasörleri taranmaz
  (biçimleri resmen kararsız).
- Kullanım yoklaması seyrek: `/usage` 5 dakikada bir ve sadece beyin açıkken; Codex bildirimle.
- MCP sunucusu ve hook alıcısı uygulamanın içinde HTTP; her araç çağrısında ayrı süreç açılmaz.
- Tek paylaşılan Chrome, ajan başına izole bağlam; ekran görüntüsü yalnızca pencere açıkken.
- `npx` ile açılan MCP sunucuları sürüm sabitli (`cmd /c npx -y paket@sürüm`), Node LTS (24 değil).

---

## 8. Otomatik başlatma ve güvenlik

- **Otomatik başlatma:** `launch_at_startup` ile HKCU Run anahtarı, argüman `--minimized`; uygulama
  tepside başlar. Açılışta diğer programlarla yarışmasın istersen Görev Zamanlayıcı
  "oturum açılışında, 1 dk gecikme" seçeneği.
- **Yollar:** otomatik başlatılan program eski PATH'i görür; `claude.exe`, `codex`, `agy` mutlak
  yolla çağrılır, npm `.cmd` dosyaları `cmd /c` ile.
- **İzin tavrı (varsayılan):** okuma araçları serbest, dosya düzenleme kabul, kabuk komutları
  balonla sor. `permissions.deny` listesi: `git push --force`, `rm -rf`, `reset --hard`.
  Push hiçbir zaman otomatik değil. Codex `-s workspace-write` (sadece proje klasörüne yazar).
- **Gözetimsiz çalışma yok:** otomatik başlatma ofisi uyandırır, bekleyen izinleri gösterir;
  sen tıklamadan yeni iş başlamaz. "Otonom" bayrağı görev başına, bilinçli açılır.
- **Hesap güvenliği:** uygulama `claude`'u `--bare` ile asla açmaz, `ANTHROPIC_API_KEY` ortamdan
  silinir, `system/init` içinde `apiKeySource == none` değilse çalışmayı reddeder. Hiçbir
  kimlik dosyası okunmaz (`.credentials.json`, `auth.json`).
- **Kapanış:** önce stdin kapatılır, 20 sn beklenir, sonra öldürülür. Dart Windows'ta SIGINT
  gönderemez; sert kapanış 143 koduyla yarım tur bırakır, bu yüzden resume değişkeni hep açık.

---

## 9. Fazlar

| Faz | Kapsam | Bitti sayılır | Süre |
|---|---|---|---|
| **0. Deneme ve doğrulama** | Gerçek PC'de `claude`, `codex`, `agy` kur ve giriş yap. Atılacak betiklerle doğrula: stream-json giriş/çıkış, `apiKeySource`, `/usage` ham CLI'da rapor veriyor mu, `codex exec --json` olay şekilleri, `app-server rateLimits`, `agy -p` bayrakları, Chrome 136+ ile `--user-data-dir`, boşta RAM | Her varsayım için geçti/kaldı listesi, JSON örnekleri dosyada, sürümler sabitlenmiş, Gemini için "git/gitme" kararı | 2 gün |
| **1. Çekirdek döngü (arayüzsüz)** | `office_core`: SQLite şeması, durum makinesi (testli), süreç yöneticisi, Claude beyin adaptörü, Codex işçi adaptörü, sabit plan-JSON ile dağıtım, birleştirme turu, terminalden `office_core run "<istek>"` | Test reposunda tek istek → en az 1 Codex + 1 Claude görevi → birleşik rapor; SQLite'ta tüm satırlar doğru | 4-5 gün |
| **2. Ofis penceresi (MVP)** | Flutter kabuğu, sahne çizimi, ~12 sprite, 3 masa, beyaz tahta, kahve köşesi, prompt çubuğu, en az 8 animasyon, ajan paneli, görev panosu, sonuç penceresi | İsteği pencereden yaz, planla→çalış→birleştir akışını izle, masaya tıkla günlüğü oku; boşta Görev Yöneticisi %0 CPU | 4 gün |
| **3. Tepsi, otomatik başlatma, devam** | Tepsiye küçülme, tek örnek, `--minimized`, düzgün kapanış, açılışta toparlama ve `--resume` / `exec resume`, limit bekleme + uyandırma | İş başlat, Görev Yöneticisi'nden öldür, yeniden başlat: ofis tepside açılır, yarım işi bitirir, isteği tekrar yazmazsın | 2.5 gün |
| **4. MCP + kullanım göstergeleri** | Uygulama içi MCP sunucusu (`plan_submit`, `task_complete`, `ask_user`, `approve`), http hook'lar, "kullanıcı bekliyor" akışı, kullanım servisi, duvar göstergeleri, bütçe kapısı | Claude MCP ile dağıtır ve soru sorabilir; göstergeler `/usage` ve `/status` ile bir yenilemede tutar; sahte "limit doldu" olayı dağıtımı durdurur, saati gelince kendi başlar | 3.5 gün |
| **5. Tarayıcı izleme** | Paylaşılan gizli Chrome, CDP istemcisi, `chrome-devtools-mcp` ayarı, izole bağlam kuralı, monitör küçük resimleri | GPT'ye bir dokümantasyon sayfası baktır; masasında başlık ve yenilenen ekran görünür; Chrome 10 dk sonra kapanır | 3 gün |
| **6. Gemini seçeneği + oyunlaştırma + cila** | Elle `agy` koltuğu; şartları kabul ettiysen kapalı gelen "agy otomasyonu" anahtarı; XP, seviyeler, eşyalar, ayarlar, ortam doktoru, kurulum paketi | Temiz Windows profilinde: kur, iki CLI'a gir, yeniden başlatmada otomatik açılır, yarım iş devam eder; bir akşam gerçek Catudy işi terminale dokunmadan biter | 3 gün |

Toplam ~22 gün. Sprite'lar için "kendi düz stilimde çizerim" dersen +1 gün.

---

## 10. Dikkat / Yanlış giden fikirler

1. **Gemini CLI planın en zayıf halkası.** Araştırmaya göre 2026-06-18'den beri bireysel
   hesaplara kapalı; yerine `agy` var ve Google üçüncü parti sarmalamayı desteklemiyor, yasak bir
   kez uyarı, ikincide kalıcı, ve aynı Google hesabındaki her şeyi etkiler. Bu yüzden v1'de elle
   koltuk. Tam uyumlu otomatik Gemini istiyorsan tek yol Gemini Code Assist Standard koltuğu
   (~19 $/ay); o zaman açık kaynak Gemini CLI çalışmaya devam ediyor. **Kendi PC'nden
   antigravity.google/docs/faq ve /terms sayfalarını açıp oku; bu oturumdan açılamadı.**
2. **"Claude her şeyi dağıtsın" en pahalı şekil.** Her alt görev sonucu beyne yeni mesaj olarak
   döner, iki ajan paralelde iki sayaç yakar. Varsayılan: Claude çoğu işi kendi yapar, sadece net
   tanımlı uygulama işini GPT'ye verir. Pro planda bir 5 saatlik pencere tek görevle bitebilir.
3. **"Ajanın tarayıcısını göreyim" kısmen mümkün.** Claude'un `--chrome` özelliği senin gerçek
   Chrome'unu eklentiyle sürer, bizim yansıtmamız mümkün değil. Codex CLI'ın tarayıcısı yok.
   Göreceğin şey: ofisin kendi açtığı gizli Chrome'un küçük resmi. Daha hafif ve daha güvenli.
4. **"Hafif" sadece boştayken hafif demek.** Çalışan ajanlar yüzlerce MB. Plan boş ofisi sıfıra
   çekiyor; "üçü de hep çalışsın" isteme.
5. **`claude -p` artık varsayılan olarak her izin isteyen aracı sessizce reddediyor** (v2.1.302+).
   İzin tavrını açıkça vermek şart; bunu `--permission-prompt-tool` ile balona çeviriyoruz.
6. **`codex mcp-server` kaldırıldı** (Eylül 2026). İnternetteki "Codex'i MCP olarak Claude'a bağla"
   tarifleri ölü. Bizim yol: `codex exec --json` (iş) + `app-server` (yalnızca kullanım okumak).
7. **Agent SDK kullanma.** Daha kolay görünür ama dokümanlar API anahtarı istiyor; token
   aracılığı da yasak. Sade CLI tek güvenli şekil.
8. **Devam etmek = ajanın kendi sohbetine geri dönmesi**, yarım dosya düzenlemesinin aynen
   oynatılması değil. Çökme sonrası ajan repoya yeniden bakar; birleştirme turu `git` ile
   doğrular.
9. **Bu uygulama Catudy'nin içine girmez.** `tray_manager 0.8` Flutter 3.47 istiyor, Catudy
   3.41.2'de. Ayrı repo, FVM ile ayrı Flutter.
10. **Doğrulanamayanlar** (Faz 0'da bakılacak): `/usage` ham CLI'da rapor döndürüyor mu;
    `--chrome` ile `-p` birlikte çalışıyor mu; Codex plan limit tablosu; `agy` bayrakları;
    app-server'ın "üretim için değil" ifadesi.

---

## 11. Senin karar vermen gerekenler

1. **Planların:** Claude Pro mu Max (5x/20x) mi, ChatGPT Plus mu Pro mu, Google AI Pro var mı?
   Paralellik ve bütçe eşiklerini bu belirler. *(Önerim: Max yoksa paralelliği 1'de tut.)*
2. **Gemini:** (a) elle danışman koltuğu **← önerilen**, (b) Code Assist Standard koltuğu alıp
   otomatik işçi, (c) v1'de masayı hiç koymamak.
3. **Codex adaptörü:** `codex exec --json` ile iş + app-server sadece ölçüm **← önerilen**;
   ya da her şey app-server (onay akışı daha zengin ama deneysel).
4. **Dağıtım biçimi:** Faz 1'de sabit plan-JSON, Faz 4'te MCP **← önerilen**; ya da ilk günden
   MCP (+1.5 gün).
5. **Tarayıcı izleme v1'de mi** (Node + Chrome süreçleri ekler) **yoksa Faz 5'e mi** **← önerilen**.
6. **Sprite kaynağı:** kendi düz stilinde çiz **← önerilen** (tutarlı, +1 gün) ya da CC0 piksel ofis
   paketi (lisansı kontrol et; Pixel Agents'ın kullandığı Metro City paketinin lisansı net değil).
7. **Arayüz dili:** Türkçe, İngilizce, ikisi? Beyin kuralları İngilizce kalsın **← önerilen**.

---

## 12. Kaynaklar

- Claude Code headless modu: <https://code.claude.com/docs/en/headless>
- Claude Code CLI bayrakları: <https://code.claude.com/docs/en/cli-reference>
- Claude Code stream-json olay alanları (SDK referansı): <https://code.claude.com/docs/en/agent-sdk/typescript>
- Claude Code durum satırı / kullanım alanları: <https://code.claude.com/docs/en/statusline>
- Claude Code hook'ları: <https://code.claude.com/docs/en/hooks>
- Claude Code MCP: <https://code.claude.com/docs/en/mcp>
- Claude Code yasal sayfa (abonelikle kullanım koşulları): <https://code.claude.com/docs/en/legal-and-compliance>
- Codex CLI deposu (exec, app-server, mcp-server kaldırımı): <https://github.com/openai/codex>
- Codex fiyat/limit sayfası (PC'nden aç): <https://developers.openai.com/codex/pricing>
- Codex app-server protokolü (PC'nden aç): <https://developers.openai.com/codex/app-server>
- Codex'in Claude Code eklentisi: <https://github.com/openai/codex-plugin-cc>
- Gemini CLI bireysel hesap kapanışı tartışması: <https://github.com/google-gemini/gemini-cli/discussions/27274>
- Antigravity CLI SSS ve şartlar (PC'nden aç): <https://antigravity.google/docs/faq> , <https://antigravity.google/terms>
- Chrome DevTools MCP (mevcut tarayıcıya bağlanma, izole bağlam): <https://github.com/ChromeDevTools/chrome-devtools-mcp>
- Pixel Agents (VS Code eklentisi, MIT; hook → canvas deseni): <https://github.com/pablodelucca/pixel-agents>
- Flutter Impeller Windows boyutlandırma RAM hatası: <https://github.com/flutter/flutter/issues/191050>
- Flutter paketleri: <https://pub.dev/packages/tray_manager> , <https://pub.dev/packages/launch_at_startup> , <https://pub.dev/packages/window_manager> , <https://pub.dev/packages/drift>
