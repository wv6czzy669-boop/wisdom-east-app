// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Sagesse quotidienne : EAST.';

  @override
  String get tapAnywhereToBegin => 'Touche l’écran pour commencer.';

  @override
  String get tapWhenReady => 'Touche l’écran quand tu es prêt.';

  @override
  String get pause => 'Pause.';

  @override
  String get feel => 'Ressens.';

  @override
  String get askFromYourHeart => 'Demande avec le cœur.';

  @override
  String get east => 'EAST.';

  @override
  String get kept => 'Ce qui reste';

  @override
  String get searchKept => 'Rechercher';

  @override
  String get clearSearch => 'Effacer la recherche';

  @override
  String get noKeptSearchResults => 'Aucun résultat.';

  @override
  String get keptUpper => 'CE QUI RESTE';

  @override
  String get reflectedUpper => 'RÉFLEXION';

  @override
  String get addReflectionUpper => 'AJOUTER UNE RÉFLEXION';

  @override
  String get reflection => 'Réflexion';

  @override
  String get journal => 'Carnet';

  @override
  String get settings => 'Réglages';

  @override
  String get language => 'Langue';

  @override
  String get systemDefault => 'Selon le système';

  @override
  String get english => 'Anglais';

  @override
  String languageSettingSemantics(Object value) {
    return 'Langue. Sélection actuelle : $value.';
  }

  @override
  String languageOptionSemantics(Object language) {
    return '$language';
  }

  @override
  String get appearance => 'Apparence';

  @override
  String get light => 'Clair';

  @override
  String get dark => 'Sombre';

  @override
  String appearanceSettingSemantics(Object value) {
    return 'Apparence. Sélection actuelle : $value.';
  }

  @override
  String appearanceOptionSemantics(Object option) {
    return '$option';
  }

  @override
  String get back => 'Retour';

  @override
  String get delete => 'Supprimer';

  @override
  String get deleteUpper => 'SUPPRIMER';

  @override
  String get cancel => 'Annuler';

  @override
  String get close => 'Fermer';

  @override
  String get done => 'Terminé';

  @override
  String get retry => 'Réessayer';

  @override
  String get tryAgainUpper => 'RÉESSAYER';

  @override
  String get skip => 'Passer';

  @override
  String get addName => 'Ajouter un nom';

  @override
  String get changeName => 'Modifier le nom';

  @override
  String get keptWisdoms => 'Sagesses gardées';

  @override
  String get addReflection => 'Ajouter une réflexion';

  @override
  String get deleteReflection => 'Supprimer la réflexion';

  @override
  String get reflectedEditReflection => 'RÉFLEXION. Modifier la réflexion.';

  @override
  String addReflectionNumbered(Object number) {
    return 'Ajouter une réflexion, élément $number';
  }

  @override
  String openReflectionNumbered(Object number) {
    return 'Ouvrir la réflexion, élément $number';
  }

  @override
  String get journalSemantic => 'Carnet';

  @override
  String get keeper => 'Keeper';

  @override
  String get restorePurchases => 'Restaurer les achats';

  @override
  String get icloudSync => 'Synchronisation iCloud';

  @override
  String get removeFromIcloud => 'Supprimer d’iCloud';

  @override
  String get exportMyData => 'Exporter mes données';

  @override
  String get privacyPolicy => 'Politique de confidentialité';

  @override
  String get reachOut => 'Nous contacter';

  @override
  String get eastProductions => 'EAST. Productions';

  @override
  String get supportCircle => 'Soutiens le cercle, garde ce qui reste.';

  @override
  String get restoreBelongs => 'Retrouve ce qui t’appartient.';

  @override
  String get worldBeyondRitual => 'Le monde au-delà du rituel.';

  @override
  String get whatStaysPrivate => 'Ce qui reste privé.';

  @override
  String get thoughtsAndQuestions => 'Pour les pensées et les questions.';

  @override
  String get keepThisWisdom => 'Garde cette sagesse.';

  @override
  String get wisdomCouldNotBeKept =>
      'Cette sagesse n’a pas pu être gardée. Réessaie.';

  @override
  String get keptLimit => 'Limite des sagesses gardées';

  @override
  String get freeUsersKeepLimit =>
      'La version gratuite permet de garder jusqu’à 3 sagesses.';

  @override
  String get keepReflectingQuestion => 'Continuer à réfléchir ?';

  @override
  String get reflectionLimitExplanation =>
      'Trois Réflexions sont incluses. Keeper ouvre un espace illimité pour ce qui reste.';

  @override
  String get becomeKeeper => 'Devenir Keeper';

  @override
  String get whoseJournal => 'À qui appartient ce carnet ?';

  @override
  String get journalNameExplanation =>
      'Un nom apparaît discrètement sur la page de titre de ton Carnet.';

  @override
  String get notificationTitle => 'EAST.';

  @override
  String get notificationBody => 'Quelque chose attend dans le silence.';

  @override
  String get journalPdfTitle => 'Carnet.';

  @override
  String get dailyWisdomReady => 'Une nouvelle sagesse est prête.';

  @override
  String get discoverTheObjects => 'DÉCOUVRIR LES OBJETS';

  @override
  String get enterTheCircle => 'Entre dans le cercle.';

  @override
  String get withinTheCircle => 'Dans le cercle.';

  @override
  String get keeperActive => 'Keeper actif';

  @override
  String get oneTimePurchase => 'Achat unique';

  @override
  String get askFrom => 'Demande avec';

  @override
  String get yourHeart => 'le cœur.';

  @override
  String get longPressToShareWisdom =>
      'Appuie longuement pour partager cette sagesse.';

  @override
  String get shareWisdom => 'Partager';

  @override
  String shareWisdomNumbered(int itemNumber) {
    return 'Partager la sagesse, élément $itemNumber';
  }

  @override
  String get quietReminder => 'Rappel discret';

  @override
  String get nothingHasStayedYet => 'Rien n’est encore resté.';

  @override
  String get wisdomCouldNotBeRemoved =>
      'Cette sagesse n’a pas pu être retirée. Réessaie.';

  @override
  String get reflectionPrompt => 'Que remarques-tu maintenant ?';

  @override
  String get returnWhenSilenceOpensAgain =>
      'Reviens quand le silence s\'ouvre à nouveau.';

  @override
  String get reflectionPromptWhatRemains => 'Que reste-t-il ?';

  @override
  String get reflectionPromptWhatStayedWithYou =>
      'Qu\'est-ce qui t\'est resté ?';

  @override
  String get reflectionPromptWhatBecameClearer =>
      'Qu\'est-ce qui est devenu plus clair ?';

  @override
  String get reflectionPromptWhatFeelsDifferent =>
      'Qu\'est-ce qui semble différent ?';

  @override
  String get reflectionPromptCarryForward =>
      'Qu\'aimerais-tu emporter avec toi ?';

  @override
  String get deleteReflectionQuestion => 'Supprimer la réflexion ?';

  @override
  String get reflectionDeleteExplanation =>
      'La réflexion sera retirée de cette sagesse gardée.';

  @override
  String get removeKeptQuestion => 'Retirer de « Ce qui reste » ?';

  @override
  String get keptDeleteExplanation =>
      'Cette sagesse et sa réflexion seront supprimées.';

  @override
  String get cancelUpper => 'ANNULER';

  @override
  String get continueAction => 'Continuer';

  @override
  String get onlyKeptOnThisDevice => 'Gardé uniquement sur cet appareil.';

  @override
  String get yourName => 'Ton nom';

  @override
  String get journalCouldNotBePrepared =>
      'Le Carnet n’a pas pu être préparé. Réessaie.';

  @override
  String get takeItWithYou => 'Emporte-le.';

  @override
  String get takeItWithYouKeeper => 'Emporte-le. Disponible avec Keeper.';

  @override
  String get availableWithKeeper => 'Disponible avec Keeper.';

  @override
  String get opensKeeper => 'Ouvre Keeper.';

  @override
  String get nameUpper => 'NOM';

  @override
  String get keeperPersistenceError =>
      'L’accès Keeper n’a pas pu être enregistré. Essaie Restaurer les achats.';

  @override
  String get purchaseUpdating =>
      'Le statut de l’achat est encore en cours de mise à jour. Utilise Restaurer les achats dans Réglages.';

  @override
  String get purchaseNotReady =>
      'L’achat n’est pas encore prêt. Réessaie dans un instant.';

  @override
  String get restore => 'Restaurer';

  @override
  String get keepWhatStays => 'Garde ce qui reste.';

  @override
  String get addReflectionSemantics => 'Ajouter une réflexion';

  @override
  String get deleteSemantics => 'Supprimer';

  @override
  String get settingsClose => 'Fermer';

  @override
  String get notificationPermissionTitle => 'Un retour silencieux';

  @override
  String get notificationPermissionBody =>
      'Souhaites-tu être averti lorsqu’une nouvelle sagesse est prête ?';

  @override
  String get whereSilenceSpeaks => 'Là où parle le silence.';

  @override
  String get preparing => 'Préparation…';

  @override
  String get exportKeptAndReflections =>
      'Emporte tes sagesses gardées et tes Réflexions.';

  @override
  String get keeperAccessActive => 'Accès Keeper actif';

  @override
  String keeperPurchaseInProgress(Object price) {
    return 'Entre dans le cercle, $price. Achat en cours.';
  }

  @override
  String keeperPurchaseOffering(Object price) {
    return 'Entre dans le cercle, $price, contribution unique';
  }

  @override
  String get keeperUnavailable =>
      'Entre dans le cercle, temporairement indisponible';

  @override
  String get keepWithoutLimit => 'Garde sans limite.';

  @override
  String get reflectWithoutLimit => 'Réfléchis sans limite.';

  @override
  String get takeJournalWithYou => 'Emporte ton Carnet.';

  @override
  String get keeperWidgetRitual => 'Le rituel, dans ton widget.';

  @override
  String get addKeeperWidget => 'Ajouter le widget Keeper';

  @override
  String get keeperWidgetInteractive =>
      'Sous iOS 17 ou version ultérieure, commence le rituel dans le widget.';

  @override
  String get keeperWidgetOpensApp => 'Sous iOS 15 et 16, le widget ouvre EAST.';

  @override
  String get keepEastAlive => 'Fais vivre EAST.';

  @override
  String get operationFailedRetry =>
      'Cette action n’a pas pu être effectuée. Réessaie.';

  @override
  String get restoreRequestSent =>
      'Demande de restauration envoyée. L’accès Keeper sera mis à jour automatiquement.';

  @override
  String get restoreRecoveryPending =>
      'Une restauration précédente est encore en cours de rapprochement. L’accès Keeper sera mis à jour automatiquement ; rouvre EAST. avant de réessayer.';

  @override
  String get opening => 'Ouverture.';

  @override
  String get bootstrapRecovery =>
      'L’ouverture prend plus de temps que prévu. Fermez EAST., puis rouvrez l’app.';

  @override
  String get supportEmailSubject => 'Assistance EAST.';

  @override
  String get removeIcloudLocalData =>
      'Tes sagesses gardées et tes Réflexions resteront sur cet iPhone.';

  @override
  String get removeIcloudCloudData =>
      'Leurs copies iCloud seront supprimées et la synchronisation iCloud sera désactivée.';

  @override
  String get enableIcloudQuestion => 'Activer la synchronisation iCloud ?';

  @override
  String get enableIcloudData =>
      'Tes sagesses gardées et tes Réflexions seront stockées dans ta base iCloud privée et synchronisées sur tes appareils.';

  @override
  String get dailyRitualOnDevice =>
      'Le rythme de ton rituel quotidien reste sur cet appareil.';

  @override
  String get removeUpper => 'SUPPRIMER';

  @override
  String get saveUpper => 'ENREGISTRER';

  @override
  String get enableUpper => 'ACTIVER';

  @override
  String get icloudEnabling => 'Activation…';

  @override
  String get icloudEnabled => 'Activée';

  @override
  String get icloudSyncing => 'Synchronisation';

  @override
  String get icloudUnavailable => 'iCloud indisponible';

  @override
  String get icloudNeedsAttention => 'Intervention requise';

  @override
  String get icloudNotEnabled => 'Non activée';

  @override
  String get icloudRemovalStarting => 'Démarrage…';

  @override
  String get icloudRemovalCompleted => 'Supprimé d’iCloud.';

  @override
  String get icloudRemovalPending =>
      'Suppression en attente. EAST. la terminera quand iCloud sera disponible.';

  @override
  String get icloudRemovalIdle => 'Supprime tes copies iCloud.';

  @override
  String get icloudRemovalNone => 'Rien à supprimer.';

  @override
  String get reflectionSaveFailed =>
      'La Réflexion n’a pas pu être enregistrée. Réessaie.';

  @override
  String get reflectionAutosaveFailed =>
      'La Réflexion n’a pas pu être enregistrée. Un nouvel essai aura lieu pendant que tu écris.';

  @override
  String get reflectionDeleteFailed =>
      'La Réflexion n’a pas pu être supprimée. Réessaie.';

  @override
  String remainingDurationHoursMinutes(int hours, int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'Encore $hours heures',
      one: 'Encore 1 heure',
    );
    String _temp1 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'et $minutes minutes',
      one: 'et 1 minute',
    );
    return '$_temp0 $_temp1';
  }

  @override
  String remainingDurationHoursOnly(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'Encore $hours heures',
      one: 'Encore 1 heure',
    );
    return '$_temp0';
  }

  @override
  String remainingDurationMinutesOnly(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Encore $minutes minutes',
      one: 'Encore 1 minute',
    );
    return '$_temp0';
  }

  @override
  String get keeperPreviewLabel => 'Un aperçu de Keeper';

  @override
  String get keeperWidgetTab => 'Widget';

  @override
  String get keeperPreviewExample => 'Exemple';

  @override
  String get keeperPreviewReflection =>
      'Aujourd’hui, je veux avancer sans me presser.';

  @override
  String get keeperDailyRitual =>
      'Une sagesse toutes les 24 heures, avec ou sans Keeper.';

  @override
  String get keeperWidgetStepOne =>
      'Appuie longuement sur une zone vide de l’écran d’accueil.';

  @override
  String get keeperWidgetStepTwo =>
      'Touche Modifier, puis Ajouter un widget. Sur les anciennes versions d’iOS, touche le bouton +.';

  @override
  String get keeperWidgetStepThree =>
      'Cherche EAST., choisis le widget Rituel Keeper, puis touche Ajouter le widget.';

  @override
  String get reflectionSaved => 'Enregistré';

  @override
  String get reflectionSaving => 'Enregistrement…';

  @override
  String get reflectionCopyText => 'Copier le texte';

  @override
  String get reflectionCopied => 'Copié';

  @override
  String get reflectionAddThought => 'Ajouter une nouvelle pensée';

  @override
  String get reflectionRevisitPrompt =>
      'Comment est-ce que je lis cela aujourd’hui ?';

  @override
  String get reflectionEarlier => 'Auparavant';

  @override
  String get reflectionOverTime => 'Au fil du temps';

  @override
  String get reflectionHistoryDeleteExplanation =>
      'Toutes les pensées liées à cette sagesse conservée seront supprimées.';

  @override
  String get reflectionRecoveryMessage =>
      'Ton texte n’a pas encore été enregistré.';

  @override
  String get settingsEveryday => 'Au quotidien';

  @override
  String get settingsYourWriting => 'Tes écrits';

  @override
  String get settingsAbout => 'À propos d’EAST.';

  @override
  String get writingLock => 'Verrouillage des écrits';

  @override
  String get writingLockDescription =>
      'Ouvre Ce qui reste, Réflexion et Carnet avec Face ID, Touch ID ou le code de ton appareil.';

  @override
  String get writingLockFootnote =>
      'Ton rituel quotidien reste accessible. Tes écrits privés se verrouillent à nouveau quand tu quittes l’app.';

  @override
  String get writingLockTitle => 'Tes mots t’appartiennent.';

  @override
  String get writingLockPrompt =>
      'Authentifie-toi pour ouvrir tes écrits privés.';

  @override
  String get writingLockUnlock => 'Déverrouiller';

  @override
  String get writingLockChecking => 'Authentification…';

  @override
  String get writingLockReason => 'Ouvre tes écrits privés.';

  @override
  String get writingLockUnavailable =>
      'L’authentification est indisponible. Vérifie le code de ton appareil et les réglages de Face ID ou Touch ID.';

  @override
  String get writingLockToggleReason =>
      'Modifie le verrouillage de tes écrits privés.';

  @override
  String get writingLockOn => 'Activé';

  @override
  String get writingLockOff => 'Désactivé';

  @override
  String get privacyPreview =>
      'Tes écrits sont masqués dans le sélecteur d’apps.';

  @override
  String get settingsAboutDescription =>
      'Un espace pour revenir à toi, une fois par jour.';

  @override
  String get dailyRitualICloudRequired =>
      'Connecte-toi à iCloud pour ouvrir une nouvelle sagesse.';

  @override
  String get dailyRitualConnectionRequired =>
      'Connecte-toi à Internet pour ouvrir une nouvelle sagesse.';

  @override
  String get dailyRitualUnavailable =>
      'Ta sagesse du jour est indisponible pour le moment. Réessaie.';

  @override
  String get dailyRitualAccountNote =>
      'Une sagesse par compte iCloud toutes les 24 heures. Une connexion Internet est nécessaire pour une nouvelle sagesse. Tes écrits enregistrés restent accessibles hors ligne.';

  @override
  String get dailyRitualPreviousWisdom => 'Dernière sagesse';

  @override
  String get keeperJournalTitle => 'Un journal à toi.';

  @override
  String get keeperJournalDescription =>
      'Les sagesses que tu gardes et les mots que tu écris, réunis.';

  @override
  String get keeperJournalOpen => 'Ouvrir ton journal';

  @override
  String get keeperJournalEmpty =>
      'Il commence avec la première sagesse que tu gardes.';

  @override
  String get keeperJournalExport => 'Avec Keeper, emporte-le en PDF.';

  @override
  String get ritualSound => 'Son du rituel';

  @override
  String get ritualSoundOn => 'Avec son';

  @override
  String get ritualSoundOff => 'Silencieux';

  @override
  String get ritualSoundOnDescription =>
      'Sons du rituel et vibrations douces. Le guidage vocal est disponible en anglais.';

  @override
  String get ritualSoundOffDescription => 'Sans son ni vibration.';

  @override
  String get ritualSoundSaveFailed =>
      'Ton choix est actif, mais n’a pas pu être enregistré. Réessaie.';

  @override
  String remainingDurationHoursMinutesSeconds(
      int hours, int minutes, int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours heures',
      one: '1 heure',
    );
    String _temp1 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
      one: '1 minute',
    );
    String _temp2 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds secondes',
      one: '1 seconde',
    );
    return 'Il reste $_temp0 $_temp1 $_temp2';
  }

  @override
  String remainingDurationSecondsOnly(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds secondes',
      one: '1 seconde',
    );
    return 'Il reste $_temp0';
  }
}
