#===============================================================================
# MODULE 8: Attack Phase Alias - Sync State Reset
#===============================================================================
# Wraps pbAttackPhase to reset action sync state after all moves executed
# This ensures Turn 2+ properly wait for action sync instead of using stale state
# Note: RNG sync now happens in command phase (before AI runs), not here
#===============================================================================

class PokeBattle_Battle
  # Save original method
  alias coop_original_pbAttackPhase pbAttackPhase

  def pbAttackPhase
    @scene.pbBeginAttackPhase

    # IMPORTANT: Capture turn number BEFORE incrementing for RNG sync
    # Action sync uses `turnCount + 1` during command phase
    # So we need to match that same turn number here
    rng_sync_turn = @turnCount + 1

    # Reset certain effects
    @battlers.each_with_index do |b,i|
      next if !b
      b.turnCount += 1 if !b.fainted?
      @successStates[i].clear
      if @choices[i][0]!=:UseMove && @choices[i][0]!=:Shift && @choices[i][0]!=:SwitchOut
        b.effects[PBEffects::DestinyBond] = false
        b.effects[PBEffects::Grudge]      = false
      end
      b.effects[PBEffects::Rage] = false if !pbChoseMoveFunctionCode?(i,"093")   # Rage
    end
    PBDebug.log("")

    # NOTE: RNG is now synced in command phase (before AI runs)
    # No need to sync again here in attack phase

    # Calculate move order for this round
    pbCalculatePriority(true)

    # DEBUG: Log priority order after calculation
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle? && defined?(RNGLog)
      role = CoopBattleState.am_i_initiator? ? "INIT" : "NON"
      priority_order = pbPriority.map { |b| "b#{b.index}" }.join(",")
      RNGLog.write("[PRIORITY][#{role}][T#{@turnCount}] order=#{priority_order}")
    end

    # Perform actions
    pbAttackPhasePriorityChangeMessages
    pbAttackPhaseCall
    pbAttackPhaseSwitch
    return if @decision>0
    pbAttackPhaseItems
    return if @decision>0
    pbAttackPhaseMegaEvolution
    pbAttackPhaseMoves

    # MODULE 5: Reset sync state at end of attack phase (after all moves executed)
    # This ensures next turn's command phase will wait for fresh actions
    if defined?(CoopActionSync) && defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      # Use current_turn from action sync (which was set during command phase)
      completed_turn = CoopActionSync.current_turn

      # Report RNG call count for this turn
      if defined?(CoopRNGDebug)
        CoopRNGDebug.report
      end

      CoopActionSync.reset_sync_state
      ##MultiplayerDebug.info("COOP-SYNC", "Turn #{completed_turn} complete, sync state reset for next turn")
    end
  end
end

##MultiplayerDebug.info("MODULE-8", "Attack phase alias loaded - RNG sync + sync state reset enabled")
