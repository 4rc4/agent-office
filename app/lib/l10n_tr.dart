import 'package:office_core/office_core.dart';

import 'state/seat_state.dart';

/// Every user-facing Turkish string of the window, in one place.
///
/// Keep entries short and plain; code and comments stay English. Widgets
/// never embed literal Turkish text, they read it from here.
abstract final class Tr {
  // --- window -------------------------------------------------------------
  static const String appTitle = 'Agent Office';
  static const String send = 'Gönder';
  static const String stop = 'Durdur';
  static const String close = 'Kapat';
  static const String copy = 'Kopyala';
  static const String copied = 'Kopyalandı';
  static const String folder = 'Klasör';
  static const String folderHint = 'Çalışma klasörü';
  static const String promptHint =
      'Ne yapılsın? (Enter gönderir, Shift+Enter yeni satır)';
  static const String mode = 'Mod';
  static const String working = 'Çalışıyor…';
  static const String officeQuiet = 'Ofis sakin.';
  static const String busyRefused = 'Ofis meşgul: önce açık görev bitsin.';
  static const String submitFailed = 'Gönderilemedi';
  static const String startupFailed = 'Ofis başlatılamadı';
  static const String startupHint =
      'Ayarları veya komut satırını düzeltip pencereyi yeniden açın.';

  // --- desktop layer ------------------------------------------------------
  static const String whatShallWeDo = 'Ne yapalım?';
  static const String desktopPromptHint = 'Bir iş yaz… (Enter gönderir)';
  static const String noFolder = 'Klasör seçilmedi';
  static const String chooseFolder = 'Klasörü seç';
  static const String sentLabel = 'Gönderildi';

  // --- prompt modes -------------------------------------------------------
  static const String modeOffice = 'Ofis (Claude planlar)';
  static const String modeClaudeOnly = 'Sadece Claude';
  static const String modeGptOnly = 'Sadece GPT';

  // --- panels -------------------------------------------------------------
  static const String whiteboard = 'Beyaz tahta';
  static const String mailbox = 'Posta kutusu';
  static const String events = 'Olaylar';
  static const String noEvents = 'Henüz olay yok.';
  static const String noTasks = 'Tahta boş.';
  static const String noReport =
      'Posta kutusu boş. Bir görev bitince rapor burada görünür.';
  static const String seatDetails = 'Masa';
  static const String state = 'Durum';
  static const String currentTask = 'Görev';
  static const String noTask = 'Görev yok';
  static const String session = 'Oturum';
  static const String noSession = 'Oturum yok';
  static const String tokens = 'Jeton';
  static const String tokensIn = 'giren';
  static const String tokensOut = 'çıkan';
  static const String xp = 'XP';
  static const String lastEvents = 'Son olaylar';
  static const String attempt = 'Deneme';
  static const String unassigned = 'Atanmadı';

  // --- seats --------------------------------------------------------------
  /// Display name of a desk.
  static String seatName(Seat seat) => switch (seat) {
    Seat.claude => 'Claude',
    Seat.gpt => 'GPT',
    Seat.gemini => 'Gemini',
  };

  /// What the desk's occupant is doing, as the panel says it.
  static String visualLabel(SeatVisual visual) => switch (visual) {
    SeatVisual.empty => 'Boş masa',
    SeatVisual.idle => 'Boşta',
    SeatVisual.sleeping => 'Uyuyor',
    SeatVisual.arriving => 'Geliyor',
    SeatVisual.thinking => 'Düşünüyor',
    SeatVisual.typing => 'Yazıyor',
    SeatVisual.reading => 'Okuyor',
    SeatVisual.editing => 'Düzenliyor',
    SeatVisual.shell => 'Komut çalıştırıyor',
    SeatVisual.browsing => 'Geziniyor',
    SeatVisual.waitingUser => 'Onay bekliyor',
    SeatVisual.onBreak => 'Molada',
    SeatVisual.celebrating => 'Bitirdi',
    SeatVisual.failed => 'Hata',
  };

  // --- tasks --------------------------------------------------------------
  /// Whiteboard group heading for a task status.
  static String statusLabel(TaskStatus status) => switch (status) {
    TaskStatus.queued => 'Sırada',
    TaskStatus.planned => 'Planlandı',
    TaskStatus.assigned => 'Atandı',
    TaskStatus.running => 'Çalışıyor',
    TaskStatus.waitingApproval => 'Onay bekliyor',
    TaskStatus.waitingUser => 'Soru bekliyor',
    TaskStatus.waitingBudget => 'Bütçe bekliyor',
    TaskStatus.review => 'İncelemede',
    TaskStatus.interrupted => 'Yarıda kaldı',
    TaskStatus.done => 'Bitti',
    TaskStatus.failed => 'Başarısız',
    TaskStatus.needsHuman => 'İnsan gerekli',
  };

  // --- events -------------------------------------------------------------
  /// Short label for an event kind in the log lists.
  static String eventKindLabel(AgentEventKind kind) => switch (kind) {
    AgentEventKind.sessionStarted => 'oturum',
    AgentEventKind.textDelta => 'metin',
    AgentEventKind.thinking => 'düşünce',
    AgentEventKind.toolStarted => 'araç',
    AgentEventKind.toolFinished => 'araç bitti',
    AgentEventKind.fileChanged => 'dosya',
    AgentEventKind.approvalRequested => 'onay',
    AgentEventKind.userQuestion => 'soru',
    AgentEventKind.turnCompleted => 'tur bitti',
    AgentEventKind.turnFailed => 'tur hatası',
    AgentEventKind.rateLimit => 'limit',
    AgentEventKind.compacting => 'özetleme',
    AgentEventKind.subagentStarted => 'yardımcı',
    AgentEventKind.subagentStopped => 'yardımcı bitti',
    AgentEventKind.processExited => 'süreç bitti',
    AgentEventKind.unknown => 'bilinmeyen',
  };
}
