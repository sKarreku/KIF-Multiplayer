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
  SPAWN_CHANCE = 75           # Default fallback (used by runtime override / debug)
  SPAWN_CHANCE_MIN = 150      # 1 in 150 at 5 badges  (hardest to trigger)
  SPAWN_CHANCE_MAX = 50       # 1 in 50  at 16 badges (easiest to trigger)
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
  # Base Stat Multipliers by Player Count (before BST scaling)
  #=============================================================================
  # These are the BASE multipliers. They get further adjusted by allied BST.
  # Higher player count = tankier boss but lower per-player scaling
  MULTIPLIERS = {
    1 => { hp: 2.0, def: 1.5, spdef: 1.5, atk: 0.75, spatk: 0.75, speed: 1.0 },
    2 => { hp: 3.0, def: 1.3, spdef: 1.3, atk: 0.85, spatk: 0.85, speed: 1.0 },
    3 => { hp: 4.0, def: 1.2, spdef: 1.2, atk: 1.0, spatk: 1.0, speed: 1.0 }
  }

  #=============================================================================
  # BST-Based Scaling System
  #=============================================================================
  # Scales boss multipliers and move selection based on allied team average BST.
  # A squad of starters (BST ~300) facing a legendary fusion boss shouldn't get
  # one-shot or fight a wall. As allied BST rises, bosses scale up to match.
  #
  # BST Tiers (based on average BST of all allied Pokemon across all players):
  #   Starter  : avg BST < 350  (just got starters + a couple catches)
  #   Early    : avg BST 350-449 (first evolutions, early routes)
  #   Mid      : avg BST 450-529 (mid-game, second evos, decent team)
  #   Late     : avg BST 530-599 (strong teams, pseudo-legends)
  #   Endgame  : avg BST 600+    (legends, mega-tier, fully optimized)
  #
  # Each tier defines:
  #   bst_scale   - Multiplier applied ON TOP of the player-count multipliers
  #                 (affects hp, def, spdef). Lower = squishier boss.
  #   atk_scale   - Multiplier on atk/spatk. Lower = boss hits softer.
  #   move_bp_cap - Maximum base power the boss can pick from its pool.
  #                 Prevents e.g. Flamethrower on a Bulbasaur-level fight.
  #   hp_phases   - Override HP phases for very early fights (nil = use default)
  #   shields_cap - Override max shields (nil = use level-based default)
  #
  BST_TIERS = [
    { name: :starter, max_bst: 349,
      bst_scale: 0.50, atk_scale: 0.50, move_bp_cap: 50,
      hp_phases: 2, shields_cap: 2 },
    { name: :early,   max_bst: 449,
      bst_scale: 0.65, atk_scale: 0.65, move_bp_cap: 70,
      hp_phases: 3, shields_cap: 3 },
    { name: :mid,     max_bst: 529,
      bst_scale: 0.80, atk_scale: 0.70, move_bp_cap: 95,
      hp_phases: nil, shields_cap: nil },
    { name: :late,    max_bst: 599,
      bst_scale: 0.95, atk_scale: 0.85, move_bp_cap: 120,
      hp_phases: nil, shields_cap: nil },
    { name: :endgame, max_bst: 99999,
      bst_scale: 1.00, atk_scale: 1.00, move_bp_cap: 999,
      hp_phases: nil, shields_cap: nil }
  ]

  # Determine which BST tier an average BST falls into
  def self.bst_tier(avg_bst)
    BST_TIERS.each do |tier|
      return tier if avg_bst <= tier[:max_bst]
    end
    BST_TIERS.last
  end

  # Get BST-scaled multipliers: combines player-count base with BST scaling
  def self.get_multipliers_bst(player_count, avg_bst)
    base = get_multipliers(player_count).dup
    tier = bst_tier(avg_bst)

    scaled = {
      hp:    (base[:hp]    * tier[:bst_scale]).round(2),
      def:   (base[:def]   * tier[:bst_scale]).round(2),
      spdef: (base[:spdef] * tier[:bst_scale]).round(2),
      atk:   (base[:atk]   * tier[:atk_scale]).round(2),
      spatk: (base[:spatk] * tier[:atk_scale]).round(2),
      speed: base[:speed]
    }

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("BOSS-BST", "BST tier: #{tier[:name]} (avg_bst=#{avg_bst})")
      MultiplayerDebug.info("BOSS-BST", "  Base mults (#{player_count}p): hp=#{base[:hp]} def=#{base[:def]} atk=#{base[:atk]}")
      MultiplayerDebug.info("BOSS-BST", "  BST scales: bst=#{tier[:bst_scale]} atk=#{tier[:atk_scale]} bp_cap=#{tier[:move_bp_cap]}")
      MultiplayerDebug.info("BOSS-BST", "  Final mults: hp=#{scaled[:hp]} def=#{scaled[:def]} atk=#{scaled[:atk]} spatk=#{scaled[:spatk]}")
    end

    scaled
  end

  # Get move base power cap for a given allied BST
  def self.move_bp_cap(avg_bst)
    bst_tier(avg_bst)[:move_bp_cap]
  end

  # Get HP phase override (nil means use default HP_PHASES)
  def self.bst_hp_phases(avg_bst)
    bst_tier(avg_bst)[:hp_phases]
  end

  # Get shield cap override (nil means use level-based default)
  def self.bst_shields_cap(avg_bst)
    bst_tier(avg_bst)[:shields_cap]
  end

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
    THIEF COVET TRICK SWITCHEROO KNOCKOFF
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
  # Loot System — Data-Driven Rarity Tiers
  #=============================================================================
  # 3 categories: Pokeball, TM, Item.  Each boss drops one vote option per
  # category. Rarity is determined automatically from game data:
  #   Pokeballs → sorted by item price
  #   TMs       → sorted by move base power (NPT id≥6001 = legendary)
  #   Items     → sorted by item price (bloodbound/resonance = legendary)
  #
  # Rarity roll weights (shared across all categories):
  RARITY_WEIGHTS = {
    common:    45,
    uncommon:  30,
    rare:      15,
    epic:       8,
    legendary:  2
  }

  # Quantity per rarity tier
  RARITY_QTY = {
    common:    5,
    uncommon:  3,
    rare:      2,
    epic:      1,
    legendary: 1
  }

  # ── Special Rewards (non-item loot like eggs) ──────────────────────────
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

  # ── Pokeball Pool (auto-tiered by price) ───────────────────────────────
  def self.ball_pool
    @ball_pool ||= begin
      tiers = { common: [], uncommon: [], rare: [], epic: [], legendary: [] }
      GameData::Item.each do |item|
        next unless item.is_poke_ball?
        if item.id == :MASTERBALL
          tiers[:legendary] << item.id
        else
          t = case item.price
              when 0..300   then :common
              when 301..800 then :uncommon
              when 801..2000 then :rare
              else :epic
              end
          tiers[t] << item.id
        end
      end
      tiers
    end
  end

  # ── TM Pool (auto-tiered by move base power) ──────────────────────────
  def self.tm_pool
    @tm_pool ||= begin
      tiers = { common: [], uncommon: [], rare: [], epic: [], legendary: [] }
      GameData::Item.each do |item|
        next unless item.is_TM?
        move_id = (item.move rescue nil)
        next unless move_id
        md = (GameData::Move.get(move_id) rescue nil)
        next unless md
        bp = md.base_damage.to_i
        npt = (md.id_number.to_i >= 6001) rescue false
        t = if npt
              :legendary
            elsif bp > 120
              :legendary
            elsif bp > 100
              :epic
            elsif bp > 70
              :rare
            elsif bp > 40
              :uncommon
            else
              :common
            end
        tiers[t] << item.id
      end
      tiers
    end
  end

  # ── Item Pool (auto-tiered by price, special items forced legendary) ───
  LEGENDARY_ITEM_IDS = [:RESONANCECORE, :RESONANCERESONATOR, :SHINY_EGG, :SHINY_LEGENDARY_EGG]

  def self.item_pool
    @item_pool ||= begin
      tiers = { common: [], uncommon: [], rare: [], epic: [], legendary: [] }
      # Force bloodbound catalysts + resonance items to legendary
      forced_legendary = LEGENDARY_ITEM_IDS.dup
      forced_legendary += BloodboundCatalysts::ALL_ITEMS if defined?(BloodboundCatalysts)

      GameData::Item.each do |item|
        next if item.is_poke_ball? || item.is_TM? || item.is_machine? || item.is_key_item?
        next if item.price.to_i == 0  # skip unsellable/junk items
        if forced_legendary.include?(item.id)
          tiers[:legendary] << item.id
          next
        end
        t = case item.price
            when 1..400     then :common
            when 401..2000  then :uncommon
            when 2001..6000 then :rare
            when 6001..15000 then :epic
            else :legendary
            end
        tiers[t] << item.id
      end
      # Add special (non-item) rewards to legendary
      tiers[:legendary] << :SHINY_EGG unless tiers[:legendary].include?(:SHINY_EGG)
      tiers[:legendary] << :SHINY_LEGENDARY_EGG unless tiers[:legendary].include?(:SHINY_LEGENDARY_EGG)
      tiers
    end
  end

  def self.reset_pools; @ball_pool = nil; @tm_pool = nil; @item_pool = nil; end

  # ── Rarity Roll ────────────────────────────────────────────────────────
  # Weighted random pick of a rarity tier.
  def self.roll_rarity
    total = RARITY_WEIGHTS.values.sum
    roll  = rand(total)
    cumulative = 0
    RARITY_WEIGHTS.each do |tier, weight|
      cumulative += weight
      return tier if roll < cumulative
    end
    :common
  end

  # Pick an item from a pool at a given rarity. Falls back to nearest
  # lower tier if the rolled tier is empty.
  def self.pick_from_pool(pool, rarity)
    order = [:legendary, :epic, :rare, :uncommon, :common]
    start = order.index(rarity) || 4
    # Try rolled tier first, then fall downward
    order[start..].each do |tier|
      candidates = pool[tier]
      return { item: candidates.sample, rarity: tier, qty: RARITY_QTY[tier] } if candidates && !candidates.empty?
    end
    # Last resort: try upward
    order[0...start].reverse_each do |tier|
      candidates = pool[tier]
      return { item: candidates.sample, rarity: tier, qty: RARITY_QTY[tier] } if candidates && !candidates.empty?
    end
    nil
  end

  # ── Generate 3 Loot Options (one per category) ────────────────────────
  def self.generate_loot_options
    pools = [
      { pool: ball_pool, label: "Pokeball", force_qty: nil },
      { pool: tm_pool,   label: "TM",       force_qty: 1 },
      { pool: item_pool, label: "Item",     force_qty: 1 }
    ]
    options = pools.map do |entry|
      rarity = roll_rarity
      pick = pick_from_pool(entry[:pool], rarity)
      pick ||= { item: :POKEBALL, rarity: :common, qty: 3 }  # absolute fallback
      pick[:qty] = entry[:force_qty] if entry[:force_qty]
      pick
    end
    options
  end

  # Legacy helper (kept for compatibility — weighted_loot_pick is unused now)
  def self.weighted_loot_pick
    generate_loot_options.sample
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
    badge_spawn_chance
  end

  # Badge-scaled spawn chance: linearly interpolates between
  # SPAWN_CHANCE_MIN (5 badges) and SPAWN_CHANCE_MAX (16 badges).
  # 5 badges → 1/150, 16 badges → 1/50, <5 badges → no bosses (gated in SpawnHook)
  def self.badge_spawn_chance
    badges = ($Trainer.badge_count rescue 0)
    badges = [[badges, 5].max, 16].min  # clamp 5..16
    # Linear: 150 at 5 badges, 50 at 16 badges
    # step = (150 - 50) / (16 - 5) = ~9.1 per badge
    chance = SPAWN_CHANCE_MIN - ((badges - 5) * (SPAWN_CHANCE_MIN - SPAWN_CHANCE_MAX) / 11.0)
    chance.round
  end

  def self.set_spawn_chance(val)
    @runtime_spawn_chance = val
  end

  #=============================================================================
  # Helper Methods
  #=============================================================================

  # Get base stat multipliers for given player count (clamped 1-3)
  # NOTE: For BST-aware scaling, use get_multipliers_bst() instead
  def self.get_multipliers(player_count)
    count = [[player_count, 1].max, 3].min
    MULTIPLIERS[count]
  end

  # Calculate average BST across all allied Pokemon in all player parties
  # parties = array of party arrays, e.g. [player1_party, player2_party]
  def self.calculate_avg_bst(parties)
    all_pokemon = parties.flatten.compact.select { |p| p.respond_to?(:baseStats) }
    return 400 if all_pokemon.empty?  # Fallback: assume early-game

    total_bst = 0
    all_pokemon.each do |pkmn|
      stats = pkmn.baseStats
      bst = 0
      stats.each_value { |v| bst += v }
      total_bst += bst
    end

    avg = total_bst / all_pokemon.length
    MultiplayerDebug.info("BOSS-BST", "Allied avg BST: #{avg} (from #{all_pokemon.length} Pokemon)") if defined?(MultiplayerDebug)
    avg
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

end
