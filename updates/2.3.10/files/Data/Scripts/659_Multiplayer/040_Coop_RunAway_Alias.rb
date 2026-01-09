#===============================================================================
# MODULE 20: Coop Battle Run Away Alias
#===============================================================================
# Wraps pbRun to synchronize run attempt counter across all clients
# CRITICAL: In coop battles, we defer the actual run attempt until AFTER action
# sync, so both clients execute pbRun() with the same RNG state.
#===============================================================================

class PokeBattle_Battle
  alias coop_original_pbRun pbRun

  def pbRun(idxBattler, duringBattle = false)
    # If not in coop battle, use original behavior
    unless defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      return coop_original_pbRun(idxBattler, duringBattle)
    end

    # Check if this is a trainer battle
    if trainerBattle?
      # COOP TRAINER BATTLE: Forfeit causes whiteout for all players
      # Unlike wild battles, trainer battle forfeit is GUARANTEED to succeed
      if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
        battler = @battlers[idxBattler]

        # Only player's battlers can forfeit
        return coop_original_pbRun(idxBattler, duringBattle) if battler.opposes?

        ##MultiplayerDebug.info("COOP-FORFEIT", "Player chose to forfeit coop trainer battle")

        # Broadcast forfeit to all allies
        battle_id = CoopBattleState.battle_id
        turn = turnCount
        message = "COOP_FORFEIT:#{battle_id}|#{turn}"
        MultiplayerClient.send_data(message) if defined?(MultiplayerClient)

        # Small delay to allow message to send
        sleep(0.05)

        # Display forfeit message
        pbDisplay(_INTL("{1} forfeited the battle!", pbPlayer.name))

        # Mark as loss (will trigger whiteout in pbEndOfBattle)
        @decision = 2

        # Mark that we whited out (for coop battle state tracking)
        if defined?(CoopBattleState)
          CoopBattleState.instance_variable_set(:@whiteout, true)
        end

        ##MultiplayerDebug.info("COOP-FORFEIT", "Battle decision set to 2 (loss), whiteout flag set")
        return 1  # Return success (forfeit always succeeds)
      else
        # Solo trainer battle - can't run
        return coop_original_pbRun(idxBattler, duringBattle)
      end
    end

    battler = @battlers[idxBattler]

    # Only player's battlers can attempt to run
    if battler.opposes?
      return coop_original_pbRun(idxBattler, duringBattle)
    end

    ###MultiplayerDebug.info("COOP-RUN", "=" * 70)
    ##MultiplayerDebug.info("COOP-RUN", "Run attempt by battler #{idxBattler} (#{battler.pbThis})")
    ##MultiplayerDebug.info("COOP-RUN", "  duringBattle: #{duringBattle}")

    # Mark that a run was attempted (triggers RNG re-sync after action sync)
    if defined?(CoopRunAwaySync)
      CoopRunAwaySync.mark_run_attempted

      # Broadcast to allies that run was attempted (so they also trigger re-sync)
      battle_id = CoopBattleState.battle_id
      turn = turnCount
      message = "COOP_RUN_ATTEMPTED:#{battle_id}|#{turn}"
      MultiplayerClient.send_data(message) if defined?(MultiplayerClient)
      ##MultiplayerDebug.info("COOP-RUN", "Broadcasted run attempt to allies")
    end

    # Use synchronized run command counter instead of @runCommand
    if defined?(CoopRunAwaySync)
      synced_run_command = CoopRunAwaySync.get_run_command
      ##MultiplayerDebug.info("COOP-RUN", "Using synchronized run command: #{synced_run_command}")

      # Temporarily override @runCommand for this calculation
      old_run_command = @runCommand
      @runCommand = synced_run_command
    end

    # Call original pbRun - with synced RNG and synced @runCommand, result is deterministic
    result = coop_original_pbRun(idxBattler, duringBattle)

    # Restore original @runCommand (we manage it via CoopRunAwaySync)
    if defined?(CoopRunAwaySync)
      @runCommand = old_run_command
    end

    # Handle result
    if result == 1
      # Success - broadcast to all allies BEFORE ending battle
      ##MultiplayerDebug.info("COOP-RUN", "✓ Run SUCCEEDED - broadcasting to allies")

      battle_id = CoopBattleState.battle_id
      turn = turnCount
      message = "COOP_RUN_SUCCESS:#{battle_id}|#{turn}"
      MultiplayerClient.send_data(message) if defined?(MultiplayerClient)

      # Small delay to allow message to send
      sleep(0.05)

      ##MultiplayerDebug.info("COOP-RUN", "  Battle ending for all clients")
      ###MultiplayerDebug.info("COOP-RUN", "=" * 70)
      # @decision already set to 3 by original pbRun
      return 1

    elsif result == -1
      # Failure - increment synchronized counter (initiator only)
      ##MultiplayerDebug.info("COOP-RUN", "✗ Run FAILED - incrementing run command")

      if defined?(CoopRunAwaySync) && CoopBattleState.am_i_initiator?
        # Only initiator increments and broadcasts
        battle_id = CoopBattleState.battle_id
        turn = turnCount
        CoopRunAwaySync.increment_run_command(battle_id, turn)
      end

      # CRITICAL: Clear the battler's choice so they waste their turn
      # The vanilla game goes back to command menu, but in coop we can't do that
      # Set choice to :None - NPCTrainers are now skipped in AI phase via pbCommandPhaseLoop override
      @choices[idxBattler][0] = :None
      @choices[idxBattler][1] = 0
      @choices[idxBattler][2] = nil
      @choices[idxBattler][3] = -1
      ##MultiplayerDebug.info("COOP-RUN", "  Cleared battler choice - turn will be wasted")

      # Broadcast the cleared choice to allies so they also clear it
      if defined?(CoopActionSync)
        battle_id = CoopBattleState.battle_id
        turn = turnCount
        # Send cleared action (format: battler_idx => [:None, 0, nil, -1])
        cleared_action = { idxBattler => [:None, 0, nil, -1] }
        CoopActionSync.broadcast_failed_run(battle_id, turn, idxBattler)
        ##MultiplayerDebug.info("COOP-RUN", "  Broadcasted cleared choice to allies")
      end

      ###MultiplayerDebug.info("COOP-RUN", "=" * 70)
      return -1

    else
      # Invalid case (couldn't attempt run)
      ##MultiplayerDebug.info("COOP-RUN", "Run attempt invalid (result=#{result})")
      ###MultiplayerDebug.info("COOP-RUN", "=" * 70)
      return 0
    end
  end
end

##MultiplayerDebug.info("MODULE-20", "Run away alias loaded - run command synchronization enabled")
