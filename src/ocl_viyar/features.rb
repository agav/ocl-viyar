require 'json'

module OclViyar

  # Resolves surface-feature component names (f_*) into hole specs.
  #
  # A hole spec is a Hash:
  #   d:       diameter, mm
  #   depth:   depth, mm, or nil for a through hole
  #   dx, dy:  offset from the feature component origin in its local XY plane, mm
  #   countersink: true for a confirmat hole with countersink (key present only when set)
  #
  # Pure Ruby (no SketchUp API), so it can be tested outside SketchUp.
  module Features

    NUM = '\d+(?:[.,]\d+)?'
    PLAIN_RE = /\Af_d(#{NUM})x(F|#{NUM})(c)?\z/i
    COPY_SUFFIX_RE = /_\d+\z/

    # Returns the feature name to parse: drops SketchUp's "#1" uniqueness suffix and anything after
    # the first space (free comment). Returns nil if the name doesn't start with the given prefix.
    def self.normalize(name, prefix = 'f_')
      return nil if name.nil?
      base = name.strip.sub(/#\d+\z/, '').split(/\s+/).first
      return nil if base.nil? || !base.downcase.start_with?(prefix)
      base
    end

    # f_... : a drilling (one hole or a preset)
    def self.feature_name?(name)
      !normalize(name).nil?
    end

    # g_... : a container grouping f_ features (and other g_ containers) for easier placement;
    # anything else inside it is helper geometry and is ignored
    def self.group_name?(name)
      !normalize(name, 'g_').nil?
    end

    # Returns an Array of hole specs, or nil if the name is not recognized.
    def self.resolve(name, presets)
      base = normalize(name)
      return nil if base.nil?
      [ base, base.sub(COPY_SUFFIX_RE, '') ].uniq.each do |candidate|
        if (m = PLAIN_RE.match(candidate))
          hole = { d: to_f(m[1]), depth: m[2].upcase == 'F' ? nil : to_f(m[2]), dx: 0.0, dy: 0.0 }
          hole[:countersink] = true if m[3]
          return [ hole ]
        end
        key = candidate.sub(/\Af_/i, '').downcase
        return presets[key] if presets.key?(key)
      end
      nil
    end

    # Loads presets from the given JSON files (later files override earlier ones).
    # File format: { "preset_name": [ { "d": 7, "depth": "F", "dx": 0, "dy": 0, "countersink": true }, ... ], ... }
    def self.load_presets(*paths)
      presets = {}
      paths.flatten.compact.each do |path|
        next unless File.exist?(path)
        JSON.parse(File.read(path, encoding: 'UTF-8')).each do |key, holes|
          next if key.start_with?('_')   # "_comment" style keys
          presets[key.downcase] = Array(holes).map { |h| parse_preset_hole(h, key) }
        end
      end
      presets
    end

    def self.parse_preset_hole(h, key)
      raise ArgumentError, "Preset '#{key}': hole needs 'd' and 'depth'" unless h['d'] && h['depth']
      depth = h['depth'].to_s.upcase == 'F' ? nil : to_f(h['depth'])
      hole = { d: to_f(h['d']), depth: depth, dx: to_f(h['dx'] || 0), dy: to_f(h['dy'] || 0) }
      hole[:countersink] = true if h['countersink'] == true
      hole
    end

    def self.to_f(s)
      s.to_s.tr(',', '.').to_f
    end

  end

end
