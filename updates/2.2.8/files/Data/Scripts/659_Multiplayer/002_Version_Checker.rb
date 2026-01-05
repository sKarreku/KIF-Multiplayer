#===============================================================================
# Version Checker Module
#===============================================================================
# Checks for updates on game startup (non-blocking)
# Stores update information in global variables
#===============================================================================

module VersionChecker
  module_function

  # Current version (update this when releasing new versions)
  CURRENT_VERSION = "2.2.7"

  # GitHub repository URL (raw content)
  GITHUB_RAW_BASE = "https://raw.githubusercontent.com/sKarreku/KIF-Multiplayer/main"
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
    # RGSS doesn't have JSON library, use manual parser
    MultiplayerDebug.info("VERSION-CHECKER", "Parsing JSON manually (RGSS mode)") if defined?(MultiplayerDebug)

    # Remove whitespace and newlines for easier parsing
    json = json_string.strip

    # Parse object
    if json[0] == '{'
      return parse_json_object(json)
    elsif json[0] == '['
      return parse_json_array(json)
    else
      return {}
    end
  rescue => e
    MultiplayerDebug.error("VERSION-CHECKER", "JSON parse failed: #{e.message}") if defined?(MultiplayerDebug)
    return {}
  end

  # Parse JSON object
  def parse_json_object(json)
    result = {}

    # Remove outer braces
    json = json[1..-2].strip

    # Split by commas (simple approach - doesn't handle nested commas perfectly)
    # For manifest structure, this should work
    depth = 0
    current_key = nil
    current_value = ""
    in_string = false
    escape_next = false

    i = 0
    while i < json.length
      char = json[i]

      if escape_next
        current_value << char
        escape_next = false
        i += 1
        next
      end

      if char == '\\'
        escape_next = true
        current_value << char
        i += 1
        next
      end

      if char == '"' && !escape_next
        in_string = !in_string
        current_value << char
        i += 1
        next
      end

      if !in_string
        if char == '{' || char == '['
          depth += 1
        elsif char == '}' || char == ']'
          depth -= 1
        elsif char == ':' && depth == 0 && current_key.nil?
          # Extract key from current_value
          current_key = current_value.strip.gsub(/^"|"$/, '')
          current_value = ""
          i += 1
          next
        elsif char == ',' && depth == 0
          # Store key-value pair
          if current_key
            result[current_key] = parse_json_value(current_value.strip)
            current_key = nil
            current_value = ""
          end
          i += 1
          next
        end
      end

      current_value << char
      i += 1
    end

    # Store final pair
    if current_key
      result[current_key] = parse_json_value(current_value.strip)
    end

    return result
  end

  # Parse JSON array
  def parse_json_array(json)
    result = []

    # Remove outer brackets
    json = json[1..-2].strip
    return result if json.empty?

    depth = 0
    current_value = ""
    in_string = false
    escape_next = false

    i = 0
    while i < json.length
      char = json[i]

      if escape_next
        current_value << char
        escape_next = false
        i += 1
        next
      end

      if char == '\\'
        escape_next = true
        current_value << char
        i += 1
        next
      end

      if char == '"' && !escape_next
        in_string = !in_string
        current_value << char
        i += 1
        next
      end

      if !in_string
        if char == '{' || char == '['
          depth += 1
        elsif char == '}' || char == ']'
          depth -= 1
        elsif char == ',' && depth == 0
          result << parse_json_value(current_value.strip)
          current_value = ""
          i += 1
          next
        end
      end

      current_value << char
      i += 1
    end

    # Store final value
    result << parse_json_value(current_value.strip) unless current_value.strip.empty?

    return result
  end

  # Parse JSON value (string, number, boolean, null, object, array)
  def parse_json_value(value)
    return nil if value == "null"
    return true if value == "true"
    return false if value == "false"

    if value[0] == '"'
      # String - remove quotes and unescape
      return value[1..-2].gsub('\\"', '"').gsub('\\\\', '\\').gsub('\\n', "\n")
    elsif value[0] == '{'
      # Object
      return parse_json_object(value)
    elsif value[0] == '['
      # Array
      return parse_json_array(value)
    elsif value =~ /^-?\d+$/
      # Integer
      return value.to_i
    elsif value =~ /^-?\d+\.\d+$/
      # Float
      return value.to_f
    else
      return value
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
