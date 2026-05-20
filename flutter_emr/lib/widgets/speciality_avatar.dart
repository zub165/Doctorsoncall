import 'package:flutter/material.dart';

import '../utils/twemoji_assets.dart';

/// Avatar for a medical speciality — local Twemoji when possible, else network / icon.
class SpecialityAvatar extends StatelessWidget {
  const SpecialityAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 48,
    this.radius,
    /// When true and no local Twemoji, loads ui-avatars.com for empty/non-emoji URLs.
    this.onlineFallback = true,
    /// Prefer bundled Twemoji for keyword-matched names when [imageUrl] is empty.
    this.useLocalEmojiForName = true,
  });

  final String name;
  final String? imageUrl;
  final double size;
  final double? radius;

  final bool onlineFallback;
  final bool useLocalEmojiForName;

  static String generatedAvatarUrl(String name) {
    final n = name.trim().isEmpty ? 'MD' : name.trim();
    return 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(n)}&size=256&background=D32F2F&color=fff&bold=true';
  }

  static String resolveImageUrl(
    String name,
    String? raw, {
    bool onlineFallback = true,
  }) {
    final url = (raw ?? '').trim();
    if (TwemojiAssets.resolveAssetPath(url) != null) {
      return '';
    }
    if (url.isNotEmpty && (url.startsWith('http://') || url.startsWith('https://'))) {
      return url;
    }
    if (onlineFallback) {
      return generatedAvatarUrl(name);
    }
    return '';
  }

  static String? localAssetPath(String name, String? raw, {bool useLocalEmojiForName = true}) {
    final fromRaw = TwemojiAssets.resolveAssetPath(raw);
    if (fromRaw != null) return fromRaw;
    if (useLocalEmojiForName) {
      final code = TwemojiAssets.codeForSpecialityName(name);
      if (code != null) return TwemojiAssets.pathForCode(code);
    }
    return null;
  }

  static IconData iconForName(String name) {
    final n = name.toLowerCase();
    if (n.contains('cardio') || n.contains('heart')) return Icons.favorite_rounded;
    if (n.contains('derma') || n.contains('skin')) return Icons.face_retouching_natural_rounded;
    if (n.contains('neuro') || n.contains('brain')) return Icons.psychology_rounded;
    if (n.contains('pediatr') || n.contains('child')) return Icons.child_care_rounded;
    if (n.contains('ortho') || n.contains('bone')) return Icons.accessibility_new_rounded;
    if (n.contains('eye') || n.contains('ophthal')) return Icons.visibility_rounded;
    if (n.contains('radio') || n.contains('imaging')) return Icons.camera_alt_rounded;
    if (n.contains('emergency') || n.contains('trauma')) return Icons.local_hospital_rounded;
    if (n.contains('psych') || n.contains('mental')) return Icons.self_improvement_rounded;
    if (n.contains('dent')) return Icons.masks_rounded;
    if (n.contains('nutrition') || n.contains('diet')) return Icons.restaurant_rounded;
    return Icons.medical_services_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final r = radius ?? size / 2;
    final asset = localAssetPath(name, imageUrl, useLocalEmojiForName: useLocalEmojiForName);

    if (asset != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _fallback(r),
        ),
      );
    }

    final url = resolveImageUrl(name, imageUrl, onlineFallback: onlineFallback);

    if (url.isEmpty) {
      return _fallback(r);
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheSize = (size * dpr).round();

    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: Image.network(
        url,
        key: ValueKey<String>(url),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        frameBuilder: (context, child, frame, loadedSync) {
          if (loadedSync || frame != null) return child;
          return _loadingBox(r);
        },
        errorBuilder: (_, __, ___) => _fallback(r),
      ),
    );
  }

  Widget _loadingBox(double r) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFD32F2F).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(r),
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: size * 0.35,
        height: size * 0.35,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: const Color(0xFFD32F2F).withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _fallback(double r) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFD32F2F).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(r),
      ),
      alignment: Alignment.center,
      child: Icon(iconForName(name), color: const Color(0xFFD32F2F), size: size * 0.5),
    );
  }
}

/// Suggested images for the admin speciality editor (bundled Twemoji, offline).
abstract final class SpecialityImagePresets {
  static String avatarFor(String name) => SpecialityAvatar.generatedAvatarUrl(name);

  static List<({String label, String url})> get catalog => [
        for (final p in TwemojiAssets.presetCatalog)
          (label: p.label, url: TwemojiAssets.assetRefForCode(p.code)),
      ];
}
