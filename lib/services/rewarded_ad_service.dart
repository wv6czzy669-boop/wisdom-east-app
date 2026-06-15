import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class RewardedAdService {
  RewardedAd? rewardedAd;

  bool _isDisposed = false;

  bool isRewardedAdReady = false;
  bool isLoadingRewardedAd = false;
  bool adRewardEarned = false;
  bool adShowInProgress = false;

  int adSessionId = 0;
  int adRetrySessionId = 0;

  static const String rewardedAdUnitId =
      'ca-app-pub-1367967256658706/4388775484';

  bool get canShowAd => !_isDisposed && isRewardedAdReady && rewardedAd != null;

  bool get shouldShowPreparingMessage => isLoadingRewardedAd;

  void markRewardEarned() {
    adRewardEarned = true;
  }

  void beginShowSession() {
    adRewardEarned = false;
    adShowInProgress = true;
    adSessionId += 1;
  }

  bool isCurrentShowSession(int sessionId) {
    return sessionId == adSessionId;
  }

  int beginRetrySession() {
    adRetrySessionId += 1;
    return adRetrySessionId;
  }

  bool isCurrentRetrySession(int sessionId) {
    return sessionId == adRetrySessionId;
  }

  void loadRewardedAd({
    required bool isPremium,
    required bool Function() isMounted,
    required VoidCallback onStateChanged,
    required VoidCallback onRetry,
  }) {
    if (_isDisposed || isPremium || isLoadingRewardedAd || isRewardedAdReady) {
      return;
    }

    final currentAdRetrySessionId = beginRetrySession();

    markLoading();

    try {
      RewardedAd.load(
        adUnitId: rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (_isDisposed || !isMounted()) {
              ad.dispose();
              markLoadFailed();
              return;
            }

            markLoaded(ad);
            onStateChanged();
          },
          onAdFailedToLoad: (error) {
            if (_isDisposed) return;

            markLoadFailed();

            if (isMounted()) {
              onStateChanged();
            }

            Future.delayed(const Duration(seconds: 8), () {
              if (_isDisposed || !isMounted()) {
                return;
              }

              if (!isCurrentRetrySession(currentAdRetrySessionId)) {
                return;
              }

              if (isPremium) {
                return;
              }

              if (isLoadingRewardedAd || isRewardedAdReady) {
                return;
              }

              onRetry();
            });
          },
        ),
      );
    } catch (_) {
      markLoadFailed();

      if (isMounted()) {
        onStateChanged();
      }
    }
  }

  void markLoading() {
    isLoadingRewardedAd = true;
  }

  void markLoaded(RewardedAd ad) {
    rewardedAd = ad;
    isLoadingRewardedAd = false;
    isRewardedAdReady = true;
  }

  void markLoadFailed() {
    rewardedAd = null;
    isLoadingRewardedAd = false;
    isRewardedAdReady = false;
  }

  void showRewardedAd({
    required VoidCallback onAdNotReady,
    required VoidCallback onAdMissing,
    required Future<void> Function() onAdDismissedAfterRewardCheck,
    required Future<void> Function() onAdFailedToShow,
  }) {
    if (_isDisposed || adShowInProgress) {
      return;
    }

    if (!canShowAd) {
      onAdNotReady();
      return;
    }

    beginShowSession();
    final currentAdSessionId = adSessionId;

    final adToShow = takeAdForShowing();

    if (adToShow == null) {
      resetRewardedAdState();
      onAdMissing();
      return;
    }

    adToShow.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) async {
        if (!isCurrentShowSession(currentAdSessionId)) {
          ad.dispose();
          return;
        }

        ad.dispose();
        resetRewardedAdState();

        try {
          await onAdDismissedAfterRewardCheck();
        } catch (_) {}
      },
      onAdFailedToShowFullScreenContent: (ad, error) async {
        if (!isCurrentShowSession(currentAdSessionId)) {
          ad.dispose();
          return;
        }

        ad.dispose();
        resetRewardedAdState();

        try {
          await onAdFailedToShow();
        } catch (_) {}
      },
    );

    try {
      adToShow.show(
        onUserEarnedReward: (ad, reward) {
          if (!isCurrentShowSession(currentAdSessionId)) {
            return;
          }

          markRewardEarned();
        },
      );
    } catch (_) {
      resetRewardedAdState();
      onAdMissing();
    }
  }

  RewardedAd? takeAdForShowing() {
    final adToShow = rewardedAd;
    rewardedAd = null;
    isRewardedAdReady = false;
    return adToShow;
  }

  void resetRewardedAdState() {
    adShowInProgress = false;
    adRewardEarned = false;
    isRewardedAdReady = false;
    rewardedAd = null;
  }

  void dispose() {
    _isDisposed = true;
    adRetrySessionId += 1;
    adSessionId += 1;

    try {
      rewardedAd?.dispose();
    } catch (_) {}

    rewardedAd = null;
    isRewardedAdReady = false;
    isLoadingRewardedAd = false;
    adShowInProgress = false;
    adRewardEarned = false;
  }
}
