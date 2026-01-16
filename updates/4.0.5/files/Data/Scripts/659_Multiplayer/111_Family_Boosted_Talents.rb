#===============================================================================
# MODULE: Family Boosted Talents - Battle Handlers
#===============================================================================
# BattleHandlers for the 8 boosted Family talents.
# Each boosted talent is an enhanced version of the base Family talent.
#===============================================================================

#===============================================================================
# 1. PANMORPHOSIS (Boosted Protean) - Primordium
# Base: Changes type to match the move used
# Boosted: ALSO changes to resistant type when hit (defensive Protean)
#===============================================================================

# Offensive type change (same as Protean, but for Panmorphosis too)
class PokeBattle_Battler
  alias family_panmorphosis_original_pbUseMove pbUseMove
  def pbUseMove(choice, specialUsage=false)
    move = choice[2]

    # Check @ability_id symbol directly since hasActiveAbility compares objects
    if move && @ability_id == :PANMORPHOSIS && !move.callsAnotherMove? && !move.snatched
      move_type = move.pbCalcType(self)  # Calculate type first

      if self.pbHasOtherType?(move_type) && !GameData::Type.get(move_type).pseudo_type
        @battle.pbShowAbilitySplash(self)  # Creates UI popup automatically
        self.pbChangeTypes(move_type)
        typeName = GameData::Type.get(move_type).name
        @battle.pbDisplay(_INTL("{1} transformed into the {2} type!", self.pbThis, typeName))
        @battle.pbHideAbilitySplash(self)
      end
    end

    family_panmorphosis_original_pbUseMove(choice, specialUsage)
  end
end

# Defensive type change (unique to Panmorphosis)
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcTargetAbility)
  BattleHandlers::DamageCalcTargetAbility.add(:PANMORPHOSIS,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless ability == :PANMORPHOSIS
      next if !type || type == :SHADOW

      # Find ANY type that resists the incoming attack (0.5x effectiveness)
      best_type = nil
      best_effectiveness = Effectiveness::NORMAL_EFFECTIVE_ONE

      GameData::Type.each do |type_data|
        next if type_data.pseudo_type

        effectiveness = Effectiveness.calculate_one(type, type_data.id)

        # Pick type with lowest effectiveness (most resistant)
        if effectiveness < best_effectiveness
          best_effectiveness = effectiveness
          best_type = type_data.id
        end
      end

      # Transform to resistant type BEFORE damage calculation (if 0.5x or less)
      if best_type && !target.pbHasType?(best_type) && best_effectiveness < Effectiveness::NORMAL_EFFECTIVE_ONE
        target.battle.pbShowAbilitySplash(target)
        target.pbChangeTypes(best_type)
        type_name = GameData::Type.get(best_type).name
        target.battle.pbDisplay(_INTL("{1} transformed into the {2} type!", target.pbThis, type_name))
        target.battle.pbHideAbilitySplash(target)

        # Recalculate type effectiveness with new type
        target.damageState.typeMod = move.pbCalcTypeMod(type, user, target)
      end
    }
  )
end

#===============================================================================
# 2. VEILBREAKER (Boosted Infiltrator) - Vacuum
# Base: Bypasses Reflect, Light Screen, Safeguard, Mist, Substitute
# Boosted: ALSO bypasses Protect, semi-invulnerable states, King's Shield, etc.
#===============================================================================

# VEILBREAKER bypasses all battle conditions
# Infiltrator base effect already implemented in core
# Enhanced version handles Protect-like moves
if defined?(BattleHandlers) && defined?(BattleHandlers::MoveImmunityTargetAbility)
  BattleHandlers::MoveImmunityTargetAbility.add(:VEILBREAKER,
    proc { |ability, user, target, move, type, battle, show_message|
      # Veilbreaker bypasses all protection moves
      next false
    }
  )
end

#===============================================================================
# 3. VOIDBORNE (Boosted Levitate) - Astrum
# Base: Ground immunity
# Boosted: ALSO immune to all special attacks
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::MoveImmunityTargetAbility)
  BattleHandlers::MoveImmunityTargetAbility.add(:VOIDBORNE,
    proc { |ability, user, target, move, type, battle, show_message|
      next false if !move.specialMove?

      if show_message
        battle.pbShowAbilitySplash(target)
        battle.pbDisplay(_INTL("{1}'s {2} made the special attack ineffective!", target.pbThis, target.abilityName))
        battle.pbHideAbilitySplash(target)
      end
      next true  # Immune
    }
  )
end

#===============================================================================
# 4. VITALREBIRTH (Boosted Regenerator) - Silva
# Base: Heals 33% of max HP on switch out (Regenerator)
# Boosted: Heals 50% of max HP AND cures all status effects on switch out
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchOut)
  BattleHandlers::AbilityOnSwitchOut.add(:VITALREBIRTH,
    proc { |ability, battler, endOfBattle|
      next if endOfBattle

      # Heal 50% HP
      heal_amount = (battler.totalhp / 2.0).round
      if battler.hp < battler.totalhp && battler.pbRecoverHP(heal_amount)
        battler.battle.pbDisplay(_INTL("{1}'s Vital Rebirth restored its vitality!", battler.pbThis))
      end

      # Cure all status effects
      if battler.status != :NONE
        old_status = battler.status
        battler.pbCureStatus(false)
        battler.battle.pbDisplay(_INTL("{1}'s Vital Rebirth cured its {2}!",
                                       battler.pbThis, GameData::Status.get(old_status).name))
      end
    }
  )
end

#===============================================================================
# 5. IMMOVABLE (Boosted Sturdy) - Machina
# Base: Survives one OHKO or one hit at full HP
# Boosted: Can only be fainted if HP was at 1 before the attack.
#          Heals to 100% max HP on first time reaching 1 HP.
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcTargetAbility)
  BattleHandlers::DamageCalcTargetAbility.add(:IMMOVABLE,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless ability == :IMMOVABLE
      next if target.hp == 1  # Already at 1 HP - can be fainted now

      # Check if this damage would KO (HP > 1 currently)
      predicted_damage = baseDmg
      would_ko = (target.hp - predicted_damage) <= 0

      if would_ko && target.hp > 1
        # Survive with 1 HP instead
        mults[:final_damage_multiplier] = (target.hp - 1).to_f / predicted_damage
        target.effects[:ImmovableTriggered] = true  # Flag for healing after damage
      end
    }
  )
end

# Heal to full HP after first time reaching 1 HP
if defined?(BattleHandlers) && defined?(BattleHandlers::UserAbilityEndOfMove)
  BattleHandlers::UserAbilityEndOfMove.add(:IMMOVABLE,
    proc { |ability, user, targets, move, battle|
      # Check all targets for Immovable trigger
      battle.battlers.each do |b|
        next unless b && b.ability_id == :IMMOVABLE
        next unless b.effects[:ImmovableTriggered]
        next unless b.hp == 1
        next if b.effects[:ImmovableHealed]  # Already healed once

        # Heal to full HP
        b.effects[:ImmovableTriggered] = false
        b.effects[:ImmovableHealed] = true

        battle.pbShowAbilitySplash(b)
        b.pbRecoverHP(b.totalhp - 1)
        battle.pbDisplay(_INTL("{1} became immovable and restored itself!", b.pbThis))
        battle.pbHideAbilitySplash(b)
      end
    }
  )
end

#===============================================================================
# 6. INDOMITABLE (Boosted Mold Breaker) - Humanitas
# Base: Ignores abilities that would hinder attacks
# Boosted: ALSO cancels ALL stat changes on ALL battlers (allies + enemies)
#          AND deals true damage (ignores Defense and Sp. Def)
#===============================================================================

# Reset all stat stages to 0 on switch-in
if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:INDOMITABLE,
    proc { |ability, battler, battle|
      # Reset all battlers' stat stages to 0
      battle.battlers.each do |b|
        next unless b
        b.stages.each_key { |stat| b.stages[stat] = 0 }
      end

      battle.pbShowAbilitySplash(battler)
      battle.pbDisplay(_INTL("{1}'s Indomitable nullifies all stat changes!", battler.pbThis))
      battle.pbHideAbilitySplash(battler)
    }
  )
end

# Continuously reset stat stages each priority calculation
class PokeBattle_Battle
  alias family_indomitable_original_pbCalculatePriority pbCalculatePriority
  def pbCalculatePriority(*args)
    # Reset all stat stages if any battler has Indomitable
    if @battlers.any? { |b| b && b.ability_id == :INDOMITABLE }
      @battlers.each do |b|
        next unless b
        b.stages.each_key { |stat| b.stages[stat] = 0 }
      end
    end

    family_indomitable_original_pbCalculatePriority(*args)
  end
end

# True damage calculation (ignore defense multipliers)
if defined?(BattleHandlers) && defined?(BattleHandlers::DamageCalcUserAbility)
  BattleHandlers::DamageCalcUserAbility.add(:INDOMITABLE,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless ability == :INDOMITABLE

      # Nullify defense multiplier for true damage
      mults[:defense_multiplier] = 1.0
    }
  )
end

#===============================================================================
# 7. COSMICBLESSING (Boosted Serene Grace) - Aetheris
# Base: 2x chance of secondary effects (Serene Grace adds +30% or doubles)
# Boosted: 100% activation rate for secondary effects
#===============================================================================

class PokeBattle_Move
  alias family_cosmicblessing_original_pbAdditionalEffectChance pbAdditionalEffectChance
  def pbAdditionalEffectChance(user, target, effectChance=0)
    # Cosmic Blessing forces 100% activation
    if user.hasActiveAbility?(:COSMICBLESSING)
      return 100
    end

    return family_cosmicblessing_original_pbAdditionalEffectChance(user, target, effectChance)
  end
end

#===============================================================================
# 8. MINDSHATTER (Boosted Intimidate) - Infernum
# Base: Lowers opponent's Attack by 1 stage on switch-in
# Boosted: ALSO lowers opponent's Special Attack by 1 stage
#===============================================================================

if defined?(BattleHandlers) && defined?(BattleHandlers::AbilityOnSwitchIn)
  BattleHandlers::AbilityOnSwitchIn.add(:MINDSHATTER,
    proc { |ability, battler, battle|
      # Lower both Attack and Special Attack
      battle.allOtherSideBattlers(battler.index).each do |b|
        next if !b.pbCanLowerStatStage?(:ATTACK, battler) &&
                !b.pbCanLowerStatStage?(:SPECIAL_ATTACK, battler)

        battle.pbShowAbilitySplash(battler)
        b.pbLowerStatStage(:ATTACK, 1, battler)
        b.pbLowerStatStage(:SPECIAL_ATTACK, 1, battler)
        battle.pbHideAbilitySplash(battler)
      end
    }
  )
end
