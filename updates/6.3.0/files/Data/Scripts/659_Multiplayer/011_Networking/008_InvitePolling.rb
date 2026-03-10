#===============================================================================
# STABILITY MODULE 5: Battle Invite Polling Outside Encounter Hook
#===============================================================================
# Problem: Non-initiators only process battle invites when they step in grass
#          (pbBattleOnStepTaken). If they're on a path, they miss the invite
#          entirely and timeout after 30s.
#
# Solution: Hook Events.onMapUpdate to poll for pending invites every frame.
#           This fires during the normal overworld loop, independent of
#           encounter triggers.
#===============================================================================

unless defined?($__invite_polling_installed)
  $__invite_polling_installed = true

  if defined?(Events) && Events.respond_to?(:onMapUpdate)
    Events.onMapUpdate += proc { |_sender, _e|
      # Skip if not connected or not in a squad
      next unless defined?(MultiplayerClient)
      next unless MultiplayerClient.instance_variable_get(:@connected) rescue false
      next unless MultiplayerClient.respond_to?(:in_squad?) && MultiplayerClient.in_squad?

      # NOTE: Do NOT check CoopEncounterGuard.suppressed? here!
      # Invite processing must always work - the guard only blocks wild encounters.

      # Skip if wild hook is already running (re-entrancy guard)
      next if $__coop_wild_hook_v2_running

      # Skip if already in a battle transaction
      next if defined?(CoopBattleTransaction) && CoopBattleTransaction.active?

      # Skip if already in an active coop battle
      next if defined?(CoopBattleState) && CoopBattleState.active?

      # Check for pending invite
      if MultiplayerClient.respond_to?(:coop_battle_pending?) && MultiplayerClient.coop_battle_pending?
        invite = MultiplayerClient.dequeue_coop_battle rescue nil
        if invite
          StabilityDebug.info("INVITE-POLL", "Picked up invite from #{invite[:from_sid]} via onMapUpdate polling") if defined?(StabilityDebug)

          $__coop_wild_hook_v2_running = true
          begin
            CoopWildHook._handle_coop_battle_join(invite) if defined?(CoopWildHook)
          rescue => e
            StabilityDebug.error("INVITE-POLL", "Join failed: #{e.class}: #{e.message}") if defined?(StabilityDebug)
          ensure
            $__coop_wild_hook_v2_running = false
          end
        end
      end
    }

    StabilityDebug.info("INVITE-POLL", "Installed Events.onMapUpdate invite polling hook") if defined?(StabilityDebug)
  else
    StabilityDebug.warn("INVITE-POLL", "Events.onMapUpdate not available - invite polling disabled") if defined?(StabilityDebug)
  end
end

StabilityDebug.info("INVITE-POLL", "Module 905_InvitePolling loaded") if defined?(StabilityDebug)
