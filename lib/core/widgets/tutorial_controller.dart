import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/application/auth_controller.dart';
import 'tutorial_storage.dart';

enum TutorialStep {
  inactive,
  homeScan,
  cameraCapture,
  reportDownload,
}

class TutorialController extends StateNotifier<TutorialStep> {
  TutorialController(this._userId) : super(TutorialStep.inactive);

  final String _userId;

  /// Starts the tutorial if it hasn't been completed yet.
  /// Typically called from the home screen when passing from registration.
  Future<void> start() async {
    if (_userId.isEmpty) return;
    final completed = await TutorialStorage.isCompleted(_userId);
    if (!completed) {
      state = TutorialStep.homeScan;
    }
  }

  void advanceToCamera() {
    if (state == TutorialStep.homeScan) {
      state = TutorialStep.cameraCapture;
    }
  }

  void advanceToReport() {
    if (state == TutorialStep.cameraCapture) {
      state = TutorialStep.reportDownload;
    }
  }

  void finish() {
    if (_userId.isNotEmpty) {
      TutorialStorage.markCompleted(_userId);
    }
    state = TutorialStep.inactive;
  }

  void skip() => finish();
}

final tutorialControllerProvider =
    StateNotifierProvider<TutorialController, TutorialStep>((ref) {
  final user = ref.watch(authControllerProvider).user;
  return TutorialController(user?.id ?? '');
});
