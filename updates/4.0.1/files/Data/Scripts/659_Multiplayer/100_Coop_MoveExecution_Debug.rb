#===============================================================================
# Move Execution Debug Logging
#===============================================================================
# Logs which battler is executing a move to track execution order
#===============================================================================

class PokeBattle_Battler
  alias coop_debug_original_pbProcessTurn pbProcessTurn if method_defined?(:pbProcessTurn)

  def pbProcessTurn(choice, tryFlee = true)
    # Log move execution start
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle? && defined?(RNGLog)
      role = CoopBattleState.am_i_initiator? ? "INIT" : "NON"
      move_name = choice[2] ? choice[2].name : "none"
      RNGLog.write("[MOVE-EXEC][#{role}][T#{@battle.turnCount}] b#{@index} using #{move_name}")
    end

    # Call original
    coop_debug_original_pbProcessTurn(choice, tryFlee)
  end
end

##MultiplayerDebug.info("MODULE-100", "Move execution debug logging loaded")
