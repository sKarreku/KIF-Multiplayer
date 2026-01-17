#!/usr/bin/env ruby
#===============================================================================
# KIF Multiplayer External Auto-Updater
#===============================================================================
# Standalone Ruby script for updating the multiplayer mod
# Runs outside RGSS environment with full Ruby standard library
#===============================================================================

require 'net/http'
require 'uri'
require 'json'
require 'digest/sha2'
require 'fileutils'
require 'time'

#===============================================================================
# Configuration
#===============================================================================

VERSION_URL = "https://raw.githubusercontent.com/skarreku/KIF-Multiplayer/main/version.txt"
MANIFEST_BASE_URL = "https://raw.githubusercontent.com/skarreku/KIF-Multiplayer/main/updates"
LOCAL_VERSION_FILE = "Data/Scripts/659_Multiplayer/002_Version.rb"
TARGET_DIR = "Data/Scripts/659_Multiplayer"
UPDATES_DIR = "Updates"
PENDING_DIR = File.join(UPDATES_DIR, "pending")
STAGING_DIR = File.join(UPDATES_DIR, "staging")
BACKUPS_DIR = "Backups"
LOG_FILE = File.join(UPDATES_DIR, "autoupdater.log")
MAX_BACKUPS = 3
HTTP_TIMEOUT = 30
USER_AGENT = "KIF-Multiplayer-External-Updater/1.0"

#===============================================================================
# Logging System
#===============================================================================

class Logger
  def initialize(log_file)
    @log_file = log_file
    FileUtils.mkdir_p(File.dirname(@log_file)) unless Dir.exist?(File.dirname(@log_file))

    # Rotate log if it exceeds 5MB
    if File.exist?(@log_file) && File.size(@log_file) > 5 * 1024 * 1024
      old_log = @log_file.sub('.log', '.log.old')
      FileUtils.mv(@log_file, old_log, force: true)
    end
  end

  def log(message, level: :info)
    timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    formatted = "[#{timestamp}] #{message}"

    # Write to console
    puts formatted

    # Write to log file
    File.open(@log_file, 'a') do |f|
      f.puts formatted
    end
  rescue => e
    puts "[LOG ERROR] Failed to write to log: #{e.message}"
  end

  def step(num, total, message)
    log("[STEP #{num}/#{total}] #{message}")
  end

  def success(message)
    log("[SUCCESS] #{message}")
  end

  def error(message, flag: nil)
    msg = flag ? "[#{flag}] #{message}" : "[ERROR] #{message}"
    log(msg)
  end

  def rollback(message)
    log("[ROLLBACK] #{message}")
  end
end

#===============================================================================
# Utility Functions
#===============================================================================

def check_game_running
  output = `tasklist /FI "IMAGENAME eq Game.exe" 2>nul`
  return output.include?("Game.exe")
rescue => e
  $logger.error("Failed to check if game is running: #{e.message}")
  return false
end

def kill_game_process
  system('taskkill /F /IM Game.exe /T >nul 2>&1')
  sleep 0.5  # Wait for process to terminate
  return true
rescue => e
  $logger.error("Failed to kill game process: #{e.message}")
  return false
end

def fetch_url(url, timeout: HTTP_TIMEOUT)
  uri = URI.parse(url)

  # Upgrade to HTTPS if needed
  uri.scheme = 'https' if uri.scheme == 'http'

  Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: timeout, read_timeout: timeout) do |http|
    request = Net::HTTP::Get.new(uri.request_uri)
    request['User-Agent'] = USER_AGENT

    response = http.request(request)

    if response.code.to_i == 200
      return response.body
    else
      raise "HTTP #{response.code}: #{response.message}"
    end
  end
rescue => e
  raise "Failed to fetch #{url}: #{e.message}"
end

def download_file(url, dest_path, show_progress: true)
  uri = URI.parse(url)
  uri.scheme = 'https' if uri.scheme == 'http'

  # Ensure directory exists
  FileUtils.mkdir_p(File.dirname(dest_path))

  # Download to temporary file
  temp_path = dest_path + ".tmp"

  Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: HTTP_TIMEOUT, read_timeout: HTTP_TIMEOUT) do |http|
    request = Net::HTTP::Get.new(uri.request_uri)
    request['User-Agent'] = USER_AGENT

    # Use request block form to stream response
    http.request(request) do |response|
      if response.code.to_i != 200
        raise "HTTP #{response.code}: #{response.message}"
      end

      total_size = response['Content-Length'].to_i
      downloaded = 0

      File.open(temp_path, 'wb') do |file|
        response.read_body do |chunk|
          file.write(chunk)
          downloaded += chunk.size

          if show_progress && total_size > 0
            progress_mb = (downloaded / 1024.0 / 1024.0).round(1)
            total_mb = (total_size / 1024.0 / 1024.0).round(1)
            print "\r  Downloading... #{progress_mb} MB / #{total_mb} MB"
          end
        end
      end

      puts "" if show_progress  # New line after progress
    end
  end

  # Rename temp file to final name
  FileUtils.mv(temp_path, dest_path, force: true)
  return dest_path
rescue => e
  # Clean up temp file on error
  File.delete(temp_path) if File.exist?(temp_path)
  raise "Download failed: #{e.message}"
end

def calculate_sha256(file_path)
  Digest::SHA256.file(file_path).hexdigest
end

def parse_version(version_string)
  version_string.strip.split('.').map(&:to_i)
end

def version_greater_than?(v1, v2)
  v1_parts = parse_version(v1)
  v2_parts = parse_version(v2)

  [v1_parts.length, v2_parts.length].max.times do |i|
    v1_num = v1_parts[i] || 0
    v2_num = v2_parts[i] || 0

    return true if v1_num > v2_num
    return false if v1_num < v2_num
  end

  return false  # Versions are equal
end

def extract_archive(archive_path, dest_dir)
  FileUtils.mkdir_p(dest_dir)

  # Try bundled 7z.exe first, fallback to system rar.exe
  bundled_7z = File.join(Dir.pwd, "REQUIRED_BY_INSTALLER_UPDATER", "7z.exe")

  if File.exist?(bundled_7z)
    # Use bundled 7z.exe: x = extract with paths, -y = yes to all prompts, -o = output directory
    command = "\"#{bundled_7z}\" x -y \"#{archive_path}\" -o\"#{dest_dir}\""
    $logger.log("  Using bundled 7z: #{command}")
  else
    # Fallback to system rar.exe (requires WinRAR in PATH)
    command = "rar x -o+ \"#{archive_path}\" \"#{dest_dir}\\\""
    $logger.log("  Using system rar: #{command}")
  end

  success = system(command)

  if !success || $?.exitstatus != 0
    if $?.exitstatus == 127
      raise "Extraction failed: 7z.exe not found and WinRAR not installed in PATH (exit code: 127)"
    else
      raise "Extraction failed (exit code: #{$?.exitstatus})"
    end
  end

  return true
end

def create_backup(source_dir, backup_name)
  backup_path = File.join(BACKUPS_DIR, backup_name)

  # Create backups directory
  FileUtils.mkdir_p(BACKUPS_DIR)

  # Copy entire directory
  FileUtils.cp_r(source_dir, backup_path)

  # Clean up old backups (keep only MAX_BACKUPS)
  backups = Dir.glob(File.join(BACKUPS_DIR, "multiplayer_backup_*")).sort_by { |f| File.mtime(f) }.reverse
  backups[MAX_BACKUPS..-1]&.each do |old_backup|
    $logger.log("  Deleting old backup: #{File.basename(old_backup)}")
    FileUtils.rm_rf(old_backup)
  end

  return backup_path
end

def restore_from_backup(backup_path, target_dir)
  # Delete current target
  FileUtils.rm_rf(target_dir) if Dir.exist?(target_dir)

  # Restore from backup
  FileUtils.cp_r(backup_path, target_dir)

  return true
end

def cleanup_temp_dirs
  FileUtils.rm_rf(PENDING_DIR) if Dir.exist?(PENDING_DIR)
  FileUtils.rm_rf(STAGING_DIR) if Dir.exist?(STAGING_DIR)
end

#===============================================================================
# Main Update Flow
#===============================================================================

def fetch_remote_version
  $logger.step(2, 9, "Fetching remote version...")

  version_text = fetch_url(VERSION_URL)
  remote_version = version_text.strip

  if !remote_version.match?(/^\d+\.\d+\.\d+$/)
    raise "Invalid version format: #{remote_version}"
  end

  $logger.log("  Remote version: #{remote_version}")
  return remote_version
rescue => e
  $logger.error("Failed to fetch remote version: #{e.message}", flag: "ERROR:VERSION_FETCH")
  exit 1
end

def read_local_version
  # Create version file if it doesn't exist
  if !File.exist?(LOCAL_VERSION_FILE)
    $logger.log("  Version file not found, creating with version 0.0.0...")
    create_version_file("0.0.0")
  end

  content = File.read(LOCAL_VERSION_FILE)

  # Match: CURRENT_VERSION = "X.Y.Z"
  match = content.match(/CURRENT_VERSION\s*=\s*["']([^"']+)["']/)

  if !match
    raise "Could not parse version from #{LOCAL_VERSION_FILE}"
  end

  local_version = match[1].strip
  $logger.log("  Local version: #{local_version}")
  return local_version
rescue => e
  $logger.error("Failed to read local version: #{e.message}", flag: "ERROR:LOCAL_VERSION_READ")
  exit 1
end

def create_version_file(version)
  # Ensure directory exists
  FileUtils.mkdir_p(File.dirname(LOCAL_VERSION_FILE))

  # Create version file with template
  content = <<~RUBY
    #===============================================================================
    # Multiplayer Mod Version
    #===============================================================================
    # Used by external updater to check current version
    # This file is automatically updated by update_publisher.rb
    #===============================================================================

    module MultiplayerVersion
      CURRENT_VERSION = "#{version}"
    end
  RUBY

  File.write(LOCAL_VERSION_FILE, content)
  $logger.log("  Created #{LOCAL_VERSION_FILE} with version #{version}")
end

def fetch_manifest(version)
  $logger.step(4, 9, "Downloading update v#{version}...")

  manifest_url = "#{MANIFEST_BASE_URL}/#{version}/manifest.json"
  manifest_text = fetch_url(manifest_url)
  manifest = JSON.parse(manifest_text)

  $logger.log("  Manifest loaded successfully")
  return manifest
rescue => e
  $logger.error("Failed to fetch manifest: #{e.message}", flag: "ERROR:MANIFEST_FETCH")
  exit 1
end

def download_archive(manifest, version)
  archive_info = manifest['full_archive']

  if !archive_info || !archive_info['url']
    $logger.error("Manifest missing full_archive information", flag: "ERROR:MANIFEST_INVALID")
    exit 1
  end

  archive_url = archive_info['url']
  archive_filename = archive_info['filename'] || "v#{version}.rar"
  archive_path = File.join(PENDING_DIR, archive_filename)
  expected_sha256 = archive_info['sha256']

  # Validate SHA256 exists in manifest
  if !expected_sha256 || expected_sha256.strip.empty?
    $logger.error("Manifest missing SHA256 hash for archive", flag: "ERROR:MANIFEST_INVALID")
    $logger.log("  The manifest.json file on GitHub is incomplete.")
    $logger.log("  Please ensure update_publisher.rb generated the SHA256 hash correctly.")
    exit 1
  end

  $logger.log("  URL: #{archive_url}")
  $logger.log("  Expected SHA256: #{expected_sha256}")

  # Download
  download_file(archive_url, archive_path, show_progress: true)

  $logger.log("  Download complete: #{(File.size(archive_path) / 1024.0 / 1024.0).round(1)} MB")

  return archive_path, expected_sha256
rescue => e
  $logger.error("Failed to download archive: #{e.message}", flag: "ERROR:DOWNLOAD_FAILED")
  cleanup_temp_dirs
  exit 1
end

def verify_archive_sha256(archive_path, expected_sha256)
  $logger.step(5, 9, "Verifying archive integrity (SHA256)...")

  actual_sha256 = calculate_sha256(archive_path)

  $logger.log("  Calculated SHA256: #{actual_sha256}")

  if actual_sha256 != expected_sha256
    $logger.error("SHA256 mismatch! Archive may be corrupted.", flag: "ERROR:SHA256_MISMATCH")
    $logger.log("  Expected: #{expected_sha256}")
    $logger.log("  Actual:   #{actual_sha256}")
    cleanup_temp_dirs
    exit 1
  end

  $logger.log("  SHA256 verification passed")
  return true
end

def perform_backup
  $logger.step(6, 9, "Creating backup...")

  timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
  backup_name = "multiplayer_backup_#{timestamp}"
  backup_path = create_backup(TARGET_DIR, backup_name)

  $logger.log("  Backup created: #{backup_path}")
  return backup_path
rescue => e
  $logger.error("Failed to create backup: #{e.message}", flag: "ERROR:BACKUP_FAILED")
  cleanup_temp_dirs
  exit 1
end

def extract_update(archive_path)
  $logger.step(7, 9, "Extracting archive...")

  extract_archive(archive_path, STAGING_DIR)

  # Verify extraction
  staged_target = File.join(STAGING_DIR, TARGET_DIR)
  if !Dir.exist?(staged_target)
    raise "Extracted archive missing expected directory: #{TARGET_DIR}"
  end

  file_count = Dir.glob(File.join(staged_target, "**", "*")).select { |f| File.file?(f) }.count
  $logger.log("  Extraction complete: #{file_count} files")

  return staged_target
rescue => e
  $logger.error("Failed to extract archive: #{e.message}", flag: "ERROR:EXTRACTION_FAILED")
  cleanup_temp_dirs
  exit 1
end

def install_update(staged_target, backup_path)
  $logger.step(8, 9, "Installing update...")

  begin
    # Find all top-level directories and files in staging
    staged_items = Dir.glob(File.join(STAGING_DIR, "*"))

    if staged_items.empty?
      raise "No files found in staging directory"
    end

    $logger.log("  Installing #{staged_items.length} top-level items from staging...")

    installed_count = 0

    staged_items.each do |staged_item|
      item_name = File.basename(staged_item)
      target_path = File.join(Dir.pwd, item_name)

      # Special handling for 659_Multiplayer (remove old version first)
      if item_name == "Data"
        # Handle Data directory specially - need to replace 659_Multiplayer subfolder
        staged_scripts = File.join(staged_item, "Scripts", "659_Multiplayer")
        if Dir.exist?(staged_scripts)
          $logger.log("  Removing old 659_Multiplayer...")
          FileUtils.rm_rf(TARGET_DIR) if Dir.exist?(TARGET_DIR)

          $logger.log("  Moving new 659_Multiplayer...")
          FileUtils.mkdir_p(File.dirname(TARGET_DIR))
          FileUtils.mv(staged_scripts, TARGET_DIR)
          installed_count += Dir.glob(File.join(TARGET_DIR, "**", "*")).select { |f| File.file?(f) }.count
        end
      elsif File.directory?(staged_item)
        # For other directories (Fonts, Graphics, KIFM), merge/overwrite
        $logger.log("  Installing #{item_name}/...")
        FileUtils.mkdir_p(target_path) unless Dir.exist?(target_path)

        # Copy all files from staged directory to target
        Dir.glob(File.join(staged_item, "**", "*")).each do |file|
          next unless File.file?(file)

          relative_path = file.sub(staged_item + File::SEPARATOR, "")
          dest_file = File.join(target_path, relative_path)

          FileUtils.mkdir_p(File.dirname(dest_file))
          FileUtils.cp(file, dest_file)
          installed_count += 1
        end
      else
        # For individual files (autoupdater.rb, autoupdate_multiplayer.bat)
        $logger.log("  Installing #{item_name}...")
        FileUtils.cp(staged_item, target_path)
        installed_count += 1
      end
    end

    $logger.log("  Installation complete: #{installed_count} files installed")

    return true
  rescue => e
    # Rollback on failure
    $logger.rollback("Installation failed, restoring from backup...")
    $logger.error("Installation error: #{e.message}", flag: "ERROR:REPLACEMENT_FAILED")

    begin
      restore_from_backup(backup_path, TARGET_DIR)
      $logger.rollback("Successfully restored from backup")
    rescue => restore_error
      $logger.error("CRITICAL: Rollback failed! #{restore_error.message}", flag: "ERROR:ROLLBACK_FAILED")
    end

    cleanup_temp_dirs
    exit 1
  end
end

def perform_cleanup
  $logger.step(9, 9, "Cleaning up...")

  cleanup_temp_dirs

  $logger.log("  Temporary files deleted")
  return true
rescue => e
  $logger.log("  Warning: Cleanup error: #{e.message}")
  # Don't fail on cleanup errors
  return true
end

#===============================================================================
# Main Entry Point
#===============================================================================

def main
  # Initialize logger
  $logger = Logger.new(LOG_FILE)

  $logger.log("=" * 60)
  $logger.log("KIF Multiplayer Auto-Updater")
  $logger.log("=" * 60)
  $logger.log("")

  # Step 1: Check if game is running
  $logger.step(1, 9, "Checking if game is running...")

  if check_game_running
    $logger.log("  Game is running, terminating...")
    if kill_game_process
      $logger.log("  Game process terminated successfully")
    else
      $logger.error("Failed to terminate game process", flag: "ERROR:GAME_RUNNING")
      exit 1
    end
  else
    $logger.log("  Game is not running")
  end

  # Step 2: Fetch remote version
  remote_version = fetch_remote_version

  # Step 3: Compare versions
  $logger.step(3, 9, "Comparing versions...")
  local_version = read_local_version

  if !version_greater_than?(remote_version, local_version)
    $logger.log("")
    $logger.success("You have the most up to date version!")
    $logger.log("  Local:  #{local_version}")
    $logger.log("  Remote: #{remote_version}")
    exit 0
  end

  $logger.log("  Update available: #{local_version} → #{remote_version}")

  # Step 4: Download
  manifest = fetch_manifest(remote_version)
  archive_path, expected_sha256 = download_archive(manifest, remote_version)

  # Step 5: Verify
  verify_archive_sha256(archive_path, expected_sha256)

  # Step 6: Backup
  backup_path = perform_backup

  # Step 7: Extract
  staged_target = extract_update(archive_path)

  # Step 8: Install
  install_update(staged_target, backup_path)

  # Step 9: Cleanup
  perform_cleanup

  # Success!
  $logger.log("")
  $logger.success("Update to v#{remote_version} complete!")
  $logger.log("=" * 60)

  exit 0
rescue => e
  $logger.log("")
  $logger.error("Unexpected error: #{e.class}: #{e.message}")
  $logger.log("Backtrace:")
  e.backtrace.first(10).each { |line| $logger.log("  #{line}") }

  cleanup_temp_dirs
  exit 1
end

# Run the updater
main if __FILE__ == $0
