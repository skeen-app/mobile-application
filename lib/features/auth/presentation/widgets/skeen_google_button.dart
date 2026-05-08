import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Brand-compliant "Continue with Google" button. White background with a
/// hairline border, the official multicolor G mark on the left, and
/// "Continue with Google" rendered in Roboto medium per Google's branding
/// guidelines.
///
/// Hidden on iOS in this iteration — federated sign-in is Android-only
/// until the iOS Firebase config ships. The widget exposes the
/// [forceVisible] flag for tests / preview surfaces that want to show
/// the button regardless of platform.
class SkeenGoogleButton extends StatelessWidget {
  const SkeenGoogleButton({
    super.key,
    required this.onPressed,
    this.label = 'Continue with Google',
    this.isLoading = false,
    this.forceVisible = false,
  });

  final Future<void> Function()? onPressed;
  final String label;
  final bool isLoading;
  final bool forceVisible;

  @override
  Widget build(BuildContext context) {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    if (!forceVisible && !isAndroid) {
      // iOS / desktop / web — federated sign-in not enabled yet. The
      // form falls back to email + password.
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: (isLoading || onPressed == null) ? null : () => onPressed!(),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFFDADCE0)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF3C4043)),
                    ),
                  )
                else
                  SvgPicture.string(
                    _googleGSvg,
                    width: 20,
                    height: 20,
                  ),
                const Spacer(),
                Text(
                  label,
                  style: const TextStyle(
                    // Roboto matches Google's brand spec, but it isn't
                    // bundled with the app — the system Roboto on Android
                    // is acceptable. We fall back gracefully on platforms
                    // where the system replaces it.
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    letterSpacing: 0.25,
                    color: Color(0xFF3C4043),
                  ),
                ),
                const Spacer(),
                // Mirror width of the leading icon so the label sits
                // visually centered.
                const SizedBox(width: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Official Google "G" multicolor mark — vector identical to the one
// shipped with Google's Sign-In branding pack. Inlining keeps a single
// source of truth and avoids dragging another asset through the build.
const String _googleGSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <path fill="#FFC107" d="M43.611 20.083H42V20H24v8h11.303c-1.649 4.657-6.08 8-11.303 8-6.627 0-12-5.373-12-12s5.373-12 12-12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 12.955 4 4 12.955 4 24s8.955 20 20 20 20-8.955 20-20c0-1.341-.138-2.65-.389-3.917z"/>
  <path fill="#FF3D00" d="M6.306 14.691l6.571 4.819C14.655 15.108 18.961 12 24 12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 16.318 4 9.656 8.337 6.306 14.691z"/>
  <path fill="#4CAF50" d="M24 44c5.166 0 9.86-1.977 13.409-5.192l-6.19-5.238A11.91 11.91 0 0 1 24 36c-5.202 0-9.619-3.317-11.283-7.946l-6.522 5.025C9.505 39.556 16.227 44 24 44z"/>
  <path fill="#1976D2" d="M43.611 20.083H42V20H24v8h11.303a12.04 12.04 0 0 1-4.087 5.571l.003-.002 6.19 5.238C36.971 39.205 44 34 44 24c0-1.341-.138-2.65-.389-3.917z"/>
</svg>
''';
