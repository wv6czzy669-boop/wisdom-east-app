// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Sabiduría diaria: EAST.';

  @override
  String get tapAnywhereToBegin => 'Toca cualquier parte para comenzar.';

  @override
  String get tapWhenReady => 'Toca cuando estés listo.';

  @override
  String get pause => 'Pausa.';

  @override
  String get feel => 'Siente.';

  @override
  String get askFromYourHeart => 'Pregunta desde el corazón.';

  @override
  String get east => 'EAST.';

  @override
  String get kept => 'Lo que queda';

  @override
  String get searchKept => 'Buscar';

  @override
  String get clearSearch => 'Borrar búsqueda';

  @override
  String get noKeptSearchResults => 'No se encontró nada.';

  @override
  String get keptUpper => 'LO QUE QUEDA';

  @override
  String get reflectedUpper => 'REFLEXIÓN';

  @override
  String get addReflectionUpper => 'AÑADIR UNA REFLEXIÓN';

  @override
  String get reflection => 'Reflexión';

  @override
  String get journal => 'Diario';

  @override
  String get settings => 'Ajustes';

  @override
  String get language => 'Idioma';

  @override
  String get systemDefault => 'Predeterminado del sistema';

  @override
  String get english => 'Inglés';

  @override
  String languageSettingSemantics(Object value) {
    return 'Idioma. Selección actual: $value.';
  }

  @override
  String languageOptionSemantics(Object language) {
    return '$language';
  }

  @override
  String get appearance => 'Aspecto';

  @override
  String get light => 'Claro';

  @override
  String get dark => 'Oscuro';

  @override
  String appearanceSettingSemantics(Object value) {
    return 'Aspecto. Selección actual: $value.';
  }

  @override
  String appearanceOptionSemantics(Object option) {
    return '$option';
  }

  @override
  String get back => 'Atrás';

  @override
  String get delete => 'Eliminar';

  @override
  String get deleteUpper => 'ELIMINAR';

  @override
  String get cancel => 'Cancelar';

  @override
  String get close => 'Cerrar';

  @override
  String get done => 'Listo';

  @override
  String get retry => 'Reintentar';

  @override
  String get tryAgainUpper => 'REINTENTAR';

  @override
  String get skip => 'Omitir';

  @override
  String get addName => 'Añadir nombre';

  @override
  String get changeName => 'Cambiar nombre';

  @override
  String get keptWisdoms => 'Sabidurías conservadas';

  @override
  String get addReflection => 'Añadir una reflexión';

  @override
  String get deleteReflection => 'Eliminar reflexión';

  @override
  String get reflectedEditReflection => 'REFLEXIÓN. Editar reflexión.';

  @override
  String addReflectionNumbered(Object number) {
    return 'Añadir una reflexión, elemento $number';
  }

  @override
  String openReflectionNumbered(Object number) {
    return 'Abrir reflexión, elemento $number';
  }

  @override
  String get journalSemantic => 'Diario';

  @override
  String get keeper => 'Keeper';

  @override
  String get restorePurchases => 'Restaurar compras';

  @override
  String get icloudSync => 'Sincronización con iCloud';

  @override
  String get removeFromIcloud => 'Eliminar de iCloud';

  @override
  String get exportMyData => 'Exportar mis datos';

  @override
  String get privacyPolicy => 'Política de privacidad';

  @override
  String get reachOut => 'Contáctanos';

  @override
  String get eastProductions => 'EAST. Productions';

  @override
  String get supportCircle => 'Apoya el círculo, guarda lo que queda.';

  @override
  String get restoreBelongs => 'Recupera lo que te pertenece.';

  @override
  String get worldBeyondRitual => 'El mundo más allá del ritual.';

  @override
  String get whatStaysPrivate => 'Lo que permanece privado.';

  @override
  String get thoughtsAndQuestions => 'Para pensamientos y preguntas.';

  @override
  String get keepThisWisdom => 'Guarda esta sabiduría.';

  @override
  String get wisdomCouldNotBeKept =>
      'No se pudo guardar esta sabiduría. Inténtalo de nuevo.';

  @override
  String get keptLimit => 'Límite de sabidurías guardadas';

  @override
  String get freeUsersKeepLimit =>
      'La versión gratuita permite guardar hasta 3 sabidurías.';

  @override
  String get keepReflectingQuestion => '¿Seguir reflexionando?';

  @override
  String get reflectionLimitExplanation =>
      'Se incluyen tres Reflexiones. Keeper abre espacio ilimitado para lo que permanece.';

  @override
  String get becomeKeeper => 'Activar Keeper';

  @override
  String get whoseJournal => '¿De quién es este diario?';

  @override
  String get journalNameExplanation =>
      'Un nombre aparece discretamente en la portada de tu Diario.';

  @override
  String get notificationTitle => 'EAST.';

  @override
  String get notificationBody => 'Algo espera en el silencio.';

  @override
  String get journalPdfTitle => 'Diario.';

  @override
  String get dailyWisdomReady => 'Hay una nueva sabiduría lista.';

  @override
  String get discoverTheObjects => 'DESCUBRE LOS OBJETOS';

  @override
  String get enterTheCircle => 'Entra en el círculo.';

  @override
  String get withinTheCircle => 'Dentro del círculo.';

  @override
  String get keeperActive => 'Keeper activo';

  @override
  String get oneTimePurchase => 'Compra única';

  @override
  String get askFrom => 'Pregunta desde';

  @override
  String get yourHeart => 'el corazón.';

  @override
  String get longPressToShareWisdom =>
      'Mantén pulsado para compartir esta sabiduría.';

  @override
  String get shareWisdom => 'Compartir';

  @override
  String shareWisdomNumbered(int itemNumber) {
    return 'Compartir sabiduría, elemento $itemNumber';
  }

  @override
  String get quietReminder => 'Recordatorio discreto';

  @override
  String get nothingHasStayedYet => 'Aún no ha quedado nada.';

  @override
  String get wisdomCouldNotBeRemoved =>
      'No se pudo eliminar esta sabiduría. Inténtalo de nuevo.';

  @override
  String get reflectionPrompt => '¿Qué estás notando ahora?';

  @override
  String get returnWhenSilenceOpensAgain =>
      'Vuelve cuando el silencio se abra de nuevo.';

  @override
  String get reflectionPromptWhatRemains => '¿Qué permanece?';

  @override
  String get reflectionPromptWhatStayedWithYou => '¿Qué se quedó contigo?';

  @override
  String get reflectionPromptWhatBecameClearer => '¿Qué se volvió más claro?';

  @override
  String get reflectionPromptWhatFeelsDifferent => '¿Qué se siente diferente?';

  @override
  String get reflectionPromptCarryForward => '¿Qué te gustaría llevar contigo?';

  @override
  String get deleteReflectionQuestion => '¿Eliminar reflexión?';

  @override
  String get reflectionDeleteExplanation =>
      'La reflexión se eliminará de esta sabiduría guardada.';

  @override
  String get removeKeptQuestion => '¿Quitar de «Lo que queda»?';

  @override
  String get keptDeleteExplanation =>
      'Esta sabiduría y su reflexión se eliminarán.';

  @override
  String get cancelUpper => 'CANCELAR';

  @override
  String get continueAction => 'Continuar';

  @override
  String get onlyKeptOnThisDevice => 'Guardada solo en este dispositivo.';

  @override
  String get yourName => 'Tu nombre';

  @override
  String get journalCouldNotBePrepared =>
      'No se pudo preparar el Diario. Inténtalo de nuevo.';

  @override
  String get takeItWithYou => 'Llévalo contigo.';

  @override
  String get takeItWithYouKeeper => 'Llévalo contigo. Disponible con Keeper.';

  @override
  String get availableWithKeeper => 'Disponible con Keeper.';

  @override
  String get opensKeeper => 'Abre Keeper.';

  @override
  String get nameUpper => 'NOMBRE';

  @override
  String get keeperPersistenceError =>
      'No se pudo guardar el acceso a Keeper. Prueba Restaurar compras.';

  @override
  String get purchaseUpdating =>
      'El estado de la compra sigue actualizándose. Usa Restaurar compras en Ajustes.';

  @override
  String get purchaseNotReady =>
      'La compra aún no está lista. Inténtalo de nuevo en unos instantes.';

  @override
  String get restore => 'Restaurar';

  @override
  String get keepWhatStays => 'Guarda lo que queda.';

  @override
  String get addReflectionSemantics => 'Añadir una reflexión';

  @override
  String get deleteSemantics => 'Eliminar';

  @override
  String get settingsClose => 'Cerrar';

  @override
  String get notificationPermissionTitle => 'Un regreso silencioso';

  @override
  String get notificationPermissionBody =>
      '¿Quieres saber cuándo hay una nueva sabiduría lista?';

  @override
  String get whereSilenceSpeaks => 'Donde habla el silencio.';

  @override
  String get preparing => 'Preparando…';

  @override
  String get exportKeptAndReflections =>
      'Lleva contigo tus sabidurías guardadas y tus Reflexiones.';

  @override
  String get keeperAccessActive => 'Acceso a Keeper activo';

  @override
  String keeperPurchaseInProgress(Object price) {
    return 'Entra en el círculo, $price. Compra en curso.';
  }

  @override
  String keeperPurchaseOffering(Object price) {
    return 'Entra en el círculo, $price, aportación única';
  }

  @override
  String get keeperUnavailable =>
      'Entra en el círculo, temporalmente no disponible';

  @override
  String get keepWithoutLimit => 'Guarda sin límites.';

  @override
  String get reflectWithoutLimit => 'Reflexiona sin límites.';

  @override
  String get takeJournalWithYou => 'Lleva contigo tu Diario.';

  @override
  String get keeperWidgetRitual => 'El ritual, dentro de tu widget.';

  @override
  String get addKeeperWidget => 'Añadir el widget de Keeper';

  @override
  String get keeperWidgetInteractive =>
      'En iOS 17 o posterior, comienza el ritual dentro del widget.';

  @override
  String get keeperWidgetOpensApp => 'En iOS 15 y 16, el widget abre EAST.';

  @override
  String get keepEastAlive => 'Haz que EAST. siga vivo.';

  @override
  String get operationFailedRetry =>
      'No se pudo completar esta acción. Inténtalo de nuevo.';

  @override
  String get restoreRequestSent =>
      'Solicitud de restauración enviada. El acceso de Keeper se actualizará automáticamente.';

  @override
  String get restoreRecoveryPending =>
      'Aún se está conciliando una restauración anterior. El acceso de Keeper se actualizará automáticamente; vuelve a abrir EAST. antes de intentarlo de nuevo.';

  @override
  String get opening => 'Abriendo.';

  @override
  String get bootstrapRecovery =>
      'La apertura está tardando más de lo esperado. Cierra EAST. y vuelve a abrirla.';

  @override
  String get supportEmailSubject => 'Soporte de EAST.';

  @override
  String get removeIcloudLocalData =>
      'Tus sabidurías guardadas y Reflexiones permanecerán en este iPhone.';

  @override
  String get removeIcloudCloudData =>
      'Se eliminarán sus copias de iCloud y se desactivará la sincronización de iCloud.';

  @override
  String get enableIcloudQuestion => '¿Activar la sincronización de iCloud?';

  @override
  String get enableIcloudData =>
      'Tus sabidurías guardadas y Reflexiones se almacenarán en tu base de datos privada de iCloud y se sincronizarán entre tus dispositivos.';

  @override
  String get dailyRitualOnDevice =>
      'El horario de tu ritual diario permanece en este dispositivo.';

  @override
  String get removeUpper => 'ELIMINAR';

  @override
  String get saveUpper => 'GUARDAR';

  @override
  String get enableUpper => 'ACTIVAR';

  @override
  String get icloudEnabling => 'Activando…';

  @override
  String get icloudEnabled => 'Activada';

  @override
  String get icloudSyncing => 'Sincronizando';

  @override
  String get icloudUnavailable => 'iCloud no disponible';

  @override
  String get icloudNeedsAttention => 'Requiere atención';

  @override
  String get icloudNotEnabled => 'No activada';

  @override
  String get icloudRemovalStarting => 'Iniciando…';

  @override
  String get icloudRemovalCompleted => 'Eliminado de iCloud.';

  @override
  String get icloudRemovalPending =>
      'Eliminación pendiente. EAST. terminará cuando iCloud esté disponible.';

  @override
  String get icloudRemovalIdle => 'Elimina tus copias de iCloud.';

  @override
  String get icloudRemovalNone => 'No hay nada que eliminar.';

  @override
  String get reflectionSaveFailed =>
      'No se pudo guardar la Reflexión. Inténtalo de nuevo.';

  @override
  String get reflectionAutosaveFailed =>
      'No se pudo guardar la Reflexión. Se volverá a intentar mientras sigues escribiendo.';

  @override
  String get reflectionDeleteFailed =>
      'No se pudo eliminar la Reflexión. Inténtalo de nuevo.';

  @override
  String remainingDurationHoursMinutes(int hours, int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'Quedan $hours horas',
      one: 'Queda 1 hora',
    );
    String _temp1 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'y $minutes minutos',
      one: 'y 1 minuto',
    );
    return '$_temp0 $_temp1';
  }

  @override
  String remainingDurationHoursOnly(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'Quedan $hours horas',
      one: 'Queda 1 hora',
    );
    return '$_temp0';
  }

  @override
  String remainingDurationMinutesOnly(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Quedan $minutes minutos',
      one: 'Queda 1 minuto',
    );
    return '$_temp0';
  }

  @override
  String get keeperPreviewLabel => 'Un vistazo a Keeper';

  @override
  String get keeperWidgetTab => 'Widget';

  @override
  String get keeperPreviewExample => 'Ejemplo';

  @override
  String get keeperPreviewReflection => 'Hoy quiero avanzar sin prisas.';

  @override
  String get keeperDailyRitual =>
      'Una reflexión sabia cada 24 horas, con o sin Keeper.';

  @override
  String get keeperWidgetStepOne =>
      'Mantén pulsada una zona vacía de la pantalla de inicio.';

  @override
  String get keeperWidgetStepTwo =>
      'Toca Editar y luego Añadir widget. En versiones anteriores de iOS, toca el botón +.';

  @override
  String get keeperWidgetStepThree =>
      'Busca EAST., elige el widget Ritual Keeper y toca Añadir widget.';

  @override
  String get reflectionSaved => 'Guardado';

  @override
  String get reflectionSaving => 'Guardando…';

  @override
  String get reflectionCopyText => 'Copiar texto';

  @override
  String get reflectionCopied => 'Copiado';

  @override
  String get reflectionAddThought => 'Añadir un nuevo pensamiento';

  @override
  String get reflectionRevisitPrompt => '¿Cómo leo esto hoy?';

  @override
  String get reflectionEarlier => 'Antes';

  @override
  String get reflectionOverTime => 'Con el tiempo';

  @override
  String get reflectionHistoryDeleteExplanation =>
      'Se eliminarán todos los pensamientos vinculados a esta sabiduría guardada.';

  @override
  String get reflectionRecoveryMessage => 'Tu texto aún no se ha guardado.';

  @override
  String get settingsEveryday => 'Preferencias diarias';

  @override
  String get settingsYourWriting => 'Tus palabras';

  @override
  String get settingsAbout => 'Acerca de EAST.';

  @override
  String get writingLock => 'Bloqueo de escritos';

  @override
  String get writingLockDescription =>
      'Abre Lo que queda, Reflexión y Diario con Face ID, Touch ID o el código de tu dispositivo.';

  @override
  String get writingLockFootnote =>
      'Tu ritual diario sigue accesible. Tus escritos privados vuelven a bloquearse al salir de la app.';

  @override
  String get writingLockTitle => 'Tus palabras te pertenecen.';

  @override
  String get writingLockPrompt =>
      'Autentícate para abrir tus escritos privados.';

  @override
  String get writingLockUnlock => 'Desbloquear';

  @override
  String get writingLockChecking => 'Autenticando…';

  @override
  String get writingLockReason => 'Abre tus escritos privados.';

  @override
  String get writingLockUnavailable =>
      'La autenticación no está disponible. Revisa el código de tu dispositivo y los ajustes de Face ID o Touch ID.';

  @override
  String get writingLockToggleReason =>
      'Cambia el bloqueo de tus escritos privados.';

  @override
  String get writingLockOn => 'Activado';

  @override
  String get writingLockOff => 'Desactivado';

  @override
  String get privacyPreview =>
      'Tus escritos se ocultan en el selector de apps.';

  @override
  String get settingsAboutDescription =>
      'Un espacio para volver a ti, una vez al día.';

  @override
  String get dailyRitualICloudRequired =>
      'Inicia sesión en iCloud para abrir una nueva sabiduría.';

  @override
  String get dailyRitualConnectionRequired =>
      'Conéctate a internet para abrir una nueva sabiduría.';

  @override
  String get dailyRitualUnavailable =>
      'Tu sabiduría diaria no está disponible ahora. Inténtalo de nuevo.';

  @override
  String get dailyRitualAccountNote =>
      'Una sabiduría por cuenta de iCloud cada 24 horas. Para una nueva sabiduría se necesita conexión a internet. Tus escritos guardados siguen disponibles sin conexión.';

  @override
  String get dailyRitualPreviousWisdom => 'Sabiduría anterior';

  @override
  String get keeperJournalTitle => 'Un diario propio.';

  @override
  String get keeperJournalDescription =>
      'La sabiduría que guardas y las palabras que escribes, juntas.';

  @override
  String get keeperJournalOpen => 'Abre tu diario';

  @override
  String get keeperJournalEmpty =>
      'Comienza con la primera sabiduría que guardas.';

  @override
  String get keeperJournalExport => 'Con Keeper, llévalo contigo en PDF.';

  @override
  String get ritualSound => 'Sonido del ritual';

  @override
  String get ritualSoundOn => 'Con sonido';

  @override
  String get ritualSoundOff => 'Silencio';

  @override
  String get ritualSoundOnDescription =>
      'Sonidos del ritual y vibraciones suaves. La guía de voz está disponible en inglés.';

  @override
  String get ritualSoundOffDescription => 'Sin sonido ni vibración.';

  @override
  String get ritualSoundSaveFailed =>
      'Tu elección está activa, pero no se pudo guardar. Inténtalo de nuevo.';

  @override
  String remainingDurationHoursMinutesSeconds(
      int hours, int minutes, int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours horas',
      one: '1 hora',
    );
    String _temp1 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutos',
      one: '1 minuto',
    );
    String _temp2 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds segundos',
      one: '1 segundo',
    );
    return 'Quedan $_temp0 $_temp1 $_temp2';
  }

  @override
  String remainingDurationSecondsOnly(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds segundos',
      one: '1 segundo',
    );
    return 'Quedan $_temp0';
  }
}
