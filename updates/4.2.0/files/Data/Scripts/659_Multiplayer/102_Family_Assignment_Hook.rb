#===============================================================================
# MODULE: Family/Subfamily System - Capture Hook
#===============================================================================
# Hooks pbRecordAndStoreCaughtPokemon to assign family to newly-caught shinies.
# Uses deterministic RNG based on personalID (no rand() calls - no battle RNG interference).
#
# Assignment Logic:
#   1. Only applies to shiny Pokemon (natural or fakeshiny)
#   2. 1% chance based on personalID % 100 (or 100% in testing mode)
#   3. Family/subfamily selection uses personalID bit-shifting (deterministic)
#
# RNG-Free Approach:
#   - 1% chance: personalID % 100 < 1
#   - Family (0-7): (personalID >> 8) % 8
#   - Subfamily (0-3): (personalID >> 16) % 4
#===============================================================================

class PokeBattle_Battle
  # Hook pbRecordAndStoreCaughtPokemon to assign family before vanilla processing
  alias family_original_pbRecordAndStoreCaughtPokemon pbRecordAndStoreCaughtPokemon

  def pbRecordAndStoreCaughtPokemon
    # Apply family to caught shinies BEFORE original processing
    if defined?(MultiplayerDebug)
      #MultiplayerDebug.info("FAMILY-CAPTURE", "Processing #{@caughtPokemon.length} caught Pokemon for family assignment")
    end

    @caughtPokemon.each do |pkmn|
      pbAssignFamilyToNewlyCaughtShiny(pkmn)
    end

    # Call original method (vanilla Pokemon capture processing)
    family_original_pbRecordAndStoreCaughtPokemon
  end

  # Assign family to a newly-caught shiny Pokemon
  # Uses deterministic selection based on personalID (no battle RNG interference)
  def pbAssignFamilyToNewlyCaughtShiny(pkmn)
    # Check if family system is enabled (runtime setting first, then config)
    if defined?($PokemonSystem) && $PokemonSystem && $PokemonSystem.respond_to?(:mp_family_enabled)
      return if $PokemonSystem.mp_family_enabled == 0
    elsif defined?(PokemonFamilyConfig)
      return unless PokemonFamilyConfig.system_enabled?
    end

    # Don't assign family to PokeRadar shinies
    if pkmn.pokeradar_encounter
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("FAMILY-ASSIGN", "#{pkmn.name} is from PokeRadar - skipping family assignment")
      end
      return
    end

    # Only assign to shiny Pokemon
    unless pkmn.shiny? || pkmn.fakeshiny?
      if defined?(MultiplayerDebug)
        #MultiplayerDebug.info("FAMILY-ASSIGN", "#{pkmn.name} is not shiny - skipping family assignment")
      end
      return
    end

    # Skip if already assigned (shouldn't happen, but safety check)
    if pkmn.family
      if defined?(MultiplayerDebug)
        #MultiplayerDebug.info("FAMILY-ASSIGN", "#{pkmn.name} already has family #{pkmn.family} - skipping")
      end
      return
    end

    # Use personalID for deterministic "random" selection (no battle RNG interference)
    # Testing mode: always assign, Normal mode: chance based on personalID
    if PokemonFamilyConfig::FORCE_FAMILY_ASSIGNMENT
      # Force assignment in testing mode
      should_assign = true
      if defined?(MultiplayerDebug)
        #MultiplayerDebug.info("FAMILY-ASSIGN", "Testing mode enabled - forcing family assignment for #{pkmn.name}")
      end
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
      seed_for_chance = pkmn.personalID % 100
      threshold = (assignment_chance * 100).round
      should_assign = (seed_for_chance < threshold)

      if defined?(MultiplayerDebug)
        #MultiplayerDebug.info("FAMILY-ASSIGN", "#{pkmn.name} #{threshold}% check: personalID=#{pkmn.personalID}, seed=#{seed_for_chance}, assign=#{should_assign}")
      end
    end

    return unless should_assign

    # Deterministic weighted family selection using personalID
    pkmn.family = select_weighted_family(pkmn.personalID)
    # Deterministic weighted subfamily selection
    pkmn.subfamily = select_weighted_subfamily(pkmn.family, pkmn.personalID)
    pkmn.family_assigned_at = Time.now.to_i

    # Verbose debug logging
    if defined?(MultiplayerDebug)
      family_name = PokemonFamilyConfig.get_full_name(pkmn.family, pkmn.subfamily)
      #MultiplayerDebug.info("FAMILY-ASSIGN", "=" * 60)
      #MultiplayerDebug.info("FAMILY-ASSIGN", "✨ FAMILY ASSIGNED! ✨")
      #MultiplayerDebug.info("FAMILY-ASSIGN", "Pokemon: #{pkmn.name}")
      #MultiplayerDebug.info("FAMILY-ASSIGN", "PersonalID: #{pkmn.personalID}")
      #MultiplayerDebug.info("FAMILY-ASSIGN", "Family: #{pkmn.family} (#{PokemonFamilyConfig::FAMILIES[pkmn.family][:name]})")
      #MultiplayerDebug.info("FAMILY-ASSIGN", "Subfamily: #{pkmn.subfamily} (#{PokemonFamilyConfig::SUBFAMILIES[pkmn.family * 4 + pkmn.subfamily][:name]})")
      #MultiplayerDebug.info("FAMILY-ASSIGN", "Full Name: #{family_name}")
      #MultiplayerDebug.info("FAMILY-ASSIGN", "Font: #{PokemonFamilyConfig.get_family_font(pkmn.family)}")
      #MultiplayerDebug.info("FAMILY-ASSIGN", "Effect: #{PokemonFamilyConfig.get_family_effect(pkmn.family)}")
      #MultiplayerDebug.info("FAMILY-ASSIGN", "Colors: #{PokemonFamilyConfig.get_subfamily_colors(pkmn.family, pkmn.subfamily).inspect}")
      #MultiplayerDebug.info("FAMILY-ASSIGN", "=" * 60)
    end
  end

  # Select family using weighted random based on personalID
  def select_weighted_family(personal_id)
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
  def select_weighted_subfamily(family, personal_id)
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

# Module loaded successfully
if defined?(MultiplayerDebug)
  #MultiplayerDebug.info("FAMILY-CAPTURE", "=" * 60)
  #MultiplayerDebug.info("FAMILY-CAPTURE", "102_Family_Assignment_Hook.rb loaded successfully")
  #MultiplayerDebug.info("FAMILY-CAPTURE", "Hooked pbRecordAndStoreCaughtPokemon for family assignment")
  #MultiplayerDebug.info("FAMILY-CAPTURE", "1% chance for shinies (deterministic via personalID)")
  #MultiplayerDebug.info("FAMILY-CAPTURE", "No rand() calls - no battle RNG interference")
  #MultiplayerDebug.info("FAMILY-CAPTURE", "=" * 60)
end
