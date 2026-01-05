#===============================================================================
# Update UI Hook for Title Screen
#===============================================================================
# Hooks into pbStartLoadScreen to add "Update Multiplayer" button
# Shows update status and allows manual update checks
#===============================================================================

class PokemonLoadScreen
  alias pbStartLoadScreen_original_no_update pbStartLoadScreen

  def pbStartLoadScreen
    # Check if there's a pending installation BEFORE loading screen
    # Simple check: if Updates/staging exists and has files, install them
    staging_dir = File.join("Updates", "staging")
    has_staged_files = Dir.exist?(staging_dir) && !Dir.glob(File.join(staging_dir, "**", "*")).select { |f| File.file?(f) }.empty?

    if has_staged_files || UpdateInstaller.installation_pending?
      pbMessage(_INTL("Installing update..."))

      state = UpdateDownloader.load_download_state
      version = state ? state[:downloading_version] : "unknown"

      success = UpdateInstaller.install_pending_update

      if success
        pbMessage(_INTL("Update installed successfully! (v{1})", version))
        sleep(2)
      else
        error = $install_error || "Unknown error"
        pbMessage(_INTL("Installation failed: {1}", error))
      end
    end

    # Check for updates on startup
    pbMessage(_INTL("Checking for multiplayer mod update..."))
    VersionChecker.check_for_updates

    # Wait briefly for check to complete
    wait_time = 0
    while wait_time < 3 && !$update_available && !$update_check_failed
      sleep(0.1)
      wait_time += 0.1
    end

    # Prompt if update found
    if $update_available && $update_version
      if pbConfirmMessage(_INTL("New version v{1} available! Download now?", $update_version))
        # Blocking download with progress
        if defined?(UpdateDownloader) && defined?($update_manifest)
          pbMessage(_INTL("Downloading update v{1}...", $update_version))

          success = UpdateDownloader.download_update_blocking($update_manifest, $update_version)

          if success
            pbMessage(_INTL("Download complete! Restart the game to install."))
          else
            error_msg = $download_error || "Unknown error"
            pbMessage(_INTL("Download failed: {1}", error_msg))
          end
        end
      end
    end

    # Initialize update UI
    UpdateUI.initialize_ui

    # Run original method
    return pbStartLoadScreen_original_no_update
  end

  # This was the old broken version - keeping commented for reference
  # The issue was we duplicated the entire method instead of calling the original
  def pbStartLoadScreen_OLD_BROKEN_VERSION
    # Check for updates on startup (non-blocking)
    VersionChecker.check_for_updates

    # Check if there's a pending installation BEFORE loading screen
    if UpdateInstaller.installation_pending?
      UpdateUI.show_installation_screen

      state = UpdateDownloader.load_download_state
      version = state ? state[:downloading_version] : "unknown"

      success = UpdateInstaller.install_pending_update
      UpdateUI.show_installation_result(success, version)

      if success
        # Show success message for 3 seconds before continuing
        sleep(3)
      end
    end

    # Initialize update UI
    UpdateUI.initialize_ui

    # Now run the original pbStartLoadScreen with our modifications
    updateHttpSettingsFile
    updateCreditsFile
    updateCustomDexFile
    updateOnlineCustomSpritesFile

    # Check for newer version (original system)
    newer_version = find_newer_available_version
    if newer_version
      if File.file?('.\INSTALL_OR_UPDATE.bat')
        update_answer = pbMessage(_INTL("Version {1} is now available! Update now?", newer_version), ["Yes","No"], 1)
        if update_answer == 0
          Process.spawn('.\INSTALL_OR_UPDATE.bat', "auto")
          exit
        end
      else
        pbMessage(_INTL("Version {1} is now available! Please check the game's official page to download the newest version.", newer_version))
      end
    end

    if $PokemonSystem && $PokemonSystem.shiny_cache == 1
      checkDirectory("Cache")
      checkDirectory("Cache/Shiny")
      Dir.glob("Cache/Shiny/*").each do |file|
        File.delete(file) if File.file?(file)
      end
    end

    if ($game_temp.unimportedSprites && $game_temp.unimportedSprites.size > 0)
      handleReplaceExistingSprites()
    end
    if ($game_temp.nb_imported_sprites && $game_temp.nb_imported_sprites > 0)
      pbMessage(_INTL("{1} new custom sprites were imported into the game", $game_temp.nb_imported_sprites.to_s))
    end
    checkEnableSpritesDownload
    $game_temp.nb_imported_sprites = nil

    copyKeybindings()
    $KURAY_OPTIONSNAME_LOADED = false
    kurayeggs_main() if $KURAYEGGS_WRITEDATA

    save_file_list = SaveData::AUTO_SLOTS + SaveData::MANUAL_SLOTS
    first_time = true
    loop do
      if @selected_file
        @save_data = load_save_file(SaveData.get_full_path(@selected_file))
      else
        @save_data = {}
      end

      commands = []
      cmd_continue = -1
      cmd_new_game = -1
      cmd_new_game_plus = -1
      cmd_options = -1
      cmd_language = -1
      cmd_mystery_gift = -1
      cmd_debug = -1
      cmd_quit = -1
      cmd_doc = -1
      cmd_discord = -1
      cmd_pifdiscord = -1
      cmd_wiki = -1
      cmd_update_mp = -1  # NEW: Update Multiplayer command

      show_continue = !@save_data.empty?
      new_game_plus = show_continue && (@save_data[:player].new_game_plus_unlocked || $DEBUG)

      if show_continue
        commands[cmd_continue = commands.length] = "#{@selected_file}"
        commands[cmd_mystery_gift = commands.length] = _INTL('Mystery Gift')
      end

      commands[cmd_new_game = commands.length] = _INTL('New Game')
      if new_game_plus
        commands[cmd_new_game_plus = commands.length] = _INTL('New Game +')
      end

      commands[cmd_options = commands.length] = _INTL('Options')

      # NEW: Add "Update Multiplayer" button
      update_text = get_update_button_text
      commands[cmd_update_mp = commands.length] = update_text

      commands[cmd_discord = commands.length] = _INTL('KIF Discord')
      commands[cmd_doc = commands.length] = _INTL('KIF Documentation (Obsolete)')
      commands[cmd_pifdiscord = commands.length] = _INTL('PIF Discord')
      commands[cmd_wiki = commands.length] = _INTL('Wiki')
      commands[cmd_language = commands.length] = _INTL('Language') if Settings::LANGUAGES.length >= 2
      commands[cmd_debug = commands.length] = _INTL('Debug') if $DEBUG
      commands[cmd_quit = commands.length] = _INTL('Quit Game')

      cmd_left = -3
      cmd_right = -2

      map_id = show_continue ? @save_data[:map_factory].map.map_id : 0
      @scene.pbStartScene(commands, show_continue, @save_data[:player],
                          @save_data[:frame_count] || 0, map_id)
      @scene.pbSetParty(@save_data[:player]) if show_continue
      if first_time
        @scene.pbStartScene2
        first_time = false
      else
        @scene.pbUpdate
      end

      loop do
        command = @scene.pbChoose(commands, cmd_continue)
        pbPlayDecisionSE if command != cmd_quit

        case command
        when cmd_continue
          @scene.pbEndScene
          Game.load(@save_data)
          $game_switches[SWITCH_V5_1] = true
          ensureCorrectDifficulty()
          setGameMode()
          $PokemonGlobal.alt_sprite_substitutions = {} if !$PokemonGlobal.alt_sprite_substitutions
          $PokemonGlobal.autogen_sprites_cache = {}
          return
        when cmd_new_game
          @scene.pbEndScene
          Game.start_new
          $PokemonGlobal.alt_sprite_substitutions = {} if !$PokemonGlobal.alt_sprite_substitutions
          return
        when cmd_new_game_plus
          @scene.pbEndScene
          Game.start_new(@save_data[:bag], @save_data[:storage_system], @save_data[:player])
          @save_data[:player].new_game_plus_unlocked = true
          return
        when cmd_pifdiscord
          openUrlInBrowser(Settings::PIF_DISCORD_URL)
        when cmd_wiki
          openUrlInBrowser(Settings::WIKI_URL)
        when cmd_doc
          openUrlInBrowser("https://docs.google.com/document/d/1O6pKKL62dbLcapO0c2zDG2UI-eN6uatYlt_0GSk1dbE")
          return
        when cmd_discord
          openUrlInBrowser(Settings::DISCORD_URL)
          return
        when cmd_mystery_gift
          pbFadeOutIn { pbDownloadMysteryGift(@save_data[:player]) }
        when cmd_options
          pbFadeOutIn do
            scene = PokemonOption_Scene.new
            screen = PokemonOptionScreen.new(scene)
            screen.pbStartScreen(true)
          end
        when cmd_language
          @scene.pbEndScene
          $PokemonSystem.language = pbChooseLanguage
          pbLoadMessages('Data/' + Settings::LANGUAGES[$PokemonSystem.language][1])
          if show_continue
            @save_data[:pokemon_system] = $PokemonSystem
            File.open(SaveData.get_full_path(@selected_file), 'wb') { |file| Marshal.dump(@save_data, file) }
          end
          $scene = pbCallTitle
          return
        when cmd_debug
          pbFadeOutIn { pbDebugMenu(false) }

        # NEW: Handle "Update Multiplayer" button
        when cmd_update_mp
          pbFadeOutIn { handle_update_multiplayer_menu }

        when cmd_quit
          pbPlayCloseMenuSE
          @scene.pbEndScene
          $scene = nil
          return
        when cmd_left
          if @selected_file
            old_index = save_file_list.index(@selected_file)
            new_index = (old_index - 1) % save_file_list.length
            @selected_file = save_file_list[new_index]
            break
          end
        when cmd_right
          if @selected_file
            old_index = save_file_list.index(@selected_file)
            new_index = (old_index + 1) % save_file_list.length
            @selected_file = save_file_list[new_index]
            break
          end
        end
      end
    end
  end

  # Get dynamic text for the update button
  # @return [String] Button text based on update status
  def get_update_button_text
    if UpdateInstaller.installation_pending?
      return _INTL('Update Ready - Restart to Install')
    elsif $download_status == "downloading"
      return _INTL('Downloading Update ({1}%)', $download_progress.round(0))
    elsif $download_status == "complete"
      return _INTL('Update Downloaded - Restart Now')
    elsif $update_available
      return _INTL('Update Available (v{1})', $update_version)
    else
      return _INTL('Check for Updates')
    end
  end

  # Handle the Update Multiplayer menu
  def handle_update_multiplayer_menu
    if UpdateInstaller.installation_pending?
      # Update is ready to install
      message = _INTL("An update is ready to install. Please restart the game to apply it.")
      pbMessage(message)

      if pbConfirmMessage(_INTL("Restart now?"))
        # Save any changes and restart
        @scene.pbEndScene
        system("start \"\" \"#{$0}\"")
        exit
      end

    elsif $download_status == "downloading" || $download_status == "verifying"
      # Download in progress
      message = _INTL("Update download in progress: {1}%", $download_progress.round(1))
      pbMessage(message)

    elsif $download_status == "complete"
      # Download complete, ready to install
      message = _INTL("Update downloaded successfully! Restart the game to install.")
      pbMessage(message)

      if pbConfirmMessage(_INTL("Restart now?"))
        @scene.pbEndScene
        system("start \"\" \"#{$0}\"")
        exit
      end

    elsif $download_status == "failed"
      # Download failed
      error_msg = $download_error || "Unknown error"
      message = _INTL("Update download failed: {1}", error_msg)
      pbMessage(message)

      if pbConfirmMessage(_INTL("Try again?"))
        UpdateDownloader.download_update($update_manifest, $update_version)
      end

    elsif $update_available
      # Update available, prompt to download
      info = VersionChecker.get_update_info

      message = _INTL("Update available: v{1}\n", info[:version])
      message += _INTL("Size: {1} MB\n", (info[:size] / 1024.0 / 1024.0).round(2))
      message += _INTL("Files: {1}\n\n", info[:files_count])
      message += _INTL("Changelog:\n{1}", info[:changelog])

      pbMessage(message)

      choices = [_INTL("Download Now"), _INTL("Later"), _INTL("Dismiss")]
      choice = pbMessage(_INTL("Download this update?"), choices, 2)

      case choice
      when 0  # Download Now
        UpdateUI.start_download
        pbMessage(_INTL("Download started! You can continue playing while it downloads."))
      when 1  # Later
        # Do nothing, keep showing banner
      when 2  # Dismiss
        UpdateUI.dismiss_update
        pbMessage(_INTL("Update dismissed. You can check again later."))
      end

    else
      # No update available, check manually
      pbMessage(_INTL("Checking for updates..."))

      # Force a new check
      $update_last_check = nil
      VersionChecker.check_for_updates

      # Wait a bit for the check to complete
      wait_time = 0
      while wait_time < 5 && !$update_available && !$update_check_failed
        sleep(0.5)
        wait_time += 0.5
      end

      if $update_available
        pbMessage(_INTL("Update found! v{1} is available.", $update_version))
      elsif $update_check_failed
        pbMessage(_INTL("Failed to check for updates. Please check your internet connection."))
      else
        pbMessage(_INTL("You are running the latest version (v{1}).", VersionChecker::CURRENT_VERSION))
      end
    end
  end
end

#-------------------------------------------------------------------------------
# Module loaded successfully
#-------------------------------------------------------------------------------
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("UPDATE-UI-HOOK", "=" * 60)
  MultiplayerDebug.info("UPDATE-UI-HOOK", "006_Update_UI_Hook.rb loaded successfully")
  MultiplayerDebug.info("UPDATE-UI-HOOK", "'Update Multiplayer' button added to title screen")
  MultiplayerDebug.info("UPDATE-UI-HOOK", "Installation check enabled on startup")
  MultiplayerDebug.info("UPDATE-UI-HOOK", "=" * 60)
end
