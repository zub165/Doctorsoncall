import 'package:flutter/material.dart';

import 'speciality_avatar.dart';

/// Avatar for a person — photo URL, generated initials, or icon fallback.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 48,
    this.fallbackIcon = Icons.person_rounded,
    this.useSpecialityStyle = false,
    this.specialityName,
    this.specialityImageUrl,
  });

  final String name;
  final String? imageUrl;
  final double size;
  final IconData fallbackIcon;
  final bool useSpecialityStyle;
  final String? specialityName;
  final String? specialityImageUrl;

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (useSpecialityStyle) {
      return SpecialityAvatar(
        name: specialityName ?? name,
        imageUrl: (imageUrl ?? '').trim().isNotEmpty
            ? imageUrl
            : specialityImageUrl,
        size: size,
        radius: size * 0.28,
        onlineFallback: (imageUrl ?? specialityImageUrl ?? '').trim().isEmpty,
      );
    }

    final url = (imageUrl ?? '').trim();
    final r = size * 0.28;

    if (url.startsWith('http://') || url.startsWith('https://')) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final cache = (size * dpr).round();
      return ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: Image.network(
          url,
          key: ValueKey<String>(url),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: cache,
          cacheHeight: cache,
          errorBuilder: (_, __, ___) => _initialsBox(r),
        ),
      );
    }

    return _initialsBox(r);
  }

  Widget _initialsBox(double r) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFD32F2F).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(r),
      ),
      alignment: Alignment.center,
      child: Text(
        initials(name),
        style: TextStyle(
          color: const Color(0xFFD32F2F),
          fontWeight: FontWeight.bold,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}
