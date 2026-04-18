#===============================================================================
# MODULE: Shiny Odds Tracking — Pokemon Data Model
#===============================================================================
# Adds shiny odds attributes to Pokemon class for server-stamped display.
# Uses the same alias pattern as 008_Family/001_PokemonPatch.rb.
#
# New attributes:
#   @shiny_catch_odds    (Integer or nil) — numerator out of 65536 at catch time
#   @family_catch_rate   (Integer or nil) — numerator out of 100 at catch time
#   @shiny_odds_stamped  (Boolean)        — true if server validated the odds
#   @shiny_catch_context (String or nil)  — how shininess was obtained
#       Valid values: "wild", "breeding", "kegg", "gamble", "resonance", "default"
#
# Backward compatible: existing Pokemon have nil values (nothing displayed).
# Safe if Multiplayer is uninstalled: fields sit unused in save data.
#===============================================================================

class Pokemon
  attr_accessor :shiny_catch_odds    # e.g. 512 means "512/65536"
  attr_accessor :family_catch_rate   # e.g. 1 means "1/100"
  attr_accessor :shiny_odds_stamped  # true if server confirmed
  attr_accessor :shiny_catch_context # "wild", "breeding", "kegg", "gamble", "resonance", "default"

  # Stored per-component shiny odds for fused Pokemon (restored on unfuse)
  attr_accessor :body_shiny_catch_odds
  attr_accessor :body_shiny_odds_stamped
  attr_accessor :body_shiny_catch_context
  attr_accessor :head_shiny_catch_odds
  attr_accessor :head_shiny_odds_stamped
  attr_accessor :head_shiny_catch_context

  # Hook initialization
  alias shiny_odds_original_initialize initialize
  def initialize(*args)
    shiny_odds_original_initialize(*args)
    @shiny_catch_odds    = nil
    @family_catch_rate   = nil
    @shiny_odds_stamped  = false
    @shiny_catch_context = nil
    @body_shiny_catch_odds     = nil
    @body_shiny_odds_stamped   = false
    @body_shiny_catch_context  = nil
    @head_shiny_catch_odds     = nil
    @head_shiny_odds_stamped   = false
    @head_shiny_catch_context  = nil
    # Lock shiny status at creation time so changing $PokemonSystem.shinyodds
    # later can never retroactively make a non-shiny Pokemon shiny.
    # This calls the full shiny? chain (including event bonuses) and caches the
    # result in @shiny, so subsequent calls always return the same value.
    self.shiny? if @shiny.nil?
  end

  # Hook JSON serialization (save files)
  alias shiny_odds_original_as_json as_json
  def as_json(options = {})
    json = shiny_odds_original_as_json(options)
    json["shiny_catch_odds"]    = @shiny_catch_odds
    json["family_catch_rate"]   = @family_catch_rate
    json["shiny_odds_stamped"]  = @shiny_odds_stamped
    json["shiny_catch_context"] = @shiny_catch_context
    json["body_shiny_catch_odds"]    = @body_shiny_catch_odds
    json["body_shiny_odds_stamped"]  = @body_shiny_odds_stamped
    json["body_shiny_catch_context"] = @body_shiny_catch_context
    json["head_shiny_catch_odds"]    = @head_shiny_catch_odds
    json["head_shiny_odds_stamped"]  = @head_shiny_odds_stamped
    json["head_shiny_catch_context"] = @head_shiny_catch_context
    json
  end

  # Hook JSON deserialization (loading saves)
  alias shiny_odds_original_load_json load_json
  def load_json(jsonparse, jsonfile = nil, forcereadonly = false)
    shiny_odds_original_load_json(jsonparse, jsonfile, forcereadonly)
    @shiny_catch_odds    = jsonparse['shiny_catch_odds']
    @family_catch_rate   = jsonparse['family_catch_rate']
    @shiny_odds_stamped  = jsonparse['shiny_odds_stamped'] || false
    @shiny_catch_context = jsonparse['shiny_catch_context']
    @body_shiny_catch_odds    = jsonparse['body_shiny_catch_odds']
    @body_shiny_odds_stamped  = jsonparse['body_shiny_odds_stamped'] || false
    @body_shiny_catch_context = jsonparse['body_shiny_catch_context']
    @head_shiny_catch_odds    = jsonparse['head_shiny_catch_odds']
    @head_shiny_odds_stamped  = jsonparse['head_shiny_odds_stamped'] || false
    @head_shiny_catch_context = jsonparse['head_shiny_catch_context']
    # Lock shiny for legacy Pokemon (saved with @shiny=nil before this fix).
    # Use default odds (S_CHANCE_VALIDATOR=16) so boosted settings can't
    # retroactively flip them shiny.
    if @shiny.nil?
      saved_odds = $PokemonSystem.shinyodds rescue 16
      $PokemonSystem.shinyodds = S_CHANCE_VALIDATOR if defined?(S_CHANCE_VALIDATOR)
      begin; self.shiny?; ensure
        $PokemonSystem.shinyodds = saved_odds
      end
    end
  end
end
