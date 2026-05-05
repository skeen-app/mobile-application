import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_button.dart';
import '../../../../core/widgets/skeen_step_indicator.dart';

class CalibrateScreen extends StatefulWidget {
  const CalibrateScreen({super.key});

  @override
  State<CalibrateScreen> createState() => _CalibrateScreenState();
}

class _CalibrateScreenState extends State<CalibrateScreen> {
  CameraController? _controller;
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (kDebugMode) print('No cameras found');
        return;
      }
      
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      if (kDebugMode) print('Error initializing camera: $e');
      // On web without web camera support, or lack of permissions, mock it.
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: SkeenStepIndicator(currentStep: 2, totalSteps: 3),
            ),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.22,
                    color: AppColors.violetaClaro,
                  ),
                  children: [
                    TextSpan(text: 'Photo to calibrate '),
                    TextSpan(
                      text: 'ೃ',
                      style: TextStyle(
                        fontFamily: 'Arial',
                        color: AppColors.naranja,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'In order to calibrate the AI model correctly please provide a photo of your hand',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  height: 1.4,
                  letterSpacing: -0.16,
                  color: AppColors.hintText,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: AppColors.indigo,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_isCameraInitialized && _controller != null)
                          CameraPreview(_controller!)
                        else
                          const Center(
                            child: Icon(
                              Icons.camera_alt,
                              size: 48,
                              color: AppColors.hintText,
                            ),
                          ),
                        // Scanner bracket overlay
                        Container(
                          width: double.infinity,
                          height: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AppColors.violeta.withOpacity(0.5),
                              width: 2,
                            ),
                          ),
                          margin: const EdgeInsets.all(24),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF24154B),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Make sure to:',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.violetaClaro,
                      ),
                    ),
                    SizedBox(height: 8),
                    _InstructionRow(
                      icon: Icons.check_circle_outline,
                      text: 'Place your hand inside the square',
                    ),
                    SizedBox(height: 8),
                    _InstructionRow(
                      icon: Icons.lightbulb_outline,
                      text: 'Be in a well illuminated place',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SkeenButton.primary(
                label: 'Calibrate',
                onPressed: () => context.go('/onboarding/terms'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _InstructionRow extends StatelessWidget {
  const _InstructionRow({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.turquesa, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: AppColors.hintText,
            ),
          ),
        ),
      ],
    );
  }
}
