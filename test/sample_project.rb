# Sample project mirroring the manual GibLab samples verified on ViyarPro (giblab_test_3).
module SampleProject
  def self.build
    {
      name: 'WriterTest',
      materials: [ { key: 'DSP|18.0', name: 'DSP white', thickness: 18.0, length: 2800.0, width: 2070.0 } ],
      bands: [
        { key: 'Band1|1.0|22.0', name: 'Band1', thickness: 1.0, width: 22.0 },
        { key: 'Band2|0.5|22.0', name: 'Band2', thickness: 0.5, width: 22.0 }
      ],
      parts: [
        {
          number: 'A', name: 'side', material_key: 'DSP|18.0', count: 2,
          length: 600.0, width: 400.0, thickness: 18.0,
          edges: { top: 'Band1|1.0|22.0', left: 'Band2|0.5|22.0' },
          holes: [
            { side: :bottom, x: 500.0, y: 0.0, z: 9.0, d: 5.0, depth: 16.0, source: 'f_d5x16' },
            { side: :left, x: 0.0, y: 368.0, z: 9.0, d: 5.0, depth: 24.0, source: 'f_d5x24' },
            { side: :right, x: 600.0, y: 70.0, z: 9.0, d: 5.0, depth: 24.0, source: 'f_d5x24' },
            { side: :top, x: 150.0, y: 400.0, z: 9.0, d: 8.0, depth: 30.0, source: 'f_d8x30' },
            { side: :front, x: 120.0, y: 130.0, z: 18.0, d: 5.0, depth: 5.0, source: 'f_d5x5' },
            { side: :front, x: 220.0, y: 220.0, z: 18.0, d: 7.0, depth: nil, source: 'f_d7xF' },
            { side: :back, x: 100.0, y: 300.0, z: 0.0, d: 5.0, depth: 10.0, source: 'f_d5x10' }
          ]
        },
        {
          number: 'B', name: 'shelf', material_key: 'DSP|18.0', count: 1,
          length: 700.0, width: 300.0, thickness: 18.0,
          edges: { bottom: 'Band1|1.0|22.0' },
          holes: []
        }
      ],
      warnings: []
    }
  end
end
