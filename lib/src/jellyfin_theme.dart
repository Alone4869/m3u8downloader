import 'package:flutter/material.dart';

const jellyfinBackground = Color(0xFF0B0B0F);
const jellyfinAccent = Color(0xFF00A4DC);

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
