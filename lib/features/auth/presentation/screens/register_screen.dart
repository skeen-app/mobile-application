import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Text(
          'Register (TODO)',
          style: TextStyle(color: AppColors.violetaClaro, fontSize: 18),
        ),
      ),
    );
  }
}
