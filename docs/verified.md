# Faz 0 doğrulama listesi

Planın (`docs/agent-office-plan.md`, bölüm 9 ve 10) dayandığı varsayımlar. Her satırı
gerçek Windows PC'de doğrula, **Sonuç** ve **Tarih** sütunlarını doldur. Betikler:
`agent_office/spikes/run_all.ps1`; ham çıktılar `agent_office/spikes/out/`.

Sonuç sütununa `geçti`, `kaldı` veya `kısmen` + bir cümle yaz. Kaldıysa planın ilgili
bölümünü de güncelle; varsayım değişirse kod da değişir.

| # | Varsayım | Nasıl doğrulanır | Sonuç | Tarih |
|---|---|---|---|---|
| 1 | `claude -p "<istek>" --output-format stream-json --verbose` şu olayları basar: `system/init`, `assistant`, (`stream_event` sadece `--include-partial-messages` ile), `result`. Alanlar `office_core/test/fixtures/claude_pong.jsonl` ile uyuşur. | `01_claude_stream.ps1`; `out/01_claude_run1.jsonl` ile fixture'ı yan yana koy, alan adlarını karşılaştır (`session_id`, `result`, `is_error`, `usage`, `modelUsage`). | | |
| 2 | Abonelikle giriş yapılmışken `system/init` içinde `apiKeySource` değeri `none`. Ofis bunu görmezse çalışmayı reddeder. | `01_claude_stream.ps1` → `PASS init apiKeySource = none`. Ek: `$env:ANTHROPIC_API_KEY` tanımlıyken değerin ne olduğuna da bak (betik anahtarı çocuğa geçirmez). | | |
| 3 | `claude -p --resume <session_id> "<istek>"` aynı sohbeti sürdürür ve aynı `session_id`'yi korur (`--fork-session` yoksa). | `01_claude_stream.ps1` → `PASS resume kept session id`; `out/01_claude_run2.jsonl`. | | |
| 4 | `-p` modunda `/usage` komutu okunabilir bir kullanım raporu döndürür (5 saatlik ve haftalık yüzde). Döndürmezse duvar göstergeleri için başka kaynak lazım (`/status`, durum satırı alanları). | `01_claude_stream.ps1` → `/usage` satırı; `out/01_claude_usage.jsonl` içindeki `result` metnini oku. | | |
| 5 | `codex exec --json` olayları: `thread.started` (`thread_id`), `turn.started`, `item.started/updated/completed` (`item.type`: `agent_message`, `command_execution`, `file_change`, ...), `turn.completed` (`usage`). | `02_codex_exec.ps1`; `out/02_codex_run1.jsonl` ve `out/02_codex_event_types.txt`. | | |
| 6 | Devam için bayrak sırası: `codex exec resume <thread_id> --json "<istek>"` mi, `codex exec --json resume <thread_id> "<istek>"` mi? Çalışan sırayı adaptöre sabitle. | `02_codex_exec.ps1` iki sırayı da dener, hangisinin çalıştığını `PASS resume works with: ...` satırında yazar. | | |
| 7 | `codex app-server` kullanım yüzdelerini verir: JSON-RPC `initialize` sonrası `account/rateLimits/read` cevabı 5 saatlik ve haftalık pencereleri içerir; `account/rateLimits/updated` bildirimi gelir. Protokol deneysel. | **Elle.** Terminalde `codex app-server --listen stdio://` aç; önce `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"agent-office-spike","version":"0.0.1"}}}` yapıştır, sonra `{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}`. Metot adlarını <https://developers.openai.com/codex/app-server> ile karşılaştır; cevabı `spikes/out/07_app_server.txt` dosyasına kaydet (token içermez, ama yine de göz at). | | |
| 8 | `agy` (Antigravity CLI) başsız çalışır: `agy -p "<istek>" --output-format stream-json` JSONL basar. SSS/şartlar "üçüncü parti ajan içinde sarmalamak desteklenmez" diyor; cümlenin tam hali ve yaptırım (uyarı → kalıcı kapatma) not edilir. | `03_agy_headless.ps1` (`out/03_agy_help.txt`, `out/03_agy.jsonl`). Ardından **kendi PC'nden** <https://antigravity.google/docs/faq> ve <https://antigravity.google/terms> oku; ilgili cümleyi buraya aynen yaz. Git/gitme kararı: plan bölüm 11, madde 2. | | |
| 9 | Chrome 136+ `--remote-debugging-port` bayrağını yalnızca varsayılan olmayan `--user-data-dir` ile kabul eder. `%LOCALAPPDATA%\AgentOffice\chrome-spike` profiliyle `/json/version` cevap verir ve `webSocketDebuggerUrl` döner. | `04_chrome_cdp.ps1` → `PASS webSocketDebuggerUrl`; `out/04_chrome_version.json`. Ek kontrol: aynı komutu `--user-data-dir` olmadan elle çalıştır, portun açılmadığını gör. | | |
| 10 | Ofis uygulaması boşta 10 dakika sonra **≤120 MB RAM, %0 CPU** (beyin süreci kapalı, animasyon zamanlayıcısı durmuş). | Faz 2 sonrası: uygulamayı aç, 10 dk bekle, `05_footprint.ps1` çalıştır (`out/05_footprint.md`) ve Görev Yöneticisi ile karşılaştır. Çalışırken de bir kez ölç: `claude.exe`, `codex.exe`, Chrome tablosu plan bölüm 7'ye girer. | | |
| 11 | Flutter 3.47 stable + `tray_manager` 0.8 Windows'ta kurulur ve derlenir; Catudy'nin 3.41.2'siyle çakışmaz (FVM). | **Elle.** `fvm install 3.47.x`, boş bir klasörde `fvm flutter create --platforms=windows tray_probe`, `pubspec.yaml`'a `tray_manager: ^0.8.0`, `window_manager`, `launch_at_startup`, `windows_single_instance` ekle, `fvm flutter build windows`. Sürümleri buraya yaz. | | |

## Ek (zorunlu değil, Faz 1'i rahatlatır)

| # | Varsayım | Nasıl doğrulanır | Sonuç | Tarih |
|---|---|---|---|---|
| E1 | `claude -p --input-format stream-json --output-format stream-json` ile tek uzun ömürlü süreç stdin'den ardışık `user` mesajları alır; her turun sonunda bir `result` olayı gelir. | Elle: `claude -p --input-format stream-json --output-format stream-json --verbose` aç, `{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Reply with exactly: pong"}]}}` yapıştır, `result` bekle, ikinci mesajı gönder. | | |
| E2 | `--permission-prompt-tool mcp__office__approve` `-p` modunda çalışır; `--permission-mode` verilmezse izin isteyen araçlar sessizce reddedilir (v2.1.302+). | Faz 4'te ofis MCP sunucusuyla; şimdilik `claude --help` çıktısında iki bayrağın da varlığını not et. | | |
| E3 | `result` olayı `usage` ve `modelUsage` alanları taşır; ofis bunları maliyet değil **aktivite** göstergesi olarak kullanır (abonelikte dolar anlamsız). | `out/01_claude_run1.jsonl` son satır. | | |
| E4 | `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1` ile `--resume` yarıda kalan turu sürdürür. | Elle: uzun bir `-p` isteği başlat, Görev Yöneticisi'nden öldür, değişkenle `--resume` et, devam ettiğini gör. | | |
