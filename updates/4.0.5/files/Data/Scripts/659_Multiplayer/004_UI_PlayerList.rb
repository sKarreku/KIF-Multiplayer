# ===========================================
# File: 004_UI_PlayerList.rb
# Purpose: Adds "Player List" option under Outfit in pause menu (scene hook)
# Works with KIF’s PokemonPauseMenu_Scene#pbShowCommands
# Fixed: no index shifting (doesn't mutate caller's array)
# Adds: "Request Trade" action per player
# ===========================================

##MultiplayerDebug.info("UI-PLAYER", "Player List hook (Scene level) loaded.")

module MultiplayerUI
  # ===========================================
  # === Parsing Helpers
  # ===========================================
  # Expected format from server: "SIDx - Name"
  def self.parse_player_entry(entry)
    return [nil, nil] if entry.nil?
    s = entry.to_s
    if s.include?(" - ")
      sid, name = s.split(" - ", 2)
    else
      parts = s.split(" ", 2)
      sid   = parts[0]
      name  = (parts[1] || "")
    end
    sid = sid && sid.strip
    name = name ? name.strip : ""
    [sid, name]
  end

  # Build a display list without mutating the original commands.
  # Returns [display_commands, inserted_indices]
  def self.build_playerlist_display(orig_cmds)
    display = orig_cmds.dup
    inserted = []
    begin
      return [display, inserted] unless MultiplayerClient.instance_variable_get(:@connected)
      oi = display.index(_INTL("Outfit"))
      return [display, inserted] if oi.nil?
      return [display, inserted] if display.include?(_INTL("Player List"))
      insert_pos = oi + 1
      display = display.dup
      display.insert(insert_pos, _INTL("Player List"))
      inserted << insert_pos
      ##MultiplayerDebug.info("UI-PL-INJ", "Prepared Player List injection at #{insert_pos} (no mutation).")
    rescue => e
      ##MultiplayerDebug.error("UI-PL-INJ-ERR", "Injection prep failed: #{e.message}")
    end
    [display, inserted]
  end

  # ===========================================
  # === Hook: Scene Level (pbShowCommands)
  # ===========================================
  if defined?(PokemonPauseMenu_Scene)
    class ::PokemonPauseMenu_Scene
      alias kif_pl_pbShowCommands pbShowCommands unless method_defined?(:kif_pl_pbShowCommands)

      def pbShowCommands(commands)
        # Build a separate display list and keep original intact
        display, inserted = MultiplayerUI.build_playerlist_display(commands)
        ##MultiplayerDebug.info("UI-PL-HOOK", "pbShowCommands hooked; orig=#{commands.length}, disp=#{display.length}")

        # Call original with our display list
        ret_disp = kif_pl_pbShowCommands(display)

        # If canceled or invalid
        return ret_disp if ret_disp.nil? || ret_disp < 0

        # If user picked our injected command, handle and consume it
        if inserted.include?(ret_disp) && display[ret_disp] == _INTL("Player List")
          begin
            ##MultiplayerDebug.info("UI-PL-ACT", "Player List selected from menu.")
            MultiplayerUI.openPlayerList
          rescue => e
            ##MultiplayerDebug.error("UI-PL-SELERR", "Player List open failed: #{e.message}")
          end
          return -1  # consume; return to menu
        end

        # Map display index back to the original index by subtracting
        # how many injected items occurred before the selection.
        shift = inserted.count { |i| i < ret_disp }
        ret_orig = ret_disp - shift
        return ret_orig
      end
    end
    ##MultiplayerDebug.info("UI-PL-OK", "Hooked PokemonPauseMenu_Scene.pbShowCommands (Player List, no-shift).")
  else
    ##MultiplayerDebug.error("UI-PL-NOCLASS", "PokemonPauseMenu_Scene not found — Player List hook failed.")
  end

  # ===========================================
  # === Open Player List Scene (fullscreen, safe)
  # ===========================================
  def self.openPlayerList
    unless MultiplayerClient.instance_variable_get(:@connected)
      pbMessage(_INTL("You are not connected to any server."))
      ##MultiplayerDebug.warn("UI-PL04", "Attempted to open Player List while disconnected.")
      return
    end

    # Set flag to prevent multiple windows
    MultiplayerUI.instance_variable_set(:@playerlist_open, true)
    MultiplayerUI.instance_variable_set(:@playerlist_close_requested, false)

    begin
      ##MultiplayerDebug.info("UI-PL05", "Requesting player list from server...")
      MultiplayerClient.send_data("REQ_PLAYERS")

      # --- Viewport setup ---
      viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      viewport.z = 99999  # Match standard Pokemon Essentials UI z-index

      # Background (semi-transparent)
      bg = Sprite.new(viewport)
      bg.bitmap = Bitmap.new(Graphics.width, Graphics.height)
      bg.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 160))

      # Centered loading window (manual) - wider to accommodate progress percentage
      loading = Window_UnformattedTextPokemon.newWithSize(
        _INTL("Loading player list... 0%"), 0, 0, Graphics.width - 64, 64, viewport
      )
      loading.x = (Graphics.width - loading.width) / 2
      loading.y = (Graphics.height - loading.height) / 2

      start_time = Time.now
      timeout_seconds = 3.0
      players = nil

      # --- Non-blocking wait with progress bar (real-time based, independent of game speed) ---
      while Time.now - start_time < timeout_seconds
        Graphics.update
        Input.update

        # Update loading progress bar (visual feedback)
        elapsed = Time.now - start_time
        progress = (elapsed / timeout_seconds * 100).to_i
        loading.text = _INTL("Loading player list... {1}%", progress)

        players = MultiplayerClient.instance_variable_get(:@player_list)
        break if players && players.any?
      end
      # Final quick recheck
      if (!players || players.empty?) && MultiplayerClient.instance_variable_get(:@player_list)
        players = MultiplayerClient.instance_variable_get(:@player_list)
      end
      loading.dispose if !loading.disposed?

      if !players || players.empty?
        pbSEPlay("GUI menu close")
        bg.dispose if !bg.disposed?
        viewport.dispose if !viewport.disposed?
        pbMessage(_INTL("No player data received from server."))
        ##MultiplayerDebug.warn("UI-PL07", "No player list received or timed out.")
        return
      end

      # --- Scroll window ---
      cmds = players.map { |p| _INTL("{1}", p) }
      win = Window_CommandPokemon.new(cmds)
      win.viewport = viewport
      win.width  = Graphics.width - 32
      win.height = Graphics.height - 32
      win.x = 16
      win.y = 16
      win.opacity = 210
      win.index = 0

      # --- Main loop ---
      loop do
        Graphics.update
        Input.update
        win.update

        # Check for F3 close request
        if MultiplayerUI.instance_variable_get(:@playerlist_close_requested)
          ##MultiplayerDebug.info("UI-PL-F3CLOSE", "F3 close request detected")
          MultiplayerUI.instance_variable_set(:@playerlist_close_requested, false)
          pbSEPlay("GUI menu close")
          break
        end

        if Input.trigger?(Input::BACK)
          pbSEPlay("GUI menu close")
          break
        elsif Input.trigger?(Input::USE)
          sel = win.index
          chosen_line = cmds[sel]
          pbSEPlay("GUI select")

          sid, name = MultiplayerUI.parse_player_entry(chosen_line)
          if sid.nil? || sid.empty?
            pbMessage(_INTL("Invalid player entry."))
            next
          end

          my_sid = MultiplayerClient.session_id rescue nil
          if my_sid && sid == my_sid
            pbMessage(_INTL("You cannot select yourself."))
            next
          end

          # Build per-player actions
          actions = [_INTL("Invite to Squad"), _INTL("Let's Battle!"), _INTL("Request Trade"), _INTL("Cancel")]
          act = pbMessage(_INTL("Player: {1}", name), actions, 0)

          case act
          when 0
            begin
              sq = MultiplayerClient.squad
              if sq && sq[:members].is_a?(Array) && sq[:members].length >= 3
                pbMessage(_INTL("Your squad is full."))
              else
                MultiplayerClient.invite_player(sid)
                pbMessage(_INTL("Invite sent to {1}.", name))
                ##MultiplayerDebug.info("UI-PL-INV", "Invited #{sid} (#{name}) to squad.")
              end
            rescue => e
              ##MultiplayerDebug.error("UI-PL-INV-ERR", "Error sending squad invite: #{e.message}")
              pbMessage(_INTL("Failed to send invite."))
            end

          when 1
            # Let's Battle!
            begin
              if defined?(PvPBattleState) && defined?(MultiplayerClient.pvp_active?) && MultiplayerClient.pvp_active?
                pbMessage(_INTL("You are already in a PvP battle setup."))
              elsif MultiplayerClient.trade_active?
                pbMessage(_INTL("You are currently trading."))
              elsif defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
                pbMessage(_INTL("You are currently in a coop battle."))
              else
                MultiplayerClient.pvp_invite(sid)
                pbMessage(_INTL("Battle request sent to {1}.", name))
              end
            rescue => e
              ##MultiplayerDebug.error("UI-PL-PVP-ERR", "Error sending battle request: #{e.message}") if defined?(MultiplayerDebug)
              pbMessage(_INTL("Failed to send battle request."))
            end

          when 2
            # Request Trade
            begin
              # Optional: prevent starting a new trade if already trading
              if MultiplayerClient.trade_active?
                pbMessage(_INTL("You are already in a trade."))
              else
                MultiplayerClient.trade_invite(sid)
                pbMessage(_INTL("Trade request sent to {1}.", name))
                ##MultiplayerDebug.info("UI-PL-TRQ", "Trade request sent to #{sid} (#{name}).")
              end
            rescue => e
              ##MultiplayerDebug.error("UI-PL-TRQ-ERR", "Error sending trade request: #{e.message}")
              pbMessage(_INTL("Failed to send trade request."))
            end
          end
        end
      end

      # --- Cleanup ---
      win.dispose if !win.disposed?
      bg.dispose if !bg.disposed?
      viewport.dispose if !viewport.disposed?
      Graphics.update  # Force graphics refresh
      ##MultiplayerDebug.info("UI-PL-END", "Closed Player List window normally.")

    rescue Exception => e
      ##MultiplayerDebug.error("UI-PL-CRASH", "Exception in PlayerList: #{e.class} - #{e.message}")
      begin
        loading.dispose if loading && !loading.disposed?
        bg.dispose if bg && !bg.disposed?
        viewport.dispose if viewport && !viewport.disposed?
        Graphics.update  # Force graphics refresh even on error
      rescue; end
      pbMessage(_INTL("Player List encountered an error and was closed."))
    ensure
      # Always clear flag when window closes
      MultiplayerUI.instance_variable_set(:@playerlist_open, false)
    end
  end
end
