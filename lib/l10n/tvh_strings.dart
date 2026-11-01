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
}
