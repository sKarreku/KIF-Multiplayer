#===============================================================================
# MODULE: PvP Battle Forfeit Synchronization
#===============================================================================
# Handles forfeits in PvP battles. When a player forfeits:
# - Sends PVP_FORFEIT message to opponent
# - Opponent receives it and ends battle immediately (they win)
# - Prevents the "waiting for action" bug when one player forfeits
#===============================================================================

module PvPForfeitSync
  @forfeit_received = false
  @forfeit_from = nil

  #-----------------------------------------------------------------------------
  # Send forfeit to opponent
  #-----------------------------------------------------------------------------
  def self.send_forfeit(battle_id)
    return unless defined?(MultiplayerClient)
    return unless defined?(PvPBattleState) && PvPBattleState.in_pvp_battle?

    message = "PVP_FORFEIT:#{battle_id}"
    MultiplayerClient.send_data(message)

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-FORFEIT", "Sent forfeit to opponent")
    end
  end

  #-----------------------------------------------------------------------------
  # Receive forfeit from opponent (called from network handler)
  #-----------------------------------------------------------------------------
  def self.receive_forfeit(battle_id)
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-FORFEIT", "Received forfeit from opponent!")
    end

    # Validate battle context
    if defined?(PvPBattleState)
      unless PvPBattleState.battle_id == battle_id
        if defined?(MultiplayerDebug)
          MultiplayerDebug.warn("PVP-FORFEIT", "Battle ID mismatch - ignoring forfeit")
        end
        return false
      end
    end

    @forfeit_received = true
    @forfeit_from = PvPBattleState.opponent_sid

    # Immediately end the battle - we WIN because opponent forfeited
    if defined?(PvPBattleState) && PvPBattleState.battle_instance
      battle = PvPBattleState.battle_instance

      # Decision 1 = Win for player
      battle.decision = 1

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-FORFEIT", "Battle decision set to 1 (win) - opponent forfeited")
      end
    else
      if defined?(MultiplayerDebug)
        MultiplayerDebug.warn("PVP-FORFEIT", "No battle instance to set decision on")
      end
    end

    true
  end

  #-----------------------------------------------------------------------------
  # Check if opponent forfeited (called from action sync wait loop)
  #-----------------------------------------------------------------------------
  def self.opponent_forfeited?
    @forfeit_received
  end

  #-----------------------------------------------------------------------------
  # Reset forfeit state (called when battle ends)
  #-----------------------------------------------------------------------------
  def self.reset
    @forfeit_received = false
    @forfeit_from = nil
  end
end

#===============================================================================
# Hook pbRun for PvP battles - forfeit handling
#===============================================================================
class PokeBattle_Battle
  alias pvp_original_pbRun pbRun unless method_defined?(:pvp_original_pbRun)

  def pbRun(idxBattler, duringBattle = false)
    # If not in PvP battle, use original/coop behavior
    unless defined?(PvPBattleState) && PvPBattleState.in_pvp_battle?
      return pvp_original_pbRun(idxBattler, duringBattle)
    end

    battler = @battlers[idxBattler]

    # Only player's battlers can forfeit (not opponent's)
    if battler.opposes?
      return pvp_original_pbRun(idxBattler, duringBattle)
    end

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-FORFEIT", "Player chose to forfeit PvP battle")
    end

    # Broadcast forfeit to opponent
    battle_id = PvPBattleState.battle_id
    PvPForfeitSync.send_forfeit(battle_id)

    # Small delay to allow message to send
    sleep(0.05)

    # Display forfeit message
    pbDisplay(_INTL("{1} forfeited the battle!", pbPlayer.name))

    # Mark as loss (opponent wins)
    @decision = 2

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-FORFEIT", "Battle decision set to 2 (loss)")
    end

    return 1  # Return success (forfeit always succeeds)
  end
end

#-------------------------------------------------------------------------------
# Module loaded successfully
#-------------------------------------------------------------------------------
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("PVP-FORFEIT", "=" * 60)
  MultiplayerDebug.info("PVP-FORFEIT", "130_PvP_ForfeitSync.rb loaded")
  MultiplayerDebug.info("PVP-FORFEIT", "PvP forfeit synchronization enabled")
  MultiplayerDebug.info("PVP-FORFEIT", "=" * 60)
end
