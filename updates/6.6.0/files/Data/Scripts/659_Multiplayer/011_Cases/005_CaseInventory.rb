#===============================================================================
# KIF Cases — Per-Server Case Inventory
# File: 011_Cases/005_CaseInventory.rb
#
# Tracks how many unopened cases each player owns on each server.
# Server is authoritative; this is the client-side cache + request API.
# Stored in PokemonGlobalMetadata and persisted via local file.
#===============================================================================

# ── Extend save-game globals ────────────────────────────────────────────────
class PokemonGlobalMetadata
  attr_accessor :case_inventory       # { "poke" => count, "mega" => count, "move" => count }
  attr_accessor :case_buy_result      # :SUCCESS, :INSUFFICIENT, :ERROR, nil
  attr_accessor :case_inv_pending     # true while waiting for server response

  alias kif_case_inv_global_initialize initialize unless method_defined?(:kif_case_inv_global_initialize)
  def initialize
    kif_case_inv_global_initialize
    @case_inventory   = { "poke" => 0, "mega" => 0, "move" => 0 }
    @case_buy_result  = nil
    @case_inv_pending = false
  end
end

# ── Inventory API ───────────────────────────────────────────────────────────
module KIFCaseInventory

  # Get cached count for a case type
  def self.count(case_type)
    return 0 unless defined?($PokemonGlobal) && $PokemonGlobal
    $PokemonGlobal.case_inventory ||= { "poke" => 0, "mega" => 0, "move" => 0 }
    $PokemonGlobal.case_inventory[case_type.to_s] || 0
  end

  # Update cached count (called by client message handler)
  def self.set_count(case_type, amount)
    return unless defined?($PokemonGlobal) && $PokemonGlobal
    $PokemonGlobal.case_inventory ||= { "poke" => 0, "mega" => 0, "move" => 0 }
    $PokemonGlobal.case_inventory[case_type.to_s] = [amount.to_i, 0].max
  end

  # Request full inventory sync from server
  def self.request_sync
    return unless defined?(MultiplayerClient) && MultiplayerClient.session_id
    MultiplayerClient.send_data("CASE_INV_REQ")
  end

  # Buy a case (adds to inventory, costs platinum)
  # Returns true on success, false on failure/timeout
  def self.buy(case_type)
    return false unless defined?(MultiplayerClient) && MultiplayerClient.session_id
    return false unless defined?($PokemonGlobal) && $PokemonGlobal

    $PokemonGlobal.case_buy_result = nil
    MultiplayerClient.send_data("CASE_BUY:#{case_type}")

    start_time = Time.now
    while Time.now - start_time < 4.0
      Graphics.update
      Input.update
      $multiplayer.update if $multiplayer
      if $PokemonGlobal.case_buy_result
        result = $PokemonGlobal.case_buy_result
        $PokemonGlobal.case_buy_result = nil
        return result == :SUCCESS
      end
    end
    false
  end

  # Open a case from inventory (server validates count, rolls result)
  # Sends CASE_OPEN_INV:<type>  — response comes as CASE_RESULT
  def self.open_from_inventory(case_type)
    return false unless defined?(MultiplayerClient) && MultiplayerClient.session_id
    $PokemonGlobal.case_result = nil
    MultiplayerClient.send_data("CASE_OPEN_INV:#{case_type}")
    # Caller polls $PokemonGlobal.case_result (same as existing flow)
    true
  end

  # Buy and open atomically (server handles both in one transaction)
  # Sends CASE_BUYOPEN:<type>  — response comes as CASE_RESULT
  def self.buy_and_open(case_type)
    return false unless defined?(MultiplayerClient) && MultiplayerClient.session_id
    $PokemonGlobal.case_result = nil
    MultiplayerClient.send_data("CASE_BUYOPEN:#{case_type}")
    # Caller polls $PokemonGlobal.case_result
    true
  end
end
