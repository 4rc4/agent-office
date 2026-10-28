# Faz 0 deneme betikleri

Windows + PowerShell 5.1 veya 7. Her betik `out/` altına ham çıktı yazar ve ekrana
`PASS` / `FAIL` / `SKIP` / `INFO` satırları basar. Hiçbiri kimlik dosyası okumaz; sadece senin
zaten giriş yaptığın `claude`, `codex`, `agy` programlarını mutlak yoluyla çalıştırır.

## Çalıştırma

```powershell
# repo kökünden
powershell -ExecutionPolicy Bypass -File agent_office\spikes\run_all.ps1
```

- `run_all.ps1` 01-05'i sırayla çalıştırır, biri kalsa da devam eder, `out\summary.txt` yazar.
- Tek betik: `.\01_claude_stream.ps1` (nokta-kaynak **etme**, `exit` konsolu kapatır).
- Zaman aşımı: `-TimeoutSec 300` gibi parametre verebilirsin.
- Ortamda `ANTHROPIC_API_KEY` varsa 01 onu çocuk süreçlere **geçirmez** (değerini de yazmaz).

## Betikler

| Betik | Ne dener | Çıktı |
|---|---|---|
| `01_claude_stream.ps1` | `claude -p` stream-json, `apiKeySource = none`, `session_id`, `--resume`, `/usage` | `01_claude_run1.jsonl`, `01_claude_run2.jsonl`, `01_claude_usage.jsonl` |
| `02_codex_exec.ps1` | `codex login status`, geçici git reposunda `codex exec --json`, `thread_id`, `exec resume` bayrak sırası, olay tipleri | `02_codex_run1.jsonl`, `02_codex_resume_*.jsonl`, `02_codex_event_types.txt` |
| `03_agy_headless.ps1` | `agy` varsa `agy -p ... --output-format stream-json`; yoksa SKIP. SSS hatırlatması basar. | `03_agy_help.txt`, `03_agy.jsonl` |
| `04_chrome_cdp.ps1` | Gizli Chrome/Edge + `--remote-debugging-port` + ayrı `--user-data-dir`, `/json/version` | `04_chrome_version.json`, `04_chrome_targets.json` |
| `05_footprint.ps1` | Çalışan `claude`/`codex`/`agy`/`chrome`/`node` süreçlerinin RAM ve CPU'su | `05_footprint.txt`, `05_footprint.md` |
| `run_all.ps1` | Hepsini sırayla; özet | `summary.txt`, `*.log` |
| `_common.ps1` | Ortak yardımcılar (betikler nokta-kaynak eder) | - |

Sonuçları `../docs/verified.md` tablosuna işle. `out/` git dışında; JSON örneklerini saklamak
istersen `office_core/test/fixtures/` altına **kimlik ve yol bilgisi temizlenmiş** kopyasını koy.
