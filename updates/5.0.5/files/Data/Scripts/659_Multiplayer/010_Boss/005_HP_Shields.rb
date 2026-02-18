#===============================================================================
# MODULE 5: Boss Pokemon System - HP Phases & Shields
#===============================================================================
# Implements the 4-phase HP system and shield damage-reduction mechanic.
#
# HP Phases:
#   - Boss has 4 HP phases (displayed as "x4", "x3", etc.)
#   - Each phase = 25% of total HP
#   - When a phase breaks, shields activate
#
# Shields:
#   - While shields are active, attacks still deal reduced HP damage
#   - Damage reduction: 50% solo, 60% duo, 70% trio
#   - Each attack also removes shields (1 normal, 2 super effective)
#   - When all shields break, full HP damage resumes
#
# Test: Encounter boss, attack it. HP depletes until phase threshold,
#       then shields activate and reduce subsequent attack damage.
#===============================================================================

#===============================================================================
# Override pbInflictHPDamage for Boss Shield Logic
#===============================================================================
class PokeBattle_Move
  alias boss_hp_shields_pbInflictHPDamage pbInflictHPDamage

  def pbInflictHPDamage(target)
    pkmn = target.pokemon
    return boss_hp_shields_pbInflictHPDamage(target) unless pkmn&.is_boss?

    # Get boss state
    shields = pkmn.boss_shields
    hp_phase = pkmn.boss_hp_phase

    #===========================================================================
    # Shield Phase: Remove shields + apply REDUCED damage
    #===========================================================================
    if shields > 0
      # Calculate base shield damage based on effectiveness
      type_mod = target.damageState.typeMod
      is_super_effective = Effectiveness.super_effective?(type_mod)
      is_critical = target.damageState.critical

      # Base damage: 1 for normal, 2 for super effective
      base_shield_dmg = is_super_effective ? BossConfig::SHIELD_DMG_SUPER : BossConfig::SHIELD_DMG_NORMAL

      # Critical hits double shield damage (2 for normal crit, 4 for super effective crit)
      shield_dmg = is_critical ? base_shield_dmg * 2 : base_shield_dmg

      # Apply shield damage
      pkmn.boss_shields = [shields - shield_dmg, 0].max

      # Force UI update for shield change
      if defined?(BossUIManager)
        BossUIManager.update_boss_databox(target)
      end

      # Apply damage reduction while shielded
      dr = pkmn.boss_shield_dr
      original_damage = target.damageState.hpLost
      reduced_damage = [(original_damage * (1.0 - dr)).to_i, 1].max
      target.damageState.hpLost = reduced_damage

      MultiplayerDebug.info("BOSS-HP", "Shield DR! #{original_damage}->#{reduced_damage} (#{(dr * 100).to_i}% DR), Shields #{shields}->#{pkmn.boss_shields}") if defined?(MultiplayerDebug)

      # Display messages
      crit_text = is_critical ? "Critical hit! " : ""
      if pkmn.boss_shields > 0
        @battle.pbDisplay(_INTL("{1}The barrier weakened the attack! ({2} shields remaining)", crit_text, pkmn.boss_shields))
      else
        @battle.pbDisplay(_INTL("{1}The barrier shattered!", crit_text))
      end
    end

    #===========================================================================
    # Apply HP damage (reduced if shields were up, full if not)
    #===========================================================================
    hp_before = target.hp

    boss_hp_shields_pbInflictHPDamage(target)

    # Calculate new phase based on HP
    # Phase thresholds: 75%, 50%, 25%, 0%
    phase_hp = target.totalhp.to_f / BossConfig::HP_PHASES
    new_phase = [(target.hp.to_f / phase_hp).ceil, 0].max

    #===========================================================================
    # Overdamage Clamp: A single hit can never skip more than 1 HP bar
    #===========================================================================
    if hp_phase > 1 && new_phase < hp_phase - 1
      clamped_phase = hp_phase - 1
      clamped_hp = [((clamped_phase - 1) * phase_hp).to_i + 1, 1].max
      target.hp = clamped_hp
      new_phase = [(target.hp.to_f / phase_hp).ceil, 0].max
      MultiplayerDebug.info("BOSS-HP", "Overdamage clamped! HP set to #{target.hp} (phase #{new_phase})") if defined?(MultiplayerDebug)
    end

    #===========================================================================
    # Phase Transition: Activate shields
    #===========================================================================
    if new_phase < hp_phase && new_phase > 0
      pkmn.boss_hp_phase = new_phase
      pkmn.boss_shields = pkmn.boss_max_shields

      # Force UI update for shield activation
      if defined?(BossUIManager)
        BossUIManager.update_boss_databox(target)
        MultiplayerDebug.info("BOSS-HP", "Shields activated! Phase=#{new_phase}, Shields=#{pkmn.boss_shields}/#{pkmn.boss_max_shields}") if defined?(MultiplayerDebug)
      end

      # Display phase break message
      @battle.pbDisplay(_INTL("The boss's defenses faltered!"))
      @battle.pbDisplay(_INTL("A new barrier has been raised! ({1} phases remaining)", new_phase))
    end

    #===========================================================================
    # Final Phase (phase 0): Boss is defeated (only possible from phase 1)
    #===========================================================================
    if target.hp <= 0 && hp_phase > 0
      pkmn.boss_hp_phase = 0
      # Loot voting will be triggered in pbEndOfBattle hook
    end
  end
end

#===============================================================================
# Apply Boss Stat Multipliers During Battle
#===============================================================================
# This hooks into the stat calculation to apply boss multipliers
class PokeBattle_Battler
  alias boss_stats_pbSpeed pbSpeed

  def pbSpeed
    spd = boss_stats_pbSpeed
    return spd unless is_boss? && @pokemon.boss_stat_mults

    mults = @pokemon.boss_stat_mults
    (spd * (mults[:speed] || 1.0)).to_i
  end

  # Override totalhp calculation for boss HP multiplier
  def boss_totalhp_multiplied
    return @totalhp unless is_boss? && @pokemon.boss_stat_mults

    mults = @pokemon.boss_stat_mults
    (@totalhp * (mults[:hp] || 1.0)).to_i
  end
end

#===============================================================================
# Initialize Boss Stats When Entering Battle
#===============================================================================
# Hook into battler initialization to apply boss HP multiplier
class PokeBattle_Battler
  alias boss_pbInitialize pbInitialize

  def pbInitialize(pkmn, idxParty, batonPass = false)
    boss_pbInitialize(pkmn, idxParty, batonPass)

    return unless pkmn&.is_boss?

    # Apply HP multiplier
    mults = pkmn.boss_stat_mults
    if mults && mults[:hp]
      @totalhp = (@totalhp * mults[:hp]).to_i
      @hp = @totalhp  # Start at full HP
    end

    # Log boss initialization
    MultiplayerDebug.info("BOSS", "Boss battler initialized: HP=#{@hp}/#{@totalhp}") if defined?(MultiplayerDebug)
  end
end

#===============================================================================
# Defense/SpDef Multipliers (Applied in Damage Calculation)
#===============================================================================
# Rather than modifying base stats, apply multipliers in damage calc
# This is handled via BattleHandlers for cleaner integration

if defined?(BattleHandlers)
  # Boss Defense Multiplier (when boss is TARGET - tankier)
  BattleHandlers::DamageCalcTargetAbility.add(:BOSS_DEFENSE_BOOST,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless target.is_boss? && target.pokemon.boss_stat_mults

      stat_mults = target.pokemon.boss_stat_mults

      if move.physicalMove?
        def_mult = stat_mults[:def] || 1.0
        mults[:defense_multiplier] *= def_mult
      elsif move.specialMove?
        spdef_mult = stat_mults[:spdef] || 1.0
        mults[:defense_multiplier] *= spdef_mult
      end
    }
  )

  # Boss Attack Reduction (when boss is USER - deals less damage)
  BattleHandlers::DamageCalcUserAbility.add(:BOSS_ATTACK_REDUCTION,
    proc { |ability, user, target, move, mults, baseDmg, type|
      next unless user.is_boss? && user.pokemon.boss_stat_mults

      stat_mults = user.pokemon.boss_stat_mults

      if move.physicalMove?
        atk_mult = stat_mults[:atk] || 1.0
        mults[:attack_multiplier] *= atk_mult
      elsif move.specialMove?
        spatk_mult = stat_mults[:spatk] || 1.0
        mults[:attack_multiplier] *= spatk_mult
      end
    }
  )
end

#===============================================================================
# Override pbReduceHP for Status Damage (Burn, Poison, Leech Seed, etc.)
#===============================================================================
# Status damage bypasses pbInflictHPDamage, so we need to hook pbReduceHP
# to properly handle shields and phase transitions for bosses.
class PokeBattle_Battler
  alias boss_shields_pbReduceHP pbReduceHP

  def pbReduceHP(amt, anim = true, registerDamage = true, anyAnim = true)
    pkmn = @pokemon
    return boss_shields_pbReduceHP(amt, anim, registerDamage, anyAnim) unless pkmn&.is_boss?

    shields = pkmn.boss_shields
    hp_phase = pkmn.boss_hp_phase

    #===========================================================================
    # Shield Phase: Remove 1 shield + apply reduced status damage
    #===========================================================================
    if shields > 0
      # Status damage always does 1 shield damage (no super effective/crit bonus)
      pkmn.boss_shields = shields - 1

      # Force UI update
      if defined?(BossUIManager)
        BossUIManager.update_boss_databox(self)
      end

      # Apply damage reduction
      dr = pkmn.boss_shield_dr
      reduced_amt = [(amt * (1.0 - dr)).to_i, 1].max

      MultiplayerDebug.info("BOSS-HP", "Shield DR on status! #{amt}->#{reduced_amt} (#{(dr * 100).to_i}% DR), Shields #{shields}->#{pkmn.boss_shields}") if defined?(MultiplayerDebug)

      # Show message
      if pkmn.boss_shields > 0
        @battle.pbDisplay(_INTL("The barrier weakened the damage! ({1} shields remaining)", pkmn.boss_shields))
      else
        @battle.pbDisplay(_INTL("The barrier shattered!"))
      end

      amt = reduced_amt
    end

    #===========================================================================
    # Apply HP damage (reduced if shields were up, full if not)
    #===========================================================================
    hp_before = @hp

    # Call original to reduce HP
    actual_loss = boss_shields_pbReduceHP(amt, anim, registerDamage, anyAnim)

    # Calculate new phase based on HP
    phase_hp = @totalhp.to_f / BossConfig::HP_PHASES
    new_phase = [(@hp.to_f / phase_hp).ceil, 0].max

    # Overdamage clamp: a single hit can never skip more than 1 HP bar
    if hp_phase > 1 && new_phase < hp_phase - 1
      clamped_phase = hp_phase - 1
      clamped_hp = [((clamped_phase - 1) * phase_hp).to_i + 1, 1].max
      @hp = clamped_hp
      actual_loss = hp_before - @hp
      new_phase = [(@hp.to_f / phase_hp).ceil, 0].max
      MultiplayerDebug.info("BOSS-HP", "Status overdamage clamped! HP set to #{@hp} (phase #{new_phase})") if defined?(MultiplayerDebug)
    end

    # Check for phase transition
    if new_phase < hp_phase && new_phase > 0
      pkmn.boss_hp_phase = new_phase
      pkmn.boss_shields = pkmn.boss_max_shields

      # Force UI update
      if defined?(BossUIManager)
        BossUIManager.update_boss_databox(self)
        MultiplayerDebug.info("BOSS-HP", "Status damage triggered phase transition! Phase=#{new_phase}, Shields=#{pkmn.boss_max_shields}") if defined?(MultiplayerDebug)
      end

      # Display phase break message
      @battle.pbDisplay(_INTL("The boss's defenses faltered!"))
      @battle.pbDisplay(_INTL("A new barrier has been raised! ({1} phases remaining)", new_phase))
    end

    # Final phase check
    if @hp <= 0 && hp_phase > 0
      pkmn.boss_hp_phase = 0
    end

    return actual_loss
  end
end

#===============================================================================
# Helper: Check Phase Threshold
#===============================================================================
module BossHPSystem
  def self.get_phase_threshold(totalhp, phase)
    phase_hp = totalhp.to_f / BossConfig::HP_PHASES
    (phase * phase_hp).to_i
  end

  def self.get_current_phase(hp, totalhp)
    return 0 if hp <= 0
    phase_hp = totalhp.to_f / BossConfig::HP_PHASES
    [(hp.to_f / phase_hp).ceil, BossConfig::HP_PHASES].min
  end

  def self.phase_info(battler)
    return nil unless battler.is_boss?

    pkmn = battler.pokemon
    {
      current_phase: pkmn.boss_hp_phase,
      shields: pkmn.boss_shields,
      hp: battler.hp,
      totalhp: battler.totalhp,
      phase_hp: battler.totalhp / BossConfig::HP_PHASES
    }
  end
end
