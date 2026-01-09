#===============================================================================
# MODULE: Family/Subfamily System - Outline Effect Renderers
#===============================================================================
# 8 unique outline effects for Pokemon sprites and text.
# Each family has a distinct animated effect applied to outlines.
#
# Effects:
#   0. Primordium: Inner glow pulse + subtle expanding ripple
#   1. Vacuum: Flicker static + color inversion on outline
#   2. Astrum: Twinkling stars along stroke, gradient shimmer
#   3. Silva: Soft bioluminescent pulse (green)
#   4. Machina: Neon glow / circuit pulse
#   5. Humanitas: Faint parchment-shadow stroke (static)
#   6. Aetheris: Soft glow + pulsing light
#   7. Infernum: Flickering flame gradient
#
# NO rand() calls - all effects use frame_counter for deterministic animation.
#===============================================================================

module FamilyOutlineEffects
  # Base outline generator - draws colored silhouette at 8-directional offsets
  # Uses 5-color gradient palette from subfamily config
  # @param source_bitmap [Bitmap] The original sprite/text bitmap
  # @param colors [Array<String>] Array of 5 hex color strings
  # @param frame_counter [Integer] Current frame for animation (not used in base)
  # @return [Bitmap] Outline bitmap with gradient
  def self.generate_base_outline(source_bitmap, colors, frame_counter)
    if defined?(MultiplayerDebug)
      ##MultiplayerDebug.info("FAMILY-EFFECT", "Generating outline: #{source_bitmap.width}x#{source_bitmap.height}, Colors: #{colors.length}")
    end

    outline_bitmap = Bitmap.new(source_bitmap.width, source_bitmap.height)

    # Convert hex colors to Color objects
    color_objects = colors.map { |hex| PokemonFamilyConfig.hex_to_color(hex) }

    # 8-directional offsets for outline (1px thickness)
    offsets = [[-1,0], [1,0], [0,-1], [0,1], [-1,-1], [1,-1], [-1,1], [1,1]]

    # Count pixels drawn for debugging
    pixels_drawn = 0

    # Draw outline by checking each pixel
    for x in 0...source_bitmap.width
      for y in 0...source_bitmap.height
        pixel = source_bitmap.get_pixel(x, y)

        # Skip if current pixel is transparent (we only want opaque edge pixels)
        next if pixel.alpha < 128

        # Check if any neighbor is transparent (edge detection)
        is_edge = false
        offsets.each do |ox, oy|
          check_x = x + ox
          check_y = y + oy
          next if check_x < 0 || check_x >= source_bitmap.width
          next if check_y < 0 || check_y >= source_bitmap.height

          neighbor = source_bitmap.get_pixel(check_x, check_y)
          if neighbor.alpha < 128
            is_edge = true
            break
          end
        end

        # Draw outline pixel if this opaque pixel is next to a transparent pixel
        if is_edge
          gradient_index = (y.to_f / outline_bitmap.height * color_objects.length).floor
          gradient_index = [gradient_index, color_objects.length - 1].min
          color = color_objects[gradient_index]

          outline_bitmap.set_pixel(x, y, Color.new(color.red, color.green, color.blue, 255))
          pixels_drawn += 1
        end
      end
    end

    if defined?(MultiplayerDebug)
      ##MultiplayerDebug.info("FAMILY-EFFECT", "Outline generated: #{pixels_drawn} pixels drawn")
    end

    return outline_bitmap
  end

  #-----------------------------------------------------------------------------
  # Effect 0: Inner glow pulse (Primordium)
  # Gentle pulsing glow effect (70% to 100% opacity, slow cycle)
  # Note: Returns bitmap with alpha modulation applied to pixels
  #-----------------------------------------------------------------------------
  def self.inner_glow_pulse(source_bitmap, colors, frame_counter)
    outline = generate_base_outline(source_bitmap, colors, frame_counter)

    # Slow pulse using sine wave (60 frames = 1 second cycle at 60 FPS)
    pulse = Math.sin(frame_counter * Math::PI / 60.0) * 0.3 + 0.7  # Range: 0.4 to 1.0
    opacity_value = (255 * pulse).to_i

    # Apply opacity by modulating alpha channel of all pixels
    for x in 0...outline.width
      for y in 0...outline.height
        pixel = outline.get_pixel(x, y)
        next if pixel.alpha == 0
        outline.set_pixel(x, y, Color.new(pixel.red, pixel.green, pixel.blue, (pixel.alpha * pulse).to_i))
      end
    end

    if defined?(MultiplayerDebug) && frame_counter % 60 == 0
      #MultiplayerDebug.info("FAMILY-EFFECT", "Primordium pulse: #{(pulse * 100).to_i}%")
    end

    return outline
  end

  #-----------------------------------------------------------------------------
  # Effect 1: Flicker static (Vacuum)
  # Irregular flicker pattern (deterministic via frame_counter, NO rand())
  #-----------------------------------------------------------------------------
  def self.flicker_static(source_bitmap, colors, frame_counter)
    outline = generate_base_outline(source_bitmap, colors, frame_counter)

    # Deterministic pseudo-random flicker using frame_counter (no rand() calls)
    # Creates irregular flicker pattern between 50% and 100% opacity
    # Using prime number (31) to create non-repeating pattern
    pseudo_random = ((frame_counter * 31) % 128) + 128  # Range: 128-255
    opacity_factor = pseudo_random / 255.0

    # Apply opacity by modulating alpha channel
    for x in 0...outline.width
      for y in 0...outline.height
        pixel = outline.get_pixel(x, y)
        next if pixel.alpha == 0
        outline.set_pixel(x, y, Color.new(pixel.red, pixel.green, pixel.blue, (pixel.alpha * opacity_factor).to_i))
      end
    end

    if defined?(MultiplayerDebug) && frame_counter % 60 == 0
      #MultiplayerDebug.info("FAMILY-EFFECT", "Vacuum flicker: opacity=#{pseudo_random}")
    end

    return outline
  end

  #-----------------------------------------------------------------------------
  # Effect 2: Twinkling stars (Astrum)
  # Fast pulsing shimmer effect (60% to 100% opacity)
  # TODO: Add star particles along outline stroke for enhanced effect
  #-----------------------------------------------------------------------------
  def self.twinkling_stars(source_bitmap, colors, frame_counter)
    outline = generate_base_outline(source_bitmap, colors, frame_counter)

    # Fast pulse (30 frames = 0.5 second cycle)
    pulse = Math.sin(frame_counter * Math::PI / 30.0) * 0.4 + 0.6  # Range: 0.2 to 1.0

    # Apply opacity by modulating alpha channel
    for x in 0...outline.width
      for y in 0...outline.height
        pixel = outline.get_pixel(x, y)
        next if pixel.alpha == 0
        outline.set_pixel(x, y, Color.new(pixel.red, pixel.green, pixel.blue, (pixel.alpha * pulse).to_i))
      end
    end

    if defined?(MultiplayerDebug) && frame_counter % 60 == 0
      #MultiplayerDebug.info("FAMILY-EFFECT", "Astrum twinkle: #{(pulse * 100).to_i}%")
    end

    return outline
  end

  #-----------------------------------------------------------------------------
  # Effect 3: Bioluminescent (Silva)
  # Soft, slow green pulse (80% to 100% opacity, very gentle)
  #-----------------------------------------------------------------------------
  def self.bioluminescent(source_bitmap, colors, frame_counter)
    outline = generate_base_outline(source_bitmap, colors, frame_counter)

    # Very slow pulse (90 frames = 1.5 second cycle)
    pulse = Math.sin(frame_counter * Math::PI / 90.0) * 0.2 + 0.8  # Range: 0.6 to 1.0

    # Apply opacity by modulating alpha channel
    for x in 0...outline.width
      for y in 0...outline.height
        pixel = outline.get_pixel(x, y)
        next if pixel.alpha == 0
        outline.set_pixel(x, y, Color.new(pixel.red, pixel.green, pixel.blue, (pixel.alpha * pulse).to_i))
      end
    end

    if defined?(MultiplayerDebug) && frame_counter % 60 == 0
      #MultiplayerDebug.info("FAMILY-EFFECT", "Silva bioluminescent: #{(pulse * 100).to_i}%")
    end

    return outline
  end

  #-----------------------------------------------------------------------------
  # Effect 4: Neon circuit (Machina)
  # Fast pulse simulating electric current (50% to 100% opacity)
  #-----------------------------------------------------------------------------
  def self.neon_circuit(source_bitmap, colors, frame_counter)
    outline = generate_base_outline(source_bitmap, colors, frame_counter)

    # Fast electric pulse (20 frames = 0.33 second cycle)
    pulse = Math.sin(frame_counter * Math::PI / 20.0) * 0.5 + 0.5  # Range: 0.0 to 1.0

    # Apply opacity by modulating alpha channel
    for x in 0...outline.width
      for y in 0...outline.height
        pixel = outline.get_pixel(x, y)
        next if pixel.alpha == 0
        outline.set_pixel(x, y, Color.new(pixel.red, pixel.green, pixel.blue, (pixel.alpha * pulse).to_i))
      end
    end

    if defined?(MultiplayerDebug) && frame_counter % 60 == 0
      #MultiplayerDebug.info("FAMILY-EFFECT", "Machina neon: #{(pulse * 100).to_i}%")
    end

    return outline
  end

  #-----------------------------------------------------------------------------
  # Effect 5: Parchment shadow (Humanitas)
  # Static, faint outline (no animation, 50% opacity)
  #-----------------------------------------------------------------------------
  def self.parchment_shadow(source_bitmap, colors, frame_counter)
    outline = generate_base_outline(source_bitmap, colors, frame_counter)

    # Static outline - no animation, 50% opacity
    opacity_factor = 0.5

    # Apply opacity by modulating alpha channel
    for x in 0...outline.width
      for y in 0...outline.height
        pixel = outline.get_pixel(x, y)
        next if pixel.alpha == 0
        outline.set_pixel(x, y, Color.new(pixel.red, pixel.green, pixel.blue, (pixel.alpha * opacity_factor).to_i))
      end
    end

    if defined?(MultiplayerDebug) && frame_counter % 120 == 0
      #MultiplayerDebug.info("FAMILY-EFFECT", "Humanitas parchment: static 50%")
    end

    return outline
  end

  #-----------------------------------------------------------------------------
  # Effect 6: Pulsing light (Aetheris)
  # Gentle, radiant pulse (70% to 100% opacity)
  #-----------------------------------------------------------------------------
  def self.pulsing_light(source_bitmap, colors, frame_counter)
    outline = generate_base_outline(source_bitmap, colors, frame_counter)

    # Medium-speed pulse (45 frames = 0.75 second cycle)
    pulse = Math.sin(frame_counter * Math::PI / 45.0) * 0.3 + 0.7  # Range: 0.4 to 1.0

    # Apply opacity by modulating alpha channel
    for x in 0...outline.width
      for y in 0...outline.height
        pixel = outline.get_pixel(x, y)
        next if pixel.alpha == 0
        outline.set_pixel(x, y, Color.new(pixel.red, pixel.green, pixel.blue, (pixel.alpha * pulse).to_i))
      end
    end

    if defined?(MultiplayerDebug) && frame_counter % 60 == 0
      #MultiplayerDebug.info("FAMILY-EFFECT", "Aetheris pulse: #{(pulse * 100).to_i}%")
    end

    return outline
  end

  #-----------------------------------------------------------------------------
  # Effect 7: Flickering flame (Infernum)
  # Irregular flicker simulating fire (combines two sine waves)
  #-----------------------------------------------------------------------------
  def self.flickering_flame(source_bitmap, colors, frame_counter)
    outline = generate_base_outline(source_bitmap, colors, frame_counter)

    # Irregular flicker using two overlapping sine waves
    flicker = Math.sin(frame_counter * Math::PI / 15.0) * 0.3 +
              Math.sin(frame_counter * Math::PI / 10.0) * 0.2 + 0.5
    flicker = [flicker, 1.0].min  # Clamp to max 1.0

    # Apply opacity by modulating alpha channel
    for x in 0...outline.width
      for y in 0...outline.height
        pixel = outline.get_pixel(x, y)
        next if pixel.alpha == 0
        outline.set_pixel(x, y, Color.new(pixel.red, pixel.green, pixel.blue, (pixel.alpha * flicker).to_i))
      end
    end

    if defined?(MultiplayerDebug) && frame_counter % 60 == 0
      #MultiplayerDebug.info("FAMILY-EFFECT", "Infernum flame: #{(flicker * 100).to_i}%")
    end

    return outline
  end

  #-----------------------------------------------------------------------------
  # Main dispatcher - routes to appropriate effect based on effect_type
  # @param effect_type [Symbol] Effect identifier (:inner_glow_pulse, etc.)
  # @param source_bitmap [Bitmap] Source sprite/text bitmap
  # @param colors [Array<String>] 5 hex color strings for gradient
  # @param frame_counter [Integer] Current animation frame
  # @return [Bitmap, nil] Outline bitmap or nil if effect not found
  #-----------------------------------------------------------------------------
  def self.apply_effect(effect_type, source_bitmap, colors, frame_counter)
    if defined?(MultiplayerDebug)
      ##MultiplayerDebug.info("FAMILY-EFFECT", "Applying effect: #{effect_type} (frame #{frame_counter})")
    end

    result = case effect_type
    when :inner_glow_pulse then inner_glow_pulse(source_bitmap, colors, frame_counter)
    when :flicker_static then flicker_static(source_bitmap, colors, frame_counter)
    when :twinkling_stars then twinkling_stars(source_bitmap, colors, frame_counter)
    when :bioluminescent then bioluminescent(source_bitmap, colors, frame_counter)
    when :neon_circuit then neon_circuit(source_bitmap, colors, frame_counter)
    when :parchment_shadow then parchment_shadow(source_bitmap, colors, frame_counter)
    when :pulsing_light then pulsing_light(source_bitmap, colors, frame_counter)
    when :flickering_flame then flickering_flame(source_bitmap, colors, frame_counter)
    else
      if defined?(MultiplayerDebug)
        #MultiplayerDebug.error("FAMILY-EFFECT", "Unknown effect type: #{effect_type}")
      end
      nil
    end

    if defined?(MultiplayerDebug) && result
      ##MultiplayerDebug.info("FAMILY-EFFECT", "Effect applied: #{effect_type}")
    end

    return result
  end

  #-----------------------------------------------------------------------------
  # Apply effect to filled silhouette (recolor all black pixels with gradient + effect)
  # Used for Pokemon sprite outline (filled shape, not just edges)
  # @param effect_type [Symbol] Effect identifier
  # @param source_bitmap [Bitmap] Black silhouette bitmap (filled)
  # @param colors [Array<String>] 5 hex color strings for gradient
  # @param frame_counter [Integer] Current animation frame
  # @return [Bitmap] Colored + animated silhouette
  #-----------------------------------------------------------------------------
  def self.apply_effect_filled(effect_type, source_bitmap, colors, frame_counter)
    result = Bitmap.new(source_bitmap.width, source_bitmap.height)

    # Convert hex colors to Color objects
    color_objects = colors.map { |hex| PokemonFamilyConfig.hex_to_color(hex) }

    # Calculate animation factor based on effect type
    animation_factor = case effect_type
    when :inner_glow_pulse
      Math.sin(frame_counter * Math::PI / 60.0) * 0.3 + 0.7  # 0.4 to 1.0
    when :flicker_static
      (((frame_counter * 31) % 128) + 128) / 255.0  # 0.5 to 1.0
    when :twinkling_stars
      Math.sin(frame_counter * Math::PI / 30.0) * 0.4 + 0.6  # 0.2 to 1.0
    when :bioluminescent
      Math.sin(frame_counter * Math::PI / 90.0) * 0.2 + 0.8  # 0.6 to 1.0
    when :neon_circuit
      Math.sin(frame_counter * Math::PI / 20.0) * 0.5 + 0.5  # 0.0 to 1.0
    when :parchment_shadow
      0.5  # Static 50%
    when :pulsing_light
      Math.sin(frame_counter * Math::PI / 45.0) * 0.3 + 0.7  # 0.4 to 1.0
    when :flickering_flame
      flicker = Math.sin(frame_counter * Math::PI / 15.0) * 0.3 +
                Math.sin(frame_counter * Math::PI / 10.0) * 0.2 + 0.5
      [flicker, 1.0].min
    else
      1.0
    end

    # Recolor all black pixels with gradient + animation
    source_bitmap.width.times do |x|
      source_bitmap.height.times do |y|
        pixel = source_bitmap.get_pixel(x, y)

        # Only recolor opaque black pixels
        if pixel.alpha > 0
          # Apply vertical gradient
          gradient_index = (y.to_f / source_bitmap.height * color_objects.length).floor
          gradient_index = [gradient_index, color_objects.length - 1].min
          color = color_objects[gradient_index]

          # Apply animation opacity
          final_alpha = (255 * animation_factor).to_i
          result.set_pixel(x, y, Color.new(color.red, color.green, color.blue, final_alpha))
        end
      end
    end

    return result
  end
end

# Module loaded successfully
if defined?(MultiplayerDebug)
  #MultiplayerDebug.info("FAMILY-EFFECT", "=" * 60)
  #MultiplayerDebug.info("FAMILY-EFFECT", "104_Family_Outline_Effects.rb loaded successfully")
  #MultiplayerDebug.info("FAMILY-EFFECT", "8 outline effects registered:")
  #MultiplayerDebug.info("FAMILY-EFFECT", "  0. inner_glow_pulse (Primordium) - gentle pulse")
  #MultiplayerDebug.info("FAMILY-EFFECT", "  1. flicker_static (Vacuum) - irregular flicker")
  #MultiplayerDebug.info("FAMILY-EFFECT", "  2. twinkling_stars (Astrum) - fast shimmer")
  #MultiplayerDebug.info("FAMILY-EFFECT", "  3. bioluminescent (Silva) - soft green pulse")
  #MultiplayerDebug.info("FAMILY-EFFECT", "  4. neon_circuit (Machina) - electric pulse")
  #MultiplayerDebug.info("FAMILY-EFFECT", "  5. parchment_shadow (Humanitas) - static outline")
  #MultiplayerDebug.info("FAMILY-EFFECT", "  6. pulsing_light (Aetheris) - radiant pulse")
  #MultiplayerDebug.info("FAMILY-EFFECT", "  7. flickering_flame (Infernum) - fire flicker")
  #MultiplayerDebug.info("FAMILY-EFFECT", "NO rand() calls - deterministic animations only")
  #MultiplayerDebug.info("FAMILY-EFFECT", "=" * 60)
end
