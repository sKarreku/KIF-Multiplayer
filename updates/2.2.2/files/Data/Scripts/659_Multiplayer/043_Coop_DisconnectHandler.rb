# ===========================================
# File: 043_Coop_DisconnectHandler.rb
# Purpose: Detect and handle player disconnects during coop battles
# Notes: Hooks into pbEndOfRoundPhase to check if any allied players have disconnected
#        Shows "Player X Disconnected" message and ends the battle immediately
# ===========================================

##MultiplayerDebug.info("COOP-DC", "Loading coop battle disconnect handler...")

class PokeBattle_Battle
  alias coop_disconnect_pbEndOfRoundPhase pbEndOfRoundPhase

  def pbEndOfRoundPhase
    # Check for disconnects before phase executes
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      check_coop_disconnects
    end
    coop_disconnect_pbEndOfRoundPhase
  end

  def check_coop_disconnects
    begin
      # Get allied player SIDs from CoopBattleState
      battle_id = CoopBattleState.battle_id rescue nil
      return unless battle_id

      # Get expected allied player SIDs
      allied_sids = CoopBattleState.get_allied_player_sids rescue []
      return if allied_sids.empty?

      # Check if any allied players are missing from MultiplayerClient.players
      disconnected = []
      allied_sids.each do |sid|
        unless MultiplayerClient.players.key?(sid.to_s)
          # Player disconnected
          player_info = CoopBattleState.get_player_info(sid) rescue nil
          player_name = player_info ? player_info[:name] : "Player #{sid}"
          disconnected << { sid: sid, name: player_name }
        end
      end

      # If any players disconnected, end the battle
      unless disconnected.empty?
        ##MultiplayerDebug.warn("COOP-DC", "Detected #{disconnected.length} disconnected player(s) in coop battle #{battle_id}")

        disconnected.each do |dc|
          ##MultiplayerDebug.info("COOP-DC", "  Disconnected: #{dc[:name]} (#{dc[:sid]})")

          # Show bordered message to player
          begin
            pbDisplayPaused(_INTL("Player {1} Disconnected", dc[:name]))
          rescue => e
            ##MultiplayerDebug.warn("COOP-DC", "Failed to show disconnect message: #{e.message}")
            begin
              pbMessage(_INTL("Player {1} Disconnected", dc[:name]))
            rescue; end
          end
        end

        # End the battle immediately
        ##MultiplayerDebug.info("COOP-DC", "Ending coop battle #{battle_id} due to disconnect(s)")
        @decision = 3  # Ran away decision (avoids whiteout behavior)

        # Notify CoopBattleState that the battle has ended due to disconnect
        begin
          CoopBattleState.mark_battle_ended_by_disconnect(battle_id) if CoopBattleState.respond_to?(:mark_battle_ended_by_disconnect)
        rescue => e
          ##MultiplayerDebug.warn("COOP-DC", "Failed to mark battle as ended by disconnect: #{e.message}")
        end
      end
    rescue => e
      ##MultiplayerDebug.error("COOP-DC", "Error in check_coop_disconnects: #{e.class}: #{e.message}")
      ##MultiplayerDebug.error("COOP-DC", "  #{(e.backtrace || [])[0, 5].join(' | ')}")
    end
  end
end

##MultiplayerDebug.info("COOP-DC", "Coop battle disconnect handler loaded successfully.")
