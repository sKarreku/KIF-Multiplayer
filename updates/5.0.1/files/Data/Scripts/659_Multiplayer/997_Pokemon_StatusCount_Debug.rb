#===============================================================================
# Pokemon StatusCount Debug - Track when Pokemon.statusCount is modified
#===============================================================================

class Pokemon
  alias status_count_debug_original_statusCount= statusCount=

  def statusCount=(value)
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      old_count = @statusCount
      ##MultiplayerDebug.info("🟡 PKMN-COUNT", "►►► Pokemon #{@name}: statusCount #{old_count} → #{value} (status=#{@status}) CALLER: #{caller[0..2].join(' | ')} ◄◄◄")
    end
    status_count_debug_original_statusCount=(value)
  end
end

#MultiplayerDebug.info("MODULE-997", "Pokemon statusCount debug loaded")
