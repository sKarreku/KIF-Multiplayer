#===============================================================================
# Update UI Module
#===============================================================================
# Provides user interface for update notifications and management
# Displays banners, prompts, and progress on title screen
#===============================================================================

module UpdateUI
  module_function

  # UI state
  $update_ui_dismissed = false
  $update_ui_show_banner = false
  $update_ui_downloading = false

  # Initialize update UI (call on title screen load)
  def initialize_ui
    # Check if update is available
    if $update_available && !$update_ui_dismissed
      $update_ui_show_banner = true
      MultiplayerDebug.info("UPDATE-UI", "Update banner shown: v#{$update_version}") if defined?(MultiplayerDebug)
    end

    # Check if download is in progress
    if $download_status == "downloading" || $download_status == "verifying"
      $update_ui_downloading = true
    end

    # Check if update is ready to install
    if UpdateInstaller.installation_pending?
      MultiplayerDebug.info("UPDATE-UI", "Update ready to install on restart") if defined?(MultiplayerDebug)
    end
  end

  # Get UI text for update banner
  # @return [String, nil] Banner text or nil if no update
  def get_banner_text
    return nil unless $update_ui_show_banner

    if $update_available
      return "Update Available: v#{$update_version}"
    elsif UpdateInstaller.installation_pending?
      return "Update Ready - Restart to Install"
    else
      return nil
    end
  end

  # Get UI text for download status
  # @return [String, nil] Status text or nil
  def get_download_status_text
    case $download_status
    when "downloading"
      return "Downloading update: #{$download_progress.round(1)}%"
    when "verifying"
      return "Verifying download..."
    when "complete"
      return "Download complete! Restart to install."
    when "failed"
      return "Download failed: #{$download_error || 'Unknown error'}"
    else
      return nil
    end
  end

  # Get UI text for installation status
  # @return [String, nil] Status text or nil
  def get_install_status_text
    case $install_status
    when "backing_up"
      return "Creating backup... #{$install_progress.round(1)}%"
    when "installing"
      return "Installing update... #{$install_progress.round(1)}%"
    when "complete"
      return "Installation complete!"
    when "failed"
      return "Installation failed: #{$install_error || 'Unknown error'}"
    when "rolled_back"
      return "Update rolled back - using previous version"
    else
      return nil
    end
  end

  # Prompt user to download update
  # @return [Symbol] :yes, :no, :later
  def prompt_download_update
    info = VersionChecker.get_update_info
    return :no unless info

    # In a real Pokemon Essentials game, this would show a custom UI
    # For now, we'll use MultiplayerDebug to simulate the prompt
    MultiplayerDebug.info("UPDATE-UI", "=" * 60) if defined?(MultiplayerDebug)
    MultiplayerDebug.info("UPDATE-UI", "UPDATE AVAILABLE: v#{info[:version]}") if defined?(MultiplayerDebug)
    MultiplayerDebug.info("UPDATE-UI", "Changelog: #{info[:changelog]}") if defined?(MultiplayerDebug)
    MultiplayerDebug.info("UPDATE-UI", "Size: #{(info[:size] / 1024.0 / 1024.0).round(2)} MB") if defined?(MultiplayerDebug)
    MultiplayerDebug.info("UPDATE-UI", "Files: #{info[:files_count]}") if defined?(MultiplayerDebug)
    MultiplayerDebug.info("UPDATE-UI", "=" * 60) if defined?(MultiplayerDebug)

    # Return :yes to auto-download (in real implementation, show UI)
    return :yes
  end

  # Start update download (triggered by user action)
  # @return [Boolean] True if download started
  def start_download
    return false unless $update_available
    return false if $download_status == "downloading"

    success = UpdateDownloader.download_update($update_manifest, $update_version)
    if success
      $update_ui_downloading = true
      MultiplayerDebug.info("UPDATE-UI", "Download started") if defined?(MultiplayerDebug)
    else
      MultiplayerDebug.error("UPDATE-UI", "Failed to start download") if defined?(MultiplayerDebug)
    end

    return success
  end

  # Dismiss update notification
  def dismiss_update
    $update_ui_dismissed = true
    $update_ui_show_banner = false
    MultiplayerDebug.info("UPDATE-UI", "Update dismissed by user") if defined?(MultiplayerDebug)
  end

  # Check if user should be prompted
  # @return [Boolean] True if prompt should be shown
  def should_prompt_user?
    return false if $update_ui_dismissed
    return false unless $update_available
    return false if $download_status == "downloading"
    return false if $download_status == "complete"
    return true
  end

  # Update UI tick (call every frame on title screen)
  def update_tick
    # Update download status
    if $update_ui_downloading
      if $download_status == "complete"
        $update_ui_downloading = false
        MultiplayerDebug.info("UPDATE-UI", "Download complete notification") if defined?(MultiplayerDebug)
      elsif $download_status == "failed"
        $update_ui_downloading = false
        MultiplayerDebug.error("UPDATE-UI", "Download failed notification") if defined?(MultiplayerDebug)
      end
    end

    # Show prompt if needed (throttle to avoid spam)
    if should_prompt_user?
      # In real implementation, check if prompt hasn't been shown recently
      # For now, just log
    end
  end

  # Get update summary for display
  # @return [Hash, nil] Summary hash or nil
  def get_update_summary
    return nil unless $update_available

    info = VersionChecker.get_update_info
    return {
      version: $update_version,
      changelog: info[:changelog],
      size_mb: (info[:size] / 1024.0 / 1024.0).round(2),
      files_count: info[:files_count],
      download_status: $download_status,
      download_progress: $download_progress,
      ready_to_install: UpdateInstaller.installation_pending?
    }
  end

  # Show installation blocking screen (call before install)
  # This should be called in a way that blocks user input
  def show_installation_screen
    MultiplayerDebug.info("UPDATE-UI", "=" * 60) if defined?(MultiplayerDebug)
    MultiplayerDebug.info("UPDATE-UI", "INSTALLING UPDATE") if defined?(MultiplayerDebug)
    MultiplayerDebug.info("UPDATE-UI", "Please do not close the game...") if defined?(MultiplayerDebug)
    MultiplayerDebug.info("UPDATE-UI", "=" * 60) if defined?(MultiplayerDebug)

    # In real implementation, show full-screen blocking UI with progress bar
    # For now, rely on MultiplayerDebug logging
  end

  # Show installation complete screen
  # @param success [Boolean] True if installation succeeded
  # @param version [String] Version that was installed
  def show_installation_result(success, version)
    if success
      MultiplayerDebug.info("UPDATE-UI", "=" * 60) if defined?(MultiplayerDebug)
      MultiplayerDebug.info("UPDATE-UI", "UPDATE COMPLETE!") if defined?(MultiplayerDebug)
      MultiplayerDebug.info("UPDATE-UI", "Now running v#{version}") if defined?(MultiplayerDebug)
      MultiplayerDebug.info("UPDATE-UI", "=" * 60) if defined?(MultiplayerDebug)
    else
      MultiplayerDebug.error("UPDATE-UI", "=" * 60) if defined?(MultiplayerDebug)
      MultiplayerDebug.error("UPDATE-UI", "UPDATE FAILED") if defined?(MultiplayerDebug)
      MultiplayerDebug.error("UPDATE-UI", "Error: #{$install_error || 'Unknown error'}") if defined?(MultiplayerDebug)
      MultiplayerDebug.error("UPDATE-UI", "Running previous version") if defined?(MultiplayerDebug)
      MultiplayerDebug.error("UPDATE-UI", "=" * 60) if defined?(MultiplayerDebug)
    end
  end

  # Reset UI state (for testing)
  def reset_ui_state
    $update_ui_dismissed = false
    $update_ui_show_banner = false
    $update_ui_downloading = false
  end
end

#===============================================================================
# Integration Hooks for Pokemon Essentials Title Screen
#===============================================================================
# These hooks should be added to the title screen scene
#===============================================================================

# Example integration (add to your title screen update method):
#
# class Scene_Title
#   alias update_auto_updater_original update
#   def update
#     update_auto_updater_original
#     UpdateUI.update_tick
#   end
# end

# Example integration (add to title screen initialization):
#
# class Scene_Title
#   alias initialize_auto_updater_original initialize
#   def initialize
#     initialize_auto_updater_original
#     UpdateUI.initialize_ui
#
#     # Check for updates on startup (non-blocking)
#     VersionChecker.check_for_updates
#
#     # Auto-prompt for download if update available
#     if UpdateUI.should_prompt_user?
#       response = UpdateUI.prompt_download_update
#       case response
#       when :yes
#         UpdateUI.start_download
#       when :no
#         UpdateUI.dismiss_update
#       when :later
#         # Keep showing banner
#       end
#     end
#   end
# end

# Example integration (add before game loads):
#
# # In main.rb or boot script, BEFORE loading scripts:
# if UpdateInstaller.installation_pending?
#   UpdateUI.show_installation_screen
#   success = UpdateInstaller.install_pending_update
#   state = UpdateDownloader.load_download_state
#   version = state ? state[:downloading_version] : "unknown"
#   UpdateUI.show_installation_result(success, version)
# end

#-------------------------------------------------------------------------------
# Module loaded successfully
#-------------------------------------------------------------------------------
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("UPDATE-UI", "=" * 60)
  MultiplayerDebug.info("UPDATE-UI", "005_Update_UI.rb loaded successfully")
  MultiplayerDebug.info("UPDATE-UI", "Title screen integration ready")
  MultiplayerDebug.info("UPDATE-UI", "=" * 60)
end
