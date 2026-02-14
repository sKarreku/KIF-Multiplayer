#===============================================================================
# STABILITY MODULE 6: (DEPRECATED — merged into 910_UnifiedSync.rb)
#===============================================================================
# All sync timeout/wait logic is now in 910_UnifiedSync.rb which loads last
# and does a clean method override with no alias chains.
#
# This file is intentionally empty.
#===============================================================================

#===============================================================================
# Pending invite handling note (kept for reference)
#===============================================================================
# The invite is handled by:
#   - 905_InvitePolling.rb (Events.onMapUpdate) - processes invites every frame
#   - Line 698 of 017_Coop_WildHook_v2.rb - checks pending invites at top of
#     pbBattleOnStepTaken BEFORE the encounter guard would block
#   - Line 742 simultaneous initiator check - defers if invite arrived mid-flow
#===============================================================================
