
# ===========================================
# File: 001_Debug.rb
# Purpose: Global debug logger for Multiplayer mod
# ===========================================

MULTI_LOG_DIR  = "Logs"

begin
  Dir.mkdir(MULTI_LOG_DIR) unless File.directory?(MULTI_LOG_DIR)
  MULTI_LOG_FILE = File.join(MULTI_LOG_DIR, "multiplayer_debug.log")
rescue => e
  # Fallback to project root if Logs/ can't be created
  print "Could not create log dir: #{e.message}\n"
  MULTI_LOG_FILE = "multiplayer_debug.log"
end

module MultiplayerDebug
  LOG_MUTEX = Mutex.new

  # --- Rotation settings ---
  MAX_BYTES = 2 * 1024 * 1024       # 2MB
  ROTATE_CHECK_INTERVAL = 200       # check every N writes

  # --- Internal state ---
  @@queue   = []                    # RGSS-safe simple queue
  @@running = true
  @@writes  = 0

  # --- Background worker (non-blocking logs) ---
  @@worker = Thread.new do
    Thread.current[:name] = "LOGGER"
    loop do
      item = nil
      LOG_MUTEX.synchronize { item = @@queue.shift }
      if item
        begin
          @@writes += 1
          rotate_if_needed if (@@writes % ROTATE_CHECK_INTERVAL) == 0
          # Force UTF-8 encoding with replacement for invalid sequences
          safe_item = item.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
          File.open(MULTI_LOG_FILE, "a:UTF-8") { |f| f.write(safe_item) }
        rescue => e
          print "Debug logging failed: #{e.class}\n"
        end
      else
        sleep(0.01)  # yield without burning CPU
      end
      break unless @@running
    end
  end

  at_exit do
    begin
      @@running = false
      # Drain remaining log lines (up to ~3s)
      300.times do
        empty = LOG_MUTEX.synchronize { @@queue.empty? }
        break if empty
        sleep(0.01)
      end
    rescue => e
      print "Logger shutdown failed: #{e.class}: #{e.message}\n"
    end
  end

  # --- Public API ---
  def self.info(code, msg);  log(code, msg); end
  def self.warn(code, msg);  log(code, msg); end
  def self.error(code, msg); log(code, msg); end

  # Log an exception with backtrace
  def self.ex(code, e, prefix=nil)
    begin
      bt  = e.backtrace ? e.backtrace.join("\n") : "(no backtrace)"
      msg = "#{prefix ? prefix + ' - ' : ''}#{e.class}: #{e.message}\n#{bt}"
      error(code, msg)
    rescue => err
      print "Exception logging failed: #{err.class}: #{err.message}\n"
    end
  end

  # --- Internals ---
  def self.log(code, message)
    begin
      time = Time.now.strftime("%Y-%m-%d %H:%M:%S")
      thr  = Thread.current[:name] || ("T" + Thread.current.object_id.to_s(16))
      entry = "[#{time}] [#{code}] [#{thr}] #{message}\n"
      enqueue(entry)
    rescue => e
      print "Inline log failed: #{e.class}: #{e.message}\n"
    end
  end

  def self.enqueue(line)
    LOG_MUTEX.synchronize { @@queue << line }
  end

  def self.rotate_if_needed
    begin
      return unless File.exist?(MULTI_LOG_FILE)
      return if File.size(MULTI_LOG_FILE) < MAX_BYTES
      ts = Time.now.strftime("%Y%m%d_%H%M%S")
      rotated = MULTI_LOG_FILE.sub(/\.log\z/, "_#{ts}.log")
      File.rename(MULTI_LOG_FILE, rotated)
    rescue => e
      # If rename fails (e.g., locked), truncate as a last resort
      begin
        File.open(MULTI_LOG_FILE, "w") { |f| f.write("") }
      rescue => e2
        print "Log rotate/truncate failed: #{e.class}/#{e2.class}\n"
      end
    end
  end
end

##MultiplayerDebug.info("D-000", "Debug system initialized successfully.")
