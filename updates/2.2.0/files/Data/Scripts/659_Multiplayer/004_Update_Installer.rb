#===============================================================================
# Update Installer Module
#===============================================================================
# Installs verified updates BEFORE scripts load
# Provides atomic installation with backup and rollback
#===============================================================================

module UpdateInstaller
  module_function

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
    return true unless state # No update pending

    # Only install if download is complete and verified
    return true unless state[:download_complete] && state[:verified]

    begin
      $install_status = "backing_up"
      $install_progress = 0.0
      $install_error = nil

      MultiplayerDebug.info("UPDATE-INSTALLER", "Starting installation of v#{state[:downloading_version]}") if defined?(MultiplayerDebug)

      # Step 1: Create backup
      backup_path = create_backup
      if !backup_path
        $install_status = "failed"
        $install_error = "Backup creation failed"
        return false
      end
      $install_progress = 25.0

      # Step 2: Verify staged files
      $install_status = "installing"
      manifest = $update_manifest
      if !verify_staged_files(manifest)
        $install_status = "failed"
        $install_error = "Staged files verification failed"
        MultiplayerDebug.error("UPDATE-INSTALLER", "Verification failed, keeping old version") if defined?(MultiplayerDebug)
        return false
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
      FileUtils.mkdir_p(BACKUPS_DIR)

      # Backup only 659_Multiplayer folder
      source_scripts = File.join("Data", "Scripts", "659_Multiplayer")
      dest_scripts = File.join(backup_path, "659_Multiplayer")

      if File.exist?(source_scripts)
        FileUtils.cp_r(source_scripts, dest_scripts)
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
      FileUtils.rm_rf(old_backup)
      MultiplayerDebug.info("UPDATE-INSTALLER", "Deleted old backup: #{File.basename(old_backup)}") if defined?(MultiplayerDebug)
    end
  end

  # Verify all staged files match manifest SHA256
  # @param manifest [Hash] Update manifest
  # @return [Boolean] True if all files valid
  def verify_staged_files(manifest)
    return false unless manifest && manifest["files"]

    files = manifest["files"]
    files.each do |file_info|
      staged_path = File.join(STAGING_DIR, file_info["path"])
      expected_sha256 = file_info["sha256"]

      if !File.exist?(staged_path)
        MultiplayerDebug.error("UPDATE-INSTALLER", "Missing staged file: #{file_info['path']}") if defined?(MultiplayerDebug)
        return false
      end

      actual_sha256 = HTTPWrapper.calculate_sha256(staged_path)
      if actual_sha256 != expected_sha256
        MultiplayerDebug.error("UPDATE-INSTALLER", "SHA256 mismatch: #{file_info['path']}") if defined?(MultiplayerDebug)
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
      files.each do |file_info|
        staged_path = File.join(STAGING_DIR, file_info["path"])
        target_path = file_info["path"]

        # Ensure target directory exists
        FileUtils.mkdir_p(File.dirname(target_path))

        # Atomic move: delete old, move new
        File.delete(target_path) if File.exist?(target_path)
        FileUtils.mv(staged_path, target_path)
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
      FileUtils.rm_rf(target_scripts) if File.exist?(target_scripts)

      # Restore from backup
      FileUtils.cp_r(source_backup, target_scripts)

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
    FileUtils.rm_rf(PENDING_DIR) if Dir.exist?(PENDING_DIR)

    # Delete staging area
    FileUtils.rm_rf(STAGING_DIR) if Dir.exist?(STAGING_DIR)

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
