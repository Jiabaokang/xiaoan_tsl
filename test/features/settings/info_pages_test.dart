import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';

void main() {
  test('AppLocalizations 包含新增的关于和第三方库文案', () {
    const zh = AppLocalizationsZh();
    const en = AppLocalizationsEn();

    expect(zh.aboutTagline, isNotEmpty);
    expect(en.aboutTagline, isNotEmpty);
    expect(zh.openSourceDependenciesLabel, '第三方开源库与组件');
    expect(
      en.openSourceDependenciesLabel,
      'Open Source Licenses & Dependencies',
    );
    expect(zh.privacyEffectiveDate, contains('2026'));
    expect(en.privacyEffectiveDate, contains('2026'));
  });

  test('中英文本地化所有新增关于和隐私字段均不为空', () {
    const zh = AppLocalizationsZh();
    const en = AppLocalizationsEn();

    for (final loc in [zh, en]) {
      expect(loc.privacyEffectiveDate, isNotEmpty);
      expect(loc.privacySubtitle, isNotEmpty);
      expect(loc.privacySection1Title, isNotEmpty);
      expect(loc.privacySection1Content, isNotEmpty);
      expect(loc.privacySection2Title, isNotEmpty);
      expect(loc.privacySection2Content, isNotEmpty);
      expect(loc.privacySection3Title, isNotEmpty);
      expect(loc.privacySection3Content, isNotEmpty);
      expect(loc.privacySection4Title, isNotEmpty);
      expect(loc.privacySection4Content, isNotEmpty);
      expect(loc.privacySection5Title, isNotEmpty);
      expect(loc.privacySection5Content, isNotEmpty);
      expect(loc.viewFullPrivacyPolicy, isNotEmpty);
      expect(loc.aboutTagline, isNotEmpty);
      expect(loc.aboutFeatureOfflineTitle, isNotEmpty);
      expect(loc.aboutFeatureOfflineDesc, isNotEmpty);
      expect(loc.aboutFeaturePrivacyTitle, isNotEmpty);
      expect(loc.aboutFeaturePrivacyDesc, isNotEmpty);
      expect(loc.aboutFeatureTtsTitle, isNotEmpty);
      expect(loc.aboutFeatureTtsDesc, isNotEmpty);
      expect(loc.openSourceDependenciesLabel, isNotEmpty);
      expect(loc.openSourceDependenciesSubtitle, isNotEmpty);
      expect(loc.openSourceDependenciesTitle, isNotEmpty);
      expect(loc.openSourcePageNotice, isNotEmpty);
      expect(loc.copyrightNotice, isNotEmpty);
    }
  });
}
