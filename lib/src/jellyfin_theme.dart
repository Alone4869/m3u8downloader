import 'package:flutter/material.dart';

const jellyfinBackground = Color(0xFF0B0B0F);
const jellyfinAccent = Color(0xFF00A4DC);
const jellyfinHeaderHeight = 300.0;

ThemeData jellyfinCinemaTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: jellyfinAccent,
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: jellyfinBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );
}

Route<T> jellyfinRoute<T>({required WidgetBuilder builder}) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final incoming = CurvedAnimation(
        parent: animation,
        curve: Curves.fastEaseInToSlowEaseOut,
        reverseCurve: Curves.fastEaseInToSlowEaseOut.flipped,
      );
      final outgoing = CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.linearToEaseOut,
        reverseCurve: Curves.easeInToLinear,
      );
      return SlideTransition(
        position: outgoing.drive(
          Tween<Offset>(begin: Offset.zero, end: const Offset(-1 / 3, 0)),
        ),
        child: SlideTransition(
          position: incoming.drive(
            Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero),
          ),
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 500),
    reverseTransitionDuration: const Duration(milliseconds: 500),
  );
}

class JellyfinPlaceholder extends StatelessWidget {
  const JellyfinPlaceholder({super.key, this.icon = Icons.movie_outlined});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF16161C),
      child: Center(child: Icon(icon, size: 44, color: Colors.white24)),
    );
  }
}

class JellyfinEffectWarmup extends StatelessWidget {
  const JellyfinEffectWarmup({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: jellyfinBackground,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [jellyfinBackground, Colors.transparent],
              ),
            ),
          ),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              child: SizedBox(width: 120, height: 180),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0x2900A4DC),
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                  border: Border.fromBorderSide(
                    BorderSide(color: Color(0x5900A4DC)),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    '预热',
                    style: TextStyle(color: jellyfinAccent, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
