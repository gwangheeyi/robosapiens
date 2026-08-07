import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/map_geometry.dart';

/// A 1000 x 800 room with a stub wall hanging down from the ceiling at x=500.
const _walls = <Segment>[
  (Offset(0, 0), Offset(1000, 0)),
  (Offset(0, 800), Offset(1000, 800)),
  (Offset(0, 0), Offset(0, 800)),
  (Offset(1000, 0), Offset(1000, 800)),
  (Offset(500, 0), Offset(500, 300)),
];

const _floor = <Offset>[
  Offset(0, 0),
  Offset(1000, 0),
  Offset(1000, 800),
  Offset(0, 800),
];

void main() {
  group('segmentDistance', () {
    test('reports zero for segments that cross', () {
      // Endpoint distances alone would call these 200 px apart.
      expect(
        segmentDistance(
          const Offset(250, 200),
          const Offset(750, 200),
          const Offset(500, 0),
          const Offset(500, 400),
        ),
        0,
      );
    });

    test('measures the gap for segments that miss each other', () {
      expect(
        segmentDistance(
          const Offset(0, 0),
          const Offset(100, 0),
          const Offset(0, 30),
          const Offset(100, 30),
        ),
        closeTo(30, .001),
      );
    });
  });

  group('waypointMoveIssue', () {
    WaypointMoveIssue? issueFor(
      Offset original,
      Offset updated, {
      List<Offset> waypoints = const [],
      List<Segment> lanes = const [],
      double clearance = 40,
    }) => waypointMoveIssue(
      original: original,
      updated: updated,
      waypoints: waypoints.isEmpty ? [original] : waypoints,
      lanes: lanes,
      walls: _walls,
      floorOutline: _floor,
      laneWallClearance: clearance,
    );

    test('allows a move into open floor', () {
      expect(issueFor(const Offset(200, 500), const Offset(300, 500)), isNull);
    });

    test('refuses a drop outside the floor', () {
      expect(
        issueFor(const Offset(200, 500), const Offset(1200, 500)),
        WaypointMoveIssue.outsideFloor,
      );
    });

    test('refuses a drop on top of another waypoint', () {
      expect(
        issueFor(
          const Offset(200, 500),
          const Offset(400, 502),
          waypoints: const [Offset(200, 500), Offset(400, 500)],
        ),
        WaypointMoveIssue.waypointTooClose,
      );
    });

    test('refuses a move that pushes its own lane into a wall', () {
      // The lane would end 10 px from the ceiling; it needs 40.
      expect(
        issueFor(
          const Offset(200, 500),
          const Offset(200, 10),
          waypoints: const [Offset(200, 500), Offset(200, 600)],
          lanes: const [(Offset(200, 500), Offset(200, 600))],
        ),
        WaypointMoveIssue.laneTouchesWall,
      );
    });

    test('refuses a move that drags its own lane across a wall', () {
      expect(
        issueFor(
          // Dragged to the far side of the stub wall, so the lane it carries
          // sweeps straight through that wall.
          const Offset(250, 200),
          const Offset(750, 200),
          waypoints: const [Offset(250, 200), Offset(250, 100)],
          lanes: const [(Offset(250, 200), Offset(250, 100))],
        ),
        WaypointMoveIssue.laneTouchesWall,
      );
    });

    test('ignores lanes elsewhere that already break the clearance', () {
      // A pre-existing lane 10 px from the ceiling used to block every drag on
      // the map, including moves that have nothing to do with it.
      expect(
        issueFor(
          const Offset(200, 500),
          const Offset(300, 500),
          waypoints: const [
            Offset(200, 500),
            Offset(700, 10),
            Offset(900, 10),
          ],
          lanes: const [(Offset(700, 10), Offset(900, 10))],
        ),
        isNull,
      );
    });

    test('keeps checking the lanes attached to the dragged waypoint', () {
      expect(
        issueFor(
          const Offset(200, 500),
          const Offset(200, 10),
          waypoints: const [
            Offset(200, 500),
            Offset(200, 600),
            Offset(700, 10),
            Offset(900, 10),
          ],
          lanes: const [
            (Offset(200, 500), Offset(200, 600)),
            (Offset(700, 10), Offset(900, 10)),
          ],
        ),
        WaypointMoveIssue.laneTouchesWall,
      );
    });
  });
}
