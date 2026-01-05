#===============================================================================
# Version Checker Module
#===============================================================================
# Checks for updates on game startup (non-blocking)
# Stores update information in global variables
#===============================================================================

module VersionChecker
  module_function

  # Current version (update this when releasing new versions)
  CURRENT_VERSION = "2.2.2"

  # GitHub repository URL (raw content)
  GITHUB_RAW_BASE = "https://raw.githubusercontent.com/skarreku/KIF-Multiplayer/main"
  VERSION_URL = "#{GITHUB_RAW_BASE}/version.txt"

  # Global variables for update state
  $update_available = false
  $update_version = nil
  $update_manifest = nil
  $update_check_failed = false
  $update_last_check = nil

  # Check for updates (call on game startup)
  def check_for_updates
    return if $update_last_check && (Time.now - $update_last_check) < 3600 # Check max once per hour

    Thread.new do
      begin
        MultiplayerDebug.info("VERSION-CHECKER", "Checking for updates...") if defined?(MultiplayerDebug)

        # Fetch remote version
        remote_version_str = HTTPWrapper.http_get(VERSION_URL, 10)
        if remote_version_str.nil? || remote_version_str.strip.empty?
          MultiplayerDebug.error("VERSION-CHECKER", "Failed to fetch version.txt") if defined?(MultiplayerDebug)
          $update_check_failed = true
          $update_last_check = Time.now
          return
        end

        remote_version = remote_version_str.strip
        MultiplayerDebug.info("VERSION-CHECKER", "Remote version: #{remote_version}") if defined?(MultiplayerDebug)
        MultiplayerDebug.info("VERSION-CHECKER", "Current version: #{CURRENT_VERSION}") if defined?(MultiplayerDebug)

        # Compare versions
        if version_greater_than?(remote_version, CURRENT_VERSION)
          MultiplayerDebug.info("VERSION-CHECKER", "Update available: #{remote_version}") if defined?(MultiplayerDebug)

          # Fetch manifest
          manifest_url = "#{GITHUB_RAW_BASE}/updates/#{remote_version}/manifest.json"
          manifest_json = HTTPWrapper.http_get(manifest_url, 10)

          if manifest_json
            $update_version = remote_version
            $update_manifest = parse_json(manifest_json)
            $update_available = true
            MultiplayerDebug.info("VERSION-CHECKER", "Manifest downloaded successfully") if defined?(MultiplayerDebug)
          else
            MultiplayerDebug.error("VERSION-CHECKER", "Failed to fetch manifest") if defined?(MultiplayerDebug)
            $update_check_failed = true
          end
        else
          MultiplayerDebug.info("VERSION-CHECKER", "No updates available") if defined?(MultiplayerDebug)
          $update_available = false
        end

        $update_last_check = Time.now

      rescue => e
        MultiplayerDebug.error("VERSION-CHECKER", "Update check failed: #{e.message}") if defined?(MultiplayerDebug)
        $update_check_failed = true
        $update_last_check = Time.now
      end
    end
  end

  # Compare version strings (semantic versioning)
  # @param version1 [String] First version (e.g., "2.0.0")
  # @param version2 [String] Second version (e.g., "1.0.0")
  # @return [Boolean] True if version1 > version2
  def version_greater_than?(version1, version2)
    v1_parts = version1.split('.').map(&:to_i)
    v2_parts = version2.split('.').map(&:to_i)

    # Pad to same length
    max_length = [v1_parts.length, v2_parts.length].max
    v1_parts.fill(0, v1_parts.length...max_length)
    v2_parts.fill(0, v2_parts.length...max_length)

    # Compare each part
    v1_parts.each_with_index do |v1_part, index|
      return true if v1_part > v2_parts[index]
      return false if v1_part < v2_parts[index]
    end

    return false # Versions are equal
  end

  # Simple JSON parser (handles basic manifest structure)
  # @param json_string [String] JSON string
  # @return [Hash] Parsed JSON
  def parse_json(json_string)
    # Try using native JSON if available
    begin
      require 'json'
      return JSON.parse(json_string)
    rescue LoadError
      # Fallback to manual parsing (basic support)
      MultiplayerDebug.warn("VERSION-CHECKER", "JSON library not available, using basic parser") if defined?(MultiplayerDebug)
      return eval(json_string.gsub('null', 'nil').gsub('true', 'true').gsub('false', 'false'))
    rescue => e
      MultiplayerDebug.error("VERSION-CHECKER", "JSON parse failed: #{e.message}") if defined?(MultiplayerDebug)
      return {}
    end
  end

  # Get update info for display
  # @return [Hash, nil] Update info or nil if no update
  def get_update_info
    return nil unless $update_available && $update_manifest

    {
      version: $update_version,
      changelog: $update_manifest["changelog"] || "No changelog available",
      size: $update_manifest["full_archive"] ? $update_manifest["full_archive"]["size"] : 0,
      files_count: $update_manifest["files"] ? $update_manifest["files"].length : 0
    }
  end

  # Clear update state (after installing or dismissing)
  def clear_update_state
    $update_available = false
    $update_version = nil
    $update_manifest = nil
  end
end

# Auto-check on module load (non-blocking)
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("VERSION-CHECKER", "=" * 60)
  MultiplayerDebug.info("VERSION-CHECKER", "002_Version_Checker.rb loaded successfully")
  MultiplayerDebug.info("VERSION-CHECKER", "Current version: #{VersionChecker::CURRENT_VERSION}")
  MultiplayerDebug.info("VERSION-CHECKER", "Auto-check enabled")
  MultiplayerDebug.info("VERSION-CHECKER", "=" * 60)

  # Start version check in background
  VersionChecker.check_for_updates
end
