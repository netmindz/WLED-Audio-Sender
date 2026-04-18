/// AGC (Automatic Gain Control) - ported from WLED's audio_reactive.h
///
/// Implements a PI controller that automatically adjusts microphone gain
/// to keep the signal in a useful range for LED effects.

import 'dart:math';

/// AGC mode presets matching WLED's AGC_NUM_PRESETS
enum AgcPreset { normal, vivid, lazy }

class AutomaticGainControl {
  // AGC preset tables (from WLED audio_reactive.h)
  static const _sampleDecay  = [0.9994, 0.9985, 0.9997];
  static const _zoneLow      = [32.0,   28.0,   36.0];
  static const _zoneHigh     = [240.0,  240.0,  248.0];
  static const _zoneStop     = [336.0,  448.0,  304.0];
  static const _target0      = [112.0,  144.0,  164.0];
  static const _target0Up    = [88.0,   64.0,   116.0];
  static const _target1      = [220.0,  224.0,  216.0];
  static const _followFast   = [1/192.0, 1/128.0, 1/256.0];
  static const _followSlow   = [1/6144.0, 1/4096.0, 1/8192.0];
  static const _controlKp    = [0.6,   1.5,   0.65];
  static const _controlKi    = [1.7,   1.85,  1.2];
  static const _sampleSmooth = [1/12.0, 1/6.0, 1/16.0];

  AgcPreset preset = AgcPreset.normal;
  bool enabled = true;

  // Internal state
  double multAgc = 1.0;
  double sampleAgc = 0.0;
  double rawSampleAgc = 0.0;
  double sampleMax = 0.0;
  double controlIntegrated = 0.0;
  double squelch = 1.0; // noise floor

  // For getSample() DC removal
  double _micLev = 0.0;
  double _expAdjF = 0.0;
  double _sampleAvg = 0.0;
  double _sampleReal = 0.0;

  int get _p => preset.index;

  /// Reset all AGC state
  void reset() {
    multAgc = 1.0;
    sampleAgc = 0.0;
    rawSampleAgc = 0.0;
    sampleMax = 0.0;
    controlIntegrated = 0.0;
    _micLev = 0.0;
    _expAdjF = 0.0;
    _sampleAvg = 0.0;
    _sampleReal = 0.0;
  }

  /// Process a raw sample through DC removal, filtering, gain adjustment,
  /// and AGC. Returns the AGC-adjusted sample (0-255 range).
  ///
  /// [micDataReal] is the raw microphone sample (normalised float, typically
  /// from PCM16 / 32768.0 then scaled to roughly 0-255 range).
  double process(double micDataReal) {
    // --- getSample() port ---
    // DC offset tracking
    _micLev += (micDataReal - _micLev) / 12288.0;
    if (micDataReal < (_micLev - 0.24)) {
      _micLev = ((_micLev * 31.0) + micDataReal) / 32.0;
    }

    double micInNoDC = (micDataReal - _micLev).abs();

    // Exponential filter
    const double weightFall = 0.18;
    const double weightRise = 0.073;
    if ((micInNoDC > _expAdjF) && (_expAdjF > squelch)) {
      _expAdjF = (weightRise * micInNoDC + (1.0 - weightRise) * _expAdjF);
    } else {
      _expAdjF = (weightFall * micInNoDC + (1.0 - weightFall) * _expAdjF);
    }
    _expAdjF = _expAdjF.abs();

    // Noise gate
    if ((_expAdjF <= squelch) || (squelch == 0 && _expAdjF < 0.25)) {
      _expAdjF = 0.0;
      micInNoDC = 0.0;
    }

    double tmpSample = _expAdjF;
    _sampleReal = tmpSample;

    // Basic gain (sampleGain=40, inputLevel=128 defaults => gain ~= 1 + 1/16)
    double sampleAdj = tmpSample * 1.0 + tmpSample / 16.0;
    sampleAdj = sampleAdj.clamp(0.0, 255.0);

    // Smooth average
    _sampleAvg = ((_sampleAvg * 15.0) + sampleAdj) / 16.0;
    _sampleAvg = _sampleAvg.abs();

    // Peak tracking for AGC
    if ((sampleMax < _sampleReal) && (_sampleReal > 0.5)) {
      sampleMax = sampleMax + 0.5 * (_sampleReal - sampleMax);
    } else {
      if (enabled && (multAgc * sampleMax > _zoneStop[_p])) {
        sampleMax += 0.5 * (_sampleReal - sampleMax);
      } else {
        sampleMax *= _sampleDecay[_p];
      }
    }
    if (sampleMax < 0.5) sampleMax = 0.0;

    if (!enabled) {
      // No AGC - just return the adjusted sample
      sampleAgc = _sampleAvg;
      return sampleAdj;
    }

    // --- agcAvg() port ---
    double lastMultAgc = multAgc;
    double multAgcTemp = multAgc;
    double tmpAgc = _sampleReal * multAgc;
    double controlError;

    if ((_sampleReal.abs() < 2.0) || (sampleMax < 1.0)) {
      // Signal is squelched
      tmpAgc = 0;
      if (controlIntegrated.abs() < 0.01) {
        controlIntegrated = 0.0;
      } else {
        controlIntegrated *= 0.91;
      }
    } else {
      // Compute new setpoint
      if (tmpAgc <= _target0Up[_p]) {
        multAgcTemp = _target0[_p] / sampleMax;
      } else {
        multAgcTemp = _target1[_p] / sampleMax;
      }
    }

    multAgcTemp = multAgcTemp.clamp(1.0 / 64.0, 32.0);

    controlError = multAgcTemp - lastMultAgc;

    // Integrator with anti-windup
    if ((multAgcTemp > 0.085) && (multAgcTemp < 6.5) &&
        (multAgc * sampleMax < _zoneStop[_p])) {
      controlIntegrated += controlError * 0.002 * 0.25;
    } else {
      controlIntegrated *= 0.9;
    }

    // PI control
    tmpAgc = _sampleReal * lastMultAgc;
    if ((tmpAgc > _zoneHigh[_p]) || (tmpAgc < squelch + _zoneLow[_p])) {
      // Emergency zone - fast response
      multAgcTemp = lastMultAgc + _followFast[_p] * _controlKp[_p] * controlError;
      multAgcTemp += _followFast[_p] * _controlKi[_p] * controlIntegrated;
    } else {
      // Normal zone - slow response
      multAgcTemp = lastMultAgc + _followSlow[_p] * _controlKp[_p] * controlError;
      multAgcTemp += _followSlow[_p] * _controlKi[_p] * controlIntegrated;
    }

    multAgcTemp = multAgcTemp.clamp(1.0 / 64.0, 32.0);

    // Apply gain
    tmpAgc = _sampleReal * multAgcTemp;
    if (_sampleReal.abs() < 2.0) tmpAgc = 0.0;
    if (tmpAgc > 255) tmpAgc = 255.0;
    if (tmpAgc < 1) tmpAgc = 0.0;

    multAgc = multAgcTemp;

    // Smooth AGC output
    rawSampleAgc = 0.8 * tmpAgc + 0.2 * rawSampleAgc;
    if (tmpAgc.abs() < 1.0) {
      sampleAgc = 0.5 * tmpAgc + 0.5 * sampleAgc;
    } else {
      sampleAgc += _sampleSmooth[_p] * (tmpAgc - sampleAgc);
    }
    sampleAgc = sampleAgc.abs();

    return sampleAgc;
  }
}
