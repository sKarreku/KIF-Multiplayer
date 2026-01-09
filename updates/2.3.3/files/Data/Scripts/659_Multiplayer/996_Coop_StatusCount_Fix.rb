#===============================================================================
# Coop StatusCount Fix - Skip Pokemon sync for statusCount in coop battles
#===============================================================================
# Root cause: Each client has separate Pokemon object copies from party snapshots.
# Writing to @pokemon.statusCount only updates the local copy, not remote copies.
# Fix: In coop battles, store statusCount purely in Battler (which IS synchronized).
#===============================================================================

class PokeBattle_Battler
  # Override getter to log reads in coop
  def statusCount
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      ##MultiplayerDebug.info("🟢 GETTER", "►►► Battler##{@index} statusCount getter: @statusCount=#{@statusCount}, CALLER: #{caller[0]} ◄◄◄")
    end
    @statusCount
  end

  # Override setter to skip Pokemon sync in coop
  alias coop_statuscount_fix_original_statusCount= statusCount=

  def statusCount=(value)
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      ##MultiplayerDebug.info("🟢 SETTER", "►►► Battler##{@index} statusCount setter: #{@statusCount} → #{value}, CALLER: #{caller[0]}  ◄◄◄")
    end
    @statusCount = value
    # Skip Pokemon sync in coop battles - Pokemon objects are per-client copies
    if !defined?(CoopBattleState) || !CoopBattleState.in_coop_battle?
      @pokemon.statusCount = value if @pokemon
    end
    @battle.scene.pbRefreshOne(@index)
  end

  # Override initialization to NOT read statusCount from Pokemon in coop
  alias coop_statuscount_fix_original_pbInitPokemon pbInitPokemon

  def pbInitPokemon(pkmn, idxParty)
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      old_count = @statusCount
      ##MultiplayerDebug.info("🟢 INIT-PKMN", "►►► BEFORE pbInitPokemon: Battler##{@index} @statusCount=#{old_count} ◄◄◄")
    end
    coop_statuscount_fix_original_pbInitPokemon(pkmn, idxParty)
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      count_from_pkmn = @statusCount
      # In coop battles, statusCount stays in Battler - reset to 0 on switch-in
      @statusCount = 0
      ##MultiplayerDebug.info("🟢 INIT-PKMN", "►►► AFTER pbInitPokemon: Battler##{@index} count_from_pkmn=#{count_from_pkmn}, forced to 0 ◄◄◄")
    end
  end
end

##MultiplayerDebug.info("MODULE-996", "StatusCount coop fix loaded - skip Pokemon sync in coop battles")
