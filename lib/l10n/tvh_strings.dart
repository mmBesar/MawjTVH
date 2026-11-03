import 'strings.dart';

/// Strings for the Tvheadend-specific screens. Same hand-written approach as
/// [AppStrings]: English and Arabic side by side.
extension TvhStrings on AppStrings {
  // Server editor
  String get serverAddress => isArabic ? 'عنوان الخادم' : 'Server address';
  String get serverAddressHelp => isArabic
      ? 'اكتب العنوان فقط، مثل 10.0.0.5 أو tv.example.com أو https://tv.example.com. بدون منفذ نستخدم 9981.'
      : 'Type only the address, such as 10.0.0.5, tv.example.com or https://tv.example.com. Without a port, 9981 is used.';
  String get addressRequired =>
      isArabic ? 'أدخل عنوان الخادم.' : 'Enter the server address.';
  String get username => isArabic ? 'اسم المستخدم' : 'Username';
  String get password => isArabic ? 'كلمة المرور' : 'Password';
  String get usernameHelp => isArabic
      ? 'الخادم هو من يحدد ما يسمح به هذا الحساب. المسؤول يرى كل شيء، والمستخدم العادي يرى ما يُسمح له.'
      : 'The server decides what this account may do. Admins see everything; normal users get what their account allows.';
  String get streamProfile => isArabic ? 'ملف البث' : 'Stream profile';
  String get streamProfileHelp => isArabic
      ? 'اتركه فارغًا للبث الأصلي (pass). اختر ملف تحويل إن كانت الشبكة بطيئة.'
      : 'Leave empty for the original stream (pass). Pick a transcoding profile on a slow network.';
  String get useHtsp => isArabic ? 'بروتوكول HTSP الأصلي' : 'Native HTSP protocol';
  String get useHtspHelp => isArabic
      ? 'تحديثات فورية للقنوات والدليل والتسجيلات دون استعلام متكرر. يتطلب فتح منفذ HTSP على الخادم وصلاحية HTSP للحساب.'
      : 'Live updates of channels, guide and recordings with no polling. Needs the server\'s HTSP port open and HTSP access on the account.';
  String get visualsAndPerformance => isArabic ? 'المظهر والأداء' : 'Visuals & performance';
  String get richVisuals => isArabic ? 'صور البرامج على البطاقات' : 'Programme artwork on cards';
  String get richVisualsHelp => isArabic
      ? 'يعرض صور البرامج من الدليل كخلفيات. أوقفه لتحميل صور أقل وأداء أخف.'
      : 'Shows guide artwork as card backgrounds. Turn off to load fewer images and run lighter.';
  String get reduceMotion => isArabic ? 'تقليل الحركة' : 'Reduce motion';
  String get reduceMotionHelp => isArabic
      ? 'يوقف الحركات الزخرفية مثل موجة التقدم المتحركة.'
      : 'Stops decorative animation such as the moving progress wave.';
  String get htspStream => isArabic ? 'البث المباشر عبر HTSP' : 'Watch live TV over HTSP';
  String get htspStreamHelp => isArabic
      ? 'يعيد الاشتراك تلقائيًا عند ضعف الإشارة فيعود البث دون إغلاق المشغّل. أوقفه لاستخدام بث HTTP العادي.'
      : 'Re-subscribes by itself when the signal drops, so playback resumes instead of ending. Turn off to use the plain HTTP stream.';
  String get htspPort => isArabic ? 'منفذ HTSP' : 'HTSP port';
  String get serverNameHint => isArabic ? 'خادم المنزل' : 'Home server';
  String get showPassword => isArabic ? 'إظهار كلمة المرور' : 'Show password';
  String get hidePassword => isArabic ? 'إخفاء كلمة المرور' : 'Hide password';
  String get adminAccount => isArabic ? 'حساب مسؤول' : 'Admin account';
  String get userAccount => isArabic ? 'حساب مستخدم' : 'User account';
  String connectedSummary({
    required String server,
    required int channels,
    required int programmes,
    required bool admin,
  }) {
    final role = admin ? adminAccount : userAccount;
    return isArabic
        ? 'تم الاتصال بـ $server · $channels قناة · $programmes برنامج · $role'
        : 'Connected to $server · $channels channels · $programmes programmes · $role';
  }

  // Recordings
  String get recordings => isArabic ? 'التسجيلات' : 'Recordings';
  String get recordingsUpcoming => isArabic ? 'القادمة' : 'Upcoming';
  String get recordingsFinished => isArabic ? 'المسجّلة' : 'Recorded';
  String get recordingsFailed => isArabic ? 'الفاشلة' : 'Failed';
  String get noRecordings =>
      isArabic ? 'لا توجد تسجيلات هنا.' : 'No recordings here.';
  String get recordingsForbidden => isArabic
      ? 'هذا الحساب غير مسموح له بالتسجيل على الخادم.'
      : 'This account is not allowed to record on the server.';
  String get record => isArabic ? 'تسجيل' : 'Record';
  String get recordSeries => isArabic ? 'تسجيل كل الحلقات' : 'Record series';
  String get recordNow => isArabic ? 'سجّل الآن' : 'Record now';
  String recordNowFor(int minutes) =>
      isArabic ? 'سجّل لمدة $minutes دقيقة' : 'Record for $minutes min';
  String get recordingScheduled =>
      isArabic ? 'تمت جدولة التسجيل.' : 'Recording scheduled.';
  String get recordingStarted =>
      isArabic ? 'بدأ التسجيل.' : 'Recording started.';
  String get stopRecording => isArabic ? 'إيقاف التسجيل' : 'Stop recording';
  String get cancelRecording => isArabic ? 'إلغاء التسجيل' : 'Cancel recording';
  String get deleteRecording => isArabic ? 'حذف التسجيل' : 'Delete recording';
  String get playRecording => isArabic ? 'تشغيل التسجيل' : 'Play recording';
  String get recordingNow => isArabic ? 'يسجّل الآن' : 'Recording now';
  String get scheduled => isArabic ? 'مجدول' : 'Scheduled';
  String get confirmDeleteRecording => isArabic
      ? 'سيُحذف الملف من الخادم نهائيًا. متابعة؟'
      : 'The file is deleted from the server for good. Continue?';
  String get confirm => isArabic ? 'تأكيد' : 'Confirm';
  String get recordingProblems => isArabic ? 'أخطاء' : 'Errors';

  // Signal
  String get signal => isArabic ? 'الإشارة' : 'Signal';
  String get signalSnr => 'SNR';
  String get signalStrength => 'SS';
  String get signalNeedsAdmin => isArabic
      ? 'أرقام الإشارة تحتاج حساب مسؤول على الخادم.'
      : 'Signal numbers need an admin account on the server.';

  // Server page
  String get server => isArabic ? 'الخادم' : 'Server';
  String get serverStatus => isArabic ? 'حالة الخادم' : 'Server status';
  String get tuners => isArabic ? 'المحاضر' : 'Tuners';
  String get activeStreams => isArabic ? 'البث الجاري' : 'Active streams';
  String get connectionsLabel => isArabic ? 'الاتصالات' : 'Connections';
  String get nothingActive => isArabic ? 'لا شيء جارٍ الآن.' : 'Nothing active right now.';
  String get adminOnly => isArabic
      ? 'هذه الشاشة للمسؤولين فقط.'
      : 'This screen is for admins only.';
  String get version => isArabic ? 'الإصدار' : 'Version';

  // Local recording
  /// A readable reason for the server's stream error [text]
  /// (`No free adapter`, `Too weak signal`...).
  String streamIssue(String text) {
    final code = text.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
    bool has(String part) => code.contains(part);
    if (has('freeadapter') || has('noadapter') || has('busy')) {
      return isArabic
          ? 'كل الموالفات مشغولة. أوقف بثًا أو تسجيلًا آخر ثم جرّب.'
          : 'All tuners are busy. Stop another stream or recording and try again.';
    }
    if (has('weak') || has('badsignal')) {
      return isArabic ? 'الإشارة ضعيفة جدًا.' : 'The signal is too weak.';
    }
    if (has('descrambl') || has('scrambl')) {
      return isArabic
          ? 'القناة مشفّرة ولا يمكن فكها على هذا الخادم.'
          : 'This channel is encrypted and cannot be decoded.';
    }
    if (has('override')) {
      return isArabic
          ? 'استولى مشاهد بأولوية أعلى على الموالف.'
          : 'A viewer with higher priority took the tuner.';
    }
    if (has('noaccess') || has('access')) {
      return isArabic
          ? 'هذا الحساب غير مسموح له بمشاهدة هذه القناة.'
          : 'This account may not watch this channel.';
    }
    if (has('tuningfailed') || has('noinput')) {
      return isArabic
          ? 'تعذّر على الموالف تثبيت هذه القناة.'
          : 'The tuner could not lock this channel.';
    }
    if (has('limit') || has('toomany')) {
      return isArabic
          ? 'بلغ الحساب حدّ الاتصالات المسموح.'
          : 'This account reached its connection limit.';
    }
    return text;
  }

  String get infoVideo => isArabic ? 'الفيديو' : 'Video';
  String get infoAudio => isArabic ? 'الصوت' : 'Audio';
  String get infoDecoder => isArabic ? 'فك الترميز' : 'Decoder';
  String get infoDropped => isArabic ? 'إطارات مفقودة' : 'Dropped';
  String get audioAndSubtitles => isArabic ? 'الصوت والترجمة' : 'Audio & subtitles';
  String get preferredAudio => isArabic ? 'لغة الصوت المفضلة' : 'Preferred audio language';
  String get preferredSubtitle =>
      isArabic ? 'لغة الترجمة المفضلة' : 'Preferred subtitle language';
  String get streamDefault => isArabic ? 'افتراضي البث' : 'Stream default';
  String get subtitlesOffByDefault =>
      isArabic ? 'بدون ترجمة (افتراضي)' : 'Off by default';
  String get rememberTracks =>
      isArabic ? 'تذكّر المسارات لكل قناة' : 'Remember tracks per channel';
  String get rememberTracksHelp => isArabic
      ? 'يستعيد آخر صوت وترجمة اخترتهما على كل قناة.'
      : 'Brings back the audio and subtitle you last picked on each channel.';
  String get zapBanner => isArabic ? 'شريط القناة عند الفتح' : 'Channel banner on open';
  String get zapBannerHelp => isArabic
      ? 'يعرض شريطًا بمعلومات القناة والبرنامج عند فتح قناة (سطح المكتب). اضغط I لإظهاره أو إخفائه.'
      : 'Shows a banner with the channel and programme when one opens (desktop). Press I to pin or hide it.';
  String get muted => isArabic ? 'كتم الصوت' : 'Muted';
  String get audioLabel => isArabic ? 'الصوت' : 'Audio';
  String get subtitleLabel => isArabic ? 'الترجمة' : 'Subtitles';
  String get streamInfo => isArabic ? 'معلومات البث' : 'Stream info';
  String get inAppRenderer => isArabic ? 'عرض الفيديو داخل التطبيق' : 'In-app video rendering';
  String get rendererAuto => isArabic ? 'تلقائي (GPU)' : 'Automatic (GPU)';
  String get rendererGpu => isArabic ? 'GPU (الأسلس)' : 'GPU (smoothest)';
  String get rendererCpu => isArabic ? 'CPU (الأكثر أمانًا)' : 'CPU (safest)';
  String get inAppRendererHelp => isArabic
      ? 'إن تجمّدت النافذة أثناء التشغيل اختر CPU. يُطبَّق عند فتح القناة التالية.'
      : 'If the window freezes while playing, choose CPU. Applies the next time you open a channel.';
  String get audioTracks => isArabic ? 'المسارات الصوتية' : 'Audio';
  String get subtitleTracks => isArabic ? 'الترجمة' : 'Subtitles';
  String get subtitlesOff => isArabic ? 'بدون ترجمة' : 'Off';
  String get noTracks => isArabic ? 'لا توجد مسارات في هذا البث.' : 'This stream has none.';
  String trackNumber(int n) => isArabic ? 'مسار $n' : 'Track $n';
  String get audioAndSubtitles => isArabic ? 'الصوت والترجمة' : 'Audio & subtitles';
  String get tracksHelp => isArabic
      ? 'تظهر الأسماء من لغة المسار في البث. ترجمة DVB تُعرض بينما ترجمة التلتكست غير مدعومة بعد.'
      : 'Names come from the language each track declares. DVB subtitles are shown; teletext subtitles are not supported yet.';
  String get allKinds => isArabic ? 'الكل' : 'All';
  String get tvKind => isArabic ? 'تلفزيون' : 'TV';
  String get radioKind => isArabic ? 'راديو' : 'Radio';
  String get abortRecording => isArabic ? 'إجهاض التسجيل' : 'Abort recording';
  String recordCurrentProgramme(String title) => isArabic
      ? 'تسجيل البرنامج الحالي: $title'
      : 'Record current programme: $title';
  String get recordOnServer => isArabic ? 'تسجيل على الخادم' : 'Record on server';
  String get recordOnDevice => isArabic ? 'تسجيل على هذا الجهاز' : 'Record to this device';
  String get stopLocalRecording =>
      isArabic ? 'إيقاف التسجيل على الجهاز' : 'Stop recording to device';
  String get localTab => isArabic ? 'على الجهاز' : 'On device';
  String localRecordingStarted(String path) =>
      isArabic ? 'يُسجَّل في: $path' : 'Recording to: $path';
  String localRecordingSaved(String path) =>
      isArabic ? 'تم الحفظ: $path' : 'Saved: $path';
  String get noLocalRecordings => isArabic
      ? 'لا توجد تسجيلات على هذا الجهاز بعد. اضغط زر الحفظ أثناء المشاهدة.'
      : 'Nothing recorded on this device yet. Press the save button while watching.';
  String get recordFolder => isArabic ? 'مجلد التسجيل' : 'Recording folder';
  String get recordFolderHelp => isArabic
      ? 'يُحفظ هنا ما تسجّله على هذا الجهاز. اتركه فارغًا للمجلد الافتراضي.'
      : 'Recordings made on this device are saved here. Leave empty for the default folder.';
  String get chooseFolder => isArabic ? 'اختيار مجلد' : 'Choose folder';
  String get defaultFolder => isArabic ? 'المجلد الافتراضي' : 'Default folder';
  String get resetToDefault => isArabic ? 'العودة للافتراضي' : 'Reset to default';
  String get deleteFile => isArabic ? 'حذف الملف' : 'Delete file';
  String get confirmDeleteFile => isArabic
      ? 'سيُحذف الملف من هذا الجهاز نهائيًا. متابعة؟'
      : 'The file is deleted from this device for good. Continue?';

  // Recordings page
  String get groupBy => isArabic ? 'تجميع' : 'Group by';
  String get groupNone => isArabic ? 'بدون' : 'None';
  String get groupChannel => isArabic ? 'القناة' : 'Channel';
  String get groupSeries => isArabic ? 'المسلسل / البرنامج' : 'Series';
  String get groupDay => isArabic ? 'اليوم' : 'Day';
  String get allChannelsFilter => isArabic ? 'كل القنوات' : 'All channels';
  String get filterRecordings => isArabic ? 'تصفية التسجيلات' : 'Filter recordings';
  String get searchTooltip => isArabic ? 'بحث' : 'Search';
  String get searchChannelsTitle => isArabic ? 'بحث في القنوات' : 'Search channels';
  String get searchGuideTitle => isArabic ? 'بحث في الدليل' : 'Search the guide';
  String get allGroupsGuide => isArabic ? 'الكل' : 'All';
}
