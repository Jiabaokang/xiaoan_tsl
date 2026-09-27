import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// 应用国际化资源抽象基类，定义应用内所有界面的中英文字符串契约。
abstract class AppLocalizations {
  const AppLocalizations();

  // 当前支持的语种列表，仅支持中文和英文。
  static const supportedLocales = [
    Locale('zh'),
    Locale('en'),
  ];

  // 国际化委托实例。
  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  // 从当前 BuildContext 获取已本地化的资源。
  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizationsZh();
  }

  // 根据指定 Locale 解析对应的本地化实例。
  static AppLocalizations ofLocale(Locale? locale) {
    if (locale?.languageCode == 'en') {
      return const AppLocalizationsEn();
    }
    return const AppLocalizationsZh();
  }

  // 翻译语言名称映射（根据当前界面语言展示对应的语言名称）。
  String languageName(String code);

  // 应用品牌与基础标识
  String get appName;
  String get betaBadge;
  String get brandIconSemantics;

  // 底部导航栏标签
  String get navTranslate;
  String get navHistory;
  String get navFavorites;
  String get navSettings;

  // 路由与 404 页面
  String get pageNotFoundTitle;
  String get pageNotFound;
  String get returnToHome;

  // 翻译首页
  String get sourceLanguageLabel;
  String get targetLanguageLabel;
  String get swapLanguagesTooltip;
  String get inputTextLabel;
  String get waitingForInput;
  String detectedAs(String language);
  String get inputHint;
  String get stopSpeakingTooltip;
  String get readSourceTooltip;
  String get readTargetTooltip;
  String get clearInputTooltip;
  String get startTranslation;
  String get translateAgain;
  String get retryTranslation;
  String get modelDownloadRequired;
  String get modelDownloadDialogContent;
  String get allowMobileDownload;
  String get mobileDownloadDialogTitle;
  String get mobileDownloadDialogContent;
  String get cancel;
  String get continueDownload;
  String get translationResultLabel;
  String get translationPlaceholder;
  String get demoDisclaimer;
  String get googleDisclaimer;
  String get favoriteTranslationTooltip;
  String get unfavoriteTranslationTooltip;
  String get favoriteTooltip;
  String get unfavoriteTooltip;
  String get copyTranslationTooltip;
  String get shareTranslationTooltip;
  String get copiedNotice;
  String get selectLanguageFirstNotice;
  String get cannotSpeakNotice;
  String get ttsFailedNotice;
  String get stopSpeechFailedNotice;

  // 翻译阶段与失败提示
  String get phaseReady;
  String get phaseDetecting;
  String get phaseCheckingModel;
  String get phaseDownloadingModel;
  String get phaseTranslating;
  String get phaseSuccess;
  String get errorMaxChars;
  String get errorSwapLanguage;
  String get errorStorage;
  String get errorDetection;
  String get errorUnsupportedLang;
  String get errorModelCheck;
  String get errorModelDownload;
  String get errorTranslation;
  String get errorStorageSave;
  String get historyClearedNotice;

  // 历史与收藏页面
  String get recordsTitle;
  String get favoritesTitle;
  String get searchRecordsHint;
  String get searchFavoritesHint;
  String get readRecordsFailed;
  String get noRecordsFound;
  String get emptyRecords;
  String get emptyFavorites;
  String get onDeviceRecord;
  String get demoRecord;
  String get deleteRecordTooltip;

  // 设置页面
  String get settingsTitle;
  String get translationPreferencesSection;
  String get defaultTargetLanguage;
  String get themeModeLabel;
  String get themeModeSystem;
  String get themeModeLight;
  String get themeModeDark;
  String get appLanguageLabel;
  String get appLanguageSubtitle;
  String get languageSystem;
  String get languageZh;
  String get languageEn;
  String get offlineModelsLabel;
  String get offlineModelsSubtitle;
  String get clearHistoryLabel;
  String get clearHistoryDialogTitle;
  String get clearHistoryDialogContent;
  String get clearHistoryConfirm;
  String get privacyPolicyLabel;
  String get aboutAppLabel;

  // 隐私政策与关于页面
  String get privacyParagraph1;
  String get privacyParagraph2;
  String get privacyParagraph3;
  String get privacyParagraph4;
  String get privacyParagraph5;
  String get cannotOpenUrlNotice;
  String get aboutParagraph1;
  String get aboutParagraph2;
  String versionLabel(String version, String buildNumber);
  String get loadingVersion;

  // 结构化隐私政策卡片与外部链接文案
  String get privacyEffectiveDate;
  String get privacySubtitle;
  String get privacySection1Title;
  String get privacySection1Content;
  String get privacySection2Title;
  String get privacySection2Content;
  String get privacySection3Title;
  String get privacySection3Content;
  String get privacySection4Title;
  String get privacySection4Content;
  String get privacySection5Title;
  String get privacySection5Content;
  String get viewFullPrivacyPolicy;

  // 关于页面定位、特性卡片、开源依赖与版权文案
  String get aboutTagline;
  String get aboutFeatureOfflineTitle;
  String get aboutFeatureOfflineDesc;
  String get aboutFeaturePrivacyTitle;
  String get aboutFeaturePrivacyDesc;
  String get aboutFeatureTtsTitle;
  String get aboutFeatureTtsDesc;
  String get openSourceDependenciesLabel;
  String get openSourceDependenciesSubtitle;
  String get openSourceDependenciesTitle;
  String get openSourcePageNotice;
  String get copyrightNotice;

  // 离线语言包页面
  String get offlineModelsPageNotice;
  String get statusDownloaded;
  String get statusNotDownloaded;
  String get downloadAction;
  String get deleteAction;
  String get retryQuery;
  String get cannotReadStatus;
  String get deleteModelFailed;
  String get downloadModelFailed;

  // 语言选择页面
  String get selectSourceLanguage;
  String get selectTargetLanguage;
  String get searchLanguageHint;
  String get noLanguageFound;
}

// 中文（简体）本地化实现。
class AppLocalizationsZh extends AppLocalizations {
  const AppLocalizationsZh();

  @override
  String languageName(String code) => switch (code) {
        'auto' => '自动检测',
        'zh' => '简体中文',
        'en' => 'English',
        'ja' => '日本語',
        'ko' => '한국어',
        'fr' => 'Français',
        'de' => 'Deutsch',
        'es' => 'Español',
        'pt' => 'Português',
        'it' => 'Italiano',
        'ru' => 'Русский',
        _ => code,
      };

  @override
  String get appName => '小安翻译';
  @override
  String get betaBadge => '测试版';
  @override
  String get brandIconSemantics => '小安翻译图标';

  @override
  String get navTranslate => '翻译';
  @override
  String get navHistory => '历史';
  @override
  String get navFavorites => '收藏';
  @override
  String get navSettings => '设置';

  @override
  String get pageNotFoundTitle => '页面不存在';
  @override
  String get pageNotFound => '找不到这个页面';
  @override
  String get returnToHome => '返回翻译首页';

  @override
  String get sourceLanguageLabel => '原文语言';
  @override
  String get targetLanguageLabel => '译文语言';
  @override
  String get swapLanguagesTooltip => '交换语言';
  @override
  String get inputTextLabel => '输入文字';
  @override
  String get waitingForInput => '等待输入';
  @override
  String detectedAs(String language) => '检测为 $language';
  @override
  String get inputHint => '在这里输入要翻译的内容…';
  @override
  String get stopSpeakingTooltip => '停止朗读';
  @override
  String get readSourceTooltip => '朗读原文';
  @override
  String get readTargetTooltip => '朗读译文';
  @override
  String get clearInputTooltip => '清空输入';
  @override
  String get startTranslation => '开始翻译';
  @override
  String get translateAgain => '重新翻译';
  @override
  String get retryTranslation => '重试翻译';
  @override
  String get modelDownloadRequired => '需要下载语言模型';
  @override
  String get modelDownloadDialogContent =>
      '当前语言所需的模型尚未下载。下载可能使用移动流量，完成后会自动继续翻译。';
  @override
  String get allowMobileDownload => '允许移动网络下载';
  @override
  String get mobileDownloadDialogTitle => '使用移动网络下载模型？';
  @override
  String get mobileDownloadDialogContent => '语言模型可能占用较多流量。仅本次下载允许使用移动网络。';
  @override
  String get cancel => '取消';
  @override
  String get continueDownload => '继续下载';
  @override
  String get translationResultLabel => '翻译结果';
  @override
  String get translationPlaceholder => '译文会显示在这里';
  @override
  String get demoDisclaimer => '演示译文，不代表真实翻译效果';
  @override
  String get googleDisclaimer => '由 Google Translate 提供支持 · 译文仅供参考';
  @override
  String get favoriteTranslationTooltip => '收藏译文';
  @override
  String get unfavoriteTranslationTooltip => '取消收藏';
  @override
  String get favoriteTooltip => '收藏';
  @override
  String get unfavoriteTooltip => '取消收藏';
  @override
  String get copyTranslationTooltip => '复制译文';
  @override
  String get shareTranslationTooltip => '分享译文';
  @override
  String get copiedNotice => '已复制译文';
  @override
  String get selectLanguageFirstNotice => '请先选择原文语言，或完成一次翻译';
  @override
  String get cannotSpeakNotice => '当前设备暂不支持该语言朗读';
  @override
  String get ttsFailedNotice => '朗读失败，请检查设备语音服务';
  @override
  String get stopSpeechFailedNotice => '停止朗读失败';

  @override
  String get phaseReady => '等待翻译';
  @override
  String get phaseDetecting => '正在识别语言...';
  @override
  String get phaseCheckingModel => '正在准备语言模型...';
  @override
  String get phaseDownloadingModel => '正在下载语言模型...';
  @override
  String get phaseTranslating => '正在翻译...';
  @override
  String get phaseSuccess => '翻译成功';
  @override
  String get errorMaxChars => '最多输入 5000 个字符';
  @override
  String get errorSwapLanguage => '请先翻译或手动选择原文语言';
  @override
  String get errorStorage => '读取本地数据失败，请重启应用';
  @override
  String get errorDetection => '无法识别输入文本的语言';
  @override
  String get errorUnsupportedLang => '暂不支持当前语言组合';
  @override
  String get errorModelCheck => '检查离线模型失败，请检查存储或重试';
  @override
  String get errorModelDownload => '下载语言模型失败，请检查网络后重试';
  @override
  String get errorTranslation => '翻译失败，请检查语言模型后重试';
  @override
  String get errorStorageSave => '无法将结果写入历史';
  @override
  String get historyClearedNotice => '已清空历史';

  @override
  String get recordsTitle => '翻译历史';
  @override
  String get favoritesTitle => '我的收藏';
  @override
  String get searchRecordsHint => '搜索原文或译文';
  @override
  String get searchFavoritesHint => '搜索收藏';
  @override
  String get readRecordsFailed => '读取记录失败，请重试';
  @override
  String get noRecordsFound => '没有找到相关记录';
  @override
  String get emptyRecords => '还没有翻译记录';
  @override
  String get emptyFavorites => '还没有收藏';
  @override
  String get onDeviceRecord => '设备端记录';
  @override
  String get demoRecord => '演示记录';
  @override
  String get deleteRecordTooltip => '删除记录';

  @override
  String get settingsTitle => '设置';
  @override
  String get translationPreferencesSection => '翻译偏好';
  @override
  String get defaultTargetLanguage => '默认目标语言';
  @override
  String get themeModeLabel => '外观模式';
  @override
  String get themeModeSystem => '跟随系统';
  @override
  String get themeModeLight => '浅色';
  @override
  String get themeModeDark => '深色';
  @override
  String get appLanguageLabel => '应用语言';
  @override
  String get appLanguageSubtitle => '跟随系统或手动选择界面语言';
  @override
  String get languageSystem => '跟随系统语言';
  @override
  String get languageZh => '简体中文';
  @override
  String get languageEn => 'English';
  @override
  String get offlineModelsLabel => '离线语言包';
  @override
  String get offlineModelsSubtitle => '查看、下载或删除设备端模型';
  @override
  String get clearHistoryLabel => '清空翻译历史';
  @override
  String get clearHistoryDialogTitle => '清空翻译历史？';
  @override
  String get clearHistoryDialogContent => '收藏也会一并删除，此操作无法撤销。';
  @override
  String get clearHistoryConfirm => '清空';
  @override
  String get privacyPolicyLabel => '隐私政策';
  @override
  String get aboutAppLabel => '关于小安翻译';

  @override
  String get privacyParagraph1 =>
      '小安翻译无需注册或登录。输入文字、翻译结果、历史、收藏和设置保存在本机；Android 版本已关闭系统备份。';
  @override
  String get privacyParagraph2 =>
      '语言识别和翻译在设备端完成。首次使用某种语言时，应用会通过 Google ML Kit 下载语言模型。应用不把输入文字上传到自有服务器。';
  @override
  String get privacyParagraph3 => '朗读由设备安装的语音引擎处理；复制或分享后，文字由你选择的系统功能或第三方应用处理。';
  @override
  String get privacyParagraph4 => '应用不申请麦克风、相机、位置或通讯录权限。';
  @override
  String get privacyParagraph5 =>
      'Google ML Kit 可能向 Google 发送设备、应用及性能等诊断数据；完整的数据处理与删除说明请查看公开隐私政策。';
  @override
  String get cannotOpenUrlNotice => '无法打开网页，请在浏览器输入页面上的网址';
  @override
  String get aboutParagraph1 => '小安翻译使用设备端语言识别、翻译和系统语音朗读。';
  @override
  String get aboutParagraph2 => '翻译能力由 Google ML Kit 提供。';
  @override
  String versionLabel(String version, String buildNumber) =>
      '版本 $version ($buildNumber)';
  @override
  String get loadingVersion => '正在读取版本信息…';

  @override
  String get privacyEffectiveDate => '生效日期：2026年9月';
  @override
  String get privacySubtitle =>
      '小安翻译无需注册登录。翻译文字在设备端处理，历史与偏好保存在本机；ML Kit 仍可能联网下载模型并发送诊断数据。';
  @override
  String get privacySection1Title => '数据存储与设备边界';
  @override
  String get privacySection1Content =>
      '成功翻译后的原文、译文、语言、时间和收藏保存在本机；主题、默认目标语言及界面语言偏好也保存在本机。Android 版本已关闭系统备份。';
  @override
  String get privacySection2Title => '离线模型与网络隔离';
  @override
  String get privacySection2Content =>
      'Google ML Kit 在设备端识别和翻译文字。首次使用尚未安装的语言模型时需要联网下载；首页会先征求确认，确认后本次下载也可使用移动数据。';
  @override
  String get privacySection3Title => '语音与系统分享安全';
  @override
  String get privacySection3Content =>
      '朗读会把所选文字交给设备安装的语音引擎；该引擎是否联网取决于提供者。复制和分享会把文字交给系统剪贴板或您选择的应用。';
  @override
  String get privacySection4Title => '权限最小化声明';
  @override
  String get privacySection4Content =>
      '应用严格遵循最小必要权限原则，不申请麦克风、相机、位置或通讯录等任何敏感系统权限。';
  @override
  String get privacySection5Title => '诊断数据与第三方说明';
  @override
  String get privacySection5Content =>
      'Google ML Kit 可能向 Google 发送设备、应用、语言及性能等诊断数据。完整的数据处理规则请参阅公开隐私政策。';
  @override
  String get viewFullPrivacyPolicy => '查看完整在线隐私政策';

  @override
  String get aboutTagline => '轻量、私密、纯粹的设备端离线翻译工具';
  @override
  String get aboutFeatureOfflineTitle => '离线双向翻译';
  @override
  String get aboutFeatureOfflineDesc =>
      '基于 Google ML Kit 离线多语种模型，无需连接服务器即可在本地完成快速互译。';
  @override
  String get aboutFeaturePrivacyTitle => '隐私无痕存储';
  @override
  String get aboutFeaturePrivacyDesc =>
      '记录与偏好严格保存在本地 SQLite 数据库中，关闭系统云备份，数据完全归属于你。';
  @override
  String get aboutFeatureTtsTitle => '本地语音朗读';
  @override
  String get aboutFeatureTtsDesc => '直连系统底层原生 TTS 语音合成引擎，发音流畅自然且不消耗额外网络流量。';
  @override
  String get openSourceDependenciesLabel => '第三方开源库与组件';
  @override
  String get openSourceDependenciesSubtitle => '查看本应用使用的 13 个核心开源依赖';
  @override
  String get openSourceDependenciesTitle => '第三方开源库与组件';
  @override
  String get openSourcePageNotice =>
      '本应用严格遵循各开源库的许可协议。点击任意库可在浏览器打开其国内镜像页面（pub-web.flutter-io.cn）了解详情。';
  @override
  String get copyrightNotice =>
      'Copyright © 2026 小安翻译 Team. All rights reserved.';

  @override
  String get offlineModelsPageNotice => '模型状态来自设备。首次下载默认仅使用 Wi-Fi，下载后可离线翻译。';
  @override
  String get statusDownloaded => '已下载';
  @override
  String get statusNotDownloaded => '未下载';
  @override
  String get downloadAction => '下载';
  @override
  String get deleteAction => '删除';
  @override
  String get retryQuery => '重试查询';
  @override
  String get cannotReadStatus => '无法读取离线模型状态';
  @override
  String get deleteModelFailed => '删除语言模型失败，请重试';
  @override
  String get downloadModelFailed => '下载语言模型失败，请检查网络后重试';

  @override
  String get selectSourceLanguage => '选择原文语言';
  @override
  String get selectTargetLanguage => '选择译文语言';
  @override
  String get searchLanguageHint => '搜索语言';
  @override
  String get noLanguageFound => '没有找到语言';
}

// 英文本地化实现。
class AppLocalizationsEn extends AppLocalizations {
  const AppLocalizationsEn();

  @override
  String languageName(String code) => switch (code) {
        'auto' => 'Auto Detect',
        'zh' => 'Simplified Chinese',
        'en' => 'English',
        'ja' => 'Japanese',
        'ko' => 'Korean',
        'fr' => 'French',
        'de' => 'German',
        'es' => 'Spanish',
        'pt' => 'Portuguese',
        'it' => 'Italian',
        'ru' => 'Russian',
        _ => code,
      };

  @override
  String get appName => 'Xiaoan Translate';
  @override
  String get betaBadge => 'Beta';
  @override
  String get brandIconSemantics => 'Xiaoan Translate Icon';

  @override
  String get navTranslate => 'Translate';
  @override
  String get navHistory => 'History';
  @override
  String get navFavorites => 'Favorites';
  @override
  String get navSettings => 'Settings';

  @override
  String get pageNotFoundTitle => 'Page Not Found';
  @override
  String get pageNotFound => 'Cannot find this page';
  @override
  String get returnToHome => 'Return to Translate';

  @override
  String get sourceLanguageLabel => 'Source Language';
  @override
  String get targetLanguageLabel => 'Target Language';
  @override
  String get swapLanguagesTooltip => 'Swap languages';
  @override
  String get inputTextLabel => 'Input Text';
  @override
  String get waitingForInput => 'Waiting for input';
  @override
  String detectedAs(String language) => 'Detected as $language';
  @override
  String get inputHint => 'Enter text to translate here…';
  @override
  String get stopSpeakingTooltip => 'Stop speaking';
  @override
  String get readSourceTooltip => 'Read source text';
  @override
  String get readTargetTooltip => 'Read translation';
  @override
  String get clearInputTooltip => 'Clear input';
  @override
  String get startTranslation => 'Translate';
  @override
  String get translateAgain => 'Translate Again';
  @override
  String get retryTranslation => 'Retry';
  @override
  String get modelDownloadRequired => 'Language model required';
  @override
  String get modelDownloadDialogContent =>
      'A model for this language is missing. Downloading may use cellular data. Translation will continue when it is ready.';
  @override
  String get allowMobileDownload => 'Allow download via cellular';
  @override
  String get mobileDownloadDialogTitle => 'Download model using cellular data?';
  @override
  String get mobileDownloadDialogContent =>
      'Language models may consume considerable data. Cellular data will only be used for this download.';
  @override
  String get cancel => 'Cancel';
  @override
  String get continueDownload => 'Continue Download';
  @override
  String get translationResultLabel => 'Translation Result';
  @override
  String get translationPlaceholder => 'Translation will appear here';
  @override
  String get demoDisclaimer =>
      'Demo translation, does not represent actual translation quality';
  @override
  String get googleDisclaimer =>
      'Powered by Google Translate · For reference only';
  @override
  String get favoriteTranslationTooltip => 'Favorite translation';
  @override
  String get unfavoriteTranslationTooltip => 'Remove favorite';
  @override
  String get favoriteTooltip => 'Favorite';
  @override
  String get unfavoriteTooltip => 'Remove favorite';
  @override
  String get copyTranslationTooltip => 'Copy translation';
  @override
  String get shareTranslationTooltip => 'Share translation';
  @override
  String get copiedNotice => 'Translation copied';
  @override
  String get selectLanguageFirstNotice =>
      'Please select source language or complete a translation first';
  @override
  String get cannotSpeakNotice =>
      'Speech is not supported for this language on this device';
  @override
  String get ttsFailedNotice =>
      'Speech failed, please check device TTS service';
  @override
  String get stopSpeechFailedNotice => 'Failed to stop speech';

  @override
  String get phaseReady => 'Ready to translate';
  @override
  String get phaseDetecting => 'Identifying language...';
  @override
  String get phaseCheckingModel => 'Preparing language model...';
  @override
  String get phaseDownloadingModel => 'Downloading language model...';
  @override
  String get phaseTranslating => 'Translating...';
  @override
  String get phaseSuccess => 'Translation successful';
  @override
  String get errorMaxChars => 'Maximum 5000 characters allowed';
  @override
  String get errorSwapLanguage =>
      'Please translate first or select source language manually';
  @override
  String get errorStorage => 'Failed to read local data, please restart app';
  @override
  String get errorDetection => 'Unable to identify the language of input text';
  @override
  String get errorUnsupportedLang => 'Language pair not currently supported';
  @override
  String get errorModelCheck =>
      'Failed to check offline model, please check storage or retry';
  @override
  String get errorModelDownload =>
      'Failed to download language model, please check network and retry';
  @override
  String get errorTranslation =>
      'Translation failed, please check language models and retry';
  @override
  String get errorStorageSave => 'Failed to save record to history';
  @override
  String get historyClearedNotice => 'History cleared';

  @override
  String get recordsTitle => 'Translation History';
  @override
  String get favoritesTitle => 'My Favorites';
  @override
  String get searchRecordsHint => 'Search source or translation';
  @override
  String get searchFavoritesHint => 'Search favorites';
  @override
  String get readRecordsFailed => 'Failed to read records, please retry';
  @override
  String get noRecordsFound => 'No matching records found';
  @override
  String get emptyRecords => 'No translation history yet';
  @override
  String get emptyFavorites => 'No favorites yet';
  @override
  String get onDeviceRecord => 'On-device';
  @override
  String get demoRecord => 'Demo';
  @override
  String get deleteRecordTooltip => 'Delete record';

  @override
  String get settingsTitle => 'Settings';
  @override
  String get translationPreferencesSection => 'Translation Preferences';
  @override
  String get defaultTargetLanguage => 'Default Target Language';
  @override
  String get themeModeLabel => 'Theme Mode';
  @override
  String get themeModeSystem => 'System';
  @override
  String get themeModeLight => 'Light';
  @override
  String get themeModeDark => 'Dark';
  @override
  String get appLanguageLabel => 'App Language';
  @override
  String get appLanguageSubtitle =>
      'Follow system or manually select interface language';
  @override
  String get languageSystem => 'Follow System Language';
  @override
  String get languageZh => '简体中文';
  @override
  String get languageEn => 'English';
  @override
  String get offlineModelsLabel => 'Offline Models';
  @override
  String get offlineModelsSubtitle =>
      'View, download, or delete on-device models';
  @override
  String get clearHistoryLabel => 'Clear Translation History';
  @override
  String get clearHistoryDialogTitle => 'Clear translation history?';
  @override
  String get clearHistoryDialogContent =>
      'Favorites will also be deleted. This action cannot be undone.';
  @override
  String get clearHistoryConfirm => 'Clear';
  @override
  String get privacyPolicyLabel => 'Privacy Policy';
  @override
  String get aboutAppLabel => 'About Xiaoan Translate';

  @override
  String get privacyParagraph1 =>
      'Xiaoan Translate requires no registration or login. Input text, translation results, history, favorites, and settings are stored on this device. System backup is disabled on Android.';
  @override
  String get privacyParagraph2 =>
      'Language identification and translation are performed on-device. When using a language for the first time, the app downloads language models via Google ML Kit. The app does not upload your text to any proprietary server.';
  @override
  String get privacyParagraph3 =>
      'Speech is processed by your device\'s installed text-to-speech engine. When copied or shared, text is processed by system features or third-party apps of your choice.';
  @override
  String get privacyParagraph4 =>
      'The app does not request microphone, camera, location, or contacts permissions.';
  @override
  String get privacyParagraph5 =>
      'Google ML Kit may send diagnostic data such as device, app, and performance metrics to Google. For complete data handling and deletion information, please refer to the public privacy policy.';
  @override
  String get cannotOpenUrlNotice =>
      'Cannot open webpage. Please enter the URL in a browser.';
  @override
  String get aboutParagraph1 =>
      'Xiaoan Translate uses on-device language identification, translation, and system speech synthesis.';
  @override
  String get aboutParagraph2 =>
      'Translation capabilities are powered by Google ML Kit.';
  @override
  String versionLabel(String version, String buildNumber) =>
      'Version $version ($buildNumber)';
  @override
  String get loadingVersion => 'Loading version information…';

  @override
  String get privacyEffectiveDate => 'Effective Date: September 2026';
  @override
  String get privacySubtitle =>
      'Xiaoan Translate requires no account. Text is translated on your device, and history and preferences stay there; ML Kit may still download models and send diagnostics.';
  @override
  String get privacySection1Title => 'Data Storage & Device Boundary';
  @override
  String get privacySection1Content =>
      'After translation, source text, translated text, languages, time and favorites are stored locally. Theme, default target language and interface language preferences are also stored locally. Android system backup is disabled.';
  @override
  String get privacySection2Title => 'Offline Models & Network Isolation';
  @override
  String get privacySection2Content =>
      'Google ML Kit identifies languages and translates text on-device. A missing language model needs a network download. The home screen asks for confirmation first; the confirmed download may use cellular data.';
  @override
  String get privacySection3Title => 'Speech & System Sharing Security';
  @override
  String get privacySection3Content =>
      'Reading text aloud passes the selected text to your installed speech engine; whether it uses the network depends on its provider. Copy and Share pass text to the system clipboard or an app you choose.';
  @override
  String get privacySection4Title => 'Minimal Permissions Declaration';
  @override
  String get privacySection4Content =>
      'The app strictly adheres to minimal permissions and does not request microphone, camera, location, or contacts permissions.';
  @override
  String get privacySection5Title => 'Diagnostic Data & Third-Party Notice';
  @override
  String get privacySection5Content =>
      'Google ML Kit may send device, app, language and performance diagnostics to Google. See the public privacy policy for the full details.';
  @override
  String get viewFullPrivacyPolicy => 'View Complete Online Privacy Policy';

  @override
  String get aboutTagline =>
      'Lightweight, private, and on-device offline translation tool';
  @override
  String get aboutFeatureOfflineTitle => 'Offline Bi-Directional Translation';
  @override
  String get aboutFeatureOfflineDesc =>
      'Powered by Google ML Kit on-device models, translating quickly without external server connections.';
  @override
  String get aboutFeaturePrivacyTitle => 'Private Local Storage';
  @override
  String get aboutFeaturePrivacyDesc =>
      'Records and preferences stay securely in a local SQLite database with cloud backup disabled.';
  @override
  String get aboutFeatureTtsTitle => 'Native Speech Synthesis';
  @override
  String get aboutFeatureTtsDesc =>
      'Direct integration with device native TTS engine for natural pronunciation without extra data usage.';
  @override
  String get openSourceDependenciesLabel =>
      'Open Source Licenses & Dependencies';
  @override
  String get openSourceDependenciesSubtitle =>
      'View the 13 core open source dependencies used by this app';
  @override
  String get openSourceDependenciesTitle =>
      'Open Source Licenses & Dependencies';
  @override
  String get openSourcePageNotice =>
      'This application complies with each open source package license. Tap any library to open its mirror details page in your browser.';
  @override
  String get copyrightNotice =>
      'Copyright © 2026 Xiaoan Translate Team. All rights reserved.';

  @override
  String get offlineModelsPageNotice =>
      'Model status is retrieved from the device. Initial download defaults to Wi-Fi only. Once downloaded, models can translate offline.';
  @override
  String get statusDownloaded => 'Downloaded';
  @override
  String get statusNotDownloaded => 'Not downloaded';
  @override
  String get downloadAction => 'Download';
  @override
  String get deleteAction => 'Delete';
  @override
  String get retryQuery => 'Retry Query';
  @override
  String get cannotReadStatus => 'Unable to read offline model status';
  @override
  String get deleteModelFailed =>
      'Failed to delete language model, please retry';
  @override
  String get downloadModelFailed =>
      'Failed to download language model, please check network and retry';

  @override
  String get selectSourceLanguage => 'Select Source Language';
  @override
  String get selectTargetLanguage => 'Select Target Language';
  @override
  String get searchLanguageHint => 'Search language';
  @override
  String get noLanguageFound => 'No languages found';
}

// 国际化资源委托，支持 zh 和 en。
class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['zh', 'en'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(
      AppLocalizations.ofLocale(locale),
    );
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

// 便捷语法糖，允许直接使用 context.l10n 访问文案。
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
