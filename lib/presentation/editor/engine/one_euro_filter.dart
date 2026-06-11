import 'dart:math' as math;

/// One-euro filter (Casiez et al. 2012): adaptive low-pass that smooths
/// jitter at low speeds without adding lag at high speeds — the standard
/// choice for stylus input.
class OneEuroFilter {
  OneEuroFilter({
    this.minCutoff = 1.2,
    this.beta = 0.01,
    this.dCutoff = 1.0,
  });

  final double minCutoff;
  final double beta;
  final double dCutoff;

  double? _prevValue;
  double? _prevDeriv;
  int? _prevTimeMs;

  void reset() {
    _prevValue = null;
    _prevDeriv = null;
    _prevTimeMs = null;
  }

  double filter(double value, int timeMs) {
    final prevValue = _prevValue;
    final prevTimeMs = _prevTimeMs;
    if (prevValue == null || prevTimeMs == null) {
      _prevValue = value;
      _prevDeriv = 0;
      _prevTimeMs = timeMs;
      return value;
    }

    // Guard duplicate timestamps (coalesced samples can share one).
    final dtMs = timeMs - prevTimeMs;
    final dt = dtMs > 0 ? dtMs / 1000.0 : 1 / 120.0;

    final rawDeriv = (value - prevValue) / dt;
    final derivAlpha = _alpha(dCutoff, dt);
    final deriv = _lerp(_prevDeriv ?? 0, rawDeriv, derivAlpha);

    final cutoff = minCutoff + beta * deriv.abs();
    final alpha = _alpha(cutoff, dt);
    final filtered = _lerp(prevValue, value, alpha);

    _prevValue = filtered;
    _prevDeriv = deriv;
    _prevTimeMs = timeMs;
    return filtered;
  }

  static double _alpha(double cutoff, double dt) {
    final tau = 1 / (2 * math.pi * cutoff);
    return 1 / (1 + tau / dt);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
