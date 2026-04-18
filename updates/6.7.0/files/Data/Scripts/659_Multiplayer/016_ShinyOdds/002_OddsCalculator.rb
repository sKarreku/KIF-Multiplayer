#===============================================================================
# MODULE: Shiny Odds Tracking — Odds Calculator
#===============================================================================
# Calculates the effective shiny odds denominator (the X in "1/X") based on
# the current game state and catch context.
#
# Contexts:
#   :wild      — Wild encounter (Shiny Charm = 3 rolls, SSC = 1.5x)
#   :pokeradar — PokeRadar chain encounter (chain count reduces denominator)
#   :breeding  — Daycare egg (Shiny Charm +2 rolls, Masuda +5 rolls)
#   :kegg      — Kuray Egg (10x base, 40x if sparkling)
#   :gamble    — Gamble for Shiny in PC (1/kuraygambleodds, default 1/100)
#   :resonance — Resonance Core / Resonance Resonator (guaranteed 1/1)
#   :default   — Cases, gifts, trades, etc. (base odds only)
#===============================================================================

module ShinyOddsTracker
  # ── Context management ────────────────────────────────────────────────────
  # Set before creating Pokemon so the stamp hook knows what modifiers apply.
  @catch_context       = :default
  @breeding_extra_rolls = 0  # set by breeding hook
  @pokeradar_chain      = 0  # set by wild catch hook when PokeRadar active

  def self.catch_context;           @catch_context;           end
  def self.catch_context=(ctx);     @catch_context = ctx;     end
  def self.breeding_extra_rolls;    @breeding_extra_rolls;    end
  def self.breeding_extra_rolls=(n); @breeding_extra_rolls = n; end
  def self.pokeradar_chain;         @pokeradar_chain;         end
  def self.pokeradar_chain=(n);     @pokeradar_chain = n;     end

  def self.reset_context
    @catch_context        = :default
    @breeding_extra_rolls = 0
    @pokeradar_chain      = 0
  end

  # ── Pending stamps (personalID => Pokemon ref) ────────────────────────────
  @pending_stamps = {}

  def self.pending_stamps; @pending_stamps; end

  def self.add_pending(pkmn)
    @pending_stamps[pkmn.personalID] = pkmn
  end

  def self.resolve_pending(personal_id, success)
    pkmn = @pending_stamps.delete(personal_id)
    return unless pkmn
    if success
      pkmn.shiny_odds_stamped = true
    else
      pkmn.shiny_catch_odds  = nil
      pkmn.family_catch_rate = nil
    end
  end

  # ── Odds calculation ──────────────────────────────────────────────────────

  # Returns the effective numerator out of 65536 for the current context.
  # e.g. 16 means "16/65536" chance per encounter.
  def self.calculate_odds(context = nil)
    context ||= @catch_context
    base_odds = $PokemonSystem.shinyodds rescue 16  # out of 65536

    case context
    when :wild
      _calc_wild_odds(base_odds)
    when :pokeradar
      _calc_pokeradar_odds(base_odds)
    when :breeding
      _calc_breeding_odds(base_odds)
    when :kegg
      _calc_kegg_odds(base_odds)
    when :gamble
      _calc_gamble_odds
    when :resonance
      65536  # guaranteed 1/1
    else
      _calc_base_odds(base_odds)
    end
  end

  # Returns the family rate numerator out of 100, or nil if family system off.
  # e.g. 1 means "1/100", 50 means "50/100".
  def self.calculate_family_rate
    return nil unless defined?($PokemonSystem) && $PokemonSystem
    return nil unless $PokemonSystem.respond_to?(:mp_family_enabled)
    return nil if $PokemonSystem.mp_family_enabled == 0

    rate = $PokemonSystem.mp_family_rate rescue 1
    rate = 1 if rate.nil? || rate < 1
    [rate, 100].min
  end

  # ── Private calculation methods ───────────────────────────────────────────
  private

  # Wild: Shiny Charm gives 3 rolls, Shooting Star Charm gives 1.5x multiplier
  # Returns effective numerator out of 65536.
  def self._calc_wild_odds(base_odds)
    rolls = 1
    multiplier = 1.0

    # Shiny Charm: 3 total rolls (2 extra re-rolls)
    if _has_shiny_charm?
      rolls = 3
    end

    # Shooting Star Charm: 1.5x multiplier on shinyodds
    if _has_shooting_star_charm?
      multiplier = 1.5
    end

    modified_odds = [base_odds * multiplier, 65535].min
    p_per_roll = modified_odds / 65536.0
    effective_p = 1.0 - (1.0 - p_per_roll) ** rolls
    [(effective_p * 65536).round, 1].max
  end

  # PokeRadar chain: Two independent shiny chances per encounter:
  #   1. Chain-boosted shiny grass tile (005_Item_PokeRadar.rb:186-188)
  #      v = max((65536 / shinyodds) - chain * 200, 200); chance ≈ 1/v
  #   2. Normal wild shiny roll (Shiny Charm + SSC still apply as fallback)
  # Combined: P = 1 - (1 - P_radar) * (1 - P_wild)
  # Returns effective numerator out of 65536.
  def self._calc_pokeradar_odds(base_odds)
    chain = @pokeradar_chain
    chain = 0 if chain.nil? || chain < 0
    chain = 40 if chain > 40  # game caps at 40

    # Radar shiny grass chance
    base_odds = 1 if base_odds < 1
    denom = (65536.0 / base_odds) - chain * 200
    denom = 200 if denom < 200
    p_radar = 1.0 / denom

    # Normal wild shiny roll (Charm + SSC) as fallback
    wild_numerator = _calc_wild_odds(base_odds)
    p_wild = wild_numerator / 65536.0

    # Combined probability
    p_combined = 1.0 - (1.0 - p_radar) * (1.0 - p_wild)
    [(p_combined * 65536).round, 1].max
  end

  # Breeding: Masuda Method +5, Shiny Charm +2, total rolls = 1 + extras
  # Returns effective numerator out of 65536.
  def self._calc_breeding_odds(base_odds)
    rolls = 1 + @breeding_extra_rolls  # set by the breeding hook
    p_per_roll = base_odds / 65536.0
    effective_p = 1.0 - (1.0 - p_per_roll) ** rolls
    [(effective_p * 65536).round, 1].max
  end

  # K-egg: 10x base (40x if sparkling), single roll
  # Returns effective numerator out of 65536.
  def self._calc_kegg_odds(base_odds)
    kegg_mult = ($KURAYEGGS_SPARKLING ? 40 : 10) rescue 10
    modified_odds = [base_odds * kegg_mult, 65535].min
    [modified_odds.round, 1].max
  end

  # Gamble: 1/kuraygambleodds chance (default 1/100), single roll
  # Returns effective numerator out of 65536.
  def self._calc_gamble_odds
    odds = $PokemonSystem.kuraygambleodds rescue 100
    odds = 100 if odds.nil? || odds <= 0
    # Convert 1/odds to numerator out of 65536
    [(65536.0 / odds).round, 1].max
  end

  # Default: just base odds, 1 roll
  # Returns effective numerator out of 65536.
  def self._calc_base_odds(base_odds)
    [base_odds, 1].max
  end

  # ── Item checks ──────────────────────────────────────────────────────────

  def self._has_shiny_charm?
    return false unless defined?(GameData::Item) && defined?($PokemonBag)
    GameData::Item.exists?(:SHINYCHARM) && $PokemonBag.pbHasItem?(:SHINYCHARM) rescue false
  end

  def self._has_shooting_star_charm?
    return false unless defined?(EventRewards)
    EventRewards.has_shooting_star_charm? rescue false
  end
end
