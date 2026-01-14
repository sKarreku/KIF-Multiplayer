#===============================================================================
# MODULE: Family Type Infusion System
#===============================================================================
# STAB moves gain a secondary type from the Family's type pool for dual-type damage.
# Type selection is deterministic based on best effectiveness against target.
#===============================================================================

#===============================================================================
# PokeBattle_Move - Add infused_type attribute
#===============================================================================

class PokeBattle_Move
  attr_accessor :infused_type  # Track infused type for this move usage

  # Hook type effectiveness calculation to add infused type
  alias family_infusion_original_pbCalcTypeModSingle pbCalcTypeModSingle
  def pbCalcTypeModSingle(moveType, defType, user, target)
    ret = family_infusion_original_pbCalcTypeModSingle(moveType, defType, user, target)

    # Apply infused type effectiveness (multiplicative, like Flying Press)
    if @infused_type && @infused_type != moveType
      infused_eff = Effectiveness.calculate_one(@infused_type, defType)
      ret *= infused_eff.to_f / Effectiveness::NORMAL_EFFECTIVE_ONE
    end

    return ret
  end
end

#===============================================================================
# PokeBattle_Battler - Type Infusion Logic
#===============================================================================

class PokeBattle_Battler
  # Hook move usage to determine type infusion
  alias family_infusion_original_pbUseMove pbUseMove
  def pbUseMove(choice, specialUsage=false)
    move = choice[2]

    if move && should_infuse_type?(move)
      # Target index is in choice[4] for this battle system
      # choice = [:UseMove, move_index, move_object, -1, target_idx]
      target_idx = choice[4]
      infused_type = calculate_best_infused_type(move, target_idx)

      if infused_type
        move.infused_type = infused_type
        type_name = GameData::Type.get(infused_type).name
        @battle.pbDisplay(_INTL("{1} infused the attack with {2} energy!",
                                self.pbThis, type_name))
      end
    end

    # Call original
    family_infusion_original_pbUseMove(choice, specialUsage)

    # Clear infusion after use
    move.infused_type = nil if move
  end

  private

  # Check if type infusion should apply to this move
  def should_infuse_type?(move)
    return false unless PokemonFamilyConfig::ENABLE_TALENT_INFUSION
    return false unless PokemonFamilyConfig::FAMILY_SYSTEM_ENABLED
    return false unless self.pokemon && self.pokemon.has_family?
    return false unless move.damagingMove?

    # Skip moves that transform into other moves (Metronome, Mirror Move, etc.)
    # These need to execute first before we can determine their type
    return false if move.function_code == "UseRandomMove" # Metronome
    return false if move.function_code == "UseLastMoveUsedByTarget" # Mirror Move
    return false if move.function_code == "UseLastMoveUsed" # Copycat
    return false if move.function_code == "UseMoveTargetIsAboutToUse" # Me First

    move_type = move.pbCalcType(self) rescue nil
    return false unless move_type

    # Special case: Protean/Panmorphosis makes EVERY move STAB (changes type before move)
    return true if @ability_id == :PROTEAN || @ability_id == :PANMORPHOSIS

    # Normal case: Only infuse STAB moves (move type matches user's natural type)
    return self.pbHasType?(move_type)
  end

  # Calculate best infused type based on effectiveness against target
  def calculate_best_infused_type(move, target_idx)
    return nil unless target_idx >= 0

    target = @battle.battlers[target_idx]
    return nil unless target && !target.fainted?

    family = self.pokemon.family
    family_types = PokemonFamilyConfig.get_family_types(family)
    return nil if family_types.empty?

    # Safely get move type
    move_type = move.pbCalcType(self) rescue nil
    return nil unless move_type

    best_type = nil
    best_effectiveness = 0

    family_types.each do |f_type|
      next if f_type == move_type  # Don't infuse with same type as move

      # Calculate total effectiveness against target's types
      total_eff = Effectiveness.calculate(f_type, *target.pbTypes(true))

      # Pick highest effectiveness (most damage)
      if total_eff > best_effectiveness
        best_effectiveness = total_eff
        best_type = f_type
      end
    end

    return best_type
  end
end

# Module loaded successfully
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("FAMILY-TALENT", "=" * 60)
  MultiplayerDebug.info("FAMILY-TALENT", "112_Family_Type_Infusion.rb loaded")
  MultiplayerDebug.info("FAMILY-TALENT", "Type infusion system implemented:")
  MultiplayerDebug.info("FAMILY-TALENT", "  - STAB moves gain secondary type from Family pool")
  MultiplayerDebug.info("FAMILY-TALENT", "  - Type selection based on best effectiveness vs target")
  MultiplayerDebug.info("FAMILY-TALENT", "  - Dual-type damage calculation (multiplicative)")
  MultiplayerDebug.info("FAMILY-TALENT", "  - Message displayed on every infusion")
  MultiplayerDebug.info("FAMILY-TALENT", "=" * 60)
end
