#!/usr/bin/env python3
"""EAST. Phase 5F-A -- English master repair + 15-locale App Store plate set.

New, standalone tool: does not modify or depend on `compose.py`/`validate.py`
(explicitly protected pre-existing screenshot tooling). Reads the 9 approved
English master plates, the fresh device captures written by
`integration_test/app_store_screenshots_localized_test.dart`, and produces
`tool/app_store_screenshots/localized_final/<locale>/01.png ... 09.png`.
"""

from __future__ import annotations

import json
from pathlib import Path

import arabic_reshaper
from bidi.algorithm import get_display
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
TOOL_DIR = Path(__file__).resolve().parent
MASTERS_SRC = Path("/Users/dogukanisik/Desktop/English Screen Posts East")
OUT_ROOT = TOOL_DIR / "localized_final"
RAW_ROOT = Path(
    "/private/tmp/claude-501/-Users-dogukanisik-Documents-Codex-2026-06-20-https-auth-openai-com-choose-an-work-wisdom-app"
    "/b25807cf-c2bf-455a-8563-2b55e6ae8948/scratchpad/raw_captures"
)
STATUS_BAR_STRIP = Path(
    "/private/tmp/claude-501/-Users-dogukanisik-Documents-Codex-2026-06-20-https-auth-openai-com-choose-an-work-wisdom-app"
    "/b25807cf-c2bf-455a-8563-2b55e6ae8948/scratchpad/status_bar_strip.png"
)

CANVAS = (1242, 2688)
BACKGROUND = (226, 224, 217)  # #E2E0D9
INK = (79, 74, 66)  # #4F4A42 (task-specified "ink/text")
DIVIDER_Y = 793
STATUS_BAR_HEIGHT = 132

FONT_DIR = ROOT / "assets/fonts"
LOCALE_FONT_FILE = {
    "ja": FONT_DIR / "NotoSerifJP-Regular.ttf",
    "ko": FONT_DIR / "NotoSerifKR-Regular.ttf",
    "zh-Hant": FONT_DIR / "NotoSerifTC-Regular.ttf",
    "ar": FONT_DIR / "NotoNaskhArabic-Regular.ttf",
    "th": FONT_DIR / "NotoSerifThai-Regular.ttf",
}
LATIN_REGULAR = FONT_DIR / "EBGaramond-Variable.ttf"
LATIN_ITALIC = FONT_DIR / "EBGaramond-Italic-Variable.ttf"

LOCALES = [
    "en", "tr", "ja", "de", "fr", "ko", "zh-Hant", "ar", "es",
    "pt-BR", "it", "th", "nl", "pl", "vi",
]

DEVICE_PLATES = {"02", "03", "09"}  # marketing header + fresh device capture
FULLBLEED_PLATES = {"05", "06", "07"}  # pure device capture, no marketing header
TEXT_ONLY_PLATES = {"01", "04", "08"}  # pure marketing typography, no device UI

MASTER_FILES = {
    "01": "1.png", "02": "2.png", "03": "3.png", "04": "4.png",
    "05": "5.png", "06": "6.png", "07": "7.png", "08": "8.png", "09": "9.png",
}

RAW_CAPTURE_NAME = {
    "02": "02_reveal", "03": "03_kept", "05": "05_pause",
    "06": "06_pause_feel", "07": "07_ask", "09": "09_keeper",
}


def _font(locale: str, italic: bool, size: int) -> ImageFont.FreeTypeFont:
    path = LOCALE_FONT_FILE.get(locale)
    if path is None:
        path = LATIN_ITALIC if italic else LATIN_REGULAR
    return ImageFont.truetype(str(path), size)


def _load_master(plate: str) -> Image.Image:
    return Image.open(MASTERS_SRC / MASTER_FILES[plate]).convert("RGB")


def _status_bar_strip() -> Image.Image:
    return Image.open(STATUS_BAR_STRIP).convert("RGB")


def _raw_capture(locale: str, plate: str) -> Image.Image:
    name = RAW_CAPTURE_NAME[plate]
    path = RAW_ROOT / locale / f"{name}.png"
    img = Image.open(path).convert("RGB")
    if img.size != CANVAS:
        img = img.resize(CANVAS, Image.Resampling.LANCZOS)
    return img


def _content_bbox(img: Image.Image, top: int) -> tuple[int, int, int, int]:
    """Tight bounding box of non-background pixels in `img[top:]`, so a
    screen whose real content (e.g. Keeper's `Center`-ed, `FittedBox`-scaled
    column) sits well short of the full raw-capture height never gets
    silently truncated by a fixed crop -- every plate finds its own actual
    content extent instead of assuming one.
    """
    px = img.load()
    w, h = img.size
    bg = px[4, top + 4]

    def row_has_content(y: int) -> bool:
        return any(px[x, y] != bg for x in range(0, w, 4))

    def col_has_content(x: int, y0: int, y1: int) -> bool:
        return any(px[x, y] != bg for y in range(y0, y1, 4))

    top_y = top
    for y in range(top, h):
        if row_has_content(y):
            top_y = y
            break
    bottom_y = h
    for y in range(h - 1, top, -1):
        if row_has_content(y):
            bottom_y = y + 1
            break
    left_x = 0
    for x in range(0, w):
        if col_has_content(x, top_y, bottom_y):
            left_x = x
            break
    right_x = w
    for x in range(w - 1, -1, -1):
        if col_has_content(x, top_y, bottom_y):
            right_x = x + 1
            break
    return (left_x, top_y, right_x, bottom_y)


def _fit_content_into(
    capture: Image.Image, target_w: int, target_h: int, margin: int = 16
) -> Image.Image:
    """Crops `capture`'s real content (below its blank status-bar gap) and
    scales it down -- never up -- so it fits `target_w`x`target_h` without
    clipping, matching how a shorter marketing "device window" than the raw
    capture's own full screen height must be reconciled. Centered on both
    axes; margins fill with `BACKGROUND` (identical to the canvas color, so
    the seam is invisible).
    """
    box = _content_bbox(capture, STATUS_BAR_HEIGHT)
    content = capture.crop(box)
    cw, ch = content.size
    scale = min(1.0, (target_w - 2 * margin) / cw, (target_h - 2 * margin) / ch)
    if scale < 1.0:
        content = content.resize(
            (max(1, round(cw * scale)), max(1, round(ch * scale))),
            Image.Resampling.LANCZOS,
        )
        cw, ch = content.size
    result = Image.new("RGB", (target_w, target_h), BACKGROUND)
    result.paste(content, ((target_w - cw) // 2, (target_h - ch) // 2))
    return result


#: Plates whose content is anchored immediately below the app's own top
#: navigation/app bar (Reveal, Kept) -- a simple top-anchored crop of the
#: raw capture already shows everything real content occupies, verified
#: against the repaired English masters.
_TOP_ANCHORED_DEVICE_PLATES = {"02", "03"}

#: Plates whose content is instead `Center`-ed across the *full* device
#: screen height (Keeper's `FittedBox` column) -- a fixed-height top crop
#: truncates their bottom rows, so these use `_fit_content_into` instead.
_CENTERED_DEVICE_PLATES = {"09"}


def _compose_device_region(canvas: Image.Image, locale: str, plate: str) -> None:
    """Pastes a fresh capture's status bar + content below `DIVIDER_Y`."""
    strip = _status_bar_strip()
    canvas.paste(strip, (0, DIVIDER_Y))
    capture = _raw_capture(locale, plate)
    remaining_height = CANVAS[1] - (DIVIDER_Y + STATUS_BAR_HEIGHT)
    if plate in _CENTERED_DEVICE_PLATES:
        fitted = _fit_content_into(capture, CANVAS[0], remaining_height)
        canvas.paste(fitted, (0, DIVIDER_Y + STATUS_BAR_HEIGHT))
        return
    content = capture.crop(
        (0, STATUS_BAR_HEIGHT, CANVAS[0], STATUS_BAR_HEIGHT + remaining_height)
    )
    canvas.paste(content, (0, DIVIDER_Y + STATUS_BAR_HEIGHT))


def _compose_fullbleed(locale: str, plate: str) -> Image.Image:
    """05/06/07: the target window (`CANVAS[1] - STATUS_BAR_HEIGHT`) is
    exactly the raw capture's own remaining height, so this is a plain
    status-bar-strip + 1:1 content copy -- no scaling needed or applied.
    """
    canvas = Image.new("RGB", CANVAS, BACKGROUND)
    strip = _status_bar_strip()
    canvas.paste(strip, (0, 0))
    capture = _raw_capture(locale, plate)
    content = capture.crop((0, STATUS_BAR_HEIGHT, CANVAS[0], CANVAS[1]))
    canvas.paste(content, (0, STATUS_BAR_HEIGHT))
    return canvas


def build_english_master(plate: str) -> Image.Image:
    if plate == "02":
        canvas = _load_master(plate).crop((0, 0, CANVAS[0], DIVIDER_Y))
        full = Image.new("RGB", CANVAS, BACKGROUND)
        full.paste(canvas, (0, 0))
        _compose_device_region(full, "en", plate)
        return full
    if plate == "03":
        canvas = _load_master(plate).crop((0, 0, CANVAS[0], DIVIDER_Y))
        full = Image.new("RGB", CANVAS, BACKGROUND)
        full.paste(canvas, (0, 0))
        _compose_device_region(full, "en", plate)
        return full
    if plate == "09":
        canvas = _load_master(plate).crop((0, 0, CANVAS[0], DIVIDER_Y))
        full = Image.new("RGB", CANVAS, BACKGROUND)
        full.paste(canvas, (0, 0))
        _compose_device_region(full, "en", plate)
        return full
    if plate in FULLBLEED_PLATES:
        # Deterministic export normalization only: upscale the existing
        # accepted raw capture to the canonical canvas -- content pixels
        # are resampled, never redrawn/replaced.
        src = _load_master(plate)
        if src.size != CANVAS:
            src = src.resize(CANVAS, Image.Resampling.LANCZOS)
        return src
    # 01, 04, 08: unchanged.
    return _load_master(plate)


COPY: dict[str, dict[str, dict]] = {
    "tr": {
        "01": {"subhead": "Çoğu uygulama dikkatinden daha fazlasını ister.",
               "headline1": "EAST. senden tek", "headline2": "bir an istiyor.",
               "footer": "GÜNLÜK BİR YANSIMA RİTÜELİ"},
        "02": {"kicker": "AÇILIŞ", "headline1": "Bir bilgelik.", "headline2": "Her 24 saatte bir.",
               "caption": "AKIŞ YOK. AÇILACAK BAŞKA BİR ŞEY YOK."},
        "03": {"kicker": "KALANLAR · YANSIMALAR", "headline1": "Tuttuğun,", "headline2": "geri döner.",
               "caption": "KALAN SÖZLER VE KENDİ YANSIMALARIN, BİR ARADA."},
        "04": {"kicker": "RİTÜEL — DÖRT HAREKET", "pause": "Bekle.", "feel": "Hisset.",
               "ask": "Soruyu kalbinden sor.", "reveal": "Açığa çık.",
               "footer1": "SONRA YİRMİ DÖRT SAATLİK BİR BOŞLUK",
               "footer2": "AKIŞ YOK · SERİ YOK · HESAP YOK"},
        "08": {"kicker": "EAST.'TA OLMAYANLAR", "list": ["Akış yok.", "Seri yok.", "Reklam yok.", "Hesap yok."],
               "headline1": "Sessiz bir an.", "headline2": "Her gün.", "footer": "TASARIMDAN GELEN GİZLİLİK"},
        "09": {"headline1": "Çembere", "headline2": "katıl.", "caption": "TUTUCU — TEK SEFERLİK SATIN ALMA"},
    },
    "ja": {
        "01": {"subhead": "多くのアプリはさらに多くの関心を求める。",
               "headline1": "EAST.が求めるのは", "headline2": "ただ一瞬。",
               "footer": "内省のための日々の儀式"},
        "02": {"kicker": "リビール", "headline1": "ひとつの知恵。", "headline2": "24時間ごとに。",
               "caption": "フィードはない。開くものは他にない。"},
        "03": {"kicker": "残したもの・内省", "headline1": "残したものは、", "headline2": "戻ってくる。",
               "caption": "残した知恵と、あなた自身の内省が、ともに。"},
        "04": {"kicker": "儀式 — 四つの動き", "pause": "立ち止まる。", "feel": "感じる。",
               "ask": "心から問いかける。", "reveal": "現れる。",
               "footer1": "そして二十四時間の静けさ",
               "footer2": "フィードなし · 連続記録なし · アカウントなし"},
        "08": {"kicker": "EAST.にないもの", "list": ["フィードはない。", "連続記録はない。", "広告はない。", "アカウントはない。"],
               "headline1": "静かなひととき。", "headline2": "毎日。", "footer": "設計による、プライバシー"},
        "09": {"headline1": "輪の", "headline2": "中へ。", "caption": "残す — 一回限りの購入"},
    },
    "de": {
        "01": {"subhead": "Die meisten Apps verlangen mehr von deiner Aufmerksamkeit.",
               "headline1": "EAST. bittet um", "headline2": "einen Moment.",
               "footer": "EIN TÄGLICHES RITUAL DER BESINNUNG"},
        "02": {"kicker": "DIE OFFENBARUNG", "headline1": "Eine Weisheit.", "headline2": "Alle 24 Stunden.",
               "caption": "KEIN FEED. NICHTS WEITER ZU ÖFFNEN."},
        "03": {"kicker": "BEWAHRT · REFLEXIONEN", "headline1": "Was du bewahrst,", "headline2": "kehrt zurück.",
               "caption": "BEWAHRTE WEISHEIT UND DEINE EIGENEN REFLEXIONEN, VEREINT."},
        "04": {"kicker": "DAS RITUAL — VIER BEWEGUNGEN", "pause": "Innehalten.", "feel": "Spüren.",
               "ask": "Von Herzen fragen.", "reveal": "Enthüllen.",
               "footer1": "DANN VIERUNDZWANZIG STUNDEN STILLE",
               "footer2": "KEIN FEED · KEINE SERIE · KEIN KONTO"},
        "08": {"kicker": "WAS EAST. NICHT HAT", "list": ["Kein Feed.", "Keine Serie.", "Keine Werbung.", "Kein Konto."],
               "headline1": "Ein stiller Moment.", "headline2": "Jeden Tag.", "footer": "PRIVAT VON GRUND AUF"},
        "09": {"headline1": "Komm in", "headline2": "den Kreis.", "caption": "BEWAHREN — EINMALIGER KAUF"},
    },
    "fr": {
        "01": {"subhead": "La plupart des applications réclament toujours plus d'attention.",
               "headline1": "EAST. demande", "headline2": "un instant.",
               "footer": "UN RITUEL QUOTIDIEN DE RÉFLEXION"},
        "02": {"kicker": "LA RÉVÉLATION", "headline1": "Une sagesse.", "headline2": "Toutes les 24 heures.",
               "caption": "PAS DE FIL. RIEN D'AUTRE À OUVRIR."},
        "03": {"kicker": "CE QUI RESTE · RÉFLEXIONS", "headline1": "Ce que tu gardes", "headline2": "te revient.",
               "caption": "SAGESSE GARDÉE ET TES PROPRES RÉFLEXIONS, RÉUNIES."},
        "04": {"kicker": "LE RITUEL — QUATRE MOUVEMENTS", "pause": "Pause.", "feel": "Ressens.",
               "ask": "Demande avec le cœur.", "reveal": "Révèle.",
               "footer1": "PUIS VINGT-QUATRE HEURES D'ESPACE",
               "footer2": "PAS DE FIL · PAS DE SÉRIE · PAS DE COMPTE"},
        "08": {"kicker": "CE QUE EAST. N'A PAS", "list": ["Pas de fil.", "Pas de série.", "Pas de publicité.", "Pas de compte."],
               "headline1": "Un instant calme.", "headline2": "Chaque jour.", "footer": "PRIVÉ PAR CONCEPTION"},
        "09": {"headline1": "Entre dans", "headline2": "le cercle.", "caption": "GARDER — ACHAT UNIQUE"},
    },
    "ko": {
        "01": {"subhead": "대부분의 앱은 더 많은 관심을 요구합니다.",
               "headline1": "EAST.가 청하는 건", "headline2": "단 한 순간.",
               "footer": "성찰을 위한 하루의 의식"},
        "02": {"kicker": "리빌", "headline1": "하나의 지혜.", "headline2": "24시간마다.",
               "caption": "피드가 없습니다. 더 열어볼 것도 없습니다."},
        "03": {"kicker": "남은 것 · 성찰", "headline1": "간직한 것은,", "headline2": "돌아옵니다.",
               "caption": "간직한 지혜와 당신의 성찰이, 함께."},
        "04": {"kicker": "의식 — 네 가지 움직임", "pause": "잠시.", "feel": "느끼다.",
               "ask": "마음으로 묻다.", "reveal": "드러나다.",
               "footer1": "그리고 스물네 시간의 여백",
               "footer2": "피드 없음 · 연속 기록 없음 · 계정 없음"},
        "08": {"kicker": "EAST.에 없는 것", "list": ["피드가 없습니다.", "연속 기록이 없습니다.", "광고가 없습니다.", "계정이 없습니다."],
               "headline1": "고요한 한 순간.", "headline2": "매일.", "footer": "설계부터 사적인"},
        "09": {"headline1": "원", "headline2": "안으로.", "caption": "간직 — 일회성 구매"},
    },
    "zh-Hant": {
        "01": {"subhead": "多數應用程式渴求你更多的注意力。",
               "headline1": "EAST. 只求", "headline2": "一刻。",
               "footer": "一場日常的省思儀式"},
        "02": {"kicker": "揭曉", "headline1": "一句智慧。", "headline2": "每二十四小時。",
               "caption": "沒有動態消息。沒有其他可開啟的東西。"},
        "03": {"kicker": "留下的 · 省思", "headline1": "你留下的,", "headline2": "會再回來。",
               "caption": "留下的智慧與你自己的省思,共存於此。"},
        "04": {"kicker": "儀式 — 四個時刻", "pause": "停一停。", "feel": "感受。",
               "ask": "從心裡提問。", "reveal": "揭曉。",
               "footer1": "接著是二十四小時的留白",
               "footer2": "沒有動態消息 · 沒有連續紀錄 · 沒有帳號"},
        "08": {"kicker": "EAST. 沒有的東西", "list": ["沒有動態消息。", "沒有連續紀錄。", "沒有廣告。", "沒有帳號。"],
               "headline1": "安靜的片刻。", "headline2": "每一天。", "footer": "從設計開始的隱私"},
        "09": {"headline1": "走進", "headline2": "圓圈。", "caption": "留住 — 單次購買"},
    },
    "ar": {
        "01": {"subhead": "معظم التطبيقات تطلب المزيد من انتباهك.",
               "headline1": "EAST. تطلب", "headline2": "لحظة واحدة فقط.",
               "footer": "طقس يومي للتأمُّل"},
        "02": {"kicker": "الكشف", "headline1": "حكمة واحدة.", "headline2": "كل 24 ساعة.",
               "caption": "لا تغذية إخبارية. لا شيء آخر لفتحه."},
        "03": {"kicker": "ما بقي · تأمُّلات", "headline1": "ما تحتفظ به", "headline2": "يعود إليك.",
               "caption": "الحكمة المحفوظة وتأمُّلاتك الخاصة، معًا."},
        "04": {"kicker": "الطقس — أربع حركات", "pause": "تمهّل.", "feel": "اشعر.",
               "ask": "اسأل من قلبك.", "reveal": "تكشّف.",
               "footer1": "ثم أربع وعشرون ساعة من الفراغ",
               "footer2": "لا تغذية إخبارية · لا تتابع · لا حساب"},
        "08": {"kicker": "ما لا يملكه EAST.", "list": ["لا تغذية إخبارية.", "لا تتابع.", "لا إعلانات.", "لا حساب."],
               "headline1": "لحظة هادئة.", "headline2": "كل يوم.", "footer": "خصوصية بالتصميم"},
        "09": {"headline1": "ادخل", "headline2": "الدائرة.", "caption": "احتفظ — شراء لمرة واحدة"},
    },
    "es": {
        "01": {"subhead": "La mayoría de las apps piden más de tu atención.",
               "headline1": "EAST. pide", "headline2": "un instante.",
               "footer": "UN RITUAL DIARIO DE REFLEXIÓN"},
        "02": {"kicker": "LA REVELACIÓN", "headline1": "Una sabiduría.", "headline2": "Cada 24 horas.",
               "caption": "SIN FEED. NADA MÁS QUE ABRIR."},
        "03": {"kicker": "LO QUE QUEDA · REFLEXIONES", "headline1": "Lo que guardas", "headline2": "vuelve a ti.",
               "caption": "SABIDURÍA GUARDADA Y TUS PROPIAS REFLEXIONES, JUNTAS."},
        "04": {"kicker": "EL RITUAL — CUATRO MOVIMIENTOS", "pause": "Pausa.", "feel": "Siente.",
               "ask": "Pregunta desde el corazón.", "reveal": "Revela.",
               "footer1": "LUEGO, VEINTICUATRO HORAS DE ESPACIO",
               "footer2": "SIN FEED · SIN RACHAS · SIN CUENTA"},
        "08": {"kicker": "LO QUE EAST. NO TIENE", "list": ["Sin feed.", "Sin rachas.", "Sin anuncios.", "Sin cuenta."],
               "headline1": "Un instante quieto.", "headline2": "Cada día.", "footer": "PRIVADO DESDE EL DISEÑO"},
        "09": {"headline1": "Entra en", "headline2": "el círculo.", "caption": "GUARDAR — COMPRA ÚNICA"},
    },
    "pt-BR": {
        "01": {"subhead": "A maioria dos apps pede mais da sua atenção.",
               "headline1": "O EAST. pede", "headline2": "um instante.",
               "footer": "UM RITUAL DIÁRIO DE REFLEXÃO"},
        "02": {"kicker": "A REVELAÇÃO", "headline1": "Uma sabedoria.", "headline2": "A cada 24 horas.",
               "caption": "SEM FEED. NADA MAIS PARA ABRIR."},
        "03": {"kicker": "O QUE FICOU · REFLEXÕES", "headline1": "O que você guarda", "headline2": "volta a você.",
               "caption": "SABEDORIA GUARDADA E SUAS PRÓPRIAS REFLEXÕES, JUNTAS."},
        "04": {"kicker": "O RITUAL — QUATRO MOVIMENTOS", "pause": "Pausa.", "feel": "Sinta.",
               "ask": "Pergunte com o coração.", "reveal": "Revele-se.",
               "footer1": "DEPOIS, VINTE E QUATRO HORAS DE ESPAÇO",
               "footer2": "SEM FEED · SEM SEQUÊNCIA · SEM CONTA"},
        "08": {"kicker": "O QUE O EAST. NÃO TEM", "list": ["Sem feed.", "Sem sequência.", "Sem anúncios.", "Sem conta."],
               "headline1": "Um instante quieto.", "headline2": "Todos os dias.", "footer": "PRIVADO DESDE O DESIGN"},
        "09": {"headline1": "Entre no", "headline2": "círculo.", "caption": "GUARDAR — COMPRA ÚNICA"},
    },
    "it": {
        "01": {"subhead": "La maggior parte delle app chiede sempre più attenzione.",
               "headline1": "EAST. chiede", "headline2": "un istante.",
               "footer": "UN RITUALE QUOTIDIANO DI RIFLESSIONE"},
        "02": {"kicker": "LA RIVELAZIONE", "headline1": "Una saggezza.", "headline2": "Ogni 24 ore.",
               "caption": "NESSUN FEED. NIENT'ALTRO DA APRIRE."},
        "03": {"kicker": "CIÒ CHE RESTA · RIFLESSIONI", "headline1": "Ciò che custodisci", "headline2": "ritorna a te.",
               "caption": "SAGGEZZA CUSTODITA E LE TUE RIFLESSIONI, INSIEME."},
        "04": {"kicker": "IL RITUALE — QUATTRO MOVIMENTI", "pause": "Pausa.", "feel": "Senti.",
               "ask": "Chiedi con il cuore.", "reveal": "Rivela.",
               "footer1": "POI VENTIQUATTRO ORE DI SPAZIO",
               "footer2": "NESSUN FEED · NESSUNA SERIE · NESSUN ACCOUNT"},
        "08": {"kicker": "CIÒ CHE EAST. NON HA", "list": ["Nessun feed.", "Nessuna serie.", "Nessuna pubblicità.", "Nessun account."],
               "headline1": "Un istante quieto.", "headline2": "Ogni giorno.", "footer": "PRIVATO FIN DAL PRINCIPIO"},
        "09": {"headline1": "Entra nel", "headline2": "cerchio.", "caption": "CUSTODIRE — ACQUISTO UNICO"},
    },
    "th": {
        "01": {"subhead": "แอปส่วนใหญ่ขอความสนใจจากคุณมากขึ้นเรื่อยๆ",
               "headline1": "EAST. ขอเพียง", "headline2": "หนึ่งชั่วขณะ",
               "footer": "พิธีกรรมแห่งการไตร่ตรองในแต่ละวัน"},
        "02": {"kicker": "การเผย", "headline1": "ข้อคิดหนึ่งข้อ", "headline2": "ทุก 24 ชั่วโมง",
               "caption": "ไม่มีฟีด ไม่มีอะไรอื่นให้เปิด"},
        "03": {"kicker": "สิ่งที่เก็บไว้ · การไตร่ตรอง", "headline1": "สิ่งที่คุณเก็บไว้", "headline2": "ย้อนกลับมาหาคุณ",
               "caption": "ข้อคิดที่เก็บไว้และการไตร่ตรองของคุณเอง อยู่ด้วยกัน"},
        "04": {"kicker": "พิธีกรรม — สี่ช่วงเวลา", "pause": "ชั่วครู่.", "feel": "รู้สึก.",
               "ask": "ถามจากใจ.", "reveal": "เผยออกมา.",
               "footer1": "จากนั้นคือยี่สิบสี่ชั่วโมงแห่งความว่าง",
               "footer2": "ไม่มีฟีด · ไม่มีสตรีค · ไม่มีบัญชี"},
        "08": {"kicker": "สิ่งที่ EAST. ไม่มี", "list": ["ไม่มีฟีด.", "ไม่มีสตรีค.", "ไม่มีโฆษณา.", "ไม่มีบัญชี."],
               "headline1": "ช่วงเวลาแห่งความสงบ", "headline2": "ทุกวัน", "footer": "เป็นส่วนตัวตั้งแต่การออกแบบ"},
        "09": {"headline1": "เข้ามา", "headline2": "ในวง.", "caption": "คงไว้ — ซื้อครั้งเดียว"},
    },
    "nl": {
        "01": {"subhead": "De meeste apps vragen steeds meer van je aandacht.",
               "headline1": "EAST. vraagt om", "headline2": "één moment.",
               "footer": "EEN DAGELIJKS RITUEEL VAN REFLECTIE"},
        "02": {"kicker": "DE ONTHULLING", "headline1": "Eén wijsheid.", "headline2": "Elke 24 uur.",
               "caption": "GEEN FEED. NIETS ANDERS TE OPENEN."},
        "03": {"kicker": "WAT BLIJFT · REFLECTIES", "headline1": "Wat je bewaart,", "headline2": "keert terug.",
               "caption": "BEWAARDE WIJSHEID EN JE EIGEN REFLECTIES, SAMEN."},
        "04": {"kicker": "HET RITUEEL — VIER BEWEGINGEN", "pause": "Pauze.", "feel": "Voel.",
               "ask": "Vraag vanuit je hart.", "reveal": "Onthul.",
               "footer1": "DAARNA VIERENTWINTIG UUR RUIMTE",
               "footer2": "GEEN FEED · GEEN REEKS · GEEN ACCOUNT"},
        "08": {"kicker": "WAT EAST. NIET HEEFT", "list": ["Geen feed.", "Geen reeks.", "Geen advertenties.", "Geen account."],
               "headline1": "Eén stil moment.", "headline2": "Elke dag.", "footer": "PRIVÉ VANAF HET ONTWERP"},
        "09": {"headline1": "Stap in", "headline2": "de cirkel.", "caption": "BEWAREN — EENMALIGE AANKOOP"},
    },
    "pl": {
        "01": {"subhead": "Większość aplikacji domaga się coraz więcej twojej uwagi.",
               "headline1": "EAST. prosi", "headline2": "o jedną chwilę.",
               "footer": "CODZIENNY RYTUAŁ REFLEKSJI"},
        "02": {"kicker": "OBJAWIENIE", "headline1": "Jedna mądrość.", "headline2": "Co 24 godziny.",
               "caption": "BEZ KANAŁU. NIC WIĘCEJ DO OTWARCIA."},
        "03": {"kicker": "ZACHOWANE · REFLEKSJE", "headline1": "To, co zachowasz,", "headline2": "wraca do ciebie.",
               "caption": "ZACHOWANA MĄDROŚĆ I TWOJE WŁASNE REFLEKSJE, RAZEM."},
        "04": {"kicker": "RYTUAŁ — CZTERY RUCHY", "pause": "Zatrzymaj się.", "feel": "Poczuj.",
               "ask": "Zapytaj prosto z serca.", "reveal": "Odsłoń się.",
               "footer1": "POTEM DWADZIEŚCIA CZTERY GODZINY PRZESTRZENI",
               "footer2": "BEZ KANAŁU · BEZ SERII · BEZ KONTA"},
        "08": {"kicker": "CZEGO EAST. NIE MA", "list": ["Bez kanału.", "Bez serii.", "Bez reklam.", "Bez konta."],
               "headline1": "Cicha chwila.", "headline2": "Każdego dnia.", "footer": "PRYWATNE OD PROJEKTU"},
        "09": {"headline1": "Wejdź do", "headline2": "kręgu.", "caption": "ZACHOWAĆ — JEDNORAZOWY ZAKUP"},
    },
    "vi": {
        "01": {"subhead": "Hầu hết các ứng dụng đòi hỏi ngày càng nhiều sự chú ý của bạn.",
               "headline1": "EAST. chỉ xin", "headline2": "một khoảnh khắc.",
               "footer": "MỘT NGHI THỨC SUY NGẪM MỖI NGÀY"},
        "02": {"kicker": "SỰ HÉ LỘ", "headline1": "Một điều minh triết.", "headline2": "Mỗi 24 giờ.",
               "caption": "KHÔNG CÓ BẢNG TIN. KHÔNG CÒN GÌ KHÁC ĐỂ MỞ."},
        "03": {"kicker": "ĐIỀU CÒN LẠI · SUY NGẪM", "headline1": "Điều bạn giữ lại,", "headline2": "sẽ quay về.",
               "caption": "MINH TRIẾT ĐÃ GIỮ VÀ SUY NGẪM CỦA RIÊNG BẠN, CÙNG NHAU."},
        "04": {"kicker": "NGHI THỨC — BỐN CHUYỂN ĐỘNG", "pause": "Lắng lại.", "feel": "Cảm nhận.",
               "ask": "Hỏi bằng tấm lòng.", "reveal": "Hé lộ.",
               "footer1": "RỒI ĐẾN HAI MƯƠI BỐN GIỜ TĨNH LẶNG",
               "footer2": "KHÔNG BẢNG TIN · KHÔNG CHUỖI NGÀY · KHÔNG TÀI KHOẢN"},
        "08": {"kicker": "ĐIỀU EAST. KHÔNG CÓ", "list": ["Không bảng tin.", "Không chuỗi ngày.", "Không quảng cáo.", "Không tài khoản."],
               "headline1": "Một khoảnh khắc tĩnh lặng.", "headline2": "Mỗi ngày.", "footer": "RIÊNG TƯ NGAY TỪ THIẾT KẾ"},
        "09": {"headline1": "Bước vào", "headline2": "vòng tròn.", "caption": "GIỮ LẠI — MUA MỘT LẦN"},
    },
}

SECONDARY = (98, 93, 84)  # #625D54
CAPTION = (98, 93, 84)


def _reshape_arabic(text: str) -> str:
    """Converts logical-order Arabic text into shaped, visual-order glyphs.
    Pillow has no `raqm` binding in this environment (`features.check
    ('raqm')` is False), so it never joins Arabic letterforms or reorders
    RTL runs on its own -- drawn as-is, Arabic renders as reversed, isolated
    (unjoined) characters. `arabic_reshaper` + `python-bidi` do that shaping/
    reordering up front instead, so the rest of this module can keep
    treating every string as plain left-to-right-drawable text.
    """
    return get_display(arabic_reshaper.reshape(text))


def _wrap(
    draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, max_width: int, locale: str = ""
) -> list[str]:
    """Greedy word-wrap (character-wrap for scripts with no ASCII spaces)."""
    if locale != "ar" and " " not in text.strip():
        # CJK/Thai-style: wrap by character instead of by word. Never for
        # Arabic -- breaking a cursive run mid-word loses letter joining.
        lines: list[str] = []
        current = ""
        for ch in text:
            trial = current + ch
            if draw.textlength(trial, font=font) <= max_width or not current:
                current = trial
            else:
                lines.append(current)
                current = ch
        if current:
            lines.append(current)
        return lines
    words = text.split(" ")
    lines = []
    current = ""
    for word in words:
        trial = f"{current} {word}".strip()
        if draw.textlength(trial, font=font) <= max_width or not current:
            current = trial
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def _draw_block(
    canvas: Image.Image,
    box: tuple[int, int, int, int],
    lines: list[tuple[str, bool, tuple[int, int, int]]],
    locale: str,
    size: int,
    line_gap: int = 10,
    align: str = "left",
    tracking: float = 0.0,
    min_size: int = 14,
    strike: bool = False,
    erase: bool = True,
) -> None:
    """Erases `box` (fills with BACKGROUND) then draws `lines` -- each
    (text, italic, color) -- word-wrapped to the box width, shrinking `size`
    (never below `min_size`) only if the natural translation still overflows
    the box height. `tracking` adds extra letter-spacing (uppercase kickers).
    """
    x0, y0, x1, y1 = box
    if erase:
        ImageDraw.Draw(canvas).rectangle(box, fill=BACKGROUND)
    draw = ImageDraw.Draw(canvas)
    max_width = x1 - x0

    if locale == "ar":
        # Arabic has no uppercase/tracked-caps convention, and reads right
        # to left -- override both regardless of what the caller passed.
        tracking = 0.0
        if align == "left":
            align = "right"

    def _tracked(draw_, text, font):
        if tracking <= 0 or not text:
            return draw_.textlength(text, font=font) + tracking * max(0, len(text) - 1)
        return sum(draw_.textlength(ch, font=font) + tracking for ch in text) - tracking

    def _draw_tracked(draw_, xy, text, font, fill):
        if tracking <= 0:
            draw_.text(xy, text, font=font, fill=fill)
            return
        x, y = xy
        for ch in text:
            draw_.text((x, y), ch, font=font, fill=fill)
            x += draw_.textlength(ch, font=font) + tracking

    cur_size = size
    while cur_size >= min_size:
        fonts = [_font(locale, italic, cur_size) for _, italic, _ in lines]
        wrapped: list[tuple[list[str], ImageFont.FreeTypeFont, tuple[int, int, int]]] = []
        for (text, italic, color), font in zip(lines, fonts):
            para_lines = _wrap(draw, text, font, max_width, locale) if not tracking else [text]
            wrapped.append((para_lines, font, color))
        line_h = int(cur_size * 1.28)
        total_h = sum(len(p) for p, _, _ in wrapped) * line_h + line_gap * (len(wrapped) - 1)
        if total_h <= (y1 - y0) or cur_size <= min_size:
            break
        cur_size -= 2

    y = y0
    for para_lines, font, color in wrapped:
        for line in para_lines:
            if locale == "ar":
                line = _reshape_arabic(line)
            w = _tracked(draw, line, font) if tracking else draw.textlength(line, font=font)
            if align == "left":
                x = x0
            elif align == "right":
                x = x1 - w
            else:
                x = x0 + (max_width - w) / 2
            if tracking:
                _draw_tracked(draw, (x, y), line, font, color)
            else:
                draw.text((x, y), line, font=font, fill=color)
            if strike:
                strike_y = y + cur_size * 0.42
                draw.line([(x, strike_y), (x + w, strike_y)], fill=color, width=max(2, cur_size // 20))
            y += line_h
        y += line_gap


def build_localized_plate(locale: str, plate: str, copy: dict) -> Image.Image:
    if plate in FULLBLEED_PLATES:
        return _compose_fullbleed(locale, plate)

    if plate in DEVICE_PLATES:
        base = _load_master(plate).crop((0, 0, CANVAS[0], DIVIDER_Y))
        canvas = Image.new("RGB", CANVAS, BACKGROUND)
        canvas.paste(base, (0, 0))
    else:
        canvas = _load_master(plate).copy()

    p = copy[plate]

    if plate == "01":
        _draw_block(canvas, (60, 530, 1180, 710), [(p["subhead"], False, SECONDARY)], locale, 46, align="left")
        _draw_block(
            canvas, (60, 1090, 1200, 1370),
            [(p["headline1"], False, (44, 41, 36)), (p["headline2"], True, SECONDARY)],
            locale, 80, align="left",
        )
        _draw_block(canvas, (60, 2495, 1200, 2565), [(p["footer"], False, SECONDARY)], locale, 24, tracking=3.0)
        return canvas

    if plate == "04":
        _draw_block(canvas, (60, 130, 1000, 200), [(p["kicker"], False, SECONDARY)], locale, 24, tracking=3.0)
        _draw_block(canvas, (60, 520, 850, 665), [(p["pause"], False, (44, 41, 36))], locale, 96)
        _draw_block(canvas, (60, 860, 850, 1010), [(p["feel"], False, (44, 41, 36))], locale, 96)
        _draw_block(canvas, (60, 1225, 950, 1475), [(p["ask"], True, SECONDARY)], locale, 68)
        _draw_block(canvas, (60, 1735, 1050, 1915), [(p["reveal"], False, (28, 27, 25))], locale, 108)
        _draw_block(canvas, (60, 2230, 1200, 2300), [(p["footer1"], False, SECONDARY)], locale, 24, tracking=3.0)
        _draw_block(canvas, (60, 2430, 1200, 2500), [(p["footer2"], False, (147, 141, 130))], locale, 24, tracking=3.0)
        return canvas

    if plate == "08":
        _draw_block(canvas, (60, 105, 1000, 175), [(p["kicker"], False, SECONDARY)], locale, 24, tracking=3.0)
        _draw_block(
            canvas, (60, 345, 750, 670),
            [(line, False, SECONDARY) for line in p["list"]],
            locale, 48, line_gap=6, strike=True,
        )
        _draw_block(
            canvas, (60, 1040, 1200, 1300),
            [(p["headline1"], False, (44, 41, 36)), (p["headline2"], True, SECONDARY)],
            locale, 66,
        )
        _draw_block(canvas, (60, 2495, 1200, 2565), [(p["footer"], False, SECONDARY)], locale, 24, tracking=3.0, align="left")
        return canvas

    if plate == "02":
        _draw_block(canvas, (60, 105, 750, 175), [(p["kicker"], False, SECONDARY)], locale, 24, tracking=3.0)
        _draw_block(
            canvas, (60, 310, 1200, 545),
            [(p["headline1"], False, (44, 41, 36)), (p["headline2"], True, SECONDARY)],
            locale, 66,
        )
        _draw_block(canvas, (60, 600, 1200, 670), [(p["caption"], False, SECONDARY)], locale, 23, tracking=2.5)
        _compose_device_region(canvas, locale, plate)
        return canvas

    if plate == "03":
        _draw_block(canvas, (60, 105, 900, 175), [(p["kicker"], False, SECONDARY)], locale, 24, tracking=3.0)
        _draw_block(
            canvas, (60, 310, 1200, 530),
            [(p["headline1"], False, (44, 41, 36)), (p["headline2"], True, SECONDARY)],
            locale, 66,
        )
        _draw_block(canvas, (60, 600, 1200, 670), [(p["caption"], False, SECONDARY)], locale, 23, tracking=2.5)
        _compose_device_region(canvas, locale, plate)
        return canvas

    if plate == "09":
        _draw_block(
            canvas, (60, 445, 1200, 675),
            [(p["headline1"], False, (44, 41, 36)), (p["headline2"], True, SECONDARY)],
            locale, 78,
        )
        _draw_block(canvas, (60, 675, 1200, 745), [(p["caption"], False, SECONDARY)], locale, 22, tracking=2.5)
        _compose_device_region(canvas, locale, plate)
        return canvas

    raise AssertionError(plate)


def main() -> None:
    import sys

    only_locales = sys.argv[1:] or LOCALES
    OUT_ROOT.mkdir(parents=True, exist_ok=True)

    if "en" in only_locales:
        en_dir = OUT_ROOT / "en"
        en_dir.mkdir(parents=True, exist_ok=True)
        for plate in [f"{i:02d}" for i in range(1, 10)]:
            img = build_english_master(plate)
            assert img.size == CANVAS, (plate, img.size)
            img.save(en_dir / f"{plate}.png", format="PNG", optimize=True)
            print(f"en/{plate}.png written ({img.size[0]}x{img.size[1]})")

    for locale in only_locales:
        if locale == "en":
            continue
        out_dir = OUT_ROOT / locale
        out_dir.mkdir(parents=True, exist_ok=True)
        for plate in [f"{i:02d}" for i in range(1, 10)]:
            img = build_localized_plate(locale, plate, COPY[locale])
            assert img.size == CANVAS, (locale, plate, img.size)
            img.save(out_dir / f"{plate}.png", format="PNG", optimize=True)
            print(f"{locale}/{plate}.png written ({img.size[0]}x{img.size[1]})")


if __name__ == "__main__":
    main()
