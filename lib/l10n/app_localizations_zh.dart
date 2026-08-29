// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '每日智慧：EAST.';

  @override
  String get tapAnywhereToBegin => '點一下任意位置以開始。';

  @override
  String get tapWhenReady => '準備好時點一下。';

  @override
  String get pause => '停一停。';

  @override
  String get feel => '感受。';

  @override
  String get askFromYourHeart => '從心裡提問。';

  @override
  String get east => 'EAST.';

  @override
  String get kept => '留下的';

  @override
  String get searchKept => '搜尋';

  @override
  String get clearSearch => '清除搜尋';

  @override
  String get noKeptSearchResults => '找不到結果。';

  @override
  String get keptUpper => '留下的';

  @override
  String get reflectedUpper => '已省思';

  @override
  String get addReflectionUpper => '新增省思';

  @override
  String get reflection => '省思';

  @override
  String get journal => '日記';

  @override
  String get settings => '設定';

  @override
  String get language => '語言';

  @override
  String get systemDefault => '系統預設';

  @override
  String get english => '英文';

  @override
  String languageSettingSemantics(Object value) {
    return '語言。目前選擇：$value。';
  }

  @override
  String languageOptionSemantics(Object language) {
    return '$language';
  }

  @override
  String get appearance => '外观';

  @override
  String get light => '浅色';

  @override
  String get dark => '深色';

  @override
  String appearanceSettingSemantics(Object value) {
    return '外观。当前选择：$value。';
  }

  @override
  String appearanceOptionSemantics(Object option) {
    return '$option';
  }

  @override
  String get back => '返回';

  @override
  String get delete => '刪除';

  @override
  String get deleteUpper => '刪除';

  @override
  String get cancel => '取消';

  @override
  String get close => '關閉';

  @override
  String get done => '完成';

  @override
  String get retry => '再試一次';

  @override
  String get tryAgainUpper => '再試一次';

  @override
  String get skip => '略過';

  @override
  String get addName => '新增名字';

  @override
  String get changeName => '更改名字';

  @override
  String get keptWisdoms => '留下的智慧';

  @override
  String get addReflection => '新增省思';

  @override
  String get deleteReflection => '刪除省思';

  @override
  String get reflectedEditReflection => '已省思。編輯省思。';

  @override
  String addReflectionNumbered(Object number) {
    return '新增省思，項目 $number';
  }

  @override
  String openReflectionNumbered(Object number) {
    return '開啟省思，項目 $number';
  }

  @override
  String get journalSemantic => '日記';

  @override
  String get keeper => '留住';

  @override
  String get restorePurchases => '回復購買項目';

  @override
  String get icloudSync => 'iCloud 同步';

  @override
  String get removeFromIcloud => '從 iCloud 移除';

  @override
  String get exportMyData => '匯出我的資料';

  @override
  String get privacyPolicy => '隱私權政策';

  @override
  String get reachOut => '聯絡我們';

  @override
  String get eastProductions => 'EAST. Productions';

  @override
  String get supportCircle => '讓圓圈延續，留住留下的。';

  @override
  String get restoreBelongs => '找回屬於你的。';

  @override
  String get worldBeyondRitual => '儀式之外的世界。';

  @override
  String get whatStaysPrivate => '保持私密的部分。';

  @override
  String get thoughtsAndQuestions => '用於想法與提問。';

  @override
  String get keepThisWisdom => '留住這份智慧。';

  @override
  String get wisdomCouldNotBeKept => '無法留住這份智慧。請再試一次。';

  @override
  String get keptLimit => '留下的數量上限';

  @override
  String get freeUsersKeepLimit => '免費使用者最多可留住 3 則智慧。';

  @override
  String get keepReflectingQuestion => '繼續省思？';

  @override
  String get reflectionLimitExplanation => '內含 3 則省思。Keeper 為留下的一切開啟無限空間。';

  @override
  String get becomeKeeper => '啟用留住';

  @override
  String get whoseJournal => '這是誰的日記？';

  @override
  String get journalNameExplanation => '名字會靜靜出現在日記的扉頁。';

  @override
  String get notificationTitle => 'EAST.';

  @override
  String get notificationBody => '有什麼在寂靜中等待。';

  @override
  String get journalPdfTitle => '日記。';

  @override
  String get dailyWisdomReady => '新的智慧已準備好。';

  @override
  String get discoverTheObjects => '探索物件';

  @override
  String get enterTheCircle => '走進圓圈。';

  @override
  String get withinTheCircle => '身在圓圈之中。';

  @override
  String get keeperActive => 'Keeper 已啟用';

  @override
  String get oneTimePurchase => '一次性購買';

  @override
  String get askFrom => '從心裡';

  @override
  String get yourHeart => '提問。';

  @override
  String get longPressToShareWisdom => '長按即可分享這份智慧。';

  @override
  String get shareWisdom => '分享';

  @override
  String shareWisdomNumbered(int itemNumber) {
    return '分享智慧，第 $itemNumber 項';
  }

  @override
  String get quietReminder => '靜默提醒';

  @override
  String get nothingHasStayedYet => '還沒有任何事物留下。';

  @override
  String get wisdomCouldNotBeRemoved => '無法移除這份智慧。請再試一次。';

  @override
  String get reflectionPrompt => '此刻，你注意到了什麼？';

  @override
  String get returnWhenSilenceOpensAgain => '寂靜再次敞開時，回來吧。';

  @override
  String get reflectionPromptWhatRemains => '什麼留下了？';

  @override
  String get reflectionPromptWhatStayedWithYou => '什麼留在你心裡？';

  @override
  String get reflectionPromptWhatBecameClearer => '什麼變得更清晰了？';

  @override
  String get reflectionPromptWhatFeelsDifferent => '什麼感覺不一樣了？';

  @override
  String get reflectionPromptCarryForward => '你想帶著什麼前行？';

  @override
  String get deleteReflectionQuestion => '刪除省思？';

  @override
  String get reflectionDeleteExplanation => '這則留下的智慧將移除其省思。';

  @override
  String get removeKeptQuestion => '從「留下的」移除？';

  @override
  String get keptDeleteExplanation => '這則智慧及其省思將被移除。';

  @override
  String get cancelUpper => '取消';

  @override
  String get continueAction => '繼續';

  @override
  String get onlyKeptOnThisDevice => '僅留存在此裝置上。';

  @override
  String get yourName => '你的名字';

  @override
  String get journalCouldNotBePrepared => '無法準備日記。請再試一次。';

  @override
  String get takeItWithYou => '隨身帶走。';

  @override
  String get takeItWithYouKeeper => '隨身帶走。可透過「留住」使用。';

  @override
  String get availableWithKeeper => '可透過「留住」使用。';

  @override
  String get opensKeeper => '開啟 Keeper。';

  @override
  String get nameUpper => '名字';

  @override
  String get keeperPersistenceError => '無法儲存「留住」的使用權。請嘗試回復購買項目。';

  @override
  String get purchaseUpdating => '購買狀態仍在更新。請在設定中使用回復購買項目。';

  @override
  String get purchaseNotReady => '尚未能進行購買。請稍後再試。';

  @override
  String get restore => '回復';

  @override
  String get keepWhatStays => '留住留下的。';

  @override
  String get addReflectionSemantics => '新增省思';

  @override
  String get deleteSemantics => '刪除';

  @override
  String get settingsClose => '關閉';

  @override
  String get notificationPermissionTitle => '一次寂靜的回返';

  @override
  String get notificationPermissionBody => '新的智慧準備好時，要通知你嗎？';

  @override
  String get whereSilenceSpeaks => '寂靜說話的地方。';

  @override
  String get preparing => '準備中…';

  @override
  String get exportKeptAndReflections => '帶走你留下的智慧與省思。';

  @override
  String get keeperAccessActive => '「留住」使用權已啟用';

  @override
  String keeperPurchaseInProgress(Object price) {
    return '走進圓圈，$price。購買進行中。';
  }

  @override
  String keeperPurchaseOffering(Object price) {
    return '走進圓圈，$price，一次性費用';
  }

  @override
  String get keeperUnavailable => '走進圓圈，暫時無法使用';

  @override
  String get keepWithoutLimit => '無限留住。';

  @override
  String get reflectWithoutLimit => '無限省思。';

  @override
  String get takeJournalWithYou => '帶走你的日記。';

  @override
  String get keeperWidgetRitual => '儀式，就在你的小工具中。';

  @override
  String get addKeeperWidget => '加入 Keeper 小工具';

  @override
  String get keeperWidgetInteractive => '在 iOS 17 或更新版本中，可直接在小工具內開始儀式。';

  @override
  String get keeperWidgetOpensApp => '在 iOS 15 與 16 中，小工具會開啟 EAST.。';

  @override
  String get keepEastAlive => '讓 EAST. 延續。';

  @override
  String get operationFailedRetry => '無法完成，請再試一次。';

  @override
  String get restoreRequestSent => '已送出回復請求。Keeper 權限將自動更新。';

  @override
  String get restoreRecoveryPending =>
      '先前的回復仍在處理中。Keeper 權限將自動更新；再次嘗試前請重新開啟 EAST.。';

  @override
  String get opening => '正在開啟。';

  @override
  String get bootstrapRecovery => '開啟時間比預期更久。請關閉 EAST.，然後重新開啟。';

  @override
  String get supportEmailSubject => 'EAST. 支援';

  @override
  String get removeIcloudLocalData => '保留的智慧與反思會留在這部 iPhone 上。';

  @override
  String get removeIcloudCloudData => '它們的 iCloud 副本會被移除，iCloud 同步也會關閉。';

  @override
  String get enableIcloudQuestion => '啟用 iCloud 同步？';

  @override
  String get enableIcloudData => '保留的智慧與反思會儲存在你的私人 iCloud 資料庫中，並在裝置間同步。';

  @override
  String get dailyRitualOnDevice => '每日儀式的時間仍會留在此裝置上。';

  @override
  String get removeUpper => '移除';

  @override
  String get saveUpper => '儲存';

  @override
  String get enableUpper => '啟用';

  @override
  String get icloudEnabling => '正在啟用…';

  @override
  String get icloudEnabled => '已啟用';

  @override
  String get icloudSyncing => '同步中';

  @override
  String get icloudUnavailable => 'iCloud 無法使用';

  @override
  String get icloudNeedsAttention => '需要留意';

  @override
  String get icloudNotEnabled => '未啟用';

  @override
  String get icloudRemovalStarting => '正在開始…';

  @override
  String get icloudRemovalCompleted => '已從 iCloud 移除。';

  @override
  String get icloudRemovalPending => '等待移除。iCloud 可用時 EAST. 會完成。';

  @override
  String get icloudRemovalIdle => '移除你的 iCloud 副本。';

  @override
  String get icloudRemovalNone => '沒有可移除的內容。';

  @override
  String get reflectionSaveFailed => '無法儲存反思，請再試一次。';

  @override
  String get reflectionAutosaveFailed => '無法儲存反思；你繼續書寫時會再試一次。';

  @override
  String get reflectionDeleteFailed => '無法刪除反思，請再試一次。';

  @override
  String remainingDurationHoursMinutes(int hours, int minutes) {
    return '還剩$hours小時$minutes分鐘';
  }

  @override
  String remainingDurationHoursOnly(int hours) {
    return '還剩$hours小時';
  }

  @override
  String remainingDurationMinutesOnly(int minutes) {
    return '還剩$minutes分鐘';
  }
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get appTitle => '每日智慧：EAST.';

  @override
  String get tapAnywhereToBegin => '點一下任意位置以開始。';

  @override
  String get tapWhenReady => '準備好時點一下。';

  @override
  String get pause => '停一停。';

  @override
  String get feel => '感受。';

  @override
  String get askFromYourHeart => '從心裡提問。';

  @override
  String get east => 'EAST.';

  @override
  String get kept => '留下的';

  @override
  String get searchKept => '搜尋';

  @override
  String get clearSearch => '清除搜尋';

  @override
  String get noKeptSearchResults => '找不到結果。';

  @override
  String get keptUpper => '留下的';

  @override
  String get reflectedUpper => '已省思';

  @override
  String get addReflectionUpper => '新增省思';

  @override
  String get reflection => '省思';

  @override
  String get journal => '日記';

  @override
  String get settings => '設定';

  @override
  String get language => '語言';

  @override
  String get systemDefault => '系統預設';

  @override
  String get english => '英文';

  @override
  String languageSettingSemantics(Object value) {
    return '語言。目前選擇：$value。';
  }

  @override
  String languageOptionSemantics(Object language) {
    return '$language';
  }

  @override
  String get appearance => '外觀';

  @override
  String get light => '淺色';

  @override
  String get dark => '深色';

  @override
  String appearanceSettingSemantics(Object value) {
    return '外觀。目前選擇：$value。';
  }

  @override
  String appearanceOptionSemantics(Object option) {
    return '$option';
  }

  @override
  String get back => '返回';

  @override
  String get delete => '刪除';

  @override
  String get deleteUpper => '刪除';

  @override
  String get cancel => '取消';

  @override
  String get close => '關閉';

  @override
  String get done => '完成';

  @override
  String get retry => '再試一次';

  @override
  String get tryAgainUpper => '再試一次';

  @override
  String get skip => '略過';

  @override
  String get addName => '新增名字';

  @override
  String get changeName => '更改名字';

  @override
  String get keptWisdoms => '留下的智慧';

  @override
  String get addReflection => '新增省思';

  @override
  String get deleteReflection => '刪除省思';

  @override
  String get reflectedEditReflection => '已省思。編輯省思。';

  @override
  String addReflectionNumbered(Object number) {
    return '新增省思，項目 $number';
  }

  @override
  String openReflectionNumbered(Object number) {
    return '開啟省思，項目 $number';
  }

  @override
  String get journalSemantic => '日記';

  @override
  String get keeper => '留住';

  @override
  String get restorePurchases => '回復購買項目';

  @override
  String get icloudSync => 'iCloud 同步';

  @override
  String get removeFromIcloud => '從 iCloud 移除';

  @override
  String get exportMyData => '匯出我的資料';

  @override
  String get privacyPolicy => '隱私權政策';

  @override
  String get reachOut => '聯絡我們';

  @override
  String get eastProductions => 'EAST. Productions';

  @override
  String get supportCircle => '讓圓圈延續，留住留下的。';

  @override
  String get restoreBelongs => '找回屬於你的。';

  @override
  String get worldBeyondRitual => '儀式之外的世界。';

  @override
  String get whatStaysPrivate => '保持私密的部分。';

  @override
  String get thoughtsAndQuestions => '用於想法與提問。';

  @override
  String get keepThisWisdom => '留住這份智慧。';

  @override
  String get wisdomCouldNotBeKept => '無法留住這份智慧。請再試一次。';

  @override
  String get keptLimit => '留下的數量上限';

  @override
  String get freeUsersKeepLimit => '免費使用者最多可留住 3 則智慧。';

  @override
  String get keepReflectingQuestion => '繼續省思？';

  @override
  String get reflectionLimitExplanation => '內含 3 則省思。Keeper 為留下的一切開啟無限空間。';

  @override
  String get becomeKeeper => '啟用留住';

  @override
  String get whoseJournal => '這是誰的日記？';

  @override
  String get journalNameExplanation => '名字會靜靜出現在日記的扉頁。';

  @override
  String get notificationTitle => 'EAST.';

  @override
  String get notificationBody => '有什麼在寂靜中等待。';

  @override
  String get journalPdfTitle => '日記。';

  @override
  String get dailyWisdomReady => '新的智慧已準備好。';

  @override
  String get discoverTheObjects => '探索物件';

  @override
  String get enterTheCircle => '走進圓圈。';

  @override
  String get withinTheCircle => '身在圓圈之中。';

  @override
  String get keeperActive => 'Keeper 已啟用';

  @override
  String get oneTimePurchase => '一次性購買';

  @override
  String get askFrom => '從心裡';

  @override
  String get yourHeart => '提問。';

  @override
  String get longPressToShareWisdom => '長按即可分享這份智慧。';

  @override
  String get shareWisdom => '分享';

  @override
  String shareWisdomNumbered(int itemNumber) {
    return '分享智慧，第 $itemNumber 項';
  }

  @override
  String get quietReminder => '靜默提醒';

  @override
  String get nothingHasStayedYet => '還沒有任何事物留下。';

  @override
  String get wisdomCouldNotBeRemoved => '無法移除這份智慧。請再試一次。';

  @override
  String get reflectionPrompt => '此刻，你注意到了什麼？';

  @override
  String get returnWhenSilenceOpensAgain => '寂靜再次敞開時，回來吧。';

  @override
  String get reflectionPromptWhatRemains => '什麼留下了？';

  @override
  String get reflectionPromptWhatStayedWithYou => '什麼留在你心裡？';

  @override
  String get reflectionPromptWhatBecameClearer => '什麼變得更清晰了？';

  @override
  String get reflectionPromptWhatFeelsDifferent => '什麼感覺不一樣了？';

  @override
  String get reflectionPromptCarryForward => '你想帶著什麼前行？';

  @override
  String get deleteReflectionQuestion => '刪除省思？';

  @override
  String get reflectionDeleteExplanation => '這則留下的智慧將移除其省思。';

  @override
  String get removeKeptQuestion => '從「留下的」移除？';

  @override
  String get keptDeleteExplanation => '這則智慧及其省思將被移除。';

  @override
  String get cancelUpper => '取消';

  @override
  String get continueAction => '繼續';

  @override
  String get onlyKeptOnThisDevice => '僅留存在此裝置上。';

  @override
  String get yourName => '你的名字';

  @override
  String get journalCouldNotBePrepared => '無法準備日記。請再試一次。';

  @override
  String get takeItWithYou => '隨身帶走。';

  @override
  String get takeItWithYouKeeper => '隨身帶走。可透過「留住」使用。';

  @override
  String get availableWithKeeper => '可透過「留住」使用。';

  @override
  String get opensKeeper => '開啟 Keeper。';

  @override
  String get nameUpper => '名字';

  @override
  String get keeperPersistenceError => '無法儲存「留住」的使用權。請嘗試回復購買項目。';

  @override
  String get purchaseUpdating => '購買狀態仍在更新。請在設定中使用回復購買項目。';

  @override
  String get purchaseNotReady => '尚未能進行購買。請稍後再試。';

  @override
  String get restore => '回復';

  @override
  String get keepWhatStays => '留住留下的。';

  @override
  String get addReflectionSemantics => '新增省思';

  @override
  String get deleteSemantics => '刪除';

  @override
  String get settingsClose => '關閉';

  @override
  String get notificationPermissionTitle => '一次寂靜的回返';

  @override
  String get notificationPermissionBody => '新的智慧準備好時，要通知你嗎？';

  @override
  String get whereSilenceSpeaks => '寂靜說話的地方。';

  @override
  String get preparing => '準備中…';

  @override
  String get exportKeptAndReflections => '帶走你留下的智慧與省思。';

  @override
  String get keeperAccessActive => '「留住」使用權已啟用';

  @override
  String keeperPurchaseInProgress(Object price) {
    return '走進圓圈，$price。購買進行中。';
  }

  @override
  String keeperPurchaseOffering(Object price) {
    return '走進圓圈，$price，一次性費用';
  }

  @override
  String get keeperUnavailable => '走進圓圈，暫時無法使用';

  @override
  String get keepWithoutLimit => '無限留住。';

  @override
  String get reflectWithoutLimit => '無限省思。';

  @override
  String get takeJournalWithYou => '帶走你的日記。';

  @override
  String get keeperWidgetRitual => '儀式，就在你的小工具中。';

  @override
  String get addKeeperWidget => '加入 Keeper 小工具';

  @override
  String get keeperWidgetInteractive => '在 iOS 17 或更新版本中，可直接在小工具內開始儀式。';

  @override
  String get keeperWidgetOpensApp => '在 iOS 15 與 16 中，小工具會開啟 EAST.。';

  @override
  String get keepEastAlive => '讓 EAST. 延續。';

  @override
  String get operationFailedRetry => '無法完成，請再試一次。';

  @override
  String get restoreRequestSent => '已送出回復請求。Keeper 權限將自動更新。';

  @override
  String get restoreRecoveryPending =>
      '先前的回復仍在處理中。Keeper 權限將自動更新；再次嘗試前請重新開啟 EAST.。';

  @override
  String get opening => '正在開啟。';

  @override
  String get bootstrapRecovery => '開啟時間比預期更久。請關閉 EAST.，然後重新開啟。';

  @override
  String get supportEmailSubject => 'EAST. 支援';

  @override
  String get removeIcloudLocalData => '保留的智慧與反思會留在這部 iPhone 上。';

  @override
  String get removeIcloudCloudData => '它們的 iCloud 副本會被移除，iCloud 同步也會關閉。';

  @override
  String get enableIcloudQuestion => '啟用 iCloud 同步？';

  @override
  String get enableIcloudData => '保留的智慧與反思會儲存在你的私人 iCloud 資料庫中，並在裝置間同步。';

  @override
  String get dailyRitualOnDevice => '每日儀式的時間仍會留在此裝置上。';

  @override
  String get removeUpper => '移除';

  @override
  String get saveUpper => '儲存';

  @override
  String get enableUpper => '啟用';

  @override
  String get icloudEnabling => '正在啟用…';

  @override
  String get icloudEnabled => '已啟用';

  @override
  String get icloudSyncing => '同步中';

  @override
  String get icloudUnavailable => 'iCloud 無法使用';

  @override
  String get icloudNeedsAttention => '需要留意';

  @override
  String get icloudNotEnabled => '未啟用';

  @override
  String get icloudRemovalStarting => '正在開始…';

  @override
  String get icloudRemovalCompleted => '已從 iCloud 移除。';

  @override
  String get icloudRemovalPending => '等待移除。iCloud 可用時 EAST. 會完成。';

  @override
  String get icloudRemovalIdle => '移除你的 iCloud 副本。';

  @override
  String get icloudRemovalNone => '沒有可移除的內容。';

  @override
  String get reflectionSaveFailed => '無法儲存反思，請再試一次。';

  @override
  String get reflectionAutosaveFailed => '無法儲存反思；你繼續書寫時會再試一次。';

  @override
  String get reflectionDeleteFailed => '無法刪除反思，請再試一次。';

  @override
  String remainingDurationHoursMinutes(int hours, int minutes) {
    return '還剩$hours小時$minutes分鐘';
  }

  @override
  String remainingDurationHoursOnly(int hours) {
    return '還剩$hours小時';
  }

  @override
  String remainingDurationMinutesOnly(int minutes) {
    return '還剩$minutes分鐘';
  }
}
