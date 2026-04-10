#===============================================================================
# Platinum Currency - Client API
# Server-authoritative currency system
# Client can only query balance and request spending
#===============================================================================

module MultiplayerPlatinum
  # Request current platinum balance from server
  # @return [Integer, nil] Current balance, or nil if not connected/timeout
  def self.get_balance
    return nil unless $multiplayer&.connected?

    ##MultiplayerDebug.info("PLATINUM", "Requesting balance from server")
    $multiplayer.send_message("REQ_PLATINUM")

    # Wait for response with timeout
    start_time = Time.now
    timeout = 2.0

    while Time.now - start_time < timeout
      Graphics.update
      Input.update
      $multiplayer.update if $multiplayer

      # Check if balance was updated
      if $PokemonGlobal.platinum_balance
        balance = $PokemonGlobal.platinum_balance
        ##MultiplayerDebug.info("PLATINUM", "Balance received: #{balance} Pt")
        return balance
      end
    end

    ##MultiplayerDebug.warn("PLATINUM", "Balance request timeout")
    return nil
  end

  # Request to spend platinum on server
  # Server validates balance and triggers autosave on success
  # @param amount [Integer] Amount to spend (must be positive)
  # @param reason [String] Reason for spending (for server logging)
  # @return [Boolean] true if transaction succeeded, false otherwise
  def self.spend(amount, reason = "purchase")
    return false unless $multiplayer&.connected?

    if amount <= 0
      ##MultiplayerDebug.warn("PLATINUM", "Invalid amount: #{amount}")
      return false
    end

    ##MultiplayerDebug.info("PLATINUM", "Requesting spend: #{amount} Pt (#{reason})")

    # Clear previous transaction result
    $PokemonGlobal.last_platinum_transaction = nil

    # Send spend request
    $multiplayer.send_message("SPEND_PLATINUM:#{amount},#{reason}")

    # Wait for response with timeout
    start_time = Time.now
    timeout = 3.0  # Longer timeout for transactions

    while Time.now - start_time < timeout
      Graphics.update
      Input.update
      $multiplayer.update if $multiplayer

      # Check transaction result
      if $PokemonGlobal.last_platinum_transaction
        result = $PokemonGlobal.last_platinum_transaction
        $PokemonGlobal.last_platinum_transaction = nil

        case result
        when :SUCCESS
          ##MultiplayerDebug.info("PLATINUM", "Transaction succeeded")
          # Refresh balance from server
          get_balance
          return true
        when :INSUFFICIENT
          ##MultiplayerDebug.warn("PLATINUM", "Insufficient balance")
          return false
        when :ERROR
          ##MultiplayerDebug.warn("PLATINUM", "Transaction error")
          return false
        else
          ##MultiplayerDebug.warn("PLATINUM", "Unknown result: #{result}")
          return false
        end
      end
    end

    ##MultiplayerDebug.warn("PLATINUM", "Transaction timeout")
    return false
  end

  # Get cached balance without querying server
  # @return [Integer] Cached balance, or 0 if not available
  def self.cached_balance
    return 0 unless defined?($PokemonGlobal) && $PokemonGlobal
    return $PokemonGlobal.platinum_balance || 0
  end

  # Check if player has enough platinum (uses cached balance)
  # @param amount [Integer] Amount to check
  # @return [Boolean] true if cached balance >= amount
  def self.can_afford?(amount)
    return cached_balance >= amount
  end

  # Internal: Update cached balance (called by client message handler)
  # @param amount [Integer] New balance from server
  def self.set_balance(amount)
    return unless defined?($PokemonGlobal) && $PokemonGlobal
    $PokemonGlobal.platinum_balance = amount
    ##MultiplayerDebug.info("PLATINUM", "Balance updated: #{amount} Pt")
  end

  # Internal: Set transaction result (called by client message handler)
  # @param result [Symbol] :SUCCESS, :INSUFFICIENT, :ERROR
  def self.set_transaction_result(result)
    return unless defined?($PokemonGlobal) && $PokemonGlobal
    $PokemonGlobal.last_platinum_transaction = result
    ##MultiplayerDebug.info("PLATINUM", "Transaction result: #{result}")
  end

  # Internal: Store auth token for current server (called by client on AUTH_TOKEN)
  # @param token [String] Authentication token from server
  def self.store_token(server_key, token)
    return unless defined?($PokemonGlobal) && $PokemonGlobal
    $PokemonGlobal.platinum_tokens ||= {}
    $PokemonGlobal.platinum_tokens[server_key] = token
    ##MultiplayerDebug.info("PLATINUM", "Token stored for server: #{server_key}")
  end

  # Internal: Get auth token for current server
  # @param server_key [String] "host:port" identifier
  # @return [String, nil] Token if exists, nil otherwise
  def self.get_token(server_key)
    return nil unless defined?($PokemonGlobal) && $PokemonGlobal
    $PokemonGlobal.platinum_tokens ||= {}
    return $PokemonGlobal.platinum_tokens[server_key]
  end
end
