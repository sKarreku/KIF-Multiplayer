#===============================================================================
# Coop Trainer Battle - Wait Screen with Ready States
#===============================================================================
# Custom wait screen using TrainerCoopSync.png background
# Shows player head sprites, names, pokemon counts, and ready states
#===============================================================================

class CoopTrainerWaitScreen
  SLOT_POSITIONS = {
    # Left side - 3 ally slots (initiator + 2 joiners)
    # Slot 1: Initiator (top left: 27,25 | bottom right: 84,65)
    ally_1: {
      sprite_x: 27, sprite_y: 25, sprite_w: 57, sprite_h: 40,
      name_x: 27, name_y: 65, name_w: 57, name_h: 7,
      count_x: 99, count_y: 42
    },
    # Slot 2: Non-initiator left (top left: 28,94 | bottom right: 83,138)
    ally_2: {
      sprite_x: 28, sprite_y: 94, sprite_w: 55, sprite_h: 44,
      name_x: 26, name_y: 142, name_w: 57, name_h: 7,
      count_x: 0, count_y: 0  # No individual count
    },
    # Slot 3: Non-initiator right (top left: 93,94 | bottom right: 148,138)
    ally_3: {
      sprite_x: 93, sprite_y: 94, sprite_w: 55, sprite_h: 44,
      name_x: 92, name_y: 142, name_w: 57, name_h: 9,
      count_x: 0, count_y: 0  # No individual count
    },

    # Right side - 1 foe slot (top left: 411,28 | bottom right: 466,65)
    foe: {
      sprite_x: 411, sprite_y: 26, sprite_w: 54, sprite_h: 37,
      name_x: 410, name_y: 65, name_w: 57, name_h: 10,
      count_x: 354, count_y: 42
    }
  }

  def initialize(battle_id, trainer, is_initiator)
    @battle_id = battle_id
    @trainer = trainer # Enemy trainer object
    @is_initiator = is_initiator
    @ready_states = {} # SID => true/false
    @my_ready = false
    @my_sid = MultiplayerClient.instance_variable_get(:@session_id) rescue "SID0"
    @disposed = false

    create_ui
    update_display
  end

  def create_ui
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999

    # Opaque grey background overlay
    @bg_overlay = Sprite.new(@viewport)
    @bg_overlay.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @bg_overlay.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 180))
    @bg_overlay.z = @viewport.z

    # Background
    @bg = Sprite.new(@viewport)
    begin
      bg_bitmap = RPG::Cache.load_bitmap("Graphics/", "TrainerCoopSync")
      @bg.bitmap = Bitmap.new(bg_bitmap.width, bg_bitmap.height)
      @bg.bitmap.blt(0, 0, bg_bitmap, Rect.new(0, 0, bg_bitmap.width, bg_bitmap.height))

      # Center the background
      @bg.x = (Graphics.width - bg_bitmap.width) / 2
      @bg.y = (Graphics.height - bg_bitmap.height) / 2
      @bg.z = @viewport.z + 1

      # Store offset for centering other elements
      @offset_x = @bg.x
      @offset_y = @bg.y
    rescue => e
      # Fallback if image not found
      ##MultiplayerDebug.warn("COOP-WAIT-SCREEN", "Failed to load TrainerCoopSync.png: #{e.message}")
      @bg.bitmap = Bitmap.new(512, 224)
      @bg.bitmap.fill_rect(0, 0, 512, 224, Color.new(50, 50, 100))
      @bg.x = (Graphics.width - 512) / 2
      @bg.y = (Graphics.height - 224) / 2
      @bg.z = @viewport.z + 1
      @offset_x = @bg.x
      @offset_y = @bg.y
    end

    # Head sprites
    @head_sprites = {}
    [:ally_1, :ally_2, :ally_3, :foe].each do |slot|
      pos = SLOT_POSITIONS[slot]
      @head_sprites[slot] = Sprite.new(@viewport)
      @head_sprites[slot].bitmap = Bitmap.new(pos[:sprite_w], pos[:sprite_h])
      @head_sprites[slot].x = pos[:sprite_x] + @offset_x
      @head_sprites[slot].y = pos[:sprite_y] + @offset_y
      @head_sprites[slot].ox = 0  # Top-left origin
      @head_sprites[slot].oy = 0
      @head_sprites[slot].z = @viewport.z + 2
    end

    # Text overlays (names and counts)
    @text_overlay = Sprite.new(@viewport)
    @text_overlay.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @text_overlay.z = @viewport.z + 3

    # Load pokeball icon for count display
    @pokeball_icon = nil
    begin
      @pokeball_icon = RPG::Cache.load_bitmap("Graphics/Pictures/Summary/", "icon_ball_POKEBALL")
    rescue => e
      ##MultiplayerDebug.warn("COOP-WAIT-SCREEN", "Failed to load pokeball icon: #{e.message}")
    end

    # Question mark sprites
    @question_sprites = {}
    [:ally_2, :ally_3].each do |slot|
      pos = SLOT_POSITIONS[slot]
      @question_sprites[slot] = Sprite.new(@viewport)
      @question_sprites[slot].bitmap = Bitmap.new(pos[:sprite_w], pos[:sprite_h])
      @question_sprites[slot].bitmap.font.size = 28
      @question_sprites[slot].bitmap.font.bold = true
      @question_sprites[slot].bitmap.font.color = Color.new(200, 200, 200)
      rect = Rect.new(0, 0, pos[:sprite_w], pos[:sprite_h])
      @question_sprites[slot].bitmap.draw_text(rect, "?", 1)
      @question_sprites[slot].x = pos[:sprite_x] + @offset_x
      @question_sprites[slot].y = pos[:sprite_y] + @offset_y
      @question_sprites[slot].ox = 0
      @question_sprites[slot].oy = 0
      @question_sprites[slot].z = @viewport.z + 2
    end
  end

  def update_display
    return if @disposed

    @text_overlay.bitmap.clear

    # Get current allies and ready states
    allies_joined = MultiplayerClient.trainer_battle_allies(@battle_id) rescue []
    ready_states = MultiplayerClient.trainer_ready_states(@battle_id) rescue {}

    # Merge remote ready states with local
    ready_states.each { |sid, is_ready| @ready_states[sid] = is_ready }

    # Build ally list: [initiator_sid, joiner1_sid, joiner2_sid]
    ally_list = [@my_sid] if @is_initiator
    ally_list ||= []

    # Get initiator SID from sync wait if joiner
    unless @is_initiator
      sync_wait = MultiplayerClient.active_trainer_sync_wait
      initiator_sid = sync_wait[:initiator_sid] if sync_wait
      ally_list = [initiator_sid] if initiator_sid
    end

    # Add joiners
    allies_joined.each { |sid| ally_list << sid unless ally_list.include?(sid) }

    # Slot 1: Initiator
    if ally_list[0]
      draw_ally_slot(:ally_1, ally_list[0], true) # Initiator always ready
      @question_sprites[:ally_2].visible = false if ally_list[1]
    else
      @head_sprites[:ally_1].bitmap.clear
    end

    # Slot 2: Joiner 1
    if ally_list[1]
      draw_ally_slot(:ally_2, ally_list[1], @ready_states[ally_list[1]] || false)
      @question_sprites[:ally_2].visible = false
    else
      @head_sprites[:ally_2].bitmap.clear
      @question_sprites[:ally_2].visible = true
    end

    # Slot 3: Joiner 2
    if ally_list[2]
      draw_ally_slot(:ally_3, ally_list[2], @ready_states[ally_list[2]] || false)
      @question_sprites[:ally_3].visible = false
    else
      @head_sprites[:ally_3].bitmap.clear
      @question_sprites[:ally_3].visible = true
    end

    # Foe slot
    draw_foe_slot

    # Instructions at bottom
    draw_instructions(ally_list)
  end

  def draw_ally_slot(slot, sid, is_ready)
    pos = SLOT_POSITIONS[slot]

    # Get player info
    is_me = (sid == @my_sid)
    player_name = is_me ? $Trainer.name : (get_player_name(sid) || sid)
    party_count = is_me ? $Trainer.party.length : (get_remote_party_count(sid) || 0)

    # Draw head sprite
    draw_player_head(@head_sprites[slot], sid, is_me, pos[:sprite_w], pos[:sprite_h])

    # Draw name (green if ready, red if not ready, white if initiator)
    name_color = is_ready ? Color.new(0, 255, 0) : Color.new(255, 100, 100)
    name_color = Color.new(255, 255, 255) if slot == :ally_1 # Initiator always white

    @text_overlay.bitmap.font.size = 10
    @text_overlay.bitmap.font.bold = true

    # Draw name in exact position (with offset)
    @text_overlay.bitmap.font.color = Color.new(0, 0, 0) # Shadow
    @text_overlay.bitmap.draw_text(pos[:name_x] + @offset_x + 1, pos[:name_y] + @offset_y + 1, pos[:name_w], pos[:name_h], player_name, 1)
    @text_overlay.bitmap.font.color = name_color
    @text_overlay.bitmap.draw_text(pos[:name_x] + @offset_x, pos[:name_y] + @offset_y, pos[:name_w], pos[:name_h], player_name, 1)

    # Draw pokemon count ONLY for slot 1 (initiator) in the dedicated small box
    if slot == :ally_1
      total_count = party_count
      # Add joined allies' counts
      allies_joined = MultiplayerClient.trainer_battle_allies(@battle_id) rescue []
      allies_joined.each do |ally_sid|
        total_count += get_remote_party_count(ally_sid) || 0
      end

      @text_overlay.bitmap.font.size = 14
      @text_overlay.bitmap.font.color = Color.new(0, 0, 0) # Shadow
      @text_overlay.bitmap.draw_text(pos[:count_x] + @offset_x + 1, pos[:count_y] + @offset_y + 1, 20, 16, total_count.to_s, 1)
      @text_overlay.bitmap.font.color = Color.new(255, 255, 255)
      @text_overlay.bitmap.draw_text(pos[:count_x] + @offset_x, pos[:count_y] + @offset_y, 20, 16, total_count.to_s, 1)

      # Draw pokeball icon to the right of count (scaled down)
      if @pokeball_icon
        icon_x = pos[:count_x] + @offset_x + 18
        icon_y = pos[:count_y] + @offset_y
        icon_scale = 12  # Target size in pixels
        src_rect = Rect.new(0, 0, @pokeball_icon.width, @pokeball_icon.height)
        dst_rect = Rect.new(icon_x, icon_y, icon_scale, icon_scale)
        @text_overlay.bitmap.stretch_blt(dst_rect, @pokeball_icon, src_rect)
      end
    end
  end

  def draw_foe_slot
    return unless @trainer

    pos = SLOT_POSITIONS[:foe]

    # Draw trainer sprite
    draw_trainer_head(@head_sprites[:foe], @trainer, pos[:sprite_w], pos[:sprite_h])

    # Draw trainer name (with offset)
    trainer_name = @trainer.name.to_s rescue "Trainer"
    @text_overlay.bitmap.font.size = 10
    @text_overlay.bitmap.font.bold = true

    @text_overlay.bitmap.font.color = Color.new(0, 0, 0) # Shadow
    @text_overlay.bitmap.draw_text(pos[:name_x] + @offset_x + 1, pos[:name_y] + @offset_y + 1, pos[:name_w], pos[:name_h], trainer_name, 1)
    @text_overlay.bitmap.font.color = Color.new(255, 200, 100) # Orange for enemy
    @text_overlay.bitmap.draw_text(pos[:name_x] + @offset_x, pos[:name_y] + @offset_y, pos[:name_w], pos[:name_h], trainer_name, 1)

    # Draw foe pokemon count in small box
    foe_count = @trainer.party.length rescue 0
    @text_overlay.bitmap.font.size = 14
    @text_overlay.bitmap.font.color = Color.new(0, 0, 0) # Shadow
    @text_overlay.bitmap.draw_text(pos[:count_x] + @offset_x + 1, pos[:count_y] + @offset_y + 1, 20, 16, foe_count.to_s, 1)
    @text_overlay.bitmap.font.color = Color.new(255, 255, 255)
    @text_overlay.bitmap.draw_text(pos[:count_x] + @offset_x, pos[:count_y] + @offset_y, 20, 16, foe_count.to_s, 1)

    # Draw pokeball icon to the right of count (scaled down)
    if @pokeball_icon
      icon_x = pos[:count_x] + @offset_x + 18
      icon_y = pos[:count_y] + @offset_y
      icon_scale = 12  # Target size in pixels
      src_rect = Rect.new(0, 0, @pokeball_icon.width, @pokeball_icon.height)
      dst_rect = Rect.new(icon_x, icon_y, icon_scale, icon_scale)
      @text_overlay.bitmap.stretch_blt(dst_rect, @pokeball_icon, src_rect)
    end
  end

  def draw_instructions(ally_list)
    text_x = 248 + @offset_x
    text_y = 181 + @offset_y

    @text_overlay.bitmap.font.size = 12
    @text_overlay.bitmap.font.bold = false

    if @is_initiator
      text = "Press ACTION to start battle (#{ally_list.length}v1)"
      @text_overlay.bitmap.font.color = Color.new(0, 0, 0)
      @text_overlay.bitmap.draw_text(text_x + 1, text_y + 1, 250, 20, text, 1)
      @text_overlay.bitmap.font.color = Color.new(255, 255, 255)
      @text_overlay.bitmap.draw_text(text_x, text_y, 250, 20, text, 1)
    else
      status = @my_ready ? "READY" : "NOT READY"
      color = @my_ready ? Color.new(0, 255, 0) : Color.new(255, 100, 100)
      text = "Press ACTION to toggle ready (#{status})"
      @text_overlay.bitmap.font.color = Color.new(0, 0, 0)
      @text_overlay.bitmap.draw_text(text_x + 1, text_y + 1, 250, 20, text, 1)
      @text_overlay.bitmap.font.color = color
      @text_overlay.bitmap.draw_text(text_x, text_y, 250, 20, text, 1)
    end
  end

  def draw_player_head(sprite, sid, is_me, target_w, target_h)
    sprite.bitmap.clear

    begin
      # Generate full sprite using outfit system
      if is_me
        # Use local player's outfit
        full_bmp = generateClothedBitmapStatic($Trainer, "walk") if defined?(generateClothedBitmapStatic)
      else
        # Try to get remote player's outfit
        remote_data = get_remote_outfit_data(sid)
        if remote_data
          remote_trainer = ::RemoteTrainer.new(
            remote_data[:clothes], remote_data[:hat], remote_data[:hair],
            remote_data[:skin_tone], remote_data[:hair_color],
            remote_data[:hat_color], remote_data[:clothes_color]
          )
          full_bmp = generateClothedBitmapStatic(remote_trainer, "walk") if defined?(generateClothedBitmapStatic)
        end
      end

      if full_bmp
        # Extract front-facing frame (column 1, row 0)
        char_width = full_bmp.width / 4
        char_height = full_bmp.height / 4
        full_char_rect = Rect.new(char_width, 0, char_width, char_height)

        # Scale to fit target size maintaining aspect ratio
        aspect = char_width.to_f / char_height.to_f
        if aspect > 1
          scaled_h = target_h
          scaled_w = (target_h * aspect).to_i
        else
          scaled_w = target_w
          scaled_h = (target_w / aspect).to_i
        end

        offset_x = (target_w - scaled_w) / 2
        offset_y = (target_h - scaled_h) / 2

        sprite.bitmap.stretch_blt(Rect.new(offset_x, offset_y, scaled_w, scaled_h), full_bmp, full_char_rect)
        full_bmp.dispose if full_bmp
      else
        # Fallback
        sprite.bitmap.fill_rect(0, 0, target_w, target_h, Color.new(100, 100, 200))
      end
    rescue => e
      ##MultiplayerDebug.warn("COOP-WAIT-SCREEN", "Failed to draw player sprite: #{e.message}")
      sprite.bitmap.fill_rect(0, 0, target_w, target_h, Color.new(100, 100, 200))
    end
  end

  def draw_trainer_head(sprite, trainer, target_w, target_h)
    sprite.bitmap.clear
    return unless trainer

    begin
      trainer_type = trainer.trainer_type rescue :YOUNGSTER
      char_name = getTrainerTypeGraphic(trainer_type) rescue "BW (19)"

      full_sprite = RPG::Cache.load_bitmap("Graphics/Characters/", char_name)

      char_width = full_sprite.width / 4
      char_height = full_sprite.height / 4

      # Front-facing frame
      full_char_rect = Rect.new(char_width, 0, char_width, char_height)

      # Maintain aspect ratio
      aspect = char_width.to_f / char_height.to_f
      if aspect > 1
        scaled_h = target_h
        scaled_w = (target_h * aspect).to_i
      else
        scaled_w = target_w
        scaled_h = (target_w / aspect).to_i
      end

      offset_x = (target_w - scaled_w) / 2
      offset_y = (target_h - scaled_h) / 2

      sprite.bitmap.stretch_blt(Rect.new(offset_x, offset_y, scaled_w, scaled_h), full_sprite, full_char_rect)
    rescue => e
      ##MultiplayerDebug.warn("COOP-WAIT-SCREEN", "Failed to draw trainer sprite: #{e.message}")
      sprite.bitmap.fill_rect(0, 0, target_w, target_h, Color.new(200, 100, 100))
    end
  end

  def get_player_name(sid)
    squad = MultiplayerClient.squad rescue nil
    return nil unless squad && squad[:members]
    member = squad[:members].find { |m| m[:sid].to_s == sid.to_s }
    member ? member[:name] : nil
  end

  def get_remote_party_count(sid)
    party = MultiplayerClient.remote_party(sid) rescue nil
    party ? party.length : 0
  end

  def get_remote_outfit_data(sid)
    # Get outfit data from @players hash (populated by SYNC messages)
    players = MultiplayerClient.instance_variable_get(:@players) rescue nil
    return nil unless players

    player_data = players[sid.to_s]
    return nil unless player_data

    # Return outfit data hash
    {
      clothes: (player_data[:clothes] || "001").to_s,
      hat: (player_data[:hat] || "000").to_s,
      hair: (player_data[:hair] || "000").to_s,
      skin_tone: (player_data[:skin_tone] || 0).to_i,
      hair_color: (player_data[:hair_color] || 0).to_i,
      hat_color: (player_data[:hat_color] || 0).to_i,
      clothes_color: (player_data[:clothes_color] || 0).to_i
    }
  end

  def toggle_ready
    return if @is_initiator # Initiator doesn't toggle
    @my_ready = !@my_ready

    # Broadcast ready state
    message = @my_ready ? "COOP_TRAINER_READY:#{@battle_id}" : "COOP_TRAINER_UNREADY:#{@battle_id}"
    MultiplayerClient.send_data(message)

    @ready_states[@my_sid] = @my_ready
    update_display
  end

  def update_ready_state(sid, is_ready)
    @ready_states[sid] = is_ready
    update_display
  end

  def update
    Graphics.update
    Input.update
  end

  def dispose
    return if @disposed

    @head_sprites.each_value do |sprite|
      sprite.bitmap.dispose if sprite.bitmap
      sprite.dispose
    end

    @question_sprites.each_value do |sprite|
      sprite.bitmap.dispose if sprite.bitmap
      sprite.dispose
    end

    @text_overlay.bitmap.dispose if @text_overlay.bitmap
    @text_overlay.dispose

    @bg.bitmap.dispose if @bg.bitmap
    @bg.dispose

    @viewport.dispose

    @disposed = true
  end
end

#===============================================================================
# Helper function to get trainer graphic
#===============================================================================
def getTrainerTypeGraphic(trainerType)
  case trainerType
  when :YOUNGSTER       then return "BW (19)"
  when :LASS            then return "BW (23)"
  when :POKEMANIAC      then return "BW (30)"
  when :PSYCHIC_F       then return "BW (30)"
  when :GENTLEMAN       then return "BW (55)"
  when :LADY            then return "BW (28)"
  when :CAMPER          then return "BW (59)"
  when :PICNICKER       then return "BW (60)"
  when :TUBER_M         then return "BWTuber_male"
  when :TUBER_F         then return "BWTuber_female"
  when :SWIMMER_M       then return "BWSwimmerLand"
  when :SWIMMER_F       then return "BWSwimmer_female2"
  when :COOLTRAINER_F   then return "BW024"
  when :JUGGLER         then return "BWHarlequin"
  when :POKEMONBREEDER  then return "BW028"
  when :BUGCATCHER      then return "BWBugCatcher_male"
  when :BLACKBELT       then return "BWBlackbelt"
  when :FISHERMAN       then return "BW (71)"
  when :RUINMANIAC      then return "BW (72)"
  when :TAMER           then return "BW (69)"
  when :BEAUTY          then return "BW015"
  when :AROMALADY       then return "BWAomalady"
  when :ROCKER          then return "BWPunkGuy"
  when :BIRDKEEPER      then return "BW (29)"
  when :SAILOR          then return "BWSailor"
  when :HIKER           then return "BWHiker"
  when :ENGINEER        then return "BW (75)"
  when :COOLTRAINER_M   then return "BW023"
  when :BIKER           then return "BW055"
  when :CRUSHGIRL       then return "BWBattleGirl"
  when :POKEMONRANGER_M then return "BW (47)"
  when :POKEMONRANGER_F then return "BW (48)"
  when :PSYCHIC_M       then return "BW (30)"
  when :CHANNELER       then return "BW (40)"
  when :GAMBLER         then return "BW (111)"
  when :SCIENTIST       then return "BW (81)"
  when :SUPERNERD       then return "BW (81)"
  when :CUEBALL         then return "BWRoughneck"
  else                  return "BW (19)" # Default
  end
end

##MultiplayerDebug.info("MODULE-66", "Coop trainer wait screen with ready states loaded")
