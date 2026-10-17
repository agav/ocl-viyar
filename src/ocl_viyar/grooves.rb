module OclViyar

  # Finds grooves and rabbets modeled with push/pull in a panel's own geometry.
  #
  # Every rectangular recess leaves a "floor": a planar face parallel to a panel face (or to an
  # edge face) lying strictly inside the panel. The floor's position, its rectangle and its normal
  # (pointing to the open side) give the box of removed material. Classifying the box (groove,
  # rabbet, edge groove) is left to the writer.
  #
  # Input faces are in the panel frame (mm): x along length, y along width, z = thickness, front
  # face at z = thickness (see PanelFrame).
  #
  # Pure Ruby (no SketchUp API).
  module Grooves

    PLANE_TOL = 0.05    # mm, vertices of a floor face lie on one plane
    EDGE_TOL = 0.1      # mm, "touches" the panel boundary (Bazis2Viyar PRECISION)
    AXIS_TOL = 0.999    # face normal along a panel axis
    RECT_TOL = 0.005    # relative, face area vs its bounding rectangle

    # faces: [ { points: [ [x, y, z], ... ] (outer loop), normal: [x, y, z] (unit) }, ... ]
    # size:  [ length, width, thickness ]
    # Returns [ boxes, warnings ]; a box is { x: [min, max], y: [min, max], z: [min, max] }.
    def self.find(faces, size)
      candidates = faces.map { |f| _candidate(f, size) }.compact
      warnings = []
      boxes = []
      candidates.each do |c|
        next if _wall?(c, candidates)
        box = _box(c, size)
        unless c[:rect]
          warnings << "non-rectangular recess #{describe(box)} skipped"
          next
        end
        boxes << box
      end
      [ merge(boxes), warnings ]
    end

    # Joins boxes that are pieces of one recess (a floor split by a drawn line, duplicated faces).
    def self.merge(boxes)
      boxes = boxes.dup
      loop do
        pair = boxes.combination(2).find { |a, b| _joinable?(a, b) }
        break if pair.nil?
        a, b = pair
        boxes.delete_at(boxes.index(b))
        boxes[boxes.index(a)] = _union(a, b)
      end
      boxes
    end

    def self.describe(box)
      'x %s..%s, y %s..%s, z %s..%s' % (box[:x] + box[:y] + box[:z]).map { |v| _fmt(v) }
    end

    # A face that could be a recess floor, or nil.
    def self._candidate(face, size)
      axis = (0..2).find { |i| face[:normal][i].abs > AXIS_TOL }
      return nil if axis.nil?
      values = face[:points].map { |p| p[axis] }
      return nil if values.max - values.min > PLANE_TOL
      pos = values.sum / values.length
      return nil if pos <= EDGE_TOL || pos >= size[axis] - EDGE_TOL   # panel face or edge face

      u, v = ([ 0, 1, 2 ] - [ axis ])
      ranges = {}
      [ u, v ].each { |i| ranges[i] = face[:points].map { |p| p[i] }.minmax }
      if axis != 2
        # edge-groove floor: must be closed by material on both faces, otherwise it is a wall
        z1, z2 = ranges[2]
        return nil if z1 <= EDGE_TOL || z2 >= size[2] - EDGE_TOL
      end
      area = _area(face[:points].map { |p| [ p[u], p[v] ] })
      rect_area = (ranges[u][1] - ranges[u][0]) * (ranges[v][1] - ranges[v][0])
      { axis: axis, pos: pos, dir: face[:normal][axis] > 0 ? 1 : -1, ranges: ranges,
        rect: rect_area > 0 && (area - rect_area).abs <= rect_area * RECT_TOL }
    end

    # The walls of a slot cut into an edge (its sides and its ends) also look like floors. A floor
    # opens to the panel boundary; a wall has another face in front of it, facing back at it.
    def self._wall?(c, candidates)
      others = c[:ranges].keys
      candidates.any? do |o|
        o[:axis] == c[:axis] && o[:dir] == -c[:dir] && (o[:pos] - c[:pos]) * c[:dir] > PLANE_TOL &&
          others.all? { |i| _overlap?(c[:ranges][i], o[:ranges][i]) }
      end
    end

    def self._box(c, size)
      box = {}
      (0..2).each do |i|
        range = if i == c[:axis]
                  c[:dir] > 0 ? [ c[:pos], size[i] ] : [ 0.0, c[:pos] ]
                else
                  c[:ranges][i]
                end
        box[%i[x y z][i]] = [ [ range[0], 0.0 ].max, [ range[1], size[i] ].min ].map { |v| v.round(2) }
      end
      box
    end

    def self._joinable?(a, b)
      return true if _contains?(a, b) || _contains?(b, a)
      touching = %i[x y z].all? { |k| a[k][0] <= b[k][1] + PLANE_TOL && b[k][0] <= a[k][1] + PLANE_TOL }
      touching && (_volume(_union(a, b)) - _volume(a) - _volume(b)).abs <= _volume(_union(a, b)) * RECT_TOL
    end

    def self._contains?(a, b)
      %i[x y z].all? { |k| a[k][0] <= b[k][0] + PLANE_TOL && b[k][1] <= a[k][1] + PLANE_TOL }
    end

    def self._union(a, b)
      %i[x y z].map { |k| [ k, [ [ a[k][0], b[k][0] ].min, [ a[k][1], b[k][1] ].max ] ] }.to_h
    end

    def self._volume(box)
      %i[x y z].map { |k| box[k][1] - box[k][0] }.reduce(:*)
    end

    def self._overlap?(r1, r2)
      [ r1[1], r2[1] ].min - [ r1[0], r2[0] ].max > PLANE_TOL
    end

    # Shoelace formula
    def self._area(points)
      sum = 0.0
      points.each_with_index do |(x1, y1), i|
        x2, y2 = points[(i + 1) % points.length]
        sum += x1 * y2 - x2 * y1
      end
      sum.abs / 2.0
    end

    def self._fmt(v)
      v == v.to_i ? v.to_i.to_s : v.to_s
    end

  end

end
