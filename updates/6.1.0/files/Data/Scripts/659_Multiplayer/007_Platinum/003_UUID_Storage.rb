#===============================================================================
# Platinum UUID Storage - Local File Persistence
# Stores platinum UUIDs per server in a local file (not in save file)
# File location: KIFM/platinum_uuids.txt (next to server files)
#===============================================================================

module PlatinumUUIDStorage
  # Get path to UUID storage file (in KIFM folder)
  def self.storage_path
    base_dir = File.dirname(File.dirname(File.dirname(__FILE__)))  # Go up from Scripts folder
    kifm_dir = File.join(base_dir, "KIFM")
    Dir.mkdir(kifm_dir) unless Dir.exist?(kifm_dir)
    File.join(kifm_dir, "platinum_uuids.txt")
  end

  # Load UUIDs from file
  # @return [Hash] Hash of "host:port" => "uuid"
  def self.load_uuids
    path = storage_path
    return {} unless File.exist?(path)

    begin
      uuids = {}
      File.readlines(path).each do |line|
        line = line.strip
        next if line.empty? || line.start_with?("#")

        parts = line.split("=", 2)
        next unless parts.length == 2

        server_key = parts[0].strip
        uuid = parts[1].strip
        uuids[server_key] = uuid
      end

      ##MultiplayerDebug.info("PLAT-UUID", "Loaded #{uuids.length} UUIDs from #{path}")
      return uuids
    rescue => e
      ##MultiplayerDebug.error("PLAT-UUID", "Failed to load UUIDs: #{e.message}")
      return {}
    end
  end

  # Save UUIDs to file
  # @param uuids [Hash] Hash of "host:port" => "uuid"
  def self.save_uuids(uuids)
    path = storage_path

    begin
      File.open(path, "w") do |f|
        f.puts "# Platinum Account UUIDs (per server)"
        f.puts "# Format: host:port=uuid"
        f.puts "# DO NOT EDIT MANUALLY"
        f.puts ""

        uuids.each do |server_key, uuid|
          f.puts "#{server_key}=#{uuid}"
        end
      end

      ##MultiplayerDebug.info("PLAT-UUID", "Saved #{uuids.length} UUIDs to #{path}")
      return true
    rescue => e
      ##MultiplayerDebug.error("PLAT-UUID", "Failed to save UUIDs: #{e.message}")
      return false
    end
  end

  # Get UUID for a specific server
  # @param server_key [String] "host:port"
  # @return [String, nil] UUID or nil if not found
  def self.get_uuid(server_key)
    uuids = load_uuids
    uuids[server_key]
  end

  # Set UUID for a specific server
  # @param server_key [String] "host:port"
  # @param uuid [String] Account UUID
  def self.set_uuid(server_key, uuid)
    uuids = load_uuids
    uuids[server_key] = uuid
    save_uuids(uuids)
  end

  # Clear UUID for a specific server (for testing/debugging)
  # @param server_key [String] "host:port"
  def self.clear_uuid(server_key)
    uuids = load_uuids
    uuids.delete(server_key)
    save_uuids(uuids)
  end
end

##MultiplayerDebug.info("MODULE-56B", "Platinum UUID storage loaded (file: #{PlatinumUUIDStorage.storage_path})")
