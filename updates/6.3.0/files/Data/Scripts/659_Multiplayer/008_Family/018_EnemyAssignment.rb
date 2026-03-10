#===============================================================================
# MODULE: Family/Subfamily System - Enemy Pokemon Assignment
#===============================================================================
# Assigns family to wild and trainer Pokemon so they display with outlines/fonts
# in battle, just like player Pokemon.
#
# Assignment Logic:
#   - Applies to ALL shiny enemy Pokemon (wild + trainer)
#   - Same 1% chance as capture hook (deterministic via personalID)
#   - Assignment happens at Pokemon initialization, before battle starts
#===============================================================================

#===============================================================================
# Pokemon Class - Family Assignment Methods
#===============================================================================

class Pokemon
  # Assign family to shiny Pokemon (called after Pokemon is fully created)
  def pbAssignFamilyIfShiny
    # Check if family system is enabled (runtime setting first, then config)
    if defined?($PokemonSystem) && $PokemonSystem && $PokemonSystem.respond_to?(:mp_family_enabled)
      return if $PokemonSystem.mp_family_enabled == 0
    elsif defined?(PokemonFamilyConfig)
      return unless PokemonFamilyConfig.system_enabled?
    end

    # Only assign to shiny Pokemon
    return unless self.shiny? || self.fakeshiny?

    # Skip if already assigned
    return if self.family

    # Don't assign family to PokeRadar shinies
    if self.pokeradar_encounter
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("FAMILY-ENEMY", "#{self.name} is from PokeRadar - skipping family assignment")
      end
      return
    end

    # Use personalID for deterministic "random" selection
    if PokemonFamilyConfig::FORCE_FAMILY_ASSIGNMENT
      # Force assignment in testing mode
      should_assign = true
    else
      # Check runtime setting first (from $PokemonSystem), then fall back to config
      assignment_chance = 0.01  # Default 1%
      if defined?($PokemonSystem) && $PokemonSystem && $PokemonSystem.respond_to?(:mp_family_rate)
        rate = $PokemonSystem.mp_family_rate || 1
        assignment_chance = rate / 100.0
      elsif defined?(PokemonFamilyConfig) && PokemonFamilyConfig.respond_to?(:get_assignment_chance)
        assignment_chance = PokemonFamilyConfig.get_assignment_chance
      end

      # Deterministic chance check using personalID (range 0-99)
      seed_for_chance = self.personalID % 100
      threshold = (assignment_chance * 100).round
      should_assign = (seed_for_chance < threshold)
    end

    return unless should_assign

    # Deterministic weighted family selection using personalID
    self.family = select_weighted_family_from_pid(self.personalID)
    # Deterministic weighted subfamily selection
    self.subfamily = select_weighted_subfamily_from_pid(self.family, self.personalID)
    self.family_assigned_at = Time.now.to_i

    if defined?(MultiplayerDebug)
      family_name = PokemonFamilyConfig.get_full_name(self.family, self.subfamily)
      MultiplayerDebug.info("FAMILY-ENEMY", "Assigned #{family_name} to enemy #{self.name}")
    end
  end

  # Select family using weighted random based on personalID
  def select_weighted_family_from_pid(personal_id)
    weights = PokemonFamilyConfig::FAMILIES.values.map { |f| f[:weight] }
    total_weight = weights.sum
    roll = (personal_id >> 8) % total_weight

    cumulative = 0
    PokemonFamilyConfig::FAMILIES.each do |id, data|
      cumulative += data[:weight]
      return id if roll < cumulative
    end
    return 0  # Fallback
  end

  # Select subfamily using weighted random based on personalID
  def select_weighted_subfamily_from_pid(family, personal_id)
    # Get the 4 subfamilies for this family (family * 4 + 0..3)
    base_idx = family * 4
    subfamily_data = (0..3).map { |i| PokemonFamilyConfig::SUBFAMILIES[base_idx + i] }
    weights = subfamily_data.map { |s| s[:weight] }
    total_weight = weights.sum
    roll = (personal_id >> 16) % total_weight

    cumulative = 0
    weights.each_with_index do |weight, idx|
      cumulative += weight
      return idx if roll < cumulative
    end
    return 0  # Fallback
  end
end

#===============================================================================
# Event Handler - Assign Family to Wild Pokemon
#===============================================================================

# Hook wild Pokemon creation to assign family (after Shiny Charm processing)
Events.onWildPokemonCreate += proc { |_sender, e|
  begin
    pokemon = e[0]
    next if !pokemon
    # Assign family to shiny wild Pokemon
    pokemon.pbAssignFamilyIfShiny if pokemon.respond_to?(:pbAssignFamilyIfShiny)
  rescue => err
    # Never crash the encounter system
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("FAMILY-ENEMY", "Error in enemy assignment hook: #{err.message}")
    end
  end
}

#-------------------------------------------------------------------------------
# Module loaded successfully
#-------------------------------------------------------------------------------
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("FAMILY-ENEMY", "=" * 60)
  MultiplayerDebug.info("FAMILY-ENEMY", "120_Family_Enemy_Assignment.rb loaded successfully")
  MultiplayerDebug.info("FAMILY-ENEMY", "Wild Pokemon will show family outlines/fonts via Events.onWildPokemonCreate")
  MultiplayerDebug.info("FAMILY-ENEMY", "Assignment happens after Pokemon creation (deterministic)")
  MultiplayerDebug.info("FAMILY-ENEMY", "=" * 60)
end
