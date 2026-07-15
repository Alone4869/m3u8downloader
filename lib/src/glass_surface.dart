import 'package:flutter/material.dart';

/// A quiet app backdrop that gives the floating navigation glass just enough
/// colour to refract without turning every page into a decorative gradient.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: dark
                  ? const [Color(0xFF0D0F14), Color(0xFF12151B)]
                  : const [Color(0xFFF8F9FC), Color(0xFFF1F3F8)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        IgnorePointer(
          child: Align(
            alignment: const Alignment(0, 1.18),
            child: _GlowOrb(
              size: 360,
              color: colors.primary.withValues(alpha: dark ? 0.13 : 0.09),
            ),
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

/// The shared content surface. Glass is intentionally reserved for the
/// floating navigation bar; cards and dialogs stay crisp and readable.
class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding,
    this.elevated = false,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      side: BorderSide(
        color: colors.outlineVariant.withValues(alpha: dark ? 0.38 : 0.62),
        width: 0.8,
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.24 : 0.07),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Material(
        color: dark ? const Color(0xFF191C22) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ),
    );
  }
}
