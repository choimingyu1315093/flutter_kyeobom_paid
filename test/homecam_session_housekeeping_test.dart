import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/homecam_session_housekeeping.dart';

void main() {
  test('only ended, expired sessions are eligible for cleanup', () {
    final now = DateTime(2026, 11, 15, 19);
    final old = Timestamp.fromDate(now.subtract(const Duration(days: 4)));
    final recent = Timestamp.fromDate(now.subtract(const Duration(hours: 3)));
    expect(HomeCamSessionHousekeeping.shouldRemove(
      {'state': 'ended', 'endedAt': old}, now), isTrue);
    expect(HomeCamSessionHousekeeping.shouldRemove(
      {'state': 'ended', 'endedAt': recent}, now), isFalse);
    expect(HomeCamSessionHousekeeping.shouldRemove(
      {'state': 'answer_ready', 'endedAt': old}, now), isFalse);
    expect(HomeCamSessionHousekeeping.shouldRemove(
      {'state': 'creating_offer', 'endedAt': old}, now), isFalse);
    expect(HomeCamSessionHousekeeping.shouldRemove(
      {'state': 'ended'}, now), isFalse);
    expect(HomeCamSessionHousekeeping.shouldRemove(
      <String, dynamic>{}, now), isFalse);
  });

  test('a 10-day-long live session must never be removed', () {
    final now = DateTime(2026, 11, 15);
    final veryOld = Timestamp.fromDate(now.subtract(const Duration(days: 10)));
    expect(HomeCamSessionHousekeeping.shouldRemove(
      {'state': 'answer_ready', 'createdAt': veryOld}, now), isFalse);
  });
}
