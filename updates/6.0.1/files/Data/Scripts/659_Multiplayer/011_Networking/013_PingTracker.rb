#===============================================================================
# MODULE: Ping Tracker - Displays player latency in player list
#===============================================================================
# Measures round-trip time (RTT) for each player and displays it in the UI.
# Can be easily disabled by deleting this file.
#===============================================================================

module PingTracker
  @player_pings = {}  # { session_id => ping_ms }
  @last_ping_time = 0
  @ping_sequence = 0

  # Store ping for a specific player
  def self.set_ping(session_id, ping_ms)
    @player_pings[session_id.to_s] = ping_ms.to_i
  end

  # Get ping for a specific player
  def self.get_ping(session_id)
    @player_pings[session_id.to_s] || 0
  end

  # Get all pings
  def self.all_pings
    @player_pings.dup
  end

  # Clear ping for a player (when they disconnect)
  def self.clear_ping(session_id)
    @player_pings.delete(session_id.to_s)
  end

  # Clear all pings
  def self.clear_all
    @player_pings.clear
  end

  # Get color based on ping value
  def self.ping_color(ping_ms)
    return Color.new(0, 255, 0) if ping_ms < 50      # Green: Excellent
    return Color.new(144, 238, 144) if ping_ms < 100 # Light Green: Good
    return Color.new(255, 255, 0) if ping_ms < 150   # Yellow: Fair
    return Color.new(255, 165, 0) if ping_ms < 250   # Orange: Poor
    return Color.new(255, 0, 0)                       # Red: Bad
  end

  # Format ping for display
  def self.format_ping(ping_ms)
    return "?ms" if ping_ms == 0
    return "#{ping_ms}ms"
  end
end

#===============================================================================
# Hook MultiplayerClient to track ping
#===============================================================================
module MultiplayerClient
  class << self
    # Add ping tracking attributes
    attr_accessor :last_ping_sent_at
    attr_accessor :ping_sequence_id
    attr_accessor :my_last_ping

    # Hook connect to initialize ping tracking
    alias ping_tracker_original_connect connect
    def connect(*args)
      @last_ping_sent_at = nil
      @ping_sequence_id = 0
      @my_last_ping = 0
      ping_tracker_original_connect(*args)
    end

    # Hook disconnect to clear pings
    alias ping_tracker_original_disconnect disconnect
    def disconnect
      PingTracker.clear_all
      ping_tracker_original_disconnect
    end

    # Add method to send ping request
    def send_ping_request
      return unless @connected

      @ping_sequence_id = (@ping_sequence_id || 0) + 1
      @last_ping_sent_at = Time.now

      # Send PING with timestamp
      send_data("PING:#{@ping_sequence_id}:#{@last_ping_sent_at.to_f}")

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PING", "Sent PING ##{@ping_sequence_id}")
      end
    end

    # Get my own ping
    def my_ping
      @my_last_ping || 0
    end
  end
end

#===============================================================================
# Add periodic ping sending
#===============================================================================
# Hook the sync loop to start ping thread
module MultiplayerClient
  class << self
    alias ping_tracker_original_start_sync_loop start_sync_loop
    def start_sync_loop
      # Call original
      ping_tracker_original_start_sync_loop

      # Start ping thread if not already running
      if !@ping_thread || !@ping_thread.alive?
        @ping_thread = Thread.new do
          Thread.current.abort_on_exception = false
          loop do
            break unless @connected
            begin
              # Send ping every 5 seconds
              send_ping_request if @connected
              sleep(5)
            rescue => e
              MultiplayerDebug.error("PING-THREAD", "Ping thread error: #{e.message}") if defined?(MultiplayerDebug)
            end
          end
        end
      end
    end
  end
end

#===============================================================================
# Note: PONG response handler is in 002_Client.rb listen thread
#===============================================================================
# The client's listen thread processes incoming PONG messages and calls
# PingTracker.set_ping() to store the RTT values.
#===============================================================================

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("PING-TRACKER", "=" * 60)
  MultiplayerDebug.info("PING-TRACKER", "Ping tracker initialized")
  MultiplayerDebug.info("PING-TRACKER", "- Sends PING every 5 seconds")
  MultiplayerDebug.info("PING-TRACKER", "- Tracks RTT for all players")
  MultiplayerDebug.info("PING-TRACKER", "- Color-coded display (green/yellow/orange/red)")
  MultiplayerDebug.info("PING-TRACKER", "=" * 60)
end
