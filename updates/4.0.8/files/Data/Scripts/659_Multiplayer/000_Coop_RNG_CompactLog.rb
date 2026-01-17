#===============================================================================
# RNG Compact File Logger
#===============================================================================

RNG_LOG_DIR = "Logs"
begin
  Dir.mkdir(RNG_LOG_DIR) unless File.directory?(RNG_LOG_DIR)
  RNG_LOG_FILE = File.join(RNG_LOG_DIR, "rng_log.txt")
rescue => e
  RNG_LOG_FILE = "rng_log.txt"
end

module RNGLog
  LOG_MUTEX = Mutex.new

  def self.write(msg)
    LOG_MUTEX.synchronize do
      File.open(RNG_LOG_FILE, "a") { |f| f.write("#{msg}\n") }
    end
  rescue => e
    # Fail silently
  end
end
