// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Thai (`th`).
class AppLocalizationsTh extends AppLocalizations {
  AppLocalizationsTh([String locale = 'th']) : super(locale);

  @override
  String get appTitle => 'ข้อคิดประจำวัน: EAST.';

  @override
  String get tapAnywhereToBegin => 'แตะที่ใดก็ได้เพื่อเริ่ม';

  @override
  String get tapWhenReady => 'แตะเมื่อคุณพร้อม';

  @override
  String get pause => 'ชั่วครู่.';

  @override
  String get feel => 'รู้สึก.';

  @override
  String get askFromYourHeart => 'ถามจากใจ.';

  @override
  String get east => 'EAST.';

  @override
  String get kept => 'สิ่งที่เก็บไว้';

  @override
  String get searchKept => 'ค้นหา';

  @override
  String get clearSearch => 'ล้างการค้นหา';

  @override
  String get noKeptSearchResults => 'ไม่พบสิ่งที่ค้นหา';

  @override
  String get keptUpper => 'สิ่งที่เก็บไว้';

  @override
  String get reflectedUpper => 'การไตร่ตรอง';

  @override
  String get addReflectionUpper => 'บันทึกการไตร่ตรอง';

  @override
  String get reflection => 'การไตร่ตรอง';

  @override
  String get journal => 'สมุดบันทึก';

  @override
  String get settings => 'การตั้งค่า';

  @override
  String get language => 'ภาษา';

  @override
  String get systemDefault => 'ค่าเริ่มต้นของระบบ';

  @override
  String get english => 'ภาษาอังกฤษ';

  @override
  String languageSettingSemantics(Object value) {
    return 'ภาษา ตัวเลือกปัจจุบัน: $value.';
  }

  @override
  String languageOptionSemantics(Object language) {
    return '$language';
  }

  @override
  String get appearance => 'รูปลักษณ์';

  @override
  String get light => 'สว่าง';

  @override
  String get dark => 'มืด';

  @override
  String appearanceSettingSemantics(Object value) {
    return 'รูปลักษณ์ ตัวเลือกปัจจุบัน: $value';
  }

  @override
  String appearanceOptionSemantics(Object option) {
    return '$option';
  }

  @override
  String get back => 'กลับ';

  @override
  String get delete => 'ลบ';

  @override
  String get deleteUpper => 'ลบ';

  @override
  String get cancel => 'ยกเลิก';

  @override
  String get close => 'ปิด';

  @override
  String get done => 'เสร็จสิ้น';

  @override
  String get retry => 'ลองอีกครั้ง';

  @override
  String get tryAgainUpper => 'ลองอีกครั้ง';

  @override
  String get skip => 'ข้าม';

  @override
  String get addName => 'เพิ่มชื่อ';

  @override
  String get changeName => 'เปลี่ยนชื่อ';

  @override
  String get keptWisdoms => 'ข้อคิดที่เก็บไว้';

  @override
  String get addReflection => 'บันทึกการไตร่ตรอง';

  @override
  String get deleteReflection => 'ลบการไตร่ตรอง';

  @override
  String get reflectedEditReflection => 'ไตร่ตรองแล้ว แก้ไขการไตร่ตรอง.';

  @override
  String addReflectionNumbered(Object number) {
    return 'บันทึกการไตร่ตรอง รายการที่ $number';
  }

  @override
  String openReflectionNumbered(Object number) {
    return 'เปิดการไตร่ตรอง รายการที่ $number';
  }

  @override
  String get journalSemantic => 'สมุดบันทึก';

  @override
  String get keeper => 'คงไว้';

  @override
  String get restorePurchases => 'กู้คืนรายการซื้อ';

  @override
  String get icloudSync => 'ซิงค์ iCloud';

  @override
  String get removeFromIcloud => 'ลบออกจาก iCloud';

  @override
  String get exportMyData => 'ส่งออกข้อมูลของฉัน';

  @override
  String get privacyPolicy => 'นโยบายความเป็นส่วนตัว';

  @override
  String get reachOut => 'ติดต่อเรา';

  @override
  String get eastProductions => 'EAST. Productions';

  @override
  String get supportCircle => 'สนับสนุนวงนี้ เก็บสิ่งที่ยังคงอยู่ไว้.';

  @override
  String get restoreBelongs => 'กู้คืนสิ่งที่เป็นของคุณ.';

  @override
  String get worldBeyondRitual => 'โลกที่อยู่นอกพิธี.';

  @override
  String get whatStaysPrivate => 'สิ่งที่ยังคงเป็นส่วนตัว.';

  @override
  String get thoughtsAndQuestions => 'สำหรับความคิดและคำถาม.';

  @override
  String get keepThisWisdom => 'เก็บข้อคิดนี้ไว้';

  @override
  String get wisdomCouldNotBeKept =>
      'ไม่สามารถเก็บข้อคิดนี้ไว้ได้ โปรดลองอีกครั้ง.';

  @override
  String get keptLimit => 'ขีดจำกัดสิ่งที่เก็บไว้';

  @override
  String get freeUsersKeepLimit => 'ผู้ใช้ฟรีเก็บข้อคิดได้สูงสุด 3 ข้อ.';

  @override
  String get keepReflectingQuestion => 'ไตร่ตรองต่อไหม?';

  @override
  String get reflectionLimitExplanation =>
      'รวมการไตร่ตรอง 3 ครั้ง Keeper เปิดพื้นที่ไม่จำกัดสำหรับสิ่งที่ยังคงอยู่';

  @override
  String get becomeKeeper => 'เปิดใช้ “คงไว้”';

  @override
  String get whoseJournal => 'สมุดบันทึกนี้เป็นของใคร?';

  @override
  String get journalNameExplanation =>
      'ชื่อจะปรากฏอย่างเรียบง่ายบนหน้าชื่อเรื่องของสมุดบันทึก.';

  @override
  String get notificationTitle => 'EAST.';

  @override
  String get notificationBody => 'มีบางสิ่งรออยู่ในความเงียบ.';

  @override
  String get journalPdfTitle => 'สมุดบันทึก.';

  @override
  String get dailyWisdomReady => 'ข้อคิดใหม่พร้อมแล้ว.';

  @override
  String get discoverTheObjects => 'สำรวจวัตถุ';

  @override
  String get enterTheCircle => 'เข้ามาในวง.';

  @override
  String get withinTheCircle => 'ภายในวง.';

  @override
  String get keeperActive => 'Keeper เปิดใช้งานอยู่';

  @override
  String get oneTimePurchase => 'ซื้อครั้งเดียว';

  @override
  String get askFrom => 'ถาม';

  @override
  String get yourHeart => 'จากใจ.';

  @override
  String get longPressToShareWisdom => 'กดค้างเพื่อแชร์ข้อคิดนี้.';

  @override
  String get shareWisdom => 'แชร์';

  @override
  String shareWisdomNumbered(int itemNumber) {
    return 'แชร์ข้อคิด รายการที่ $itemNumber';
  }

  @override
  String get quietReminder => 'การเตือนอย่างเงียบงัน';

  @override
  String get nothingHasStayedYet => 'ยังไม่มีสิ่งใดคงอยู่.';

  @override
  String get wisdomCouldNotBeRemoved =>
      'ไม่สามารถนำข้อคิดนี้ออกได้ โปรดลองอีกครั้ง.';

  @override
  String get reflectionPrompt => 'ตอนนี้คุณสังเกตเห็นอะไร?';

  @override
  String get returnWhenSilenceOpensAgain => 'กลับมาเมื่อความเงียบเปิดอีกครั้ง.';

  @override
  String get reflectionPromptWhatRemains => 'อะไรที่หลงเหลืออยู่?';

  @override
  String get reflectionPromptWhatStayedWithYou => 'อะไรที่ยังคงอยู่กับคุณ?';

  @override
  String get reflectionPromptWhatBecameClearer => 'อะไรที่ชัดเจนขึ้น?';

  @override
  String get reflectionPromptWhatFeelsDifferent => 'อะไรที่รู้สึกแตกต่างไป?';

  @override
  String get reflectionPromptCarryForward => 'คุณอยากพกอะไรติดตัวไปต่อ?';

  @override
  String get deleteReflectionQuestion => 'ลบการไตร่ตรอง?';

  @override
  String get reflectionDeleteExplanation =>
      'การไตร่ตรองจะถูกนำออกจากข้อคิดที่เก็บไว้นี้.';

  @override
  String get removeKeptQuestion => 'นำออกจากสิ่งที่เก็บไว้?';

  @override
  String get keptDeleteExplanation => 'ข้อคิดนี้และการไตร่ตรองจะถูกนำออก.';

  @override
  String get cancelUpper => 'ยกเลิก';

  @override
  String get continueAction => 'ดำเนินการต่อ';

  @override
  String get onlyKeptOnThisDevice => 'เก็บไว้บนอุปกรณ์นี้เท่านั้น.';

  @override
  String get yourName => 'ชื่อของคุณ';

  @override
  String get journalCouldNotBePrepared =>
      'ไม่สามารถเตรียมสมุดบันทึกได้ โปรดลองอีกครั้ง.';

  @override
  String get takeItWithYou => 'พกติดตัวไป.';

  @override
  String get takeItWithYouKeeper => 'พกติดตัวไป ใช้ได้เมื่อมี “คงไว้”.';

  @override
  String get availableWithKeeper => 'ใช้ได้เมื่อมี “คงไว้”.';

  @override
  String get opensKeeper => 'เปิด Keeper';

  @override
  String get nameUpper => 'ชื่อ';

  @override
  String get keeperPersistenceError =>
      'ไม่สามารถบันทึกสิทธิ์ “คงไว้” ได้ โปรดลองกู้คืนรายการซื้อ.';

  @override
  String get purchaseUpdating =>
      'สถานะการซื้อยังอยู่ระหว่างอัปเดต โปรดใช้กู้คืนรายการซื้อในการตั้งค่า.';

  @override
  String get purchaseNotReady =>
      'การซื้อยังไม่พร้อม โปรดลองอีกครั้งในอีกสักครู่.';

  @override
  String get restore => 'กู้คืน';

  @override
  String get keepWhatStays => 'เก็บสิ่งที่ยังคงอยู่ไว้.';

  @override
  String get addReflectionSemantics => 'บันทึกการไตร่ตรอง';

  @override
  String get deleteSemantics => 'ลบ';

  @override
  String get settingsClose => 'ปิด';

  @override
  String get notificationPermissionTitle => 'การกลับมาอย่างเงียบงัน';

  @override
  String get notificationPermissionBody =>
      'ต้องการทราบเมื่อข้อคิดใหม่พร้อมหรือไม่?';

  @override
  String get whereSilenceSpeaks => 'ที่ซึ่งความเงียบเอ่ยถ้อยคำ.';

  @override
  String get preparing => 'กำลังเตรียม…';

  @override
  String get exportKeptAndReflections =>
      'พกข้อคิดที่เก็บไว้และการไตร่ตรองของคุณไปด้วย.';

  @override
  String get keeperAccessActive => 'สิทธิ์ “คงไว้” เปิดใช้งานแล้ว';

  @override
  String keeperPurchaseInProgress(Object price) {
    return 'เข้ามาในวง $price การซื้อกำลังดำเนินการ.';
  }

  @override
  String keeperPurchaseOffering(Object price) {
    return 'เข้ามาในวง $price ชำระครั้งเดียว';
  }

  @override
  String get keeperUnavailable => 'เข้ามาในวง ไม่พร้อมใช้งานชั่วคราว';

  @override
  String get keepWithoutLimit => 'เก็บไว้ได้ไม่จำกัด.';

  @override
  String get reflectWithoutLimit => 'ไตร่ตรองได้ไม่จำกัด.';

  @override
  String get takeJournalWithYou => 'พกสมุดบันทึกของคุณไปด้วย.';

  @override
  String get keeperWidgetRitual => 'พิธีกรรม อยู่ในวิดเจ็ตของคุณ.';

  @override
  String get keepEastAlive => 'ให้ EAST. ดำเนินต่อไป.';

  @override
  String get operationFailedRetry => 'ดำเนินการไม่สำเร็จ โปรดลองอีกครั้ง';

  @override
  String get restoreRequestSent =>
      'ส่งคำขอกู้คืนแล้ว สิทธิ์ Keeper จะอัปเดตโดยอัตโนมัติ';

  @override
  String get restoreRecoveryPending =>
      'ยังตรวจสอบการกู้คืนก่อนหน้าอยู่ สิทธิ์ Keeper จะอัปเดตโดยอัตโนมัติ โปรดเปิด EAST. ใหม่ก่อนลองอีกครั้ง';

  @override
  String get opening => 'กำลังเปิด';

  @override
  String get bootstrapRecovery =>
      'การเปิดใช้เวลานานกว่าที่คาด โปรดปิด EAST. แล้วเปิดอีกครั้ง';

  @override
  String get supportEmailSubject => 'EAST. การสนับสนุน';

  @override
  String get removeIcloudLocalData =>
      'ปัญญาที่เก็บไว้และบันทึกสะท้อนคิดจะอยู่บน iPhone เครื่องนี้';

  @override
  String get removeIcloudCloudData =>
      'สำเนาใน iCloud จะถูกลบ และการซิงค์ iCloud จะปิดลง';

  @override
  String get enableIcloudQuestion => 'เปิดใช้การซิงค์ iCloud?';

  @override
  String get enableIcloudData =>
      'ปัญญาที่เก็บไว้และบันทึกสะท้อนคิดจะถูกเก็บในฐานข้อมูล iCloud ส่วนตัวและซิงค์ระหว่างอุปกรณ์ของคุณ';

  @override
  String get dailyRitualOnDevice => 'เวลาของพิธีกรรมประจำวันจะอยู่บนอุปกรณ์นี้';

  @override
  String get removeUpper => 'ลบ';

  @override
  String get saveUpper => 'บันทึก';

  @override
  String get enableUpper => 'เปิดใช้';

  @override
  String get icloudEnabling => 'กำลังเปิดใช้…';

  @override
  String get icloudEnabled => 'เปิดใช้แล้ว';

  @override
  String get icloudSyncing => 'กำลังซิงค์';

  @override
  String get icloudUnavailable => 'iCloud ไม่พร้อมใช้งาน';

  @override
  String get icloudNeedsAttention => 'ต้องตรวจสอบ';

  @override
  String get icloudNotEnabled => 'ยังไม่เปิดใช้';

  @override
  String get icloudRemovalStarting => 'กำลังเริ่ม…';

  @override
  String get icloudRemovalCompleted => 'นำออกจาก iCloud แล้ว';

  @override
  String get icloudRemovalPending =>
      'กำลังรอการนำออก EAST. จะทำให้เสร็จเมื่อ iCloud พร้อมใช้งาน';

  @override
  String get icloudRemovalIdle => 'นำสำเนา iCloud ของคุณออก';

  @override
  String get icloudRemovalNone => 'ไม่มีสิ่งที่จะนำออก';

  @override
  String get reflectionSaveFailed => 'บันทึกการสะท้อนคิดไม่ได้ โปรดลองอีกครั้ง';

  @override
  String get reflectionAutosaveFailed =>
      'บันทึกการสะท้อนคิดไม่ได้ ระบบจะลองอีกครั้งขณะที่คุณเขียนต่อ';

  @override
  String get reflectionDeleteFailed => 'ลบการสะท้อนคิดไม่ได้ โปรดลองอีกครั้ง';

  @override
  String remainingDurationHoursMinutes(int hours, int minutes) {
    return 'เหลืออีก $hours ชั่วโมง $minutes นาที';
  }

  @override
  String remainingDurationHoursOnly(int hours) {
    return 'เหลืออีก $hours ชั่วโมง';
  }

  @override
  String remainingDurationMinutesOnly(int minutes) {
    return 'เหลืออีก $minutes นาที';
  }
}
