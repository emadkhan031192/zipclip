import 'package:flutter_test/flutter_test.dart';
import 'package:zipclip/core/engine/segment_planner.dart';

void main() {
  group('SegmentPlanner.plan', () {
    test('small files download in one piece', () {
      final plan = SegmentPlanner.plan(totalBytes: 500 * 1024);
      expect(plan.length, 1);
      expect(plan.single.start, 0);
      expect(plan.single.end, 500 * 1024 - 1);
    });

    test('unknown size downloads in one open stream', () {
      final plan = SegmentPlanner.plan(totalBytes: null);
      expect(plan.length, 1);
      expect(plan.single.end, -1); // open-ended
    });

    test('14.2 MB splits into 4 contiguous segments', () {
      const total = 14889779; // ~14.2 MB
      final plan = SegmentPlanner.plan(totalBytes: total);
      expect(plan.length, 4);
      expect(plan.first.start, 0);
      expect(plan.last.end, total - 1);
      var covered = 0;
      for (var i = 0; i < plan.length; i++) {
        expect(plan[i].start, covered);
        covered = plan[i].end + 1;
      }
      expect(covered, total);
      // Segments are near-equal in size.
      final sizes = plan.map((r) => r.length).toList();
      expect(sizes.reduce((a, b) => a > b ? a : b) - sizes.reduce((a, b) => a < b ? a : b),
          lessThanOrEqualTo(1),);
    });

    test('respects maxSegments', () {
      final plan =
          SegmentPlanner.plan(totalBytes: 100 * 1024 * 1024, maxSegments: 2);
      expect(plan.length, 2);
    });

    test('ranges round-trip through JSON (persisted progress)', () {
      const r = ByteRange(100, 199);
      expect(ByteRange.fromJson(r.toJson()).start, 100);
      expect(ByteRange.fromJson(r.toJson()).end, 199);
      expect(r.length, 100);
    });
  });
}
