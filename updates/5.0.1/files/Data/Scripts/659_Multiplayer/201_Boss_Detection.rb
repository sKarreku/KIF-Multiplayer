#===============================================================================
# MODULE 2: Boss Pokemon System - Detection
#===============================================================================
# Adds boss-related attributes and methods to the Pokemon class.
# Simple flag system for marking and checking boss status.
#
# Test: Debug console:
#   p = Pokemon.new(:CHARIZARD, 50)
#   p.boss_data = { hp_phase: 4, shields: 0 }
#   p.is_boss?  # => true
#===============================================================================

MultiplayerDebug.info("BOSS", "Loading 201_Boss_Detection.rb...") if defined?(MultiplayerDebug)

class Pokemon
  #=============================================================================
  # Boss Data Attribute
  #=============================================================================
  # nil for normal Pokemon, hash for boss Pokemon containing:
  # - :hp_phase      - Current HP phase (4 to 1, 0 = defeated)
  # - :shields       - Current shield count (0-7)
  # - :stat_mults    - Stat multipliers applied
  # - :loot_options  - Pre-rolled loot choices for voting
  # - :battle_id     - Server-tracked battle ID
  # - :all_moves     - Full moveset (all learnable moves)
  attr_accessor :boss_data

  #=============================================================================
  # Boss Detection
  #=============================================================================
  def is_boss?
    !@boss_data.nil?
  end

  #=============================================================================
  # Boss HP Phase (4 phases = 4 HP bars)
  #=============================================================================
  def boss_hp_phase
    return 0 unless @boss_data
    @boss_data[:hp_phase] || 0
  end

  def boss_hp_phase=(val)
    return unless @boss_data
    @boss_data[:hp_phase] = val
  end

  #=============================================================================
  # Boss Shields (7 shields per phase)
  #=============================================================================
  def boss_shields
    return 0 unless @boss_data
    @boss_data[:shields] || 0
  end

  def boss_shields=(val)
    return unless @boss_data
    @boss_data[:shields] = [val, 0].max
  end

  #=============================================================================
  # Boss Battle ID (for server tracking)
  #=============================================================================
  def boss_battle_id
    return nil unless @boss_data
    @boss_data[:battle_id]
  end

  def boss_battle_id=(val)
    return unless @boss_data
    @boss_data[:battle_id] = val
  end

  #=============================================================================
  # Boss Loot Options (pre-rolled at spawn)
  #=============================================================================
  def boss_loot_options
    return [] unless @boss_data
    @boss_data[:loot_options] || []
  end

  #=============================================================================
  # Boss Stat Multipliers
  #=============================================================================
  def boss_stat_mults
    return nil unless @boss_data
    @boss_data[:stat_mults]
  end

  #=============================================================================
  # Boss Max Shields (level-based cap)
  #=============================================================================
  def boss_max_shields
    return 0 unless @boss_data
    @boss_data[:max_shields] || BossConfig::SHIELDS_PER_PHASE
  end

  #=============================================================================
  # Boss Shield Damage Reduction (player-count-based)
  #=============================================================================
  def boss_shield_dr
    return 0.50 unless @boss_data
    @boss_data[:shield_dr] || 0.50
  end

  #=============================================================================
  # Boss All Moves (full moveset access)
  #=============================================================================
  def boss_all_moves
    return [] unless @boss_data
    @boss_data[:all_moves] || []
  end

  def boss_all_moves=(moves)
    return unless @boss_data
    @boss_data[:all_moves] = moves
  end

  #=============================================================================
  # Initialize Boss Data
  #=============================================================================
  # Call this to mark a Pokemon as a boss with default values
  def make_boss!(player_count = 1)
    @boss_data = {
      hp_phase: BossConfig::HP_PHASES,
      shields: 0,
      max_shields: BossConfig.shields_for_level(self.level),
      shield_dr: BossConfig.shield_dr(player_count),
      stat_mults: BossConfig.get_multipliers(player_count),
      loot_options: BossConfig.generate_loot_options,
      battle_id: nil,
      all_moves: []
    }
  end

  #=============================================================================
  # Clear Boss Data
  #=============================================================================
  def clear_boss!
    @boss_data = nil
  end
end

#===============================================================================
# PokeBattle_Battler Extension
#===============================================================================
# Mirror boss methods to battler for easy access during battle
class PokeBattle_Battler
  def is_boss?
    return false unless @pokemon
    @pokemon.is_boss?
  end

  def boss_hp_phase
    return 0 unless @pokemon
    @pokemon.boss_hp_phase
  end

  def boss_hp_phase=(val)
    return unless @pokemon
    @pokemon.boss_hp_phase = val
  end

  def boss_shields
    return 0 unless @pokemon
    @pokemon.boss_shields
  end

  def boss_shields=(val)
    return unless @pokemon
    @pokemon.boss_shields = val
  end

  def boss_battle_id
    return nil unless @pokemon
    @pokemon.boss_battle_id
  end

  def boss_loot_options
    return [] unless @pokemon
    @pokemon.boss_loot_options
  end

  def boss_max_shields
    return 0 unless @pokemon
    @pokemon.boss_max_shields
  end

  def boss_shield_dr
    return 0.50 unless @pokemon
    @pokemon.boss_shield_dr
  end

  def boss_all_moves
    return [] unless @pokemon
    @pokemon.boss_all_moves
  end
end
