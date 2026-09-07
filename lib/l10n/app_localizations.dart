import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_nl.dart';
import 'app_localizations_pl.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_th.dart';
import 'app_localizations_tr.dart';
import 'app_localizations_vi.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
    Locale('ja'),
    Locale('ko'),
    Locale('nl'),
    Locale('pl'),
    Locale('pt'),
    Locale('pt', 'BR'),
    Locale('th'),
    Locale('tr'),
    Locale('vi'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily Wisdom: EAST.'**
  String get appTitle;

  /// No description provided for @tapAnywhereToBegin.
  ///
  /// In en, this message translates to:
  /// **'Tap anywhere to begin.'**
  String get tapAnywhereToBegin;

  /// No description provided for @tapWhenReady.
  ///
  /// In en, this message translates to:
  /// **'Tap when you’re ready.'**
  String get tapWhenReady;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause.'**
  String get pause;

  /// No description provided for @feel.
  ///
  /// In en, this message translates to:
  /// **'Feel.'**
  String get feel;

  /// No description provided for @askFromYourHeart.
  ///
  /// In en, this message translates to:
  /// **'Ask from your heart.'**
  String get askFromYourHeart;

  /// No description provided for @east.
  ///
  /// In en, this message translates to:
  /// **'EAST.'**
  String get east;

  /// No description provided for @kept.
  ///
  /// In en, this message translates to:
  /// **'Kept'**
  String get kept;

  /// No description provided for @searchKept.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchKept;

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @noKeptSearchResults.
  ///
  /// In en, this message translates to:
  /// **'Nothing found.'**
  String get noKeptSearchResults;

  /// No description provided for @keptUpper.
  ///
  /// In en, this message translates to:
  /// **'KEPT'**
  String get keptUpper;

  /// No description provided for @reflectedUpper.
  ///
  /// In en, this message translates to:
  /// **'REFLECTED'**
  String get reflectedUpper;

  /// No description provided for @addReflectionUpper.
  ///
  /// In en, this message translates to:
  /// **'ADD REFLECTION'**
  String get addReflectionUpper;

  /// No description provided for @reflection.
  ///
  /// In en, this message translates to:
  /// **'Reflection'**
  String get reflection;

  /// No description provided for @journal.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get journal;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get systemDefault;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @languageSettingSemantics.
  ///
  /// In en, this message translates to:
  /// **'Language. Current selection: {value}.'**
  String languageSettingSemantics(Object value);

  /// No description provided for @languageOptionSemantics.
  ///
  /// In en, this message translates to:
  /// **'{language}'**
  String languageOptionSemantics(Object language);

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @appearanceSettingSemantics.
  ///
  /// In en, this message translates to:
  /// **'Appearance. Current selection: {value}.'**
  String appearanceSettingSemantics(Object value);

  /// No description provided for @appearanceOptionSemantics.
  ///
  /// In en, this message translates to:
  /// **'{option}'**
  String appearanceOptionSemantics(Object option);

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteUpper.
  ///
  /// In en, this message translates to:
  /// **'DELETE'**
  String get deleteUpper;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @tryAgainUpper.
  ///
  /// In en, this message translates to:
  /// **'TRY AGAIN'**
  String get tryAgainUpper;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @addName.
  ///
  /// In en, this message translates to:
  /// **'Add name'**
  String get addName;

  /// No description provided for @changeName.
  ///
  /// In en, this message translates to:
  /// **'Change name'**
  String get changeName;

  /// No description provided for @keptWisdoms.
  ///
  /// In en, this message translates to:
  /// **'Kept wisdoms'**
  String get keptWisdoms;

  /// No description provided for @addReflection.
  ///
  /// In en, this message translates to:
  /// **'Add reflection'**
  String get addReflection;

  /// No description provided for @deleteReflection.
  ///
  /// In en, this message translates to:
  /// **'Delete reflection'**
  String get deleteReflection;

  /// No description provided for @reflectedEditReflection.
  ///
  /// In en, this message translates to:
  /// **'REFLECTED. Edit reflection.'**
  String get reflectedEditReflection;

  /// No description provided for @addReflectionNumbered.
  ///
  /// In en, this message translates to:
  /// **'Add Reflection, item {number}'**
  String addReflectionNumbered(Object number);

  /// No description provided for @openReflectionNumbered.
  ///
  /// In en, this message translates to:
  /// **'Open Reflection, item {number}'**
  String openReflectionNumbered(Object number);

  /// No description provided for @journalSemantic.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get journalSemantic;

  /// No description provided for @keeper.
  ///
  /// In en, this message translates to:
  /// **'Keeper'**
  String get keeper;

  /// No description provided for @restorePurchases.
  ///
  /// In en, this message translates to:
  /// **'Restore Purchases'**
  String get restorePurchases;

  /// No description provided for @icloudSync.
  ///
  /// In en, this message translates to:
  /// **'iCloud Sync'**
  String get icloudSync;

  /// No description provided for @removeFromIcloud.
  ///
  /// In en, this message translates to:
  /// **'Remove from iCloud'**
  String get removeFromIcloud;

  /// No description provided for @exportMyData.
  ///
  /// In en, this message translates to:
  /// **'Export My Data'**
  String get exportMyData;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @reachOut.
  ///
  /// In en, this message translates to:
  /// **'Reach Out'**
  String get reachOut;

  /// No description provided for @eastProductions.
  ///
  /// In en, this message translates to:
  /// **'EAST. Productions'**
  String get eastProductions;

  /// No description provided for @supportCircle.
  ///
  /// In en, this message translates to:
  /// **'Support the circle, keep what stays.'**
  String get supportCircle;

  /// No description provided for @restoreBelongs.
  ///
  /// In en, this message translates to:
  /// **'Restore what belongs with you.'**
  String get restoreBelongs;

  /// No description provided for @worldBeyondRitual.
  ///
  /// In en, this message translates to:
  /// **'The world beyond the ritual.'**
  String get worldBeyondRitual;

  /// No description provided for @whatStaysPrivate.
  ///
  /// In en, this message translates to:
  /// **'What stays private.'**
  String get whatStaysPrivate;

  /// No description provided for @thoughtsAndQuestions.
  ///
  /// In en, this message translates to:
  /// **'For thoughts and questions.'**
  String get thoughtsAndQuestions;

  /// No description provided for @keepThisWisdom.
  ///
  /// In en, this message translates to:
  /// **'Keep this wisdom.'**
  String get keepThisWisdom;

  /// No description provided for @wisdomCouldNotBeKept.
  ///
  /// In en, this message translates to:
  /// **'Wisdom could not be kept. Please try again.'**
  String get wisdomCouldNotBeKept;

  /// No description provided for @keptLimit.
  ///
  /// In en, this message translates to:
  /// **'Kept Limit'**
  String get keptLimit;

  /// No description provided for @freeUsersKeepLimit.
  ///
  /// In en, this message translates to:
  /// **'Free users can keep up to 3 wisdoms.'**
  String get freeUsersKeepLimit;

  /// No description provided for @keepReflectingQuestion.
  ///
  /// In en, this message translates to:
  /// **'Keep reflecting?'**
  String get keepReflectingQuestion;

  /// No description provided for @reflectionLimitExplanation.
  ///
  /// In en, this message translates to:
  /// **'Three Reflections are included. Keeper opens unlimited space for what stays.'**
  String get reflectionLimitExplanation;

  /// No description provided for @becomeKeeper.
  ///
  /// In en, this message translates to:
  /// **'Become a Keeper'**
  String get becomeKeeper;

  /// No description provided for @whoseJournal.
  ///
  /// In en, this message translates to:
  /// **'Whose journal is this?'**
  String get whoseJournal;

  /// No description provided for @journalNameExplanation.
  ///
  /// In en, this message translates to:
  /// **'A name appears quietly on the title page of your Journal.'**
  String get journalNameExplanation;

  /// No description provided for @notificationTitle.
  ///
  /// In en, this message translates to:
  /// **'EAST.'**
  String get notificationTitle;

  /// No description provided for @notificationBody.
  ///
  /// In en, this message translates to:
  /// **'Something waits in silence.'**
  String get notificationBody;

  /// No description provided for @journalPdfTitle.
  ///
  /// In en, this message translates to:
  /// **'Journal.'**
  String get journalPdfTitle;

  /// No description provided for @dailyWisdomReady.
  ///
  /// In en, this message translates to:
  /// **'A new wisdom is ready.'**
  String get dailyWisdomReady;

  /// No description provided for @discoverTheObjects.
  ///
  /// In en, this message translates to:
  /// **'DISCOVER THE OBJECTS'**
  String get discoverTheObjects;

  /// No description provided for @enterTheCircle.
  ///
  /// In en, this message translates to:
  /// **'Enter the Circle'**
  String get enterTheCircle;

  /// No description provided for @withinTheCircle.
  ///
  /// In en, this message translates to:
  /// **'Within the Circle'**
  String get withinTheCircle;

  /// No description provided for @keeperActive.
  ///
  /// In en, this message translates to:
  /// **'Keeper active'**
  String get keeperActive;

  /// No description provided for @oneTimePurchase.
  ///
  /// In en, this message translates to:
  /// **'One-time purchase'**
  String get oneTimePurchase;

  /// No description provided for @askFrom.
  ///
  /// In en, this message translates to:
  /// **'Ask from'**
  String get askFrom;

  /// No description provided for @yourHeart.
  ///
  /// In en, this message translates to:
  /// **'your heart.'**
  String get yourHeart;

  /// No description provided for @longPressToShareWisdom.
  ///
  /// In en, this message translates to:
  /// **'Long press to share this wisdom.'**
  String get longPressToShareWisdom;

  /// No description provided for @shareWisdom.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareWisdom;

  /// No description provided for @shareWisdomNumbered.
  ///
  /// In en, this message translates to:
  /// **'Share wisdom, item {itemNumber}'**
  String shareWisdomNumbered(int itemNumber);

  /// No description provided for @quietReminder.
  ///
  /// In en, this message translates to:
  /// **'Quiet Reminder'**
  String get quietReminder;

  /// No description provided for @nothingHasStayedYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing has stayed yet.'**
  String get nothingHasStayedYet;

  /// No description provided for @wisdomCouldNotBeRemoved.
  ///
  /// In en, this message translates to:
  /// **'This wisdom could not be removed. Please try again.'**
  String get wisdomCouldNotBeRemoved;

  /// No description provided for @reflectionPrompt.
  ///
  /// In en, this message translates to:
  /// **'What are you noticing now?'**
  String get reflectionPrompt;

  /// No description provided for @returnWhenSilenceOpensAgain.
  ///
  /// In en, this message translates to:
  /// **'Return when the silence opens again.'**
  String get returnWhenSilenceOpensAgain;

  /// No description provided for @reflectionPromptWhatRemains.
  ///
  /// In en, this message translates to:
  /// **'What remains?'**
  String get reflectionPromptWhatRemains;

  /// No description provided for @reflectionPromptWhatStayedWithYou.
  ///
  /// In en, this message translates to:
  /// **'What stayed with you?'**
  String get reflectionPromptWhatStayedWithYou;

  /// No description provided for @reflectionPromptWhatBecameClearer.
  ///
  /// In en, this message translates to:
  /// **'What became clearer?'**
  String get reflectionPromptWhatBecameClearer;

  /// No description provided for @reflectionPromptWhatFeelsDifferent.
  ///
  /// In en, this message translates to:
  /// **'What feels different?'**
  String get reflectionPromptWhatFeelsDifferent;

  /// No description provided for @reflectionPromptCarryForward.
  ///
  /// In en, this message translates to:
  /// **'What would you like to carry forward?'**
  String get reflectionPromptCarryForward;

  /// No description provided for @deleteReflectionQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete Reflection?'**
  String get deleteReflectionQuestion;

  /// No description provided for @reflectionDeleteExplanation.
  ///
  /// In en, this message translates to:
  /// **'The reflection will be removed from this kept wisdom.'**
  String get reflectionDeleteExplanation;

  /// No description provided for @removeKeptQuestion.
  ///
  /// In en, this message translates to:
  /// **'Remove from Kept?'**
  String get removeKeptQuestion;

  /// No description provided for @keptDeleteExplanation.
  ///
  /// In en, this message translates to:
  /// **'This wisdom and its Reflection will be removed.'**
  String get keptDeleteExplanation;

  /// No description provided for @cancelUpper.
  ///
  /// In en, this message translates to:
  /// **'CANCEL'**
  String get cancelUpper;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @onlyKeptOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Only kept on this device.'**
  String get onlyKeptOnThisDevice;

  /// No description provided for @yourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourName;

  /// No description provided for @journalCouldNotBePrepared.
  ///
  /// In en, this message translates to:
  /// **'Journal could not be prepared. Please try again.'**
  String get journalCouldNotBePrepared;

  /// No description provided for @takeItWithYou.
  ///
  /// In en, this message translates to:
  /// **'Take it with you.'**
  String get takeItWithYou;

  /// No description provided for @takeItWithYouKeeper.
  ///
  /// In en, this message translates to:
  /// **'Take it with you. Available with Keeper.'**
  String get takeItWithYouKeeper;

  /// No description provided for @availableWithKeeper.
  ///
  /// In en, this message translates to:
  /// **'Available with Keeper.'**
  String get availableWithKeeper;

  /// No description provided for @opensKeeper.
  ///
  /// In en, this message translates to:
  /// **'Opens Keeper.'**
  String get opensKeeper;

  /// No description provided for @nameUpper.
  ///
  /// In en, this message translates to:
  /// **'NAME'**
  String get nameUpper;

  /// No description provided for @keeperPersistenceError.
  ///
  /// In en, this message translates to:
  /// **'Keeper access could not be saved. Please try Restore Purchases.'**
  String get keeperPersistenceError;

  /// No description provided for @purchaseUpdating.
  ///
  /// In en, this message translates to:
  /// **'Purchase status is still updating. Please use Restore Purchases in Settings.'**
  String get purchaseUpdating;

  /// No description provided for @purchaseNotReady.
  ///
  /// In en, this message translates to:
  /// **'Purchase is not ready yet. Please try again shortly.'**
  String get purchaseNotReady;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @keepWhatStays.
  ///
  /// In en, this message translates to:
  /// **'Keep what stays.'**
  String get keepWhatStays;

  /// No description provided for @addReflectionSemantics.
  ///
  /// In en, this message translates to:
  /// **'Add reflection'**
  String get addReflectionSemantics;

  /// No description provided for @deleteSemantics.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteSemantics;

  /// No description provided for @settingsClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get settingsClose;

  /// No description provided for @notificationPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'A quiet return'**
  String get notificationPermissionTitle;

  /// No description provided for @notificationPermissionBody.
  ///
  /// In en, this message translates to:
  /// **'Would you like to know when a new wisdom is ready?'**
  String get notificationPermissionBody;

  /// No description provided for @whereSilenceSpeaks.
  ///
  /// In en, this message translates to:
  /// **'Where silence speaks.'**
  String get whereSilenceSpeaks;

  /// No description provided for @preparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get preparing;

  /// No description provided for @exportKeptAndReflections.
  ///
  /// In en, this message translates to:
  /// **'Take your Kept wisdoms and Reflections with you.'**
  String get exportKeptAndReflections;

  /// No description provided for @keeperAccessActive.
  ///
  /// In en, this message translates to:
  /// **'Keeper access active'**
  String get keeperAccessActive;

  /// No description provided for @keeperPurchaseInProgress.
  ///
  /// In en, this message translates to:
  /// **'Enter the Circle, {price}. Purchase in progress.'**
  String keeperPurchaseInProgress(Object price);

  /// No description provided for @keeperPurchaseOffering.
  ///
  /// In en, this message translates to:
  /// **'Enter the Circle, {price}, one-time purchase'**
  String keeperPurchaseOffering(Object price);

  /// No description provided for @keeperUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Enter the Circle, temporarily unavailable'**
  String get keeperUnavailable;

  /// No description provided for @keepWithoutLimit.
  ///
  /// In en, this message translates to:
  /// **'Keep without limit.'**
  String get keepWithoutLimit;

  /// No description provided for @reflectWithoutLimit.
  ///
  /// In en, this message translates to:
  /// **'Reflect without limit.'**
  String get reflectWithoutLimit;

  /// No description provided for @takeJournalWithYou.
  ///
  /// In en, this message translates to:
  /// **'Take your Journal with you.'**
  String get takeJournalWithYou;

  /// No description provided for @keeperWidgetRitual.
  ///
  /// In en, this message translates to:
  /// **'The ritual, within your widget.'**
  String get keeperWidgetRitual;

  /// No description provided for @addKeeperWidget.
  ///
  /// In en, this message translates to:
  /// **'Add the Keeper Widget'**
  String get addKeeperWidget;

  /// No description provided for @keeperWidgetInteractive.
  ///
  /// In en, this message translates to:
  /// **'On iOS 17 or later, begin the ritual in the widget.'**
  String get keeperWidgetInteractive;

  /// No description provided for @keeperWidgetOpensApp.
  ///
  /// In en, this message translates to:
  /// **'On iOS 15 and 16, the widget opens EAST.'**
  String get keeperWidgetOpensApp;

  /// No description provided for @keepEastAlive.
  ///
  /// In en, this message translates to:
  /// **'Keep EAST. alive.'**
  String get keepEastAlive;

  /// No description provided for @operationFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'This could not be completed. Please try again.'**
  String get operationFailedRetry;

  /// No description provided for @restoreRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Restore request sent. Keeper access will update automatically.'**
  String get restoreRequestSent;

  /// No description provided for @restoreRecoveryPending.
  ///
  /// In en, this message translates to:
  /// **'A previous restore is still being reconciled. Keeper access will update automatically; reopen EAST. before trying again.'**
  String get restoreRecoveryPending;

  /// No description provided for @opening.
  ///
  /// In en, this message translates to:
  /// **'Opening.'**
  String get opening;

  /// No description provided for @bootstrapRecovery.
  ///
  /// In en, this message translates to:
  /// **'Opening is taking longer than expected. Please close EAST. and open it again.'**
  String get bootstrapRecovery;

  /// No description provided for @supportEmailSubject.
  ///
  /// In en, this message translates to:
  /// **'EAST. Support'**
  String get supportEmailSubject;

  /// No description provided for @removeIcloudLocalData.
  ///
  /// In en, this message translates to:
  /// **'Your Kept wisdoms and Reflections will remain on this iPhone.'**
  String get removeIcloudLocalData;

  /// No description provided for @removeIcloudCloudData.
  ///
  /// In en, this message translates to:
  /// **'Their iCloud copies will be removed, and iCloud Sync will turn off.'**
  String get removeIcloudCloudData;

  /// No description provided for @enableIcloudQuestion.
  ///
  /// In en, this message translates to:
  /// **'Enable iCloud Sync?'**
  String get enableIcloudQuestion;

  /// No description provided for @enableIcloudData.
  ///
  /// In en, this message translates to:
  /// **'Your Kept wisdoms and Reflections will be stored in your private iCloud database and kept in sync across your devices.'**
  String get enableIcloudData;

  /// No description provided for @dailyRitualOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Your daily ritual timing stays on this device.'**
  String get dailyRitualOnDevice;

  /// No description provided for @removeUpper.
  ///
  /// In en, this message translates to:
  /// **'REMOVE'**
  String get removeUpper;

  /// No description provided for @saveUpper.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get saveUpper;

  /// No description provided for @enableUpper.
  ///
  /// In en, this message translates to:
  /// **'ENABLE'**
  String get enableUpper;

  /// No description provided for @icloudEnabling.
  ///
  /// In en, this message translates to:
  /// **'Enabling…'**
  String get icloudEnabling;

  /// No description provided for @icloudEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get icloudEnabled;

  /// No description provided for @icloudSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get icloudSyncing;

  /// No description provided for @icloudUnavailable.
  ///
  /// In en, this message translates to:
  /// **'iCloud unavailable'**
  String get icloudUnavailable;

  /// No description provided for @icloudNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get icloudNeedsAttention;

  /// No description provided for @icloudNotEnabled.
  ///
  /// In en, this message translates to:
  /// **'Not enabled'**
  String get icloudNotEnabled;

  /// No description provided for @icloudRemovalStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get icloudRemovalStarting;

  /// No description provided for @icloudRemovalCompleted.
  ///
  /// In en, this message translates to:
  /// **'Removed from iCloud.'**
  String get icloudRemovalCompleted;

  /// No description provided for @icloudRemovalPending.
  ///
  /// In en, this message translates to:
  /// **'Removal pending. EAST. will finish when iCloud is available.'**
  String get icloudRemovalPending;

  /// No description provided for @icloudRemovalIdle.
  ///
  /// In en, this message translates to:
  /// **'Remove your iCloud copies.'**
  String get icloudRemovalIdle;

  /// No description provided for @icloudRemovalNone.
  ///
  /// In en, this message translates to:
  /// **'Nothing to remove.'**
  String get icloudRemovalNone;

  /// No description provided for @reflectionSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Reflection could not be saved. Please try again.'**
  String get reflectionSaveFailed;

  /// No description provided for @reflectionAutosaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Reflection could not be saved. It will try again as you keep writing.'**
  String get reflectionAutosaveFailed;

  /// No description provided for @reflectionDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Reflection could not be deleted. Please try again.'**
  String get reflectionDeleteFailed;

  /// Accessibility duration when both hours and minutes remain.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, one{1 hour} other{{hours} hours}} {minutes, plural, one{1 minute} other{{minutes} minutes}} remaining'**
  String remainingDurationHoursMinutes(int hours, int minutes);

  /// Accessibility duration when whole hours remain and minutes are zero.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, one{1 hour remaining} other{{hours} hours remaining}}'**
  String remainingDurationHoursOnly(int hours);

  /// Accessibility duration when fewer than 60 minutes remain.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, one{1 minute remaining} other{{minutes} minutes remaining}}'**
  String remainingDurationMinutesOnly(int minutes);

  /// No description provided for @keeperPreviewLabel.
  ///
  /// In en, this message translates to:
  /// **'A glimpse of Keeper'**
  String get keeperPreviewLabel;

  /// No description provided for @keeperWidgetTab.
  ///
  /// In en, this message translates to:
  /// **'Widget'**
  String get keeperWidgetTab;

  /// No description provided for @keeperPreviewExample.
  ///
  /// In en, this message translates to:
  /// **'Example'**
  String get keeperPreviewExample;

  /// No description provided for @keeperPreviewReflection.
  ///
  /// In en, this message translates to:
  /// **'Today, I want to move without rushing.'**
  String get keeperPreviewReflection;

  /// No description provided for @keeperDailyRitual.
  ///
  /// In en, this message translates to:
  /// **'One wisdom every 24 hours, with or without Keeper.'**
  String get keeperDailyRitual;

  /// No description provided for @keeperWidgetStepOne.
  ///
  /// In en, this message translates to:
  /// **'Touch and hold an empty area of your Home Screen.'**
  String get keeperWidgetStepOne;

  /// No description provided for @keeperWidgetStepTwo.
  ///
  /// In en, this message translates to:
  /// **'Tap Edit, then Add Widget. On earlier iOS versions, tap the + button.'**
  String get keeperWidgetStepTwo;

  /// No description provided for @keeperWidgetStepThree.
  ///
  /// In en, this message translates to:
  /// **'Find EAST., choose the Keeper Ritual widget, then tap Add Widget.'**
  String get keeperWidgetStepThree;

  /// No description provided for @reflectionSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get reflectionSaved;

  /// No description provided for @reflectionSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get reflectionSaving;

  /// No description provided for @reflectionCopyText.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get reflectionCopyText;

  /// No description provided for @reflectionCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get reflectionCopied;

  /// No description provided for @reflectionAddThought.
  ///
  /// In en, this message translates to:
  /// **'Add a new thought'**
  String get reflectionAddThought;

  /// No description provided for @reflectionRevisitPrompt.
  ///
  /// In en, this message translates to:
  /// **'How do I read this today?'**
  String get reflectionRevisitPrompt;

  /// No description provided for @reflectionEarlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get reflectionEarlier;

  /// No description provided for @reflectionOverTime.
  ///
  /// In en, this message translates to:
  /// **'Over time'**
  String get reflectionOverTime;

  /// No description provided for @reflectionHistoryDeleteExplanation.
  ///
  /// In en, this message translates to:
  /// **'All thoughts attached to this kept wisdom will be removed.'**
  String get reflectionHistoryDeleteExplanation;

  /// No description provided for @reflectionRecoveryMessage.
  ///
  /// In en, this message translates to:
  /// **'Your writing has not been saved yet.'**
  String get reflectionRecoveryMessage;

  /// Private writing protection or Settings navigation.
  ///
  /// In en, this message translates to:
  /// **'Everyday preferences'**
  String get settingsEveryday;

  /// Private writing protection or Settings navigation.
  ///
  /// In en, this message translates to:
  /// **'Your writing'**
  String get settingsYourWriting;

  /// Private writing protection or Settings navigation.
  ///
  /// In en, this message translates to:
  /// **'About EAST.'**
  String get settingsAbout;

  /// Private writing protection or Settings navigation.
  ///
  /// In en, this message translates to:
  /// **'Writing lock'**
  String get writingLock;

  /// Private writing protection or Settings navigation.
  ///
  /// In en, this message translates to:
  /// **'Open Kept, Reflection and Journal with Face ID, Touch ID or your device passcode.'**
  String get writingLockDescription;

  /// Private writing protection or Settings navigation.
  ///
  /// In en, this message translates to:
  /// **'Your daily ritual stays open. Your private writing locks again when you leave the app.'**
  String get writingLockFootnote;

  /// Private writing protection or Settings navigation.
  ///
  /// In en, this message translates to:
  /// **'Your words belong to you.'**
  String get writingLockTitle;

  /// Private writing protection or Settings navigation.
  ///
  /// In en, this message translates to:
  /// **'Authenticate to open your private writing.'**
  String get writingLockPrompt;

  /// Private writing protection or Settings navigation.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get writingLockUnlock;

  /// Private writing protection or Settings navigation.
  ///
  /// In en, this message translates to:
  /// **'Authenticating…'**
  String get writingLockChecking;

  /// Private writing protection or Settings navigation.
  ///
  /// In en, this message translates to:
  /// **'Open your private writing.'**
  String get writingLockReason;

  /// Private writing protection or Settings navigation.
  ///
  /// In en, this message translates to:
  /// **'Authentication is unavailable. Check your device passcode and Face ID or Touch ID settings.'**
  String get writingLockUnavailable;

  /// Private writing protection or Settings navigation.
  ///
  /// In en, this message translates to:
  /// **'Change the lock for your private writing.'**
  String get writingLockToggleReason;

  /// Private writing protection or Settings navigation.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get writingLockOn;

  /// Private writing protection or Settings navigation.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get writingLockOff;

  /// Private writing protection or Settings navigation.
  ///
  /// In en, this message translates to:
  /// **'Your writing is hidden in the app switcher.'**
  String get privacyPreview;

  /// Private writing protection or Settings navigation.
  ///
  /// In en, this message translates to:
  /// **'A place to return to yourself, once a day.'**
  String get settingsAboutDescription;

  /// No description provided for @dailyRitualICloudRequired.
  ///
  /// In en, this message translates to:
  /// **'Sign in to iCloud to open a new wisdom.'**
  String get dailyRitualICloudRequired;

  /// No description provided for @dailyRitualConnectionRequired.
  ///
  /// In en, this message translates to:
  /// **'Connect to the internet to open a new wisdom.'**
  String get dailyRitualConnectionRequired;

  /// No description provided for @dailyRitualUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Your daily wisdom is unavailable right now. Please try again.'**
  String get dailyRitualUnavailable;

  /// No description provided for @dailyRitualAccountNote.
  ///
  /// In en, this message translates to:
  /// **'One wisdom per iCloud account every 24 hours. A new wisdom needs an internet connection. Your saved writing remains available offline.'**
  String get dailyRitualAccountNote;

  /// No description provided for @dailyRitualPreviousWisdom.
  ///
  /// In en, this message translates to:
  /// **'Previous wisdom'**
  String get dailyRitualPreviousWisdom;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'ar',
        'de',
        'en',
        'es',
        'fr',
        'it',
        'ja',
        'ko',
        'nl',
        'pl',
        'pt',
        'th',
        'tr',
        'vi',
        'zh'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'pt':
      {
        switch (locale.countryCode) {
          case 'BR':
            return AppLocalizationsPtBr();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'nl':
      return AppLocalizationsNl();
    case 'pl':
      return AppLocalizationsPl();
    case 'pt':
      return AppLocalizationsPt();
    case 'th':
      return AppLocalizationsTh();
    case 'tr':
      return AppLocalizationsTr();
    case 'vi':
      return AppLocalizationsVi();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
