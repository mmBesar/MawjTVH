/// Readable names for the ISO 639 codes that audio and subtitle tracks carry.
///
/// Broadcast streams use the three-letter codes (`ara`, `eng`, `fre`); some
/// players report two letters. Unknown codes are shown as they are.
String languageName(String? code, {required bool arabic}) {
  final raw = (code ?? '').trim().toLowerCase();
  if (raw.isEmpty || raw == 'und' || raw == 'unk') {
    return '';
  }
  final entry = _names[raw];
  if (entry == null) {
    return code!.trim();
  }
  return arabic ? entry.$2 : entry.$1;
}

/// Name for a track's language code, including the codes that are not
/// languages: `org` (original soundtrack), `und` (not labelled), and so on.
/// Empty when there is nothing to show.
String trackLanguageName(String? code, {required bool arabic}) {
  final raw = (code ?? '').trim().toLowerCase();
  final special = _special[raw] ??
      (raw.length == 3 && raw.startsWith('q') ? _special['qaa'] : null);
  if (special != null) {
    return arabic ? special.$2 : special.$1;
  }
  return languageName(code, arabic: arabic);
}

const Map<String, (String, String)> _special = <String, (String, String)>{
  'org': ('Original', 'الأصلية'),
  'qaa': ('Original', 'الأصلية'),
  'und': ('Unnamed', 'بدون اسم'),
  'unk': ('Unnamed', 'بدون اسم'),
  'mul': ('Multiple languages', 'لغات متعددة'),
  'mis': ('Other', 'أخرى'),
  'zxx': ('No speech', 'بدون كلام'),
};

const Map<String, (String, String)> _names = <String, (String, String)>{
  'ara': ('Arabic', 'العربية'),
  'ar': ('Arabic', 'العربية'),
  'eng': ('English', 'الإنجليزية'),
  'en': ('English', 'الإنجليزية'),
  'fre': ('French', 'الفرنسية'),
  'fra': ('French', 'الفرنسية'),
  'fr': ('French', 'الفرنسية'),
  'ger': ('German', 'الألمانية'),
  'deu': ('German', 'الألمانية'),
  'de': ('German', 'الألمانية'),
  'spa': ('Spanish', 'الإسبانية'),
  'es': ('Spanish', 'الإسبانية'),
  'ita': ('Italian', 'الإيطالية'),
  'it': ('Italian', 'الإيطالية'),
  'por': ('Portuguese', 'البرتغالية'),
  'pt': ('Portuguese', 'البرتغالية'),
  'rus': ('Russian', 'الروسية'),
  'ru': ('Russian', 'الروسية'),
  'tur': ('Turkish', 'التركية'),
  'tr': ('Turkish', 'التركية'),
  'per': ('Persian', 'الفارسية'),
  'fas': ('Persian', 'الفارسية'),
  'fa': ('Persian', 'الفارسية'),
  'kur': ('Kurdish', 'الكردية'),
  'ku': ('Kurdish', 'الكردية'),
  'heb': ('Hebrew', 'العبرية'),
  'he': ('Hebrew', 'العبرية'),
  'urd': ('Urdu', 'الأردية'),
  'ur': ('Urdu', 'الأردية'),
  'hin': ('Hindi', 'الهندية'),
  'hi': ('Hindi', 'الهندية'),
  'dut': ('Dutch', 'الهولندية'),
  'nld': ('Dutch', 'الهولندية'),
  'nl': ('Dutch', 'الهولندية'),
  'pol': ('Polish', 'البولندية'),
  'pl': ('Polish', 'البولندية'),
  'gre': ('Greek', 'اليونانية'),
  'ell': ('Greek', 'اليونانية'),
  'el': ('Greek', 'اليونانية'),
  'chi': ('Chinese', 'الصينية'),
  'zho': ('Chinese', 'الصينية'),
  'zh': ('Chinese', 'الصينية'),
  'jpn': ('Japanese', 'اليابانية'),
  'ja': ('Japanese', 'اليابانية'),
  'kor': ('Korean', 'الكورية'),
  'ko': ('Korean', 'الكورية'),
  'swe': ('Swedish', 'السويدية'),
  'nor': ('Norwegian', 'النرويجية'),
  'dan': ('Danish', 'الدنماركية'),
  'fin': ('Finnish', 'الفنلندية'),
  'cze': ('Czech', 'التشيكية'),
  'ces': ('Czech', 'التشيكية'),
  'hun': ('Hungarian', 'المجرية'),
  'rum': ('Romanian', 'الرومانية'),
  'ron': ('Romanian', 'الرومانية'),
  'bul': ('Bulgarian', 'البلغارية'),
  'srp': ('Serbian', 'الصربية'),
  'hrv': ('Croatian', 'الكرواتية'),
  'alb': ('Albanian', 'الألبانية'),
  'sqi': ('Albanian', 'الألبانية'),
  'amh': ('Amharic', 'الأمهرية'),
  'som': ('Somali', 'الصومالية'),
  'mul': ('Multiple languages', 'لغات متعددة'),
  'qaa': ('Original audio', 'الصوت الأصلي'),
};
