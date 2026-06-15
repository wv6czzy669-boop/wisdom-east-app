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

  void dispose() {
    rewardedAd?.dispose();
    rewardedAd = null;
  }
}
