#===============================================================================
# Discord ID Storage — Local File Persistence
# Stores Discord snowflake IDs per server in a local file (not in save file)
# File: KIFM/discord_ids.txt  (same folder as platinum_uuids.txt)
#
# When a Discord ID is stored for a server, AUTH sends:
#   AUTH:tid:DISCORD:discord_snowflake_id
# instead of the normal UUID/token flow, so identity survives reinstalls.
#===============================================================================

module DiscordIDStorage
  def self.storage_path
    base_dir = File.dirname(File.dirname(File.dirname(__FILE__)))
    kifm_dir = File.join(base_dir, "KIFM")
    Dir.mkdir(kifm_dir) unless Dir.exist?(kifm_dir)
    File.join(kifm_dir, "discord_ids.txt")
  end

  def self.get(server_key)
    _load[server_key]
  end

  def self.set(server_key, discord_id)
    all = _load
    all[server_key] = discord_id.to_s.strip
    _save(all)
  end

  def self.clear(server_key)
    all = _load
    all.delete(server_key)
    _save(all)
  end

  def self._load
    path = storage_path
    return {} unless File.exist?(path)
    begin
      result = {}
      File.readlines(path).each do |line|
        line = line.strip
        next if line.empty? || line.start_with?("#")
        parts = line.split("=", 2)
        next unless parts.length == 2
        result[parts[0].strip] = parts[1].strip
      end
      result
    rescue
      {}
    end
  end

  def self._save(data)
    path = storage_path
    begin
      File.open(path, "w") do |f|
        f.puts "# Discord IDs per server (host:port => discord_snowflake_id)"
        f.puts "# DO NOT EDIT MANUALLY"
        f.puts ""
        data.each { |k, v| f.puts "#{k}=#{v}" }
      end
    rescue
    end
  end
end
