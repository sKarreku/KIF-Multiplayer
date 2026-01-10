#===============================================================================
# Status Effect Debug - Track status application and checks in coop battles
#===============================================================================

# DISABLED - Using 998_StatusSetter_Instrumentation.rb instead
# class PokeBattle_Battler
#   # Alias status= to log when status is set
#   alias status_debug_original_status= status=
#
#   def status=(value)
#     if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
#       old_status = @status
#       old_pkmn_status = @pokemon ? @pokemon.status : :NONE
#       #MultiplayerDebug.info("🔴 STATUS-SET", "►►► Battler##{@index} (#{@pokemon.name}): battler.status=#{old_status || :NONE}, pokemon.status=#{old_pkmn_status || :NONE} → setting #{value || :NONE} ◄◄◄")
#     end
#     status_debug_original_status=(value)
#     if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
#       new_status = @status
#       new_pkmn_status = @pokemon ? @pokemon.status : :NONE
#       #MultiplayerDebug.info("🔴 STATUS-SET-AFTER", "►►► Battler##{@index} (#{@pokemon.name}): battler.status=#{new_status || :NONE}, pokemon.status=#{new_pkmn_status || :NONE} ◄◄◄")
#     end
#   end
# end

# DISABLED - statusCount alias removed, 996 handles it
# class PokeBattle_Battler
#   alias status_debug_original_statusCount= statusCount=
#
#   def statusCount=(value)
#     if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
#       old_count = @statusCount
#       has_pokemon = !@pokemon.nil?
#       pkmn_count_before = @pokemon ? @pokemon.statusCount : "N/A"
#       pkmn_obj_id = @pokemon ? @pokemon.object_id : "N/A"
#       #MultiplayerDebug.info("🔴 STATUS-COUNT", "►►► Battler##{@index} (#{@pokemon ? @pokemon.name : 'NO-PKMN'}): count #{old_count} → #{value} (status=#{@status}), @pokemon.object_id=#{pkmn_obj_id}, pkmn.statusCount=#{pkmn_count_before} ◄◄◄")
#     end
#     status_debug_original_statusCount=(value)
#     if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
#       pkmn_count_after = @pokemon ? @pokemon.statusCount : "N/A"
#       if @pokemon && pkmn_count_after != value
#         #MultiplayerDebug.info("🔴 STATUS-COUNT-BUG", "►►► SYNC FAILED! Battler.statusCount=#{value} but Pokemon.statusCount=#{pkmn_count_after} ◄◄◄")
#       end
#       #MultiplayerDebug.info("🔴 STATUS-COUNT-AFTER", "►►► Battler##{@index}: pkmn.statusCount AFTER setter = #{pkmn_count_after} ◄◄◄")
#     end
#   end
# end

class PokeBattle_Battle
  # Alias pbAttackPhaseMoves to log status before each move execution
  alias status_debug_original_pbAttackPhaseMoves pbAttackPhaseMoves

  def pbAttackPhaseMoves
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      ##MultiplayerDebug.info("🔴 ATTACK-PHASE", "►►► Starting move execution phase ◄◄◄")
      @battlers.each_with_index do |b, idx|
        next unless b && !b.fainted?
        choice = @choices[idx]
        if choice && choice[0] == :UseMove
          move_name = choice[2] ? choice[2].name : "unknown"
          ##MultiplayerDebug.info("🔴 PRE-MOVE", "►►► Battler##{idx} (#{b.pokemon.name}): choice=UseMove(#{move_name}), status=#{b.status || :NONE}, count=#{b.statusCount} ◄◄◄")
        end
      end
    end
    status_debug_original_pbAttackPhaseMoves
  end

end

class PokeBattle_Battler
  # Alias pbUseMove to log status check during move execution
  alias status_debug_original_pbUseMove pbUseMove

  def pbUseMove(choice, specialUsage = false)
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      move_name = choice[2] ? choice[2].name : "unknown"
      ##MultiplayerDebug.info("🔴 USE-MOVE", "►►► Battler##{@index} (#{@pokemon.name}): executing #{move_name}, status=#{@status || :NONE}, count=#{@statusCount} ◄◄◄")
    end
    status_debug_original_pbUseMove(choice, specialUsage)
  end
end

##MultiplayerDebug.info("MODULE-999", "Status effect debug logging loaded")
