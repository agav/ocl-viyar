module OclViyar

  # Panel coordinate frame, in the panel definition's space (inches), with instance scale applied.
  #   x = along length (OpenCutList's length axis, grain direction)
  #   y = along width
  #   z = along thickness, z = x * y (right-handed), so z = thickness is the FRONT face
  # Origin = panel corner at min x, min y, min z, i.e. bottom-left corner seen from the front.
  class PanelFrame

    attr_reader :sizes

    def initialize(instance_info, bounds = instance_info.definition_bounds)
      s = instance_info.scale
      @s = [ s.x.abs, s.y.abs, s.z.abs ]
      axes = instance_info.size.axes
      @dirs = [ axes[0].normalize, axes[1].normalize ]
      @dirs << (@dirs[0] * @dirs[1]).normalize
      b = bounds
      corners = (0..7).map { |i| _scaled(b.corner(i)) }
      @mins = @dirs.map { |d| corners.map { |c| _dot(d, c) }.min }
      maxs = @dirs.map { |d| corners.map { |c| _dot(d, c) }.max }
      @sizes = (0..2).map { |i| maxs[i] - @mins[i] }
    end

    # Point in definition space -> [x, y, z] panel coordinates (inches)
    def local_point(point)
      c = _scaled(point)
      (0..2).map { |i| _dot(@dirs[i], c) - @mins[i] }
    end

    # Vector in definition space -> [x, y, z] panel direction (unit)
    def local_vector(vector)
      c = _scaled(vector)
      v = (0..2).map { |i| _dot(@dirs[i], c) }
      len = Math.sqrt(v.map { |a| a * a }.reduce(:+))
      len == 0 ? v : v.map { |a| a / len }
    end

    private

    def _scaled(p)
      [ p.x * @s[0], p.y * @s[1], p.z * @s[2] ]
    end

    def _dot(d, c)
      d.x * c[0] + d.y * c[1] + d.z * c[2]
    end

  end

  # Runs OpenCutList's cutlist generator and converts sheet-good parts into a plain project Hash
  # (millimeters, no SketchUp objects) consumed by ViyarWriter and GiblabWriter.
  class Collector

    INCH = 25.4
    TOL_MM = 1.0
    DIR_TOL = 0.99
    DEFAULT_SHEET = [ 2800.0, 2070.0 ]
    EDGE_SIDES = { ymin: :bottom, ymax: :top, xmin: :left, xmax: :right }

    attr_reader :warnings

    def initialize(model, presets)
      @model = model
      @presets = presets
      @warnings = []
    end

    def run
      ocl = Ladb::OpenCutList
      require File.join(ocl::PLUGIN_DIR, 'ruby', 'worker', 'cutlist', 'cutlist_generate_worker')

      cutlist = ocl::CutlistGenerateWorker.new(**_generate_settings).run
      cutlist.errors.each { |e| @warnings << "OpenCutList error: #{e.inspect}" }

      materials = {}
      bands = {}
      parts = []

      cutlist.groups.each do |group|
        unless group.material_type == ocl::MaterialAttributes::TYPE_SHEET_GOOD
          @warnings << "Skipped #{group.part_count} part(s) of '#{group.material_display_name || 'no material'}' (not a sheet good)" if group.material_type != ocl::MaterialAttributes::TYPE_EDGE
          next
        end

        gdef = group.def
        thickness = _mm(gdef.std_thickness)
        material_key = "#{group.material_display_name}|#{thickness}"
        materials[material_key] ||= _material(gdef, group, material_key, thickness)

        group.parts.each do |part|
          parts << _part(part, material_key, bands)
        end
      end

      {
        name: @model.title.empty? ? 'untitled' : @model.title,
        materials: materials.values,
        bands: bands.values,
        parts: parts,
        warnings: @warnings
      }
    end

    private

    def _generate_settings
      preset = begin
        Ladb::OpenCutList::PLUGIN.get_model_preset('cutlist_options') || {}
      rescue StandardError
        {}
      end
      accepted = Ladb::OpenCutList::CutlistGenerateWorker.instance_method(:initialize).parameters
                                                          .select { |type, _| type == :key || type == :keyreq }
                                                          .map(&:last)
      settings = {}
      preset.each { |k, v| settings[k.to_sym] = v if accepted.include?(k.to_sym) }
      settings[:part_folding] = false if accepted.include?(:part_folding)
      settings
    end

    def _material(gdef, group, key, thickness)
      length, width = DEFAULT_SHEET
      begin
        std = gdef.material_attributes.l_std_sizes.first
        length, width = _mm(std.length), _mm(std.width) if std && std.length.to_f > 0 && std.width.to_f > 0
      rescue StandardError
        # keep default sheet size
      end
      { key: key, name: group.material_display_name, thickness: thickness, length: length, width: width, grained: _grained(gdef),
        article: _article(gdef.material_attributes.material) }
    end

    # Viyar article: first line of the OpenCutList material description
    def _article(material)
      description = material && material.get_attribute(Ladb::OpenCutList::Plugin::ATTRIBUTE_DICTIONARY, 'description')
      description.to_s.strip.lines.first.to_s.strip
    rescue StandardError
      ''
    end

    # Unknown -> true: keeps the texture along the part length
    def _grained(gdef)
      attributes = gdef.material_attributes
      attributes.respond_to?(:grained) ? attributes.grained != false : true
    rescue StandardError
      true
    end

    def _part(part, material_key, bands)
      pdef = part.def
      instance_info = pdef.instance_infos.values.first
      label = "#{part.number} #{part.name}"
      bounds = _panel_bounds(instance_info.definition)
      if bounds.empty?
        @warnings << "#{label}: no panel faces outside f_/g_ features, using OpenCutList's bounds"
        bounds = instance_info.definition_bounds
      end
      frame = PanelFrame.new(instance_info, bounds)
      length, width, thickness = frame.sizes.map { |v| _mm(v) }
      ocl_sizes = PanelFrame.new(instance_info).sizes.map { |v| _mm(v) }
      if ocl_sizes.zip([ length, width, thickness ]).any? { |a, b| (a - b).abs > 0.1 }
        @warnings << "#{label}: feature geometry sticks out of the panel; OpenCutList size #{ocl_sizes.join(' x ')}, exported #{length} x #{width} x #{thickness}"
      end

      edges = {}
      EDGE_SIDES.each do |key, side|
        material = pdef.edge_materials[key]
        next if material.nil?
        edge_group_def = pdef.edge_group_defs[key]
        band_thickness = edge_group_def ? _mm(edge_group_def.std_thickness) : 0.0
        band_width = edge_group_def ? _mm(edge_group_def.std_width) : 0.0
        band_key = "#{material.display_name}|#{band_thickness}|#{band_width}"
        bands[band_key] ||= { key: band_key, name: material.display_name, thickness: band_thickness, width: band_width,
                              article: _article(material) }
        edges[side] = band_key
      end

      holes = _holes(instance_info.definition, frame, [ length, width, thickness ], pdef.flipped, label)

      {
        number: part.number,
        name: part.name,
        material_key: material_key,
        count: part.count,
        length: length,
        width: width,
        thickness: thickness,
        edges: edges,
        holes: holes
      }
    end

    def _holes(definition, frame, size, flipped, label)
      thickness = size[2]
      holes = []

      _collect_features(definition.entities, Geom::Transformation.new, [], label).each do |name, t, source|
        specs = Features.resolve(name, @presets)
        if specs.nil?
          @warnings << "#{label}: unknown feature '#{source}', skipped"
          next
        end

        origin = frame.local_point(t.origin).map { |v| _mm(v) }
        side = _side_by_position(origin, size) || _side_by_axis(frame.local_vector(t.zaxis))
        if side.nil?
          @warnings << "#{label}: feature '#{source}' is not on a panel face or edge, skipped"
          next
        end

        specs.each do |spec|
          point = t * Geom::Point3d.new(spec[:dx] / INCH, spec[:dy] / INCH, 0)
          x, y, z = frame.local_point(point).map { |v| _mm(v) }
          hole_side = side
          if flipped   # mirrored instance: physical part is the definition mirrored through its thickness
            z = (thickness - z).round(2)
            hole_side = { front: :back, back: :front }.fetch(side, side)
          end
          depth = spec[:depth]
          if %i[front back].include?(hole_side)
            depth = nil if depth && depth >= thickness
          else
            if depth.nil?
              @warnings << "#{label}: through hole '#{source}' on an edge is not supported, skipped"
              next
            end
            if (z - thickness / 2.0).abs > TOL_MM
              @warnings << "#{label}: edge hole '#{source}' is #{z} mm from the back face, off-center (the GibLab export centers it)"
            end
          end
          hole = { side: hole_side, x: x, y: y, z: z, d: spec[:d], depth: depth, source: source }
          hole[:countersink] = true if spec[:countersink]
          holes << hole
        end
      end

      holes
    end

    # f_ features placed directly in the panel or inside g_ containers (nested at any depth).
    # Everything else inside a g_ container is helper geometry and is ignored.
    # Returns [ [ feature name, transformation into panel definition space, path for messages ], ... ]
    def _collect_features(entities, transformation, path, label, found = [])
      entities.each do |entity|
        next unless entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
        name = _feature_entity_name(entity)
        component = entity.is_a?(Sketchup::ComponentInstance)
        if name.nil?
          # helper component inside a g_ container: OpenCutList lists it as a part unless it cuts opening
          if component && !path.empty? && !entity.definition.behavior.cuts_opening?
            @warnings << "#{label}: helper component '#{entity.definition.name}' in '#{path.join(' / ')}' has no 'Cuts opening' behaviour, OpenCutList may list it as a part"
          end
          next
        end

        source = (path + [ name ]).join(' / ')
        if component && !entity.definition.behavior.cuts_opening?
          @warnings << "#{label}: '#{source}' has no 'Cuts opening' behaviour, OpenCutList may list it as a part"
        end

        t = transformation * entity.transformation
        if Features.feature_name?(name)
          found << [ name, t, source ]
        else
          _collect_features(entity.definition.entities, t, path + [ name ], label, found)
        end
      end
      found
    end

    # Instance name if it is an f_/g_ name, otherwise the definition name if it is one, otherwise nil
    def _feature_entity_name(entity)
      [ entity.name, entity.definition.name ].find { |n| Features.feature_name?(n) || Features.group_name?(n) }
    end

    # Faces bounds of the panel like OpenCutList computes them (groups and Cuts-opening components
    # count as panel geometry), but without f_/g_ feature subtrees.
    def _panel_bounds(container, transformation = nil)
      bounds = Geom::BoundingBox.new
      container.entities.each do |entity|
        next if entity.is_a?(Sketchup::Edge)
        next unless entity.visible? && entity.layer.visible?
        if entity.is_a?(Sketchup::Face)
          if transformation
            entity.vertices.each { |v| bounds.add(v.position.transform(transformation)) }
          else
            bounds.add(entity.bounds)
          end
        elsif entity.is_a?(Sketchup::Group) || (entity.is_a?(Sketchup::ComponentInstance) && entity.definition.behavior.cuts_opening?)
          next unless _feature_entity_name(entity).nil?
          t = transformation ? transformation * entity.transformation : entity.transformation
          sub = _panel_bounds(entity.definition, t)
          bounds.add(sub) unless sub.empty?
        end
      end
      bounds
    end

    # Feature origin lying on exactly one panel face plane decides the side.
    def _side_by_position(origin, size)
      x, y, z = origin
      length, width, thickness = size
      candidates = []
      candidates << :back if z.abs <= TOL_MM
      candidates << :front if (z - thickness).abs <= TOL_MM
      candidates << :left if x.abs <= TOL_MM
      candidates << :right if (x - length).abs <= TOL_MM
      candidates << :bottom if y.abs <= TOL_MM
      candidates << :top if (y - width).abs <= TOL_MM
      candidates.length == 1 ? candidates.first : nil
    end

    # Fallback: glued components have their Z axis along the face's outward normal.
    def _side_by_axis(v)
      return :front if v[2] > DIR_TOL
      return :back if v[2] < -DIR_TOL
      return :right if v[0] > DIR_TOL
      return :left if v[0] < -DIR_TOL
      return :top if v[1] > DIR_TOL
      return :bottom if v[1] < -DIR_TOL
      nil
    end

    def _mm(value)
      (value.to_f * INCH).round(2)
    end

  end

end
