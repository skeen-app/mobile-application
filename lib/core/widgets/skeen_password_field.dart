import 'package:flutter/material.dart';

import '../../features/auth/application/validators.dart';
import '../theme/app_colors.dart';
import 'skeen_text_field.dart';

class SkeenPasswordField extends StatefulWidget {
  const SkeenPasswordField({
    super.key,
    required this.label,
    required this.controller,
    this.errorText,
    this.onChanged,
    this.showRulesHelper = true,
    this.textInputAction,
  });

  final String label;
  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final bool showRulesHelper;
  final TextInputAction? textInputAction;

  @override
  State<SkeenPasswordField> createState() => _SkeenPasswordFieldState();
}

class _SkeenPasswordFieldState extends State<SkeenPasswordField> {
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return SkeenTextField(
      label: widget.label,
      controller: widget.controller,
      obscureText: _obscured,
      errorText: widget.errorText,
      onChanged: widget.onChanged,
      textInputAction: widget.textInputAction,
      autofillHints: const [AutofillHints.password],
      suffix: IconButton(
        splashRadius: 18,
        onPressed: () => setState(() => _obscured = !_obscured),
        icon: Icon(
          _obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: AppColors.hintText,
          size: 22,
        ),
      ),
      helperBuilder: widget.showRulesHelper
          ? (context) => _PasswordRulesPanel(
                rules: Validators.passwordRules(widget.controller.text),
              )
          : null,
    );
  }
}

class _PasswordRulesPanel extends StatelessWidget {
  const _PasswordRulesPanel({required this.rules});

  final List<PasswordRule> rules;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.indigo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Your password must include:',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.12,
              color: AppColors.violetaClaro,
            ),
          ),
          const SizedBox(height: 6),
          for (final rule in rules) _RuleRow(rule: rule),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.rule});

  final PasswordRule rule;

  @override
  Widget build(BuildContext context) {
    final color = rule.met ? AppColors.turquesa : AppColors.hintText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            rule.met ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              rule.label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                letterSpacing: -0.12,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
