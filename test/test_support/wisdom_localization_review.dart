/// Review artifact for a wisdom that has not met every production criterion.
///
/// Unresolved entries never appear in a reviewed locale catalog. Keeping the
/// review details with the tests makes omission explicit and auditable without
/// exposing QA-only models from the production package.
class UnresolvedWisdomLocalization {
  const UnresolvedWisdomLocalization({
    required this.locale,
    required this.wisdomId,
    required this.englishSource,
    required this.bestCandidate,
    required this.blindBackMeaning,
    required this.failureReason,
    required this.failedDimensions,
    required this.alternativeCandidates,
  });

  final String locale;
  final String wisdomId;
  final String englishSource;
  final String bestCandidate;
  final String blindBackMeaning;
  final String failureReason;
  final List<String> failedDimensions;
  final List<String> alternativeCandidates;
}

/// Locale-level QA facts recorded when a reviewed corpus is admitted.
class WisdomLocalizationReviewSummary {
  const WisdomLocalizationReviewSummary({
    required this.qaRewriteCount,
    required this.finalFontRenderQaRequired,
    required this.obviousLayoutRiskCount,
  });

  final int qaRewriteCount;
  final bool finalFontRenderQaRequired;
  final int obviousLayoutRiskCount;
}

const Map<String, List<UnresolvedWisdomLocalization>>
    unresolvedWisdomLocalizations =
    <String, List<UnresolvedWisdomLocalization>>{
  'ja': <UnresolvedWisdomLocalization>[],
  'de': <UnresolvedWisdomLocalization>[],
  'fr': <UnresolvedWisdomLocalization>[],
  'ko': <UnresolvedWisdomLocalization>[],
  'zh-Hant': <UnresolvedWisdomLocalization>[],
  'ar': <UnresolvedWisdomLocalization>[],
  'es': <UnresolvedWisdomLocalization>[],
  'pt-BR': <UnresolvedWisdomLocalization>[],
  'it': <UnresolvedWisdomLocalization>[],
  'th': <UnresolvedWisdomLocalization>[],
  'nl': <UnresolvedWisdomLocalization>[],
  'pl': <UnresolvedWisdomLocalization>[],
  'vi': <UnresolvedWisdomLocalization>[],
};

const Map<String, WisdomLocalizationReviewSummary>
    wisdomLocalizationReviewSummaries =
    <String, WisdomLocalizationReviewSummary>{
  'ja': WisdomLocalizationReviewSummary(
    qaRewriteCount: 50,
    finalFontRenderQaRequired: false,
    obviousLayoutRiskCount: 0,
  ),
  'de': WisdomLocalizationReviewSummary(
    qaRewriteCount: 96,
    finalFontRenderQaRequired: false,
    obviousLayoutRiskCount: 0,
  ),
  'fr': WisdomLocalizationReviewSummary(
    qaRewriteCount: 65,
    finalFontRenderQaRequired: false,
    obviousLayoutRiskCount: 0,
  ),
  'ko': WisdomLocalizationReviewSummary(
    qaRewriteCount: 15,
    finalFontRenderQaRequired: false,
    obviousLayoutRiskCount: 0,
  ),
  'zh-Hant': WisdomLocalizationReviewSummary(
    qaRewriteCount: 16,
    finalFontRenderQaRequired: false,
    obviousLayoutRiskCount: 0,
  ),
  'ar': WisdomLocalizationReviewSummary(
    qaRewriteCount: 33,
    finalFontRenderQaRequired: false,
    obviousLayoutRiskCount: 0,
  ),
  'es': WisdomLocalizationReviewSummary(
    qaRewriteCount: 49,
    finalFontRenderQaRequired: false,
    obviousLayoutRiskCount: 0,
  ),
  'pt-BR': WisdomLocalizationReviewSummary(
    qaRewriteCount: 53,
    finalFontRenderQaRequired: false,
    obviousLayoutRiskCount: 0,
  ),
  'it': WisdomLocalizationReviewSummary(
    qaRewriteCount: 56,
    finalFontRenderQaRequired: false,
    obviousLayoutRiskCount: 0,
  ),
  'th': WisdomLocalizationReviewSummary(
    qaRewriteCount: 7,
    finalFontRenderQaRequired: false,
    obviousLayoutRiskCount: 0,
  ),
  'nl': WisdomLocalizationReviewSummary(
    qaRewriteCount: 43,
    finalFontRenderQaRequired: false,
    obviousLayoutRiskCount: 0,
  ),
  'pl': WisdomLocalizationReviewSummary(
    qaRewriteCount: 40,
    finalFontRenderQaRequired: false,
    obviousLayoutRiskCount: 0,
  ),
  'vi': WisdomLocalizationReviewSummary(
    qaRewriteCount: 47,
    finalFontRenderQaRequired: false,
    obviousLayoutRiskCount: 0,
  ),
};
