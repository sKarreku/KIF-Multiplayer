#===============================================================================
# MODULE 19: Coop Battle Run Away Synchronization
#===============================================================================
# Ensures run away attempts are synchronized across all clients by maintaining
# a shared @runCommand counter that increases escape chance on failed attempts.
#===============================================================================

module CoopRunAwaySync
  @synchronized_run_command = 0  # Shared run attempt counter across all clients
  @run_attempted_this_turn = false  # Track if any run was attempted this turn

  #-----------------------------------------------------------------------------
  # Get current synchronized run command value
  #-----------------------------------------------------------------------------
  def self.get_run_command
    @synchronized_run_command
  end

  #-----------------------------------------------------------------------------
  # Mark that a run was attempted this turn (for RNG re-sync)
  #-----------------------------------------------------------------------------
  def self.mark_run_attempted
    @run_attempted_this_turn = true
  end

  #-----------------------------------------------------------------------------
  # Check if run was attempted this turn (triggers RNG re-sync)
  #-----------------------------------------------------------------------------
  def self.run_attempted?
    @run_attempted_this_turn
  end

  #-----------------------------------------------------------------------------
  # Reset turn-specific flags
  #-----------------------------------------------------------------------------
  def self.reset_turn
    @run_attempted_this_turn = false
  end

  #-----------------------------------------------------------------------------
  # Increment run command after failed attempt (called by initiator only)
  # Broadcasts the new value to all allies to keep counters synchronized
  #-----------------------------------------------------------------------------
  def self.increment_run_command(battle_id, turn)
    @synchronized_run_command += 1

    # Broadcast increment to all allies
    message = "COOP_RUN_INCREMENT:#{battle_id}|#{turn}|#{@synchronized_run_command}"
    MultiplayerClient.send_data(message, rate_limit_type: :RUN_AWAY) if defined?(MultiplayerClient)

    ##MultiplayerDebug.info("COOP-RUN", "Run command incremented to #{@synchronized_run_command}, broadcasted to allies")
  end

  #-----------------------------------------------------------------------------
  # Receive run command increment from network (non-initiators)
  #-----------------------------------------------------------------------------
  def self.receive_run_increment(battle_id, turn, new_value)
    @synchronized_run_command = new_value.to_i
    ##MultiplayerDebug.info("COOP-RUN", "Received run command increment: #{@synchronized_run_command}")
  end

  #-----------------------------------------------------------------------------
  # Receive run success notification from ally (non-initiators)
  # This is called when another player successfully runs away
  # Sets the battle decision to escape so all clients end battle together
  #-----------------------------------------------------------------------------
  def self.receive_run_success(battle_id, turn)
    ###MultiplayerDebug.info("COOP-RUN", "=" * 70)
    ##MultiplayerDebug.info("COOP-RUN", "Received RUN SUCCESS notification from ally")
    ##MultiplayerDebug.info("COOP-RUN", "  Battle ID: #{battle_id}")
    ##MultiplayerDebug.info("COOP-RUN", "  Turn: #{turn}")

    # Get the current battle instance from CoopBattleState
    if defined?(CoopBattleState) && CoopBattleState.battle_instance
      battle = CoopBattleState.battle_instance
      battle.decision = 3  # Escape
      ##MultiplayerDebug.info("COOP-RUN", "✓ Set battle.decision = 3 (escape)")
      ##MultiplayerDebug.info("COOP-RUN", "  All clients will now end battle")
    else
      ##MultiplayerDebug.warn("COOP-RUN", "WARNING: Could not access battle instance to set decision")
      ##MultiplayerDebug.warn("COOP-RUN", "  CoopBattleState.battle_instance is nil")
    end

    ###MultiplayerDebug.info("COOP-RUN", "=" * 70)
  end

  #-----------------------------------------------------------------------------
  # Reset counter at battle start
  #-----------------------------------------------------------------------------
  def self.reset_state
    @synchronized_run_command = 0
    @run_attempted_this_turn = false
    ##MultiplayerDebug.info("COOP-RUN", "Run command counter reset")
  end

  #-----------------------------------------------------------------------------
  # Export sync statistics (for debugging)
  #-----------------------------------------------------------------------------
  def self.export_stats
    {
      synchronized_run_command: @synchronized_run_command
    }
  end
end

##MultiplayerDebug.info("MODULE-19", "CoopRunAwaySync loaded - run attempt synchronization enabled")
