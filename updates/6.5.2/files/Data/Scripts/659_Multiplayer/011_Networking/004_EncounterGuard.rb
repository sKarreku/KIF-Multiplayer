#===============================================================================
# STABILITY MODULE 1: Encounter Guard System
#===============================================================================
# Prevents spurious wild encounters during the coop battle lifecycle:
#   - Party wait, sync screen, GO wait, actual battle, post-battle cooldown
# Also suppresses encounters at x5 speed flooding the system.
#
# How it works:
#   CoopEncounterGuard.suppress!   → block all encounters
#   CoopEncounterGuard.unsuppress! → unblock, start cooldown timer
#   CoopEncounterGuard.suppressed? → true while blocked OR during cooldown
#
# Integration points (patched into 017_Coop_WildHook_v2.rb below):
#   - Top of pbBattleOnStepTaken: early return if suppressed
#   - Before party wait: suppress!
#   - In _handle_coop_battle_join: suppress!
#   - ensure blocks (both initiator + joiner): unsuppress!
#===============================================================================

module CoopEncounterGuard
  COOLDOWN_SECONDS = 3  # After battle ends, block encounters for 3s

  @suppressed    = false
  @cooldown_until = nil

  def self.suppress!
    @suppressed = true
    StabilityDebug.info("ENC-GUARD", "Encounters SUPPRESSED") if defined?(StabilityDebug)
  end

  def self.unsuppress!
    @suppressed = false
    @cooldown_until = Time.now + COOLDOWN_SECONDS
    StabilityDebug.info("ENC-GUARD", "Encounters UNSUPPRESSED - cooldown #{COOLDOWN_SECONDS}s until #{@cooldown_until.strftime('%H:%M:%S')}") if defined?(StabilityDebug)
  end

  def self.suppressed?
    return true if @suppressed
    if @cooldown_until && Time.now < @cooldown_until
      return true
    end
    false
  end

  def self.reset!
    @suppressed = false
    @cooldown_until = nil
    StabilityDebug.info("ENC-GUARD", "Guard RESET (full clear)") if defined?(StabilityDebug)
  end

  def self.status
    if @suppressed
      "SUPPRESSED"
    elsif @cooldown_until && Time.now < @cooldown_until
      remaining = (@cooldown_until - Time.now).round(1)
      "COOLDOWN (#{remaining}s left)"
    else
      "OPEN"
    end
  end
end

#===============================================================================
# Patch pbBattleOnStepTaken - inject guard as FIRST check
#===============================================================================
if defined?(pbBattleOnStepTaken)
  # Only patch if not already patched by this module
  unless defined?($__encounter_guard_patched)
    $__encounter_guard_patched = true

    alias pbBattleOnStepTaken_before_guard pbBattleOnStepTaken

    def pbBattleOnStepTaken(repel_active)
      # ENCOUNTER GUARD: block ALL encounters during coop lifecycle or cooldown
      if defined?(CoopEncounterGuard) && CoopEncounterGuard.suppressed?
        StabilityDebug.info("ENC-GUARD", "Blocked encounter (#{CoopEncounterGuard.status})") if defined?(StabilityDebug)
        return
      end

      pbBattleOnStepTaken_before_guard(repel_active)
    end

    StabilityDebug.info("ENC-GUARD", "Patched pbBattleOnStepTaken with encounter guard") if defined?(StabilityDebug)
  end
end

#===============================================================================
# Patch CoopWildHook lifecycle points - suppress/unsuppress
#===============================================================================
if defined?(CoopWildHook)
  class << CoopWildHook
    # Patch _handle_coop_battle_join (non-initiator join)
    if method_defined?(:_handle_coop_battle_join)
      alias _handle_coop_battle_join_before_guard _handle_coop_battle_join

      def _handle_coop_battle_join(invite)
        CoopEncounterGuard.suppress! if defined?(CoopEncounterGuard)
        begin
          _handle_coop_battle_join_before_guard(invite)
        ensure
          CoopEncounterGuard.unsuppress! if defined?(CoopEncounterGuard)
        end
      end

      StabilityDebug.info("ENC-GUARD", "Patched _handle_coop_battle_join with suppress/unsuppress") if defined?(StabilityDebug)
    end
  end
end

#===============================================================================
# Patch the initiator path in pbBattleOnStepTaken
# We need to suppress BEFORE the party wait (line ~776) and unsuppress in ensure.
# Since the main function is a monolith, we inject via the re-entrancy guard:
# When coop_ok=true and allies found, we suppress. The ensure block unsuppress.
#
# Strategy: Override the already-aliased function to add suppress around the
# coop-specific path. We detect the coop path by checking if we got past
# the "No eligible allies" check.
#===============================================================================
# Note: The 017 file's ensure block already runs on exit. We hook into
# Events.onStartBattle / Events.onEndBattle as a safety net.
unless defined?($__encounter_guard_battle_events)
  $__encounter_guard_battle_events = true

  if defined?(Events)
    # Suppress on ANY battle start (safety net)
    Events.onStartBattle += proc { |_s, _|
      CoopEncounterGuard.suppress! if defined?(CoopEncounterGuard)
    }

    # Unsuppress on ANY battle end (with cooldown)
    if Events.respond_to?(:onEndBattle)
      Events.onEndBattle += proc { |_s, _|
        CoopEncounterGuard.unsuppress! if defined?(CoopEncounterGuard)
      }
    end

    StabilityDebug.info("ENC-GUARD", "Installed Events.onStartBattle/onEndBattle suppress hooks") if defined?(StabilityDebug)
  end
end

StabilityDebug.info("ENC-GUARD", "Module 901_EncounterGuard loaded") if defined?(StabilityDebug)
