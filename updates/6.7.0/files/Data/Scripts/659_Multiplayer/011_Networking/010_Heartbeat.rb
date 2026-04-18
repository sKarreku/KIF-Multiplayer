#===============================================================================
# STABILITY MODULE 8: Heartbeat During Action Sync
#===============================================================================
# Problem: During action sync wait, if a player disconnects, others wait the
#          full timeout (20-25s). The COOP_BATTLE_ABORT message may arrive late.
#
# Solution:
#   - Send COOP_HEARTBEAT every 5s during action sync wait
#   - Track last heartbeat per ally
#   - If no heartbeat from an ally for 10s, treat as disconnected
#   - Remove disconnected allies from expected_sids (don't wait for them)
#
# Heartbeat sending is triggered by 902_ThreadSafe_ActionSync.rb (calls
# CoopHeartbeat.send_heartbeat in the wait loop every 300 frames).
#===============================================================================

module CoopHeartbeat
  @last_heartbeat = {}  # { sid_string => Time }
  @hb_mutex = DebugMutex.new("Heartbeat")
  HEARTBEAT_INTERVAL = 5.0   # Send every 5s
  DISCONNECT_THRESHOLD = 10.0 # Consider disconnected after 10s silence

  #---------------------------------------------------------------------------
  # Send a heartbeat to allies (called from action sync wait loop)
  #---------------------------------------------------------------------------
  def self.send_heartbeat(battle_id, turn_num)
    return unless defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:send_data)
    begin
      connected = MultiplayerClient.instance_variable_get(:@connected) rescue false
      return unless connected

      MultiplayerClient.send_data("COOP_HEARTBEAT:#{battle_id}|#{turn_num}")
      StabilityDebug.info("HEARTBEAT", "Sent heartbeat: battle=#{battle_id} turn=#{turn_num}") if defined?(StabilityDebug)
    rescue => e
      StabilityDebug.warn("HEARTBEAT", "Failed to send heartbeat: #{e.class}: #{e.message}") if defined?(StabilityDebug)
    end
  end

  #---------------------------------------------------------------------------
  # Receive heartbeat from ally (called from listener thread)
  #---------------------------------------------------------------------------
  def self.receive_heartbeat(from_sid, battle_id, turn_num)
    @hb_mutex.synchronize do
      @last_heartbeat[from_sid.to_s] = Time.now
    end
    StabilityDebug.info("HEARTBEAT", "Received from #{from_sid}: battle=#{battle_id} turn=#{turn_num}") if defined?(StabilityDebug)
  end

  #---------------------------------------------------------------------------
  # Check if an ally appears disconnected (no heartbeat for DISCONNECT_THRESHOLD)
  # Returns array of disconnected SIDs from the given list
  #---------------------------------------------------------------------------
  def self.check_disconnected(expected_sids)
    disconnected = []
    now = Time.now

    @hb_mutex.synchronize do
      expected_sids.each do |sid|
        sid_key = sid.to_s
        last_hb = @last_heartbeat[sid_key]

        # Only flag as disconnected if we've received at least one heartbeat
        # (otherwise they might just be slow to start)
        if last_hb && (now - last_hb) > DISCONNECT_THRESHOLD
          disconnected << sid_key
          StabilityDebug.warn("HEARTBEAT", "Ally #{sid_key} appears disconnected (last heartbeat #{(now - last_hb).round(1)}s ago)") if defined?(StabilityDebug)
        end
      end
    end

    disconnected
  end

  #---------------------------------------------------------------------------
  # Reset heartbeat tracking (call at battle start/end)
  #---------------------------------------------------------------------------
  def self.reset
    @hb_mutex.synchronize do
      @last_heartbeat.clear
    end
    StabilityDebug.info("HEARTBEAT", "Heartbeat tracking reset") if defined?(StabilityDebug)
  end

  #---------------------------------------------------------------------------
  # Register allies at battle start (NO timestamp yet)
  # Disconnect detection only kicks in after we receive a REAL heartbeat
  # from them (meaning they entered the sync wait loop). This prevents
  # false disconnects while players are still picking moves.
  #---------------------------------------------------------------------------
  def self.initialize_allies(ally_sids)
    @hb_mutex.synchronize do
      ally_sids.each do |sid|
        @last_heartbeat[sid.to_s] = nil  # nil = not tracking yet
      end
    end
    StabilityDebug.info("HEARTBEAT", "Registered #{ally_sids.length} allies (tracking starts on first heartbeat)") if defined?(StabilityDebug)
  end
end

#===============================================================================
# Initialize heartbeat when battle starts
#===============================================================================
if defined?(CoopBattleState)
  module CoopBattleState
    class << self
      if method_defined?(:create_battle)
        alias _create_battle_before_heartbeat create_battle

        def create_battle(**kwargs)
          result = _create_battle_before_heartbeat(**kwargs)
          # Initialize heartbeat tracking for allies
          if defined?(CoopHeartbeat) && kwargs[:ally_sids]
            CoopHeartbeat.initialize_allies(kwargs[:ally_sids])
          end
          result
        end
      end
    end
  end
end

#===============================================================================
# Reset heartbeat when battle ends
#===============================================================================
if defined?(CoopBattleState)
  module CoopBattleState
    class << self
      # Check if we already aliased from 907 (end_battle_before_relay)
      if method_defined?(:_end_battle_before_relay)
        alias _end_battle_before_heartbeat end_battle

        def end_battle
          CoopHeartbeat.reset if defined?(CoopHeartbeat)
          _end_battle_before_heartbeat
        end
      elsif method_defined?(:end_battle)
        alias _end_battle_before_heartbeat_standalone end_battle

        def end_battle
          CoopHeartbeat.reset if defined?(CoopHeartbeat)
          _end_battle_before_heartbeat_standalone
        end
      end
    end
  end
end

#===============================================================================
# Integrate disconnect detection into action sync wait loop
# The 902 module calls CoopHeartbeat.send_heartbeat every 300 frames.
# We also need to CHECK for disconnects. We add this via a hook that
# the 902 wait loop can call.
#===============================================================================
if defined?(CoopActionSync)
  module CoopActionSync
    # Check for disconnected allies and remove them from expected list
    def self.check_heartbeat_disconnects
      return unless defined?(CoopHeartbeat)

      expected = @stability_mutex.synchronize { @expected_sids.dup } rescue []
      return if expected.empty?

      disconnected = CoopHeartbeat.check_disconnected(expected)
      return if disconnected.empty?

      @stability_mutex.synchronize do
        disconnected.each do |sid|
          if @expected_sids.include?(sid)
            @expected_sids.delete(sid)
            StabilityDebug.warn("HEARTBEAT", "Removed disconnected ally #{sid} from expected_sids") if defined?(StabilityDebug)
          end
        end
        # Re-check sync completeness
        check_sync_complete
      end
    end
  end
end

StabilityDebug.info("HEARTBEAT", "Module 908_Heartbeat loaded") if defined?(StabilityDebug)
