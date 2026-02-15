#===============================================================================
# MODULE 1: Boss Pokemon System - Configuration
#===============================================================================
# Central configuration for Boss Pokemon encounters.
# Contains all constants, loot tables, blocked moves, and stat multipliers.
#
# Test: Start game, debug console: BossConfig::SPAWN_CHANCE => 50
#===============================================================================

MultiplayerDebug.info("BOSS", "Loading 200_Boss_Config.rb...") if defined?(MultiplayerDebug)

module BossConfig

  #=============================================================================
  # Core Settings
  #=============================================================================
  SPAWN_CHANCE = 25           # 1 in X wild encounters becomes a boss (set to 2 for 50/50 testing)
  HP_PHASES = 4               # Number of HP bars to deplete
  SHIELDS_PER_PHASE = 7       # Pink shields that appear after each phase
  SHIELD_DMG_NORMAL = 1       # Shields removed per normal attack
  SHIELD_DMG_SUPER = 2        # Shields removed per super effective (x2 or x4)
  ACTIONS_PER_TURN = 2        # Boss attacks per turn
  LIVES_PER_PLAYER = 3        # Pokemon each player can use before spectating
  VOTE_SECONDS = 10           # Loot voting timer
  LEVEL_BONUS = 5             # Added to party average for boss level
  MIN_BATTLE_DURATION = 120   # Minimum seconds before reward (anti-cheat)

  #=============================================================================
  # Stat Multipliers by Player Count
  #=============================================================================
  # Higher player count = tankier boss but lower per-player scaling
  # atk/spatk reduced to ~55% to prevent low-level bosses from one-shotting
  MULTIPLIERS = {
    1 => { hp: 2.0, def: 1.5, spdef: 1.5, atk: 0.55, spatk: 0.55, speed: 1.0 },
    2 => { hp: 3.0, def: 1.3, spdef: 1.3, atk: 0.60, spatk: 0.60, speed: 0.9 },
    3 => { hp: 4.0, def: 1.2, spdef: 1.2, atk: 0.65, spatk: 0.65, speed: 0.8 }
  }

  #=============================================================================
  # Level-Based Shield Scaling
  #=============================================================================
  # Low-level bosses get fewer shields so fights aren't unreasonably long
  SHIELDS_BY_LEVEL = {
    low:  3,   # Level < 30
    mid:  5,   # Level 30-59
    high: 7    # Level 60+
  }

  def self.shields_for_level(level)
    if level < 30
      SHIELDS_BY_LEVEL[:low]
    elsif level < 60
      SHIELDS_BY_LEVEL[:mid]
    else
      SHIELDS_BY_LEVEL[:high]
    end
  end

  #=============================================================================
  # Shield Damage Reduction (% of damage blocked while shields are active)
  #=============================================================================
  # Shields reduce incoming damage instead of full immunity.
  # More players = higher DR to keep the boss challenging.
  SHIELD_DR = {
    1 => 0.50,   # Solo: 50% damage reduction
    2 => 0.60,   # Duo: 60% damage reduction
    3 => 0.70    # Trio: 70% damage reduction
  }

  def self.shield_dr(player_count)
    count = [[player_count, 1].max, 3].min
    SHIELD_DR[count]
  end

  #=============================================================================
  # Blocked Moves (comprehensive list)
  #=============================================================================
  # These moves automatically fail when targeting a boss Pokemon
  BLOCKED_MOVES = %i[
    FISSURE SHEERCOLD HORNDRILL GUILLOTINE
    PERISHSONG DESTINYBOND
    COUNTER MIRRORCOAT METALBURST
    ENDEAVOR PAINSPLIT
  ]

  # Moves bosses cannot use (self-KO / suicide moves)
  BOSS_BANNED_MOVES = %i[
    SELFDESTRUCT EXPLOSION MISTYEXPLOSION
    MEMENTO FINALGAMBIT HEALINGWISH LUNARDANCE
  ]

  #=============================================================================
  # Curated Held Items Pool
  #=============================================================================
  # Boss Pokemon randomly receive one of these strong items
  HELD_ITEMS = %i[
    LEFTOVERS LIFEORB CHOICEBAND CHOICESPECS
    ASSAULTVEST FOCUSSASH ROCKYHELMET EXPERTBELT
    SITRUSBERRY LUMBERRY WEAKNESSPOLICY AIRBALLOON
  ]

  #=============================================================================
  # Loot Table with Weighted Rarities
  #=============================================================================
  # Each rarity has a weight for random selection
  # Total weight = 100 for easy percentage reading
  LOOT = {
    common:    { item: :ULTRABALL,    qty: 5,  weight: 45 },
    uncommon:  { item: :RARECANDY,    qty: 2,  weight: 30 },
    rare:      { pool: [:PPMAX, :SHINY_EGG], qty: 1, weight: 15 },
    epic:      { pool: %i[LEFTOVERS LIFEORB CHOICEBAND CHOICESPECS ASSAULTVEST FOCUSSASH ROCKYHELMET EXPERTBELT WEAKNESSPOLICY AIRBALLOON], qty: 1, weight: 8 },
    legendary: { pool: [:MASTERBALL, :SHINY_LEGENDARY_EGG] + BloodboundCatalysts::ALL_ITEMS, qty: 1, weight: 2 }
  }

  #=============================================================================
  # Special Rewards (non-item loot like eggs)
  #=============================================================================
  SPECIAL_REWARDS = {
    SHINY_EGG:           { name: "Shiny Egg",           icon: "egg" },
    SHINY_LEGENDARY_EGG: { name: "Shiny Legendary Egg", icon: "egg" }
  }

  def self.special_reward?(item_id)
    SPECIAL_REWARDS.key?(item_id)
  end

  def self.special_reward_name(item_id)
    SPECIAL_REWARDS.dig(item_id, :name) || item_id.to_s
  end

  #=============================================================================
  # Runtime State (can be toggled via debug/multiplayer options)
  #=============================================================================
  class << self
    attr_accessor :runtime_spawn_chance
    attr_accessor :runtime_enabled
  end

  @runtime_spawn_chance = nil  # nil = use SPAWN_CHANCE constant
  @runtime_enabled = nil       # nil = enabled by default

  def self.enabled?
    return @runtime_enabled unless @runtime_enabled.nil?
    true
  end

  def self.set_enabled(val)
    @runtime_enabled = val
  end

  def self.get_spawn_chance
    return @runtime_spawn_chance unless @runtime_spawn_chance.nil?
    SPAWN_CHANCE
  end

  def self.set_spawn_chance(val)
    @runtime_spawn_chance = val
  end

  #=============================================================================
  # Helper Methods
  #=============================================================================

  # Get stat multipliers for given player count (clamped 1-3)
  def self.get_multipliers(player_count)
    count = [[player_count, 1].max, 3].min
    MULTIPLIERS[count]
  end

  # Check if a move is blocked against bosses
  def self.move_blocked?(move_id)
    BLOCKED_MOVES.include?(move_id)
  end

  # Check if a move is banned for boss use (self-KO moves)
  def self.boss_banned_move?(move_id)
    BOSS_BANNED_MOVES.include?(move_id)
  end

  # Get a random held item for boss
  def self.random_held_item
    HELD_ITEMS.sample
  end

  # Weighted random loot pick
  def self.weighted_loot_pick
    total = LOOT.values.sum { |v| v[:weight] }
    roll = rand(total)
    cumulative = 0
    LOOT.each do |rarity, data|
      cumulative += data[:weight]
      if roll < cumulative
        item = data[:pool] ? data[:pool].sample : data[:item]
        return { rarity: rarity, item: item, qty: data[:qty] }
      end
    end
    # Fallback
    { rarity: :common, item: LOOT[:common][:item], qty: LOOT[:common][:qty] }
  end

  # Generate 3 loot options for voting
  def self.generate_loot_options
    options = []
    3.times { options << weighted_loot_pick }
    options
  end
end
