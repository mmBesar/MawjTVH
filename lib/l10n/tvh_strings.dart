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
  String get stbChannels => isArabic ? 'القنوات' : 'Channels';
  String get stbAll => isArabic ? 'الكل' : 'All';
  String get stbFavorites => isArabic ? 'المفضلة' : 'Favourites';
  String get stbSearch => isArabic ? 'اكتب للبحث بالاسم أو الرقم' : 'Type to search by name or number';
  String get stbNoMatch => isArabic ? 'لا توجد قنوات مطابقة' : 'No matching channels';
  String get stbBrowserHint => isArabic
      ? '↑↓ اختيار · Enter مشاهدة · ←→ تغيير المجموعة · اكتب للبحث · Esc إغلاق'
      : '↑↓ select · Enter watch · ←→ change tag · type to search · Esc close';
  String get stbHelpTitle => isArabic ? 'اختصارات لوحة المفاتيح' : 'Keyboard shortcuts';
  String get channelListTooltip => isArabic ? 'قائمة القنوات (C)' : 'Channel list (C)';
  String get helpTooltip => isArabic ? 'الاختصارات (H)' : 'Shortcuts (H)';
  String get infoTooltip => isArabic ? 'معلومات القناة (I)' : 'Channel info (I)';
  String get aspectTooltip => isArabic ? 'نسبة العرض (Z)' : 'Aspect ratio (Z)';
  String get channelWord => isArabic ? 'القناة' : 'Channel';
  String noChannelNumber(String number) =>
      isArabic ? 'لا توجد قناة برقم $number' : 'No channel $number';
  String get aspectLabel => isArabic ? 'نسبة العرض' : 'Aspect ratio';
  String aspectName(int mode) {
    switch (mode) {
      case 1:
        return '16:9';
      case 2:
        return '4:3';
      case 3:
        return '21:9';
      case 4:
        return isArabic ? 'تكبير لملء الشاشة' : 'Zoom to fill';
      default:
        return isArabic ? 'تلقائي' : 'Auto';
    }
  }

  String get deinterlaceLabel => isArabic ? 'إزالة التداخل' : 'Deinterlace';
  String get onWord => isArabic ? 'تشغيل' : 'On';
  String get offWord => isArabic ? 'إيقاف' : 'Off';
  String get audioDelayLabel => isArabic ? 'تأخير الصوت' : 'Audio delay';
  String get recordingsInMpv =>
      isArabic ? 'تشغيل التسجيلات في mpv' : 'Play recordings in mpv';
  String get recordingsInMpvBody => isArabic
      ? 'تُفتح التسجيلات في نافذة mpv عند توفره بدل المشغّل المدمج.'
      : 'Recordings open in the mpv window when it is installed, instead of the built-in player.';
  String resumeFrom(String time) =>
      isArabic ? 'المتابعة من $time' : 'Continue from $time';
  String get resumeAction => isArabic ? 'متابعة' : 'Resume';
  String get startOver => isArabic ? 'من البداية' : 'Start over';
  /// Short label of a guide day chip: "Wed 11".
  String guideDayChip(DateTime day) {
    const en = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const ar = <String>[
      'الاثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد',
    ];
    final name = (isArabic ? ar : en)[(day.weekday - 1) % 7];
    return '$name ${day.day}';
  }

  String get searchChannelsHint => isArabic
      ? 'اسم القناة أو رقمها أو مجموعتها'
      : 'Channel name, number or group';
  String get searchGuideHint => isArabic
      ? 'برنامج أو حلقة أو تصنيف'
      : 'Programme, episode or category';
  String get seekBack10 => isArabic ? 'رجوع ١٠ ثوانٍ' : 'Back 10 s';
  String get seekForward10 => isArabic ? 'تقدّم ١٠ ثوانٍ' : 'Forward 10 s';
  String get resetPictureLabel =>
      isArabic ? 'إعادة ضبط الصورة والصوت' : 'Picture and audio reset';
  String get resetPictureDone =>
      isArabic ? 'النسبة وإزالة التداخل وتأخير الصوت' : 'Aspect, deinterlace, audio delay';
  String get noOtherTracks => isArabic ? 'لا يوجد مسار آخر' : 'No other track';

  /// Key / action pairs for the shortcuts sheet. Keys are space separated.
  List<(String, String)> get shortcutHelp => isArabic
      ? const <(String, String)>[
          ('C Enter', 'قائمة القنوات والمجموعات'),
          ('↑ ↓ PgUp PgDn', 'القناة التالية / السابقة'),
          ('0-9', 'اكتب رقم القناة (ثم Enter)'),
          ('← → + −', 'مستوى الصوت (وعجلة الفأرة)'),
          ('M', 'كتم الصوت'),
          ('Space', 'إيقاف مؤقت / تشغيل'),
          ('F F11 Esc', 'ملء الشاشة / خروج'),
          ('I', 'شريط معلومات القناة (يختفي بعد قليل)'),
          ('P', 'تثبيت الشريط على الشاشة'),
          ('G', 'دليل القناة (البرامج القادمة والتسجيل)'),
          ('S', 'قائمة الصوت والترجمة'),
          ('A', 'المسار الصوتي التالي'),
          ('J', 'الترجمة التالية'),
          ('[ ]', 'تأخير الصوت −/+ 50ms'),
          ('Z', 'تغيير نسبة العرض'),
          ('T', 'إزالة التداخل'),
          ('X', 'إعادة ضبط النسبة والتداخل وتأخير الصوت'),
          ('← → (تسجيل)', 'تقديم أو رجوع ١٠ ثوانٍ، مع Shift ٦٠ ثانية، PgUp PgDn ٥ دقائق'),
          ('R', 'تسجيل على هذا الجهاز'),
          ('D', 'التشخيص'),
          ('Ctrl + − 0', 'تكبير وتصغير الواجهة'),
          ('H F1', 'هذه القائمة'),
        ]
      : const <(String, String)>[
          ('C Enter', 'Channel list and tags'),
          ('↑ ↓ PgUp PgDn', 'Next / previous channel'),
          ('0-9', 'Type a channel number (then Enter)'),
          ('← → + −', 'Volume (and the mouse wheel)'),
          ('M', 'Mute'),
          ('Space', 'Pause / play'),
          ('F F11 Esc', 'Full screen / leave'),
          ('I', 'Channel info banner (hides after a few seconds)'),
          ('P', 'Pin the banner on screen'),
          ('G', 'Channel guide: what is next, record'),
          ('Ctrl + − 0', 'Interface zoom'),
          ('S', 'Audio & subtitles menu'),
          ('A', 'Next audio track'),
          ('J', 'Next subtitle'),
          ('[ ]', 'Audio delay −/+ 50 ms'),
          ('Z', 'Cycle aspect ratio'),
          ('T', 'Deinterlace'),
          ('X', 'Reset aspect, deinterlace and audio delay'),
          ('← →  (recording)', 'Seek 10 s, with Shift 60 s, PgUp PgDn 5 min'),
          ('R', 'Record on this device'),
          ('D', 'Diagnostics'),
          ('H F1', 'This sheet'),
        ];

  String seasonOf(int n, int total) =>
      isArabic ? 'الموسم $n من $total' : 'Season $n of $total';
  String seasonN(int n) => isArabic ? 'الموسم $n' : 'Season $n';
  String episodeOf(int n, int total) =>
      isArabic ? 'الحلقة $n من $total' : 'Episode $n of $total';
  String episodeN(int n) => isArabic ? 'الحلقة $n' : 'Episode $n';
  String firstAiredOn(String date) =>
      isArabic ? 'عُرض أول مرة $date' : 'First aired $date';
  String get stbEpg => isArabic ? 'دليل القناة' : 'Channel guide';
  String get stbEpgHint => isArabic
      ? '↑↓ اختيار · Enter تسجيل · Esc إغلاق'
      : '↑↓ select · Enter record · Esc close';
  String get pinOsd => isArabic ? 'تثبيت (P)' : 'Pin (P)';
  String get unpinOsd => isArabic ? 'إلغاء التثبيت (P)' : 'Unpin (P)';
  String get viewMode => isArabic ? 'طريقة العرض' : 'View';
  String get viewCards => isArabic ? 'بطاقات' : 'Cards';
  String get viewList => isArabic ? 'قائمة' : 'List';
  String get viewCompact => isArabic ? 'مضغوط' : 'Compact';
  String get viewWall => isArabic ? 'جدار الشعارات' : 'Logo wall';
  String get displaySection => isArabic ? 'العرض والحجم' : 'Display & size';
  String get autoWord => isArabic ? 'تلقائي' : 'Auto';
  String get uiScaleLabel => isArabic ? 'حجم الواجهة' : 'Interface size';
  String get uiScaleHelp => isArabic
      ? 'يكبّر النصوص والأيقونات في كل مكان. على سطح المكتب: Ctrl ‎+‎ و Ctrl ‎−‎ و Ctrl 0.'
      : 'Makes text and icons bigger everywhere. On desktop: Ctrl + and Ctrl − to change, Ctrl 0 for automatic.';
  String get guideSizeLabel => isArabic ? 'حجم الدليل' : 'Guide size';
  String get osdSecondsLabel =>
      isArabic ? 'مدة بقاء الشريط على الشاشة' : 'On-screen display time';
  String secondsShort(int n) => isArabic ? '$n ثانية' : '$n s';
  String get pipLabel => isArabic ? 'نافذة عائمة عند الخروج' : 'Floating window on leave';
  String get pipHelp => isArabic
      ? 'عند الخروج من التطبيق أثناء المشاهدة يستمر الفيديو في نافذة صغيرة عائمة.'
      : 'Leaving the app while watching keeps the video in a small floating window.';
  String get androidPlayerLabel =>
      isArabic ? 'مشغّل الفيديو' : 'Video player';
  String get androidPlayerBuiltIn =>
      isArabic ? 'المدمج في التطبيق' : 'Built-in player';
  String get androidPlayerHelp => isArabic
      ? 'يمكن فتح القنوات والتسجيلات في mpv أو VLC (يجب تثبيته). عند الإغلاق بزر الرجوع يحفظ التطبيق موضع التوقف للتسجيلات ويعرض المتابعة في المرة التالية.'
      : 'Channels and recordings can open in mpv or VLC (it must be installed). Closing it with Back saves where a recording stopped, and the app offers to resume next time.';
  String externalPlayerMissing(String name) => isArabic
      ? '$name غير مثبّت. تم استخدام المشغّل المدمج.'
      : '$name is not installed. Using the built-in player.';
  String get pipButton => isArabic ? 'نافذة عائمة' : 'Floating window';
  String get noGuide => isArabic ? 'لا توجد بيانات دليل لهذه القناة' : 'No guide data for this channel';
  String get minutesShort => isArabic ? 'د' : 'min';
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
