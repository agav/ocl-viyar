require 'minitest/autorun'
require 'rexml/document'
require_relative '../src/ocl_viyar/giblab_writer'
require_relative 'sample_project'

class TestGiblabWriter < Minitest::Test

  def setup
    @xml = OclViyar::GiblabWriter.new(SampleProject.build).to_xml
    @doc = REXML::Document.new(@xml)
  end

  def parts
    REXML::XPath.match(@doc, '/project/good[@typeId="product"]/part')
  end

  def op(id)
    REXML::XPath.first(@doc, "/project/operation[@id=\"#{id}\"]")
  end

  def xnc_ops
    REXML::XPath.match(@doc, '/project/operation[@typeId="XNC"]')
  end

  def test_well_formed_with_expected_goods
    types = REXML::XPath.match(@doc, '/project/good').map { |g| g.attributes['typeId'] }
    assert_equal %w[product tool.cutting tool.edgeline tool.edgeline sheet band band], types
    assert_equal 'DSP white', REXML::XPath.first(@doc, '/project/good[@typeId="sheet"]').attributes['name']
  end

  def test_part_sizes_subtract_band_thickness
    a = parts[0].attributes
    assert_equal %w[600 400], [ a['dl'], a['dw'] ]
    assert_equal %w[599.5 399], [ a['l'], a['w'] ]
    assert_equal %w[599.5 399], [ a['cl'], a['cw'] ]
    assert_equal '2', a['count']
    assert_equal 'A side', a['name']
    b = parts[1].attributes
    assert_equal %w[700 299], [ b['l'], b['w'] ]
  end

  def test_edges_reference_el_operations
    a = parts[0].attributes
    assert_equal 'Band1', a['eltMat']
    assert_equal 'Band2', a['ellMat']
    assert_nil a['elb']
    top_op = op(a['elt'].sub('@operation#', ''))
    assert_equal 'EL', top_op.attributes['typeId']
    band_good = REXML::XPath.first(@doc, "/project/good[@id=\"#{top_op.elements['material'].attributes['id']}\"]")
    assert_equal %w[band Band1 1], [ band_good.attributes['typeId'], band_good.attributes['name'], band_good.attributes['t'] ]
    assert_equal 'elb', parts[1].attributes.keys.find { |k| k.start_with?('el') && !k.end_with?('Mat') }
    assert_equal a['elt'], parts[1].attributes['elb']   # same band -> same EL operation
  end

  def test_cs_operation_lists_all_parts_and_stock
    cs = REXML::XPath.first(@doc, '/project/operation[@typeId="CS"]')
    assert_equal 3, cs.get_elements('part').length
  end

  def test_xnc_front_and_back
    assert_equal 2, xnc_ops.length
    front, back = xnc_ops
    assert_equal %w[true true true 6], [ front.attributes['side'], front.attributes['mirVert'], front.attributes['bySizeDetail'], front.attributes['countBore'] ]
    assert_equal %w[false 1], [ back.attributes['side'], back.attributes['countBore'] ]
    assert_equal parts[0].attributes['id'], front.elements['part'].attributes['id']
  end

  def test_program_holes
    program = REXML::Document.new(xnc_ops[0].attributes['program']).root
    assert_equal %w[600 400 18], [ program.attributes['dx'], program.attributes['dy'], program.attributes['dz'] ]
    tools = program.get_elements('tool').map { |t| [ t.attributes['name'], t.attributes['d'] ] }
    assert_equal [ %w[D5 5], %w[D8 8], %w[D7 7] ], tools

    holes = program.elements.to_a.reject { |e| e.name == 'tool' }
    summary = holes.map { |h| [ h.name, h.attributes['x'], h.attributes['y'], h.attributes['dp'], h.attributes['name'] ] }
    assert_equal [
      [ 'bt', '500', nil, '16', 'D5' ],     # bottom edge -> bt
      [ 'bl', nil, '368', '24', 'D5' ],
      [ 'br', nil, '70', '24', 'D5' ],
      [ 'bb', '150', nil, '30', 'D8' ],     # top edge -> bb
      [ 'bf', '120', '130', '5', 'D5' ],
      [ 'bf', '220', '220', '20', 'D7' ]    # through = thickness + 2
    ], summary

    back = REXML::Document.new(xnc_ops[1].attributes['program']).root
    assert_equal [ %w[100 300 10] ], back.get_elements('bf').map { |h| [ h.attributes['x'], h.attributes['y'], h.attributes['dp'] ] }
  end

  def test_escaping
    project = SampleProject.build
    project[:materials][0][:name] = 'ДСП "Egger" <W980> & co'
    doc = REXML::Document.new(OclViyar::GiblabWriter.new(project).to_xml)
    assert_equal 'ДСП "Egger" <W980> & co', REXML::XPath.first(doc, '/project/good[@typeId="sheet"]').attributes['name']
  end

  # Writes the sample to OCL_VIYAR_SAMPLE_OUT (if set) for a manual ViyarPro import check.
  def test_write_sample_file
    out = ENV['OCL_VIYAR_SAMPLE_OUT']
    skip 'set OCL_VIYAR_SAMPLE_OUT to write the sample' if out.nil?
    File.write(out, @xml, encoding: 'UTF-8')
  end

end
