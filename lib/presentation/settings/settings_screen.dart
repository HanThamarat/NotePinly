import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/tokens.dart';

/// Minimal settings: everything notepinly needs today. Grows with real
/// preferences (default paper, left-handed toolbar) as they land.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: InkColors.backdrop,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Padding(
              padding: const EdgeInsets.all(InkSpace.sm),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: 'Back',
                    color: InkColors.ink,
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/'),
                  ),
                  const SizedBox(width: InkSpace.xs),
                  Text('Settings',
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisAlignment: .center,
                    children: const [
                      Text(
                        'NotePinly',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: InkColors.ink,
                          letterSpacing: -0.3,
                        ),
                      ),
                      SizedBox(height: InkSpace.xs),
                      Text(
                        'Handwritten notes, saved as you write.\nAll data stays on this device.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 14, color: InkColors.inkMuted),
                      ),
                      SizedBox(height: InkSpace.xl),
                      Text(
                        'Version 0.1.0',
                        style:
                            TextStyle(fontSize: 12.5, color: InkColors.inkMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
