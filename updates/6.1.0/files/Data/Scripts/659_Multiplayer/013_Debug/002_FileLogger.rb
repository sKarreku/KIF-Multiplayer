#===============================================================================
# COOP FILE LOGGER - Persistent logging for 3-player battle diagnostics
#===============================================================================
# Purpose: Write all sync events to a file for post-mortem analysis
#          when testing with real 3 players
#
# Log file location: KIFM/coop_debug.log
#===============================================================================

module CoopFileLogger
  LOG_FILE = "KIFM/coop_debug.log"
  MAX_FILE_SIZE = 5 * 1024 * 1024  # 5 MB max, then rotate

  @enabled = true
  @mutex = Mutex.new
  @session_id = nil

  def self.enable
    @enabled = true
    log("LOGGER", "File logging ENABLED")
  end

  def self.disable
    log("LOGGER", "File logging DISABLED")
    @enabled = false
  end

  def self.enabled?
    @enabled
  end

  def self.log(tag, message)
    return unless @enabled

    @mutex.synchronize do
      begin
        # Rotate log if too large
        rotate_if_needed

        # Get session ID if not set
        @session_id ||= (MultiplayerClient.session_id rescue "UNKNOWN")

        # Format: [timestamp] [SID] [TAG] message
        timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S.%L")
        line = "[#{timestamp}] [SID:#{@session_id}] [#{tag}] #{message}\n"

        # Append to file
        File.open(LOG_FILE, "a") { |f| f.write(line) }
      rescue => e
        # Silent fail - don't crash the game for logging
        puts "[COOP-LOG-ERROR] #{e.message}" rescue nil
      end
    end
  end

  def self.rotate_if_needed
    return unless File.exist?(LOG_FILE)
    return if File.size(LOG_FILE) < MAX_FILE_SIZE

    # Rotate: rename current to .old, start fresh
    old_file = LOG_FILE + ".old"
    File.delete(old_file) if File.exist?(old_file)
    File.rename(LOG_FILE, old_file)
  end

  def self.log_separator(title = nil)
    log("=====", "=" * 60)
    log("=====", title) if title
    log("=====", "=" * 60)
  end

  # Log battle start with full context
  def self.log_battle_start(is_initiator, ally_sids, battle_id, foe_count)
    log_separator("BATTLE START")
    log("BATTLE", "Role: #{is_initiator ? 'INITIATOR' : 'NON-INITIATOR'}")
    log("BATTLE", "Battle ID: #{battle_id}")
    log("BATTLE", "Ally SIDs: #{ally_sids.inspect}")
    log("BATTLE", "Foe count: #{foe_count}")
    log("BATTLE", "My SID: #{MultiplayerClient.session_id rescue 'UNKNOWN'}")
  end

  # Log message sent
  def self.log_sent(msg_type, payload_size, target_sids = nil)
    targets = target_sids ? " -> #{target_sids.inspect}" : ""
    log("SENT", "#{msg_type} (#{payload_size} bytes)#{targets}")
  end

  # Log message received
  def self.log_received(msg_type, from_sid, payload_size)
    log("RECV", "#{msg_type} from SID:#{from_sid} (#{payload_size} bytes)")
  end

  # Log waiting state
  def self.log_waiting(what, expected_sids, timeout_sec)
    log("WAIT", "Waiting for #{what} from: #{expected_sids.inspect} (timeout: #{timeout_sec}s)")
  end

  # Log sync complete
  def self.log_sync_complete(what, elapsed_sec)
    log("SYNC", "#{what} complete in #{elapsed_sec}s")
  end

  # Log sync timeout
  def self.log_sync_timeout(what, missing_sids)
    log("TIMEOUT", "#{what} TIMEOUT - missing: #{missing_sids.inspect}")
  end

  # Log potential deadlock warning
  def self.log_deadlock_warning(my_sid, waiting_for_sids)
    log("DEADLOCK", "!!! POTENTIAL DEADLOCK !!!")
    log("DEADLOCK", "My SID: #{my_sid}")
    log("DEADLOCK", "Waiting for: #{waiting_for_sids.inspect}")
    log("DEADLOCK", "If they're also waiting for us, we're deadlocked!")
  end

  # Log battle end
  def self.log_battle_end(decision, duration_sec)
    log("BATTLE", "Battle ended: decision=#{decision}, duration=#{duration_sec}s")
    log_separator("BATTLE END")
  end

  # Log error
  def self.log_error(tag, message, exception = nil)
    log("ERROR", "[#{tag}] #{message}")
    if exception
      log("ERROR", "  Exception: #{exception.class}: #{exception.message}")
      log("ERROR", "  Backtrace: #{exception.backtrace.first(5).join(' | ')}") if exception.backtrace
    end
  end

  # Dump current state
  def self.dump_state
    log_separator("STATE DUMP")

    # Battle state
    if defined?(CoopBattleState)
      log("STATE", "CoopBattleState.in_coop_battle?: #{CoopBattleState.in_coop_battle?}")
      log("STATE", "CoopBattleState.am_i_initiator?: #{CoopBattleState.am_i_initiator?}")
      log("STATE", "CoopBattleState.battle_id: #{CoopBattleState.battle_id}")
      log("STATE", "CoopBattleState.get_ally_sids: #{CoopBattleState.get_ally_sids.inspect}")
    end

    # Transaction state
    if defined?(CoopBattleTransaction)
      log("STATE", "CoopBattleTransaction.active?: #{CoopBattleTransaction.active?}")
      log("STATE", "CoopBattleTransaction.cancelled?: #{CoopBattleTransaction.cancelled?}")
    end

    # Joined SIDs
    if defined?(MultiplayerClient)
      joined = MultiplayerClient.instance_variable_get(:@coop_battle_joined_sids) || []
      log("STATE", "joined_ally_sids: #{joined.inspect}")
    end

    # Action sync
    if defined?(CoopActionSync)
      log("STATE", "CoopActionSync.current_turn: #{CoopActionSync.current_turn}")
      stats = CoopActionSync.export_sync_stats rescue {}
      log("STATE", "CoopActionSync stats: #{stats.inspect}")
    end

    log_separator
  end

  # Clear log file
  def self.clear
    @mutex.synchronize do
      File.delete(LOG_FILE) if File.exist?(LOG_FILE)
    end
    log("LOGGER", "Log file cleared")
  end
end

#===============================================================================
# Auto-hook into key sync points
#===============================================================================

# Hook into CoopBattleState
if defined?(CoopBattleState)
  class << CoopBattleState
    alias _file_logger_create_battle create_battle unless method_defined?(:_file_logger_create_battle)

    def create_battle(**args)
      result = _file_logger_create_battle(**args)
      CoopFileLogger.log_battle_start(
        args[:is_initiator],
        args[:ally_sids] || [],
        result,
        args[:foe_count] || 0
      )
      result
    end

    alias _file_logger_end_battle end_battle unless method_defined?(:_file_logger_end_battle)

    def end_battle
      duration = battle_duration rescue 0
      CoopFileLogger.log_battle_end(0, duration)
      _file_logger_end_battle
    end
  end
end

# Hook into MultiplayerClient.send_data for coop messages
if defined?(MultiplayerClient)
  module MultiplayerClient
    class << self
      alias _file_logger_send_data send_data unless method_defined?(:_file_logger_send_data)

      def send_data(message, **opts)
        # Log coop messages
        if message.is_a?(String) && message.start_with?("COOP_")
          msg_type = message.split(":").first
          payload_size = message.length
          CoopFileLogger.log_sent(msg_type, payload_size)
        end

        _file_logger_send_data(message, **opts)
      end
    end
  end
end

# Hook into _handle_coop_battle_joined
if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:_handle_coop_battle_joined)
  module MultiplayerClient
    class << self
      alias _file_logger_handle_joined _handle_coop_battle_joined unless method_defined?(:_file_logger_handle_joined)

      def _handle_coop_battle_joined(from_sid)
        CoopFileLogger.log_received("COOP_BATTLE_JOINED", from_sid, 0)
        _file_logger_handle_joined(from_sid)
      end
    end
  end
end

puts "[COOP-FILE-LOG] File logger installed - logs to #{CoopFileLogger::LOG_FILE}"
