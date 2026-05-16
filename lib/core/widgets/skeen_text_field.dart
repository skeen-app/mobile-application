import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

class SkeenTextField extends StatefulWidget {
  const SkeenTextField({
    super.key,
    required this.label,
    required this.controller,
    this.keyboardType,
    this.inputFormatters,
    this.obscureText = false,
    this.suffix,
    this.errorText,
    this.helperBuilder,
    this.onChanged,
    this.textInputAction,
    this.autofillHints,
    this.scrollPadding = const EdgeInsets.all(20),
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final Widget? suffix;
  final String? errorText;
  final WidgetBuilder? helperBuilder;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  // Reserves space below the field so the helper panel that appears on
  // focus is also scrolled above the keyboard (not just the input row).
  final EdgeInsets scrollPadding;

  static const Color _labelColor = Color(0xFF817691);

  @override
  State<SkeenTextField> createState() => _SkeenTextFieldState();
}

class _SkeenTextFieldState extends State<SkeenTextField> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showError = widget.errorText != null && !_focused;
    final borderColor = showError ? AppColors.fucsia : AppColors.stroke;

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(5),
      borderSide: BorderSide(color: borderColor),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          keyboardType: widget.keyboardType,
          inputFormatters: widget.inputFormatters,
          obscureText: widget.obscureText,
          onChanged: widget.onChanged,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          scrollPadding: widget.scrollPadding,
          cursorColor: AppColors.violetaLink,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            letterSpacing: -0.16,
            color: AppColors.violetaClaro,
          ),
          decoration: InputDecoration(
            labelText: widget.label,
            labelStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              letterSpacing: -0.16,
              color: SkeenTextField._labelColor,
            ),
            floatingLabelStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              letterSpacing: -0.12,
              color: SkeenTextField._labelColor,
            ),
            floatingLabelBehavior: FloatingLabelBehavior.auto,
            suffixIcon: widget.suffix,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            filled: true,
            fillColor: Colors.transparent,
            enabledBorder: border,
            focusedBorder: border,
            disabledBorder: border,
            errorBorder: border,
            focusedErrorBorder: border,
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _buildHelperArea(showError),
        ),
      ],
    );
  }

  Widget _buildHelperArea(bool showError) {
    if (showError) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Text(
          widget.errorText!,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            letterSpacing: -0.12,
            color: AppColors.fucsia,
          ),
        ),
      );
    }
    if (_focused && widget.helperBuilder != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: widget.helperBuilder!(context),
      );
    }
    return const SizedBox(width: double.infinity);
  }
}
