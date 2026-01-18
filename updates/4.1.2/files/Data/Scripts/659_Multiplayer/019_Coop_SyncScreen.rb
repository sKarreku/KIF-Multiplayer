# ===========================================
# File: 019_Coop_SyncScreen.rb
# Purpose: Visual HUD for co-op battle synchronization
# Notes : Shows which allies have joined the battle
#         Initiator waits here before battle starts
# ===========================================

##MultiplayerDebug.info("COOP-SYNC", "Loading co-op sync screen...")

class CoopBattleSyncScreen
  TIMEOUT_SECONDS = 30

  def initialize(viewport, expected_allies)
    @viewport = viewport
    @expected_allies = expected_allies  # [{ sid:, name: }, ...]
    @sprites = {}
    @start_time = Time.now
    @disposed = false

    create_sprites
    update_status
  end

  def create_sprites
    # Background box (semi-transparent black)
    @sprites[:bg] = Sprite.new(@viewport)
    @sprites[:bg].bitmap = Bitmap.new(320, 240)
    @sprites[:bg].bitmap.fill_rect(0, 0, 320, 240, Color.new(0, 0, 0, 180))
    @sprites[:bg].x = 10
    @sprites[:bg].y = 10
    @sprites[:bg].z = 99998

    # Border (white)
    draw_border(@sprites[:bg].bitmap, 0, 0, 320, 240, Color.new(255, 255, 255))

    # Title text
    @sprites[:title] = Sprite.new(@viewport)
    @sprites[:title].bitmap = Bitmap.new(300, 32)
    @sprites[:title].bitmap.font.bold = true
    @sprites[:title].bitmap.font.size = 24
    @sprites[:title].bitmap.draw_text(0, 0, 300, 32, "Battle Synchronization", 1)
    @sprites[:title].x = 20
    @sprites[:title].y = 20
    @sprites[:title].z = 99999

    # Status text (waiting message)
    @sprites[:status] = Sprite.new(@viewport)
    @sprites[:status].bitmap = Bitmap.new(300, 32)
    @sprites[:status].bitmap.font.size = 18
    @sprites[:status].bitmap.font.color = Color.new(200, 200, 200)
    @sprites[:status].bitmap.draw_text(0, 0, 300, 32, "Waiting for squadmates...", 0)
    @sprites[:status].x = 20
    @sprites[:status].y = 55
    @sprites[:status].z = 99999

    # Player status list (one sprite per ally)
    @expected_allies.each_with_index do |ally, i|
      key = "player_#{i}".to_sym
      @sprites[key] = Sprite.new(@viewport)
      @sprites[key].bitmap = Bitmap.new(300, 24)
      @sprites[key].bitmap.font.size = 18
      @sprites[key].x = 30
      @sprites[key].y = 90 + (i * 30)
      @sprites[key].z = 99999
    end

    # Timeout counter
    @sprites[:timeout] = Sprite.new(@viewport)
    @sprites[:timeout].bitmap = Bitmap.new(300, 24)
    @sprites[:timeout].bitmap.font.size = 16
    @sprites[:timeout].bitmap.font.color = Color.new(255, 200, 0)
    @sprites[:timeout].x = 20
    @sprites[:timeout].y = 90 + (@expected_allies.length * 30) + 10
    @sprites[:timeout].z = 99999
  end

  def draw_border(bitmap, x, y, width, height, color)
    # Top
    bitmap.fill_rect(x, y, width, 2, color)
    # Bottom
    bitmap.fill_rect(x, y + height - 2, width, 2, color)
    # Left
    bitmap.fill_rect(x, y, 2, height, color)
    # Right
    bitmap.fill_rect(x + width - 2, y, 2, height, color)
  end

  def update_status
    return if @disposed

    joined_sids = MultiplayerClient.joined_ally_sids

    # Update each player's status
    @expected_allies.each_with_index do |ally, i|
      key = "player_#{i}".to_sym
      sprite = @sprites[key]
      next unless sprite && sprite.bitmap

      sprite.bitmap.clear

      is_joined = joined_sids.include?(ally[:sid].to_s)
      status_text = is_joined ? "Synced ✓" : "Unsynced ✗"
      status_color = is_joined ? Color.new(0, 255, 0) : Color.new(255, 0, 0)

      # Draw player name
      sprite.bitmap.font.color = Color.new(255, 255, 255)
      sprite.bitmap.draw_text(0, 0, 200, 24, ally[:name].to_s, 0)

      # Draw status
      sprite.bitmap.font.color = status_color
      sprite.bitmap.draw_text(200, 0, 100, 24, status_text, 0)
    end

    # Update timeout counter
    elapsed = Time.now - @start_time
    remaining = [TIMEOUT_SECONDS - elapsed.to_i, 0].max
    @sprites[:timeout].bitmap.clear
    @sprites[:timeout].bitmap.draw_text(0, 0, 300, 24, "Timeout in #{remaining}s", 0)
  end

  def all_synced?
    joined_sids = MultiplayerClient.joined_ally_sids
    @expected_allies.all? { |ally| joined_sids.include?(ally[:sid].to_s) }
  end

  def timed_out?
    elapsed = Time.now - @start_time
    elapsed >= TIMEOUT_SECONDS
  end

  def update
    return if @disposed
    update_status
    Graphics.update
    Input.update
  end

  def dispose
    return if @disposed
    @disposed = true
    @sprites.each_value do |sprite|
      sprite.bitmap.dispose if sprite.bitmap
      sprite.dispose
    end
    @sprites.clear
    ##MultiplayerDebug.info("COOP-SYNC", "Sync screen disposed")
  end

  def disposed?
    @disposed
  end
end

# Wait for all allies to join the battle
# Returns true if all joined, false if timed out
def pbCoopWaitForAllies(expected_allies)
  return true if expected_allies.empty?

  ##MultiplayerDebug.info("COOP-SYNC", "Waiting for #{expected_allies.length} allies to join")
  MultiplayerClient.reset_battle_sync

  viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
  viewport.z = 99999  # Match standard Pokemon Essentials UI z-index

  sync_screen = CoopBattleSyncScreen.new(viewport, expected_allies)

  loop do
    sync_screen.update

    # Check if another player cancelled the battle
    if defined?(CoopBattleTransaction) && CoopBattleTransaction.cancelled?
      reason = CoopBattleTransaction.cancel_reason || "cancelled"
      if defined?(MultiplayerDebug)
        MultiplayerDebug.warn("COOP-SYNC", "Battle cancelled by remote player: #{reason}")
      end
      sync_screen.dispose
      viewport.dispose
      Graphics.update
      CoopBattleTransaction.reset
      return false
    end

    if sync_screen.all_synced?
      ##MultiplayerDebug.info("COOP-SYNC", "All allies synced!")
      sync_screen.dispose
      viewport.dispose
      Graphics.update  # Force graphics system refresh to clear corrupted z-layer state
      return true
    end

    if sync_screen.timed_out?
      ##MultiplayerDebug.warn("COOP-SYNC", "Sync timeout! Some allies didn't join")
      # Cancel transaction so other players know
      if defined?(CoopBattleTransaction)
        CoopBattleTransaction.cancel("timeout")
      end
      sync_screen.dispose
      viewport.dispose
      Graphics.update  # Force graphics system refresh to clear corrupted z-layer state
      return false
    end

    # Allow user to cancel with B button (fallback to vanilla)
    if Input.trigger?(Input::BACK)
      ##MultiplayerDebug.info("COOP-SYNC", "User cancelled sync wait")
      # Broadcast cancellation to all players
      if defined?(CoopBattleTransaction)
        CoopBattleTransaction.cancel("user_cancelled")
      end
      sync_screen.dispose
      viewport.dispose
      Graphics.update  # Force graphics system refresh to clear corrupted z-layer state
      return false
    end
  end
end

##MultiplayerDebug.info("COOP-SYNC", "Co-op sync screen loaded successfully.")
