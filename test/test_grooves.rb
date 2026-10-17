require 'minitest/autorun'
require_relative '../src/ocl_viyar/grooves'

# Faces are built as axis-aligned rectangles in the panel frame, the way the collector passes them.
class TestGrooves < Minitest::Test

  G = OclViyar::Grooves
  SIZE = [ 720.0, 560.0, 18.0 ]

  # Rectangle on the plane <axis> = pos, normal along +/- axis, spanning u and v (the other axes in order)
  def rect(axis, pos, dir, u, v)
    others = [ 0, 1, 2 ] - [ axis ]
    corners = [ [ u[0], v[0] ], [ u[1], v[0] ], [ u[1], v[1] ], [ u[0], v[1] ] ].map do |a, b|
      p = []
      p[axis] = pos
      p[others[0]] = a
      p[others[1]] = b
      p
    end
    normal = [ 0.0, 0.0, 0.0 ]
    normal[axis] = dir.to_f
    { points: corners, normal: normal }
  end

  def panel_faces
    [ rect(2, 18.0, 1, [ 0, 720 ], [ 0, 560 ]), rect(2, 0.0, -1, [ 0, 720 ], [ 0, 560 ]),
      rect(0, 0.0, -1, [ 0, 560 ], [ 0, 18 ]), rect(0, 720.0, 1, [ 0, 560 ], [ 0, 18 ]),
      rect(1, 0.0, -1, [ 0, 720 ], [ 0, 18 ]), rect(1, 560.0, 1, [ 0, 720 ], [ 0, 18 ]) ]
  end

  def find(faces)
    G.find(panel_faces + faces, SIZE)
  end

  def test_plain_panel_has_no_grooves
    assert_equal [ [], [] ], find([])
  end

  def test_front_groove
    floor = rect(2, 13.0, 1, [ 530, 533 ], [ 0, 560 ])
    walls = [ rect(0, 530.0, 1, [ 0, 560 ], [ 13, 18 ]), rect(0, 533.0, -1, [ 0, 560 ], [ 13, 18 ]) ]
    boxes, warnings = find([ floor ] + walls)
    assert_equal [ { x: [ 530.0, 533.0 ], y: [ 0.0, 560.0 ], z: [ 13.0, 18.0 ] } ], boxes
    assert_empty warnings
  end

  def test_back_rabbet
    floor = rect(2, 9.0, -1, [ 712, 720 ], [ 0, 560 ])
    wall = rect(0, 712.0, 1, [ 0, 560 ], [ 0, 9 ])
    boxes, = find([ floor, wall ])
    assert_equal [ { x: [ 712.0, 720.0 ], y: [ 0.0, 560.0 ], z: [ 0.0, 9.0 ] } ], boxes
  end

  def test_edge_groove_ignores_slot_walls
    floor = rect(1, 550.0, 1, [ 100, 300 ], [ 6, 10 ])
    walls = [ rect(2, 6.0, 1, [ 100, 300 ], [ 550, 560 ]), rect(2, 10.0, -1, [ 100, 300 ], [ 550, 560 ]),
              rect(0, 100.0, 1, [ 550, 560 ], [ 6, 10 ]), rect(0, 300.0, -1, [ 550, 560 ], [ 6, 10 ]) ]
    boxes, warnings = find([ floor ] + walls)
    assert_equal [ { x: [ 100.0, 300.0 ], y: [ 550.0, 560.0 ], z: [ 6.0, 10.0 ] } ], boxes
    assert_empty warnings
  end

  def test_split_floor_is_merged
    floors = [ rect(2, 13.0, 1, [ 530, 533 ], [ 0, 200 ]), rect(2, 13.0, 1, [ 530, 533 ], [ 200, 560 ]) ]
    boxes, = find(floors)
    assert_equal [ { x: [ 530.0, 533.0 ], y: [ 0.0, 560.0 ], z: [ 13.0, 18.0 ] } ], boxes
  end

  def test_separate_grooves_are_not_merged
    floors = [ rect(2, 13.0, 1, [ 100, 103 ], [ 0, 560 ]), rect(2, 13.0, 1, [ 530, 533 ], [ 0, 560 ]) ]
    boxes, = find(floors)
    assert_equal 2, boxes.length
  end

  def test_non_rectangular_floor_is_reported
    l_shape = { points: [ [ 0, 0, 13 ], [ 100, 0, 13 ], [ 100, 10, 13 ], [ 10, 10, 13 ], [ 10, 100, 13 ], [ 0, 100, 13 ] ],
                normal: [ 0.0, 0.0, 1.0 ] }
    boxes, warnings = find([ l_shape ])
    assert_empty boxes
    assert_equal [ 'non-rectangular recess x 0..100, y 0..100, z 13..18 skipped' ], warnings
  end

  def test_slanted_and_non_planar_faces_are_ignored
    slanted = { points: [ [ 0, 0, 18 ], [ 720, 0, 18 ], [ 720, 10, 8 ], [ 0, 10, 8 ] ], normal: [ 0.0, 0.707, 0.707 ] }
    boxes, warnings = find([ slanted ])
    assert_equal [ [], [] ], [ boxes, warnings ]
  end

end
