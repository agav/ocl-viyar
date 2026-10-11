require 'securerandom'

module OclViyar

  # Writes a project Hash (see Collector#run) as GibLab XML (*.project), the format ViyarPro's
  # "Conversion" page imports as GibLab.
  #
  # Coordinates: x from the left edge along length, y from the bottom edge along width, mm,
  # finished panel size (bySizeDetail="true"), bottom-left origin (mirVert="true").
  # GibLab quirk: edge banding uses elb = bottom / elt = top, but edge HOLES use bt = bottom / bb = top.
  #
  # Pure Ruby (no SketchUp API).
  class GiblabWriter

    VERSION = '21052101'
    THROUGH_EXTRA = 2.0
    BAND_ATTR = { bottom: 'elb', top: 'elt', left: 'ell', right: 'elr' }
    EDGE_HOLE = { bottom: [ 'bt', :x ], top: [ 'bb', :x ], left: [ 'bl', :y ], right: [ 'br', :y ] }
    BAND_COLORS = %w[#000000 #D2691E #1E90FF #228B22 #8B008B #B22222]

    def initialize(project)
      @project = project
    end

    def to_xml
      @good_id = 0
      @part_id = 0
      @op_id = 0

      product_good = _next(:good)
      cutting_tool_good = _next(:good)

      sheets = {}
      @project[:materials].each do |m|
        sheets[m[:key]] = { material: m, good: _next(:good), stock_part: _next(:part), op: _next(:op), part_ids: [] }
      end

      bands = {}
      @project[:bands].each_with_index do |b, i|
        bands[b[:key]] = { band: b, tool: _next(:good), good: _next(:good), op: _next(:op), index: i, part_ids: [] }
      end

      part_ids = @project[:parts].map { _next(:part) }

      product_parts = []
      xnc_ops = []
      @project[:parts].each_with_index do |part, i|
        id = part_ids[i]
        sheets[part[:material_key]][:part_ids] << id
        part[:edges].each_value { |band_key| bands[band_key][:part_ids] << id unless bands[band_key][:part_ids].include?(id) }
        product_parts << _product_part(part, id, bands)
        xnc_ops.concat(_xnc_ops(part, id))
      end

      x = '<?xml version="1.0" encoding="UTF-8"?>'
      x << _tag('project', { 'project.uuid' => SecureRandom.uuid, 'version' => VERSION, 'costOperation' => 0, 'costMaterial' => 0, 'cost' => 0,
                             'date' => _now_ms, 'orderDate' => _now_ms }, false)

      x << _tag('good', { 'typeId' => 'product', 'count' => 1, 'id' => product_good, 'name' => @project[:name],
                          'costMaterial' => 0, 'costOperation' => 0, 'cost' => 0 }, false)
      product_parts.each { |p| x << p }
      x << '</good>'

      x << _tag('good', { 'typeId' => 'tool.cutting', 'swSawthick' => 4.4, 'swSawthickDiv' => -1, 'swPackageHeight' => 40, 'swMaxturns' => 6,
                          'swComplexBand' => true, 'swTrimIncludeSaw' => false, 'swSort' => 0, 'swSortInBand' => 3, 'swMinSizeBand' => 0,
                          'swMaxSizeBand' => 0, 'swMinPruning' => 0, 'swMaxLengthBand' => 0, 'id' => cutting_tool_good })

      bands.each_value do |b|
        x << _tag('good', { 'typeId' => 'tool.edgeline', 'elRestSide' => 0, 'elMinSize' => 0, 'elWidthPreJoint' => 0, 'elCost' => 0, 'id' => b[:tool] })
      end

      sheets.each_value do |s|
        m = s[:material]
        x << _tag('good', { 'typeId' => 'sheet', 'w' => m[:width], 'l' => m[:length], 't' => m[:thickness], 'count' => 0, 'cost' => 0,
                            'name' => m[:name], 'id' => s[:good] }, false)
        x << _tag('part', { 'l' => m[:length], 'w' => m[:width], 'count' => 1000, 'usedCount' => 0, 'id' => s[:stock_part] })
        x << '</good>'
      end

      bands.each_value do |b|
        x << _tag('good', { 'typeId' => 'band', 'w' => b[:band][:width], 't' => b[:band][:thickness], 'count' => 0, 'cost' => 0,
                            'name' => b[:band][:name], 'id' => b[:good] })
      end

      sheets.each_value do |s|
        m = s[:material]
        x << _tag('operation', { 'l' => m[:length], 'w' => m[:width], 't' => m[:thickness], 'tool1' => cutting_tool_good,
                                 'cFillRep' => 0.9, 'cCPF' => 0.9, 'cCostCut' => 0, 'cCostType' => 0, 'cSizeMode' => 1, 'cTrimL' => 10, 'cTrimW' => 10,
                                 'cMinDimRegWaste1' => 400, 'cMinDimRegWaste2' => 100, 'cBusinessWaste' => 10, 'cTrimWaste' => true,
                                 'cSaveDrawCut' => false, 'cMinDimDetail' => 0, 'cMaxPartsOnPattern' => 0, 'cCostByItem' => false,
                                 'cCostByItemRound' => 11, 'cPrefLargePacket' => false, 'cCombiningParts' => false, 'cGroupParts' => 0,
                                 'cAllowanceWorkpiece' => 0, 'typeId' => 'CS', 'costMaterial' => 0, 'costOperation' => 0, 'costTotal' => 0,
                                 'printable' => true, 'startNewPage' => true, 'id' => s[:op], 'csDirectCut' => 0, 'csTexture' => true }, false)
        x << _tag('material', { 'id' => s[:good], 'count' => 0 })
        s[:part_ids].each { |id| x << _tag('part', { 'id' => id }) }
        x << _tag('part', { 'id' => s[:stock_part] })
        x << '</operation>'
      end

      bands.each_value do |b|
        x << _tag('operation', { 'elWastePRC' => 0, 'elCalcMat' => true, 'elLength' => 0, 'tool1' => b[:tool],
                                 'elSymbol' => _band_symbol(b[:index]), 'elColor' => BAND_COLORS[b[:index] % BAND_COLORS.length],
                                 'elLineMark' => 0, 'elRoundMat' => 20, 'elRoundLength' => 20, 'elMinDimDetail' => 0, 'typeId' => 'EL',
                                 'costMaterial' => 0, 'costOperation' => 0, 'costTotal' => 0, 'printable' => true, 'startNewPage' => true,
                                 'id' => b[:op] }, false)
        x << _tag('material', { 'id' => b[:good], 'count' => 0 })
        b[:part_ids].each { |id| x << _tag('part', { 'id' => id }) }
        x << '</operation>'
      end

      xnc_ops.each { |op| x << op }

      x << '</project>'
      x
    end

    private

    def _product_part(part, id, bands)
      band_t = Hash.new(0.0)
      part[:edges].each { |side, band_key| band_t[side] = bands[band_key][:band][:thickness].to_f }
      cut_l = part[:length] - band_t[:left] - band_t[:right]
      cut_w = part[:width] - band_t[:bottom] - band_t[:top]

      attrs = { 'l' => cut_l, 'w' => cut_w, 'dl' => part[:length], 'dw' => part[:width], 'jl' => cut_l, 'jw' => cut_w,
                'cl' => cut_l, 'cw' => cut_w, 'minusCount' => 0, 'count' => part[:count], 'usedCount' => 0, 'txt' => true,
                'id' => id, 'name' => "#{part[:number]} #{part[:name]}".strip }
      BAND_ATTR.each do |side, attr|
        band_key = part[:edges][side]
        next if band_key.nil?
        attrs[attr] = "@operation##{bands[band_key][:op]}"
        attrs["#{attr}Mat"] = bands[band_key][:band][:name]
      end
      _tag('part', attrs)
    end

    # One XNC operation per drilled side: front (side="true", includes edge holes) and back (side="false").
    def _xnc_ops(part, id)
      front = part[:holes].reject { |h| h[:side] == :back }
      back = part[:holes].select { |h| h[:side] == :back }
      ops = []
      [ [ front, true ], [ back, false ] ].each do |holes, side|
        next if holes.empty?
        program = _program(part, holes)
        attrs = { 'program' => program, 'count' => 1, 'side' => side, 'turn' => 0, 'mirHor' => false, 'mirVert' => true,
                  'bySizeDetail' => true, 'priceBore' => 0, 'countBore' => holes.length, 'costBore' => 0, 'priceMill' => 0,
                  'countMill' => 0, 'costMill' => 0, 'priceCut' => 0, 'countCut' => 0, 'costCut' => 0, 'price' => 0, 'cost' => 0,
                  'typeId' => 'XNC', 'costMaterial' => 0, 'costOperation' => 0, 'costTotal' => 0, 'printable' => true,
                  'startNewPage' => true, 'id' => _next(:op) }
        ops << _tag('operation', attrs, false) + _tag('part', { 'id' => id }) + '</operation>'
      end
      ops
    end

    def _program(part, holes)
      x = _tag('program', { 'dx' => part[:length], 'dy' => part[:width], 'dz' => part[:thickness] }, false)
      holes.map { |h| h[:d] }.uniq.each { |d| x << _tag('tool', { 'name' => _tool_name(d), 'd' => d }) }
      holes.each do |h|
        depth = h[:depth].nil? ? part[:thickness] + THROUGH_EXTRA : h[:depth]
        if %i[front back].include?(h[:side])
          x << _tag('bf', { 'x' => h[:x], 'y' => h[:y], 'dp' => depth, 'ac' => 1, 'av' => false, 'name' => _tool_name(h[:d]) })
        else
          tag, coord = EDGE_HOLE[h[:side]]
          x << _tag(tag, { 'ver' => 2, coord.to_s => h[coord], 'dp' => depth, 'ac' => 1, 'm' => true, 'name' => _tool_name(h[:d]) })
        end
      end
      x << '</program>'
      '<?xml version="1.0" encoding="UTF-8"?>' + x
    end

    def _tool_name(d)
      "D#{_fmt(d)}"
    end

    def _band_symbol(index)
      index < 26 ? ('A'.ord + index).chr : "A#{index}"
    end

    def _next(kind)
      case kind
      when :good then @good_id += 1
      when :part then @part_id += 1
      when :op then @op_id += 1
      end
    end

    def _now_ms
      (Time.now.to_f * 1000).to_i
    end

    def _tag(name, attrs, self_closing = true)
      s = "<#{name}"
      attrs.each { |k, v| s << " #{k}=\"#{_escape(_fmt(v))}\"" }
      s << (self_closing ? '/>' : '>')
      s
    end

    def _fmt(v)
      case v
      when Float
        r = v.round(2)
        r == r.to_i ? r.to_i.to_s : format('%.2f', r).sub(/0+\z/, '')
      else
        v.to_s
      end
    end

    def _escape(s)
      s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
    end

  end

end
