#===============================================================================
# Title Screen Multiplayer Menu
# File: 659_Multiplayer/002_UI/015_TitleMultiplayer.rb
#
# Adds a "Multiplayer" option to the title/load screen above Continue.
# Sub-options: Join Official, Host Custom, Join Custom, Back.
# Sets $multiplayer_auto_connect so the game connects after loading.
#
# Hooks into the MultiSaves.rb version of pbStartLoadScreen which uses:
#   - pbChoose(commands, cmd_continue) with 2 args
#   - outer loop for save slot switching
#   - @selected_file for current save slot
#===============================================================================

module TitleMultiplayer
  OFFICIAL_IP    = "51.20.131.110"
  SERVER_PORT    = 12975
  KIFM_DIR       = "KIFM"
  LAUNCH_BAT     = "KIFM/launch_server.bat"

  def self.pending_ip
    $multiplayer_auto_connect
  end

  def self.set_pending_ip(ip)
    $multiplayer_auto_connect = ip
  end

  def self.clear_pending
    $multiplayer_auto_connect = nil
  end

  # ── Main submenu (called from the load screen) ───────────────────────────
  def self.open_menu
    loop do
      server_key = "#{OFFICIAL_IP}:#{SERVER_PORT}"
      discord_linked = defined?(DiscordIDStorage) && !DiscordIDStorage.get(server_key).to_s.empty?
      discord_label  = discord_linked ? "Discord Account (Linked)" : "Link Discord Account"

      commands = [
        "Join Official Server",
        "Host a Custom Server",
        "Join a Custom Server",
        discord_label,
        "Back"
      ]
      cmd = pbMessage(
        "Choose a multiplayer option:",
        commands, commands.length
      )

      case cmd
      when 0 then result = _join_official
      when 1 then result = _host_custom
      when 2 then result = _join_custom
      when 3
        _link_discord
        next
      when 4, -1
        return :back
      end
      return result if result == :continue_to_save
    end
  end

  # ── Link Discord Account ─────────────────────────────────────────────────
  # At the title screen there's no active TCP connection, so we store the
  # code locally. It's auto-sent to the server on the next successful connect.
  def self._link_discord
    server_key = "#{OFFICIAL_IP}:#{SERVER_PORT}"
    existing   = defined?(DiscordIDStorage) ? DiscordIDStorage.get(server_key).to_s : ""

    if !existing.empty?
      choice = pbShowCommands(nil, [
        "Keep current link (ID: ...#{existing[-6..]})",
        "Re-link to a different Discord account",
        "Cancel"
      ], -1)
      return if choice == 0 || choice == 2 || choice == -1
    end

    pbMessage("Your browser will open to authorize with Discord.\n\n" \
              "After clicking Authorize, you'll see a 6-letter code.\n" \
              "Come back and enter it on the next screen.")

    openUrlInBrowser("http://#{OFFICIAL_IP}:12976/auth/discord") rescue nil

    code = pbMessageFreeText("Enter the code from the browser:", "", false, 8)
    return if code.nil? || code.strip.empty?

    # Save the pending code — auto-sent when the player connects in-game
    _save_pending_discord_code(code.strip.upcase)
    pbMessage("Code saved!\n\nLoad your save and connect to the server.\nThe link will complete automatically.")
  end

  def self.pending_discord_code_path
    File.join(KIFM_DIR, "pending_discord_link.txt")
  end

  def self._save_pending_discord_code(code)
    Dir.mkdir(KIFM_DIR) unless Dir.exist?(KIFM_DIR)
    File.write(pending_discord_code_path, code)
  rescue; end

  def self.pop_pending_discord_code
    path = pending_discord_code_path
    return nil unless File.exist?(path)
    code = File.read(path).strip
    File.delete(path) rescue nil
    code.empty? ? nil : code
  rescue
    nil
  end

  # ── Join Official Server ─────────────────────────────────────────────────
  def self._join_official
    unless _npt_installed?
      pbMessage("The NPT (New Pokemon Trainer) pack is required to play\n" \
                "on the official server.\n\n" \
                "Please download it from the KIF Discord.")
      return :back
    end
    pbMessage("You will connect to the official KIF Multiplayer server.\n" \
              "This is the easiest way to play with friends!")
    set_pending_ip(OFFICIAL_IP)
    _save_settings(OFFICIAL_IP)
    :continue_to_save
  end

  # ── Host a Custom Server ─────────────────────────────────────────────────
  def self._host_custom
    unless _ruby_installed?
      pbMessage("Ruby is not installed on this computer.\n" \
                "Please install Ruby before hosting a server.\n" \
                "Download it from: https://rubyinstaller.org")
      return :back
    end

    host_cmds = [
      "LAN (local network only)",
      "Public (auto port-forward via UPnP)",
      "Software (Radmin, Hamachi, etc.)",
      "Back"
    ]
    choice = pbMessage("How do you want to host?", host_cmds, host_cmds.length)
    return :back if choice == 3

    mode_names = ["LAN", "UPnP", "Software"]
    mode = mode_names[choice]

    bat_path = _resolve_bat_path
    unless bat_path && File.exist?(bat_path)
      pbMessage("Could not find launch_server.bat in the KIFM folder.\n" \
                "Make sure the KIFM folder is next to your game.")
      return :back
    end

    pbMessage("The server will now launch in a separate window.\n" \
              "Follow the instructions in the server console to select\n" \
              "your network interface (#{mode}).\n\n" \
              "Once the server is running, your game will load.")

    bat_dir = File.dirname(bat_path).gsub("/", "\\")
    bat_file = File.basename(bat_path)
    begin
      system("start \"KIF Server\" /D \"#{bat_dir}\" \"#{bat_file}\"")
    rescue => e
      pbMessage("Failed to launch server: #{e.message}")
      return :back
    end

    pbMessage("Server launching...\nPress OK once the server console is ready.")
    set_pending_ip("127.0.0.1")
    _save_settings("127.0.0.1")
    :continue_to_save
  end

  # ── Join a Custom Server ─────────────────────────────────────────────────
  def self._join_custom
    pbMessage("Enter the IP address of the server you want to join.\n" \
              "Ask the server host for their IP.\n" \
              "(Port #{SERVER_PORT} is used automatically)")

    ip = pbEnterText("Server IP Address:", 0, 15, "")
    if ip.nil? || ip.strip.empty?
      return :back
    end

    ip = ip.strip
    unless ip.match?(/\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/)
      pbMessage("\"#{ip}\" doesn't look like a valid IP address.\n" \
                "Please enter an IPv4 address (e.g. 192.168.1.100).")
      return :back
    end

    set_pending_ip(ip)
    _save_settings(ip)
    :continue_to_save
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  def self._npt_installed?
    # Check if the 990_NPT scripts folder exists
    npt_candidates = [
      "Data/Scripts/990_NPT",
      "../Data/Scripts/990_NPT",
      File.join(Dir.pwd, "Data/Scripts/990_NPT")
    ]
    npt_candidates.any? { |p| File.directory?(p) }
  rescue
    false
  end

  def self._ruby_installed?
    # Method 1: Try to find ruby.exe via WHERE command
    result = `where ruby 2>NUL` rescue ""
    return true if result.to_s.downcase.include?("ruby")

    # Method 2: Check common install locations
    common_paths = [
      "C:/Ruby*/bin/ruby.exe",
      "C:/Program Files/Ruby*/bin/ruby.exe",
      "C:/Program Files (x86)/Ruby*/bin/ruby.exe"
    ]
    common_paths.each do |pattern|
      return true unless Dir.glob(pattern).empty?
    end

    false
  rescue
    false
  end

  def self._resolve_bat_path
    candidates = [
      LAUNCH_BAT,
      File.join("..", LAUNCH_BAT),
      File.join(Dir.pwd, LAUNCH_BAT)
    ]
    candidates.each { |p| return p if File.exist?(p) }
    nil
  end

  def self._save_settings(ip)
    File.write(MultiplayerUI::SETTINGS_FILE, "#{ip}:#{SERVER_PORT}")
    MultiplayerUI.instance_variable_set(:@settings_loaded, false) if defined?(MultiplayerUI)
  rescue => e
    puts "[TitleMultiplayer] Failed to save settings: #{e.message}"
  end

  def self._auto_connect_if_pending
    return unless $multiplayer_auto_connect && !$multiplayer_auto_connect.to_s.empty?
    ip = $multiplayer_auto_connect
    $multiplayer_auto_connect = nil
    puts "[Multiplayer] Auto-connecting to #{ip}:#{SERVER_PORT}..."
    MultiplayerClient.connect(ip) if defined?(MultiplayerClient)
  end
end

# Initialize the global
$multiplayer_auto_connect = nil

#===============================================================================
# Patch PokemonLoad_Scene — support continue panel at any index
# Must also preserve the left/right arrow sprites from MultiSaves
#===============================================================================
class PokemonLoad_Scene
  alias _kif_mp_orig_pbStartScene pbStartScene unless method_defined?(:_kif_mp_orig_pbStartScene)

  def pbStartScene(commands, show_continue, trainer, frame_count, map_id, continue_index = 0)
    @commands = commands
    @continue_index = continue_index
    @sprites = {}
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99998
    addBackgroundOrColoredPlane(@sprites, "background", "loadbg",
                                Color.new(248, 248, 248), @viewport)

    # Left/right arrows for multi-save switching (from MultiSaves.rb)
    @sprites["leftarrow"] = AnimatedSprite.new("Graphics/Pictures/leftarrow", 8, 40, 28, 2, @viewport)
    @sprites["leftarrow"].x = 10
    @sprites["leftarrow"].y = 140
    @sprites["leftarrow"].play

    @sprites["rightarrow"] = AnimatedSprite.new("Graphics/Pictures/rightarrow", 8, 40, 28, 2, @viewport)
    @sprites["rightarrow"].x = 460
    @sprites["rightarrow"].y = 140
    @sprites["rightarrow"].play

    y = 16 * 2
    for i in 0...commands.length
      is_cont = show_continue && (i == continue_index)
      @sprites["panel#{i}"] = PokemonLoadPanel.new(
        i, commands[i], is_cont, trainer, frame_count, map_id, @viewport
      )
      @sprites["panel#{i}"].x = 24 * 2
      @sprites["panel#{i}"].y = y
      @sprites["panel#{i}"].pbRefresh
      y += is_cont ? 112 * 2 : 24 * 2
    end
    @sprites["cmdwindow"] = Window_CommandPokemon.new([])
    @sprites["cmdwindow"].viewport = @viewport
    @sprites["cmdwindow"].visible  = false
  end

  alias _kif_mp_orig_pbSetParty pbSetParty unless method_defined?(:_kif_mp_orig_pbSetParty)

  def pbSetParty(trainer)
    return if !trainer || !trainer.party
    ci = @continue_index || 0
    y_offset = ci * 24 * 2
    meta = GameData::Metadata.get_player(trainer.character_ID)
    if meta
      filename = pbGetPlayerCharset(meta, 1, trainer, true)
      @sprites["player"] = TrainerWalkingCharSprite.new(filename, @viewport, trainer)
      charwidth  = @sprites["player"].bitmap.width
      charheight = @sprites["player"].bitmap.height
      @sprites["player"].x        = 56 * 2 - charwidth / 8
      @sprites["player"].y        = 56 * 2 - charheight / 8 + y_offset
      @sprites["player"].src_rect = Rect.new(0, 0, charwidth / 4, charheight / 4)
    end
    for i in 0...trainer.party.length
      @sprites["party#{i}"] = PokemonIconSprite.new(trainer.party[i], @viewport)
      @sprites["party#{i}"].setOffset(PictureOrigin::Center)
      @sprites["party#{i}"].x = (167 + 33 * (i % 2)) * 2
      @sprites["party#{i}"].y = (56 + 25 * (i / 2)) * 2 + y_offset
      @sprites["party#{i}"].z = 99999
    end
  end
end

#===============================================================================
# Hook into pbStartLoadScreen — inject "Multiplayer" above Continue
# Builds on MultiSaves.rb version (outer loop for save switching, 2-arg pbChoose)
#===============================================================================
class PokemonLoadScreen
  alias _kif_mp_title_pbStartLoadScreen pbStartLoadScreen unless method_defined?(:_kif_mp_title_pbStartLoadScreen)

  def pbStartLoadScreen
    # ── Pre-init from MultiSaves ──────────────────────────────────────────
    updateHttpSettingsFile rescue nil
    updateCreditsFile rescue nil
    updateCustomDexFile rescue nil
    updateOnlineCustomSpritesFile rescue nil

    newer_version = find_newer_available_version rescue nil
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
      checkDirectory("Cache") rescue nil
      checkDirectory("Cache/Shiny") rescue nil
      Dir.glob("Cache/Shiny/*").each do |file|
        File.delete(file) if File.file?(file)
      end
    end

    has_unimported = (($game_temp.unimportedSprites && $game_temp.unimportedSprites.size > 0) rescue false)
    if has_unimported
      handleReplaceExistingSprites() rescue nil
    end
    has_imported = (($game_temp.nb_imported_sprites && $game_temp.nb_imported_sprites > 0) rescue false)
    if has_imported
      pbMessage(_INTL("{1} new custom sprites were imported into the game", $game_temp.nb_imported_sprites.to_s))
    end
    checkEnableSpritesDownload rescue nil
    $game_temp.nb_imported_sprites = nil rescue nil

    copyKeybindings()
    $KURAY_OPTIONSNAME_LOADED = false
    begin; kurayeggs_main() if $KURAYEGGS_WRITEDATA; rescue; end

    save_file_list = SaveData::AUTO_SLOTS + SaveData::MANUAL_SLOTS
    first_time = true

    loop do
      # ── Outer loop: save slot switching ─────────────────────────────────
      if @selected_file
        @save_data = load_save_file(SaveData.get_full_path(@selected_file))
      else
        @save_data = {}
      end
      @save_data ||= {}

      commands = []
      cmd_multiplayer  = -1
      cmd_continue     = -1
      cmd_new_game     = -1
      cmd_new_game_plus = -1
      cmd_options      = -1
      cmd_language     = -1
      cmd_mystery_gift = -1
      cmd_debug        = -1
      cmd_quit         = -1
      cmd_doc          = -1
      cmd_discord      = -1
      cmd_pifdiscord   = -1
      cmd_wiki         = -1

      show_continue = !@save_data.empty?
      new_game_plus = show_continue && ((@save_data[:player].new_game_plus_unlocked rescue false) || $DEBUG)

      # ── Build commands — Multiplayer first ──────────────────────────────
      commands[cmd_multiplayer = commands.length] = _INTL('Multiplayer')

      if show_continue
        commands[cmd_continue = commands.length] = "#{@selected_file}"
        commands[cmd_mystery_gift = commands.length] = _INTL('Mystery Gift')
      end
      commands[cmd_new_game = commands.length] = _INTL('New Game')
      if new_game_plus
        commands[cmd_new_game_plus = commands.length] = _INTL('New Game +')
      end
      commands[cmd_options = commands.length]    = _INTL('Options')
      commands[cmd_discord = commands.length]    = _INTL('KIF Discord')
      commands[cmd_doc = commands.length]        = _INTL('KIF Documentation (Obsolete)')
      commands[cmd_pifdiscord = commands.length] = _INTL('PIF Discord')
      commands[cmd_wiki = commands.length]       = _INTL('Wiki')
      commands[cmd_language = commands.length]   = _INTL('Language') if Settings::LANGUAGES.length >= 2
      commands[cmd_debug = commands.length]      = _INTL('Debug') if $DEBUG
      commands[cmd_quit = commands.length]       = _INTL('Quit Game')
      cmd_left = -3
      cmd_right = -2

      map_id = show_continue ? (@save_data[:map_factory].map.map_id rescue 0) : 0
      @scene.pbStartScene(commands, show_continue, @save_data[:player],
                          @save_data[:frame_count] || 0, map_id, cmd_continue)
      @scene.pbSetParty(@save_data[:player]) if show_continue
      if first_time
        @scene.pbStartScene2
        first_time = false
      else
        @scene.pbUpdate
      end

      # Default selection: Continue if save exists, else New Game
      default_idx = show_continue ? cmd_continue : cmd_new_game
      sprites = @scene.instance_variable_get(:@sprites)
      if sprites && sprites["cmdwindow"]
        sprites["cmdwindow"].commands = commands
        sprites["cmdwindow"].index = default_idx
        commands.length.times do |i|
          panel = sprites["panel#{i}"]
          next unless panel
          panel.selected = (i == default_idx)
          panel.pbRefresh
        end
      end

      loop do
        # ── Inner loop: command selection ──────────────────────────────────
        command = @scene.pbChoose(commands, cmd_continue)
        pbPlayDecisionSE if command != cmd_quit

        case command
        when cmd_multiplayer
          result = TitleMultiplayer.open_menu
          if TitleMultiplayer.pending_ip
            if show_continue
              @scene.pbEndScene
              Game.load(@save_data)
              $game_switches[SWITCH_V5_1] = true rescue nil
              ensureCorrectDifficulty() rescue nil
              setGameMode() rescue nil
              $PokemonGlobal.alt_sprite_substitutions = {} if !$PokemonGlobal.alt_sprite_substitutions rescue nil
              $PokemonGlobal.autogen_sprites_cache = {} rescue nil
              return
            else
              @scene.pbEndScene
              Game.start_new
              $PokemonGlobal.alt_sprite_substitutions = {} if !$PokemonGlobal.alt_sprite_substitutions rescue nil
              return
            end
          end
          # :back — stay in menu
        when cmd_continue
          @scene.pbEndScene
          Game.load(@save_data)
          $game_switches[SWITCH_V5_1] = true rescue nil
          ensureCorrectDifficulty() rescue nil
          setGameMode() rescue nil
          $PokemonGlobal.alt_sprite_substitutions = {} if !$PokemonGlobal.alt_sprite_substitutions rescue nil
          $PokemonGlobal.autogen_sprites_cache = {} rescue nil
          return
        when cmd_new_game
          @scene.pbEndScene
          Game.start_new
          $PokemonGlobal.alt_sprite_substitutions = {} if !$PokemonGlobal.alt_sprite_substitutions rescue nil
          return
        when cmd_new_game_plus
          @scene.pbEndScene
          Game.start_new(@save_data[:bag], @save_data[:storage_system], @save_data[:player])
          @save_data[:player].new_game_plus_unlocked = true
          return
        when cmd_pifdiscord
          openUrlInBrowser(Settings::PIF_DISCORD_URL) rescue nil
        when cmd_wiki
          openUrlInBrowser(Settings::WIKI_URL) rescue nil
        when cmd_doc
          openUrlInBrowser("https://docs.google.com/document/d/1O6pKKL62dbLcapO0c2zDG2UI-eN6uatYlt_0GSk1dbE") rescue nil
          return
        when cmd_discord
          openUrlInBrowser(Settings::DISCORD_URL) rescue nil
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
        when cmd_quit
          pbPlayCloseMenuSE
          @scene.pbEndScene
          $scene = nil
          return
        when cmd_left
          @scene.pbCloseScene
          @selected_file = SaveData.get_prev_slot(save_file_list, @selected_file)
          break # to outer loop
        when cmd_right
          @scene.pbCloseScene
          @selected_file = SaveData.get_next_slot(save_file_list, @selected_file)
          break # to outer loop
        else
          pbPlayBuzzerSE
        end
      end
    end
  end
end

#===============================================================================
# Auto-connect hook
#===============================================================================
alias _kif_mp_orig_onLoadExistingGame onLoadExistingGame
def onLoadExistingGame
  _kif_mp_orig_onLoadExistingGame
  TitleMultiplayer._auto_connect_if_pending
end

alias _kif_mp_orig_onStartingNewGame onStartingNewGame
def onStartingNewGame
  _kif_mp_orig_onStartingNewGame
  TitleMultiplayer._auto_connect_if_pending
end
