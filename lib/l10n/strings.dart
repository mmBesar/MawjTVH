import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/catppuccin.dart';
import '../data/models.dart';

/// Hand-written localisation. It keeps the build simple (no code generation)
/// while still covering every string the interface uses, in English and
/// Arabic.
class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ar'),
  ];

  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings) ??
        const AppStrings(Locale('en'));
  }

  bool get isArabic => locale.languageCode == 'ar';

  String get appName => 'MawjTVH';
  String get appTagline =>
      isArabic ? 'مشغّل Tvheadend سلس مع دليل وتسجيلات' : 'A Tvheadend client with a smooth guide, recordings and a proper player';

  String get channels => isArabic ? 'القنوات' : 'Channels';
  String get guide => isArabic ? 'الدليل' : 'Guide';
  String get sources =>
      isArabic ? 'الخوادم' : 'Servers';
  String get settings => isArabic ? 'الإعدادات' : 'Settings';

  String get searchChannels => isArabic ? 'ابحث في القنوات' : 'Search channels';
  String get searchProgrammes => isArabic ? 'ابحث في البرامج' : 'Search programmes';
  String get clearSearch => isArabic ? 'مسح البحث' : 'Clear search';
  String get allGroups => isArabic ? 'كل المجموعات' : 'All groups';
  String get noChannels => isArabic ? 'لا توجد قنوات بعد' : 'No channels yet';
  String get noChannelsBody =>
      isArabic ? 'أضف خادم Tvheadend لتحميل قنواته ودليله.' : 'Add a Tvheadend server to load its channels and guide.';
  String get noSearchResults =>
      isArabic ? 'لا توجد قنوات تطابق البحث.' : 'No channels match your search.';
  String get addSource =>
      isArabic ? 'إضافة خادم' : 'Add server';
  String get now => isArabic ? 'الآن' : 'Now';
  String get next => isArabic ? 'التالي' : 'Next';
  String get live => isArabic ? 'مباشر' : 'LIVE';
  String get onNow => isArabic ? 'يُعرض الآن' : 'On now';
  String get upNext => isArabic ? 'التالي' : 'Up next';
  String get noProgrammeInfo =>
      isArabic ? 'لا تتوفر معلومات عن البرنامج' : 'No programme information';
  String get channel => isArabic ? 'القناة' : 'Channel';
  String get channelsLabel => isArabic ? 'القنوات' : 'Channels';
  String get programmesLabel => isArabic ? 'البرامج' : 'Programmes';

  String channelCount(int count) => isArabic
      ? '$count قناة'
      : count == 1
          ? '1 channel'
          : '$count channels';

  String programmeCount(int count) => isArabic
      ? '$count برنامج'
      : count == 1
          ? '1 programme'
          : '$count programmes';

  String get guideEmptyTitle => isArabic ? 'لا توجد بيانات للدليل' : 'No guide data yet';
  String get guideEmptyBody =>
      isArabic ? 'لا توجد بيانات دليل للساعات القادمة. تأكد من عمل مُحمّلات الدليل (EPG grabbers) على الخادم ثم حدّث.' : 'The server has no guide data for the coming hours. Check that the EPG grabbers run on the server, then refresh.';
  String get guideNoChannels =>
      isArabic ? 'أضف خادمًا لعرض جدول البرامج.' : 'Add a server to see the programme schedule.';
  String get guideNow => isArabic ? 'الآن' : 'Now';
  String get timelineZoom =>
      isArabic ? 'تكبير الجدول الزمني' : 'Timeline zoom';
  String get twelveHourWindow =>
      isArabic ? 'نافذة 12 ساعة' : '12-hour window';

  String get retry => isArabic ? 'إعادة المحاولة' : 'Retry';
  String get refresh => isArabic ? 'تحديث' : 'Refresh';
  String get refreshing => isArabic ? 'جارٍ التحديث…' : 'Refreshing…';
  String get close => isArabic ? 'إغلاق' : 'Close';
  String get cancel => isArabic ? 'إلغاء' : 'Cancel';
  String get save => isArabic ? 'حفظ' : 'Save';
  String get edit => isArabic ? 'تعديل' : 'Edit';
  String get delete => isArabic ? 'حذف' : 'Delete';
  String get back => isArabic ? 'رجوع' : 'Back';
  String get done => isArabic ? 'تم' : 'Done';
  String get unknown => isArabic ? 'غير معروف' : 'Unknown';

  String get active => isArabic ? 'نشط' : 'Active';
  String get setActive => isArabic ? 'تعيين كنشط' : 'Set as active';
  String get activeSource =>
      isArabic ? 'الخادم النشط' : 'Active server';
  String get noSources =>
      isArabic ? 'لا توجد خوادم' : 'No servers yet';
  String get noSourcesBody =>
      isArabic ? 'أضف خادم Tvheadend للبدء: العنوان واسم المستخدم وكلمة المرور. يمكنك حفظ عدة خوادم والتبديل بينها.' : 'Add your Tvheadend server to get started: its address, username and password. You can keep several servers and switch between them.';
  String get sourceName =>
      isArabic ? 'اسم الخادم' : 'Server name';
  String get sourceNameHint =>
      isArabic ? 'مثال: خادم المنزل' : 'For example: Home server';
  String get playlistM3u => isArabic ? 'قائمة التشغيل (M3U)' : 'Playlist (M3U)';
  String get xmltvGuide => isArabic ? 'دليل XMLTV' : 'XMLTV guide';
  String get playlistHelp => isArabic
      ? 'رابط أو ملف M3U أو M3U8.'
      : 'An M3U or M3U8 URL or file.';
  String get guideHelp => isArabic
      ? 'اتركه فارغًا لاستخدام عنوان XMLTV المعلن في قائمة التشغيل.'
      : 'Leave empty to use the XMLTV URL advertised by the playlist.';
  String get location => isArabic ? 'الموقع' : 'Location';
  String get url => isArabic ? 'رابط' : 'URL';
  String get file => isArabic ? 'ملف' : 'File';
  String get chooseFile => isArabic ? 'اختيار ملف' : 'Choose file';
  String get browse => isArabic ? 'استعراض' : 'Browse';
  String get allowInsecure =>
      isArabic ? 'السماح بشهادات HTTPS ذاتية التوقيع' : 'Allow self-signed HTTPS certificates';
  String get allowInsecureHelp =>
      isArabic ? 'فعّل هذا الخيار للخوادم المحلية التي تستخدم شهادة HTTPS ذاتية التوقيع. يُطبَّق على الاتصال والشعارات والتشغيل. يُقبل HTTP العادي دائمًا.' : 'Enable for local servers with a self-signed HTTPS certificate. Applies to the connection, logos and playback. Plain HTTP is always accepted.';
  String get addSourceTitle =>
      isArabic ? 'إضافة خادم' : 'Add server';
  String get editSourceTitle =>
      isArabic ? 'تعديل الخادم' : 'Edit server';
  String get sourceAdded => isArabic ? 'تمت إضافة المصدر.' : 'Source added.';
  String get sourceSaved => isArabic ? 'تم حفظ المصدر.' : 'Source saved.';
  String get sourceNameRequired =>
      isArabic ? 'أدخل اسمًا للمصدر.' : 'Enter a name for this source.';
  String get playlistRequired =>
      isArabic ? 'أدخل رابط أو ملف قائمة التشغيل.' : 'Enter a playlist URL or file.';
  String get invalidLocation => isArabic
      ? 'أدخل رابطًا يبدأ بـ http أو https، أو مسار ملف صالح.'
      : 'Enter an http(s) URL or a valid file path.';
  String get deleteSourceTitle =>
      isArabic ? 'حذف المصدر؟' : 'Delete source?';
  String deleteSourceBody(String name) => isArabic
      ? 'سيتم حذف «$name» وإعداداته من هذا الجهاز.'
      : '"$name" and its settings will be removed from this device.';
  String get testConnection => isArabic ? 'اختبار الاتصال' : 'Test connection';
  String get testing => isArabic ? 'جارٍ الاختبار…' : 'Testing…';
  String get testSucceeded => isArabic ? 'نجح الاتصال' : 'Connection succeeded';
  String get testFailed => isArabic ? 'فشل الاتصال' : 'Connection failed';
  String testSummary(int channels, int programmes) => isArabic
      ? 'تم العثور على $channels قناة و$programmes برنامج.'
      : 'Found ${channelCount(channels)} and ${programmeCount(programmes)}.';
  String get saveAndLoad => isArabic ? 'حفظ وتحميل' : 'Save and load';

  String get appearance => isArabic ? 'المظهر' : 'Appearance';
  String get theme => isArabic ? 'السمة' : 'Theme';
  String get accent => isArabic ? 'لون التمييز' : 'Accent';
  String get language => isArabic ? 'اللغة' : 'Language';
  String get systemLanguage => isArabic ? 'لغة النظام' : 'System language';
  String get english => 'English';
  String get arabic => 'العربية';
  String get timeFormat => isArabic ? 'صيغة الوقت' : 'Time format';
  String get use24HourTime =>
      isArabic ? 'استخدام نظام 24 ساعة' : 'Use 24-hour time';
  String get use24HourTimeHelp => isArabic
      ? 'عند الإيقاف يُعرض الوقت بنظام 12 ساعة مع ص/م.'
      : 'When off, times use a 12-hour clock with AM/PM.';
  String get dataAndGuide => isArabic ? 'البيانات والدليل' : 'Data and guide';
  String get lastUpdated => isArabic ? 'آخر تحديث' : 'Last updated';
  String get never => isArabic ? 'أبدًا' : 'Never';
  String get guideSource => isArabic ? 'مصدر الدليل' : 'Guide source';
  String get notConfigured => isArabic ? 'غير مُهيّأ' : 'Not configured';
  String get fromCache => isArabic ? 'من الذاكرة المؤقتة' : 'From cache';
  String get about => isArabic ? 'حول' : 'About';
  String get version => isArabic ? 'الإصدار' : 'Version';
  String get licenses => isArabic ? 'التراخيص' : 'Licenses';
  String get viewLicenses => isArabic ? 'عرض تراخيص المصادر المفتوحة' : 'View open-source licenses';
  String get projectPage => isArabic ? 'صفحة المشروع' : 'Project page';
  String get aboutBody => isArabic
      ? 'MawjTVH عميل حر ومفتوح المصدر لخادم Tvheadend على Android وLinux، يعمل بالبروتوكول الأصلي HTSP، مع دعم كامل للنصوص العربية والإنجليزية. مشروع شخصي غير رسمي وما زال قيد التطوير، وليس تابعًا لمشروع Tvheadend.'
      : 'MawjTVH is a free, open-source Tvheadend client for Android and Linux. It speaks Tvheadend\'s native HTSP protocol and has first-class Arabic and English text support. A personal project, unofficial and still in development; it is not affiliated with the Tvheadend project.';
  String get appearanceSystem => isArabic ? 'النظام' : 'System';
  String get systemThemeHelp => isArabic
      ? 'تتبع السمة ألوان النظام. على Android تُستخدم الألوان الديناميكية عند توفرها.'
      : 'Follows the system appearance. On Android, dynamic colours are used when available.';
  String get languageHelp => isArabic
      ? 'تتبع الواجهة لغة النظام عند اختيار «لغة النظام».'
      : 'The interface follows the system language when set to "System language".';

  String get themeSystem => isArabic ? 'النظام' : 'System';
  String get themeMawj => isArabic ? 'موجة' : 'Mawj';
  String get themeFoam => isArabic ? 'رغوة' : 'Foam';
  String get themeLatte => 'Latte';
  String get themeFrappe => 'Frappé';
  String get themeMacchiato => 'Macchiato';
  String get themeMocha => 'Mocha';
  String get themeAmoled => 'AMOLED';
  String themeFamilyLabel(ThemeFamily family) => switch (family) {
        ThemeFamily.system => themeSystem,
        ThemeFamily.studio => isArabic ? 'استوديو' : 'Studio',
        ThemeFamily.daylight => isArabic ? 'نهار' : 'Daylight',
        ThemeFamily.mawj => themeMawj,
        ThemeFamily.foam => themeFoam,
        ThemeFamily.latte => themeLatte,
        ThemeFamily.frappe => themeFrappe,
        ThemeFamily.macchiato => themeMacchiato,
        ThemeFamily.mocha => themeMocha,
        ThemeFamily.amoled => themeAmoled,
      };

  String get warningNoEpg =>
      isArabic ? 'لا يوجد دليل لهذا الخادم.' : 'This server has no guide.';
  String get warningPlaylistCache =>
      isArabic ? 'تعذّر الوصول إلى الخادم؛ تُعرض آخر قنوات محفوظة.' : 'The server could not be reached; showing the last saved channels.';
  String get warningEpgCache =>
      isArabic ? 'تعذّر تحديث الدليل؛ تُعرض النسخة المحفوظة.' : 'The guide could not be refreshed; showing the saved copy.';
  String get warningEpgUnavailable =>
      isArabic ? 'تعذّر تحميل الدليل من الخادم.' : 'The guide could not be loaded from the server.';
  String get warningEpgEmpty =>
      isArabic ? 'اتصلنا بالخادم لكن لا توجد برامج في الدليل ضمن النافذة الحالية.' : 'The server answered but its guide has no programmes in the current window.';
  String warningText(LoadWarning warning) => switch (warning) {
        LoadWarning.noEpgEndpoint => warningNoEpg,
        LoadWarning.playlistFromCache => warningPlaylistCache,
        LoadWarning.epgFromCache => warningEpgCache,
        LoadWarning.epgUnavailable => warningEpgUnavailable,
        LoadWarning.epgEmpty => warningEpgEmpty,
      };

  String get playbackError =>
      isArabic ? 'تعذّر تشغيل البث' : 'Playback failed';
  String get playbackErrorBody =>
      isArabic ? 'تعذّر فتح القناة. تحقق من اتصال الشبكة، ومن أن حسابك يسمح بالمشاهدة، ومن ملف البث وإعداد الشهادات ذاتية التوقيع.' : 'The channel could not be opened. Check the network connection, that your account may watch, the stream profile, and the self-signed certificate setting.';
  String get playbackRetry => isArabic ? 'إعادة المحاولة' : 'Retry playback';
  String get fullScreen => isArabic ? 'ملء الشاشة' : 'Full screen';
  String get play => isArabic ? 'تشغيل' : 'Play';
  String get pause => isArabic ? 'إيقاف مؤقت' : 'Pause';
  String get mute => isArabic ? 'كتم الصوت' : 'Mute';
  String get unmute => isArabic ? 'إلغاء كتم الصوت' : 'Unmute';
  String get volume => isArabic ? 'مستوى الصوت' : 'Volume';
  String get brightness => isArabic ? 'السطوع' : 'Brightness';
  String get exitFullScreen => isArabic ? 'إنهاء ملء الشاشة' : 'Exit full screen';
  String get closePlayer => isArabic ? 'إغلاق المشغّل' : 'Close player';
  String get streamUnavailable =>
      isArabic ? 'البث غير متاح' : 'Stream unavailable';

  String get channelGuide => isArabic ? 'دليل القناة' : 'Channel guide';
  String get watchLive => isArabic ? 'مشاهدة مباشرة' : 'Watch live';
  String get programmeGuide =>
      isArabic ? 'جدول البرامج' : 'Programme schedule';

  String get programmeDetails => isArabic ? 'تفاصيل البرنامج' : 'Programme details';
  String get noDescription =>
      isArabic ? 'لا يوجد وصف لهذا البرنامج.' : 'No description for this programme.';
  String get categories => isArabic ? 'التصنيفات' : 'Categories';
  String get watchChannel => isArabic ? 'مشاهدة القناة' : 'Watch channel';
  String get startsAt => isArabic ? 'يبدأ' : 'Starts';
  String get endsAt => isArabic ? 'ينتهي' : 'Ends';

  String get errorTitle => isArabic ? 'حدث خطأ' : 'Something went wrong';
  String get settingsSaved => isArabic ? 'تم حفظ الإعدادات.' : 'Settings saved.';
  String get noActiveSource =>
      isArabic ? 'لا يوجد مصدر نشط' : 'No active source';
  String get openSettings => isArabic ? 'فتح الإعدادات' : 'Open settings';

  String get errorGeneric => isArabic
      ? 'تعذّر إكمال العملية. حاول مرة أخرى.'
      : 'The operation could not be completed. Try again.';

  String relativeTime(DateTime time, DateTime now) {
    final difference = now.difference(time);
    if (difference.inSeconds < 60) {
      return isArabic ? 'قبل لحظات' : 'moments ago';
    }
    if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return isArabic ? 'قبل $minutes دقيقة' : '${minutes}m ago';
    }
    if (difference.inHours < 24) {
      final hours = difference.inHours;
      return isArabic ? 'قبل $hours ساعة' : '${hours}h ago';
    }
    final days = difference.inDays;
    return isArabic ? 'قبل $days يوم' : '${days}d ago';
  }

  String formatTime(DateTime value, {required bool use24HourTime}) {
    final hour = value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    if (use24HourTime) {
      return '${hour.toString().padLeft(2, '0')}:$minute';
    }
    final display = hour % 12 == 0 ? 12 : hour % 12;
    final suffix = hour < 12
        ? (isArabic ? 'ص' : 'AM')
        : (isArabic ? 'م' : 'PM');
    return '$display:$minute $suffix';
  }

  String formatHour(DateTime value, {required bool use24HourTime}) {
    final hour = value.hour;
    final minute = value.minute;
    if (use24HourTime) {
      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    }
    final display = hour % 12 == 0 ? 12 : hour % 12;
    final suffix = minute == 0
        ? (hour < 12 ? (isArabic ? 'ص' : 'AM') : (isArabic ? 'م' : 'PM'))
        : '';
    final minutes = minute == 0 ? '' : ':${minute.toString().padLeft(2, '0')}';
    return suffix.isEmpty ? '$display$minutes' : '$display$minutes $suffix';
  }

  String formatRange(
    DateTime start,
    DateTime stop, {
    required bool use24HourTime,
  }) {
    return '${formatTime(start, use24HourTime: use24HourTime)} – '
        '${formatTime(stop, use24HourTime: use24HourTime)}';
  }

  String formatDateTime(DateTime value, {required bool use24HourTime}) {
    return '${formatDate(value)} · '
        '${formatTime(value, use24HourTime: use24HourTime)}';
  }

  String formatDate(DateTime value) {
    final weekdays = isArabic
        ? const <String>[
            'الاثنين',
            'الثلاثاء',
            'الأربعاء',
            'الخميس',
            'الجمعة',
            'السبت',
            'الأحد',
          ]
        : const <String>[
            'Monday',
            'Tuesday',
            'Wednesday',
            'Thursday',
            'Friday',
            'Saturday',
            'Sunday',
          ];
    final months = isArabic
        ? const <String>[
            'يناير',
            'فبراير',
            'مارس',
            'أبريل',
            'مايو',
            'يونيو',
            'يوليو',
            'أغسطس',
            'سبتمبر',
            'أكتوبر',
            'نوفمبر',
            'ديسمبر',
          ]
        : const <String>[
            'January',
            'February',
            'March',
            'April',
            'May',
            'June',
            'July',
            'August',
            'September',
            'October',
            'November',
            'December',
          ];
    final weekday = weekdays[(value.weekday - 1) % 7];
    final month = months[(value.month - 1) % 12];
    return isArabic
        ? '$weekday، ${value.day} $month'
        : '$weekday, $month ${value.day}';
  }

  String formatDayNumber(DateTime value) => value.day.toString();
  // ---- MawjTVH additions ----
  String get watch => isArabic ? 'شاهد' : 'Watch';
  String get search => isArabic ? 'بحث' : 'Search';
  String get favorites => isArabic ? 'المفضلة' : 'Favorites';
  String get allChannels => isArabic ? 'الكل' : 'All';
  String get resume => isArabic ? 'متابعة' : 'Resume';
  String get watchNow => isArabic ? 'شاهد الآن' : 'Watch now';
  String get addFavorite => isArabic ? 'إضافة إلى المفضلة' : 'Add to favorites';
  String get removeFavorite =>
      isArabic ? 'إزالة من المفضلة' : 'Remove from favorites';
  String get noFavorites => isArabic ? 'لا توجد قنوات مفضلة' : 'No favorites yet';
  String get noFavoritesBody => isArabic
      ? 'اضغط على النجمة بجانب أي قناة لتظهر هنا.'
      : 'Tap the star next to a channel to keep it here.';
  String get welcomeTitle => isArabic ? 'ابدأ المشاهدة' : 'Tune in';
  String get welcomeBody =>
      isArabic ? 'أضف خادم Tvheadend الخاص بك. المسؤول يدير كل شيء، والمستخدم العادي يشاهد ويسجّل حسب صلاحيات حسابه.' : 'Add your Tvheadend server. Admins see everything; normal users watch and record as their account allows.';
  String get searchHint =>
      isArabic ? 'قناة أو برنامج' : 'Channel or programme';
  String get searchEmptyTitle =>
      isArabic ? 'ابحث في كل شيء' : 'Find anything on air';
  String get searchEmptyBody => isArabic
      ? 'اكتب اسم قناة أو برنامج أو تصنيف.'
      : 'Type a channel, a programme or a category.';
  String get noResultsTitle => isArabic ? 'لا نتائج' : 'No results';
  String noResultsBody(String query) => isArabic
      ? 'لا شيء يطابق «$query».'
      : 'Nothing matches "$query".';
  String get onAirSoon => isArabic ? 'قريبًا على الهواء' : 'On air soon';
  String get guideFavoritesOnly =>
      isArabic ? 'المفضلة فقط' : 'Favorites only';
  String get tuning => isArabic ? 'جارٍ الاتصال بالقناة' : 'Tuning in';
  String get stalledTitle =>
      isArabic ? 'ما زلنا ننتظر الفيديو' : 'Still waiting for video';
  String get stalledBody => isArabic
      ? 'قد يكون الخادم ما زال يجهّز القناة. انتظر قليلًا، أو أعد المحاولة، أو انسخ التشخيص لإرساله.'
      : 'The server may still be starting this channel. Wait a little, retry, or copy the diagnostics to share.';
  String get diagnostics => isArabic ? 'التشخيص' : 'Diagnostics';
  String get copyDiagnostics => isArabic ? 'نسخ التشخيص' : 'Copy diagnostics';
  String get copied => isArabic ? 'تم النسخ' : 'Copied';
  String get nextChannel => isArabic ? 'القناة التالية' : 'Next channel';
  String get previousChannel => isArabic ? 'القناة السابقة' : 'Previous channel';
  String get manageSources => isArabic ? 'إدارة المصادر' : 'Manage sources';
  String get startsSoon => isArabic ? 'يبدأ قريبًا' : 'Starts soon';
  // Desktop player and settings.
  String get startingPlayer =>
      isArabic ? 'جارٍ تشغيل المشغّل' : 'Starting the player';
  String get playingInWindow =>
      isArabic ? 'يعمل في نافذة المشغّل' : 'Playing in the player window';
  String get stopPlayback => isArabic ? 'إيقاف' : 'Stop';
  String get playerClosed =>
      isArabic ? 'أُغلقت نافذة المشغّل' : 'The player window closed';
  String get playerFailed =>
      isArabic ? 'توقف المشغّل بخطأ' : 'The player stopped with an error';
  String decodingWith(String decoder) =>
      isArabic ? 'فك الترميز: $decoder' : 'Decoding: $decoder';
  String get softwareDecoding => isArabic ? 'برمجي' : 'software';
  String get toggleFullscreen =>
      isArabic ? 'ملء الشاشة' : 'Toggle fullscreen';
  String get switchSource => isArabic ? 'تبديل المصدر' : 'Switch source';
  String get recentlyWatched =>
      isArabic ? 'شوهدت مؤخرًا' : 'Recently watched';
  String get autoRefresh =>
      isArabic ? 'التحديث التلقائي' : 'Refresh automatically';
  String get autoRefreshOff => isArabic ? 'متوقف' : 'Off';
  String autoRefreshEvery(int minutes) {
    if (minutes < 60) {
      return isArabic ? 'كل $minutes دقيقة' : 'Every $minutes minutes';
    }
    final hours = minutes ~/ 60;
    if (hours == 1) {
      return isArabic ? 'كل ساعة' : 'Every hour';
    }
    return isArabic ? 'كل $hours ساعات' : 'Every $hours hours';
  }
  String get autoRefreshHelp => isArabic
      ? 'يحدّث القنوات والدليل في الخلفية للحفاظ عليهما محدّثين.'
      : 'Reloads the channels and guide in the background to keep them current.';
  String get guideSpan => isArabic ? 'مدى الدليل' : 'Guide timeline length';
  String hoursCount(int hours) =>
      isArabic ? '$hours ساعة' : '$hours hours';
  String get playerSection => isArabic ? 'المشغّل' : 'Player';
  String get useMpvWindow =>
      isArabic ? 'مشغّل mpv في نافذة مستقلة' : 'Play in a separate mpv window';
  String get useMpvWindowBody => isArabic
      ? 'أفضل أداء على لينكس: فك ترميز بالعتاد وملء شاشة حقيقي. عند الإيقاف يعمل المشغّل المدمج.'
      : 'Best on Linux: hardware decoding and real compositor fullscreen. Off uses the built-in renderer.';
  String get hardwareDecoding =>
      isArabic ? 'فك الترميز بالعتاد' : 'Hardware decoding';
  String get hwdecAutoSafe =>
      isArabic ? 'تلقائي (آمن)' : 'Automatic (safe)';
  String get hwdecAuto => isArabic ? 'تلقائي' : 'Automatic';
  String get hwdecOff => isArabic ? 'برمجي فقط' : 'Software only';
  String get hwdecAutoCopy =>
      isArabic ? 'تلقائي (بنسخ الإطارات)' : 'Automatic (copy-back)';
  String get videoOutput => isArabic ? 'مخرج الفيديو' : 'Video output';
  String get videoOutputAuto => isArabic ? 'الافتراضي' : 'Default';
  String get useMpvConfig =>
      isArabic ? 'استخدم إعدادات mpv الخاصة بي' : 'Use my own mpv config';
  String get useMpvConfigBody => isArabic
      ? 'يحمّل ‎~/.config/mpv‎ بما فيها السكربتات مثل uosc.'
      : 'Loads ~/.config/mpv, including scripts such as uosc.';
  String get startFullscreen =>
      isArabic ? 'ابدأ بملء الشاشة' : 'Start fullscreen';
  String mpvFound(String version, bool bundled) => isArabic
      ? '${bundled ? 'مضمّن' : 'من النظام'} · $version'
      : '${bundled ? 'Bundled' : 'System'} · $version';
  String get mpvMissing => isArabic
      ? 'mpv غير مثبّت أو غير موجود، لذا يُستخدم المشغّل المدمج. ثبّت حزمة mpv أو حدّد مساره في الإعدادات.'
      : 'mpv was not found, so the built-in player is used. Install mpv (for example sudo apt install mpv, or add it to your NixOS packages) or set its path in Settings.';
  String get mpvPathLabel =>
      isArabic ? 'مسار mpv (اختياري)' : 'mpv path (optional)';
  String get mpvPathHint => isArabic ? '/usr/bin/mpv' : '/usr/bin/mpv';
  String get apply => isArabic ? 'تطبيق' : 'Apply';
  String get today => isArabic ? 'اليوم' : 'Today';
  String get tomorrow => isArabic ? 'غدًا' : 'Tomorrow';
  String get noUpcoming =>
      isArabic ? 'لا توجد برامج قادمة لهذه القناة' : 'No upcoming programmes for this channel';

  String minutesLeft(int minutes) =>
      isArabic ? 'متبقي $minutes د' : '$minutes min left';
  String startsIn(int minutes) {
    if (minutes < 60) {
      return isArabic ? 'يبدأ بعد $minutes د' : 'Starts in $minutes min';
    }
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    final suffix = rest == 0 ? '' : ' $rest';
    return isArabic
        ? 'يبدأ بعد $hours س$suffix'
        : 'Starts in ${hours}h$suffix';
  }

}

class AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const AppStringsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppStrings.supportedLocales
        .any((supported) => supported.languageCode == locale.languageCode);
  }

  @override
  Future<AppStrings> load(Locale locale) {
    return SynchronousFuture<AppStrings>(AppStrings(locale));
  }

  @override
  bool shouldReload(AppStringsDelegate old) => false;
}

extension AppStringsContext on BuildContext {
  AppStrings get strings => AppStrings.of(this);
}
