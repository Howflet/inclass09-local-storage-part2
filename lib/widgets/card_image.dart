import 'package:flutter/material.dart';

import '../models/card_record.dart';

// ============================================================================
// CardImage: show the referenced artwork, or a suit-symbol fallback
// ============================================================================
// Summary: image_ref is only a reference. It may be null, blank, malformed,
// point at an asset that is not bundled, or at a URL that cannot load. Every
// one of those cases renders the same stable suit placeholder, so the card
// stays identifiable and nothing is deleted because an image failed.
//
// Supported references:
//   assets/...            -> bundled asset (registered in pubspec.yaml)
//   http:// or https://   -> remote image (loading + error fallback)
//   anything else         -> treated as malformed; fallback shown
class CardImage extends StatelessWidget {
  final String? imageRef;
  final String suit;
  final double size;

  const CardImage({
    super.key,
    required this.imageRef,
    required this.suit,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final ref = imageRef?.trim() ?? '';
    final Widget child;
    if (ref.startsWith('assets/')) {
      child = Image.asset(
        ref,
        fit: BoxFit.cover,
        errorBuilder: (_, error, _) => _fallback(context, 'asset missing'),
      );
    } else if (ref.startsWith('http://') || ref.startsWith('https://')) {
      child = Image.network(
        ref,
        fit: BoxFit.cover,
        loadingBuilder: (context, image, progress) => progress == null
            ? image
            : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        errorBuilder: (_, error, _) => _fallback(context, 'URL unavailable'),
      );
    } else {
      child = _fallback(context, ref.isEmpty ? 'no image' : 'invalid ref');
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 8),
      child: SizedBox(width: size, height: size * 1.4, child: child),
    );
  }

  Widget _fallback(BuildContext context, String reason) {
    final symbol = kSuitSymbols[suit] ?? '?';
    final red = suit == 'Hearts' || suit == 'Diamonds';
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$suit placeholder ($reason)',
      child: Container(
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Text(
          symbol,
          style: TextStyle(
            fontSize: size * 0.6,
            color: red ? Colors.red.shade700 : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
