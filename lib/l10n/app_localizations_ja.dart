// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => '日々の知恵：EAST.';

  @override
  String get tapAnywhereToBegin => '画面をタップして始める。';

  @override
  String get tapWhenReady => '準備ができたらタップ。';

  @override
  String get pause => '立ち止まる。';

  @override
  String get feel => '感じる。';

  @override
  String get askFromYourHeart => '心から問いかける。';

  @override
  String get east => 'EAST.';

  @override
  String get kept => '残したもの';

  @override
  String get searchKept => '検索';

  @override
  String get clearSearch => '検索をクリア';

  @override
  String get noKeptSearchResults => '見つかりませんでした。';

  @override
  String get keptUpper => '残したもの';

  @override
  String get reflectedUpper => '内省';

  @override
  String get addReflectionUpper => '内省を記す';

  @override
  String get reflection => '内省';

  @override
  String get journal => '日記';

  @override
  String get settings => '設定';

  @override
  String get language => '言語';

  @override
  String get systemDefault => 'システム設定に従う';

  @override
  String get english => '英語';

  @override
  String languageSettingSemantics(Object value) {
    return '言語。現在の選択：$value。';
  }

  @override
  String languageOptionSemantics(Object language) {
    return '$language';
  }

  @override
  String get appearance => '外観';

  @override
  String get light => 'ライト';

  @override
  String get dark => 'ダーク';

  @override
  String appearanceSettingSemantics(Object value) {
    return '外観。現在の選択: $value。';
  }

  @override
  String appearanceOptionSemantics(Object option) {
    return '$option';
  }

  @override
  String get back => '戻る';

  @override
  String get delete => '削除';

  @override
  String get deleteUpper => '削除';

  @override
  String get cancel => 'キャンセル';

  @override
  String get close => '閉じる';

  @override
  String get done => '完了';

  @override
  String get retry => '再試行';

  @override
  String get tryAgainUpper => '再試行';

  @override
  String get skip => 'スキップ';

  @override
  String get addName => '名前を追加';

  @override
  String get changeName => '名前を変更';

  @override
  String get keptWisdoms => '残した知恵';

  @override
  String get addReflection => '内省を記す';

  @override
  String get deleteReflection => '内省を削除';

  @override
  String get reflectedEditReflection => '内省済み。内省を編集。';

  @override
  String addReflectionNumbered(Object number) {
    return '内省を記す、項目$number';
  }

  @override
  String openReflectionNumbered(Object number) {
    return '内省を開く、項目$number';
  }

  @override
  String get journalSemantic => '日記';

  @override
  String get keeper => 'Keeper';

  @override
  String get restorePurchases => '購入を復元';

  @override
  String get icloudSync => 'iCloud同期';

  @override
  String get removeFromIcloud => 'iCloudから削除';

  @override
  String get exportMyData => '自分のデータを書き出す';

  @override
  String get privacyPolicy => 'プライバシーポリシー';

  @override
  String get reachOut => 'お問い合わせ';

  @override
  String get eastProductions => 'EAST. Productions';

  @override
  String get supportCircle => '輪を支え、残るものを留める。';

  @override
  String get restoreBelongs => '自分のもとにあるべきものを復元する。';

  @override
  String get worldBeyondRitual => '儀式の向こうにある世界。';

  @override
  String get whatStaysPrivate => '内に留まるもの。';

  @override
  String get thoughtsAndQuestions => 'ご意見やご質問はこちら。';

  @override
  String get keepThisWisdom => 'この気づきを心に留める。';

  @override
  String get wisdomCouldNotBeKept => 'この気づきを残せませんでした。もう一度お試しください。';

  @override
  String get keptLimit => '残せる数の上限';

  @override
  String get freeUsersKeepLimit => '無料では知恵を3つまで残せます。';

  @override
  String get keepReflectingQuestion => '内省を続けますか？';

  @override
  String get reflectionLimitExplanation =>
      '3つの内省が含まれます。Keeperなら、残ったものをいくつでも書き留められます。';

  @override
  String get becomeKeeper => 'Keeperを始める';

  @override
  String get whoseJournal => 'これは誰の日記ですか？';

  @override
  String get journalNameExplanation => '日記の扉に、名前が静かに記されます。';

  @override
  String get notificationTitle => 'EAST.';

  @override
  String get notificationBody => '静けさの中で、何かが待っています。';

  @override
  String get journalPdfTitle => '日記。';

  @override
  String get dailyWisdomReady => '新しい知恵が届きました。';

  @override
  String get discoverTheObjects => 'オブジェクトを見る';

  @override
  String get enterTheCircle => '輪の中へ。';

  @override
  String get withinTheCircle => '輪の中に。';

  @override
  String get keeperActive => 'Keeperは有効です';

  @override
  String get oneTimePurchase => '一度限りの購入';

  @override
  String get askFrom => '心から';

  @override
  String get yourHeart => '問いかける。';

  @override
  String get longPressToShareWisdom => '長押しすると、この知恵を共有できます。';

  @override
  String get shareWisdom => '共有';

  @override
  String shareWisdomNumbered(int itemNumber) {
    return '知恵を共有、項目$itemNumber';
  }

  @override
  String get quietReminder => '静かなリマインダー';

  @override
  String get nothingHasStayedYet => 'まだ何も残っていません。';

  @override
  String get wisdomCouldNotBeRemoved => 'この知恵を削除できませんでした。もう一度お試しください。';

  @override
  String get reflectionPrompt => '今、何に気づいていますか？';

  @override
  String get returnWhenSilenceOpensAgain => '静けさがまた開いたら、戻ってきて。';

  @override
  String get reflectionPromptWhatRemains => '何が残りますか？';

  @override
  String get reflectionPromptWhatStayedWithYou => '何があなたの中に残りましたか？';

  @override
  String get reflectionPromptWhatBecameClearer => '何がはっきりしましたか？';

  @override
  String get reflectionPromptWhatFeelsDifferent => '何が違って感じられますか？';

  @override
  String get reflectionPromptCarryForward => '何を持ち続けたいですか？';

  @override
  String get deleteReflectionQuestion => '内省を削除しますか？';

  @override
  String get reflectionDeleteExplanation => 'この残した知恵から内省が削除されます。';

  @override
  String get removeKeptQuestion => '残したものから削除しますか？';

  @override
  String get keptDeleteExplanation => 'この知恵と内省が削除されます。';

  @override
  String get cancelUpper => 'キャンセル';

  @override
  String get continueAction => '続ける';

  @override
  String get onlyKeptOnThisDevice => 'このデバイスにのみ残されています。';

  @override
  String get yourName => 'あなたの名前';

  @override
  String get journalCouldNotBePrepared => '日記を準備できませんでした。もう一度お試しください。';

  @override
  String get takeItWithYou => '持っていく。';

  @override
  String get takeItWithYouKeeper => '持っていく。Keeperで利用できます。';

  @override
  String get availableWithKeeper => 'Keeperで利用できます。';

  @override
  String get opensKeeper => 'Keeperを開きます。';

  @override
  String get nameUpper => '名前';

  @override
  String get keeperPersistenceError =>
      'Keeperへのアクセスを保存できませんでした。「購入を復元」をお試しください。';

  @override
  String get purchaseUpdating => '購入状況を更新中です。設定から「購入を復元」をお試しください。';

  @override
  String get purchaseNotReady => '購入の準備がまだ整っていません。少ししてからもう一度お試しください。';

  @override
  String get restore => '復元';

  @override
  String get keepWhatStays => '残るものを残す。';

  @override
  String get addReflectionSemantics => '内省を記す';

  @override
  String get deleteSemantics => '削除';

  @override
  String get settingsClose => '閉じる';

  @override
  String get notificationPermissionTitle => '静かな再訪';

  @override
  String get notificationPermissionBody => '新しい知恵が届いたときに、お知らせしますか？';

  @override
  String get whereSilenceSpeaks => '静けさが語る場所。';

  @override
  String get preparing => '準備中…';

  @override
  String get exportKeptAndReflections => '残した知恵と内省を持っていく。';

  @override
  String get keeperAccessActive => 'Keeperは利用可能です';

  @override
  String keeperPurchaseInProgress(Object price) {
    return '輪の中へ、$price。購入手続き中。';
  }

  @override
  String keeperPurchaseOffering(Object price) {
    return '輪の中へ、1回限り$price';
  }

  @override
  String get keeperUnavailable => '輪の中へ、現在利用できません';

  @override
  String get keepWithoutLimit => '限りなく残す。';

  @override
  String get reflectWithoutLimit => '限りなく内省を記す。';

  @override
  String get takeJournalWithYou => '日記を持っていく。';

  @override
  String get keeperWidgetRitual => 'ウィジェットの中にも、儀式を。';

  @override
  String get addKeeperWidget => 'Keeperウィジェットを追加';

  @override
  String get keeperWidgetInteractive => 'iOS 17以降では、ウィジェットの中で儀式を始められます。';

  @override
  String get keeperWidgetOpensApp => 'iOS 15と16では、ウィジェットからEAST.が開きます。';

  @override
  String get keepEastAlive => 'EAST.を生かし続ける。';

  @override
  String get operationFailedRetry => '完了できませんでした。もう一度お試しください。';

  @override
  String get restoreRequestSent => '復元リクエストを送信しました。Keeperへのアクセスは自動的に更新されます。';

  @override
  String get restoreRecoveryPending =>
      '以前の復元を確認中です。Keeperへのアクセスは自動的に更新されます。再試行する前にEAST.を開き直してください。';

  @override
  String get opening => '開いています。';

  @override
  String get bootstrapRecovery => '起動に時間がかかっています。EAST.を閉じて、もう一度開いてください。';

  @override
  String get supportEmailSubject => 'EAST. サポート';

  @override
  String get removeIcloudLocalData => '残したものと内省は、このiPhoneに残ります。';

  @override
  String get removeIcloudCloudData => 'iCloud上のコピーは削除され、iCloud同期はオフになります。';

  @override
  String get enableIcloudQuestion => 'iCloud同期を有効にしますか？';

  @override
  String get enableIcloudData =>
      '残したものと内省は、プライベートなiCloudデータベースに保存され、デバイス間で同期されます。';

  @override
  String get dailyRitualOnDevice => '毎日のリチュアルの時間はこのデバイスに残ります。';

  @override
  String get removeUpper => '削除';

  @override
  String get saveUpper => '保存';

  @override
  String get enableUpper => '有効にする';

  @override
  String get icloudEnabling => '有効にしています…';

  @override
  String get icloudEnabled => '有効';

  @override
  String get icloudSyncing => '同期中';

  @override
  String get icloudUnavailable => 'iCloudを利用できません';

  @override
  String get icloudNeedsAttention => '確認が必要';

  @override
  String get icloudNotEnabled => '無効';

  @override
  String get icloudRemovalStarting => '開始しています…';

  @override
  String get icloudRemovalCompleted => 'iCloudから削除しました。';

  @override
  String get icloudRemovalPending => '削除待ちです。iCloudが利用可能になるとEAST.が完了します。';

  @override
  String get icloudRemovalIdle => 'iCloudのコピーを削除します。';

  @override
  String get icloudRemovalNone => '削除するものはありません。';

  @override
  String get reflectionSaveFailed => 'リフレクションを保存できませんでした。もう一度お試しください。';

  @override
  String get reflectionAutosaveFailed => 'リフレクションを保存できませんでした。書き続ける間にもう一度試します。';

  @override
  String get reflectionDeleteFailed => 'リフレクションを削除できませんでした。もう一度お試しください。';

  @override
  String remainingDurationHoursMinutes(int hours, int minutes) {
    return '残り$hours時間$minutes分';
  }

  @override
  String remainingDurationHoursOnly(int hours) {
    return '残り$hours時間';
  }

  @override
  String remainingDurationMinutesOnly(int minutes) {
    return '残り$minutes分';
  }

  @override
  String get keeperPreviewLabel => 'Keeperを少し体験';

  @override
  String get keeperWidgetTab => 'ウィジェット';

  @override
  String get keeperPreviewExample => '表示例';

  @override
  String get keeperPreviewReflection => '今日は、急がずに進みたい。';

  @override
  String get keeperDailyRitual => 'Keeperでも、そうでなくても、知恵は24時間にひとつ。';

  @override
  String get keeperWidgetStepOne => 'ホーム画面の何もない場所を長押しします。';

  @override
  String get keeperWidgetStepTwo =>
      '「編集」から「ウィジェットを追加」をタップします。以前のiOSでは「＋」ボタンをタップします。';

  @override
  String get keeperWidgetStepThree =>
      'EAST.を探し、Keeperの儀式ウィジェットを選んで「ウィジェットを追加」をタップします。';

  @override
  String get reflectionSaved => '保存しました';

  @override
  String get reflectionSaving => '保存中…';

  @override
  String get reflectionCopyText => '文章をコピー';

  @override
  String get reflectionCopied => 'コピーしました';

  @override
  String get reflectionAddThought => '新しい思いを添える';

  @override
  String get reflectionRevisitPrompt => '今日は、この言葉をどう受けとる？';

  @override
  String get reflectionEarlier => '以前の思い';

  @override
  String get reflectionOverTime => '時を重ねて';

  @override
  String get reflectionHistoryDeleteExplanation => 'この知恵に添えた思いがすべて削除されます。';

  @override
  String get reflectionRecoveryMessage => '文章はまだ保存されていません。';

  @override
  String get settingsEveryday => '毎日の設定';

  @override
  String get settingsYourWriting => 'あなたの言葉';

  @override
  String get settingsAbout => 'EAST.について';

  @override
  String get writingLock => '文章のロック';

  @override
  String get writingLockDescription =>
      'Face ID、Touch ID、またはデバイスのパスコードで、残したもの、内省、日記を開きます。';

  @override
  String get writingLockFootnote =>
      '毎日の儀式はそのまま始められます。アプリを離れると、プライベートな文章は再びロックされます。';

  @override
  String get writingLockTitle => 'あなたの言葉は、あなたのもの。';

  @override
  String get writingLockPrompt => '認証して、プライベートな文章を開きます。';

  @override
  String get writingLockUnlock => 'ロックを解除';

  @override
  String get writingLockChecking => '認証中…';

  @override
  String get writingLockReason => 'プライベートな文章を開きます。';

  @override
  String get writingLockUnavailable =>
      '認証を利用できません。デバイスのパスコードとFace IDまたはTouch IDの設定を確認してください。';

  @override
  String get writingLockToggleReason => 'プライベートな文章のロック設定を変更します。';

  @override
  String get writingLockOn => 'オン';

  @override
  String get writingLockOff => 'オフ';

  @override
  String get privacyPreview => 'アプリスイッチャーでは文章が非表示になります。';

  @override
  String get settingsAboutDescription => '一日に一度、自分に戻るための場所。';

  @override
  String get dailyRitualICloudRequired => '新しい知恵を開くには、iCloudにサインインしてください。';

  @override
  String get dailyRitualConnectionRequired => '新しい知恵を開くには、インターネットに接続してください。';

  @override
  String get dailyRitualUnavailable => '今は今日の知恵を開けません。もう一度お試しください。';

  @override
  String get dailyRitualAccountNote =>
      'iCloudアカウントごとに、24時間に一つの知恵。新しい知恵を開くにはインターネット接続が必要です。保存した文章はオフラインでも読めます。';

  @override
  String get dailyRitualPreviousWisdom => '前の知恵';
}
