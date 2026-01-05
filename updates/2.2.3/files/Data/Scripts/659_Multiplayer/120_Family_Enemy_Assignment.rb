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
    # Check if family system is enabled
    return unless PokemonFamilyConfig::FAMILY_SYSTEM_ENABLED

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
      # Deterministic 1% check using personalID (range 0-99, assign if <1)
      seed_for_chance = self.personalID % 100
      should_assign = (seed_for_chance < 1)
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
  pokemon = e[0]
  # Assign family to shiny wild Pokemon
  pokemon.pbAssignFamilyIfShiny if pokemon.respond_to?(:pbAssignFamilyIfShiny)
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
