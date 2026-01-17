#===============================================================================
# MODULE: Family/Subfamily System - Summary Screen Integration
#===============================================================================
# Hooks PokemonSummary_Scene to display family effects in Pokemon Details screen.
#
# Integration Points:
#   1. pbStartScene - creates outline sprite behind Pokemon sprite
#   2. pbUpdate - animates the outline effect every frame
#   3. drawPage - applies custom font to Pokemon name + draws badge icon
#   4. pbEndScene - cleans up outline sprite
#
# Badge Icons:
#   - Expected path: Graphics/Pictures/Summary/family_badge_0.png through family_badge_31.png
#   - Index = family * 4 + subfamily (0-31)
#   - Placeholder logic: skips badge if file missing (no crash)
#===============================================================================

# METHOD TOGGLE: Set to true for pixel-expansion outline, false for size-difference outline
USE_PIXEL_EXPANSION = true

class PokemonSummary_Scene
  # Hook pbStartScene to create outline sprite + name sprite
  alias family_original_pbStartScene pbStartScene
  def pbStartScene(*args)
    family_original_pbStartScene(*args)

    @family_outline_sprite = nil
    @family_name_sprite = nil
    @family_frame_counter = 0

    if defined?(MultiplayerDebug)
      #MultiplayerDebug.info("FAMILY-SUMMARY", "Summary scene started for #{@pokemon.name}")
    end

    create_summary_family_outline
    create_summary_family_name
  end

  # Create outline sprite behind Pokemon sprite in summary screen
  def create_summary_family_outline
    return unless @pokemon && @pokemon.has_family?

    effect = PokemonFamilyConfig.get_family_effect(@pokemon.family)
    colors = PokemonFamilyConfig.get_subfamily_colors(@pokemon.family, @pokemon.subfamily)

    unless effect && colors
      if defined?(MultiplayerDebug)
        #MultiplayerDebug.warn("FAMILY-SUMMARY", "Missing effect or colors for #{@pokemon.name}")
      end
      return
    end

    if defined?(MultiplayerDebug)
      #MultiplayerDebug.info("FAMILY-SUMMARY", "Creating outline for #{@pokemon.name}: effect=#{effect}")
    end

    begin
      # Get Pokemon sprite bitmap
      pkmn_bitmap = @sprites["pokemon"].bitmap
      return unless pkmn_bitmap

      # Get sprite scale
      pkmn_sprite = @sprites["pokemon"]
      scale_x = pkmn_sprite.zoom_x rescue 1.0
      scale_y = pkmn_sprite.zoom_y rescue 1.0

      if USE_PIXEL_EXPANSION
        # === PIXEL EXPANSION METHOD (3px outline around every edge pixel) ===

        # Scale Pokemon to display size (66.67%)
        pkmn_display_w = (pkmn_bitmap.width * scale_x).round
        pkmn_display_h = (pkmn_bitmap.height * scale_y).round
        pkmn_scaled = Bitmap.new(pkmn_display_w, pkmn_display_h)
        pkmn_scaled.stretch_blt(Rect.new(0, 0, pkmn_display_w, pkmn_display_h), pkmn_bitmap, pkmn_bitmap.rect)

        # Create outline bitmap (3px padding on all sides)
        outline_width = 3
        final_w = pkmn_display_w + (outline_width * 2)
        final_h = pkmn_display_h + (outline_width * 2)
        @family_outline_mask = Bitmap.new(final_w, final_h)

        # Expand outline by drawing black pixels around every opaque pixel
        pkmn_display_w.times do |x|
          pkmn_display_h.times do |y|
            pixel = pkmn_scaled.get_pixel(x, y)
            if pixel.alpha > 0
              # Draw 3px outline around this pixel
              (-outline_width..outline_width).each do |dx|
                (-outline_width..outline_width).each do |dy|
                  dist = Math.sqrt(dx*dx + dy*dy)
                  if dist <= outline_width
                    outline_x = x + dx + outline_width
                    outline_y = y + dy + outline_width
                    if outline_x >= 0 && outline_x < final_w && outline_y >= 0 && outline_y < final_h
                      @family_outline_mask.set_pixel(outline_x, outline_y, Color.new(0, 0, 0, 255))
                    end
                  end
                end
              end
            end
          end
        end

        # Store Pokemon scaled bitmap to composite on top later (don't draw yet)
        @family_pkmn_scaled = pkmn_scaled
        @family_outline_width = outline_width

      else
        # === SIZE DIFFERENCE METHOD (75% silhouette with 66.67% Pokemon on top) ===

        # Scale to 75% (Pokemon displays at 66.67%, outline uses the 8.3% difference)
        outline_scale = 0.75
        final_w = (pkmn_bitmap.width * outline_scale).round
        final_h = (pkmn_bitmap.height * outline_scale).round

        # Create black silhouette at 75% scale
        @family_outline_mask = Bitmap.new(final_w, final_h)
        @family_outline_mask.stretch_blt(
          Rect.new(0, 0, final_w, final_h),
          pkmn_bitmap,
          pkmn_bitmap.rect
        )

        # Recolor to solid black
        final_w.times do |x|
          final_h.times do |y|
            pixel = @family_outline_mask.get_pixel(x, y)
            if pixel.alpha > 0
              @family_outline_mask.set_pixel(x, y, Color.new(0, 0, 0, 255))
            end
          end
        end

        # Draw Pokemon at 66.67% on top (creates visible outline ring)
        pkmn_display_w = (pkmn_bitmap.width * scale_x).round
        pkmn_display_h = (pkmn_bitmap.height * scale_y).round
        pkmn_scaled = Bitmap.new(pkmn_display_w, pkmn_display_h)
        pkmn_scaled.stretch_blt(Rect.new(0, 0, pkmn_display_w, pkmn_display_h), pkmn_bitmap, pkmn_bitmap.rect)

        # Center Pokemon on top of black silhouette
        offset_x = ((final_w - pkmn_display_w) / 2.0).round
        offset_y = ((final_h - pkmn_display_h) / 2.0).round
        @family_outline_mask.blt(offset_x, offset_y, pkmn_scaled, pkmn_scaled.rect)

        pkmn_scaled.dispose
      end

      # Create sprite (already scaled to correct size, no zoom needed)
      @family_outline_sprite = Sprite.new(@sprites["pokemon"].viewport)

      # No scaling - outline mask is already at display size
      @family_outline_sprite.zoom_x = 1.0
      @family_outline_sprite.zoom_y = 1.0

      # Center both sprites
      @family_outline_sprite.ox = (final_w / 2.0).round
      @family_outline_sprite.oy = (final_h / 2.0).round

      # Position at same x,y as Pokemon
      @family_outline_sprite.x = @sprites["pokemon"].x
      @family_outline_sprite.y = @sprites["pokemon"].y
      @family_outline_sprite.z = @sprites["pokemon"].z + 1  # On top of Pokemon
      @family_outline_sprite.visible = true
      @family_outline_sprite.opacity = 255

      # Apply initial color effect to outline mask
      @family_outline_sprite.bitmap = apply_outline_color_effect(effect, colors, 0)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("OUTLINE-DEBUG", "=" * 60)
        MultiplayerDebug.info("OUTLINE-DEBUG", "Created: visible=#{@family_outline_sprite.visible} z=#{@family_outline_sprite.z}")
        MultiplayerDebug.info("OUTLINE-DEBUG", "Bitmap: #{@family_outline_sprite.bitmap ? 'EXISTS' : 'NIL'}")
        MultiplayerDebug.info("OUTLINE-DEBUG", "Mask ref: #{@family_outline_mask ? 'EXISTS' : 'NIL'}")
        MultiplayerDebug.info("OUTLINE-DEBUG", "Pokemon: x=#{@sprites['pokemon'].x} y=#{@sprites['pokemon'].y} ox=#{@sprites['pokemon'].ox} oy=#{@sprites['pokemon'].oy}")
        MultiplayerDebug.info("OUTLINE-DEBUG", "Outline: x=#{@family_outline_sprite.x} y=#{@family_outline_sprite.y} ox=#{@family_outline_sprite.ox} oy=#{@family_outline_sprite.oy}")
        MultiplayerDebug.info("OUTLINE-DEBUG", "=" * 60)
      end
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("FAMILY-SUMMARY-OUTLINE", "Failed to create outline: #{e.class}: #{e.message}")
        MultiplayerDebug.error("FAMILY-SUMMARY-OUTLINE", e.backtrace[0, 3].join("\n"))
      end
      @family_outline_sprite = nil
      @family_outline_mask = nil
    end
  end

  # Apply color effect to Pokemon outline using FamilyOutlineEffects (filled silhouette)
  def apply_outline_color_effect(effect, colors, frame)
    return @family_outline_mask unless @family_outline_mask

    # Apply animated effect to filled silhouette (recolors all black pixels)
    animated_outline = FamilyOutlineEffects.apply_effect_filled(effect, @family_outline_mask, colors, frame)

    # Composite Pokemon sprite on top of animated outline
    if @family_pkmn_scaled && @family_outline_width
      animated_outline.blt(@family_outline_width, @family_outline_width, @family_pkmn_scaled, @family_pkmn_scaled.rect)
    end

    return animated_outline
  end

  # Hook pbUpdate to animate outline on BOTH Pokemon sprite AND name
  alias family_original_pbUpdate pbUpdate
  def pbUpdate
    family_original_pbUpdate

    # Update family outline animation (throttled to every 3 frames for performance)
    if @pokemon && @pokemon.has_family?
      @family_frame_counter ||= 0
      @family_frame_counter += 1

      # Log outline state every 60 frames
      if defined?(MultiplayerDebug) && @family_frame_counter % 60 == 0
        MultiplayerDebug.info("OUTLINE-UPDATE", "Sprite: #{@family_outline_sprite ? 'EXISTS' : 'NIL'}, Visible: #{@family_outline_sprite ? @family_outline_sprite.visible : 'N/A'}")
      end

      # Only update every 3 frames to reduce lag
      if @family_frame_counter % 3 == 0
        begin
          effect = PokemonFamilyConfig.get_family_effect(@pokemon.family)
          colors = PokemonFamilyConfig.get_subfamily_colors(@pokemon.family, @pokemon.subfamily)

          # Update Pokemon outline sprite
          if @family_outline_sprite && @family_outline_sprite.bitmap
            old_bitmap = @family_outline_sprite.bitmap
            @family_outline_sprite.bitmap = apply_outline_color_effect(effect, colors, @family_frame_counter)
            old_bitmap.dispose
          end

          # Update name sprite outline (regenerate entire composite)
          if @family_name_sprite
            update_family_name_animation(effect, colors)
          end
        rescue => e
          if defined?(MultiplayerDebug) && @family_frame_counter % 60 == 0
            #MultiplayerDebug.error("FAMILY-SUMMARY", "Outline update failed: #{e.message}")
          end
        end
      end
    end
  end

  # Regenerate name sprite with animated outline
  def update_family_name_animation(effect, colors)
    font_name = PokemonFamilyConfig.get_family_font(@pokemon.family)

    # Create test bitmap to measure font size
    test_canvas = Bitmap.new(200, 32)
    test_canvas.font.name = font_name
    test_canvas.font.size = 29

    # Measure text width and scale down if needed
    text_width = test_canvas.text_size(@pokemon.name).width
    max_width = 154  # Max width before badge area

    if text_width > max_width
      scale_factor = max_width.to_f / text_width
      test_canvas.font.size = (29 * scale_factor).floor
      test_canvas.font.size = [test_canvas.font.size, 16].max
    end

    final_font_size = test_canvas.font.size
    test_canvas.dispose

    # Create outline text (SAME font size, drawn with offsets for thickness)
    outline_canvas = Bitmap.new(204, 36)  # Slightly larger canvas for outline bleeding
    outline_canvas.font.name = font_name
    outline_canvas.font.size = final_font_size

    # Draw outline with 2px offset in all directions
    outline_offsets = [
      [-2,-2], [-1,-2], [0,-2], [1,-2], [2,-2],
      [-2,-1], [-1,-1], [0,-1], [1,-1], [2,-1],
      [-2,0],  [-1,0],          [1,0],  [2,0],
      [-2,1],  [-1,1],  [0,1],  [1,1],  [2,1],
      [-2,2],  [-1,2],  [0,2],  [1,2],  [2,2]
    ]
    outline_offsets.each do |ox, oy|
      outline_canvas.draw_text(2 + ox, 2 + oy, 200, 32, @pokemon.name, 0)
    end

    # Apply animated effect to outline
    animated_outline = FamilyOutlineEffects.apply_effect(effect, outline_canvas, colors, @family_frame_counter)

    # Create main text (same font size, centered at same position)
    name_canvas = Bitmap.new(204, 36)
    name_canvas.font.name = font_name
    name_canvas.font.size = final_font_size
    font_color = PokemonFamilyConfig.hex_to_color(colors[0])
    name_canvas.font.color = font_color
    name_canvas.draw_text(2, 2, 200, 32, @pokemon.name, 0)

    # Create composite: animated outline + normal text
    final_bmp = Bitmap.new(204, 36)
    final_bmp.blt(0, 0, animated_outline, Rect.new(0, 0, 204, 36))
    final_bmp.blt(0, 0, name_canvas, Rect.new(0, 0, 204, 36))

    # Replace old bitmap
    @family_name_sprite.bitmap.dispose if @family_name_sprite.bitmap
    @family_name_sprite.bitmap = final_bmp

    # Cleanup temp bitmaps
    outline_canvas.dispose
    animated_outline.dispose
    name_canvas.dispose
  end

  # Create separate name sprite with custom font + outline
  def create_summary_family_name
    return unless @pokemon && @pokemon.has_family?

    # Check if Family Font is enabled in settings
    if defined?($PokemonSystem) && $PokemonSystem && $PokemonSystem.respond_to?(:mp_family_font_enabled)
      return if $PokemonSystem.mp_family_font_enabled == 0
    end

    effect = PokemonFamilyConfig.get_family_effect(@pokemon.family)
    colors = PokemonFamilyConfig.get_subfamily_colors(@pokemon.family, @pokemon.subfamily)
    return unless effect && colors

    if defined?(MultiplayerDebug)
      #MultiplayerDebug.info("FAMILY-SUMMARY", "Creating family name sprite for #{@pokemon.name}")
    end

    begin
      # Create sprite for name text (use same viewport as overlay)
      viewport = @sprites["overlay"] ? @sprites["overlay"].viewport : nil
      @family_name_sprite = Sprite.new(viewport)
      @family_name_sprite.x = 14  # Centered without Pokeball (was 46)
      @family_name_sprite.y = 60  # Adjusted from 56 to 60 for better vertical centering
      @family_name_sprite.z = 100  # High z to be on top

      # Get font name
      font_name = PokemonFamilyConfig.get_family_font(@pokemon.family)

      if defined?(MultiplayerDebug)
        #MultiplayerDebug.info("FAMILY-SUMMARY", "Creating name sprite with font: #{font_name.inspect}")
      end

      # Create test bitmap to measure font size
      test_canvas = Bitmap.new(200, 32)
      test_canvas.font.name = font_name
      test_canvas.font.size = 29

      # Measure text width and scale down if needed
      text_width = test_canvas.text_size(@pokemon.name).width
      max_width = 154  # Max width before badge area

      if text_width > max_width
        scale_factor = max_width.to_f / text_width
        test_canvas.font.size = (29 * scale_factor).floor
        test_canvas.font.size = [test_canvas.font.size, 16].max

        if defined?(MultiplayerDebug)
          #MultiplayerDebug.info("FAMILY-SUMMARY", "Scaled font: #{text_width}px -> #{max_width}px (size #{test_canvas.font.size})")
        end
      end

      final_font_size = test_canvas.font.size
      test_canvas.dispose

      # Create outline text (SAME font size, drawn with offsets for thickness)
      outline_canvas = Bitmap.new(204, 36)  # Slightly larger canvas for outline bleeding
      outline_canvas.font.name = font_name
      outline_canvas.font.size = final_font_size

      # Draw outline with 2px offset in all directions
      outline_offsets = [
        [-2,-2], [-1,-2], [0,-2], [1,-2], [2,-2],
        [-2,-1], [-1,-1], [0,-1], [1,-1], [2,-1],
        [-2,0],  [-1,0],          [1,0],  [2,0],
        [-2,1],  [-1,1],  [0,1],  [1,1],  [2,1],
        [-2,2],  [-1,2],  [0,2],  [1,2],  [2,2]
      ]
      outline_offsets.each do |ox, oy|
        outline_canvas.draw_text(2 + ox, 2 + oy, 200, 32, @pokemon.name, 0)
      end

      # Apply animated effect to outline
      animated_outline = FamilyOutlineEffects.apply_effect(effect, outline_canvas, colors, 0)

      # Create main text (same font size, centered at same position)
      name_canvas = Bitmap.new(204, 36)
      name_canvas.font.name = font_name
      name_canvas.font.size = final_font_size
      font_color = PokemonFamilyConfig.hex_to_color(colors[0])
      name_canvas.font.color = font_color
      name_canvas.draw_text(2, 2, 200, 32, @pokemon.name, 0)

      if defined?(MultiplayerDebug)
        #MultiplayerDebug.info("FAMILY-SUMMARY", "Font: #{name_canvas.font.name.inspect} @ #{final_font_size}px, Color: #{colors[0]}")
      end

      # Create final composite bitmap (animated outline + text)
      final_bmp = Bitmap.new(204, 36)
      final_bmp.blt(0, 0, animated_outline, Rect.new(0, 0, 204, 36))
      final_bmp.blt(0, 0, name_canvas, Rect.new(0, 0, 204, 36))

      @family_name_sprite.bitmap = final_bmp

      # Cleanup temp bitmaps
      outline_canvas.dispose
      animated_outline.dispose
      name_canvas.dispose

      if defined?(MultiplayerDebug)
        #MultiplayerDebug.info("FAMILY-SUMMARY", "Name sprite created with font: #{font_name}")
      end
    rescue => e
      if defined?(MultiplayerDebug)
        #MultiplayerDebug.error("FAMILY-SUMMARY", "Failed to create name sprite: #{e.message}")
        #MultiplayerDebug.error("FAMILY-SUMMARY", "Backtrace: #{e.backtrace.first(3).join(' | ')}")
      end
      @family_name_sprite = nil
    end
  end

  # Helper to check if family font effects should be shown
  def should_show_family_font?
    return false unless @pokemon && @pokemon.has_family?
    # Check if Family Font is enabled in settings
    if defined?($PokemonSystem) && $PokemonSystem && $PokemonSystem.respond_to?(:mp_family_font_enabled)
      return $PokemonSystem.mp_family_font_enabled != 0
    end
    return true  # Default to enabled
  end

  # Hook drawPageOne to hide original name text
  alias family_original_drawPageOne drawPageOne
  def drawPageOne
    # Call original to draw everything normally
    family_original_drawPageOne

    # Hide original name + Pokeball if has family AND font is enabled (our sprite will replace it)
    if should_show_family_font?
      overlay = @sprites["overlay"].bitmap

      # Hide Pokeball icon (drawn at x=14, y=60)
      overlay.fill_rect(14, 60, 40, 40, Color.new(0, 0, 0, 0))

      # Hide original name text
      overlay.fill_rect(46, 56, 200, 32, Color.new(0, 0, 0, 0))

      # Draw badge
      draw_family_badge(overlay)
    end
  end

  # Hook drawPageTwo (Trainer Memo) to hide original name text + Pokeball
  alias family_original_drawPageTwo drawPageTwo
  def drawPageTwo
    family_original_drawPageTwo
    if should_show_family_font?
      overlay = @sprites["overlay"].bitmap
      overlay.fill_rect(14, 60, 40, 40, Color.new(0, 0, 0, 0))  # Hide Pokeball
      overlay.fill_rect(46, 56, 200, 32, Color.new(0, 0, 0, 0))  # Hide name
    end
  end

  # Hook drawPageThree (Skills) to hide original name text + Pokeball
  alias family_original_drawPageThree drawPageThree
  def drawPageThree
    family_original_drawPageThree
    if should_show_family_font?
      overlay = @sprites["overlay"].bitmap
      overlay.fill_rect(14, 60, 40, 40, Color.new(0, 0, 0, 0))  # Hide Pokeball
      overlay.fill_rect(46, 56, 200, 32, Color.new(0, 0, 0, 0))  # Hide name
    end
  end

  # Hook drawPageFour (Moves) to hide original name text + Pokeball
  alias family_original_drawPageFour drawPageFour
  def drawPageFour
    family_original_drawPageFour
    if should_show_family_font?
      overlay = @sprites["overlay"].bitmap
      overlay.fill_rect(14, 60, 40, 40, Color.new(0, 0, 0, 0))  # Hide Pokeball
      overlay.fill_rect(46, 56, 200, 32, Color.new(0, 0, 0, 0))  # Hide name
    end
  end

  # Draw family badge icon on summary overlay
  # Badge location: (210, 56) - right side below Pokemon name
  def draw_family_badge(overlay)
    subfamily_idx = PokemonFamilyConfig.get_subfamily_index(@pokemon.family, @pokemon.subfamily)
    badge_file = sprintf("Graphics/Pictures/Summary/family_badge_%d", subfamily_idx)

    # Check if badge file exists (placeholder logic - no crash if missing)
    badge_path_png = badge_file + ".png"
    unless File.exist?(badge_path_png)
      if defined?(MultiplayerDebug)
        #MultiplayerDebug.warn("FAMILY-SUMMARY", "Badge file not found: #{badge_path_png} - skipping")
      end
      return
    end

    begin
      # Draw badge at (210, 56) - right side below name
      imagepos = [[badge_file, 210, 56]]
      pbDrawImagePositions(overlay, imagepos)

      if defined?(MultiplayerDebug)
        #MultiplayerDebug.info("FAMILY-SUMMARY", "Badge drawn: #{badge_file} at (210, 56)")
      end
    rescue => e
      if defined?(MultiplayerDebug)
        #MultiplayerDebug.error("FAMILY-SUMMARY", "Failed to draw badge: #{e.message}")
      end
    end
  end

  # Hook pbEndScene to clean up outline sprite + name sprite
  alias family_original_pbEndScene pbEndScene
  def pbEndScene
    # Dispose cached Pokemon scaled bitmap
    if @family_pkmn_scaled
      @family_pkmn_scaled.dispose
      @family_pkmn_scaled = nil
    end

    # Dispose outline mask (cached outline shape)
    if @family_outline_mask
      @family_outline_mask.dispose
      @family_outline_mask = nil
    end

    # Dispose outline sprite
    if @family_outline_sprite
      @family_outline_sprite.bitmap.dispose if @family_outline_sprite.bitmap
      @family_outline_sprite.dispose
      @family_outline_sprite = nil
    end

    # Dispose name sprite
    if @family_name_sprite
      @family_name_sprite.bitmap.dispose if @family_name_sprite.bitmap
      @family_name_sprite.dispose
      @family_name_sprite = nil
    end

    if defined?(MultiplayerDebug)
      #MultiplayerDebug.info("FAMILY-SUMMARY", "Family sprites disposed")
    end

    # Call original
    family_original_pbEndScene
  end
end

# Module loaded successfully
if defined?(MultiplayerDebug)
  #MultiplayerDebug.info("FAMILY-SUMMARY", "=" * 60)
  #MultiplayerDebug.info("FAMILY-SUMMARY", "106_Family_Summary_UI.rb loaded successfully")
  #MultiplayerDebug.info("FAMILY-SUMMARY", "Hooked PokemonSummary_Scene for:")
  #MultiplayerDebug.info("FAMILY-SUMMARY", "  - Animated outline effect on Pokemon sprite")
  #MultiplayerDebug.info("FAMILY-SUMMARY", "  - Custom family font in Pokemon name")
  #MultiplayerDebug.info("FAMILY-SUMMARY", "  - Family badge icon at (210, 56)")
  #MultiplayerDebug.info("FAMILY-SUMMARY", "Badge path: Graphics/Pictures/Summary/family_badge_0.png to family_badge_31.png")
  #MultiplayerDebug.info("FAMILY-SUMMARY", "Placeholder logic: Skips badge if file missing (no crash)")
  #MultiplayerDebug.info("FAMILY-SUMMARY", "=" * 60)
end
