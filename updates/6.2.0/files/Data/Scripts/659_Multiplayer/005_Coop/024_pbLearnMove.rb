#===============================================================================
# pbLearnMove Alias - Suppress ALL UI for ally Pokemon in coop battles
#===============================================================================
# Allies learn moves silently without prompts
# Owner makes decisions and syncs via COOP_MOVE_SYNC when needed
#===============================================================================

class PokeBattle_Battle
  # Save original method
  alias coop_original_pbLearnMove pbLearnMove

  def pbLearnMove(idxParty, newMove)
    pkmn = pbParty(0)[idxParty]
    return if !pkmn

    # Check if this is an ally's Pokemon in a coop battle
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      my_party = $Trainer.party
      is_ally_pokemon = !my_party.include?(pkmn)

      if is_ally_pokemon
        # Ally Pokemon - learn silently without any UI
        battler = pbFindBattler(idxParty)

        # Skip if already knows the move
        return if pkmn.moves.any? { |m| m && m.id == newMove }

        if pkmn.moves.length < Pokemon::MAX_MOVES
          # Has empty slot - add move silently
          pkmn.moves.push(Pokemon::Move.new(newMove))
          if battler
            battler.moves.push(PokeBattle_Move.from_pokemon_move(self, pkmn.moves.last))
            battler.pbCheckFormOnMovesetChange
          end
          ##MultiplayerDebug.info("COOP-MOVE-LEARN", "Ally's #{pkmn.name} learned #{GameData::Move.get(newMove).name} silently")
        else
          # Has 4 moves - wait for owner's COOP_MOVE_SYNC
          ##MultiplayerDebug.info("COOP-MOVE-LEARN", "Ally's #{pkmn.name} wants to learn #{GameData::Move.get(newMove).name} - waiting for owner's sync")
        end
        return
      end
    end

    # It's our Pokemon - use original behavior with full UI
    coop_original_pbLearnMove(idxParty, newMove)
  end
end

##MultiplayerDebug.info("MODULE-100", "pbLearnMove alias loaded - suppresses UI for all ally Pokemon")
