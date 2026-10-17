module OclViyar

  # Writes a project Hash (see Collector#run) in ViyarPro's own project format, the one the
  # Bazis2Viyar script (Bazis-Mebelshchik → ViyarPro, v5.10) produces and ViyarPro's order
  # constructor loads with "Load from file". The XML is encrypted with Sjcl, as Bazis2Viyar does.
  #
  # One file holds one sheet material (like Bazis2Viyar), so the writer works per material key.
  #
  # Panel frame, as in Bazis2Viyar: x along length (widthFull), y along width (heightFull), origin at
  # the bottom-left corner seen from the front face. Operation sides: 1 front, 2 left, 3 top,
  # 4 right, 5 bottom, 6 back. Edge holes: the coordinate across the thickness is measured from the
  # front face.
  #
  # Pure Ruby (no SketchUp API).
  class ViyarWriter

    # Bazis2Viyar's encryption password (constant PASSWORD in "Экспорт проекта ViyarPro.js")
    PASSWORD = 'c928f7180e21ff8eae69f0b039d5279e90fa68607851d1a3835b8de2b739dba7'
    VIYAR_VERSION = 27
    CREATOR_ID = 'Bazis2Viyar'
    CREATOR_VERSION = '5.10'
    SHEET_SIZE = 3000
    THROUGH_EXTRA = 5.0
    MIN_PART_SIZE = 70.0
    COUNTERSINK_D = 7.1   # Bazis2Viyar convention: a 7.1 hole is a 7 mm confirmat hole with countersink
    COUNTERSINK_SUBTYPE = '48'
    CONFIRMAT_D = 7.0
    ARTICLE_KEY = '(Артикул'

    SIDE_FRONT = 1
    SIDE_LEFT = 2
    SIDE_TOP = 3
    SIDE_RIGHT = 4
    SIDE_BOTTOM = 5
    SIDE_BACK = 6
    EDGE_ORDER = %i[left top right bottom]

    attr_reader :warnings

    def initialize(project)
      @project = project
      @warnings = []
    end

    # Material keys that have parts, in project order
    def material_keys
      @project[:materials].map { |m| m[:key] }.select { |key| @project[:parts].any? { |p| p[:material_key] == key } }
    end

    def to_project(material_key)
      Sjcl.encrypt(PASSWORD, to_xml(material_key))
    end

    def to_xml(material_key)
      material = @project[:materials].find { |m| m[:key] == material_key }
      raise ArgumentError, "Unknown material '#{material_key}'" if material.nil?
      parts = @project[:parts].select { |p| p[:material_key] == material_key }

      band_keys = parts.flat_map { |p| p[:edges].values }.uniq
      bands = band_keys.map { |k| @project[:bands].find { |b| b[:key] == k } }.sort_by { |b| b[:thickness].to_f }
      band_ids = {}
      bands.each_with_index { |b, i| band_ids[b[:key]] = i + 2 }   # sheet material is id 1

      sheet_name, sheet_article = name_and_article(material)
      @warnings << "Material '#{material[:name]}' has no article; put it in the OpenCutList material description" if sheet_article.empty?

      x = '<?xml version="1.0" encoding="windows-1251" ?>' + "\n"
      x << _open('project', 'currency' => '', 'version' => '1', 'costOperation' => '0', 'costMaterial' => '0', 'cost' => '0',
                            'date' => '', 'orderDate' => '', 'productFilter' => false)
      x << _open('viyar', 'version' => VIYAR_VERSION)
      x << _tag('order', 'delivery' => '', 'uuid' => '')
      x << _tag('creator', 'id' => CREATOR_ID, 'version' => CREATOR_VERSION, 'bazisVersion' => '')
      x << _tag('constructor', 'id' => 'dsp', 'site' => '')

      x << _open('materials')
      x << _tag('material', 'id' => 1, 'type' => 'sheet', 'article' => sheet_article, 'name' => sheet_name,
                            'width' => SHEET_SIZE, 'height' => SHEET_SIZE, 'thickness' => _num(material[:thickness], 1))
      bands.each do |b|
        name, article = name_and_article(b)
        @warnings << "Edge band '#{b[:name]}' has no article" if article.empty?
        x << _tag('material', 'id' => band_ids[b[:key]], 'type' => 'band', 'article' => article, 'name' => name,
                              'height' => _num(b[:width], 1), 'thickness' => _num(b[:thickness], 2))
      end
      x << "</materials>\n"

      x << _open('details')
      parts.each_with_index { |part, i| x << _detail(part, i + 1, material, band_ids) }
      x << "</details>\n"

      x << "</viyar>\n</project>\n"
      x
    end

    # Article from the material's :article (OpenCutList description), else from its name
    def name_and_article(material)
      name, code = split_name_code(material[:name])
      article = material[:article].to_s.strip
      [ name, article.empty? ? code : article ]
    end

    # Bazis convention: "<name> (Артикул <code>)", or the code on the second line of the name.
    # Quotes are dropped from the name, like Bazis2Viyar does.
    def split_name_code(full_name)
      full_name = full_name.to_s
      start = full_name.rindex(ARTICLE_KEY)
      finish = full_name.rindex(')')
      if start && start > 0 && finish && finish > start
        name = full_name[0...start]
        code = full_name[(start + ARTICLE_KEY.length)...finish]
      else
        name, code = full_name.split(/\r\n|\r|\n/)
      end
      [ name.to_s.strip.delete('"\''), code.to_s.strip ]
    end

    private

    def _detail(part, id, material, band_ids)
      label = "#{part[:number]} #{part[:name]}".strip
      if part[:length] < MIN_PART_SIZE || part[:width] < MIN_PART_SIZE
        @warnings << "#{label}: smaller than #{MIN_PART_SIZE.to_i} mm, ViyarPro may reject it (Bazis2Viyar adds a clipping operation, not implemented)"
      end
      description = [ part[:number], part[:name] ].map(&:to_s).reject(&:empty?).join('.')

      x = _open('detail', 'id' => id, 'material' => '1', 'barcode' => '', 'amount' => part[:count],
                          'widthFull' => _fixed(part[:length]), 'heightFull' => _fixed(part[:width]), 'multiplicity' => 1,
                          'grain' => material.fetch(:grained, true) ? '1' : '0', 'description' => description, 'marker' => '0')
      x << _open('edges')
      EDGE_ORDER.each do |side|
        band_key = part[:edges][side]
        x << _tag(side.to_s, 'type' => band_key ? 'kromka' : '', 'param' => band_key ? band_ids[band_key] : '', 'drop' => '0')
      end
      x << "</edges>\n"

      operations = part[:holes].map { |h| _drilling_attrs(_drilling(part, h)) }
      (part[:grooves] || []).each do |box|
        attrs = _groove_attrs(part, box, label)
        operations << attrs unless attrs.nil?
      end
      unless operations.empty?
        x << _open('operations')
        operations.each_with_index { |attrs, i| x << _tag('operation', { 'id' => i + 1 }.merge(attrs)) }
        x << "</operations>\n"
      end
      x << "</detail>\n"
    end

    def _drilling_attrs(d)
      attrs = { 'type' => 'drilling' }
      attrs['subtype'] = COUNTERSINK_SUBTYPE if d[:countersink]
      attrs.merge('side' => d[:side], 'x' => _fixed(d[:x]), 'y' => _fixed(d[:y]), 'xo' => _fixed(d[:x]), 'yo' => _fixed(d[:y]),
                  'xl' => '0', 'yl' => '0', 'd' => _num(d[:d], 1), 'depth' => _fixed(d[:depth]))
    end

    # Box of removed material (Collector frame) -> Bazis2Viyar grooving / rabbeting attributes, or nil.
    # Like Bazis2Viyar's plane cuts: a box open to the front or back face is a groove (паз), or a
    # rabbet (четверть) when it also reaches the panel edge it runs along; a box open to an edge
    # face only is a groove in that edge. Runs along y (subtype 1) when longer in y, else along x (0).
    def _groove_attrs(part, box, label)
      l, w, t = part[:length], part[:width], part[:thickness]
      (x1, x2), (y1, y2), (z1, z2) = box[:x], box[:y], box[:z]
      front = (z2 - t).abs <= Grooves::EDGE_TOL
      back = z1.abs <= Grooves::EDGE_TOL
      touch = ->(v, limit) { (v - limit).abs <= Grooves::EDGE_TOL }

      if front && back
        @warnings << "#{label}: recess through the whole thickness (#{Grooves.describe(box)}) is not a groove, skipped"
        return nil
      end

      if front || back
        side = front ? SIDE_FRONT : SIDE_BACK
        vertical = (y2 - y1) > (x2 - x1)
        edge = if vertical
                 touch.(x2, l) ? SIDE_RIGHT : (touch.(x1, 0) ? SIDE_LEFT : nil)
               else
                 touch.(y2, w) ? SIDE_TOP : (touch.(y1, 0) ? SIDE_BOTTOM : nil)
               end
        across, along = vertical ? [ x2 - x1, [ y1, y2 ] ] : [ y2 - y1, [ x1, x2 ] ]
        common = { 'width' => _fixed(across), 'length' => _fixed(along[1] - along[0]), 'closed' => 0, 'depth' => _fixed(z2 - z1) }
        if edge
          { 'type' => 'rabbeting', 'side' => side, 'subtype' => '', 'edge' => edge, 'shift' => _fixed(along[0]) }.merge(common)
        else
          { 'type' => 'grooving', 'side' => side, 'subtype' => vertical ? 1 : 0, 'x' => _fixed(x1), 'y' => _fixed(y1) }.merge(common)
        end
      else
        edges = [ [ SIDE_LEFT, touch.(x1, 0) ], [ SIDE_RIGHT, touch.(x2, l) ], [ SIDE_BOTTOM, touch.(y1, 0) ], [ SIDE_TOP, touch.(y2, w) ] ]
                .select(&:last).map(&:first)
        if edges.length != 1
          @warnings << "#{label}: edge groove #{Grooves.describe(box)} must open to exactly one edge, skipped"
          return nil
        end
        edge = edges.first
        across = t - z2   # from the front face
        vertical = [ SIDE_LEFT, SIDE_RIGHT ].include?(edge)
        x, y, length, depth = vertical ? [ across, y1, y2 - y1, x2 - x1 ] : [ x1, across, x2 - x1, y2 - y1 ]
        { 'type' => 'grooving', 'side' => edge, 'subtype' => vertical ? 1 : 0, 'x' => _fixed(x), 'y' => _fixed(y),
          'width' => _fixed(z2 - z1), 'length' => _fixed(length), 'closed' => 0, 'depth' => _fixed(depth) }
      end
    end

    # Hole (Collector frame, z from the back face) -> Bazis2Viyar drilling
    def _drilling(part, hole)
      t = part[:thickness]
      across = t - hole[:z].to_f   # edge holes: distance from the front face
      side, x, y = case hole[:side]
                   when :front then [ SIDE_FRONT, hole[:x], hole[:y] ]
                   when :back then [ SIDE_BACK, hole[:x], hole[:y] ]
                   when :left then [ SIDE_LEFT, across, hole[:y] ]
                   when :right then [ SIDE_RIGHT, across, hole[:y] ]
                   when :bottom then [ SIDE_BOTTOM, hole[:x], across ]
                   when :top then [ SIDE_TOP, hole[:x], across ]
                   else raise ArgumentError, "Unknown hole side #{hole[:side].inspect}"
                   end
      bazis_countersink = (hole[:d] - COUNTERSINK_D).abs < 0.01
      depth = hole[:depth].nil? ? t + THROUGH_EXTRA : hole[:depth]
      { side: side, x: x, y: y, d: bazis_countersink ? CONFIRMAT_D : hole[:d], depth: depth,
        countersink: bazis_countersink || hole[:countersink] == true }
    end

    # Bazis2Viyar's rnd(): fixed one decimal ("12.0"), "0" for zero
    def _fixed(v)
      s = format('%.1f', v.to_f + 0.00005)
      s.to_f == 0 ? '0' : s
    end

    # Bazis2Viyar's rnds(): rounded, trailing zeros dropped
    def _num(v, digits)
      s = format("%.#{digits}f", v.to_f + 0.00005).sub(/(?:\.0+|(\.\d+?)0+)\z/, '\1')
      s.to_f == 0 ? '0' : s
    end

    def _tag(name, attrs = {})
      "<#{name}#{_attrs(attrs)} />\n"
    end

    def _open(name, attrs = {})
      "<#{name}#{_attrs(attrs)}>\n"
    end

    def _attrs(attrs)
      attrs.map { |k, v| " #{k}=\"#{_escape(v)}\"" }.join
    end

    def _escape(s)
      s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
    end

  end

end
