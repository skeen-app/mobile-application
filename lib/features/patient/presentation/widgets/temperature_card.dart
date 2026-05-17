import 'package:skeen/core/localization/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/environment_reading.dart';
import 'uv_index_dial.dart';

/// Combined temperature + UV + SPF guidance card on the home dashboard.
///
/// Renders three states from `environmentProvider`: loaded reading, loading
/// shimmer, and error fallback (e.g. denied location permission).
///
/// Layout adapts via `LayoutBuilder`: when the card is wide enough (≥ 340 lp)
/// the temperature info and UV dial sit side-by-side; otherwise they stack
/// vertically so nothing gets clipped on narrow devices.
class TemperatureCard extends StatelessWidget {
  const TemperatureCard.loaded({super.key, required EnvironmentReading reading})
    : _reading = reading,
      _isLoading = false,
      _errorLabel = null;

  const TemperatureCard.loading({super.key})
    : _reading = null,
      _isLoading = true,
      _errorLabel = null;

  const TemperatureCard.error({super.key, required String message})
    : _reading = null,
      _isLoading = false,
      _errorLabel = message;

  final EnvironmentReading? _reading;
  final bool _isLoading;
  final String? _errorLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1444),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFF5D3034)),
      ),
      child: _isLoading
          ? const _LoadingLeft()
          : _errorLabel != null
              ? _ErrorLeft(message: _errorLabel)
              : _LoadedBody(reading: _reading!),
    );
  }
}

/// Loaded state — adaptively lays out temperature info + UV dial.
class _LoadedBody extends StatelessWidget {
  const _LoadedBody({required this.reading});
  final EnvironmentReading reading;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: _ReadingLeft(reading: reading)),
            const SizedBox(width: 8),
            UvIndexDial(uvIndex: reading.uvIndex, size: 96),
          ],
        ),
        const SizedBox(height: 8),
        const _UvDisclaimer(),
      ],
    );
  }
}

class _ReadingLeft extends StatelessWidget {
  const _ReadingLeft({required this.reading});
  final EnvironmentReading reading;

  @override
  Widget build(BuildContext context) {
    final spf = reading.spfRecommendation;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF472537),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(
                child: SvgPicture.asset(
                  'assets/images/home/alert_circle.svg',
                  width: 20,
                  height: 20,
                  colorFilter: const ColorFilter.mode(
                    AppColors.naranja,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Temperature'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  height: 1.2,
                  color: Color(0xFFCCC3D8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 44),
          child: Text(
            reading.locationLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w500,
              fontSize: 9,
              height: 1.5,
              letterSpacing: -0.08,
              color: AppColors.stroke,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${reading.temperatureCelsius.round()}°',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 28,
                height: 1.2,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'Celsius'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    height: 1.5,
                    color: Color(0xFFFFB690),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.naranja.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: AppColors.naranja.withValues(alpha: 0.5)),
          ),
          child: Text(
            spf.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 11,
              height: 1.4,
              letterSpacing: 0.6,
              color: AppColors.naranja,
            ),
          ),
        ),
      ],
    );
  }
}

/// Subtle disclaimer below the UV section.
class _UvDisclaimer extends StatelessWidget {
  const _UvDisclaimer();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.info_outline_rounded, size: 12, color: AppColors.stroke),
        SizedBox(width: 4),
        Expanded(
          child: Text(
            'UV data is approximate. Always consult local weather sources.'.tr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w400,
              fontSize: 10,
              height: 1.4,
              color: AppColors.stroke,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingLeft extends StatelessWidget {
  const _LoadingLeft();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.naranja),
        ),
      ),
    );
  }
}

class _ErrorLeft extends StatelessWidget {
  const _ErrorLeft({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Temperature'.tr,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: Color(0xFFCCC3D8),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w400,
            fontSize: 11,
            height: 1.4,
            color: AppColors.hintText,
          ),
        ),
      ],
    );
  }
}
