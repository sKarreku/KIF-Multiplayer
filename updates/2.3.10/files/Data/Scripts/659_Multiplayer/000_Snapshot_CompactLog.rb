#===============================================================================
# Snapshot Compact File Logger
#===============================================================================

SNAPSHOT_LOG_DIR = "Logs"
begin
  Dir.mkdir(SNAPSHOT_LOG_DIR) unless File.directory?(SNAPSHOT_LOG_DIR)
  SNAPSHOT_LOG_FILE = File.join(SNAPSHOT_LOG_DIR, "snapshot_debug.log")
rescue => e
  SNAPSHOT_LOG_FILE = "snapshot_debug.log"
end

module SnapshotLog
  LOG_MUTEX = Mutex.new

  def self.write(msg)
    LOG_MUTEX.synchronize do
      File.open(SNAPSHOT_LOG_FILE, "a") { |f| f.write("#{msg}\n") }
    end
  rescue => e
    # Fail silently
  end

  def self.timestamp_ms
    (Time.now.to_f * 1000).round
  end

  def self.log_nudge_sent(ally_sids)
    ts = timestamp_ms
    write("[#{ts}] NUDGE_SENT allies=#{ally_sids.join(',')}")
  end

  def self.log_snapshot_received(from_sid, party_size)
    ts = timestamp_ms
    write("[#{ts}] SNAPSHOT_RX sid=#{from_sid} party_size=#{party_size}")
  end

  def self.log_wait_start(expected_sids)
    ts = timestamp_ms
    write("[#{ts}] WAIT_START expecting=#{expected_sids.join(',')}")
  end

  def self.log_wait_check(frame, ready_sids, pending_sids, elapsed_ms)
    ts = timestamp_ms
    write("[#{ts}] WAIT_CHECK frame=#{frame} elapsed=#{elapsed_ms}ms ready=#{ready_sids.join(',')} pending=#{pending_sids.join(',')}")
  end

  def self.log_wait_complete(total_ms, ready_count, expected_count, timed_out)
    ts = timestamp_ms
    status = timed_out ? "TIMEOUT" : "COMPLETE"
    write("[#{ts}] WAIT_#{status} elapsed=#{total_ms}ms ready=#{ready_count}/#{expected_count}")
  end

  def self.log_snapshot_age(sid, age_ms, is_fresh)
    ts = timestamp_ms
    freshness = is_fresh ? "FRESH" : "STALE"
    write("[#{ts}] SNAPSHOT_AGE sid=#{sid} age=#{age_ms}ms status=#{freshness}")
  end

  def self.log_battle_start(ally_sids)
    ts = timestamp_ms
    write("[#{ts}] BATTLE_START allies=#{ally_sids.join(',')}")
  end

  def self.log_vanilla_fallback(reason)
    ts = timestamp_ms
    write("[#{ts}] VANILLA_FALLBACK reason=#{reason}")
  end
end
