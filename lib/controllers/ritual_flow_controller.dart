class RitualFlowController {
  const RitualFlowController();

  bool isPauseScreen(int screenStep) => screenStep == 1;

  bool isHeartScreen(int screenStep) => screenStep == 2;

  bool isRevealScreen(int screenStep) => screenStep == 3;

  bool isWisdomRevealed(int screenStep) => screenStep == 4;

  Duration transitionFadeOutDuration(int nextStep) =>
      Duration(milliseconds: nextStep == 3 ? 980 : 820);

  Duration transitionSettleDuration(int nextStep) =>
      Duration(milliseconds: nextStep == 1 ? 820 : 560);

  double transitionBackgroundDepth(int nextStep) => nextStep == 1 ? 0.14 : 0.0;
}
