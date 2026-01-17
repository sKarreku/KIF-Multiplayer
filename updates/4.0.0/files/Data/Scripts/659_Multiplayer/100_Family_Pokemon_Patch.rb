#===============================================================================
# MODULE: Family/Subfamily System - Pokemon Data Model
#===============================================================================
# Adds family system attributes to Pokemon class without editing core files.
# Uses alias pattern to hook initialization and serialization methods.
#
# Adds 3 new attributes:
#   @family (0-7 or nil) - Which of the 8 families this Pokemon belongs to
#   @subfamily (0-3 or nil) - Which of the 4 subfamilies within the family
#   @family_assigned_at (timestamp or nil) - When the family was assigned
#
# Backward compatible: Existing Pokemon without family data will have nil values.
#===============================================================================

class Pokemon
  # New attributes for family system
  attr_accessor :family              # 0-7 or nil (8 families: Primordium, Vacuum, etc.)
  attr_accessor :subfamily           # 0-3 or nil (4 subfamilies per family)
  attr_accessor :family_assigned_at  # Timestamp (Time.now.to_i) or nil
  attr_accessor :pokeradar_encounter # true if caught via PokeRadar

  # Fusion-specific family storage (stores original family data for unfuse)
  attr_accessor :body_family         # Body Pokemon's original family (0-7 or nil)
  attr_accessor :body_subfamily      # Body Pokemon's original subfamily (0-3 or nil)
  attr_accessor :body_family_assigned_at  # Body Pokemon's original family timestamp
  attr_accessor :head_family         # Head Pokemon's original family (0-7 or nil)
  attr_accessor :head_subfamily      # Head Pokemon's original subfamily (0-3 or nil)
  attr_accessor :head_family_assigned_at  # Head Pokemon's original family timestamp

  # Hook initialization to add family attributes
  alias family_original_initialize initialize
  def initialize(*args)
    # Call original initialize first
    family_original_initialize(*args)

    # Initialize family attributes to nil (backward compatible)
    @family = nil
    @subfamily = nil
    @family_assigned_at = nil
    @pokeradar_encounter = false

    # Initialize fusion family storage to nil
    @body_family = nil
    @body_subfamily = nil
    @body_family_assigned_at = nil
    @head_family = nil
    @head_subfamily = nil
    @head_family_assigned_at = nil

    # Verbose debug logging
    if defined?(MultiplayerDebug)
      #MultiplayerDebug.info("FAMILY-INIT", "Pokemon initialized: #{self.name rescue 'Unknown'} | Family: #{@family.inspect}, Subfamily: #{@subfamily.inspect}")
    end
  end

  # Hook JSON serialization (for save files)
  alias family_original_as_json as_json
  def as_json(options={})
    # Get original JSON hash
    json = family_original_as_json(options)

    # Add family data to save file
    json["family"] = @family
    json["subfamily"] = @subfamily
    json["family_assigned_at"] = @family_assigned_at
    json["pokeradar_encounter"] = @pokeradar_encounter

    # Add fusion family storage
    json["body_family"] = @body_family
    json["body_subfamily"] = @body_subfamily
    json["body_family_assigned_at"] = @body_family_assigned_at
    json["head_family"] = @head_family
    json["head_subfamily"] = @head_subfamily
    json["head_family_assigned_at"] = @head_family_assigned_at

    # Verbose debug logging
    if defined?(MultiplayerDebug) && (@family || @subfamily)
      #MultiplayerDebug.info("FAMILY-SAVE", "Saving #{self.name} | Family: #{@family}, Subfamily: #{@subfamily} | Assigned: #{@family_assigned_at}")
    end

    return json
  end

  # Hook JSON deserialization (for loading save files)
  alias family_original_load_json load_json
  def load_json(jsonparse, jsonfile=nil, forcereadonly=false)
    # Call original load first
    family_original_load_json(jsonparse, jsonfile, forcereadonly)

    # Load family data from save file (defaults to nil if not present)
    @family = jsonparse['family']
    @subfamily = jsonparse['subfamily']
    @family_assigned_at = jsonparse['family_assigned_at']
    @pokeradar_encounter = jsonparse['pokeradar_encounter'] || false

    # Load fusion family storage
    @body_family = jsonparse['body_family']
    @body_subfamily = jsonparse['body_subfamily']
    @body_family_assigned_at = jsonparse['body_family_assigned_at']
    @head_family = jsonparse['head_family']
    @head_subfamily = jsonparse['head_subfamily']
    @head_family_assigned_at = jsonparse['head_family_assigned_at']

    # Verbose debug logging
    if defined?(MultiplayerDebug) && (@family || @subfamily)
      #MultiplayerDebug.info("FAMILY-LOAD", "Loaded #{self.name} | Family: #{@family}, Subfamily: #{@subfamily} | Assigned: #{@family_assigned_at}")
    end
  end

  # Helper method to check if this Pokemon has a family assigned
  # Respects the runtime Family System toggle from Multiplayer Options
  def has_family?
    # Check runtime setting first (from $PokemonSystem), then fall back to config
    if defined?($PokemonSystem) && $PokemonSystem && $PokemonSystem.respond_to?(:mp_family_enabled)
      return false if $PokemonSystem.mp_family_enabled == 0
    elsif defined?(PokemonFamilyConfig)
      return false unless PokemonFamilyConfig.system_enabled?
    end
    return !@family.nil? && !@subfamily.nil?
  end

  # Helper to check if this Pokemon has family data stored (ignores toggle)
  # Used for checking if family exists regardless of display setting
  def has_family_data?
    return !@family.nil? && !@subfamily.nil?
  end
end

# Module loaded successfully
if defined?(MultiplayerDebug)
  #MultiplayerDebug.info("FAMILY-MODULE", "=" * 60)
  #MultiplayerDebug.info("FAMILY-MODULE", "100_Family_Pokemon_Patch.rb loaded successfully")
  #MultiplayerDebug.info("FAMILY-MODULE", "Pokemon class extended with family attributes")
  #MultiplayerDebug.info("FAMILY-MODULE", "Attributes: @family, @subfamily, @family_assigned_at")
  #MultiplayerDebug.info("FAMILY-MODULE", "=" * 60)
end
