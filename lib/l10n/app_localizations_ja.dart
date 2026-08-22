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
  String get journalSemantic => '日記';

  @override
  String get keeper => '残す';

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
  String get becomeKeeper => '残すをひらく';

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
  String get askFrom => '心から';

  @override
  String get yourHeart => '問いかける。';

  @override
  String get longPressToShareWisdom => '長押しすると、この知恵を共有できます。';

  @override
  String get nothingHasStayedYet => 'まだ何も残っていません。';

  @override
  String get wisdomCouldNotBeRemoved => 'この知恵を削除できませんでした。もう一度お試しください。';

  @override
  String get reflectionPrompt => '今、何に気づいていますか？';

  @override
  String get deleteReflectionQuestion => '内省を削除しますか？';

  @override
  String get reflectionDeleteExplanation => 'この残した知恵から内省が削除されます。';

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
  String get takeItWithYouKeeper => '持っていく。残すで利用できます。';

  @override
  String get availableWithKeeper => '残すで利用できます。';

  @override
  String get nameUpper => '名前';

  @override
  String get keeperPersistenceError => '「残す」へのアクセスを保存できませんでした。「購入を復元」をお試しください。';

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
  String get keeperAccessActive => '「残す」は利用可能です';

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
  String get keepEastAlive => 'EAST.を生かし続ける。';
}
