#===============================================================================
# MODULE: Shiny Odds Tracking — Server Sync & Stamp Protocol
#===============================================================================
# Extends ShinyOddsTracker with server communication methods.
# Actual message handling is in 003_Client.rb (listener thread) and server.rb.
#
# Protocol (v2 — includes context for server-side validation):
#   Client → SHINY_ODDS_SYNC:{base_odds}:{gamble_odds}
#   Client → SHINY_STAMP:{base_odds}:{eff_denom}:{family_rate}:{personal_id}:{context}:{gamble_odds}
#   Server → SHINY_STAMP_OK:{personal_id}
#   Server → SHINY_STAMP_FAIL:{personal_id}:{reason}
#
# The server validates that eff_denom is consistent with the context and
# base_odds/gamble_odds. This prevents custom clients from faking odds.
#===============================================================================

module ShinyOddsTracker
  @last_synced_odds = nil
  @last_synced_gamble_odds = nil

  # ── Sync shiny odds + gamble odds setting to server ──────────────────────

  def self.sync_shiny_odds_to_server
    return unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
    base_odds   = $PokemonSystem.shinyodds rescue 16
    gamble_odds = $PokemonSystem.kuraygambleodds rescue 100
    gamble_odds = 100 if gamble_odds.nil? || gamble_odds <= 0
    MultiplayerClient.send_data("SHINY_ODDS_SYNC:#{base_odds}:#{gamble_odds}")
    @last_synced_odds = base_odds
    @last_synced_gamble_odds = gamble_odds
  end

  # Check if setting changed and re-sync
  def self.check_and_resync
    return unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
    current_base   = $PokemonSystem.shinyodds rescue 16
    current_gamble = $PokemonSystem.kuraygambleodds rescue 100
    current_gamble = 100 if current_gamble.nil? || current_gamble <= 0
    if @last_synced_odds != current_base || @last_synced_gamble_odds != current_gamble
      sync_shiny_odds_to_server
    end
  end

  # ── Stamp request ─────────────────────────────────────────────────────────

  def self.request_server_stamp(pkmn)
    return unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
    return unless pkmn && pkmn.shiny_catch_odds

    # Re-sync if settings changed since last sync
    check_and_resync

    base_odds    = $PokemonSystem.shinyodds rescue 16
    eff_denom    = pkmn.shiny_catch_odds
    family_rate  = pkmn.family_catch_rate || 0
    personal_id  = pkmn.personalID
    context      = @catch_context || :default
    gamble_odds  = $PokemonSystem.kuraygambleodds rescue 100
    gamble_odds  = 100 if gamble_odds.nil? || gamble_odds <= 0

    # Store context on the Pokemon for display
    pkmn.shiny_catch_context = context.to_s

    add_pending(pkmn)
    MultiplayerClient.send_data(
      "SHINY_STAMP:#{base_odds}:#{eff_denom}:#{family_rate}:#{personal_id}:#{context}:#{gamble_odds}"
    )
  end

  # ── Handle server responses (called from 003_Client.rb listener) ────────

  def self.handle_stamp_ok(personal_id)
    resolve_pending(personal_id, true)
  end

  def self.handle_stamp_fail(personal_id)
    resolve_pending(personal_id, false)
  end
end
