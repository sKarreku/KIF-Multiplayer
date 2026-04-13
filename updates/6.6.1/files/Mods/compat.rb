# ============================================================================
#  Mod Compatibility Checker for KIF Multiplayer + EBDX
#  Place this file in the Mods/ folder and run via check_compat.bat
# ============================================================================

# ---------------------------------------------------------------------------
#  RbParser — extracts definitions from a single .rb file using regex
# ---------------------------------------------------------------------------
class RbParser
  Definition = Struct.new(:kind, :scope, :name, :target, :file, :line)
  # kind:   :class, :module, :method, :alias
  # scope:  the enclosing class/module (e.g. "PokeBattle_Battle") or "(global)"
  # name:   the defined name (method name, alias new name, class name)
  # target: for aliases, the original method being aliased; nil otherwise
  # file:   source file path
  # line:   line number

  def self.parse(filepath)
    defs = []
    scope_stack = []  # tracks nested class/module/def context
    lines = File.readlines(filepath, encoding: "utf-8") rescue []
    # Track whether we're inside a string or block to avoid false positives
    in_multiline_string = false

    lines.each_with_index do |raw_line, idx|
      lineno = idx + 1
      line = raw_line.rstrip

      # Basic heredoc / multiline string tracking
      if in_multiline_string
        in_multiline_string = false if line.rstrip =~ /\A\s*(EOF|EOS|HEREDOC|END_SQL)\s*\z/
        next
      end
      if line =~ /<<[~-]?\s*['"]?(EOF|EOS|HEREDOC|END_SQL)['"]?\s*$/
        in_multiline_string = true
        next
      end

      stripped = line.lstrip
      next if stripped.empty? || stripped.start_with?("#")

      # Determine current scope (skip over (def) entries to find enclosing class/module)
      current_scope = "(global)"
      scope_stack.reverse_each do |entry|
        if entry != "(def)"
          current_scope = entry
          break
        end
      end

      # --- end detection (pop scope) ---
      if stripped =~ /\Aend\b/
        scope_stack.pop unless scope_stack.empty?
        next
      end

      # --- class detection ---
      if stripped =~ /\Aclass\s+([A-Z][\w:]*)/
        class_name = $1.split("::").last
        defs << Definition.new(:class, current_scope, class_name, nil, filepath, lineno)
        scope_stack.push(class_name)
        next
      end

      # --- module detection ---
      if stripped =~ /\Amodule\s+([A-Z][\w:]*)/
        mod_name = $1.split("::").last
        defs << Definition.new(:module, current_scope, mod_name, nil, filepath, lineno)
        scope_stack.push(mod_name)
        next
      end

      # --- method detection: def self.method or def method ---
      if stripped =~ /\Adef\s+(self\.)?(\w+[?!=]?)/
        is_self = !$1.nil?
        method_name = $2
        qualified = is_self ? "self.#{method_name}" : method_name
        defs << Definition.new(:method, current_scope, qualified, nil, filepath, lineno)
        scope_stack.push("(def)")
        next
      end

      # --- alias detection: alias new_name old_name ---
      if stripped =~ /\Aalias\s+(\w+[?!=]?)\s+(\w+[?!=]?)/
        new_name = $1
        old_name = $2
        defs << Definition.new(:alias, current_scope, new_name, old_name, filepath, lineno)
        next
      end

      # --- alias_method detection ---
      if stripped =~ /\Aalias_method\s*[\(]?\s*[:\"](\w+[?!=]?)["']?\s*,\s*[:\"](\w+[?!=]?)/
        new_name = $1
        old_name = $2
        defs << Definition.new(:alias, current_scope, new_name, old_name, filepath, lineno)
        next
      end
    end

    defs
  end
end

# ---------------------------------------------------------------------------
#  Registry — holds all definitions from a set of folders
# ---------------------------------------------------------------------------
class Registry
  attr_reader :classes, :modules, :methods, :aliases, :all_defs

  def initialize
    @classes  = {}  # "ClassName" => [Definition, ...]
    @modules  = {}  # "ModuleName" => [Definition, ...]
    @methods  = {}  # "Scope#method" => [Definition, ...]
    @aliases  = {}  # "Scope#alias_new" => [Definition, ...]
    @all_defs = []
  end

  def load_folder(folder_path)
    return unless Dir.exist?(folder_path)
    Dir.glob(File.join(folder_path, "*.rb")).sort.each do |f|
      defs = RbParser.parse(f)
      defs.each { |d| register(d) }
      @all_defs.concat(defs)
    end
  end

  def register(d)
    case d.kind
    when :class
      (@classes[d.name] ||= []) << d
    when :module
      (@modules[d.name] ||= []) << d
    when :method
      key = "#{d.scope}##{d.name}"
      (@methods[key] ||= []) << d
    when :alias
      key = "#{d.scope}##{d.name}"
      (@aliases[key] ||= []) << d
      # Also register the target (old method) as being touched
      tkey = "#{d.scope}##{d.target}"
      (@aliases[tkey] ||= []) << d
    end
  end

  def has_class?(name)
    @classes.key?(name)
  end

  def has_module?(name)
    @modules.key?(name)
  end

  def has_method?(scope, method_name)
    @methods.key?("#{scope}##{method_name}")
  end

  def has_alias_touching?(scope, method_name)
    @aliases.key?("#{scope}##{method_name}")
  end

  def source_label(scope, method_name)
    key = "#{scope}##{method_name}"
    entry = @methods[key]&.first || @aliases[key]&.first
    return nil unless entry
    File.basename(entry.file)
  end
end

# ---------------------------------------------------------------------------
#  Comparator — checks mod definitions against the registry
# ---------------------------------------------------------------------------
class Comparator
  Result = Struct.new(:status, :mod_file, :kind, :scope, :name, :detail, :line)
  # status: :compatible, :warning, :not_compatible

  def initialize(registry)
    @registry = registry
  end

  def check(mod_defs)
    results = []
    reopened_scopes = {}

    mod_defs.each do |d|
      case d.kind
      when :class
        if @registry.has_class?(d.name)
          reopened_scopes[d.name] = true
          # Don't add a result yet — methods inside will determine severity
        end

      when :module
        if @registry.has_module?(d.name)
          reopened_scopes[d.name] = true
        end

      when :method
        scope = d.scope
        next if scope == "(def)" || scope == "(global)" && !method_is_global_conflict?(d)

        effective_scope = scope == "(global)" ? "(global)" : scope

        if @registry.has_method?(effective_scope, d.name) ||
           @registry.has_alias_touching?(effective_scope, d.name)
          source = @registry.source_label(effective_scope, d.name)
          detail = "Redefines #{effective_scope}##{d.name}"
          detail += " (also in #{source})" if source
          results << Result.new(:not_compatible, d.file, :method, effective_scope, d.name, detail, d.line)
        end

      when :alias
        scope = d.scope
        # Check if the target method (being aliased away) conflicts
        if @registry.has_method?(scope, d.target) ||
           @registry.has_alias_touching?(scope, d.target)
          source = @registry.source_label(scope, d.target)
          detail = "Aliases over #{scope}##{d.target}"
          detail += " (also aliased in #{source})" if source
          results << Result.new(:not_compatible, d.file, :alias, scope, d.name, detail, d.line)
        end
      end
    end

    # Add warnings for class/module reopenings that didn't produce conflicts
    conflicted_scopes = results.select { |r| r.status == :not_compatible }.map(&:scope).uniq
    reopened_scopes.each do |scope_name, _|
      unless conflicted_scopes.include?(scope_name)
        results << Result.new(:warning, mod_defs.first&.file, :class, scope_name, scope_name,
          "Reopens #{scope_name} (also modified by 659/660) — different methods, but test carefully", 0)
      end
    end

    results
  end

  private

  def method_is_global_conflict?(d)
    @registry.has_method?("(global)", d.name) ||
      @registry.has_alias_touching?("(global)", d.name)
  end
end

# ---------------------------------------------------------------------------
#  Reporter — formats and outputs results
# ---------------------------------------------------------------------------
class Reporter
  STATUS_LABELS = {
    compatible:     "[COMPATIBLE]    ",
    warning:        "[WARNING]       ",
    not_compatible: "[NOT COMPATIBLE]"
  }

  STATUS_ICONS = {
    compatible:     "OK",
    warning:        "!!",
    not_compatible: "XX"
  }

  def initialize(output_path)
    @output_path = output_path
    @lines = []
  end

  def out(text = "")
    @lines << text
    puts text
  end

  def report_header
    out "=" * 72
    out "  MOD COMPATIBILITY REPORT"
    out "  Generated: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
    out "=" * 72
    out
  end

  def report_scan_info(mp_count, ebdx_count, mod_files)
    out "  Scanned 659_Multiplayer : #{mp_count} files"
    out "  Scanned 660_EBDX        : #{ebdx_count} files"
    out "  Mod files found          : #{mod_files.length}"
    out
    if mod_files.empty?
      out "  No .rb mod files found in the Mods folder."
      out "  Place your mod .rb files here and re-run."
    end
    out
  end

  def report_mod(mod_filename, results)
    out "-" * 72
    out "  MOD: #{mod_filename}"
    out "-" * 72

    if results.empty?
      out "  #{STATUS_LABELS[:compatible]} No conflicts detected."
      out
      return :compatible
    end

    worst = :compatible
    # Sort: not_compatible first, then warning
    sorted = results.sort_by { |r| r.status == :not_compatible ? 0 : (r.status == :warning ? 1 : 2) }

    sorted.each do |r|
      worst = :not_compatible if r.status == :not_compatible
      worst = :warning if r.status == :warning && worst != :not_compatible

      line_info = r.line > 0 ? " (line #{r.line})" : ""
      out "  #{STATUS_LABELS[r.status]} #{r.detail}#{line_info}"
    end
    out
    worst
  end

  def report_summary(file_statuses)
    out "=" * 72
    out "  SUMMARY"
    out "=" * 72
    out

    file_statuses.each do |filename, status|
      icon = STATUS_ICONS[status]
      label = status.to_s.upcase.gsub("_", " ")
      out "  [#{icon}] #{filename.ljust(40)} #{label}"
    end
    out
  end

  def report_guidelines
    out "=" * 72
    out "  MODDER GUIDELINES"
    out "=" * 72
    out
    out "  1. Avoid redefining methods already aliased by 659/660."
    out "     Use alias chaining instead of direct overrides."
    out
    out "  2. If you must override a method flagged [NOT COMPATIBLE],"
    out "     alias the current version first:"
    out "       alias my_mod_original_methodName methodName"
    out
    out "  3. Class reopenings flagged [WARNING] are likely OK but"
    out "     test thoroughly with multiplayer and EBDX enabled."
    out
    out "  4. New classes/modules with unique names are always safe."
    out
    out "  5. Re-run this checker after updating multiplayer or EBDX scripts."
    out
    out "=" * 72
  end

  def save
    File.write(@output_path, @lines.join("\n"), encoding: "utf-8")
    puts
    puts "  Report saved to: #{@output_path}"
  end
end

# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------
def main
  # Resolve paths relative to this script's location
  script_dir   = File.dirname(File.expand_path(__FILE__))
  project_root = File.expand_path(File.join(script_dir, ".."))
  mp_folder    = File.join(project_root, "Data", "Scripts", "659_Multiplayer")
  ebdx_folder  = File.join(project_root, "Data", "Scripts", "660_EBDX")
  mods_folder  = script_dir
  report_path  = File.join(mods_folder, "compat_report.txt")

  # Build registry from 659 + 660
  registry = Registry.new
  registry.load_folder(mp_folder)
  mp_count = Dir.exist?(mp_folder) ? Dir.glob(File.join(mp_folder, "*.rb")).length : 0

  registry.load_folder(ebdx_folder)
  ebdx_count = Dir.exist?(ebdx_folder) ? Dir.glob(File.join(ebdx_folder, "*.rb")).length : 0

  # Find mod files (exclude this script itself)
  self_name = File.basename(__FILE__)
  mod_files = Dir.glob(File.join(mods_folder, "*.rb")).sort.reject do |f|
    File.basename(f).downcase == self_name.downcase
  end

  # Report
  reporter = Reporter.new(report_path)
  reporter.report_header
  reporter.report_scan_info(mp_count, ebdx_count, mod_files)

  comparator = Comparator.new(registry)
  file_statuses = {}

  mod_files.each do |mod_file|
    mod_defs = RbParser.parse(mod_file)
    results  = comparator.check(mod_defs)
    filename = File.basename(mod_file)
    status   = reporter.report_mod(filename, results)
    file_statuses[filename] = status
  end

  if mod_files.any?
    reporter.report_summary(file_statuses)
  end

  reporter.report_guidelines
  reporter.save
end

main
