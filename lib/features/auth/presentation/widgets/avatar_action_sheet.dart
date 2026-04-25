import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Action chosen by the user in the avatar bottom-sheet.
enum AvatarAction {
  takePhoto,
  uploadPhoto,
  deletePhoto,
}

/// Modal bottom sheet for managing the profile picture. Themed to match the
/// rest of the dashboard (indigo card, violet accents, naranja for the
/// destructive action).
///
/// Returns the chosen [AvatarAction] when an option is tapped, or `null` if
/// the user dismisses the sheet.
Future<AvatarAction?> showAvatarActionSheet(
  BuildContext context, {
  required bool hasExistingPhoto,
}) {
  return showModalBottomSheet<AvatarAction>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _AvatarActionSheet(hasExistingPhoto: hasExistingPhoto),
  );
}

class _AvatarActionSheet extends StatelessWidget {
  const _AvatarActionSheet({required this.hasExistingPhoto});
  final bool hasExistingPhoto;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1A44),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF2F1B66)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.indigoClaro,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Profile picture',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      letterSpacing: -0.16,
                      color: AppColors.violetaClaro,
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Choose how you want to update your photo.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.hintText,
                    ),
                  ),
                ),
              ),
              _ActionRow(
                icon: Icons.photo_camera_outlined,
                label: 'Take a photo',
                onTap: () => Navigator.of(context).pop(AvatarAction.takePhoto),
              ),
              _Divider(),
              _ActionRow(
                icon: Icons.image_outlined,
                label: 'Upload from gallery',
                onTap: () =>
                    Navigator.of(context).pop(AvatarAction.uploadPhoto),
              ),
              if (hasExistingPhoto) ...[
                _Divider(),
                _ActionRow(
                  icon: Icons.delete_outline,
                  label: 'Remove current photo',
                  destructive: true,
                  onTap: () =>
                      Navigator.of(context).pop(AvatarAction.deletePhoto),
                ),
              ],
              const SizedBox(height: 8),
              _Divider(strong: true),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20),
                      ),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                      color: AppColors.hintText,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color =
        destructive ? AppColors.fucsia : AppColors.violetaClaro;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0732),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({this.strong = false});
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: EdgeInsets.symmetric(horizontal: strong ? 0 : 20),
      color: const Color(0xFF2F1B66),
    );
  }
}
