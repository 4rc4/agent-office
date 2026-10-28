# Agent Office

Piksel bir ofiste çalışan AI çalışanlar: **Claude** (beyin), **Codex / GPT** (işçi),
**Gemini** (elle kullanılan danışman koltuğu). Windows masaüstü uygulaması.

- API anahtarı **yok**. Senin zaten giriş yaptığın `claude`, `codex`, `agy` programlarını
  arka planda çalıştırır, çıktılarını okur. Şifre/token dosyasına hiç dokunmaz.
- Tek istek yazarsın → Claude planlar → net işleri Codex'e verir → sonucu birleştirir → rapor.

## Bu klasör ne?

- Agent Office'in **geçici yuvası**. Catudy'nin içinde doğuyor; Faz 1 bitince **kendi
  reposuna taşınır** (`tray_manager` Flutter 3.47 istiyor, Catudy 3.41.2'de).
- Catudy koduyla hiçbir bağı yok. Kök `analysis_options.yaml` bu klasörü hariç tutar,
  Catudy CI'ı (`flutter analyze`) burayı görmez.
- Catudy kuralları (CRLF, release lock, branch düzeni) burada da geçerli; bkz. `AGENTS.md`.

## Klasörler

| Klasör | İçerik |
|---|---|
| `packages/office_core/` | Saf Dart çekirdek: görev panosu (SQLite), durum makinesi, süreç yöneticisi, Claude ve Codex adaptörleri. Flutter yok. |
| `spikes/` | Faz 0 doğrulama betikleri (PowerShell). Ham çıktılar `spikes/out/` (git dışı). |
| `brain/brain.md` | Claude beynine `--append-system-prompt-file` ile eklenen kurallar (İngilizce). |
| `docs/verified.md` | Varsayım kontrol listesi. Sonuç ve tarih sütunlarını **sen** doldurursun. |

## Hızlı başlangıç (Windows)

1. `claude` ve `codex` kurulu, giriş yapılmış olsun: `claude` içinde `/login`, terminalde
   `codex login`. `agy` isteğe bağlı.
2. **Faz 0 (deneme):**
   ```powershell
   powershell -ExecutionPolicy Bypass -File agent_office\spikes\run_all.ps1
   ```
   Özet: `agent_office\spikes\out\summary.txt`. Sonuçları `docs/verified.md`'ye işle.
3. **Faz 1 (çekirdek döngü, arayüz yok):**
   ```powershell
   cd agent_office\packages\office_core
   dart pub get
   dart run bin/office_core.dart run "<istek>" --cwd <repo>
   ```
   `bin/office_core.dart` Faz 1 ile gelir; tek istek → en az 1 Codex + 1 Claude görevi →
   birleşik rapor.
4. **Testler:** aynı klasörde `dart test`. Testler ağ ve gerçek CLI istemez
   (`FakeProcessRunner` + `test/fixtures/`).

## Değişmez kurallar

- API anahtarı yok, `claude --bare` yok, `ANTHROPIC_API_KEY` ortamdan silinir.
- `.credentials.json`, `auth.json` gibi kimlik dosyaları okunmaz; gizli kullanım adreslerine
  istek atılmaz.
- Push hiçbir zaman otomatik değil. Yıkıcı git komutları yasak.
- Gemini koltuğu v1'de elle. `agy` otomasyonu için önce
  <https://antigravity.google/docs/faq> ve `/terms` okunur; şartlar izin vermiyorsa kapalı kalır.
- Kişisel, tek kullanıcılı, yerel araç. Başkasına dağıtılmaz.

## Plan

Tam plan repo kökünde: [`docs/agent-office-plan.md`](../docs/agent-office-plan.md).
Önce bölüm 3 (mimari), 4 (bir prompt'un yolculuğu), 5 (görev panosu ve devam), sonra 9 (fazlar).
