#===============================================================================
# Status Setter Instrumentation - Track EXACTLY what happens in status= setter
#===============================================================================

class PokeBattle_Battler
  # Remove previous alias and completely override the setter for debugging
  remove_method :status= if method_defined?(:status=)

  def status=(value)
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      ##MultiplayerDebug.info("🔵 STATUS-SETTER", "►►► START: value=#{value}, @status=#{@status}, @pokemon.status=#{@pokemon ? @pokemon.status : 'nil'} ◄◄◄")
    end

    # Line 116
    @effects[PBEffects::Truant] = false if @status == :SLEEP && value != :SLEEP && (!$PokemonSystem.drowsy || $PokemonSystem.drowsy == 0)

    # Line 117
    @effects[PBEffects::Toxic]  = 0 if value != :POISON

    # Line 118
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      ##MultiplayerDebug.info("🔵 STATUS-SETTER", "►►► BEFORE @status=value: @status=#{@status} ◄◄◄")
    end
    @status = value
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      ##MultiplayerDebug.info("🔵 STATUS-SETTER", "►►► AFTER @status=value: @status=#{@status} ◄◄◄")
    end

    # Line 119
    if @pokemon
      if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
        ##MultiplayerDebug.info("🔵 STATUS-SETTER", "►►► BEFORE @pokemon.status=value: @pokemon.status=#{@pokemon.status} ◄◄◄")
      end
      @pokemon.status = value
      if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
        ##MultiplayerDebug.info("🔵 STATUS-SETTER", "►►► AFTER @pokemon.status=value: @pokemon.status=#{@pokemon.status} ◄◄◄")
      end
    end

    # Line 120
    if value != :POISON && value != :SLEEP
      if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
        ##MultiplayerDebug.info("🔵 STATUS-SETTER", "►►► CALLING self.statusCount=0 ◄◄◄")
      end
      self.statusCount = 0
    end

    # Line 121
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      ##MultiplayerDebug.info("🔵 STATUS-SETTER", "►►► BEFORE pbRefreshOne: @status=#{@status}, @pokemon.status=#{@pokemon ? @pokemon.status : 'nil'} ◄◄◄")
    end
    @battle.scene.pbRefreshOne(@index)
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      ##MultiplayerDebug.info("🔵 STATUS-SETTER", "►►► AFTER pbRefreshOne: @status=#{@status}, @pokemon.status=#{@pokemon ? @pokemon.status : 'nil'} ◄◄◄")
    end

    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      ##MultiplayerDebug.info("🔵 STATUS-SETTER", "►►► END: @status=#{@status}, @pokemon.status=#{@pokemon ? @pokemon.status : 'nil'} ◄◄◄")
    end
  end
end

##MultiplayerDebug.info("MODULE-998", "Status setter instrumentation loaded - direct override mode")
