require 'minitest/autorun'
require 'tmpdir'
require_relative '../src/ocl_viyar/features'

class TestFeatures < Minitest::Test

  F = OclViyar::Features

  def setup
    @presets = { 'confirmat_face' => [ { d: 7.0, depth: nil, dx: 0.0, dy: 0.0 } ] }
  end

  def test_normalize
    assert_equal 'f_d5x11.5', F.normalize('f_d5x11.5')
    assert_equal 'f_d5x11.5', F.normalize('f_d5x11.5#3')
    assert_equal 'f_d5x11.5', F.normalize('  f_d5x11.5 shelf pin ')
    assert_nil F.normalize('d5x11.5')
    assert_nil F.normalize('panel-left')
    assert_nil F.normalize(nil)
  end

  def test_group_name
    assert F.group_name?('g_hinge')
    assert F.group_name?('G_hinge#2 left door')
    refute F.group_name?('f_d5x11.5')
    refute F.group_name?('panel g_x')
    refute F.feature_name?('g_hinge')
  end

  def test_plain_hole
    assert_equal [ { d: 5.0, depth: 11.5, dx: 0.0, dy: 0.0 } ], F.resolve('f_d5x11.5', @presets)
    assert_equal [ { d: 5.0, depth: 11.5, dx: 0.0, dy: 0.0 } ], F.resolve('f_d5x11,5', @presets)
    assert_equal [ { d: 35.0, depth: 12.0, dx: 0.0, dy: 0.0 } ], F.resolve('F_D35X12', @presets)
  end

  def test_through_hole
    assert_equal [ { d: 7.0, depth: nil, dx: 0.0, dy: 0.0 } ], F.resolve('f_d7xF', @presets)
    assert_equal [ { d: 7.0, depth: nil, dx: 0.0, dy: 0.0 } ], F.resolve('f_d7xf', @presets)
  end

  def test_countersink_suffix
    assert_equal [ { d: 7.0, depth: nil, dx: 0.0, dy: 0.0, countersink: true } ], F.resolve('f_d7xFc', @presets)
    assert_equal [ { d: 7.0, depth: nil, dx: 0.0, dy: 0.0, countersink: true } ], F.resolve('f_d7xfc#2', @presets)
    assert_equal [ { d: 7.0, depth: nil, dx: 0.0, dy: 0.0, countersink: true } ], F.resolve('f_d7xFc_1 confirmat', @presets)
    assert_equal [ { d: 7.0, depth: 40.0, dx: 0.0, dy: 0.0, countersink: true } ], F.resolve('f_d7x40c', @presets)
    assert_nil F.resolve('f_d7xFx', @presets)
  end

  def test_copy_suffixes
    assert_equal 11.5, F.resolve('f_d5x11.5_1', @presets).first[:depth]
    assert_equal 11.5, F.resolve('f_d5x11.5#2', @presets).first[:depth]
    assert_equal 7.0, F.resolve('f_confirmat_face_2', @presets).first[:d]
  end

  def test_preset
    assert_equal 7.0, F.resolve('f_confirmat_face', @presets).first[:d]
    assert_equal 7.0, F.resolve('f_Confirmat_Face comment', @presets).first[:d]
  end

  def test_unknown
    assert_nil F.resolve('f_whatever', @presets)
    assert_nil F.resolve('f_d5', @presets)
    assert_nil F.resolve('not_a_feature', @presets)
  end

  def test_load_presets_with_override
    Dir.mktmpdir do |dir|
      a = File.join(dir, 'a.json')
      b = File.join(dir, 'b.json')
      File.write(a, '{"_comment":"x","Hinge":[{"d":35,"depth":12},{"d":8,"depth":"F","dx":-22.5,"dy":9.5}],"keep":[{"d":7,"depth":"F","countersink":true}]}')
      File.write(b, '{"hinge":[{"d":26,"depth":11}]}')
      presets = F.load_presets(a, b, File.join(dir, 'missing.json'))
      assert_equal %w[hinge keep], presets.keys.sort
      assert_equal [ { d: 26.0, depth: 11.0, dx: 0.0, dy: 0.0 } ], presets['hinge']
      presets = F.load_presets(a)
      assert_equal({ d: 8.0, depth: nil, dx: -22.5, dy: 9.5 }, presets['hinge'][1])
      assert_equal [ { d: 7.0, depth: nil, dx: 0.0, dy: 0.0, countersink: true } ], presets['keep']
    end
  end

  def test_shipped_presets_are_valid
    presets = F.load_presets(File.expand_path('../src/ocl_viyar/presets.json', __dir__))
    refute_empty presets
    presets.each_value { |holes| holes.each { |h| assert h[:d] > 0 } }
  end

end
