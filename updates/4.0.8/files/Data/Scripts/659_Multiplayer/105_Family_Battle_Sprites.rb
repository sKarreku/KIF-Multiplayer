#===============================================================================
# MODULE: Family/Subfamily System - Battle Sprite Integration
#===============================================================================
# Hooks PokemonBattlerSprite and PokemonDataBox to display family effects in battle.
#
# Integration Points:
#   1. PokemonBattlerSprite - adds animated outline effect behind Pokemon sprite
#   2. PokemonDataBox - applies custom font to Pokemon name in battle UI
#
# Both sprite AND text get the same outline effect + colors from subfamily config.
#===============================================================================

#-------------------------------------------------------------------------------
# Pokemon Battler Sprite - adds animated outline effect behind sprite
#-------------------------------------------------------------------------------
class PokemonBattlerSprite < RPG::Sprite
  attr_reader :family_outline_sprite

  # Class-level cache for outline masks (shared across all instances)
  @@family_outline_cache = {}

  # Class-level cache for animation frames (shared across all instances)
  @@family_animation_cache = {}

  # Hook initialize to add outline sprite tracking
  alias family_original_initialize initialize
  def initialize(*args)
    family_original_initialize(*args)
    @family_outline_sprite = nil   # Composite sprite (outline + Pokemon)
    @family_frame_counter = 0
    @family_animation_frames = nil # Cached animation frames

    if defined?(MultiplayerDebug)
      #MultiplayerDebug.info("FAMILY-SPRITE", "PokemonBattlerSprite initialized (index #{@index})")
    end
  end

  # Hook setPokemonBitmap to create outline when Pokemon is set
  alias family_original_setPokemonBitmap setPokemonBitmap
  def setPokemonBitmap(pkmn, back=false)
    family_original_setPokemonBitmap(pkmn, back)

    # Only process if pkmn is valid Pokemon object
    if pkmn && pkmn.respond_to?(:has_family?)
      if defined?(MultiplayerDebug)
        #MultiplayerDebug.info("FAMILY-SPRITE", "setPokemonBitmap called: #{pkmn.name}, back=#{back}, has_family=#{pkmn.has_family?}")
      end

      if should_show_family_outline?
        create_family_outline
      else
        # Clean up family outline when switching to non-family Pokemon
        dispose_family_outline
      end
    else
      # Clean up family outline when Pokemon doesn't support family system
      dispose_family_outline
    end
  end

  # Check if this Pokemon should show a family outline
  def should_show_family_outline?
    return @pkmn && @pkmn.respond_to?(:has_family?) && @pkmn.has_family?
  end

  # Create composite sprite: outline + Pokemon (OPTIMIZED - same as summary screen)
  def create_family_outline
    dispose_family_outline

    effect = PokemonFamilyConfig.get_family_effect(@pkmn.family)
    colors = PokemonFamilyConfig.get_subfamily_colors(@pkmn.family, @pkmn.subfamily)

    unless effect && colors
      return
    end

    begin
      pkmn_bitmap = self.bitmap
      return unless pkmn_bitmap

      width = pkmn_bitmap.width
      height = pkmn_bitmap.height

      # Store original bitmap before we modify self.bitmap
      original_bitmap = pkmn_bitmap.clone

      # Step 1: Make original sprite transparent (same as DataBox approach)
      transparent_bitmap = Bitmap.new(width, height)
      old_bitmap = self.bitmap
      self.bitmap = transparent_bitmap
      old_bitmap.dispose if old_bitmap != pkmn_bitmap

      # Step 2: Create or retrieve cached outline mask
      cache_key = "#{@pkmn.species}_#{@pkmn.form}_#{width}_#{height}"
      outline_width = 3
      final_w = width + (outline_width * 2)
      final_h = height + (outline_width * 2)

      if @@family_outline_cache[cache_key]
        # Use cached outline mask
        outline_mask = @@family_outline_cache[cache_key].clone
      else
        # Generate outline mask (expensive operation)
        outline_mask = Bitmap.new(final_w, final_h)

        width.times do |x|
          height.times do |y|
            pixel = original_bitmap.get_pixel(x, y)
            if pixel.alpha > 0
              (-outline_width..outline_width).each do |dx|
                (-outline_width..outline_width).each do |dy|
                  dist = Math.sqrt(dx*dx + dy*dy)
                  if dist <= outline_width
                    outline_x = x + dx + outline_width
                    outline_y = y + dy + outline_width
                    if outline_x >= 0 && outline_x < final_w && outline_y >= 0 && outline_y < final_h
                      outline_mask.set_pixel(outline_x, outline_y, Color.new(0, 0, 0, 255))
                    end
                  end
                end
              end
            end
          end
        end

        # Cache the outline mask
        @@family_outline_cache[cache_key] = outline_mask.clone
      end

      # Store outline mask and Pokemon bitmap for compositing
      @family_outline_mask = outline_mask
      @family_pkmn_bitmap = original_bitmap
      @family_outline_width = outline_width

      # Pre-generate animation frames (cache by effect + colors + mask size)
      anim_cache_key = "#{effect}_#{colors.join('_')}_#{final_w}_#{final_h}"
      if @@family_animation_cache[anim_cache_key]
        @family_animation_frames = @@family_animation_cache[anim_cache_key]
      else
        @family_animation_frames = generate_animation_frames(effect, colors, outline_mask, 60)
        @@family_animation_cache[anim_cache_key] = @family_animation_frames
      end

      # Create single composite sprite (outline + Pokemon) - OPTIMIZED
      @family_outline_sprite = Sprite.new(self.viewport)
      @family_outline_sprite.x = self.x
      @family_outline_sprite.y = self.y
      @family_outline_sprite.ox = self.ox + outline_width
      @family_outline_sprite.oy = self.oy + outline_width
      @family_outline_sprite.z = self.z + 2
      @family_outline_sprite.mirror = self.mirror
      @family_outline_sprite.visible = true

      # Store transparent bitmap to prevent disposal
      @family_transparent_bitmap = transparent_bitmap

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("FAMILY-SPRITE", "Created composite sprite at (#{self.x}, #{self.y})")
      end

    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("FAMILY-SPRITE", "Failed: #{e.message}")
      end
      dispose_family_outline
    end
  end

  # Generate all animation frames upfront (60 frames for smooth loop)
  def generate_animation_frames(effect, colors, outline_mask, frame_count)
    frames = []
    frame_count.times do |i|
      frames << FamilyOutlineEffects.apply_effect_filled(effect, outline_mask, colors, i)
    end
    return frames
  end

  # Animate outline sprite with cached frames (OPTIMIZED)
  def animate_family_outline
    return unless @family_outline_sprite && @family_animation_frames && @family_pkmn_bitmap

    begin
      # Use cached animation frame (loop every 60 frames)
      frame_index = (@family_frame_counter / 3) % @family_animation_frames.length
      cached_outline = @family_animation_frames[frame_index]

      # Clone and composite Pokemon on top
      animated_outline = cached_outline.clone
      animated_outline.blt(@family_outline_width, @family_outline_width, @family_pkmn_bitmap, @family_pkmn_bitmap.rect)

      # Update sprite bitmap with composite
      old_bitmap = @family_outline_sprite.bitmap
      @family_outline_sprite.bitmap = animated_outline
      old_bitmap.dispose if old_bitmap

    rescue => e
      if defined?(MultiplayerDebug) && @family_frame_counter % 60 == 0
        MultiplayerDebug.error("FAMILY-SPRITE-ANIM", "Animation failed: #{e.message}")
      end
    end
  end

  # Hook update to animate the outline AND keep original sprite transparent
  alias family_original_update update
  def update(*args)
    family_original_update(*args)

    # If we have family outline AND current Pokemon is still a family Pokemon, keep original sprite transparent
    if @family_outline_sprite && @family_transparent_bitmap && should_show_family_outline?
      self.bitmap = @family_transparent_bitmap
    end

    # Animate outline every frame (60 FPS)
    @family_frame_counter += 1
    if @family_outline_sprite && @family_outline_mask && @family_frame_counter % 1 == 0
      animate_family_outline
    end

    update_family_outline
  end

  # Update composite sprite to follow Pokemon sprite
  def update_family_outline
    return unless @family_outline_sprite

    # Update composite sprite position/properties
    @family_outline_sprite.x = self.x
    @family_outline_sprite.y = self.y
    @family_outline_sprite.ox = self.ox + @family_outline_width
    @family_outline_sprite.oy = self.oy + @family_outline_width
    @family_outline_sprite.z = self.z + 2
    @family_outline_sprite.mirror = self.mirror
    @family_outline_sprite.visible = self.visible
    @family_outline_sprite.opacity = self.opacity

    # Sync zoom properties for switch-in/out animations
    @family_outline_sprite.zoom_x = self.zoom_x if self.respond_to?(:zoom_x)
    @family_outline_sprite.zoom_y = self.zoom_y if self.respond_to?(:zoom_y)

    # Sync angle for rotation animations (if any)
    @family_outline_sprite.angle = self.angle if self.respond_to?(:angle)

    # Sync color/tone for switch-in/out pink animation
    @family_outline_sprite.color = self.color.clone if self.respond_to?(:color) && self.color
    @family_outline_sprite.tone = self.tone.clone if self.respond_to?(:tone) && self.tone
  end

  # Hook dispose to clean up outline
  alias family_original_dispose dispose
  def dispose
    dispose_family_outline
    family_original_dispose
  end

  # Clean up outline resources
  def dispose_family_outline
    # Dispose transparent bitmap
    if @family_transparent_bitmap
      @family_transparent_bitmap.dispose
      @family_transparent_bitmap = nil
    end

    # Dispose composite sprite
    if @family_outline_sprite
      @family_outline_sprite.bitmap.dispose if @family_outline_sprite.bitmap
      @family_outline_sprite.dispose
      @family_outline_sprite = nil
    end

    # Dispose cached outline mask
    if @family_outline_mask
      @family_outline_mask.dispose
      @family_outline_mask = nil
    end

    # Dispose cached Pokemon bitmap
    if @family_pkmn_bitmap
      @family_pkmn_bitmap.dispose
      @family_pkmn_bitmap = nil
    end

    # Clear outline width
    @family_outline_width = nil
  end
end

#-------------------------------------------------------------------------------
# Pokemon Data Box - overlays custom font name sprite on top of default name
#-------------------------------------------------------------------------------
class PokemonDataBox < SpriteWrapper
  attr_reader :family_name_sprite

  # Hook initialize to create name sprite
  alias family_original_initialize initialize
  def initialize(*args)
    family_original_initialize(*args)
    @family_name_sprite = nil
    @family_current_pokemon = nil
    @family_name_frame_counter = 0
    @family_name_effect = nil
    @family_name_colors = nil
    @family_name_outline_canvas = nil
    @family_name_text_canvas = nil
    @family_init_done = true
    @family_was_visible = false
    @family_slide_frame = 0
    @family_slide_direction = 0  # 0=not sliding, 1=slide in, -1=slide out
    @family_prev_battler = nil
  end

  # Check if this Pokemon should show family overlay
  def should_show_family_overlay?
    return false unless @family_init_done
    return false unless @battler && @battler.pokemon

    # Check if Family Font is enabled in settings
    if defined?($PokemonSystem) && $PokemonSystem && $PokemonSystem.respond_to?(:mp_family_font_enabled)
      return false if $PokemonSystem.mp_family_font_enabled == 0
    end

    # Show for all Pokemon (player, allies, and enemies)
    # Line removed: return false if @battler.opposes?(0)  # Now showing for opponent Pokemon too!

    return @battler.pokemon.respond_to?(:has_family?) && @battler.pokemon.has_family?
  end

  # Hook refresh to create/update family name overlay and hide default elements
  alias family_original_refresh refresh
  def refresh
    # Call original refresh first
    family_original_refresh

    # Check if family overlay should be shown
    if !should_show_family_overlay?
      dispose_family_name_overlay
      @family_current_pokemon = nil
      return
    end

    # Hide default name, gender, level, shiny icon by clearing those regions
    hide_default_databox_elements

    # Detect Pokemon change - recreate overlay if different Pokemon
    if @battler && @battler.pokemon && @family_current_pokemon != @battler.pokemon
      dispose_family_name_overlay
      @family_current_pokemon = @battler.pokemon
      create_family_name_overlay
    elsif !@family_name_sprite
      # Create if doesn't exist
      @family_current_pokemon = @battler.pokemon
      create_family_name_overlay
    end
  end

  # Hide default databox elements (name, gender, level, shiny) by clearing bitmap regions
  def hide_default_databox_elements
    return unless self.bitmap

    # Clear name area
    self.bitmap.fill_rect(@spriteBaseX+8, 9, 120, 20, Color.new(0, 0, 0, 0))

    # Clear gender area
    self.bitmap.fill_rect(@spriteBaseX+118, 0, 20, 35, Color.new(0, 0, 0, 0))

    # Clear shiny icon area
    if @battler.opposes?(0)
      # Foe's shiny icon (right side)
      self.bitmap.fill_rect(@spriteBaseX+190, -5, 30, 35, Color.new(0, 0, 0, 0))
    else
      # Player's shiny icon (left side)
      self.bitmap.fill_rect(@spriteBaseX-15, -5, 30, 35, Color.new(0, 0, 0, 0))
    end
  end

  # Create sprite overlay with custom font + outline for Pokemon name
  def create_family_name_overlay
    return unless @battler && @battler.pokemon

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("FAMILY-CREATE-OVERLAY", "Creating overlay for #{@battler.pokemon.name} (idx #{@battler.index}), family=#{@battler.pokemon.family}, has_family=#{@battler.pokemon.has_family?}")
    end

    effect = PokemonFamilyConfig.get_family_effect(@battler.pokemon.family)
    colors = PokemonFamilyConfig.get_subfamily_colors(@battler.pokemon.family, @battler.pokemon.subfamily)
    return unless effect && colors

    font_name = PokemonFamilyConfig.get_family_font(@battler.pokemon.family)
    saved_font = MessageConfig.pbGetSystemFontName
    MessageConfig.pbSetSystemFontName(font_name)

    # Create sprite overlay at same position as data box name
    @family_name_sprite = Sprite.new(self.viewport)
    @family_name_sprite.x = self.x + @spriteBaseX + 8
    @family_name_sprite.y = self.y + 12  # Lowered 10px (was 2)
    @family_name_sprite.z = self.z + 10  # High z to be on top

    # Create text with outline (same approach as summary screen)
    test_canvas = Bitmap.new(120, 32)
    test_canvas.font.size = 24
    text_width = test_canvas.text_size(@battler.pokemon.name).width
    max_width = 116

    if text_width > max_width
      scale_factor = max_width.to_f / text_width
      test_canvas.font.size = (24 * scale_factor).floor
      test_canvas.font.size = [test_canvas.font.size, 14].max
    end

    final_font_size = test_canvas.font.size
    test_canvas.dispose

    # Create outline layer (2px offset in all directions)
    outline_canvas = Bitmap.new(124, 36)
    outline_canvas.font.name = font_name  # Set font name on bitmap
    outline_canvas.font.size = final_font_size
    outline_offsets = [
      [-2,-2], [-1,-2], [0,-2], [1,-2], [2,-2],
      [-2,-1], [-1,-1], [0,-1], [1,-1], [2,-1],
      [-2,0],  [-1,0],          [1,0],  [2,0],
      [-2,1],  [-1,1],  [0,1],  [1,1],  [2,1],
      [-2,2],  [-1,2],  [0,2],  [1,2],  [2,2]
    ]
    outline_offsets.each do |ox, oy|
      outline_canvas.draw_text(2 + ox, 2 + oy, 120, 32, @battler.pokemon.name, 0)
    end

    # Store effect and colors for animation
    @family_name_effect = effect
    @family_name_colors = colors
    @family_name_outline_canvas = outline_canvas  # Keep for animation
    @family_name_frame_counter = 0

    # Create main text layer (static)
    @family_name_text_canvas = Bitmap.new(124, 36)
    @family_name_text_canvas.font.name = font_name
    @family_name_text_canvas.font.size = final_font_size
    font_color = PokemonFamilyConfig.hex_to_color(colors[0])
    @family_name_text_canvas.font.color = font_color
    @family_name_text_canvas.draw_text(2, 2, 120, 32, @battler.pokemon.name, 0)

    # Create initial composite (will be updated in update loop)
    @family_name_sprite.bitmap = Bitmap.new(124, 36)

    # Restore font
    MessageConfig.pbSetSystemFontName(saved_font)

    if defined?(MultiplayerDebug)
      #MultiplayerDebug.info("FAMILY-DATABOX", "Created name overlay for #{@battler.pokemon.name} with font #{font_name}")
    end
  end

  # Hook update to sync position every frame (idle animation)
  alias family_original_update update
  def update(*args)
    family_original_update(*args)
    update_family_name_overlay
  end

  # Update family name overlay position and animation every frame
  def update_family_name_overlay
    return unless @family_name_sprite
    return unless @family_name_outline_canvas && @family_name_text_canvas

    # Detect battler change OR visibility change and trigger slide animation
    # Battler change = early warning for switch out (before visible=false)
    if @battler != @family_prev_battler && @family_prev_battler != nil && self.visible
      # Battler changed while visible - start slide out NOW
      @family_slide_direction = -1
      @family_slide_frame = 0
    elsif self.visible && !@family_was_visible
      # Became visible - slide in
      @family_slide_direction = 1
      @family_slide_frame = 0
    elsif !self.visible && @family_was_visible && @family_slide_direction != -1
      # Became hidden (fallback if battler change wasn't detected)
      @family_slide_direction = -1
      @family_slide_frame = 0
    end
    @family_was_visible = self.visible
    @family_prev_battler = @battler

    # Calculate base position
    base_x = self.x + @spriteBaseX + 8
    base_y = self.y + 12

    # Apply slide animation
    slide_offset = 0
    if @family_slide_direction != 0
      @family_slide_frame += 1

      # Determine slide direction based on battler index (player vs foe)
      dir = (@battler && @battler.index % 2 == 0) ? 1 : -1

      if @family_slide_direction == 1
        # Sliding in: 16 frames (slow)
        progress = @family_slide_frame / 16.0
        max_frames = 16
        # Start at +width/2 (right), end at 0
        slide_offset = (Graphics.width / 2.0) * (1.0 - progress)
        @family_name_sprite.visible = true
        if @family_slide_frame >= max_frames
          @family_slide_direction = 0  # Animation complete
        end
      else
        # Sliding out: 16 frames (same speed as slide in)
        progress = @family_slide_frame / 16.0
        max_frames = 16
        # Start at 0, end at +width/2 (right)
        slide_offset = (Graphics.width / 2.0) * progress
        @family_name_sprite.visible = true
        if @family_slide_frame >= max_frames
          @family_slide_direction = 0  # Animation complete
          @family_name_sprite.visible = false
        end
      end
    else
      # Not animating - sync visibility
      @family_name_sprite.visible = self.visible
    end

    @family_name_sprite.x = base_x + slide_offset
    @family_name_sprite.y = base_y
    @family_name_sprite.z = self.z + 10
    @family_name_sprite.opacity = self.opacity
    @family_name_sprite.color = self.color if self.respond_to?(:color)

    # Animate outline every 3 frames (20 FPS)
    @family_name_frame_counter += 1
    return unless @family_name_frame_counter % 3 == 0

    begin
      # Generate animated outline for current frame
      animated_outline = FamilyOutlineEffects.apply_effect(
        @family_name_effect,
        @family_name_outline_canvas,
        @family_name_colors,
        @family_name_frame_counter
      )

      # Composite: outline + text
      @family_name_sprite.bitmap.clear
      @family_name_sprite.bitmap.blt(0, 0, animated_outline, Rect.new(0, 0, 124, 36))
      @family_name_sprite.bitmap.blt(0, 0, @family_name_text_canvas, Rect.new(0, 0, 124, 36))

      # Cleanup temp bitmap
      animated_outline.dispose
    rescue => e
      if defined?(MultiplayerDebug) && @family_name_frame_counter % 60 == 0
        MultiplayerDebug.error("FAMILY-NAME-ANIM", "Animation failed: #{e.message}")
      end
    end
  end

  # Clean up overlay sprite
  def dispose_family_name_overlay
    # Dispose cached canvases
    if @family_name_outline_canvas
      @family_name_outline_canvas.dispose
      @family_name_outline_canvas = nil
    end
    if @family_name_text_canvas
      @family_name_text_canvas.dispose
      @family_name_text_canvas = nil
    end

    # Dispose sprite
    if @family_name_sprite
      @family_name_sprite.bitmap.dispose if @family_name_sprite.bitmap
      @family_name_sprite.dispose
      @family_name_sprite = nil
    end

    @family_name_effect = nil
    @family_name_colors = nil
  end

  # Hook dispose to clean up name sprite
  alias family_original_dispose dispose
  def dispose
    dispose_family_name_overlay
    family_original_dispose
  end
end

# Module loaded successfully
if defined?(MultiplayerDebug)
  #MultiplayerDebug.info("FAMILY-BATTLE", "=" * 60)
  #MultiplayerDebug.info("FAMILY-BATTLE", "105_Family_Battle_Sprites.rb loaded successfully")
  #MultiplayerDebug.info("FAMILY-BATTLE", "Hooked PokemonBattlerSprite for outline effects")
  #MultiplayerDebug.info("FAMILY-BATTLE", "Hooked PokemonDataBox for custom fonts")
  #MultiplayerDebug.info("FAMILY-BATTLE", "Family Pokemon will display with:")
  #MultiplayerDebug.info("FAMILY-BATTLE", "  - Animated outline effect on sprite")
  #MultiplayerDebug.info("FAMILY-BATTLE", "  - Custom family font in nameplate")
  #MultiplayerDebug.info("FAMILY-BATTLE", "=" * 60)
end
