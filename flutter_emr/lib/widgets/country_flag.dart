import 'package:flutter/material.dart';

/// Country row flag — custom [imageUrl], [countryCode] via flagcdn, or globe fallback.
class CountryFlag extends StatelessWidget {
  const CountryFlag({
    super.key,
    required this.countryName,
    this.countryCode,
    this.imageUrl,
    this.size = 48,
    this.radius,
  });

  final String countryName;
  final String? countryCode;
  final String? imageUrl;
  final double size;
  final double? radius;

  static String flagCdnUrl(String code) {
    final c = code.trim().toLowerCase();
    if (c.length != 2) return '';
    return 'https://flagcdn.com/w80/${c.replaceAll(RegExp(r'[^a-z]'), '')}.png';
  }

  static String resolveImageUrl({
    required String countryName,
    String? countryCode,
    String? rawImage,
  }) {
    final custom = (rawImage ?? '').trim();
    if (custom.startsWith('http://') || custom.startsWith('https://')) {
      return custom;
    }
    final code = (countryCode ?? '').trim();
    if (code.length >= 2) {
      final fromCode = flagCdnUrl(code.length == 2 ? code : code.substring(0, 2));
      if (fromCode.isNotEmpty) return fromCode;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final r = radius ?? size / 2;
    final url = resolveImageUrl(
      countryName: countryName,
      countryCode: countryCode,
      rawImage: imageUrl,
    );

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
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: SizedBox(
        width: size * 0.35,
        height: size * 0.35,
        child: const CircularProgressIndicator(strokeWidth: 2),
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
        border: Border.all(color: Colors.grey.shade300),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.public_rounded, color: const Color(0xFFD32F2F), size: size * 0.45),
    );
  }
}
