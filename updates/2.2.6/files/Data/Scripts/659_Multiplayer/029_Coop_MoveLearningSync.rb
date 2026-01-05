#===============================================================================
# MODULE 15: Coop Battle Move Learning Synchronization
#===============================================================================
# Handles in-battle move learning sync to prevent desync when Pokemon learn new moves
# Owner makes the decision (which move to replace), allies update their battlers immediately
#===============================================================================

module CoopMoveLearningSync
  #-----------------------------------------------------------------------------
  # Receive move learning sync from owner
  # Updates both Pokemon object and active battler to prevent desync
  #-----------------------------------------------------------------------------
  def self.receive_move_sync(from_sid, battle_id, idxParty, move_id, slot)
    ##MultiplayerDebug.info("COOP-MOVE-SYNC", "Received move sync from #{from_sid}: party=#{idxParty}, move=#{move_id}, slot=#{slot}")

    # Validate battle context
    return false unless defined?(CoopBattleState)
    return false unless CoopBattleState.in_coop_battle?

    current_battle_id = CoopBattleState.battle_id
    unless current_battle_id == battle_id
      ##MultiplayerDebug.warn("COOP-MOVE-SYNC", "Battle ID mismatch: expected #{current_battle_id}, got #{battle_id}")
      return false
    end

    battle = CoopBattleState.battle_instance
    return false unless battle

    # Get Pokemon from the global battle party (same as pbGainExpOne uses)
    # idxParty is the index in pbParty(0), which is the concatenated party of all players
    pkmn = battle.pbParty(0)[idxParty]
    unless pkmn
      ##MultiplayerDebug.warn("COOP-MOVE-SYNC", "Pokemon at battle party index #{idxParty} is nil")
      return false
    end

    # Update the Pokemon object's move
    old_move_name = pkmn.moves[slot] ? pkmn.moves[slot].name : "empty"
    pkmn.moves[slot] = Pokemon::Move.new(move_id)
    new_move_name = GameData::Move.get(move_id).name

    ##MultiplayerDebug.info("COOP-MOVE-SYNC", "Updated #{pkmn.name}'s slot #{slot}: #{old_move_name} → #{new_move_name}")

    # Find and update the active battler if this Pokemon is in battle
    battler = battle.pbFindBattler(idxParty)
    if battler
      # Update the battler's move
      battler.moves[slot] = PokeBattle_Move.from_pokemon_move(battle, pkmn.moves[slot])
      battler.pbCheckFormOnMovesetChange if battler.respond_to?(:pbCheckFormOnMovesetChange)

      ##MultiplayerDebug.info("COOP-MOVE-SYNC", "Updated battler #{battler.index}'s move slot #{slot} to #{new_move_name}")

      # Refresh battle display
      begin
        battle.scene.pbRefreshOne(battler.index) if battle.scene.respond_to?(:pbRefreshOne)
      rescue => e
        ##MultiplayerDebug.warn("COOP-MOVE-SYNC", "Failed to refresh display: #{e.message}")
      end
    else
      ##MultiplayerDebug.info("COOP-MOVE-SYNC", "Pokemon not currently in battle (benched)")
    end

    true
  end
end

##MultiplayerDebug.info("MODULE-15", "Coop move learning sync loaded")
