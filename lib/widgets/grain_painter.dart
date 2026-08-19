import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/east_design.dart';

class GrainPainter extends CustomPainter {
  const GrainPainter({
    required this.movement,
    required this.intensity,
  });

  final double movement;
  final double intensity;

  static final List<_GrainParticle> _particles = _buildParticles();

  static List<_GrainParticle> _buildParticles() {
    final random = Random(7);

    return List.generate(350, (_) {
      return _GrainParticle(
        xFactor: random.nextDouble(),
        yFactor: random.nextDouble(),
        isThick: random.nextDouble() > 0.72,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final thinPoints = <Offset>[];
    final thickPoints = <Offset>[];
    final motion = movement * pi * 2;

    for (int i = 0; i < _particles.length; i++) {
      final particle = _particles[i];
      final driftX = sin(motion + i) * 0.85;
      final driftY = cos(motion + i * 0.71) * 0.85;
      final point = Offset(
        particle.xFactor * size.width + driftX,
        particle.yFactor * size.height + driftY,
      );

      if (particle.isThick) {
        thickPoints.add(point);
      } else {
        thinPoints.add(point);
      }
    }

    final alpha = intensity * 0.72;

    canvas.drawPoints(
      PointMode.points,
      thinPoints,
      Paint()
        ..color = EastColors.ink.withValues(alpha: alpha)
        ..strokeWidth = 0.55,
    );
    canvas.drawPoints(
      PointMode.points,
      thickPoints,
      Paint()
        ..color = EastColors.ink.withValues(alpha: alpha)
        ..strokeWidth = 0.85,
    );
  }

  @override
  bool shouldRepaint(covariant GrainPainter oldDelegate) {
    return oldDelegate.movement != movement ||
        oldDelegate.intensity != intensity;
  }
}

class _GrainParticle {
  const _GrainParticle({
    required this.xFactor,
    required this.yFactor,
    required this.isThick,
  });

  final double xFactor;
  final double yFactor;
  final bool isThick;
}
