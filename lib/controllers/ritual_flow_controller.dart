class RitualFlowController {
  const RitualFlowController();

  bool isPauseScreen(int screenStep) => screenStep == 1;

  bool isHeartScreen(int screenStep) => screenStep == 2;

  bool isRevealScreen(int screenStep) => screenStep == 3;

  bool isWisdomRevealed(int screenStep) => screenStep == 4;

  bool isPostAdBlackScreen(int screenStep) => screenStep == 5;
}
