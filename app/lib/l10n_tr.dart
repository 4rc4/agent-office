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
  static const String askGpt = 'GPT ne yapsın?';
  static const String desktopPromptHint = 'Bir iş yaz… (Enter gönderir)';
  static const String noFolder = 'Klasör seçilmedi';
  static const String chooseFolder = 'Klasörü seç';
  static const String sentLabel = 'Gönderildi';
  static const String recentFolders = 'Son klasörler';
  static const String noSummary = 'Henüz bir şey demedi.';
  static const String reportFailed = 'Başarısız';
  static const String olderReports = 'Önceki raporlar';
  static const String reportFrom = 'Rapor';
  static const String tv = 'Televizyon';
  static const String taskDetails = 'Görev';
  static const String steer = 'Yönlendir';
  static const String steerHint = 'Yeni talimat… (oturum devam eder)';
  static const String steerGptHint = 'Yeni talimat… (GPT baştan alır)';
  static const String contextLabel = 'Bağlam';
  static const String back = 'Tahta';
  static const String usageLimits = 'Kullanım limitleri';
  static const String noUsage =
      'Henüz limit bilgisi yok; Claude çalışınca gelir.';
  static const String tokensOnly = 'jeton';
  static const String model = 'Model';
  static const String effort = 'Düşünme';
  static const String defaultChoice = 'Varsayılan';
  static const String files = 'Dosya';
  static const String attachedFiles = 'Ekli dosyalar (yoluyla oku)';
  static const String claudeModel = 'Claude modeli';
  static const String claudeEffort = 'Claude düşünme';
  static const String codexModel = 'Codex modeli';
  static const String codexEffort = 'Codex düşünme';

  /// Display name of a rate-limit window the CLI reports.
  static String windowLabel(String window) => switch (window) {
    'five_hour' => '5 saat',
    'seven_day' => 'haftalık',
    _ => window,
  };

  /// "14:30'da sıfırlanır", with the date when it is not today.
  static String resetsAt(DateTime at, {DateTime? now}) {
    final local = at.toLocal();
    final today = (now ?? DateTime.now()).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${two(local.hour)}:${two(local.minute)}';
    final sameDay =
        local.year == today.year &&
        local.month == today.month &&
        local.day == today.day;
    final day = sameDay ? '' : '${two(local.day)}.${two(local.month)} ';
    return "$day$time'da sıfırlanır";
  }

  /// Display name of an effort level; unknown levels show as they are.
  static String effortLabel(String effort) => switch (effort) {
    '' => defaultChoice,
    'low' => 'düşük',
    'medium' => 'orta',
    'high' => 'yüksek',
    'max' => 'azami',
    _ => effort,
  };

  /// Display name of a model choice; empty is the CLI default.
  static String modelLabel(String model) =>
      model.isEmpty ? defaultChoice : model;

  // --- tray and settings --------------------------------------------------
  static const String pause = 'Duraklat';
  static const String resume = 'Devam';
  static const String settings = 'Ayarlar';
  static const String quit = 'Çıkış';
  static const String officePaused = 'Ofis duraklatıldı';
  static const String claudeExecutable = 'claude programı';
  static const String codexExecutable = 'codex programı';
  static const String find = 'Bul';
  static const String permissionMode = 'İzin modu';
  static const String fakeMode = 'Sahte mod (sahte çıktı)';
  static const String startWithWindows = 'Windows ile başlat';
  static const String save = 'Kaydet';
  static const String settingsRestartNote =
      'Program ve sahte mod ayarları yeniden başlatınca geçerli olur.';

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
