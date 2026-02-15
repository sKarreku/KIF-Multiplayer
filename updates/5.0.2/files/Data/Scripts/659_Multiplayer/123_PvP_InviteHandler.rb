# ===========================================
# File: 123_PvP_InviteHandler.rb
# Purpose: Handle PvP battle invitations
# Phase: 2 - Invitation acceptance/decline with stub settings screen
# ===========================================

module PvPInviteHandler
  def self.tick
    # Process all pending PvP events
    while MultiplayerClient.pvp_events_pending?
      ev = MultiplayerClient.next_pvp_event
      next unless ev

      if ev[:type] == :invite
        # Invitation received
        from_sid = ev[:data][:from_sid].to_s
        from_name = ev[:data][:from_name].to_s
        label = (from_name && from_name != "" ? from_name : from_sid)

        # Check if invitation has expired (60 second timeout)
        if ev[:timestamp] && (Time.now - ev[:timestamp]) > 60
          ##MultiplayerDebug.info("PVP-INVITE", "Invite from #{from_sid} expired") if defined?(MultiplayerDebug)
          next
        end

        # Show accept/decline dialog
        if pbConfirmMessage(_INTL("{1} wants to battle!\nDo you accept?", label))
          # User accepted
          MultiplayerClient.pvp_accept(from_sid)
          PvPBattleState.create_session(is_initiator: false, opponent_sid: from_sid, opponent_name: from_name)

          # Open settings screen as receiver
          if defined?(Scene_PvPSettings)
            scene = Scene_PvPSettings.new(false, from_name)
            scene.main
          else
            pbMessage(_INTL("PvP settings screen not loaded!"))
            PvPBattleState.reset()
            MultiplayerClient.clear_pvp_state()
          end
        else
          # User declined
          MultiplayerClient.pvp_decline(from_sid)
        end

      elsif ev[:type] == :accepted
        # Opponent accepted our invitation
        from_sid = ev[:data][:from_sid].to_s

        # Get opponent name (we need to track this better, but for now use sid)
        opponent_name = from_sid

        # Create session as initiator
        PvPBattleState.create_session(is_initiator: true, opponent_sid: from_sid, opponent_name: opponent_name)

        # Open settings screen as initiator
        if defined?(Scene_PvPSettings)
          scene = Scene_PvPSettings.new(true, opponent_name)
          scene.main
        else
          pbMessage(_INTL("PvP settings screen not loaded!"))
          PvPBattleState.reset()
          MultiplayerClient.clear_pvp_state()
        end

      elsif ev[:type] == :declined
        # Opponent declined our invitation
        # Already handled by toast notification in 002_Client.rb
        # Just clean up any state
        PvPBattleState.reset() if defined?(PvPBattleState)
        MultiplayerClient.clear_pvp_state()
      end
    end
  end
end

# Hook into main game loop to process invitations
# This needs to be called regularly to process incoming invitations
class Scene_Map
  unless defined?(pvp_original_update)
    alias pvp_original_update update
  end

  def update
    pvp_original_update

    # Process PvP invitations if handler is available
    if defined?(PvPInviteHandler)
      begin
        PvPInviteHandler.tick
      rescue => e
        ##MultiplayerDebug.error("PVP-HANDLER", "Error in PvP invite handler: #{e.message}") if defined?(MultiplayerDebug)
      end
    end
  end
end

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("PVP-HANDLER", "PvP invitation handler loaded")
end
