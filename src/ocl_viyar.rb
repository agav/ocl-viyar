require 'sketchup.rb'
require 'extensions.rb'

module OclViyar

  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('OCL Viyar Export', File.join(File.dirname(__FILE__), 'ocl_viyar', 'main'))
    ex.version     = '0.1.0'
    ex.creator     = 'Oleksandr Gavrylenko'
    ex.copyright   = 'Oleksandr Gavrylenko'
    ex.description = 'Exports OpenCutList sheet-good parts with edge banding and drillings to GibLab XML (*.project) for ViyarPro import.'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end

end
