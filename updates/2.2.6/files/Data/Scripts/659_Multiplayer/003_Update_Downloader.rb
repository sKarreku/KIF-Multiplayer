#===============================================================================
# Update Downloader Module
#===============================================================================
# Downloads updates with delta support (only changed files)
# Falls back to full archive if >50% files changed
#===============================================================================

module UpdateDownloader
  module_function

  # RGSS-compatible directory creation (no FileUtils needed)
  def mkdir_p(path)
    return if Dir.exist?(path)

    parts = path.split(/[\/\\]/)
    current = ""

    parts.each do |part|
      current = current.empty? ? part : File.join(current, part)
      Dir.mkdir(current) unless Dir.exist?(current)
    end
  end

  # Paths
  UPDATES_DIR = "Updates"
  PENDING_DIR = File.join(UPDATES_DIR, "pending")
  STAGING_DIR = File.join(UPDATES_DIR, "staging")
  STATE_FILE = File.join(UPDATES_DIR, "update_state.json")

  # Download state
  $download_progress = 0.0
  $download_status = "idle" # idle, downloading, verifying, complete, failed
  $download_error = nil

  # Download update blocking (for UI with progress)
  # @param manifest [Hash] Update manifest from VersionChecker
  # @param version [String] Version to download
  # @return [Boolean] True if download succeeded
  def download_update_blocking(manifest, version)
    return false if $download_status == "downloading"

    begin
      $download_status = "downloading"
      $download_progress = 0.0
      $download_error = nil

      # Ensure directories exist
      mkdir_p(PENDING_DIR)
      mkdir_p(STAGING_DIR)

      # Decide: delta or full archive
      use_delta = should_use_delta?(manifest)

      if use_delta
        MultiplayerDebug.info("UPDATE-DOWNLOADER", "Using delta update") if defined?(MultiplayerDebug)
        success = download_delta_update(manifest, version)
      else
        MultiplayerDebug.info("UPDATE-DOWNLOADER", "Using full archive") if defined?(MultiplayerDebug)
        success = download_full_archive(manifest, version)
      end

      if success
        $download_status = "complete"
        $download_progress = 100.0
        save_download_state(version, true, true)
        MultiplayerDebug.info("UPDATE-DOWNLOADER", "Download complete!") if defined?(MultiplayerDebug)
        return true
      else
        $download_status = "failed"
        $download_error = "Download verification failed"
        MultiplayerDebug.error("UPDATE-DOWNLOADER", "Download failed") if defined?(MultiplayerDebug)
        return false
      end

    rescue => e
      $download_status = "failed"
      $download_error = e.message
      MultiplayerDebug.error("UPDATE-DOWNLOADER", "Download error: #{e.message}") if defined?(MultiplayerDebug)
      return false
    end
  end

  # Download update (delta or full) - background thread version
  # @param manifest [Hash] Update manifest from VersionChecker
  # @param version [String] Version to download
  # @return [Boolean] True if download started successfully
  def download_update(manifest, version)
    return false if $download_status == "downloading"

    Thread.new do
      begin
        $download_status = "downloading"
        $download_progress = 0.0
        $download_error = nil

        # Ensure directories exist
        mkdir_p(PENDING_DIR)
        mkdir_p(STAGING_DIR)

        # Decide: delta or full archive
        use_delta = should_use_delta?(manifest)

        if use_delta
          MultiplayerDebug.info("UPDATE-DOWNLOADER", "Using delta update") if defined?(MultiplayerDebug)
          success = download_delta_update(manifest, version)
        else
          MultiplayerDebug.info("UPDATE-DOWNLOADER", "Using full archive") if defined?(MultiplayerDebug)
          success = download_full_archive(manifest, version)
        end

        if success
          $download_status = "complete"
          $download_progress = 100.0
          save_download_state(version, true, true)
          MultiplayerDebug.info("UPDATE-DOWNLOADER", "Download complete!") if defined?(MultiplayerDebug)
        else
          $download_status = "failed"
          $download_error = "Download verification failed"
          MultiplayerDebug.error("UPDATE-DOWNLOADER", "Download failed") if defined?(MultiplayerDebug)
        end

      rescue => e
        $download_status = "failed"
        $download_error = e.message
        MultiplayerDebug.error("UPDATE-DOWNLOADER", "Download error: #{e.message}") if defined?(MultiplayerDebug)
      end
    end

    return true
  end

  # Determine if delta update should be used
  # @param manifest [Hash] Update manifest
  # @return [Boolean] True if delta update is appropriate
  def should_use_delta?(manifest)
    return false unless manifest["files"]
    return false unless manifest["full_archive"]

    # Calculate how many files would need downloading
    changed_files = count_changed_files(manifest["files"])
    total_files = manifest["files"].length

    # Use delta if <50% files changed
    changed_ratio = changed_files.to_f / total_files
    return changed_ratio < 0.5
  end

  # Count how many files differ from local versions
  # @param files [Array<Hash>] File list from manifest
  # @return [Integer] Number of changed files
  def count_changed_files(files)
    changed_count = 0
    files.each do |file_info|
      local_path = file_info["path"]
      expected_md5 = file_info["md5"]

      if !File.exist?(local_path)
        changed_count += 1
      else
        actual_md5 = HTTPWrapper.calculate_md5(local_path)
        changed_count += 1 if actual_md5 != expected_md5
      end
    end
    return changed_count
  end

  # Download only changed files (delta update)
  # @param manifest [Hash] Update manifest
  # @param version [String] Version string
  # @return [Boolean] True if successful
  def download_delta_update(manifest, version)
    files = manifest["files"]
    total_files = files.length
    downloaded_count = 0

    files.each_with_index do |file_info, index|
      local_path = file_info["path"]
      expected_md5 = file_info["md5"]
      file_url = file_info["url"]

      # Skip if file already matches
      if File.exist?(local_path)
        actual_md5 = HTTPWrapper.calculate_md5(local_path)
        if actual_md5 == expected_md5
          downloaded_count += 1
          $download_progress = (downloaded_count.to_f / total_files * 100).round(1)
          next # File already correct, skip download
        end
      end

      # Download file to staging
      staging_path = File.join(STAGING_DIR, local_path)
      success = HTTPWrapper.http_download_file(file_url, staging_path, expected_md5)

      if !success
        MultiplayerDebug.error("UPDATE-DOWNLOADER", "Failed to download #{file_info['path']}") if defined?(MultiplayerDebug)
        return false
      end

      downloaded_count += 1
      $download_progress = (downloaded_count.to_f / total_files * 100).round(1)
    end

    return true
  end

  # Download full archive
  # @param manifest [Hash] Update manifest
  # @param version [String] Version string
  # @return [Boolean] True if successful
  def download_full_archive(manifest, version)
    archive_info = manifest["full_archive"]
    if !archive_info
      MultiplayerDebug.error("UPDATE-DOWNLOADER", "No archive info in manifest") if defined?(MultiplayerDebug)
      $download_error = "No archive info in manifest"
      return false
    end

    archive_url = archive_info["url"]
    expected_md5 = archive_info["md5"]
    archive_name = File.basename(archive_url)
    local_path = File.join(PENDING_DIR, archive_name)

    MultiplayerDebug.info("UPDATE-DOWNLOADER", "Archive URL: #{archive_url}") if defined?(MultiplayerDebug)
    MultiplayerDebug.info("UPDATE-DOWNLOADER", "Local path: #{local_path}") if defined?(MultiplayerDebug)

    # Download with progress tracking (simplified - WinINet doesn't expose progress easily)
    $download_progress = 10.0
    success = HTTPWrapper.http_download_file(archive_url, local_path, expected_md5)
    $download_progress = success ? 100.0 : 0.0

    if !success
      MultiplayerDebug.error("UPDATE-DOWNLOADER", "Failed to download archive") if defined?(MultiplayerDebug)
      $download_error = "Failed to download archive"
      return false
    end

    MultiplayerDebug.info("UPDATE-DOWNLOADER", "Download successful, extracting...") if defined?(MultiplayerDebug)

    # Extract archive to staging
    $download_status = "verifying"
    extract_success = extract_archive(local_path, STAGING_DIR)

    if !extract_success
      MultiplayerDebug.error("UPDATE-DOWNLOADER", "Failed to extract archive") if defined?(MultiplayerDebug)
      $download_error = "Failed to extract archive"
    end

    return extract_success
  end

  # Extract archive (RAR/ZIP/7Z)
  # @param archive_path [String] Path to archive file
  # @param dest_dir [String] Destination directory
  # @return [Boolean] True if successful
  def extract_archive(archive_path, dest_dir)
    # Try different extraction methods
    ext = File.extname(archive_path).downcase

    case ext
    when ".rar"
      return system("rar x -o+ \"#{archive_path}\" \"#{dest_dir}\\\"")
    when ".7z"
      return system("7z x \"#{archive_path}\" -o\"#{dest_dir}\" -y")
    when ".zip"
      # Use Ruby's built-in Zip if available, otherwise 7z
      begin
        require 'zip'
        Zip::File.open(archive_path) do |zip_file|
          zip_file.each do |entry|
            entry_path = File.join(dest_dir, entry.name)
            mkdir_p(File.dirname(entry_path))
            entry.extract(entry_path) unless File.exist?(entry_path)
          end
        end
        return true
      rescue LoadError
        return system("7z x \"#{archive_path}\" -o\"#{dest_dir}\" -y")
      end
    else
      MultiplayerDebug.error("UPDATE-DOWNLOADER", "Unknown archive format: #{ext}") if defined?(MultiplayerDebug)
      return false
    end
  end

  # Save download state
  # @param version [String] Version downloaded
  # @param complete [Boolean] Download complete?
  # @param verified [Boolean] Files verified?
  def save_download_state(version, complete, verified)
    state = {
      downloading_version: version,
      download_complete: complete,
      verified: verified,
      download_started_at: Time.now.to_i
    }

    File.write(STATE_FILE, VersionChecker.parse_json(state.to_json))
  rescue => e
    MultiplayerDebug.error("UPDATE-DOWNLOADER", "Failed to save state: #{e.message}") if defined?(MultiplayerDebug)
  end

  # Load download state
  # @return [Hash, nil] Download state or nil
  def load_download_state
    return nil unless File.exist?(STATE_FILE)
    state_json = File.read(STATE_FILE)
    return VersionChecker.parse_json(state_json)
  rescue => e
    MultiplayerDebug.error("UPDATE-DOWNLOADER", "Failed to load state: #{e.message}") if defined?(MultiplayerDebug)
    return nil
  end

  # Clean up partial downloads
  def cleanup_partial_downloads
    Dir.glob(File.join(PENDING_DIR, "*.part")).each do |part_file|
      File.delete(part_file)
      MultiplayerDebug.info("UPDATE-DOWNLOADER", "Deleted partial download: #{File.basename(part_file)}") if defined?(MultiplayerDebug)
    end
  end
end

# Clean up on load
UpdateDownloader.cleanup_partial_downloads if File.exist?(UpdateDownloader::PENDING_DIR)

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("UPDATE-DOWNLOADER", "=" * 60)
  MultiplayerDebug.info("UPDATE-DOWNLOADER", "003_Update_Downloader.rb loaded successfully")
  MultiplayerDebug.info("UPDATE-DOWNLOADER", "Delta updates enabled with <50% threshold")
  MultiplayerDebug.info("UPDATE-DOWNLOADER", "=" * 60)
end
