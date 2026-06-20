import 'package:flutter/material.dart';

import '../models/favorite_item.dart';

class SavedReflectionsScreen extends StatelessWidget {
  const SavedReflectionsScreen({
    super.key,
    required this.reflections,
  });

  final List<FavoriteItem> reflections;

  TextStyle reflectionStyle(double size) {
    return TextStyle(
      color: const Color(0xFFF4F0E8),
      fontSize: size,
      fontWeight: FontWeight.w300,
      fontFamily: 'CormorantGaramond',
      height: 1.35,
      letterSpacing: 0.3,
    );
  }

  TextStyle dateStyle() {
    return const TextStyle(
      color: Colors.white54,
      fontSize: 15,
      fontWeight: FontWeight.w300,
      fontFamily: 'CormorantGaramond',
      letterSpacing: 0.4,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030303),
      appBar: AppBar(
        backgroundColor: const Color(0xFF030303),
        foregroundColor: const Color(0xFFF4F0E8),
        elevation: 0,
        title: Text(
          "Saved Reflections",
          style: reflectionStyle(24),
        ),
      ),
      body: reflections.isEmpty
          ? Center(
              child: Text(
                "No wisdom saved yet.",
                style: reflectionStyle(21).copyWith(color: Colors.white54),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
              itemCount: reflections.length,
              separatorBuilder: (context, index) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Divider(
                    color: Colors.white24,
                    thickness: 0.5,
                  ),
                );
              },
              itemBuilder: (context, index) {
                final item = reflections[index];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.date, style: dateStyle()),
                    const SizedBox(height: 8),
                    Text(item.text, style: reflectionStyle(24)),
                  ],
                );
              },
            ),
    );
  }
}
