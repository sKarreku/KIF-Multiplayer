# ===========================================
# Randomizer seed entry — hooks into the randomizer settings menu
# to let players set a custom seed.  Uses a seeded Random object
# passed directly to .sample(random: rng) inside aliased shuffles.
# Does NOT touch srand or the global PRNG.
# ===========================================

class PokemonGlobalMetadata
  attr_accessor :randomizer_seed   # Integer or nil
end

module RandomizerSeedHelper
  def self.parse_seed(str)
    return nil if str.nil?
    s = str.to_s.strip
    return nil if s.empty?
    if s =~ /\A-?\d+\z/
      s.to_i.abs
    else
      s.hash.abs
    end
  end

  # Single shared RNG for the entire randomization pass.
  # Created once when the first shuffle function runs, then reused
  # across dex/items/TMs so the full sequence is deterministic.
  @rng = nil

  # Initialize (or re-initialize) the shared RNG from the stored seed.
  # Call this once at the start of randomization.
  def self.init_rng
    seed = ($PokemonGlobal.randomizer_seed rescue nil)
    @rng = seed ? Random.new(seed) : nil
  end

  # Returns the shared RNG, or nil if no seed is set.
  def self.rng
    @rng
  end

  def self.prompt
    return unless defined?(pbMessageFreeText) && $PokemonGlobal
    current = $PokemonGlobal.randomizer_seed ? $PokemonGlobal.randomizer_seed.to_s : ""
    txt = pbMessageFreeText(_INTL("Enter a seed (numbers or text):"), current, false, 24, 240)
    seed = parse_seed(txt)
    if seed
      $PokemonGlobal.randomizer_seed = seed
      pbMessage(_INTL("Randomizer seed set to: {1}", seed)) if defined?(pbMessage)
    else
      $PokemonGlobal.randomizer_seed = nil
      pbMessage(_INTL("Randomizer seed cleared (will be random).")) if defined?(pbMessage)
    end
  end
end

# ── Seeded version of get_randomized_bst_hash ──────────────
# Exact copy of the original, but .sample calls use random: rng
# when a seed is set.
Object.class_eval { alias_method :get_randomized_bst_hash_noseed, :get_randomized_bst_hash }

def get_randomized_bst_hash(poke_list, bst_range, show_progress = true)
  RandomizerSeedHelper.init_rng
  rng = RandomizerSeedHelper.rng
  unless rng
    MultiplayerDebug.info("SEED", "No seed set — using original shuffle") if defined?(MultiplayerDebug)
    return get_randomized_bst_hash_noseed(poke_list, bst_range, show_progress)
  end
  MultiplayerDebug.info("SEED", "Running seeded dex shuffle with seed #{$PokemonGlobal.randomizer_seed}") if defined?(MultiplayerDebug)

  bst_hash = Hash.new
  for i in 1..NB_POKEMON - 1
    show_shuffle_progress(i) if show_progress
    baseStats = getBaseStatsFormattedForRandomizer(i)
    statsTotal = getStatsTotal(baseStats)
    targetStats_max = statsTotal + bst_range
    targetStats_min = statsTotal - bst_range
    max_bst_allowed = targetStats_max
    min_bst_allowed = targetStats_min

    playShuffleSE(i)
    random_poke = poke_list[rng.rand(poke_list.length)]
    random_poke_bst = getStatsTotal(getBaseStatsFormattedForRandomizer(random_poke))
    j = 0

    includeLegendaries = $game_switches[SWITCH_RANDOM_WILD_LEGENDARIES]
    current_species = GameData::Species.get(i).id
    random_poke_species = GameData::Species.get(random_poke).id
    while (random_poke_bst <= min_bst_allowed || random_poke_bst >= max_bst_allowed) || !legendaryOk(current_species, random_poke_species, includeLegendaries)
      random_poke = poke_list[rng.rand(poke_list.length)]
      random_poke_species = GameData::Species.get(random_poke).id
      random_poke_bst = getStatsTotal(getBaseStatsFormattedForRandomizer(random_poke))
      j += 1
      if j % 5 == 0
        min_bst_allowed -= 1
        max_bst_allowed += 1
      end
    end
    bst_hash[i] = random_poke
  end
  return bst_hash
end

# ── Seeded pbShuffleItems ──────────────────────────────────
Object.class_eval { alias_method :pbShuffleItems_noseed, :pbShuffleItems }

def pbShuffleItems()
  rng = RandomizerSeedHelper.rng
  unless rng
    return pbShuffleItems_noseed
  end

  randomItemsHash = Hash.new
  available_items = []
  for itemElement in GameData::Item.list_all
    item = itemElement[1]
    if itemCanBeRandomized(item)
      if !available_items.include?(item.id)
        available_items << item.id
      end
    end
  end
  remaining_items = available_items.clone
  for itemId in available_items
    if itemCanBeRandomized(GameData::Item.get(itemId))
      chosenItem = remaining_items[rng.rand(remaining_items.length)]
      randomItemsHash[itemId] = chosenItem
      remaining_items.delete(chosenItem)
    end
  end
  $PokemonGlobal.randomItemsHash = randomItemsHash
end

# ── Seeded pbShuffleTMs ────────────────────────────────────
Object.class_eval { alias_method :pbShuffleTMs_noseed, :pbShuffleTMs }

def pbShuffleTMs()
  rng = RandomizerSeedHelper.rng
  unless rng
    return pbShuffleTMs_noseed
  end

  randomItemsHash = Hash.new
  available_items = []
  for itemElement in GameData::Item.list_all
    item = itemElement[1]
    if item.is_TM?
      if !available_items.include?(item.id)
        available_items << item.id
      end
    end
  end
  remaining_items = available_items.clone
  for itemId in available_items
    if GameData::Item.get(itemId).is_TM?
      chosenItem = remaining_items[rng.rand(remaining_items.length)]
      randomItemsHash[itemId] = chosenItem
      remaining_items.delete(chosenItem)
    end
  end
  $PokemonGlobal.randomTMsHash = randomItemsHash
end

# ── Hook: RandomizerOptionsScene#pbGetOptions ─────────────
if defined?(RandomizerOptionsScene)
  class RandomizerOptionsScene
    unless method_defined?(:pbGetOptions_before_seed)
      alias_method :pbGetOptions_before_seed, :pbGetOptions
      def pbGetOptions(inloadscreen = false)
        options = pbGetOptions_before_seed(inloadscreen)
        options << EnumOption.new(
          _INTL("Custom Seed"),
          [_INTL("Off"), _INTL("Set...")],
          proc {
            ($PokemonGlobal && $PokemonGlobal.randomizer_seed) ? 1 : 0
          },
          proc { |value|
            has_seed = $PokemonGlobal && $PokemonGlobal.randomizer_seed
            if value == 0
              $PokemonGlobal.randomizer_seed = nil if $PokemonGlobal
            elsif !has_seed
              RandomizerSeedHelper.prompt
            end
          },
          _INTL("Enter a custom seed for reproducible randomization. " +
                "Same seed + same settings = same randomization.")
        )
        options
      end
    end
  end
end
