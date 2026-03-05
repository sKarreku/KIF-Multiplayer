
# File: 005_PlayerSprites.rb
# Purpose: Display synced multiplayer characters on the map (hook version)
# No interpolation (snap-to-position) + outfit rendering
# ===========================================

##MultiplayerDebug.info("SPR-000", "Player sprite sync system loaded (snap version).")

# ===============================================================
# === Global Remote Trainer struct
# ===============================================================
::RemoteTrainer = Struct.new(
  :clothes, :hat, :hair,
  :skin_tone, :hair_color, :hat_color, :clothes_color
)
##MultiplayerDebug.info("SPR-INIT", "Global RemoteTrainer struct initialized.")

# -----------------------------------------------------------------
# === Remote Player Name Sprite
# -----------------------------------------------------------------
class Sprite_RemoteName < Sprite
  attr_reader :name
  attr_accessor :busy

  def initialize(viewport, name)
    super(viewport)
    @name = name
    @busy = false
    self.bitmap = Bitmap.new(160, 48)  # Increased height to fit VS indicator
    self.ox = 80
    self.oy = 56  # Adjusted offset for taller bitmap
    self.z = 999
    draw_name(@name)
  end

  def draw_name(name, busy = false)
    return if name.nil?
    name = name.to_s
    @name = name
    @busy = busy
    self.bitmap.clear

    # Draw name
    font = self.bitmap.font
    font.name = "Arial"
    font.size = 16
    # RGSS1 (XP) lacks outline, so fake a drop shadow
    shadow_color = Color.new(0, 0, 0, 160)
    text_color   = Color.new(255, 255, 255)
    self.bitmap.font.color = shadow_color
    self.bitmap.draw_text(1, 17, 160, 32, name, 1)  # Shifted down to make room for VS
    self.bitmap.font.color = text_color
    self.bitmap.draw_text(0, 16, 160, 32, name, 1)

    # Draw VS indicator if busy
    if @busy
      # VS badge styling
      font.size = 14
      font.bold = true
      vs_text = "VS"

      # Draw red background rectangle for VS badge
      vs_bg_color = Color.new(200, 0, 0, 180)  # Red with transparency
      vs_border_color = Color.new(255, 255, 255, 220)  # White border

      # Center the VS badge
      badge_width = 24
      badge_height = 16
      badge_x = (160 - badge_width) / 2
      badge_y = 0

      # Draw border
      self.bitmap.fill_rect(badge_x - 1, badge_y - 1, badge_width + 2, badge_height + 2, vs_border_color)
      # Draw background
      self.bitmap.fill_rect(badge_x, badge_y, badge_width, badge_height, vs_bg_color)

      # Draw VS text
      self.bitmap.font.color = Color.new(0, 0, 0, 200)  # Shadow
      self.bitmap.draw_text(badge_x + 1, badge_y + 1, badge_width, badge_height, vs_text, 1)
      self.bitmap.font.color = Color.new(255, 255, 255)  # White text
      self.bitmap.draw_text(badge_x, badge_y, badge_width, badge_height, vs_text, 1)
    end
  end

  def update_position(x, y)
    self.x = x
    self.y = y - 32
  end

  def dispose
    begin
      self.bitmap.dispose unless self.bitmap.nil? || self.bitmap.disposed?
    rescue => e
      ##MultiplayerDebug.warn("SPR-NAME-DISP", "Name bitmap dispose: #{e.message}")
    end
    super
  end
end

# -----------------------------------------------------------------
# === Remote Player Sprite
# -----------------------------------------------------------------
class Sprite_RemotePlayer < RPG::Sprite
  def initialize(viewport, sid, data)
    super(viewport)
    @sid = sid
    @viewport = viewport
    @name_sprite = Sprite_RemoteName.new(viewport, (data && data[:name]) || sid)
    @cw = @ch = 0
    @last_appearance = nil
    @last_x = @last_y = nil
    self.ox = 16
    self.oy = 32
    self.z = 0  # Will be calculated based on Y position
    self.visible = false
    @name_sprite.visible = false
    @owns_bitmap = false

    # Interpolation state
    @interp_state = nil
    @current_tile_pos = { x: 0, y: 0 }
    @target_tile_pos = { x: 0, y: 0 }

    # Movement state (surf, dive, bike, run, fish)
    @surf = false
    @dive = false
    @bike = false
    @run = false
    @fish = false

    # Surf/dive base sprite (like local player's Sprite_SurfBase)
    @surf_base = nil

    # Track if player is currently moving (for idle vs movement sprites)
    @is_moving = false

    # Create shadow sprite (same as local player)
    make_shadow
  end

  def make_shadow
    # Disable RPG::Sprite's built-in shadow to prevent double shadows
    @_shadow_sprite = nil

    @shadow.dispose if @shadow
    @shadow = nil
    begin
      @shadow = Sprite.new(@viewport)
      shadow_path = defined?(SHADOW_IMG_FOLDER) ? SHADOW_IMG_FOLDER : "Graphics/Characters/"
      shadow_name = defined?(SHADOW_IMG_NAME) ? SHADOW_IMG_NAME : "shadow"
      @shadow.bitmap = RPG::Cache.load_bitmap(shadow_path, shadow_name)
      @shadow.ox = @shadow.bitmap.width / 2.0
      @shadow.oy = @shadow.bitmap.height / 2.0
      @shadow.visible = false
      ##MultiplayerDebug.info("SPR-SHADOW", "Created shadow for #{@sid}")
    rescue => e
      ##MultiplayerDebug.warn("SPR-SHADOW", "Failed to create shadow for #{@sid}: #{e.message}")
      @shadow = nil
    end
  end

  def position_shadow
    return unless @shadow
    @shadow.x = self.x
    @shadow.y = self.y - 6
    @shadow.z = self.z - 1
    @shadow.opacity = self.opacity
    @shadow.visible = self.visible
  end

  def rebuild_signature(data)
    [
      data[:clothes], data[:clothes_color],
      data[:hat], data[:hat_color],
      data[:hair], data[:hair_color],
      data[:skin_tone]
    ].map { |v| v.nil? ? '∅' : v.to_s }.join('|')
  end

  def update_with_data(data)
    return unless data && data[:map] && data[:x] && data[:y]

    same_map = ($game_map.map_id == data[:map])
    self.visible = same_map
    @name_sprite.visible = same_map
    return unless same_map

    # --- Position update with interpolation ---
    new_tile_pos = { x: data[:x].to_i, y: data[:y].to_i }

    # Check if position changed
    if @target_tile_pos[:x] != new_tile_pos[:x] || @target_tile_pos[:y] != new_tile_pos[:y]
      # Position changed - start new interpolation
      @target_tile_pos = new_tile_pos

      # Check for teleport (large jump)
      if ClientInterpolation.is_teleport?(@current_tile_pos, @target_tile_pos, 5.0)
        # Teleport detected - snap immediately
        @current_tile_pos = @target_tile_pos.dup
        @interp_state = nil
      elsif ClientInterpolation.should_snap?(@current_tile_pos, @target_tile_pos, 0.5)
        # Very close - snap immediately
        @current_tile_pos = @target_tile_pos.dup
        @interp_state = nil
      else
        # Normal movement - interpolate
        duration = ClientInterpolation.calculate_duration(@current_tile_pos, @target_tile_pos)
        @interp_state = ClientInterpolation.create_interpolation_state(@current_tile_pos, @target_tile_pos, duration)
      end
    end

    # Update interpolation if active
    if @interp_state
      @current_tile_pos = ClientInterpolation.update_interpolation(@interp_state)
      # Clear interpolation if complete
      @interp_state = nil if ClientInterpolation.interpolation_complete?(@interp_state[:start_time], @interp_state[:duration])
    end

    # Convert tile position to pixel position (with interpolation)
    x_px = @current_tile_pos[:x] * 32 + 16 - $game_map.display_x / 4
    y_px = @current_tile_pos[:y] * 32 + 32 - $game_map.display_y / 4
    self.x = x_px
    self.y = y_px

    # Calculate Z-level (same formula as Game_Character#screen_z)
    # Characters store position in subpixels (REAL_RES_Y = TILE_HEIGHT * Y_SUBPIXELS)
    # Convert tile position to subpixels: tile_y * 128 (where 128 = 32 * 4)
    real_y = @current_tile_pos[:y] * (Game_Map::TILE_HEIGHT * Game_Map::Y_SUBPIXELS)

    # Calculate screen_y_ground using the exact same formula as Game_Character#screen_y_ground
    screen_y_ground = ((real_y - $game_map.display_y).to_f / Game_Map::Y_SUBPIXELS).round + Game_Map::TILE_HEIGHT

    # Add height adjustment if sprite is taller than one tile (same as Game_Character#screen_z)
    z = screen_y_ground
    z += ((@ch > Game_Map::TILE_HEIGHT) ? Game_Map::TILE_HEIGHT - 1 : 0)
    self.z = z

    @name_sprite.update_position(self.x, self.y)

    # Update shadow position
    position_shadow

    # Apply day/night tint (same as local player)
    pbDayNightTint(self) if defined?(pbDayNightTint)

    # Update name and busy status
    busy = (data[:busy].to_i == 1)
    if data[:name] && (data[:name] != @name_sprite.name || busy != @name_sprite.busy)
      @name_sprite.draw_name(data[:name], busy)
    end

    # --- Check if player is moving (before sprite generation) ---
    new_x = data[:x].to_i
    new_y = data[:y].to_i
    was_moving = (@last_x != new_x || @last_y != new_y)
    @is_moving = was_moving

    # --- Movement state update (surf, dive, bike, run, fish) ---
    new_surf = (data[:surf].to_i == 1)
    new_dive = (data[:dive].to_i == 1)
    new_bike = (data[:bike].to_i == 1)
    new_run = (data[:run].to_i == 1)
    new_fish = (data[:fish].to_i == 1)

    # Detect state changes
    state_changed = (@surf != new_surf || @dive != new_dive || @bike != new_bike || @run != new_run || @fish != new_fish)

    if state_changed
      @surf = new_surf
      @dive = new_dive
      @bike = new_bike
      @run = new_run
      @fish = new_fish

      # Update surf base sprite
      if @surf || @dive
        # Create surf base if needed
        unless @surf_base
          begin
            @surf_base = Sprite.new(@viewport)
            @surf_base.bitmap = RPG::Cache.load_bitmap("Graphics/Characters/", "surf_offset")
            @surf_base.ox = @surf_base.bitmap.width / 2
            @surf_base.oy = @surf_base.bitmap.height / 2
            @surf_base.visible = true
            ##MultiplayerDebug.info("SPR-SURF", "Created surf base for #{@sid}")
          rescue => e
            ##MultiplayerDebug.warn("SPR-SURF", "Failed to create surf base for #{@sid}: #{e.message}")
            @surf_base = nil
          end
        end
      else
        # Remove surf base if not surfing/diving
        if @surf_base
          @surf_base.dispose rescue nil
          @surf_base = nil
        end
      end
    end

    # Update surf base position and visibility
    if @surf_base
      @surf_base.x = self.x
      @surf_base.y = self.y - 4  # Slight offset like Sprite_SurfBase
      @surf_base.z = self.z - 1
      @surf_base.opacity = self.opacity
      @surf_base.visible = self.visible && (@surf || @dive)
      pbDayNightTint(@surf_base) if defined?(pbDayNightTint)
    end

    # --- Outfit & sprite generation ---
    # Include movement state in appearance signature to regenerate sprite when state changes
    # Also include whether player is moving to switch between idle/movement sprites
    movement_signature = "#{@surf ? 'S' : ''}#{@dive ? 'D' : ''}#{@bike ? 'B' : ''}#{@run ? 'R' : ''}#{@fish ? 'F' : ''}#{@is_moving ? 'M' : 'I'}"
    appearance_signature = rebuild_signature(data) + "|" + movement_signature

    if @last_appearance != appearance_signature || self.bitmap.nil? || self.bitmap.disposed?
      @last_appearance = appearance_signature
      begin
        skin_tone     = (data[:skin_tone] || 0).to_i
        hair_color    = (data[:hair_color] || 0).to_i
        hat_color     = (data[:hat_color] || 0).to_i
        clothes_color = (data[:clothes_color] || 0).to_i

        clothes = (data[:clothes].to_s.empty? ? "001" : data[:clothes].to_s)
        hat     = (data[:hat].to_s.empty?     ? "000" : data[:hat].to_s)
        hair    = (data[:hair].to_s.empty?    ? "000" : data[:hair].to_s)

        # Determine action type based on movement state
        # Only use movement-based actions (bike, run) if player is actually moving
        action = "walk"

        # Stationary actions override movement
        if @fish
          action = "fish"
        # Water-based movement
        elsif @surf
          action = "surf"
        elsif @dive
          action = "dive"
        # Land-based movement (only if actually moving)
        elsif @is_moving && @bike
          action = "bike"
        elsif @is_moving && @run && !@bike
          action = "run"
        else
          action = "walk"  # Idle/standing
        end

        ##MultiplayerDebug.info("SPR-FILE", "Generating sprite for #{@sid}: c=#{clothes}/#{clothes_color} h=#{hat}/#{hat_color} hr=#{hair}/#{hair_color} st=#{skin_tone} action=#{action}")

        remote_trainer = ::RemoteTrainer.new(
          clothes, hat, hair,
          skin_tone, hair_color, hat_color, clothes_color
        )

        new_bmp = nil
        new_bmp = generateClothedBitmapStatic(remote_trainer, action) if defined?(generateClothedBitmapStatic)

        if new_bmp.nil?
          ##MultiplayerDebug.warn("SPR-GEN", "generateClothedBitmapStatic returned nil; fallback for #{@sid}")
          new_bmp = generateClothedBitmapStatic($Trainer, "walk") if defined?($Trainer)
        end

        if new_bmp
          # Dispose old safely
          begin
            if self.bitmap && !self.bitmap.disposed?
              self.bitmap.dispose
            end
          rescue => e
            ##MultiplayerDebug.warn("SPR-DISP", "Old bitmap dispose warn for #{@sid}: #{e.message}")
          end

          self.bitmap = new_bmp
          @owns_bitmap = true
          @cw = new_bmp.width / 4
          @ch = new_bmp.height / 4
          self.ox = @cw / 2
          self.oy = @ch
          ##MultiplayerDebug.info("SPR-UPD", "Sprite generated for #{@sid} (#{data[:name]})")
        else
          self.visible = false
          @name_sprite.visible = false
          ##MultiplayerDebug.error("SPR-GEN", "Failed to generate bitmap for #{@sid}")
        end
      rescue => e
        ##MultiplayerDebug.error("SPR-GEN", "Exception while generating sprite for #{@sid}: #{e.message}")
        self.visible = false
        @name_sprite.visible = false
      end
    end

    # --- Direction & animation ---
    # Update position tracking (already calculated @is_moving earlier)
    @last_x, @last_y = new_x, new_y

    dir = (data[:face] || 2).to_i
    frame = @is_moving ? (Graphics.frame_count / 15) % 4 : 0
    sx = frame * @cw
    sy = case dir
         when 2 then 0
         when 4 then @ch
         when 6 then @ch * 2
         when 8 then @ch * 3
         else 0
         end
    self.src_rect.set(sx, sy, @cw, @ch)
  end

  def dispose
    begin
      @name_sprite.dispose if @name_sprite
      @name_sprite = nil
      if @shadow
        @shadow.dispose unless @shadow.disposed?
        @shadow = nil
      end
      if @surf_base
        @surf_base.dispose unless @surf_base.disposed?
        @surf_base = nil
      end
      if @owns_bitmap && self.bitmap && !self.bitmap.disposed?
        self.bitmap.dispose
      end
    rescue => e
      ##MultiplayerDebug.warn("SPR-DISP2", "Dispose guard for #{@sid}: #{e.message}")
    end
    super
  end
end

# -----------------------------------------------------------------
# === Multiplayer Sprite Manager
# -----------------------------------------------------------------
class MultiplayerSpriteManager
  STALE_TIMEOUT = 5.0  # Remove players who haven't updated in 5 seconds

  def initialize(viewport)
    @viewport = viewport
    @sprites = {}
    @last_seen = {}  # Track when each player was last updated (sid => Time)
  end

  def safe_players_snapshot
    players = MultiplayerClient.players rescue {}
    return {} unless players.is_a?(Hash)
    snap = {}
    players.each do |sid, data|
      next if sid.nil? || data.nil?
      begin
        snap[sid] = data.dup
      rescue
        snap[sid] = {
          :name => data[:name],
          :map  => data[:map],
          :x    => data[:x],
          :y    => data[:y],
          :face => data[:face],
          :clothes => data[:clothes],
          :hat     => data[:hat],
          :hair    => data[:hair],
          :skin_tone     => data[:skin_tone],
          :hair_color    => data[:hair_color],
          :hat_color     => data[:hat_color],
          :clothes_color => data[:clothes_color]
        }
      end
    end
    snap
  end

  def update
    players = safe_players_snapshot
    current_time = Time.now

    # Clean up disconnected players from MultiplayerClient.players hash
    # Remove players who haven't sent SYNC updates in STALE_TIMEOUT seconds
    begin
      all_player_sids = MultiplayerClient.players.keys rescue []
      all_player_sids.each do |sid|
        player_data = MultiplayerClient.players[sid]
        next unless player_data

        last_sync = player_data[:last_sync_time]

        # If we haven't received a SYNC from this player in STALE_TIMEOUT seconds, remove them
        if last_sync && (current_time - last_sync) > STALE_TIMEOUT
          begin
            MultiplayerClient.players.delete(sid)
            @last_seen.delete(sid)
            ##MultiplayerDebug.info("SPR-CLEAN", "Removed stale player #{sid} from client hash (no SYNC for #{(current_time - last_sync).round(1)}s)")
          rescue => e
            ##MultiplayerDebug.warn("SPR-CLEAN", "Failed to remove stale player #{sid}: #{e.message}")
          end
        elsif last_sync
          # Player is active, update our tracking
          @last_seen[sid] = last_sync
        end
      end
    rescue => e
      ##MultiplayerDebug.warn("SPR-CLEAN", "Player cleanup error: #{e.message}")
    end

    # Remove sprites for players no longer in snapshot
    @sprites.keys.each do |sid|
      next if players.key?(sid)

      if @sprites[sid].instance_variable_get(:@_marked_for_removal)
        @sprites[sid].dispose
        @sprites.delete(sid)
        @last_seen.delete(sid)
        ##MultiplayerDebug.info("SPR-DEL", "Removed sprite for #{sid} (not in snapshot)")
      else
        @sprites[sid].instance_variable_set(:@_marked_for_removal, true)
      end
    end

    # Create/update sprites for active players
    players.each do |sid, data|
      next if data.nil?
      unless @sprites.key?(sid)
        @sprites[sid] = Sprite_RemotePlayer.new(@viewport, sid, data)
        ##MultiplayerDebug.info("SPR-NEW", "Created remote sprite for #{sid} (#{data[:name]})")
      end
      sprite = @sprites[sid]
      sprite.instance_variable_set(:@_marked_for_removal, false)
      sprite.update_with_data(data)
    end
  end

  def dispose
    @sprites.each_value do |spr|
      begin
        spr.dispose
      rescue => e
        ##MultiplayerDebug.warn("SPR-MGR-DISP", "Dispose warn: #{e.message}")
      end
    end
    @sprites.clear
  end
end

# -----------------------------------------------------------------
# === Hook into Spriteset_Map safely
# -----------------------------------------------------------------
if defined?(Spriteset_Map)
  class Spriteset_Map
    alias multiplayer_init initialize unless method_defined?(:multiplayer_init)
    alias multiplayer_dispose dispose unless method_defined?(:multiplayer_dispose)
    alias multiplayer_update update unless method_defined?(:multiplayer_update)

    def initialize(*args)
      # Create multiplayer sprites BEFORE calling original initialize
      # This ensures remote players are added to viewport before tiles
      @multiplayer_sprites = MultiplayerSpriteManager.new(@@viewport1)
      ##MultiplayerDebug.info("SPR-HOOK", "Multiplayer sprite manager pre-initialized.")

      multiplayer_init(*args)

      ##MultiplayerDebug.info("SPR-HOOK", "Multiplayer sprite manager initialized.")
    end

    def update
      multiplayer_update
      @multiplayer_sprites&.update
    end

    def dispose
      @multiplayer_sprites&.dispose
      @multiplayer_sprites = nil
      multiplayer_dispose
    end
  end
  ##MultiplayerDebug.info("SPR-HOOKOK", "Hooked Spriteset_Map successfully.")
else
  ##MultiplayerDebug.error("SPR-HOOKFAIL", "Spriteset_Map not defined; multiplayer sprites inactive.")
end
