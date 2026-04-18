#===============================================================================
# Platinum Currency - Global Metadata Storage
# Stores per-server authentication tokens, UUIDs, and cached platinum balance
# - platinum_tokens: Auth tokens keyed by "host:port"
# - platinum_uuids: Account UUIDs keyed by "host:port" (persistent across sessions)
# - platinum_balance: Last known platinum balance from server
#===============================================================================

class PokemonGlobalMetadata
  attr_accessor :platinum_tokens        # { "host:port" => "auth_token" }
  attr_accessor :platinum_uuids         # { "host:port" => "account_uuid" }
  attr_accessor :platinum_balance       # Cached balance from server
  attr_accessor :last_platinum_transaction  # :SUCCESS, :INSUFFICIENT, :ERROR, etc.

  alias platinum_global_initialize initialize
  def initialize
    platinum_global_initialize
    @platinum_tokens = {}
    @platinum_uuids = {}
    @platinum_balance = 0
    @last_platinum_transaction = nil
  end
end
