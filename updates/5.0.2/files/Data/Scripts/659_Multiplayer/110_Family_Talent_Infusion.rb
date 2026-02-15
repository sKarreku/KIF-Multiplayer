#===============================================================================
# MODULE: Family Talent & Type Infusion System
#===============================================================================
# Grants Family-based talents and type infusion for STAB moves.
# Replaces stat modifier system with ability-based bonuses.
#
# Features:
# - Each Family grants a base talent (e.g., Protean for Primordium)
# - Pokemon with matching ability get boosted version (e.g., Panmorphosis)
# - Pokemon with different ability get Family talent as ability2
# - STAB moves gain infused type from Family pool for dual-type damage
# - All calculations deterministic (coop-safe, no rand())
#===============================================================================

# Boosted abilities are defined in core ability scripts
# PANMORPHOSIS, VEILBREAKER, VOIDBORNE, SOLARBLOOM, FORTIFIEDFRAME, OVERDRIVE, COSMICBLESSING, MINDSHATTER
# These must be added to the base game's ability definitions (similar to how PROTEAN, INFILTRATOR, etc. are defined)

#===============================================================================
# Pokemon Class - Ability Assignment
#===============================================================================

class Pokemon
  # Override ability_id to inject Family talent
  alias family_talent_original_ability_id ability_id
  def ability_id
    base_ability = family_talent_original_ability_id

    if defined?(MultiplayerDebug) && has_family?
      MultiplayerDebug.info("ABILITY-ID", "=== ability_id called ===")
      MultiplayerDebug.info("ABILITY-ID", "  Pokemon: #{self.name}")
      MultiplayerDebug.info("ABILITY-ID", "  base_ability: #{base_ability}")
      MultiplayerDebug.info("ABILITY-ID", "  should_apply?: #{should_apply_family_talent?}")
    end

    return base_ability unless should_apply_family_talent?

    family_talent = PokemonFamilyConfig.get_family_talent(@family)
    return base_ability unless family_talent

    # If Pokemon's natural ability matches the family talent, use boosted version
    if base_ability == family_talent
      boosted = PokemonFamilyConfig.get_boosted_talent(@family)
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("ABILITY-ID", "  BOOSTED: #{base_ability} -> #{boosted}")
      end
      return boosted
    end

    return base_ability
  end

  # Override ability2_id to inject Family talent (when it doesn't match natural ability)
  alias family_talent_original_ability2_id ability2_id
  def ability2_id
    # Call original first (for fusion Pokemon, etc.)
    base_ability2 = family_talent_original_ability2_id
    return base_ability2 unless should_apply_family_talent?

    family_talent = PokemonFamilyConfig.get_family_talent(@family)
    return base_ability2 unless family_talent

    natural_ability = family_talent_original_ability_id

    # If natural ability already matches family talent, don't add as ability2
    # (it was converted to boosted version in ability_id)
    return nil if natural_ability == family_talent

    # Otherwise, add family talent as ability2
    return family_talent
  end

  private

  def should_apply_family_talent?
    # Check runtime Family Abilities setting first (from $PokemonSystem)
    if defined?($PokemonSystem) && $PokemonSystem && $PokemonSystem.respond_to?(:mp_family_abilities_enabled)
      return false if $PokemonSystem.mp_family_abilities_enabled == 0
    elsif defined?(PokemonFamilyConfig)
      return false unless PokemonFamilyConfig.talent_infusion_enabled?
    end

    # Check runtime Family System setting
    if defined?($PokemonSystem) && $PokemonSystem && $PokemonSystem.respond_to?(:mp_family_enabled)
      return false if $PokemonSystem.mp_family_enabled == 0
    elsif defined?(PokemonFamilyConfig)
      return false unless PokemonFamilyConfig.system_enabled?
    end

    return false unless has_family_data?  # Use has_family_data? to check raw data, not display toggle
    return true
  end
end

#===============================================================================
# Battler Class - Sync Abilities to Battle Instance
#===============================================================================

class PokeBattle_Battler
  # Hook initialization to set Family talents
  alias family_talent_original_pbInitialize pbInitialize
  def pbInitialize(pkmn, idxParty, batonPass=false)
    family_talent_original_pbInitialize(pkmn, idxParty, batonPass)

    # Sync Family talents to battler
    # Family Pokemon ALWAYS have both abilities active (natural + family talent)
    if pkmn && pkmn.respond_to?(:has_family?) && pkmn.has_family?
      @ability_id = pkmn.ability_id
      @ability2_id = pkmn.ability2_id  # Always set ability2 for family Pokemon

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("FAMILY-BATTLE", "#{pkmn.name} entered battle with dual abilities:")
        MultiplayerDebug.info("FAMILY-BATTLE", "  Ability 1: #{GameData::Ability.get(@ability_id).name}")
        MultiplayerDebug.info("FAMILY-BATTLE", "  Ability 2: #{@ability2_id ? GameData::Ability.get(@ability2_id).name : 'None'}")
      end
    end
  end

  # Attribute for Overdrive charge tracking
  attr_accessor :overdrive_charged
end

# Module loaded successfully
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("FAMILY-TALENT", "110_Family_Talent_Infusion.rb loaded - Phase 1")
  MultiplayerDebug.info("FAMILY-TALENT", "Pokemon ability hooks implemented")
  MultiplayerDebug.info("FAMILY-TALENT", "Boosted abilities registered: PANMORPHOSIS, VEILBREAKER, VOIDBORNE,")
  MultiplayerDebug.info("FAMILY-TALENT", "  SOLARBLOOM, FORTIFIEDFRAME, OVERDRIVE, COSMICBLESSING, MINDSHATTER")
end
