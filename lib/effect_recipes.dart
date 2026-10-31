import 'effects.dart';

/// Named, editable combinations of Canvas primitives; these are recipes, not
/// claims of separate physical simulations or GPU shaders.
class EffectRecipe {
  final String name, category;
  final List<EffectInstance> effects;
  const EffectRecipe(this.name, this.category, this.effects);
  bool get needsPreviousImage =>
      effects.any((e) => const ['crossfade', 'slide', 'wipe'].contains(e.type));
}

EffectInstance _e(
  String type, {
  double strength = .5,
  double frequency = 0,
  Interpolation curve = Interpolation.linear,
  int durationUs = 600000,
  double begin = 1,
  double end = 0,
}) => EffectInstance(
  id: type,
  type: type,
  strength: strength,
  frequency: frequency,
  curve: curve,
  durationUs: durationUs,
  beginIntensity: begin,
  endIntensity: end,
);

final effectRecipes = <EffectRecipe>[
  EffectRecipe('Smooth Camera Movement', 'Motion', [
    _e(
      'pan',
      strength: .18,
      curve: Interpolation.easeInOut,
      durationUs: 1500000,
    ),
    _e('zoom', strength: .16, durationUs: 1500000),
  ]),
  EffectRecipe('Cinematic Pan', 'Motion', [
    _e(
      'pan',
      strength: .7,
      durationUs: 2000000,
      curve: Interpolation.easeInOut,
    ),
  ]),
  EffectRecipe('Elastic Zoom', 'Motion', [
    _e('zoom', strength: .8, curve: Interpolation.elastic),
  ]),
  EffectRecipe('Bounce Zoom', 'Motion', [
    _e('zoom', strength: .8, curve: Interpolation.bounce),
  ]),
  EffectRecipe('3D-like Rotation', 'Motion', [
    _e('rotation', strength: .5, curve: Interpolation.easeInOut),
    _e('zoom', strength: .35),
  ]),
  EffectRecipe('Camera Drift', 'Motion', [
    _e('pan', strength: .15, durationUs: 3000000),
    _e('rotation', strength: .1, durationUs: 3000000),
  ]),
  EffectRecipe('Spring Movement', 'Motion', [
    _e('pan', strength: .6, curve: Interpolation.back),
    _e('zoom', strength: .25, curve: Interpolation.elastic),
  ]),
  EffectRecipe('Dynamic Shake', 'Motion', [
    _e('shake', strength: .8, frequency: 9),
    _e('zoom', strength: .2),
  ]),
  EffectRecipe('Digital Glitch', 'Glitch', [
    _e('glitch', strength: .8, frequency: 12),
    _e('rgb', strength: .55),
  ]),
  EffectRecipe('RGB Distortion', 'Glitch', [
    _e('rgb', strength: .9, frequency: 4),
  ]),
  EffectRecipe('Scanline Glitch', 'Glitch', [
    _e('scanlines', strength: .8),
    _e('glitch', strength: .3),
  ]),
  EffectRecipe('Pixel Stretch', 'Glitch', [
    _e('glitch', strength: 1, frequency: 2),
    _e('pan', strength: .12),
  ]),
  EffectRecipe('Signal Interference', 'Glitch', [
    _e('scanlines', strength: .7, frequency: 14),
    _e('shake', strength: .2, frequency: 15),
    _e('rgb', strength: .3),
  ]),
  EffectRecipe('VHS Distortion', 'Glitch', [
    _e('scanlines', strength: .45),
    _e('rgb', strength: .25),
    _e('glitch', strength: .15),
    _e('blur', strength: .08),
  ]),
  EffectRecipe('Frame Flicker', 'Glitch', [
    _e('flash', strength: .5, frequency: 15),
  ]),
  EffectRecipe('Soft Glow', 'Light', [
    _e(
      'glow',
      strength: .4,
      durationUs: 1200000,
      curve: Interpolation.easeInOut,
    ),
  ]),
  EffectRecipe('Flash Pulse', 'Light', [
    _e('flash', strength: .8, frequency: 3),
  ]),
  EffectRecipe('Neon Glow', 'Light', [
    _e('rgb', strength: .45),
    _e('glow', strength: .8),
  ]),
  EffectRecipe('Light Sweep', 'Light', [
    _e('lightSweep', strength: .8, begin: 1, end: 1, durationUs: 900000),
  ]),
  EffectRecipe('Bloom', 'Light', [
    _e('glow', strength: .9),
    _e('blur', strength: .1),
  ]),
  EffectRecipe('Lens Flare', 'Light', [
    _e('lightSweep', strength: .7, durationUs: 1200000),
    _e('glow', strength: .3),
  ]),
  EffectRecipe('Smooth Zoom', 'Transitions', [
    _e('crossfade', strength: 1),
    _e('zoom', strength: .75, curve: Interpolation.easeInOut),
  ]),
  EffectRecipe('Whip Pan', 'Transitions', [
    _e('slide', strength: 1, durationUs: 300000),
    _e('pan', strength: .8, durationUs: 300000),
    _e('blur', strength: .3, durationUs: 300000),
  ]),
  EffectRecipe('Motion Blur Transition', 'Transitions', [
    _e('slide', strength: 1),
    _e('blur', strength: .8),
  ]),
  EffectRecipe('Light Flash', 'Transitions', [
    _e('crossfade', strength: 1),
    _e('flash', strength: 1, durationUs: 300000),
  ]),
  EffectRecipe('Blur Dissolve', 'Transitions', [
    _e('crossfade', strength: 1),
    _e('blur', strength: .65),
  ]),
  EffectRecipe('Rotation Transition', 'Transitions', [
    _e('crossfade', strength: 1),
    _e('rotation', strength: .9),
    _e('zoom', strength: .4),
  ]),
  EffectRecipe('Elastic Slide', 'Transitions', [
    _e('slide', strength: 1, curve: Interpolation.elastic),
  ]),
  EffectRecipe('RGB Transition', 'Transitions', [
    _e('crossfade', strength: 1),
    _e('rgb', strength: .9),
  ]),
];
