// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'Saggezza quotidiana: EAST.';

  @override
  String get tapAnywhereToBegin => 'Tocca un punto qualsiasi per iniziare.';

  @override
  String get tapWhenReady => 'Tocca quando sei pronto.';

  @override
  String get pause => 'Pausa.';

  @override
  String get feel => 'Senti.';

  @override
  String get askFromYourHeart => 'Chiedi con il cuore.';

  @override
  String get east => 'EAST.';

  @override
  String get kept => 'Ciò che resta';

  @override
  String get searchKept => 'Cerca';

  @override
  String get clearSearch => 'Cancella ricerca';

  @override
  String get noKeptSearchResults => 'Nessun risultato.';

  @override
  String get keptUpper => 'CIÒ CHE RESTA';

  @override
  String get reflectedUpper => 'RIFLESSIONE';

  @override
  String get addReflectionUpper => 'AGGIUNGI UNA RIFLESSIONE';

  @override
  String get reflection => 'Riflessione';

  @override
  String get journal => 'Diario';

  @override
  String get settings => 'Impostazioni';

  @override
  String get language => 'Lingua';

  @override
  String get systemDefault => 'Predefinito di sistema';

  @override
  String get english => 'Inglese';

  @override
  String languageSettingSemantics(Object value) {
    return 'Lingua. Selezione attuale: $value.';
  }

  @override
  String languageOptionSemantics(Object language) {
    return '$language';
  }

  @override
  String get appearance => 'Aspetto';

  @override
  String get light => 'Chiaro';

  @override
  String get dark => 'Scuro';

  @override
  String appearanceSettingSemantics(Object value) {
    return 'Aspetto. Selezione attuale: $value.';
  }

  @override
  String appearanceOptionSemantics(Object option) {
    return '$option';
  }

  @override
  String get back => 'Indietro';

  @override
  String get delete => 'Elimina';

  @override
  String get deleteUpper => 'ELIMINA';

  @override
  String get cancel => 'Annulla';

  @override
  String get close => 'Chiudi';

  @override
  String get done => 'Fine';

  @override
  String get retry => 'Riprova';

  @override
  String get tryAgainUpper => 'RIPROVA';

  @override
  String get skip => 'Salta';

  @override
  String get addName => 'Aggiungi nome';

  @override
  String get changeName => 'Cambia nome';

  @override
  String get keptWisdoms => 'Saggezze conservate';

  @override
  String get addReflection => 'Aggiungi una riflessione';

  @override
  String get deleteReflection => 'Elimina riflessione';

  @override
  String get reflectedEditReflection => 'RIFLESSIONE. Modifica riflessione.';

  @override
  String addReflectionNumbered(Object number) {
    return 'Aggiungi una riflessione, elemento $number';
  }

  @override
  String openReflectionNumbered(Object number) {
    return 'Apri la riflessione, elemento $number';
  }

  @override
  String get journalSemantic => 'Diario';

  @override
  String get keeper => 'Keeper';

  @override
  String get restorePurchases => 'Ripristina acquisti';

  @override
  String get icloudSync => 'Sincronizzazione iCloud';

  @override
  String get removeFromIcloud => 'Rimuovi da iCloud';

  @override
  String get exportMyData => 'Esporta i miei dati';

  @override
  String get privacyPolicy => 'Informativa sulla privacy';

  @override
  String get reachOut => 'Contattaci';

  @override
  String get eastProductions => 'EAST. Productions';

  @override
  String get supportCircle => 'Sostieni il cerchio, conserva ciò che resta.';

  @override
  String get restoreBelongs => 'Recupera ciò che ti appartiene.';

  @override
  String get worldBeyondRitual => 'Il mondo oltre il rituale.';

  @override
  String get whatStaysPrivate => 'Ciò che resta privato.';

  @override
  String get thoughtsAndQuestions => 'Per pensieri e domande.';

  @override
  String get keepThisWisdom => 'Conserva questa saggezza.';

  @override
  String get wisdomCouldNotBeKept =>
      'Non è stato possibile conservare questa saggezza. Riprova.';

  @override
  String get keptLimit => 'Limite delle saggezze conservate';

  @override
  String get freeUsersKeepLimit =>
      'La versione gratuita consente di conservare fino a 3 saggezze.';

  @override
  String get keepReflectingQuestion => 'Continuare a riflettere?';

  @override
  String get reflectionLimitExplanation =>
      'Sono incluse tre Riflessioni. Keeper apre uno spazio illimitato per ciò che resta.';

  @override
  String get becomeKeeper => 'Attiva Keeper';

  @override
  String get whoseJournal => 'Di chi è questo diario?';

  @override
  String get journalNameExplanation =>
      'Un nome appare discretamente sulla pagina del titolo del tuo Diario.';

  @override
  String get notificationTitle => 'EAST.';

  @override
  String get notificationBody => 'Qualcosa attende nel silenzio.';

  @override
  String get journalPdfTitle => 'Diario.';

  @override
  String get dailyWisdomReady => 'Una nuova saggezza è pronta.';

  @override
  String get discoverTheObjects => 'SCOPRI GLI OGGETTI';

  @override
  String get enterTheCircle => 'Entra nel cerchio.';

  @override
  String get withinTheCircle => 'Nel cerchio.';

  @override
  String get keeperActive => 'Keeper attivo';

  @override
  String get oneTimePurchase => 'Acquisto una tantum';

  @override
  String get askFrom => 'Chiedi con';

  @override
  String get yourHeart => 'il cuore.';

  @override
  String get longPressToShareWisdom =>
      'Tieni premuto per condividere questa saggezza.';

  @override
  String get shareWisdom => 'Condividi';

  @override
  String shareWisdomNumbered(int itemNumber) {
    return 'Condividi saggezza, elemento $itemNumber';
  }

  @override
  String get quietReminder => 'Promemoria discreto';

  @override
  String get nothingHasStayedYet => 'Non è ancora rimasto nulla.';

  @override
  String get wisdomCouldNotBeRemoved =>
      'Non è stato possibile rimuovere questa saggezza. Riprova.';

  @override
  String get reflectionPrompt => 'Che cosa stai notando ora?';

  @override
  String get returnWhenSilenceOpensAgain =>
      'Torna quando il silenzio si apre di nuovo.';

  @override
  String get reflectionPromptWhatRemains => 'Che cosa resta?';

  @override
  String get reflectionPromptWhatStayedWithYou => 'Che cosa è rimasto con te?';

  @override
  String get reflectionPromptWhatBecameClearer =>
      'Che cosa è diventato più chiaro?';

  @override
  String get reflectionPromptWhatFeelsDifferent => 'Che cosa senti diverso?';

  @override
  String get reflectionPromptCarryForward =>
      'Che cosa vorresti portare con te?';

  @override
  String get deleteReflectionQuestion => 'Eliminare la riflessione?';

  @override
  String get reflectionDeleteExplanation =>
      'La riflessione verrà rimossa da questa saggezza conservata.';

  @override
  String get removeKeptQuestion => 'Rimuovere da «Ciò che resta»?';

  @override
  String get keptDeleteExplanation =>
      'Questa saggezza e la sua riflessione saranno rimosse.';

  @override
  String get cancelUpper => 'ANNULLA';

  @override
  String get continueAction => 'Continua';

  @override
  String get onlyKeptOnThisDevice => 'Conservata solo su questo dispositivo.';

  @override
  String get yourName => 'Il tuo nome';

  @override
  String get journalCouldNotBePrepared =>
      'Non è stato possibile preparare il Diario. Riprova.';

  @override
  String get takeItWithYou => 'Portalo con te.';

  @override
  String get takeItWithYouKeeper => 'Portalo con te. Disponibile con Keeper.';

  @override
  String get availableWithKeeper => 'Disponibile con Keeper.';

  @override
  String get opensKeeper => 'Apre Keeper.';

  @override
  String get nameUpper => 'NOME';

  @override
  String get keeperPersistenceError =>
      'Non è stato possibile salvare l’accesso a Keeper. Prova Ripristina acquisti.';

  @override
  String get purchaseUpdating =>
      'Lo stato dell’acquisto è ancora in aggiornamento. Usa Ripristina acquisti nelle Impostazioni.';

  @override
  String get purchaseNotReady =>
      'L’acquisto non è ancora pronto. Riprova tra poco.';

  @override
  String get restore => 'Ripristina';

  @override
  String get keepWhatStays => 'Custodisci ciò che resta.';

  @override
  String get addReflectionSemantics => 'Aggiungi una riflessione';

  @override
  String get deleteSemantics => 'Elimina';

  @override
  String get settingsClose => 'Chiudi';

  @override
  String get notificationPermissionTitle => 'Un ritorno silenzioso';

  @override
  String get notificationPermissionBody =>
      'Vuoi sapere quando una nuova saggezza è pronta?';

  @override
  String get whereSilenceSpeaks => 'Dove parla il silenzio.';

  @override
  String get preparing => 'Preparazione…';

  @override
  String get exportKeptAndReflections =>
      'Porta con te le saggezze conservate e le tue Riflessioni.';

  @override
  String get keeperAccessActive => 'Accesso a Keeper attivo';

  @override
  String keeperPurchaseInProgress(Object price) {
    return 'Entra nel cerchio, $price. Acquisto in corso.';
  }

  @override
  String keeperPurchaseOffering(Object price) {
    return 'Entra nel cerchio, $price, contributo una tantum';
  }

  @override
  String get keeperUnavailable =>
      'Entra nel cerchio, temporaneamente non disponibile';

  @override
  String get keepWithoutLimit => 'Custodisci senza limiti.';

  @override
  String get reflectWithoutLimit => 'Rifletti senza limiti.';

  @override
  String get takeJournalWithYou => 'Porta con te il tuo Diario.';

  @override
  String get keeperWidgetRitual => 'Il rituale, nel tuo widget.';

  @override
  String get addKeeperWidget => 'Aggiungi il widget Keeper';

  @override
  String get keeperWidgetInteractive =>
      'Su iOS 17 o versioni successive, inizia il rituale nel widget.';

  @override
  String get keeperWidgetOpensApp => 'Su iOS 15 e 16, il widget apre EAST.';

  @override
  String get keepEastAlive => 'Mantieni vivo EAST.';

  @override
  String get operationFailedRetry =>
      'Non è stato possibile completare. Riprova.';

  @override
  String get restoreRequestSent =>
      'Richiesta di ripristino inviata. L’accesso Keeper si aggiornerà automaticamente.';

  @override
  String get restoreRecoveryPending =>
      'Un ripristino precedente è ancora in fase di riconciliazione. L’accesso Keeper si aggiornerà automaticamente; riapri EAST. prima di riprovare.';

  @override
  String get opening => 'Apertura.';

  @override
  String get bootstrapRecovery =>
      'L’apertura sta richiedendo più tempo del previsto. Chiudi EAST. e riaprila.';

  @override
  String get supportEmailSubject => 'Supporto EAST.';

  @override
  String get removeIcloudLocalData =>
      'Le tue saggezze conservate e Riflessioni resteranno su questo iPhone.';

  @override
  String get removeIcloudCloudData =>
      'Le loro copie su iCloud saranno rimosse e la sincronizzazione iCloud verrà disattivata.';

  @override
  String get enableIcloudQuestion => 'Abilitare la sincronizzazione iCloud?';

  @override
  String get enableIcloudData =>
      'Le tue saggezze conservate e Riflessioni saranno archiviate nel tuo database iCloud privato e sincronizzate tra i dispositivi.';

  @override
  String get dailyRitualOnDevice =>
      'L’orario del tuo rituale quotidiano resta su questo dispositivo.';

  @override
  String get removeUpper => 'RIMUOVI';

  @override
  String get saveUpper => 'SALVA';

  @override
  String get enableUpper => 'ABILITA';

  @override
  String get icloudEnabling => 'Attivazione…';

  @override
  String get icloudEnabled => 'Abilitata';

  @override
  String get icloudSyncing => 'Sincronizzazione';

  @override
  String get icloudUnavailable => 'iCloud non disponibile';

  @override
  String get icloudNeedsAttention => 'Richiede attenzione';

  @override
  String get icloudNotEnabled => 'Non abilitata';

  @override
  String get icloudRemovalStarting => 'Avvio…';

  @override
  String get icloudRemovalCompleted => 'Rimosso da iCloud.';

  @override
  String get icloudRemovalPending =>
      'Rimozione in attesa. EAST. completerà quando iCloud sarà disponibile.';

  @override
  String get icloudRemovalIdle => 'Rimuovi le tue copie iCloud.';

  @override
  String get icloudRemovalNone => 'Niente da rimuovere.';

  @override
  String get reflectionSaveFailed =>
      'Non è stato possibile salvare la Riflessione. Riprova.';

  @override
  String get reflectionAutosaveFailed =>
      'Non è stato possibile salvare la Riflessione. Verrà riprovato mentre continui a scrivere.';

  @override
  String get reflectionDeleteFailed =>
      'Non è stato possibile eliminare la Riflessione. Riprova.';

  @override
  String remainingDurationHoursMinutes(int hours, int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'Mancano $hours ore',
      one: 'Manca 1 ora',
    );
    String _temp1 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'e $minutes minuti',
      one: 'e 1 minuto',
    );
    return '$_temp0 $_temp1';
  }

  @override
  String remainingDurationHoursOnly(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'Mancano $hours ore',
      one: 'Manca 1 ora',
    );
    return '$_temp0';
  }

  @override
  String remainingDurationMinutesOnly(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Mancano $minutes minuti',
      one: 'Manca 1 minuto',
    );
    return '$_temp0';
  }

  @override
  String get keeperPreviewLabel => 'Uno sguardo a Keeper';

  @override
  String get keeperWidgetTab => 'Widget';

  @override
  String get keeperPreviewExample => 'Esempio';

  @override
  String get keeperPreviewReflection => 'Oggi voglio procedere senza fretta.';

  @override
  String get keeperDailyRitual =>
      'Una saggezza ogni 24 ore, con o senza Keeper.';

  @override
  String get keeperWidgetStepOne =>
      'Tieni premuta un’area vuota della schermata Home.';

  @override
  String get keeperWidgetStepTwo =>
      'Tocca Modifica, poi Aggiungi widget. Nelle versioni precedenti di iOS, tocca il pulsante +.';

  @override
  String get keeperWidgetStepThree =>
      'Cerca EAST., scegli il widget Rituale Keeper e tocca Aggiungi widget.';

  @override
  String get reflectionSaved => 'Salvato';

  @override
  String get reflectionSaving => 'Salvataggio…';

  @override
  String get reflectionCopyText => 'Copia il testo';

  @override
  String get reflectionCopied => 'Copiato';

  @override
  String get reflectionAddThought => 'Aggiungi un nuovo pensiero';

  @override
  String get reflectionRevisitPrompt => 'Come leggo queste parole oggi?';

  @override
  String get reflectionEarlier => 'Prima';

  @override
  String get reflectionOverTime => 'Con il tempo';

  @override
  String get reflectionHistoryDeleteExplanation =>
      'Tutti i pensieri legati a questa saggezza conservata verranno rimossi.';

  @override
  String get reflectionRecoveryMessage =>
      'Il tuo testo non è ancora stato salvato.';

  @override
  String get settingsEveryday => 'Preferenze quotidiane';

  @override
  String get settingsYourWriting => 'Le tue parole';

  @override
  String get settingsAbout => 'Informazioni su EAST.';

  @override
  String get writingLock => 'Blocco degli scritti';

  @override
  String get writingLockDescription =>
      'Apri Ciò che resta, Riflessione e Diario con Face ID, Touch ID o il codice del dispositivo.';

  @override
  String get writingLockFootnote =>
      'Il rituale quotidiano resta accessibile. I tuoi scritti privati si bloccano di nuovo quando esci dall’app.';

  @override
  String get writingLockTitle => 'Le tue parole ti appartengono.';

  @override
  String get writingLockPrompt =>
      'Autenticati per aprire i tuoi scritti privati.';

  @override
  String get writingLockUnlock => 'Sblocca';

  @override
  String get writingLockChecking => 'Autenticazione…';

  @override
  String get writingLockReason => 'Apri i tuoi scritti privati.';

  @override
  String get writingLockUnavailable =>
      'Autenticazione non disponibile. Controlla il codice del dispositivo e le impostazioni di Face ID o Touch ID.';

  @override
  String get writingLockToggleReason =>
      'Modifica il blocco dei tuoi scritti privati.';

  @override
  String get writingLockOn => 'Attivo';

  @override
  String get writingLockOff => 'Disattivo';

  @override
  String get privacyPreview =>
      'I tuoi scritti sono nascosti nel selettore delle app.';

  @override
  String get settingsAboutDescription =>
      'Uno spazio per ritrovarti, una volta al giorno.';

  @override
  String get dailyRitualICloudRequired =>
      'Accedi a iCloud per aprire una nuova saggezza.';

  @override
  String get dailyRitualConnectionRequired =>
      'Connettiti a internet per aprire una nuova saggezza.';

  @override
  String get dailyRitualUnavailable =>
      'La tua saggezza quotidiana non è disponibile al momento. Riprova.';

  @override
  String get dailyRitualAccountNote =>
      'Una saggezza per account iCloud ogni 24 ore. Per una nuova saggezza serve una connessione a internet. I tuoi scritti salvati restano disponibili offline.';

  @override
  String get dailyRitualPreviousWisdom => 'Ultima saggezza';

  @override
  String get keeperJournalTitle => 'Un diario tutto tuo.';

  @override
  String get keeperJournalDescription =>
      'Le saggezze che custodisci e le parole che scrivi, insieme.';

  @override
  String get keeperJournalOpen => 'Apri il tuo diario';

  @override
  String get keeperJournalEmpty =>
      'Inizia con la prima saggezza che custodisci.';

  @override
  String get keeperJournalExport => 'Con Keeper, portalo con te in PDF.';

  @override
  String get ritualSound => 'Suono del rituale';

  @override
  String get ritualSoundOn => 'Con audio';

  @override
  String get ritualSoundOff => 'Silenzioso';

  @override
  String get ritualSoundOnDescription =>
      'Suoni del rituale e vibrazioni delicate. La guida vocale è disponibile in inglese.';

  @override
  String get ritualSoundOffDescription => 'Senza suoni né vibrazioni.';

  @override
  String get ritualSoundSaveFailed =>
      'La tua scelta è attiva, ma non è stato possibile salvarla. Riprova.';

  @override
  String remainingDurationHoursMinutesSeconds(
      int hours, int minutes, int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours ore',
      one: '1 ora',
    );
    String _temp1 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minuti',
      one: '1 minuto',
    );
    String _temp2 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds secondi',
      one: '1 secondo',
    );
    return 'Tempo rimanente: $_temp0 $_temp1 $_temp2';
  }

  @override
  String remainingDurationSecondsOnly(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds secondi',
      one: '1 secondo',
    );
    return 'Tempo rimanente: $_temp0';
  }
}
