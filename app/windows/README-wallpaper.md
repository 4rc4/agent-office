# Agent Office on the desktop (Windows runner)

## Build and run
- `flutter run -d windows` from `app/` (or `flutter build windows` and run `build/windows/x64/runner/Release/agent_office_app.exe`). No flags = wallpaper mode: a borderless, colour-keyed, full-screen window parked behind the desktop icons. `--window` shows the same stage in a plain dark window (no WorkerW trick, handy for testing); `--fake` replays canned vendor output instead of launching `claude`/`codex`.
- Not compiled on the machine that wrote this (Linux, no MSVC). If the build complains, the likely spots are `runner/desktop_layer.cpp` (Win32 calls under /W4 /WX) and the `MethodChannel` lambda in `runner/flutter_window.cpp`.

## How it works
- WorkerW trick (`runner/desktop_layer.cpp`): `FindWindow("Progman")` gets `0x052C`, which makes the shell spawn a WorkerW behind `SHELLDLL_DefView` (on 24H2 a child of Progman, earlier the sibling right after it); the window is `SetParent`ed under it, so the icons draw over it and the wallpaper shows wherever Flutter paints `DesktopStage.keyColor` (RGB 1,2,3, `LWA_COLORKEY`; DWM alpha does not reach a child of WorkerW).
- A window down there gets no mouse input, so a 40 ms timer polls the cursor: inside a hit rect Dart reported (stations, characters, an open bubble) and with only the desktop under the cursor, the window is raised to a topmost top-level window; it goes back when the cursor leaves unless Dart pinned it (`bringToFront`, bubble open). While raised it is `WS_EX_TRANSPARENT` outside the rects and `WM_NCHITTEST` answers `HTTRANSPARENT` there.
- Channel `agent_office/desktop` (`lib/desktop/desktop_layer.dart`): `enterWallpaperMode`, `bringToFront`, `sendToBack`, `setHitRects`, `screenSize`, `quit`; the runner calls back `focusLost` when another process took the foreground while a bubble was open.

## Using it
- Claude and GPT stand on a floor line 120 px above the bottom; the whiteboard, two desks, the coffee machine and the mailbox stand along it. Drag a station to move it (positions are saved).
- Click an idle character: the prompt bubble. Claude plans and delegates (office task); GPT takes the prompt directly. "Klasör" picks the folder, the chips are the last five. Enter sends, Shift+Enter is a newline, Esc closes. Several tasks can run at once, each in its own folder; a desk that is taken makes the next task wait.
- Click a working character: its status (task, last message, tokens) and "Durdur" (stops the whole office). Click the whiteboard: the tasks grouped by root with the folder. Click the mailbox (flag up = unread): the reports, newest first, with "Kopyala".
- Tray icon: "Duraklat"/"Devam" holds new prompts (running work continues), "Ayarlar" opens the settings sheet (claude/codex paths with "Bul", permission mode, fake mode, "Windows ile başlat"), "Çıkış" stops the agents and exits. Esc also quits while the layer has keyboard focus and no bubble is open.
- Settings live in `settings.json` under the app support folder (`%APPDATA%\\<org>\\agent_office_app`, see `OfficeSettings.settingsDirectory`): executables, permission mode, fake mode, station positions, recent folders. Executables and fake mode apply on the next start. Autostart is a `Run` entry under HKCU (launch_at_startup).
- On start the runtime resumes interrupted work (`Supervisor.reconcile`); the board is `<folder>/.agent_office/office.db` per working folder.

## Icons
- `tool/make_icon.py` (Pillow) draws Claude's beanie head into `assets/icons/tray_icon.ico` (tray, loaded as a Flutter asset) and `runner/resources/app_icon.ico` (exe/window). Rerun it only when the sprite changes.

## If something is off
- Character invisible: check the console for "behind the desktop icons" vs "no WorkerW"; on 24H2 the Progman child WorkerW may need `SetWindowPos(workerw, HWND_BOTTOM, …)` under `SHELLDLL_DefView`.
- Only the primary monitor is covered (`SM_CXSCREEN`/`SM_CYSCREEN`).
- The folder/file pickers (`file_selector_windows`) open owned by the raised layer, so only while a bubble is open.
- Dependencies pinned by the SDK (Flutter 3.41.2): `tray_manager 0.5.3`, `launch_at_startup 0.5.1`, `file_selector 1.1.0`.
