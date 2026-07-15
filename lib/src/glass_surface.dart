import 'dart:ui';

import 'package:flutter/material.dart';

class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: dark
                  ? const [Color(0xFF090B11), Color(0xFF101528)]
                  : const [Color(0xFFF8F9FF), Color(0xFFEFF2FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        IgnorePointer(
          child: Stack(
            children: [
              Positioned(
                top: -130,
                right: -100,
                child: _GlowOrb(
                  size: 330,
                  color: const Color(
                    0xFF625BFF,
                  ).withValues(alpha: dark ? 0.24 : 0.16),
                ),
              ),
              Positioned(
                bottom: 20,
                left: -150,
                child: _GlowOrb(
                  size: 360,
                  color: const Color(
                    0xFF27B7FF,
                  ).withValues(alpha: dark ? 0.14 : 0.11),
                ),
              ),
            ],
          ),
        ),
        child,
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.blurSigma = 20,
    this.padding,
    this.tintStrength = 1,
    this.showShadow = true,
  });

  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final EdgeInsetsGeometry? padding;
  final double tintStrength;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(borderRadius);
    final topTint = (dark ? 0.15 : 0.58) * tintStrength;
    final bottomTint = (dark ? 0.07 : 0.30) * tintStrength;

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: showShadow
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.32 : 0.12),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: colors.primary.withValues(alpha: dark ? 0.08 : 0.05),
                    blurRadius: 22,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: topTint.clamp(0, 1)),
                    (dark ? const Color(0xFF171A24) : Colors.white).withValues(
                      alpha: bottomTint.clamp(0, 1),
                    ),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: dark ? 0.17 : 0.72),
                  width: 0.8,
                ),
              ),
              child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
