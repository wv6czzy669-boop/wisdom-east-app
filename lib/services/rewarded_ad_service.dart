import 'package:google_mobile_ads/google_mobile_ads.dart';

class RewardedAdService {
  RewardedAd? rewardedAd;

  bool isRewardedAdReady = false;
  bool isLoadingRewardedAd = false;
  bool adRewardEarned = false;
  bool adShowInProgress = false;

  int adSessionId = 0;
  int adRetrySessionId = 0;

  static const String rewardedAdUnitId =
      'ca-app-pub-1367967256658706/4388775484';

  bool get canShowAd => isRewardedAdReady && rewardedAd != null;

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
    rewardedAd?.dispose();
    rewardedAd = null;
    isRewardedAdReady = false;
    isLoadingRewardedAd = false;
    adShowInProgress = false;
    adRewardEarned = false;
  }
}
