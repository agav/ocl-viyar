require 'sketchup.rb'
require 'json'

module OclViyar

  PLUGIN_ROOT = File.dirname(__FILE__)
  SOURCE_FILES = %w[features grooves collector sjcl viyar_writer giblab_writer].freeze
  MODEL_PRESETS_FILE = 'viyar_presets.json'

  SOURCE_FILES.each { |f| require File.join(PLUGIN_ROOT, f) }

  # ViyarPro project format (as written by Bazis2Viyar), loaded in ViyarPro's order constructor.
  def self.export
    project, path = _collect('Export to ViyarPro')
    return if project.nil?
    stem = path.sub(/\.project\z/i, '')

    writer = ViyarWriter.new(project)
    keys = writer.material_keys
    written = keys.map do |key|
      material = project[:materials].find { |m| m[:key] == key }
      file_stem = keys.length == 1 ? stem : "#{stem}_#{_file_safe(material[:name])}_#{_fmt_mm(material[:thickness])}"
      File.open("#{file_stem}.project", 'w:UTF-8') { |f| f.write(writer.to_project(key)) }
      # unencrypted copy for checking, in the encoding its XML declaration names
      File.open("#{file_stem}.xml", 'wb') { |f| f.write(writer.to_xml(key).encode('Windows-1251', undef: :replace, invalid: :replace)) }
      "#{file_stem}.project"
    end
    project[:warnings].concat(writer.warnings.uniq)
    _finish(project, stem, written)
  rescue StandardError => e
    UI.messagebox("Export failed: #{e.message}\n\n#{e.backtrace.first(5).join("\n")}")
  end

  # GibLab XML, imported via viyar.pro → Conversion → GibLab. Drillings only.
  def self.export_giblab
    project, path = _collect('Export to Viyar (GibLab)')
    return if project.nil?
    stem = path.sub(/\.project\z/i, '')
    File.open(path, 'w:UTF-8') { |f| f.write(GiblabWriter.new(project).to_xml) }
    project[:parts].reject { |p| p[:grooves].empty? }.each do |p|
      project[:warnings] << "#{p[:number]} #{p[:name]}: #{p[:grooves].length} groove(s) not exported, GibLab export supports drillings only"
    end
    _finish(project, stem, [ path ])
  rescue StandardError => e
    UI.messagebox("Export failed: #{e.message}\n\n#{e.backtrace.first(5).join("\n")}")
  end

  # Returns [ project, chosen *.project path ] or nil
  def self._collect(title)
    model = Sketchup.active_model
    unless defined?(Ladb::OpenCutList::PLUGIN)
      UI.messagebox('OpenCutList is not installed or not loaded.')
      return nil
    end
    if model.path.empty?
      UI.messagebox('Save the model first.')
      return nil
    end

    presets = Features.load_presets(File.join(PLUGIN_ROOT, 'presets.json'),
                                    File.join(File.dirname(model.path), MODEL_PRESETS_FILE))
    project = Collector.new(model, presets).run
    if project[:parts].empty?
      UI.messagebox("No sheet-good parts found.\n\n#{project[:warnings].first(20).join("\n")}")
      return nil
    end

    base = File.basename(model.path, '.skp')
    path = UI.savepanel(title, File.dirname(model.path), "#{base}.project")
    return nil if path.nil?
    path += '.project' unless path.downcase.end_with?('.project')
    [ project, path ]
  end

  def self._finish(project, stem, written)
    File.open("#{stem}.json", 'w:UTF-8') { |f| f.write(JSON.pretty_generate(project)) }
    report = _report(project, written)
    File.open("#{stem}.report.txt", 'w:UTF-8') { |f| f.write(report) }
    UI.messagebox(report.lines.first(25).join)
  end

  def self._file_safe(name)
    name.to_s.gsub(/[\/\\:*?"<>|]/, ' ').strip
  end

  def self._fmt_mm(v)
    v.to_f == v.to_i ? v.to_i.to_s : v.to_s
  end

  def self._report(project, paths)
    hole_count = project[:parts].map { |p| p[:holes].length * p[:count] }.reduce(0, :+)
    part_count = project[:parts].map { |p| p[:count] }.reduce(0, :+)
    lines = []
    paths.each { |path| lines << "Exported to #{path}" }
    lines << "Parts: #{project[:parts].length} distinct, #{part_count} total"
    lines << "Holes: #{hole_count} total"
    lines << "Grooves: #{project[:parts].map { |p| p[:grooves].length * p[:count] }.reduce(0, :+)} total"
    lines << "Materials: #{project[:materials].map { |m| m[:name] }.join(', ')}"
    lines << "Edge bands: #{project[:bands].map { |b| "#{b[:name]} (#{b[:thickness]})" }.join(', ')}"
    lines << ''
    lines << "Warnings (#{project[:warnings].length}):"
    project[:warnings].each { |w| lines << "  - #{w}" }
    lines.join("\n") + "\n"
  end

  # Development helper: reload source files without restarting SketchUp.
  def self.reload
    verbose, $VERBOSE = $VERBOSE, nil
    SOURCE_FILES.each { |f| load File.join(PLUGIN_ROOT, "#{f}.rb") }
    puts 'OCL Viyar Export reloaded'
  ensure
    $VERBOSE = verbose
  end

  unless file_loaded?(__FILE__)
    menu = UI.menu('Extensions').add_submenu('OCL Viyar Export')
    menu.add_item('Export to ViyarPro...') { export }
    menu.add_item('Export to Viyar (GibLab)...') { export_giblab }
    menu.add_item('Reload extension (dev)') { reload }

    file_loaded(__FILE__)
  end

end
