# ===========================================
# File: 008_UI_DisconnectCleanup.rb
# Purpose: On server disconnect, notify player and purge remote sprites
# Hook: Scene_Map#update (no base edits)
# ===========================================

##MultiplayerDebug.info("UI-DC", "Disconnect cleanup hook loaded.")

if defined?(Scene_Map)
  class Scene_Map
    alias kif_dc_update update unless method_defined?(:kif_dc_update)

    def update
      kif_dc_update

      begin
        # MultiplayerClient.handle_connection_loss sets this flag.
        if defined?($multiplayer_disconnect_notice) && $multiplayer_disconnect_notice
          # Reset the latch first to avoid re-entrancy
          $multiplayer_disconnect_notice = false

          # 1) Tell the player (MAIN THREAD)
          begin
            pbMessage(_INTL("Server disconnected, switching back to Singleplayer."))
          rescue
            # Fallback to console if UI not available
            puts "[Multiplayer] Server disconnected, switching back to Singleplayer."
          end

          # 2) Purge all remote players so sprites/nametags vanish next frame
          begin
            if defined?(MultiplayerClient)
              # Clear live remote players hash -> Sprite manager will remove them cleanly
              MultiplayerClient.players.clear rescue nil

              # Optional: clear cached player list & squad state (purely cosmetic)
              MultiplayerClient.instance_variable_set(:@player_list, []) rescue nil
              MultiplayerClient.instance_variable_set(:@squad, nil) rescue nil
              ##MultiplayerDebug.info("UI-DC", "Cleared remote players and UI caches after disconnect.")
            end
          rescue => e
            ##MultiplayerDebug.warn("UI-DC", "Cleanup exception: #{e.message}")
          end
        end
      rescue => e
        ##MultiplayerDebug.error("UI-DC", "Update hook error: #{e.message}")
      end
    end
  end

  ##MultiplayerDebug.info("UI-DC", "Hooked Scene_Map#update for disconnect cleanup.")
else
  ##MultiplayerDebug.warn("UI-DC", "Scene_Map not defined — disconnect cleanup disabled.")
end
