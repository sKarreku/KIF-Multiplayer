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
    # Safety checks to prevent crashes on multi-hit moves or edge cases
    if @infused_type && @infused_type != moveType && defType
      # Verify type exists before calculating (like Flying Press does)
      if GameData::Type.exists?(@infused_type)
        begin
          infused_eff = Effectiveness.calculate_one(@infused_type, defType)
          ret *= infused_eff.to_f / Effectiveness::NORMAL_EFFECTIVE_ONE
        rescue => e
          # Silently fail if effectiveness calculation crashes
          if defined?(MultiplayerDebug)
            MultiplayerDebug.warn("TYPE-INFUSION", "Effectiveness calc failed: #{e.message}")
          end
        end
      end
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
    # Check runtime Family Abilities setting first (from $PokemonSystem)
    if defined?($PokemonSystem) && $PokemonSystem && $PokemonSystem.respond_to?(:mp_family_abilities_enabled)
      return false if $PokemonSystem.mp_family_abilities_enabled == 0
    elsif defined?(PokemonFamilyConfig)
      return false unless PokemonFamilyConfig.talent_infusion_enabled?
    end

    # Check runtime Family System setting
    if defined?($PokemonSystem) && $PokemonSystem && $PokemonSystem.respond_to?(:mp_family_enabled)
      return false if $PokemonSystem.mp_family_enabled == 0
    elsif defined?(PokemonFamilyConfig)
      return false unless PokemonFamilyConfig.system_enabled?
    end

    return false unless self.pokemon && self.pokemon.respond_to?(:has_family_data?) && self.pokemon.has_family_data?
    return false unless move.damagingMove?

    # Skip moves that transform into other moves (Metronome, Mirror Move, etc.)
    # These need to execute first before we can determine their type
    # Note: Use @function (hex codes) not function_code (string names)
    move_func = move.function rescue nil
    return false if move_func == "0B6" # Metronome (UseRandomMove)
    return false if move_func == "0B4" # Mirror Move (UseLastMoveUsedByTarget)
    return false if move_func == "0AE" # Copycat (UseLastMoveUsed)
    return false if move_func == "0B5" # Me First (UseMoveTargetIsAboutToUse)

    move_type = move.pbCalcType(self) rescue nil
    return false unless move_type

    # Special case: Protean/Panmorphosis makes EVERY move STAB (changes type before move)
    return true if @ability_id == :PROTEAN || @ability_id == :PANMORPHOSIS

    # Normal case: Only infuse STAB moves (move type matches user's natural type)
    return self.pbHasType?(move_type)
  end

  # Calculate best infused type based on effectiveness against target
  def calculate_best_infused_type(move, target_idx)
    return nil unless target_idx && target_idx >= 0

    target = @battle.battlers[target_idx] rescue nil
    return nil unless target && !target.fainted?

    family = self.pokemon.family rescue nil
    return nil unless family

    family_types = PokemonFamilyConfig.get_family_types(family) rescue []
    return nil if family_types.nil? || family_types.empty?

    # Safely get move type
    move_type = move.pbCalcType(self) rescue nil
    return nil unless move_type

    # Safely get target types
    target_types = target.pbTypes(true) rescue nil
    return nil unless target_types && !target_types.empty?

    best_type = nil
    best_effectiveness = 0

    family_types.each do |f_type|
      next if f_type == move_type  # Don't infuse with same type as move
      next unless GameData::Type.exists?(f_type)  # Verify type is valid

      begin
        # Calculate total effectiveness against target's types
        total_eff = Effectiveness.calculate(f_type, *target_types)

        # Pick highest effectiveness (most damage)
        if total_eff > best_effectiveness
          best_effectiveness = total_eff
          best_type = f_type
        end
      rescue
        # Skip this type if calculation fails
        next
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
