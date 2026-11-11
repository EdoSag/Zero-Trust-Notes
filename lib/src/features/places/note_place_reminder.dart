import 'package:flutter/foundation.dart';
import 'package:zt_places/zt_places.dart';

/// A note's "remind me when I arrive at / leave [place]", stored in the
/// note's sealed item (key `placeReminder`). Older Notes builds keep it
/// untouched in `Note.extra`.
@immutable
class NotePlaceReminder {
  const NotePlaceReminder({required this.place, required this.trigger, required this.setAt});

  final ZtPlace place;
  final ZtPlaceTrigger trigger;

  /// When it was set. Part of the OS reminder's id, so setting it again
  /// (even to the same place) arms a reminder that already fired.
  final DateTime setAt;

  /// The id the phone watches it under.
  String idFor(String noteId) => '$noteId@${setAt.millisecondsSinceEpoch}';

  /// The note id inside an id made by [idFor].
  static String noteIdOf(String reminderId) {
    final at = reminderId.lastIndexOf('@');
    return at < 0 ? reminderId : reminderId.substring(0, at);
  }

  Map<String, Object?> toJson() => {
    'place': place.toJson(),
    'trigger': trigger.name,
    'setAt': setAt.toUtc().toIso8601String(),
  };

  static NotePlaceReminder? fromJson(Object? json) {
    if (json is! Map) return null;
    final place = ZtPlace.fromJson(json['place']);
    final setAt = json['setAt'] is String ? DateTime.tryParse(json['setAt'] as String) : null;
    if (place == null || setAt == null) return null;
    return NotePlaceReminder(
      place: place,
      trigger: ZtPlaceTrigger.parse(json['trigger']),
      setAt: setAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NotePlaceReminder &&
      other.place == place &&
      other.trigger == trigger &&
      other.setAt.isAtSameMomentAs(setAt);

  @override
  int get hashCode => Object.hash(place, trigger, setAt.millisecondsSinceEpoch);
}
