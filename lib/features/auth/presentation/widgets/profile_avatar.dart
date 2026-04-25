import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_colors.dart';

/// Round profile avatar with the dashboard's signature violet ring.
///
/// Shows the remote photo when [photoUrl] is non-null and resolves; otherwise
/// renders the static "user blank" SVG so the layout never collapses.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.photoUrl,
    required this.onTap,
    this.size = 96,
  });

  final String? photoUrl;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final innerSize = size - 8; // Ring width = 4 px on each side.
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.violeta,
          ),
          padding: const EdgeInsets.all(4),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF1C1A44), width: 2),
            ),
            child: ClipOval(
              child: SizedBox(
                width: innerSize,
                height: innerSize,
                child: _AvatarImage(photoUrl: photoUrl),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarImage extends StatelessWidget {
  const _AvatarImage({required this.photoUrl});
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return Image.network(
        photoUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const _BlankAvatar(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const _BlankAvatar();
        },
      );
    }
    return const _BlankAvatar();
  }
}

class _BlankAvatar extends StatelessWidget {
  const _BlankAvatar();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/profile/user_blank.svg',
      fit: BoxFit.cover,
    );
  }
}
