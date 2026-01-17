#===============================================================================
# MODULE: Family/Subfamily System - Configuration
#===============================================================================
# Central configuration for the 8 families and 32 subfamilies.
# Contains font mappings, effect types, and color palettes.
#
# Structure:
#   - 8 Families (Primordium, Vacuum, Astrum, Silva, Machina, Humanitas, Aetheris, Infernum)
#   - Each family has 4 subfamilies (32 total combinations)
#   - Each family has a unique font and outline effect
#   - Each subfamily has a 5-color gradient palette
#===============================================================================

module PokemonFamilyConfig
  # Global toggle to enable/disable entire Family system
  FAMILY_SYSTEM_ENABLED = true      # Set to false to disable all family features

  # Global toggle for talent and type infusion system (disabled by default)
  ENABLE_TALENT_INFUSION = true    # Set to true to enable Family talents + type infusion

  FORCE_ALL_SHINY = false           # Force all wild Pokemon to be shiny
  FORCE_FAMILY_ASSIGNMENT = false   # Force all shinies to get family (100% chance)
  FAMILY_ASSIGNMENT_CHANCE = 0.01   # Normal mode: 1% chance for shinies to get family

  #=============================================================================
  # Runtime toggles (can be changed via Multiplayer Options menu)
  # These override the constants above when set
  #=============================================================================
  class << self
    attr_accessor :runtime_system_enabled
    attr_accessor :runtime_talent_infusion_enabled
    attr_accessor :runtime_assignment_chance
    attr_accessor :runtime_font_enabled
  end

  # Initialize runtime values from constants (happens once at load)
  @runtime_system_enabled = nil  # nil means use constant
  @runtime_talent_infusion_enabled = nil
  @runtime_assignment_chance = nil
  @runtime_font_enabled = nil

  # Setters for Multiplayer Options menu
  def self.set_system_enabled(value)
    @runtime_system_enabled = value
  end

  def self.set_talent_infusion_enabled(value)
    @runtime_talent_infusion_enabled = value
  end

  def self.set_assignment_chance(value)
    @runtime_assignment_chance = value
  end

  def self.set_font_enabled(value)
    @runtime_font_enabled = value
  end

  # Getters that check runtime value first, then fall back to constant
  def self.system_enabled?
    return @runtime_system_enabled unless @runtime_system_enabled.nil?
    FAMILY_SYSTEM_ENABLED
  end

  def self.talent_infusion_enabled?
    return @runtime_talent_infusion_enabled unless @runtime_talent_infusion_enabled.nil?
    ENABLE_TALENT_INFUSION
  end

  def self.get_assignment_chance
    return @runtime_assignment_chance unless @runtime_assignment_chance.nil?
    FAMILY_ASSIGNMENT_CHANCE
  end

  def self.font_enabled?
    return @runtime_font_enabled unless @runtime_font_enabled.nil?
    true  # Default: fonts enabled
  end

  # 8 Families with font + effect mapping + rarity weights
  # Font names MUST match internal font family names (not filenames)
  # Primordium: 1% chance, Other 7: ~14.14% each (99% total)
  FAMILIES = {
    0 => { name: "Primordium", font_name: "Dovahkiin", effect: :inner_glow_pulse, weight: 1 },
    1 => { name: "Vacuum",     font_name: "Over There",  effect: :flicker_static, weight: 14 },
    2 => { name: "Astrum",     font_name: "Galactic", effect: :twinkling_stars, weight: 14 },
    3 => { name: "Silva",      font_name: "GREEN NATURE", effect: :bioluminescent, weight: 14 },
    4 => { name: "Machina",    font_name: "Origin Tech Demo", effect: :neon_circuit, weight: 14 },
    5 => { name: "Humanitas",  font_name: "Hypik",      effect: :parchment_shadow, weight: 14 },
    6 => { name: "Aetheris",   font_name: "Ancient God", effect: :pulsing_light, weight: 14 },
    7 => { name: "Infernum",   font_name: "God Hells Demo", effect: :flickering_flame, weight: 15 }
  }
  # Total: 1 + 14*6 + 15 = 100 (Primordium 1%, others ~14% each)

  # Family Talent Assignments
  # Each family grants a base talent, with boosted versions for matching Pokemon
  FAMILY_TALENTS = {
    0 => { base: :PROTEAN,      boosted: :PANMORPHOSIS },      # Primordium
    1 => { base: :INFILTRATOR,  boosted: :VEILBREAKER },       # Vacuum
    2 => { base: :LEVITATE,     boosted: :VOIDBORNE },         # Astrum
    3 => { base: :REGENERATOR,  boosted: :VITALREBIRTH },      # Silva
    4 => { base: :STURDY,       boosted: :IMMOVABLE },         # Machina
    5 => { base: :MOLDBREAKER,  boosted: :INDOMITABLE },       # Humanitas
    6 => { base: :SERENEGRACE,  boosted: :COSMICBLESSING },    # Aetheris
    7 => { base: :INTIMIDATE,   boosted: :MINDSHATTER }        # Infernum
  }

  # Family Type Pools (for type infusion)
  # Types are ordered by priority for effectiveness comparison
  FAMILY_TYPES = {
    0 => [:PSYCHIC, :FAIRY],                      # Primordium
    1 => [:GHOST, :POISON],                       # Vacuum
    2 => [:DRAGON, :ROCK],                        # Astrum
    3 => [:GRASS, :ICE, :BUG],                    # Silva
    4 => [:STEEL, :ELECTRIC],                     # Machina
    5 => [:NORMAL, :FIGHTING, :GROUND],           # Humanitas
    6 => [:FLYING, :WATER],                       # Aetheris
    7 => [:FIRE, :DARK]                           # Infernum
  }

  # 32 Subfamilies with 5-color gradients + rarity weights
  # Index calculation: family * 4 + local_subfamily (0-3)
  # Example: Primordium Genesis = 0*4 + 0 = 0, Vacuum Silentium = 1*4 + 0 = 4
  # Genesis & Cataclysmus: 1% each within Primordium, Protoflame & Echovoid: 49% each
  SUBFAMILIES = {
    # Primordium (Family 0) - Genesis & Cataclysmus are rare (1% each)
    0 => { name: "Genesis",      colors: ["#FFFFFF", "#FFFACD", "#FFEFD5", "#FAF0E6", "#FFFFF0"], weight: 1 },
    1 => { name: "Cataclysmus",  colors: ["#FF4500", "#8B0000", "#800000", "#FF6347", "#A52A2A"], weight: 1 },
    2 => { name: "Protoflame",   colors: ["#FFA500", "#FFD700", "#FF8C00", "#FFE4B5", "#FFFACD"], weight: 49 },
    3 => { name: "Echovoid",     colors: ["#E0FFFF", "#B0E0E6", "#AFEEEE", "#5F9EA0", "#4682B4"], weight: 49 },

    # Vacuum (Family 1) - Equal weights
    4 => { name: "Silentium",    colors: ["#E0E0E0", "#C0C0C0", "#A9A9A9", "#808080", "#4B4B4B"], weight: 25 },
    5 => { name: "Paradoxum",    colors: ["#FF00FF", "#00FF00", "#FF1493", "#7FFF00", "#8B008B"], weight: 25 },
    6 => { name: "Nullus",       colors: ["#000000", "#111111", "#222222", "#333333", "#444444"], weight: 25 },
    7 => { name: "Susurrus",     colors: ["#4B0082", "#2F4F4F", "#483D8B", "#191970", "#6A5ACD"], weight: 25 },

    # Astrum (Family 2) - Equal weights
    8 => { name: "Stella",       colors: ["#FFD700", "#FFFACD", "#F0E68C", "#FFF8DC", "#FFFFE0"], weight: 25 },
    9 => { name: "Nebulae",      colors: ["#FF00FF", "#800080", "#8B008B", "#4B0082", "#9400D3"], weight: 25 },
    10 => { name: "Solaria",     colors: ["#FFA500", "#FFD700", "#FF8C00", "#FFE4B5", "#FFFACD"], weight: 25 },
    11 => { name: "Cometa",      colors: ["#ADD8E6", "#B0E0E6", "#87CEFA", "#4682B4", "#5F9EA0"], weight: 25 },

    # Silva (Family 3) - Equal weights
    12 => { name: "Vernalis",    colors: ["#228B22", "#32CD32", "#ADFF2F", "#7CFC00", "#00FF7F"], weight: 25 },
    13 => { name: "Radix",       colors: ["#013220", "#006400", "#228B22", "#2E8B57", "#556B2F"], weight: 25 },
    14 => { name: "Autumnus",    colors: ["#FF8C00", "#FF4500", "#A0522D", "#D2691E", "#8B4513"], weight: 25 },
    15 => { name: "Floralis",    colors: ["#FFB6C1", "#FFC0CB", "#FFDAB9", "#FFF0F5", "#FFE4E1"], weight: 25 },

    # Machina (Family 4) - Equal weights
    16 => { name: "Ferrum",      colors: ["#B0C4DE", "#4682B4", "#5F9EA0", "#2F4F4F", "#D3D3D3"], weight: 25 },
    17 => { name: "Cruciamentum", colors: ["#FF00FF", "#00FF00", "#8B008B", "#006400", "#000000"], weight: 25 },
    18 => { name: "Neonis",      colors: ["#00FFFF", "#00CED1", "#008B8B", "#20B2AA", "#5F9EA0"], weight: 25 },
    19 => { name: "Quantum",     colors: ["#E0FFFF", "#F0FFFF", "#AFEEEE", "#B0E0E6", "#00CED1"], weight: 25 },

    # Humanitas (Family 5) - Equal weights
    20 => { name: "Civitas",     colors: ["#708090", "#2F4F4F", "#4682B4", "#B0C4DE", "#D3D3D3"], weight: 25 },
    21 => { name: "Bellator",    colors: ["#8B0000", "#A52A2A", "#B22222", "#5C0000", "#800000"], weight: 25 },
    22 => { name: "Mercator",    colors: ["#A0522D", "#8B4513", "#CD853F", "#D2B48C", "#F4A460"], weight: 25 },
    23 => { name: "Sapientia",   colors: ["#000000", "#4B4B4B", "#808080", "#A9A9A9", "#C0C0C0"], weight: 25 },

    # Aetheris (Family 6) - Equal weights
    24 => { name: "Angelus",     colors: ["#FFFACD", "#FFD700", "#F0E68C", "#FAFAD2", "#FFF5EE"], weight: 25 },
    25 => { name: "Discordia",   colors: ["#FFF8DC", "#FFFFE0", "#FFD700", "#FFF0F5", "#FFFAF0"], weight: 25 },
    26 => { name: "Caelitus",    colors: ["#87CEEB", "#B0E0E6", "#E0FFFF", "#ADD8E6", "#F0FFFF"], weight: 25 },
    27 => { name: "Luminaris",   colors: ["#FFE4E1", "#FFFACD", "#F5F5DC", "#FFFFE0", "#FFF0F5"], weight: 25 },

    # Infernum (Family 7) - Equal weights
    28 => { name: "Fulgur",      colors: ["#FFD700", "#FF4500", "#8B0000", "#FF8C00", "#FFF5E1"], weight: 25 },
    29 => { name: "Abaddon",     colors: ["#8B0000", "#4B0101", "#FF2400", "#330000", "#FF6347"], weight: 25 },
    30 => { name: "Cinis",       colors: ["#2F2F2F", "#8B4513", "#D2691E", "#A0522D", "#F4A460"], weight: 25 },
    31 => { name: "Gehennus",    colors: ["#FF4500", "#8B0000", "#330000", "#FF8C00", "#000000"], weight: 25 }
  }

  # Get global subfamily index from family + local subfamily
  # Example: Primordium (0) + Cataclysmus (1) = 0*4 + 1 = 1
  def self.get_subfamily_index(family, local_subfamily)
    return family * 4 + local_subfamily
  end

  # Get full name: "Primordium Genesis", "Vacuum Silentium", etc.
  def self.get_full_name(family, local_subfamily)
    subfamily_idx = get_subfamily_index(family, local_subfamily)
    return "#{FAMILIES[family][:name]} #{SUBFAMILIES[subfamily_idx][:name]}"
  end

  # Get font name for a family (0-7)
  def self.get_family_font(family)
    return FAMILIES[family][:font_name]
  end

  # Get effect type for a family (0-7)
  # Returns symbol: :inner_glow_pulse, :flicker_static, etc.
  def self.get_family_effect(family)
    return FAMILIES[family][:effect]
  end

  # Get color palette for a subfamily (family 0-7, local_subfamily 0-3)
  # Returns array of 5 hex color strings
  def self.get_subfamily_colors(family, local_subfamily)
    subfamily_idx = get_subfamily_index(family, local_subfamily)
    return SUBFAMILIES[subfamily_idx][:colors]
  end

  # Convert hex color string to Color object
  # Example: "#FF4500" -> Color.new(255, 69, 0)
  def self.hex_to_color(hex)
    hex = hex.gsub("#", "")
    r = hex[0..1].to_i(16)
    g = hex[2..3].to_i(16)
    b = hex[4..5].to_i(16)
    return Color.new(r, g, b)
  rescue => e
    if defined?(MultiplayerDebug)
      #MultiplayerDebug.error("FAMILY-CONFIG", "Failed to convert hex color #{hex.inspect}: #{e.message}")
    end
    return Color.new(255, 255, 255)  # Fallback to white
  end

  # Get base talent for a family (0-7)
  def self.get_family_talent(family)
    return nil unless FAMILY_TALENTS[family]
    return FAMILY_TALENTS[family][:base]
  end

  # Get boosted talent for a family (0-7)
  def self.get_boosted_talent(family)
    return nil unless FAMILY_TALENTS[family]
    return FAMILY_TALENTS[family][:boosted]
  end

  # Get type pool for a family (0-7)
  def self.get_family_types(family)
    return FAMILY_TYPES[family] || []
  end

  # Check if an ability is a family talent (base or boosted)
  def self.is_family_talent?(ability_id)
    return false unless ability_id
    FAMILY_TALENTS.values.each do |talent_data|
      return true if talent_data[:base] == ability_id || talent_data[:boosted] == ability_id
    end
    return false
  end
end

# Register custom fonts with the game engine on module load
# Font files use family names in config, but filenames were renamed
# Map internal font names to actual file names:
FONT_FILE_MAP = {
  "Dovahkiin" => "Primordium",
  "AIFragment" => "Vacuum",
  "Galactic Bold" => "Astrum",
  "GREEN NATURE" => "Silva",
  "Hyper heliX" => "Machina",
  "Oups" => "Humanitas",
  "Heavy Gothik" => "Aetheris",
  "Hellgrazer" => "Infernum"
}

# Save original default font before registering family fonts
ORIGINAL_DEFAULT_FONT = Font.default_name.is_a?(Array) ? Font.default_name.first : Font.default_name

# DO NOT register family fonts in Font.default_name - causes chat to use family fonts
# Family fonts are ONLY applied via MessageConfig.pbSetSystemFontName() in summary screen
# Summary screen saves/restores global font to prevent contamination

if defined?(MultiplayerDebug)
  PokemonFamilyConfig::FAMILIES.each do |family_id, family_data|
    font_name = family_data[:font_name]
    file_name = FONT_FILE_MAP[font_name] || font_name
    font_path_ttf = "Fonts/#{file_name}.ttf"
    font_path_otf = "Fonts/#{file_name}.otf"

    if File.exist?(font_path_ttf) || File.exist?(font_path_otf)
      #MultiplayerDebug.info("FAMILY-CONFIG", "Found font file: #{file_name} (internal name: #{font_name})")
    else
      #MultiplayerDebug.warn("FAMILY-CONFIG", "Missing font: #{file_name}")
    end
  end
end

# DO NOT set default font here - Fontif will override it during Scene_Intro
# Instead, rely on Fontif to manage global font (it already has the correct default)
# Family fonts are only applied temporarily in summary screen via pbStartScene/pbEndScene

if defined?(MultiplayerDebug)
  #MultiplayerDebug.info("FAMILY-CONFIG", "Family fonts NOT registered in Font.default_name")
  #MultiplayerDebug.info("FAMILY-CONFIG", "Fonts applied ONLY via MessageConfig in summary screen")
  #MultiplayerDebug.info("FAMILY-CONFIG", "Chat will use default font (no contamination)")
end

# Module loaded successfully
if defined?(MultiplayerDebug)
  #MultiplayerDebug.info("FAMILY-CONFIG", "=" * 60)
  #MultiplayerDebug.info("FAMILY-CONFIG", "101_Family_Config.rb loaded successfully")
  #MultiplayerDebug.info("FAMILY-CONFIG", "8 Families defined: #{PokemonFamilyConfig::FAMILIES.values.map { |f| f[:name] }.join(', ')}")
  #MultiplayerDebug.info("FAMILY-CONFIG", "32 Subfamilies defined with color palettes")
  #MultiplayerDebug.info("FAMILY-CONFIG", "Font files expected in: Fonts/Primordium.ttf (or .otf), etc.")
  #MultiplayerDebug.info("FAMILY-CONFIG", "=" * 60)
end
