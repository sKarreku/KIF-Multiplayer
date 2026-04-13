#===============================================================================
# KIF Cases — Core Data Module
# File: 011_Cases/001_CaseData.rb
# Purpose: Rarity definitions, NPT Pokémon pool builder, species resolver,
#          Pokémon awarding, and PokemonGlobalMetadata extension.
#===============================================================================

# ── Extend save-game globals with case state ──────────────────────────────────
class PokemonGlobalMetadata
  attr_accessor :case_result   # { tier:, position: } on success, { error: } on fail

  alias kif_cases_global_initialize initialize unless method_defined?(:kif_cases_global_initialize)
  def initialize
    kif_cases_global_initialize
    @case_result = nil
  end
end

# ── Main module ───────────────────────────────────────────────────────────────
module KIFCases
  CASE_COST = 200   # Platinum per opening

  # 7 rarity tiers in ascending order (index 0 = most common).
  # color_rgb  → border color of the roulette tile for that tier.
  # weight     → server-side roll weight; MUST match server.rb CASE_WEIGHTS.
  RARITY_TIERS = [
    { name: "Common",    bst_max: 299, color_rgb: [150, 150, 150], weight: 40 },
    { name: "Uncommon",  bst_max: 359, color_rgb: [80,  200, 80 ], weight: 25 },
    { name: "Rare",      bst_max: 419, color_rgb: [80,  120, 255], weight: 15 },
    { name: "Epic",      bst_max: 479, color_rgb: [180, 80,  255], weight: 10 },
    { name: "Ultra",     bst_max: 539, color_rgb: [255, 180, 0  ], weight:  6 },
    { name: "Master",    bst_max: 579, color_rgb: [255, 60,  60 ], weight:  3 },
    { name: "Legendary", bst_max: nil, color_rgb: [255, 215, 0  ], weight:  1 },
  ].freeze

  def self.rarity_color(tier_index, alpha = 255)
    rgb = RARITY_TIERS[tier_index][:color_rgb]
    Color.new(rgb[0], rgb[1], rgb[2], alpha)
  end

  def self.rarity_name(tier_index)
    RARITY_TIERS[tier_index][:name]
  end

  # ── Pool builder ────────────────────────────────────────────────────────────
  # Returns an array of 7 arrays, each containing species symbols for that tier.
  # Sorted by id_number for determinism (server picks by index, not name).
  # NPT Mega Form IDs to exclude from PokéCase (they're not catchable Pokémon)
  MEGA_FORM_IDS = (1109..1152).to_a

  def self.build_pool
    return @pool if @pool
    tiers = Array.new(7) { [] }
    GameData::Species.each do |species|
      next unless species.id_number.between?(NPT::FIRST_ID, NPT::NEW_NB_POKEMON)
      next if MEGA_FORM_IDS.include?(species.id_number)
      next unless species.base_stats && !species.base_stats.empty?
      bst = species.base_stats.values.sum
      tier_index = _bst_to_tier(bst)
      tiers[tier_index] << [species.id, species.id_number]
    end
    # Sort each tier by id_number for a consistent, deterministic ordering
    @pool = tiers.map { |t| t.sort_by { |_sym, num| num }.map { |sym, _| sym } }
    @pool
  end

  # Force pool rebuild (call after NPT species are reloaded)
  def self.reset_pool
    @pool = nil
  end

  # ── Screen open/close guard (mutex-like flag, prevents re-entry) ─────────────
  @screen_open      = false
  @close_requested  = false

  def self.screen_open?;     @screen_open;     end
  def self.close_requested?; @close_requested; end

  def self.mark_open
    @screen_open     = true
    @close_requested = false
  end

  def self.mark_closed
    @screen_open     = false
    @close_requested = false
  end

  def self.request_close
    @close_requested = true
  end

  # Total number of Pokémon across all tiers
  def self.pool_size
    build_pool.sum(&:size)
  end

  # Resolve (tier_index, position_from_server) → species symbol
  # Server sends a large random position; we mod it by tier size.
  def self.resolve_species(tier_index, position)
    pool  = build_pool
    tier  = pool[tier_index]
    return nil if tier.nil? || tier.empty?
    tier[position % tier.size]
  end

  # ── Pokémon awarding ────────────────────────────────────────────────────────
  # Creates a Pokémon at (max_party_level - 5), places it in party if space,
  # otherwise sends to PC box. Autosaves.
  # Returns the Pokemon object, or nil on failure.
  def self.award_pokemon(species_sym)
    return nil unless $Trainer && species_sym

    max_level = $Trainer.party.map(&:level).max if $Trainer.party.length > 0
    max_level  ||= 5
    award_level  = [[max_level - 5, 1].max, 100].min

    pkmn = Pokemon.new(species_sym, award_level)
    pkmn.record_first_moves

    $Trainer.pokedex.register(pkmn)
    $Trainer.pokedex.set_owned(pkmn.species)

    if $Trainer.party_full?
      $PokemonStorage.pbStoreCaught(pkmn)
    else
      $Trainer.party[$Trainer.party.length] = pkmn
    end

    Kernel.tryAutosave() rescue nil
    pkmn
  end

  # ── Private helpers ─────────────────────────────────────────────────────────
  def self._bst_to_tier(bst)
    RARITY_TIERS.each_with_index do |tier, i|
      return i if tier[:bst_max].nil? || bst <= tier[:bst_max]
    end
    0
  end
  private_class_method :_bst_to_tier
end
