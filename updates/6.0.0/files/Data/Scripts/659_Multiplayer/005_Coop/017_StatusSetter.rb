#===============================================================================
# Status Setter Instrumentation - Direct override of status= setter
#===============================================================================
# Uses remove_method pattern — ISOLATED from other files to avoid conflicts
#===============================================================================

class PokeBattle_Battler
  # Remove previous alias and completely override the setter
  remove_method :status= if method_defined?(:status=)

  def status=(value)
    # Line 116
    @effects[PBEffects::Truant] = false if @status == :SLEEP && value != :SLEEP && (!$PokemonSystem.drowsy || $PokemonSystem.drowsy == 0)

    # Line 117
    @effects[PBEffects::Toxic]  = 0 if value != :POISON

    # Line 118
    @status = value

    # Line 119
    if @pokemon
      @pokemon.status = value
    end

    # Line 120
    if value != :POISON && value != :SLEEP
      self.statusCount = 0
    end

    # Line 121
    @battle.scene.pbRefreshOne(@index)
  end
end
