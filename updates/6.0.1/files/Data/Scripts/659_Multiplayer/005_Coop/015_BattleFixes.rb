# =============================================================================
# Co-op Battle Fixes
# =============================================================================
# Small targeted fixes for edge cases in coop battles.
#
# Source files merged:
#   041_Coop_Obedience_Fix.rb       → Use max badges in coop
#   042_Coop_Whiteout_Detection.rb  → Detect when player whited out
#   044_Coop_LoseMoney_Fix.rb       → Check pbPlayer is Player before calling
#   045_Coop_PokedexFix.rb          → Pokedex entry sync (may be disabled)
#   074_Coop_ExpBarFix.rb           → Check dataBox exists before animating
#   075_Coop_SceneSafety.rb         → Scene transition safety checks
# =============================================================================

# --- Obedience Fix (from 041) ---
class PokeBattle_Battler
  alias coop_obedience_original_pbObedienceCheck? pbObedienceCheck?

  def pbObedienceCheck?(choice)
    return true if usingMultiTurnAttack?
    return true if choice[0] != :UseMove
    return true if !@battle.internalBattle
    return true if !@battle.pbOwnedByPlayer?(@index)

    disobedient = false

    # COOP FIX: In coop battles, use max badges (8) to prevent disobedience
    if defined?(CoopBattleState) && CoopBattleState.active?
      badge_count = 8  # Max badges - no disobedience in coop
    else
      # Vanilla battle, use player's actual badge count
      badge_count = @battle.pbPlayer.badge_count
    end

    badgeLevel = 10 * (badge_count + 1)
    badgeLevel = GameData::GrowthRate.max_level if badge_count >= 8

    if (@pokemon.foreign?(@battle.pbPlayer) && @level > badgeLevel) || @pokemon.force_disobey
      a = ((@level + badgeLevel) * @battle.pbRandom(256) / 256).floor
      disobedient |= (a >= badgeLevel)
    end
    disobedient |= !pbHyperModeObedience(choice[2])
    return true if !disobedient

    # Pokémon is disobedient; make it do something else
    return pbDisobey(choice, badgeLevel)
  end

  # --- Whiteout Detection (from 042) ---
  # Hook into pbFaint to detect when all player's Pokemon have fainted
  alias coop_original_pbFaint pbFaint

  def pbFaint(showMessage=true)
    # Call original faint logic first
    coop_original_pbFaint(showMessage)

    # Check if this is a coop battle
    return unless defined?(CoopBattleState) && CoopBattleState.in_coop_battle?

    # Check if the fainted battler belongs to the local player (not an opponent)
    return unless !opposes?

    # Get the trainer who owns this battler (the one that just fainted)
    my_battler_index = @index
    my_trainer = @battle.pbGetOwnerFromBattlerIndex(my_battler_index)
    return unless my_trainer && my_trainer.is_a?(Player)

    # Check if ALL of THIS trainer's Pokemon are now fainted
    # IMPORTANT: Use my_battler_index, not 0! (0 is always the initiator)
    all_fainted = @battle.pbTrainerAllFainted?(my_battler_index)

    if all_fainted
      # Mark that this player whited out
      CoopBattleState.mark_whiteout
    end
  end
end

# --- Lose Money Fix (from 044) ---
class PokeBattle_Battle
  alias coop_original_pbLoseMoney pbLoseMoney

  def pbLoseMoney
    # In coop battles, pbPlayer might return an NPCTrainer
    # Only call original if pbPlayer is actually a Player
    return unless pbPlayer.is_a?(Player)

    coop_original_pbLoseMoney
  end
end

# --- Pokedex Fix (from 045) ---
# DISABLED - functionality moved to 029_Coop_StorePokemon_Alias.rb
# This previously duplicated catch processing logic, causing non-catchers
# to see prompts and lose Pokemon. Kept for reference.

# --- Exp Bar Fix (from 074) ---
class PokeBattle_Scene
  alias coop_expbar_original_pbEXPBar pbEXPBar

  def pbEXPBar(battler, startExp, endExp, tempExp1, tempExp2)
    return if startExp > endExp
    return if !battler

    # Check if dataBox exists before trying to animate
    dataBox = @sprites["dataBox_#{battler.index}"]
    return if !dataBox

    # DataBox exists, proceed with original behavior
    startExpLevel = tempExp1 - startExp
    endExpLevel   = tempExp2 - startExp
    expRange      = endExp - startExp
    dataBox.animateExp(startExpLevel, endExpLevel, expRange)
    while dataBox.animatingExp; pbUpdate; end
  end

  # --- Scene Safety (from 075) ---
  alias coop_safety_original_pbShowWindow pbShowWindow
  alias coop_safety_original_pbDisplayPausedMessage pbDisplayPausedMessage

  def pbShowWindow(windowType)
    # In coop battles, safely handle nil sprites that may occur after captures
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      # Check if sprites exist before trying to set visibility
      return unless @sprites
      return unless @sprites["messageBox"]

      # Proceed with original method only if sprites are valid
      coop_safety_original_pbShowWindow(windowType)
    else
      # Not in coop, use original behavior
      coop_safety_original_pbShowWindow(windowType)
    end
  end

  def pbDisplayPausedMessage(msg)
    # In coop battles, safely handle nil sprites
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      return unless @sprites
      return unless @sprites["messageWindow"]
    end

    coop_safety_original_pbDisplayPausedMessage(msg)
  end
end

class PokeBattle_Battle
  alias coop_safety_original_pbDisplayPaused pbDisplayPaused

  def pbDisplayPaused(msg, &block)
    # In coop battles, safely handle scene errors during exp gain after captures
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      # Check if scene and sprites are still valid
      return unless @scene
      return unless @scene.instance_variable_get(:@sprites)

      begin
        coop_safety_original_pbDisplayPaused(msg, &block)
      rescue NoMethodError => e
        # Log the error but don't crash - scene might be in transitional state
        return
      end
    else
      coop_safety_original_pbDisplayPaused(msg, &block)
    end
  end
end
