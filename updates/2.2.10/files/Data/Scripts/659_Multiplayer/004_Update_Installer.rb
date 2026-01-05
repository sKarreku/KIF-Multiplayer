#===============================================================================
# Update Installer Module
#===============================================================================
# Installs verified updates BEFORE scripts load
# Provides atomic installation with backup and rollback
#===============================================================================

module UpdateInstaller
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

  # RGSS-compatible recursive directory copy
  def copy_directory(src, dest)
    mkdir_p(dest)
    Dir.glob(File.join(src, "**", "*")).each do |src_file|
      next if File.directory?(src_file)

      relative_path = src_file.sub(src + File::SEPARATOR, "")
      dest_file = File.join(dest, relative_path)

      mkdir_p(File.dirname(dest_file))
      File.open(src_file, "rb") do |from|
        File.open(dest_file, "wb") do |to|
          to.write(from.read)
        end
      end
    end
  end

  # RGSS-compatible recursive directory delete
  def rm_rf(path)
    return unless File.exist?(path)

    if File.directory?(path)
      Dir.glob(File.join(path, "**", "*")).reverse_each do |file|
        if File.directory?(file)
          Dir.rmdir(file)
        else
          File.delete(file)
        end
      end
      Dir.rmdir(path)
    else
      File.delete(path)
    end
  end

  # Paths
  UPDATES_DIR = "Updates"
  PENDING_DIR = File.join(UPDATES_DIR, "pending")
  STAGING_DIR = File.join(UPDATES_DIR, "staging")
  BACKUPS_DIR = "Backups"
  STATE_FILE = File.join(UPDATES_DIR, "update_state.json")
  MAX_BACKUPS = 3

  # Installation state
  $install_status = "idle" # idle, backing_up, installing, complete, failed, rolled_back
  $install_error = nil
  $install_progress = 0.0

  # Install pending update (call BEFORE scripts load)
  # @return [Boolean] True if installation succeeded or no update pending
  def install_pending_update
    state = UpdateDownloader.load_download_state

    # Check if there are staged files even without state file
    staging_has_files = Dir.exist?(STAGING_DIR) && !Dir.glob(File.join(STAGING_DIR, "**", "*")).select { |f| File.file?(f) }.empty?

    # No update pending if no state and no staged files
    return true unless state || staging_has_files

    # If we have state, verify it's ready to install
    if state && !(state[:download_complete] && state[:verified])
      return true # Not ready yet
    end

    begin
      $install_status = "backing_up"
      $install_progress = 0.0
      $install_error = nil

      version = state ? state[:downloading_version] : "unknown"
      MultiplayerDebug.info("UPDATE-INSTALLER", "Starting installation of v#{version}") if defined?(MultiplayerDebug)

      # Step 1: Create backup
      backup_path = create_backup
      if !backup_path
        $install_status = "failed"
        $install_error = "Backup creation failed"
        return false
      end
      $install_progress = 25.0

      # Step 2: Verify staged files (skip if no manifest)
      $install_status = "installing"
      manifest = $update_manifest

      if manifest && manifest["files"]
        if !verify_staged_files(manifest)
          $install_status = "failed"
          $install_error = "Staged files verification failed"
          MultiplayerDebug.error("UPDATE-INSTALLER", "Verification failed, keeping old version") if defined?(MultiplayerDebug)
          return false
        end
      else
        MultiplayerDebug.warn("UPDATE-INSTALLER", "No manifest available, skipping verification") if defined?(MultiplayerDebug)
      end
      $install_progress = 50.0

      # Step 3: Apply update (atomic directory swap)
      success = apply_staged_files(manifest)
      if !success
        $install_status = "failed"
        $install_error = "Failed to apply staged files"
        MultiplayerDebug.error("UPDATE-INSTALLER", "Installation failed, rolling back...") if defined?(MultiplayerDebug)

        # Rollback: restore from backup
        if restore_from_backup(backup_path)
          $install_status = "rolled_back"
          MultiplayerDebug.info("UPDATE-INSTALLER", "Rollback successful") if defined?(MultiplayerDebug)
        else
          $install_status = "failed"
          $install_error = "Rollback failed - manual recovery needed"
          MultiplayerDebug.error("UPDATE-INSTALLER", "CRITICAL: Rollback failed!") if defined?(MultiplayerDebug)
        end
        return false
      end
      $install_progress = 75.0

      # Step 4: Cleanup
      cleanup_after_install
      $install_progress = 100.0

      # Step 5: Update state
      $install_status = "complete"
      clear_install_state
      VersionChecker.clear_update_state

      MultiplayerDebug.info("UPDATE-INSTALLER", "Installation complete: v#{state[:downloading_version]}") if defined?(MultiplayerDebug)
      return true

    rescue => e
      $install_status = "failed"
      $install_error = e.message
      MultiplayerDebug.error("UPDATE-INSTALLER", "Installation error: #{e.message}") if defined?(MultiplayerDebug)
      return false
    end
  end

  # Create backup of current Scripts folder
  # @return [String, nil] Backup path or nil on failure
  def create_backup
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    backup_name = "scripts_backup_#{timestamp}"
    backup_path = File.join(BACKUPS_DIR, backup_name)

    begin
      mkdir_p(BACKUPS_DIR)

      # Backup only 659_Multiplayer folder
      source_scripts = File.join("Data", "Scripts", "659_Multiplayer")
      dest_scripts = File.join(backup_path, "659_Multiplayer")

      if File.exist?(source_scripts)
        copy_directory(source_scripts, dest_scripts)
        MultiplayerDebug.info("UPDATE-INSTALLER", "Backup created: #{backup_name}") if defined?(MultiplayerDebug)
      else
        MultiplayerDebug.warn("UPDATE-INSTALLER", "No existing scripts to backup") if defined?(MultiplayerDebug)
      end

      # Cleanup old backups (keep only MAX_BACKUPS most recent)
      cleanup_old_backups

      return backup_path
    rescue => e
      MultiplayerDebug.error("UPDATE-INSTALLER", "Backup failed: #{e.message}") if defined?(MultiplayerDebug)
      return nil
    end
  end

  # Cleanup old backups, keeping only the most recent MAX_BACKUPS
  def cleanup_old_backups
    return unless Dir.exist?(BACKUPS_DIR)

    backups = Dir.glob(File.join(BACKUPS_DIR, "scripts_backup_*"))
                 .select { |f| File.directory?(f) }
                 .sort_by { |f| File.mtime(f) }
                 .reverse

    # Delete oldest backups
    backups.drop(MAX_BACKUPS).each do |old_backup|
      rm_rf(old_backup)
      MultiplayerDebug.info("UPDATE-INSTALLER", "Deleted old backup: #{File.basename(old_backup)}") if defined?(MultiplayerDebug)
    end
  end

  # Verify all staged files match manifest MD5
  # @param manifest [Hash] Update manifest
  # @return [Boolean] True if all files valid
  def verify_staged_files(manifest)
    return false unless manifest && manifest["files"]

    files = manifest["files"]
    MultiplayerDebug.info("UPDATE-INSTALLER", "Verifying #{files.length} staged files...") if defined?(MultiplayerDebug)

    files.each do |file_info|
      staged_path = File.join(STAGING_DIR, file_info["path"])
      expected_md5 = file_info["md5"]

      if !File.exist?(staged_path)
        MultiplayerDebug.error("UPDATE-INSTALLER", "Missing staged file: #{file_info['path']}") if defined?(MultiplayerDebug)
        return false
      end

      actual_md5 = HTTPWrapper.calculate_md5(staged_path)
      if actual_md5 != expected_md5
        MultiplayerDebug.error("UPDATE-INSTALLER", "MD5 mismatch: #{file_info['path']}") if defined?(MultiplayerDebug)
        MultiplayerDebug.error("UPDATE-INSTALLER", "  Expected: #{expected_md5}") if defined?(MultiplayerDebug)
        MultiplayerDebug.error("UPDATE-INSTALLER", "  Actual: #{actual_md5}") if defined?(MultiplayerDebug)
        return false
      end
    end

    MultiplayerDebug.info("UPDATE-INSTALLER", "All staged files verified (#{files.length} files)") if defined?(MultiplayerDebug)
    return true
  end

  # Apply staged files to live Scripts folder (atomic operation)
  # @param manifest [Hash] Update manifest
  # @return [Boolean] True if successful
  def apply_staged_files(manifest)
    return false unless manifest && manifest["files"]

    begin
      files = manifest["files"]
      MultiplayerDebug.info("UPDATE-INSTALLER", "Applying #{files.length} files...") if defined?(MultiplayerDebug)

      files.each_with_index do |file_info, index|
        staged_path = File.join(STAGING_DIR, file_info["path"])
        target_path = file_info["path"]

        # Ensure target directory exists
        mkdir_p(File.dirname(target_path))

        # Atomic move: delete old, copy new
        File.delete(target_path) if File.exist?(target_path)

        # Manual file copy (RGSS-compatible)
        File.open(staged_path, "rb") do |from|
          File.open(target_path, "wb") do |to|
            to.write(from.read)
          end
        end

        if (index + 1) % 10 == 0
          MultiplayerDebug.info("UPDATE-INSTALLER", "Progress: #{index + 1}/#{files.length}") if defined?(MultiplayerDebug)
        end
      end

      MultiplayerDebug.info("UPDATE-INSTALLER", "Applied #{files.length} files to live directories") if defined?(MultiplayerDebug)
      return true
    rescue => e
      MultiplayerDebug.error("UPDATE-INSTALLER", "Failed to apply files: #{e.message}") if defined?(MultiplayerDebug)
      return false
    end
  end

  # Restore from backup
  # @param backup_path [String] Path to backup directory
  # @return [Boolean] True if successful
  def restore_from_backup(backup_path)
    return false unless File.exist?(backup_path)

    begin
      source_backup = File.join(backup_path, "659_Multiplayer")
      target_scripts = File.join("Data", "Scripts", "659_Multiplayer")

      # Remove current (corrupted) scripts
      rm_rf(target_scripts) if File.exist?(target_scripts)

      # Restore from backup
      copy_directory(source_backup, target_scripts)

      MultiplayerDebug.info("UPDATE-INSTALLER", "Restored from backup: #{File.basename(backup_path)}") if defined?(MultiplayerDebug)
      return true
    rescue => e
      MultiplayerDebug.error("UPDATE-INSTALLER", "Restore failed: #{e.message}") if defined?(MultiplayerDebug)
      return false
    end
  end

  # Cleanup after successful installation
  def cleanup_after_install
    # Delete pending downloads
    rm_rf(PENDING_DIR) if Dir.exist?(PENDING_DIR)

    # Delete staging area
    rm_rf(STAGING_DIR) if Dir.exist?(STAGING_DIR)

    MultiplayerDebug.info("UPDATE-INSTALLER", "Cleanup complete") if defined?(MultiplayerDebug)
  rescue => e
    MultiplayerDebug.warn("UPDATE-INSTALLER", "Cleanup warning: #{e.message}") if defined?(MultiplayerDebug)
  end

  # Clear installation state
  def clear_install_state
    File.delete(STATE_FILE) if File.exist?(STATE_FILE)
  rescue => e
    MultiplayerDebug.warn("UPDATE-INSTALLER", "Failed to clear state: #{e.message}") if defined?(MultiplayerDebug)
  end

  # Check if there's a pending installation
  # @return [Boolean] True if installation is pending
  def installation_pending?
    state = UpdateDownloader.load_download_state
    return false unless state
    return state[:download_complete] && state[:verified]
  end

  # Get installation info
  # @return [Hash, nil] Installation info or nil
  def get_install_info
    return nil unless installation_pending?
    state = UpdateDownloader.load_download_state
    return {
      version: state[:downloading_version],
      status: $install_status,
      progress: $install_progress,
      error: $install_error
    }
  end
end

#-------------------------------------------------------------------------------
# Check for pending installation on module load
#-------------------------------------------------------------------------------
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("UPDATE-INSTALLER", "=" * 60)
  MultiplayerDebug.info("UPDATE-INSTALLER", "004_Update_Installer.rb loaded successfully")

  if UpdateInstaller.installation_pending?
    MultiplayerDebug.info("UPDATE-INSTALLER", "Pending installation detected!")
    MultiplayerDebug.info("UPDATE-INSTALLER", "Will install on next game restart")
  else
    MultiplayerDebug.info("UPDATE-INSTALLER", "No pending installation")
  end

  MultiplayerDebug.info("UPDATE-INSTALLER", "=" * 60)
end
