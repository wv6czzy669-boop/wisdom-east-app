import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

class WisdomApp extends StatelessWidget {
  const WisdomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Wisdom: EAST.',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF040404),
        textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: 'CormorantGaramond',
            ),
      ),
      home: const HomeScreen(),
    );
  }
}
