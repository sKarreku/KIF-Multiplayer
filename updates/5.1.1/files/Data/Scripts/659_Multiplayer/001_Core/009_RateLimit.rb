#===============================================================================
# MODULE 2: Rate Limiting
#===============================================================================
# Prevents DoS attacks via message flooding
# Limits: 25 messages/sec for battle actions, 15/sec for SYNC
# Server-side enforcement with per-client tracking
#===============================================================================

module RateLimit
  # Rate limits (messages per second)
  SYNC_LIMIT = 30           # Position updates (10Hz nominal + buffer)
  ACTION_LIMIT = 25         # Battle actions (faster battles need headroom)
  GENERAL_LIMIT = 50        # Other messages (party push, invites, etc.)

  # Time window for rate calculation (seconds)
  WINDOW_SIZE = 1.0

  # Client-side tracker (prevents sending too fast)
  @client_counters = {}
  @client_mutex = Mutex.new

  module_function

  #-----------------------------------------------------------------------------
  # Client-side: Check if we can send a message of given type
  # Returns: true if allowed, false if rate limited
  #-----------------------------------------------------------------------------
  def can_send?(message_type)
    @client_mutex.synchronize do
      now = Time.now.to_f
      @client_counters[message_type] ||= []

      # Remove old timestamps outside the window
      @client_counters[message_type].delete_if { |ts| now - ts > WINDOW_SIZE }

      # Get limit for this message type
      limit = get_limit(message_type)

      # Check if we're under the limit
      if @client_counters[message_type].length < limit
        @client_counters[message_type] << now
        true
      else
        false
      end
    end
  end

  #-----------------------------------------------------------------------------
  # Client-side: Record a sent message (for tracking)
  #-----------------------------------------------------------------------------
  def record_send(message_type)
    @client_mutex.synchronize do
      now = Time.now.to_f
      @client_counters[message_type] ||= []
      @client_counters[message_type] << now
    end
  end

  #-----------------------------------------------------------------------------
  # Get rate limit for message type
  #-----------------------------------------------------------------------------
  def get_limit(message_type)
    case message_type
    when :SYNC
      SYNC_LIMIT
    when :ACTION, :RNG, :SWITCH, :RUN_AWAY
      ACTION_LIMIT
    when :TRAINER_SYNC
      10  # Trainer battle sync messages (invites, joins, start)
    when :PVP_INVITE
      3   # PvP invitations (prevent spam)
    else
      GENERAL_LIMIT
    end
  end

  #-----------------------------------------------------------------------------
  # Reset all counters (for cleanup)
  #-----------------------------------------------------------------------------
  def reset
    @client_mutex.synchronize do
      @client_counters.clear
    end
  end

  #-----------------------------------------------------------------------------
  # Get current message rate for a type (for debugging)
  #-----------------------------------------------------------------------------
  def current_rate(message_type)
    @client_mutex.synchronize do
      return 0 unless @client_counters[message_type]
      now = Time.now.to_f
      @client_counters[message_type].delete_if { |ts| now - ts > WINDOW_SIZE }
      @client_counters[message_type].length
    end
  end
end

#===============================================================================
# Server-side Rate Limiter (for server.rb integration)
#===============================================================================
module ServerRateLimit
  # Per-client message counters: { socket => { message_type => [timestamps] } }
  @counters = {}
  @mutex = Mutex.new

  module_function

  #-----------------------------------------------------------------------------
  # Check if a client can send this message type
  # Returns: true if allowed, false if rate limited
  #-----------------------------------------------------------------------------
  def allow?(client_socket, message_type)
    @mutex.synchronize do
      now = Time.now.to_f
      @counters[client_socket] ||= {}
      @counters[client_socket][message_type] ||= []

      # Remove old timestamps
      @counters[client_socket][message_type].delete_if { |ts| now - ts > RateLimit::WINDOW_SIZE }

      # Get limit
      limit = RateLimit.get_limit(message_type)

      # Check limit
      if @counters[client_socket][message_type].length < limit
        @counters[client_socket][message_type] << now
        true
      else
        false
      end
    end
  end

  #-----------------------------------------------------------------------------
  # Remove client from tracking (on disconnect)
  #-----------------------------------------------------------------------------
  def remove_client(client_socket)
    @mutex.synchronize do
      @counters.delete(client_socket)
    end
  end

  #-----------------------------------------------------------------------------
  # Get current rate for client (for logging/debugging)
  #-----------------------------------------------------------------------------
  def current_rate(client_socket, message_type)
    @mutex.synchronize do
      return 0 unless @counters[client_socket] && @counters[client_socket][message_type]
      now = Time.now.to_f
      @counters[client_socket][message_type].delete_if { |ts| now - ts > RateLimit::WINDOW_SIZE }
      @counters[client_socket][message_type].length
    end
  end
end

##MultiplayerDebug.info("MODULE-2-RL", "Rate limiting loaded: SYNC=#{RateLimit::SYNC_LIMIT}/s, ACTION=#{RateLimit::ACTION_LIMIT}/s, GENERAL=#{RateLimit::GENERAL_LIMIT}/s")
