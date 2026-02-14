#===============================================================================
# FIX: Pokemon status serialization
#===============================================================================
# The base as_json calls `heal_status` (a method that CURES the Pokemon)
# instead of reading @status. This means every serialization (party snapshots,
# battle invites) silently wipes all status conditions.
#
# This patch:
#   1. Overrides as_json to include @status/@statusCount as data
#   2. Overrides load_json to restore them
#===============================================================================

class Pokemon
  alias _mp_status_as_json as_json
  def as_json(*options)
    # Save status before the original as_json (which calls heal_status, wiping it)
    saved_status      = @status
    saved_statusCount = @statusCount
    data = _mp_status_as_json(*options)
    # Restore status that was wiped by the heal_status call
    @status      = saved_status
    @statusCount = saved_statusCount
    # Replace the broken key with actual status data
    data.delete('heal_status')
    data['status']      = @status
    data['statusCount'] = @statusCount
    data
  end

  alias _mp_status_load_json load_json
  def load_json(jsonparse, jsonfile = nil, forcereadonly = false)
    _mp_status_load_json(jsonparse, jsonfile, forcereadonly)
    # Restore status fields (base load_json ignores them)
    @status      = jsonparse['status'] || :NONE
    @statusCount = jsonparse['statusCount'] || 0
  end
end

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("STATUS-FIX", "909_StatusSerialize.rb loaded - status preserved during serialization")
end
