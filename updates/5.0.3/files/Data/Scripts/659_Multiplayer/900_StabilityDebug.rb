#===============================================================================
# STABILITY UPDATE: Debug Logger
#===============================================================================
# Dedicated log file for stability overhaul investigation.
# All 90x modules log here so you can isolate stability issues from
# the main multiplayer_debug.log.
#
# Log file: Logs/stability_debug.log
#===============================================================================

STABILITY_LOG_DIR = "Logs"

begin
  Dir.mkdir(STABILITY_LOG_DIR) unless File.directory?(STABILITY_LOG_DIR)
  STABILITY_LOG_FILE = File.join(STABILITY_LOG_DIR, "stability_debug.log")
rescue => e
  STABILITY_LOG_FILE = "stability_debug.log"
end

module StabilityDebug
  LOG_MUTEX = Mutex.new
  MAX_BYTES = 2 * 1024 * 1024  # 2 MB before rotation
  ROTATE_CHECK = 200           # check every N writes

  @@queue   = []
  @@running = true
  @@writes  = 0

  # Background writer (same pattern as MultiplayerDebug)
  @@worker = Thread.new do
    Thread.current[:name] = "STAB-LOG"
    loop do
      item = nil
      LOG_MUTEX.synchronize { item = @@queue.shift }
      if item
        begin
          @@writes += 1
          rotate_if_needed if (@@writes % ROTATE_CHECK) == 0
          safe = item.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
          File.open(STABILITY_LOG_FILE, "a:UTF-8") { |f| f.write(safe) }
        rescue => e
          print "StabilityDebug write failed: #{e.class}\n"
        end
      else
        sleep(0.01)
      end
      break unless @@running
    end
  end

  at_exit do
    begin
      @@running = false
      300.times do
        empty = LOG_MUTEX.synchronize { @@queue.empty? }
        break if empty
        sleep(0.01)
      end
    rescue; end
  end

  # --- Public API ---
  def self.info(tag, msg);  log("INFO",  tag, msg); end
  def self.warn(tag, msg);  log("WARN",  tag, msg); end
  def self.error(tag, msg); log("ERROR", tag, msg); end

  def self.separator(label = nil)
    line = "=" * 70
    if label
      info("-----", line)
      info("-----", label)
      info("-----", line)
    else
      info("-----", line)
    end
  end

  # --- Internals ---
  def self.log(level, tag, message)
    begin
      time = Time.now.strftime("%H:%M:%S.") + ("%03d" % (Time.now.usec / 1000))
      thr  = Thread.current[:name] || ("T" + Thread.current.object_id.to_s(16))
      entry = "[#{time}][#{level}][#{tag}][#{thr}] #{message}\n"
      LOG_MUTEX.synchronize { @@queue << entry }
    rescue; end
  end

  def self.rotate_if_needed
    begin
      return unless File.exist?(STABILITY_LOG_FILE)
      return if File.size(STABILITY_LOG_FILE) < MAX_BYTES
      ts = Time.now.strftime("%Y%m%d_%H%M%S")
      rotated = STABILITY_LOG_FILE.sub(/\.log\z/, "_#{ts}.log")
      File.rename(STABILITY_LOG_FILE, rotated)
    rescue
      begin
        File.open(STABILITY_LOG_FILE, "w") { |f| f.write("") }
      rescue; end
    end
  end
end

StabilityDebug.info("INIT", "StabilityDebug loaded - logging to #{STABILITY_LOG_FILE}")

#===============================================================================
# DebugMutex — drop-in Mutex replacement that logs ownership & contention
#===============================================================================
class DebugMutex
  def initialize(name)
    @name   = name
    @mutex  = Mutex.new
    @owner  = nil      # "GAME(id)" or "NET(id)"
    @locked_at  = nil
    @lock_site  = nil
  end

  def synchronize(&block)
    tid   = Thread.current.object_id
    tname = Thread.current == Thread.main ? "GAME" : "NET"
    me    = "#{tname}(#{tid})"
    site  = caller[0].to_s.gsub(/.*Scripts\//, "")

    # Log contention: another thread already holds this mutex
    if @mutex.locked? && !@mutex.owned?
      held_sec = @locked_at ? (Time.now - @locked_at).round(3) : "?"
      StabilityDebug.warn("MUTEX", "#{@name}: #{me} BLOCKED — held by #{@owner} for #{held_sec}s at #{@lock_site}  |  waiter at #{site}") if defined?(StabilityDebug)
    end

    @mutex.synchronize do
      @owner     = me
      @locked_at = Time.now
      @lock_site = site
      begin
        block.call
      ensure
        @owner     = nil
        @locked_at = nil
        @lock_site = nil
      end
    end
  rescue ThreadError => e
    # Deadlock! (recursive lock attempt on non-reentrant Mutex)
    StabilityDebug.error("MUTEX", "#{@name}: DEADLOCK by #{me} at #{site} — already held by #{@owner} at #{@lock_site}: #{e.message}") if defined?(StabilityDebug)
    raise
  end

  def locked?; @mutex.locked?; end
  def owned?;  @mutex.owned?;  end
end
