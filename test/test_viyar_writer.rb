require 'minitest/autorun'
require 'rexml/document'
require 'json'
require_relative '../src/ocl_viyar/sjcl'
require_relative '../src/ocl_viyar/grooves'
require_relative '../src/ocl_viyar/viyar_writer'
require_relative 'sample_project'

class TestViyarWriter < Minitest::Test

  KEY = 'DSP|18.0'

  def setup
    @project = SampleProject.build
    @project[:materials][0][:name] = 'ДСП Egger W980 (Артикул 12345)'
    @project[:bands][0][:name] = 'Кромка ПВХ 1x22 (Артикул 777)'
    @writer = OclViyar::ViyarWriter.new(@project)
    @xml = @writer.to_xml(KEY)
    @doc = parse(@xml)
  end

  # REXML would decode the text as windows-1251 because of the declaration; the XML is UTF-8 until written.
  def parse(xml)
    REXML::Document.new(xml.sub('encoding="windows-1251"', 'encoding="UTF-8"'))
  end

  def values(element, *names)
    names.map { |n| element.attributes[n] }
  end

  def viyar
    @doc.root.elements['viyar']
  end

  def details
    REXML::XPath.match(@doc, '/project/viyar/details/detail')
  end

  def ops(detail)
    detail.get_elements('operations/operation')
  end

  def test_header
    assert_equal %w[order creator constructor materials details], viyar.elements.map(&:name)
    assert_equal '27', viyar.attributes['version']
    assert_equal 'Bazis2Viyar', viyar.elements['creator'].attributes['id']
    assert_equal 'dsp', viyar.elements['constructor'].attributes['id']
    assert @xml.start_with?('<?xml version="1.0" encoding="windows-1251" ?>')
  end

  def test_materials_with_articles_and_band_ids
    m = REXML::XPath.match(@doc, '/project/viyar/materials/material')
    assert_equal [ '1', 'sheet', '12345', 'ДСП Egger W980', '18' ], values(m[0], 'id', 'type', 'article', 'name', 'thickness')
    # bands sorted by thickness: Band2 (0.5) gets id 2, Band1 (1.0) id 3
    assert_equal [ [ '2', 'band', '', 'Band2', '22', '0.5' ], [ '3', 'band', '777', 'Кромка ПВХ 1x22', '22', '1' ] ],
                 m[1..].map { |e| values(e, 'id', 'type', 'article', 'name', 'height', 'thickness') }
    assert(@writer.warnings.any? { |w| w.include?("'Band2' has no article") })
  end

  def test_detail_attributes_and_edges
    assert_equal [ '1', '1', '2', '600.0', '400.0', '1', 'A.side' ], values(details[0], 'id', 'material', 'amount', 'widthFull', 'heightFull', 'grain', 'description')
    edges = details[0].elements['edges'].elements.map { |e| [ e.name, e.attributes['type'], e.attributes['param'] ] }
    assert_equal [ [ 'left', 'kromka', '2' ], [ 'top', 'kromka', '3' ], [ 'right', '', '' ], [ 'bottom', '', '' ] ], edges
    assert_nil details[1].elements['operations']
  end

  def test_drillings_match_bazis_sides_and_coordinates
    summary = ops(details[0]).map { |o| values(o, 'type', 'side', 'x', 'y', 'd', 'depth') }
    assert_equal [
      %w[drilling 5 500.0 9.0 5 16.0],   # bottom edge: y across thickness from the front face
      %w[drilling 2 9.0 368.0 5 24.0],   # left edge: x across thickness
      %w[drilling 4 9.0 70.0 5 24.0],
      %w[drilling 3 150.0 9.0 8 30.0],
      %w[drilling 1 120.0 130.0 5 5.0],
      %w[drilling 1 220.0 220.0 7 23.0], # through = thickness + 5, like Bazis2Viyar
      %w[drilling 6 100.0 300.0 5 10.0]
    ], summary
    assert_equal (1..7).map(&:to_s), ops(details[0]).map { |o| o.attributes['id'] }
  end

  def test_edge_hole_off_center_uses_distance_from_front
    @project[:parts][0][:holes] = [ { side: :left, x: 0.0, y: 50.0, z: 6.0, d: 8.0, depth: 30.0 } ]
    op = ops(parse(OclViyar::ViyarWriter.new(@project).to_xml(KEY)).get_elements('//detail')[0])[0]
    assert_equal %w[2 12.0 50.0], values(op, 'side', 'x', 'y')
  end

  def test_countersink_confirmat
    @project[:parts][0][:holes] = [ { side: :front, x: 50.0, y: 9.0, z: 18.0, d: 7.1, depth: nil } ]
    op = ops(parse(OclViyar::ViyarWriter.new(@project).to_xml(KEY)).get_elements('//detail')[0])[0]
    assert_equal %w[48 7 23.0], values(op, 'subtype', 'd', 'depth')
  end

  def test_countersink_flag
    @project[:parts][0][:holes] = [ { side: :front, x: 50.0, y: 9.0, z: 18.0, d: 7.0, depth: nil, countersink: true },
                                    { side: :front, x: 80.0, y: 9.0, z: 18.0, d: 7.0, depth: nil } ]
    o = ops(parse(OclViyar::ViyarWriter.new(@project).to_xml(KEY)).get_elements('//detail')[0])
    assert_equal [ %w[48 7 23.0], [ nil, '7', '23.0' ] ], o.map { |op| values(op, 'subtype', 'd', 'depth') }
  end

  def grooves_ops(boxes)
    @project[:parts][1].merge!(length: 720.0, width: 560.0, grooves: boxes)
    w = OclViyar::ViyarWriter.new(@project)
    [ ops(parse(w.to_xml(KEY)).get_elements('//detail')[1]), w.warnings ]
  end

  def test_grooves_and_rabbets
    o, warnings = grooves_ops([
      { x: [ 530.0, 533.0 ], y: [ 0.0, 560.0 ], z: [ 13.0, 18.0 ] },   # паз on the front, along y
      { x: [ 0.0, 720.0 ], y: [ 100.0, 104.0 ], z: [ 0.0, 6.0 ] },     # паз on the back, along x
      { x: [ 712.0, 720.0 ], y: [ 0.0, 560.0 ], z: [ 0.0, 9.0 ] },     # четверть on the back, right edge
      { x: [ 0.0, 720.0 ], y: [ 550.0, 560.0 ], z: [ 10.0, 18.0 ] },   # четверть on the front, top edge
      { x: [ 100.0, 300.0 ], y: [ 550.0, 560.0 ], z: [ 6.0, 10.0 ] },  # паз in the top edge
      { x: [ 0.0, 12.0 ], y: [ 50.0, 450.0 ], z: [ 6.0, 10.0 ] }       # паз in the left edge
    ])
    assert_empty warnings.grep(/B shelf/)
    summary = o.map { |op| op.attributes.to_a.map { |a| "#{a.name}=#{a.value}" }.join(' ') }
    assert_equal [
      'id=1 type=grooving side=1 subtype=1 x=530.0 y=0 width=3.0 length=560.0 closed=0 depth=5.0',
      'id=2 type=grooving side=6 subtype=0 x=0 y=100.0 width=4.0 length=720.0 closed=0 depth=6.0',
      'id=3 type=rabbeting side=6 subtype= edge=4 shift=0 width=8.0 length=560.0 closed=0 depth=9.0',
      'id=4 type=rabbeting side=1 subtype= edge=3 shift=0 width=10.0 length=720.0 closed=0 depth=8.0',
      'id=5 type=grooving side=3 subtype=0 x=100.0 y=8.0 width=4.0 length=200.0 closed=0 depth=10.0',
      'id=6 type=grooving side=2 subtype=1 x=8.0 y=50.0 width=4.0 length=400.0 closed=0 depth=12.0'
    ], summary
  end

  def test_grooves_follow_drillings
    @project[:parts][1][:holes] = [ { side: :front, x: 50.0, y: 50.0, z: 18.0, d: 5.0, depth: 10.0 } ]
    o, = grooves_ops([ { x: [ 530.0, 533.0 ], y: [ 0.0, 560.0 ], z: [ 13.0, 18.0 ] } ])
    assert_equal [ %w[1 drilling], %w[2 grooving] ], o.map { |op| values(op, 'id', 'type') }
  end

  def test_unsupported_recesses_are_reported
    o, warnings = grooves_ops([
      { x: [ 100.0, 200.0 ], y: [ 100.0, 200.0 ], z: [ 0.0, 18.0 ] },   # through the thickness
      { x: [ 0.0, 10.0 ], y: [ 550.0, 560.0 ], z: [ 6.0, 10.0 ] }       # edge slot at a corner
    ])
    assert_empty o
    assert_equal 2, warnings.grep(/B shelf: (recess through|edge groove)/).length
  end

  def test_not_grained_and_small_part_warning
    @project[:materials][0][:grained] = false
    @project[:parts][1][:width] = 60.0
    w = OclViyar::ViyarWriter.new(@project)
    doc = parse(w.to_xml(KEY))
    assert_equal '0', doc.get_elements('//detail')[0].attributes['grain']
    assert(w.warnings.any? { |m| m.start_with?('B shelf: smaller than 70 mm') })
  end

  def test_one_material_per_file
    @project[:materials] << { key: 'HDF|3.0', name: 'HDF', thickness: 3.0, length: 2800.0, width: 2070.0 }
    @project[:parts][1][:material_key] = 'HDF|3.0'
    w = OclViyar::ViyarWriter.new(@project)
    assert_equal [ KEY, 'HDF|3.0' ], w.material_keys
    hdf = parse(w.to_xml('HDF|3.0'))
    assert_equal [ 'B.shelf' ], hdf.get_elements('//detail').map { |d| d.attributes['description'] }
    assert_equal %w[sheet band], hdf.get_elements('//material').map { |m| m.attributes['type'] }
  end

  def test_article_from_description_wins_over_name
    @project[:materials][0][:article] = '81234'
    @project[:bands][1][:article] = '555'
    m = parse(OclViyar::ViyarWriter.new(@project).to_xml(KEY)).get_elements('//material')
    assert_equal [ [ '81234', 'ДСП Egger W980' ], [ '555', 'Band2' ], [ '777', 'Кромка ПВХ 1x22' ] ],
                 m.map { |e| values(e, 'article', 'name') }
  end

  def test_split_name_code
    assert_equal [ 'ДСП Біла', '81234' ], @writer.split_name_code('ДСП "Біла" (Артикул 81234)')
    assert_equal [ 'ДСП', '81234' ], @writer.split_name_code("ДСП\n81234")
    assert_equal [ 'ДСП', '' ], @writer.split_name_code('ДСП')
  end

  # Independent check with OpenSSL's AES-CCM: decrypting the SJCL JSON gives back the XML.
  def test_project_decrypts_to_xml
    json = JSON.parse(@writer.to_project(KEY))
    assert_equal [ 1, 10_000, 128, 64, 'ccm', 'aes', '' ], json.values_at('v', 'iter', 'ks', 'ts', 'mode', 'cipher', 'adata')
    salt, iv, ct = %w[salt iv ct].map { |k| Base64.strict_decode64(json[k]) }
    key = OpenSSL::PKCS5.pbkdf2_hmac(OclViyar::ViyarWriter::PASSWORD, salt, 10_000, 16, OpenSSL::Digest.new('SHA256'))
    data, tag = ct.byteslice(0, ct.bytesize - 8), ct.byteslice(-8, 8)
    l = data.bytesize < 65_536 ? 2 : 3
    c = OpenSSL::Cipher.new('aes-128-ccm')
    c.decrypt
    c.iv_len = 15 - l
    c.auth_tag_len = 8
    c.key = key
    c.iv = iv.byteslice(0, 15 - l)
    c.auth_tag = tag
    c.ccm_data_len = data.bytesize
    assert_equal @xml, (c.update(data) + c.final).force_encoding('UTF-8')
  end

  # Writes the sample to OCL_VIYAR_SAMPLE_OUT (*.project) for a manual ViyarPro import check.
  def test_write_sample_project
    out = ENV['OCL_VIYAR_SAMPLE_OUT']
    skip 'set OCL_VIYAR_SAMPLE_OUT to write the sample' if out.nil?
    File.write(out, @writer.to_project(KEY), encoding: 'UTF-8')
  end

end
