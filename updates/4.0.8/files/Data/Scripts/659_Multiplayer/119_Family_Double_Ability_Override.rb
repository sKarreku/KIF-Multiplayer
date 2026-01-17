#===============================================================================
# MODULE: Family/Subfamily System - Double Ability Override
#===============================================================================
# Overrides ability2 getters to work for Family Pokemon without requiring
# SWITCH_DOUBLE_ABILITIES game switch.
#
# Family Pokemon should ALWAYS have both abilities active, regardless of
# the double abilities switch state.
#===============================================================================

#===============================================================================
# Helper method to check if Family Abilities are enabled
#===============================================================================
def family_abilities_enabled?
  # Check runtime Family Abilities setting first (from $PokemonSystem)
  if defined?($PokemonSystem) && $PokemonSystem && $PokemonSystem.respond_to?(:mp_family_abilities_enabled)
    return $PokemonSystem.mp_family_abilities_enabled != 0
  elsif defined?(PokemonFamilyConfig)
    return PokemonFamilyConfig.talent_infusion_enabled?
  end
  return true  # Default to enabled if no setting found
end

#===============================================================================
# Pokemon Class - ability2 getter override
#===============================================================================
class Pokemon
  # Override ability2 to work for Family Pokemon without switch requirement
  alias family_double_ability_original_ability2 ability2
  def ability2
    # If this is a Family Pokemon AND abilities are enabled, return ability2 (bypass switch check)
    if self.respond_to?(:has_family?) && self.has_family? && family_abilities_enabled?
      return GameData::Ability.try_get(ability2_id())
    end

    # Otherwise, use original implementation (requires SWITCH_DOUBLE_ABILITIES)
    return family_double_ability_original_ability2
  end
end

#===============================================================================
# Battler Class - ability2 getter and battle display override
#===============================================================================
class PokeBattle_Battler
  # Override ability2 to work for Family Pokemon without switch requirement
  alias family_double_ability_original_ability2 ability2
  def ability2
    # If this battler's Pokemon has a family AND abilities enabled, return ability2 (bypass switch check)
    if @ability2_id
      pkmn = self.pokemon rescue nil
      if pkmn && pkmn.respond_to?(:has_family?) && pkmn.has_family? && family_abilities_enabled?
        return GameData::Ability.try_get(@ability2_id)
      end
    end

    # Otherwise, use original implementation (requires SWITCH_DOUBLE_ABILITIES)
    return family_double_ability_original_ability2
  end

  # Override hasActiveAbility to check ability2 for Family Pokemon
  alias family_double_ability_original_hasActiveAbility hasActiveAbility?
  def hasActiveAbility?(check_ability, ignore_fainted = false, mold_broken = false)
    # For Family Pokemon with abilities enabled, check both abilities
    pkmn = self.pokemon rescue nil
    if pkmn && pkmn.respond_to?(:has_family?) && pkmn.has_family? && family_abilities_enabled? && @ability2_id
      return false if !abilityActive?(ignore_fainted)
      if check_ability.is_a?(Array)
        return check_ability.include?(@ability_id) || check_ability.include?(@ability2_id)
      end
      return self.ability == check_ability || self.ability2 == check_ability
    end

    # Otherwise, use original implementation
    return family_double_ability_original_hasActiveAbility(check_ability, ignore_fainted, mold_broken)
  end

  # Override pbEffectsOnSwitchIn to trigger ability2 for Family Pokemon
  alias family_double_ability_original_pbEffectsOnSwitchIn pbEffectsOnSwitchIn
  def pbEffectsOnSwitchIn(switchIn=false)
    # Call original first
    family_double_ability_original_pbEffectsOnSwitchIn(switchIn)

    # Trigger ability2 for Family Pokemon (if abilities enabled)
    pkmn = self.pokemon rescue nil
    if pkmn && pkmn.respond_to?(:has_family?) && pkmn.has_family? && family_abilities_enabled? && @ability2_id
      # Trigger ability2 switch-in handler if it exists
      if (!fainted? && unstoppableAbility?) || abilityActive?
        # Mark that ability2 is about to trigger (for splash display)
        @triggering_ability2 = true

        BattleHandlers.triggerAbilityOnSwitchIn(self.ability2,self,@battle) if self.ability2

        # Clear flag after trigger
        @triggering_ability2 = false

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("FAMILY-BATTLE", "Triggered ability2 switch-in for #{pkmn.name}: #{self.ability2.name}")
        end
      end
    end
  end

  # Attribute accessor for ability2 trigger flag
  attr_accessor :triggering_ability2
end

#===============================================================================
# Battler Class - Override abilityName for ability2 triggers
#===============================================================================

class PokeBattle_Battler
  # Override abilityName to return ability2 name when ability2 is triggering
  alias family_double_ability_original_abilityName abilityName
  def abilityName
    # If ability2 is currently triggering, return ability2 name instead
    if @triggering_ability2 && self.ability2
      return self.ability2.name
    end

    # Otherwise, return original ability name
    return family_double_ability_original_abilityName
  end
end

#-------------------------------------------------------------------------------
# Module loaded successfully
#-------------------------------------------------------------------------------
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("FAMILY-DOUBLE-ABILITY", "=" * 60)
  MultiplayerDebug.info("FAMILY-DOUBLE-ABILITY", "119_Family_Double_Ability_Override.rb loaded successfully")
  MultiplayerDebug.info("FAMILY-DOUBLE-ABILITY", "Family Pokemon will have ability2 without SWITCH_DOUBLE_ABILITIES")
  MultiplayerDebug.info("FAMILY-DOUBLE-ABILITY", "=" * 60)
end
