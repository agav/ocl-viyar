require 'sketchup.rb'
require 'json'

module OclViyar

  PLUGIN_ROOT = File.dirname(__FILE__)
  SOURCE_FILES = %w[features collector giblab_writer].freeze
  MODEL_PRESETS_FILE = 'viyar_presets.json'

  SOURCE_FILES.each { |f| require File.join(PLUGIN_ROOT, f) }

  def self.export
    model = Sketchup.active_model
    unless defined?(Ladb::OpenCutList::PLUGIN)
      UI.messagebox('OpenCutList is not installed or not loaded.')
      return
    end
    if model.path.empty?
      UI.messagebox('Save the model first.')
      return
    end

    presets = Features.load_presets(File.join(PLUGIN_ROOT, 'presets.json'),
                                    File.join(File.dirname(model.path), MODEL_PRESETS_FILE))
    project = Collector.new(model, presets).run
    if project[:parts].empty?
      UI.messagebox("No sheet-good parts found.\n\n#{project[:warnings].first(20).join("\n")}")
      return
    end

    base = File.basename(model.path, '.skp')
    path = UI.savepanel('Export to Viyar (GibLab)', File.dirname(model.path), "#{base}.project")
    return if path.nil?
    path += '.project' unless path.downcase.end_with?('.project')
    stem = path.sub(/\.project\z/i, '')

    File.open(path, 'w:UTF-8') { |f| f.write(GiblabWriter.new(project).to_xml) }
    File.open("#{stem}.json", 'w:UTF-8') { |f| f.write(JSON.pretty_generate(project)) }
    report = _report(project, path)
    File.open("#{stem}.report.txt", 'w:UTF-8') { |f| f.write(report) }

    UI.messagebox(report.lines.first(25).join)
  rescue StandardError => e
    UI.messagebox("Export failed: #{e.message}\n\n#{e.backtrace.first(5).join("\n")}")
  end

  def self._report(project, path)
    hole_count = project[:parts].map { |p| p[:holes].length * p[:count] }.reduce(0, :+)
    part_count = project[:parts].map { |p| p[:count] }.reduce(0, :+)
    lines = []
    lines << "Exported to #{path}"
    lines << "Parts: #{project[:parts].length} distinct, #{part_count} total"
    lines << "Holes: #{hole_count} total"
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
    menu.add_item('Export to Viyar (GibLab)...') { export }
    menu.add_item('Reload extension (dev)') { reload }

    file_loaded(__FILE__)
  end

end
