#===============================================================================
# MODULE: Family Talent Edge Case Handlers
#===============================================================================
# Handles edge cases for Family talents:
# - Skill Swap / Role Play (prevent swapping boosted talents)
# - Trace / Receiver (copy base talent instead of boosted)
# - Mold Breaker (boosted talents can still be negated)
#===============================================================================

#===============================================================================
# Skill Swap - Prevent swapping Family talents
#===============================================================================

# Find Skill Swap move class
if defined?(PokeBattle_Move)
  # Skill Swap is typically function code 05D or similar
  # Hook the generic move failure check
  class PokeBattle_Move
    alias family_talent_original_pbMoveFailed? pbMoveFailed? if method_defined?(:pbMoveFailed?)

    def pbMoveFailed?(user, targets)
      # Check if this is Skill Swap
      if @function == "05D" || self.class.name.include?("SkillSwap")
        targets.each do |target|
          # Prevent swapping if either Pokemon has a Family talent
          if PokemonFamilyConfig.is_family_talent?(user.ability_id) ||
             PokemonFamilyConfig.is_family_talent?(target.ability_id)
            @battle.pbDisplay(_INTL("But it failed!"))
            return true
          end
        end
      end

      return family_talent_original_pbMoveFailed?(user, targets) if defined?(family_talent_original_pbMoveFailed?)
      return false
    end
  end
end

#===============================================================================
# Trace - Copy base talent instead of boosted
#===============================================================================

class PokeBattle_Battler
  alias family_talent_original_pbContinualAbilityChecks pbContinualAbilityChecks if method_defined?(:pbContinualAbilityChecks)

  def pbContinualAbilityChecks(onSwitchIn=false)
    if hasActiveAbility?(:TRACE)
      choices = []
      @battle.eachOtherSideBattler(@index) do |b|
        next if b.ungainableAbility?
        next if [:POWEROFALCHEMY, :RECEIVER, :TRACE].include?(b.ability_id)

        # If target has boosted talent, trace the base version
        traced_ability = b.ability_id
        if b.pokemon && b.pokemon.has_family?
          family = b.pokemon.family
          boosted = PokemonFamilyConfig.get_boosted_talent(family)
          if traced_ability == boosted
            traced_ability = PokemonFamilyConfig.get_family_talent(family)
          end
        end

        choices.push({battler: b, ability: traced_ability})
      end

      if choices.length > 0
        choice = choices[@battle.pbRandom(choices.length)]
        @battle.pbShowAbilitySplash(self)
        self.ability = choice[:ability]
        ability_name = GameData::Ability.get(choice[:ability]).name
        @battle.pbDisplay(_INTL("{1} traced {2}'s {3}!",
                                pbThis, choice[:battler].pbThis(true), ability_name))
        @battle.pbHideAbilitySplash(self)

        if !onSwitchIn && (unstoppableAbility? || abilityActive?)
          BattleHandlers.triggerAbilityOnSwitchIn(self.ability, self, @battle)
        end
      end
      return  # Skip original Trace logic
    end

    # Call original for non-Trace abilities
    family_talent_original_pbContinualAbilityChecks(onSwitchIn) if defined?(family_talent_original_pbContinualAbilityChecks)
  end
end

#===============================================================================
# Receiver / Power of Alchemy - Copy base talent instead of boosted
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnFaintedTargetAbility)
  [:RECEIVER, :POWEROFALCHEMY].each do |ability_sym|
    BattleHandlers::AbilityOnFaintedTargetAbility.add(ability_sym,
      proc { |ability, target, battler, battle|
        next if battler.fainted?
        next if battler.ungainableAbility?

        # If fainted Pokemon has boosted talent, copy the base version
        copied_ability = target.ability_id
        if target.pokemon && target.pokemon.has_family?
          family = target.pokemon.family
          boosted = PokemonFamilyConfig.get_boosted_talent(family)
          if copied_ability == boosted
            copied_ability = PokemonFamilyConfig.get_family_talent(family)
          end
        end

        battle.pbShowAbilitySplash(battler)
        battler.ability = copied_ability
        ability_name = GameData::Ability.get(copied_ability).name
        battle.pbDisplay(_INTL("{1} received {2}!", battler.pbThis, ability_name))
        battle.pbHideAbilitySplash(battler)
        BattleHandlers.triggerAbilityOnSwitchIn(copied_ability, battler, battle)
      }
    )
  end
end

#===============================================================================
# Mold Breaker Compatibility
# Family talents CAN be negated by Mold Breaker (they're still abilities)
# No special handling needed - existing Mold Breaker logic applies
#===============================================================================

# Module loaded successfully
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("FAMILY-TALENT", "113_Family_Edge_Cases.rb loaded")
  MultiplayerDebug.info("FAMILY-TALENT", "Edge case handlers implemented:")
  MultiplayerDebug.info("FAMILY-TALENT", "  - Skill Swap: Prevented for Family talents")
  MultiplayerDebug.info("FAMILY-TALENT", "  - Trace: Copies base talent (not boosted)")
  MultiplayerDebug.info("FAMILY-TALENT", "  - Receiver/Power of Alchemy: Copies base talent")
  MultiplayerDebug.info("FAMILY-TALENT", "  - Mold Breaker: Can negate Family talents (normal behavior)")
end
