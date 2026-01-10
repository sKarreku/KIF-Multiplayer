#===============================================================================
# MODULE 22: Whiteout Detection
#===============================================================================
# Detects when the local player's entire party faints in a coop battle
# Marks the player as whited out for post-battle handling
#===============================================================================

class PokeBattle_Battler
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

    # Debug: Log faint event
    ##MultiplayerDebug.info("COOP-WHITEOUT", "Pokemon fainted (#{@pokemon.name}), checking if player whited out...")
    ##MultiplayerDebug.info("COOP-WHITEOUT", "  My battler index: #{my_battler_index}")

    # Check if ALL of THIS trainer's Pokemon are now fainted
    # IMPORTANT: Use my_battler_index, not 0! (0 is always the initiator)
    all_fainted = @battle.pbTrainerAllFainted?(my_battler_index)
    ##MultiplayerDebug.info("COOP-WHITEOUT", "  pbTrainerAllFainted?(#{my_battler_index}) = #{all_fainted}")

    if all_fainted
      ##MultiplayerDebug.info("COOP-WHITEOUT", "=" * 70)
      ##MultiplayerDebug.info("COOP-WHITEOUT", "ALL PLAYER POKEMON FAINTED")
      ##MultiplayerDebug.info("COOP-WHITEOUT", "  Player has whited out")
      ##MultiplayerDebug.info("COOP-WHITEOUT", "  Entering spectator mode")
      ##MultiplayerDebug.info("COOP-WHITEOUT", "=" * 70)

      # Mark that this player whited out
      CoopBattleState.mark_whiteout
    end
  end
end

##MultiplayerDebug.info("MODULE-22", "Whiteout detection loaded")
