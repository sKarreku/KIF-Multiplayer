#===============================================================================
# MODULE: Resonance Core - Family/Subfamily Selection UI
#===============================================================================
# A full-screen carousel UI for picking a Family, then a Subfamily.
# Layout (from user mockup):
#   - Animated starry background with custom BGM
#   - Center: large circle showing the currently selected option
#   - Flanking: smaller circles for adjacent options (perspective scaling)
#   - Below center: info rectangle with details
#   - Left/Right to cycle with smooth slide animation
#   - USE to confirm (zoom-in to subfamilies), BACK to cancel (zoom-out)
#
# Reused for both Family selection (8 options) and Subfamily selection (4 options).
#===============================================================================

class ResonanceCoreUI_Scene
  # Circle layout: [offset_from_center_x, y, radius, opacity]
  # Index 0 = center, 1 = right adjacent, 2 = left adjacent, 3 = right far, 4 = left far
  CIRCLE_LAYOUT = [
    { dx:    0, y: 155, radius: 80, opacity: 255 },  # Center (selected)
    { dx:  155, y: 175, radius: 55, opacity: 130 },  # Right adjacent
    { dx: -155, y: 175, radius: 55, opacity: 130 },  # Left adjacent
    { dx:  275, y: 195, radius: 30, opacity: 70 },   # Right far
    { dx: -275, y: 195, radius: 30, opacity: 70 },   # Left far
  ]

  INFO_RECT = { width: 280, height: 130, y: 300 }

  # Thematic taglines for each family (indexed 0-7)
  FAMILY_TAGLINES = {
    0 => "The origin of all things. Creation and destruction intertwined.",
    1 => "Born from silence. Where nothing exists, everything is possible.",
    2 => "Children of the cosmos. Guided by distant starlight.",
    3 => "Rooted in the living world. Nature's eternal cycle.",
    4 => "Forged in iron and lightning. Progress never stops.",
    5 => "Shaped by will and purpose. The strength of civilization.",
    6 => "Woven from wind and light. Grace beyond mortal reach.",
    7 => "Tempered in hellfire. Power that consumes all."
  }

  # Per-family circle style overrides (only used in :family mode)
  # Keys: fill, border, glow, font  (all [r, g, b])
  # If a family is not listed here, colors are derived from subfamily palette
  FAMILY_CIRCLE_STYLES = {
    0 => { fill: [255, 255, 255], border: [210, 180, 60],  glow: [255, 215, 80],  font: [120, 120, 120] },  # Primordium: white fill, golden edge, grey text
    1 => { fill: [50, 50, 50],    border: [10, 10, 10],    glow: [100, 100, 100],  font: [220, 220, 220] },  # Vacuum: dark grey fill, black edge
    6 => { fill: [60, 40, 100],   border: [140, 100, 200], glow: [180, 140, 255],  font: [230, 210, 255] },  # Aetheris: deep purple fill, lavender edge
    7 => { fill: [180, 60, 10],   border: [255, 140, 30],  glow: [255, 160, 50],   font: [255, 240, 220] },  # Infernum: dark orange fill, bright orange edge
  }

  STAR_COUNT       = 80
  TWINKLE_SPEED    = 0.05
  SLIDE_FRAMES     = 10    # Duration of slide animation in frames
  ZOOM_FRAMES      = 18    # Duration of zoom in/out animation in frames

  # BGM to play during selection (place file in Audio/BGM/)
  # Set to nil to keep the current map BGM playing
  SELECTION_BGM    = "donteverforget"  # Change to your preferred track
  SELECTION_VOLUME = 80

  def initialize
    @selected = 0
    @items = []
    @mode = :family
    @stars = []
    @frame = 0
    # Animation state
    @slide_progress = 0.0   # 0.0 = idle, -1.0..1.0 = sliding left/right
    @slide_direction = 0    # -1 = left, +1 = right
    @slide_frame = 0
    @zoom_progress = 0.0    # 0.0 = normal, 1.0 = fully zoomed in/out
    @zoom_type = nil         # :zoom_in, :zoom_out, nil
    @zoom_frame = 0
    @old_bgm = nil
    # Particle effects
    @particles = []
    @particle_timer = 0
    @fx_opacity = 0           # Current fx layer opacity (0-255)
    @fx_target_opacity = 0    # Target opacity (fades toward this)
    @fx_fade_speed = 15       # Opacity change per frame
  end

  def pbStartScene(items, mode = :family, skip_bgm: false, shared_stars: nil, starting_index: 0, no_fade_in: false, viewport_z: 99999)
    @items = items
    @mode = mode
    @selected = starting_index.clamp(0, [items.size - 1, 0].max)
    @frame = 0
    @slide_progress = 0.0
    @zoom_progress = 0.0
    @zoom_type = nil

    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = viewport_z
    @sprites = {}

    # Background layer (starry sky)
    @sprites["bg"] = Sprite.new(@viewport)
    @sprites["bg"].bitmap = Bitmap.new(Graphics.width, Graphics.height)

    # Circles layer
    @sprites["circles"] = Sprite.new(@viewport)
    @sprites["circles"].bitmap = Bitmap.new(Graphics.width, Graphics.height)

    # Info panel layer
    @sprites["info"] = Sprite.new(@viewport)
    @sprites["info"].bitmap = Bitmap.new(Graphics.width, Graphics.height)

    # Effects layer (drawn between circles and info, above circles)
    @sprites["fx"] = Sprite.new(@viewport)
    @sprites["fx"].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprites["fx"].z = 1  # Above circles

    # Title layer
    @sprites["title"] = Sprite.new(@viewport)
    @sprites["title"].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprites["title"].z = 2  # Above fx

    # Reset particles
    @particles = []
    @particle_timer = 0

    # Generate or reuse stars
    if shared_stars
      @stars = shared_stars
    else
      generate_stars
    end

    # BGM
    unless skip_bgm
      if SELECTION_BGM
        @old_bgm = $game_system.playing_bgm.clone if $game_system.playing_bgm
        pbBGMPlay(SELECTION_BGM, SELECTION_VOLUME)
      end
    end

    # Initial draw
    draw_background
    draw_title
    refresh_display

    if no_fade_in
      # Show instantly (used when appearing behind a zoom-out transition)
      @sprites.each_value { |s| s.visible = true if s }
    else
      pbFadeInAndShow(@sprites)
    end
  end

  def generate_stars
    @stars = []
    STAR_COUNT.times do
      @stars << {
        x: rand(Graphics.width),
        y: rand(Graphics.height),
        base_brightness: rand(80) + 120,
        phase: rand(628) / 100.0,
        size: rand(3) == 0 ? 2 : 1,
        twinkle_amp: rand(40) + 30,
        speed: 0.02 + rand(80) / 1000.0  # Each star twinkles at its own pace
      }
    end
  end

  attr_reader :stars

  def draw_background
    draw_stars(@sprites["bg"].bitmap)
  end

  def draw_stars(bmp)
    bmp.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(5, 5, 20))
    @stars.each do |star|
      twinkle = Math.sin(star[:phase] + @frame * star[:speed])
      brightness = (star[:base_brightness] + twinkle * star[:twinkle_amp]).to_i
      brightness = [[brightness, 0].max, 255].min
      color = Color.new(brightness, brightness, (brightness * 1.1).to_i.clamp(0, 255))
      bmp.fill_rect(star[:x], star[:y], star[:size], star[:size], color)
    end
  end

  def draw_title
    bmp = @sprites["title"].bitmap
    bmp.clear
    title = (@mode == :family) ? "Choose a Family" : "Choose a Subfamily"
    bmp.font.size = 26
    bmp.font.bold = true
    bmp.font.color = Color.new(255, 255, 255)
    bmp.draw_text(0, 20, Graphics.width, 32, title, 2)

    # Hint text - top left
    bmp.font.size = 14
    bmp.font.bold = false
    bmp.font.color = Color.new(160, 160, 170)
    hint = (@mode == :family) ? "[X] Cancel" :
                                "[X] Back"
    bmp.draw_text(12, Graphics.height - 30, Graphics.width, 18, hint, 0)
  end

  def refresh_display
    draw_circles
    draw_info_panel
  end

  #=============================================================================
  # Slide animation
  #=============================================================================
  def start_slide(direction)
    @slide_direction = direction  # -1 = items shift right (selected moves left), +1 = opposite
    @slide_frame = 0
    @slide_progress = 0.0
  end

  def animating_slide?
    @slide_frame > 0 && @slide_frame <= SLIDE_FRAMES
  end

  def update_slide
    return unless @slide_frame > 0 && @slide_frame <= SLIDE_FRAMES
    @slide_frame += 1
    # Ease-out: fast start, slow end
    t = @slide_frame.to_f / SLIDE_FRAMES
    @slide_progress = ease_out(t) * @slide_direction
    draw_circles_animated
    draw_info_panel
    if @slide_frame > SLIDE_FRAMES
      # Commit the selection change
      @selected = (@selected + @slide_direction) % @items.length
      @slide_progress = 0.0
      @slide_frame = 0
      @slide_direction = 0
      refresh_display
    end
  end

  #=============================================================================
  # Zoom animation
  #=============================================================================
  def start_zoom(type)
    @zoom_type = type  # :zoom_in or :zoom_out
    @zoom_frame = 1
    @zoom_progress = 0.0
  end

  def animating_zoom?
    @zoom_type != nil && @zoom_frame > 0 && @zoom_frame <= ZOOM_FRAMES
  end

  def zoom_finished?
    @zoom_type != nil && @zoom_frame > ZOOM_FRAMES
  end

  def update_zoom
    return unless @zoom_type && @zoom_frame > 0 && @zoom_frame <= ZOOM_FRAMES
    @zoom_frame += 1
    t = @zoom_frame.to_f / ZOOM_FRAMES
    @zoom_progress = ease_in_out(t)

    case @zoom_type
    when :zoom_in
      # Scale up center circle, fade out others, fade to white
      scale = 1.0 + @zoom_progress * 2.0
      alpha = (255 * (1.0 - @zoom_progress)).to_i.clamp(0, 255)
      @sprites["circles"].opacity = alpha
      @sprites["info"].opacity = alpha
      @sprites["title"].opacity = alpha
      @sprites["circles"].zoom_x = scale
      @sprites["circles"].zoom_y = scale
      @sprites["circles"].ox = Graphics.width / 2
      @sprites["circles"].oy = 155
      @sprites["circles"].x = Graphics.width / 2
      @sprites["circles"].y = 155
    when :zoom_out
      # Reverse: scale down from large, fade in
      scale = 3.0 - @zoom_progress * 2.0
      alpha = (255 * @zoom_progress).to_i.clamp(0, 255)
      @sprites["circles"].opacity = alpha
      @sprites["info"].opacity = alpha
      @sprites["title"].opacity = alpha
      @sprites["circles"].zoom_x = [scale, 1.0].max
      @sprites["circles"].zoom_y = [scale, 1.0].max
      @sprites["circles"].ox = Graphics.width / 2
      @sprites["circles"].oy = 155
      @sprites["circles"].x = Graphics.width / 2
      @sprites["circles"].y = 155
    when :shrink_out
      # Exit: shrink toward center and fade out (used when backing out)
      scale = 1.0 - @zoom_progress * 0.5   # 1.0 -> 0.5
      alpha = (255 * (1.0 - @zoom_progress)).to_i.clamp(0, 255)
      @sprites["circles"].opacity = alpha
      @sprites["info"].opacity = alpha
      @sprites["title"].opacity = alpha
      @sprites["fx"].opacity = alpha
      @sprites["bg"].opacity = alpha
      @sprites["circles"].zoom_x = scale
      @sprites["circles"].zoom_y = scale
      @sprites["circles"].ox = Graphics.width / 2
      @sprites["circles"].oy = 155
      @sprites["circles"].x = Graphics.width / 2
      @sprites["circles"].y = 155
    end
  end

  def reset_zoom
    @zoom_type = nil
    @zoom_frame = 0
    @zoom_progress = 0.0
    @sprites["circles"].zoom_x = 1.0
    @sprites["circles"].zoom_y = 1.0
    @sprites["circles"].ox = 0
    @sprites["circles"].oy = 0
    @sprites["circles"].x = 0
    @sprites["circles"].y = 0
    @sprites["circles"].opacity = 255
    @sprites["info"].opacity = 255
    @sprites["title"].opacity = 255
  end

  #=============================================================================
  # Easing functions
  #=============================================================================
  def ease_out(t)
    1.0 - (1.0 - t) ** 2
  end

  def ease_in_out(t)
    t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2.0
  end

  #=============================================================================
  # Draw carousel circles (with optional slide offset)
  #=============================================================================
  def draw_circles
    draw_circles_at_offset(0.0)
  end

  def draw_circles_animated
    draw_circles_at_offset(@slide_progress)
  end

  def draw_circles_at_offset(slide_offset)
    bmp = @sprites["circles"].bitmap
    bmp.clear
    cx = Graphics.width / 2

    # For sliding, we interpolate between current and next positions
    # slide_offset: 0 = current, +1 = fully shifted right, -1 = fully shifted left
    n = @items.length
    return if n == 0

    # Draw all visible slots with interpolated positions
    # We need to show items at positions: selected-2, selected-1, selected, selected+1, selected+2
    # During animation, these shift by slide_offset
    visible_range = n > 3 ? (-2..2) : (n > 1 ? (-1..1) : (0..0))

    # Collect draw data sorted by distance from center (draw far ones first)
    draw_list = []

    visible_range.each do |offset|
      item_idx = (@selected + offset) % n

      # During slide, the effective position shifts
      effective_pos = offset - slide_offset

      # Interpolate layout properties based on effective position
      abs_pos = effective_pos.abs

      # Skip if too far out
      next if abs_pos > 2.5

      # Interpolate between layout positions
      layout = interpolate_layout(effective_pos)
      next unless layout

      draw_list << {
        item_idx: item_idx,
        x: cx + layout[:dx],
        y: layout[:y],
        radius: layout[:radius],
        opacity: layout[:opacity],
        abs_pos: abs_pos,
        is_selected: abs_pos < 0.3
      }
    end

    # Sort by abs_pos descending (far circles drawn first = behind)
    draw_list.sort_by! { |d| -d[:abs_pos] }

    draw_list.each do |d|
      draw_one_circle(bmp, d[:x].to_i, d[:y].to_i, d[:radius].to_i,
                      @items[d[:item_idx]], d[:is_selected], d[:opacity].to_i)
    end
  end

  def interpolate_layout(pos)
    # pos is a float: 0 = center, +/-1 = adjacent, +/-2 = far
    abs_pos = pos.abs
    sign = pos >= 0 ? 1.0 : -1.0

    if abs_pos <= 1.0
      # Interpolate between center (0) and adjacent (1)
      t = abs_pos
      center = CIRCLE_LAYOUT[0]
      adjacent = CIRCLE_LAYOUT[1]  # right adjacent (positive dx)
      {
        dx: lerp(center[:dx], adjacent[:dx] * sign, t),
        y:  lerp(center[:y],  adjacent[:y],  t),
        radius: lerp(center[:radius], adjacent[:radius], t),
        opacity: lerp(center[:opacity], adjacent[:opacity], t)
      }
    elsif abs_pos <= 2.0
      # Interpolate between adjacent (1) and far (2)
      t = abs_pos - 1.0
      adjacent = CIRCLE_LAYOUT[1]
      far = CIRCLE_LAYOUT[3]
      {
        dx: lerp(adjacent[:dx] * sign, far[:dx] * sign, t),
        y:  lerp(adjacent[:y],  far[:y],  t),
        radius: lerp(adjacent[:radius], far[:radius], t),
        opacity: lerp(adjacent[:opacity], far[:opacity], t)
      }
    else
      # Beyond far - fade out
      t = abs_pos - 2.0
      far = CIRCLE_LAYOUT[3]
      opacity = lerp(far[:opacity], 0, t.clamp(0.0, 1.0))
      return nil if opacity < 10
      {
        dx: far[:dx] * sign * (1.0 + t * 0.3),
        y:  far[:y],
        radius: [far[:radius] * (1.0 - t * 0.5), 10].max,
        opacity: opacity
      }
    end
  end

  def lerp(a, b, t)
    a + (b - a) * t
  end

  #=============================================================================
  # Draw a single circle
  #=============================================================================
  def draw_one_circle(bmp, cx, cy, radius, item, is_selected, opacity)
    return if radius < 5 || opacity < 5

    # Check for per-family style override (only in family mode)
    family_id = item[:id]
    style = (@mode == :family) ? FAMILY_CIRCLE_STYLES[family_id] : nil

    if style
      # Use explicit style override
      fill_color   = Color.new(style[:fill][0],   style[:fill][1],   style[:fill][2],   opacity)
      border_color = Color.new(style[:border][0], style[:border][1], style[:border][2], opacity)
      glow_rgb     = style[:glow]
      font_rgb     = style[:font]
    else
      # Derive from subfamily color palette
      colors = item[:colors] || ["#444444", "#666666", "#888888", "#AAAAAA", "#CCCCCC"]
      primary_color   = PokemonFamilyConfig.hex_to_color(colors[0])
      secondary_color = PokemonFamilyConfig.hex_to_color(colors[1])
      accent_color    = PokemonFamilyConfig.hex_to_color(colors[2])

      # Auto-fix for very bright palettes (catch-all for subfamilies)
      avg_brightness = (primary_color.red + primary_color.green + primary_color.blue) / 3.0
      if avg_brightness > 200
        fill_color   = Color.new(40, 30, 80, opacity)
        border_color = Color.new(primary_color.red, primary_color.green, primary_color.blue, opacity)
      else
        fill_color   = Color.new(primary_color.red, primary_color.green, primary_color.blue, opacity)
        border_color = Color.new(secondary_color.red, secondary_color.green, secondary_color.blue, opacity)
      end
      glow_rgb = [accent_color.red, accent_color.green, accent_color.blue]
      font_rgb = [255, 255, 255]
    end

    draw_filled_circle(bmp, cx, cy, radius, fill_color)
    draw_circle_outline(bmp, cx, cy, radius, border_color)
    draw_circle_outline(bmp, cx, cy, radius - 1, border_color)

    if is_selected
      glow_alpha = (180 + Math.sin(@frame * 0.08) * 50).to_i.clamp(100, 230)
      glow_color = Color.new(glow_rgb[0], glow_rgb[1], glow_rgb[2], glow_alpha)
      draw_circle_outline(bmp, cx, cy, radius + 2, glow_color)
      draw_circle_outline(bmp, cx, cy, radius + 3, glow_color)
      draw_circle_outline(bmp, cx, cy, radius + 4, glow_color)
    end

    # Text inside circle
    name = item[:name] || "???"
    font_size = is_selected ? 18 : (radius > 40 ? 14 : 10)
    bmp.font.size = font_size
    bmp.font.bold = is_selected

    text_w = bmp.text_size(name).width
    text_h = bmp.text_size(name).height
    tx = cx - (text_w / 2)
    ty = cy - (text_h / 2)

    # Shadow for contrast
    bmp.font.color = Color.new(0, 0, 0, opacity)
    bmp.draw_text(tx + 1, ty + 1, text_w + 4, text_h, name, 0)
    # Main text in family-specific color
    bmp.font.color = Color.new(font_rgb[0], font_rgb[1], font_rgb[2], opacity)
    bmp.draw_text(tx, ty, text_w + 4, text_h, name, 0)
  end

  #=============================================================================
  # Info panel below center circle
  #=============================================================================
  def draw_info_panel
    bmp = @sprites["info"].bitmap
    bmp.clear

    item = @items[@selected]
    return unless item

    rx = (Graphics.width - INFO_RECT[:width]) / 2
    ry = INFO_RECT[:y]
    rw = INFO_RECT[:width]
    rh = INFO_RECT[:height]

    # Background - dark panel
    bmp.fill_rect(rx, ry, rw, rh, Color.new(15, 10, 25, 210))

    # Border using item colors (with brightness fix for Primordium)
    colors = item[:colors] || ["#FF0000", "#FF4444"]
    border_col = PokemonFamilyConfig.hex_to_color(colors[1])
    avg_b = (border_col.red + border_col.green + border_col.blue) / 3.0
    if avg_b > 200
      # Bright border - use a golden accent instead
      border_col = Color.new(200, 180, 100)
    end
    bmp.fill_rect(rx, ry, rw, 2, border_col)
    bmp.fill_rect(rx, ry + rh - 2, rw, 2, border_col)
    bmp.fill_rect(rx, ry, 2, rh, border_col)
    bmp.fill_rect(rx + rw - 2, ry, 2, rh, border_col)

    # Title - use item color but ensure readability
    title_col = PokemonFamilyConfig.hex_to_color(colors[0])
    title_avg = (title_col.red + title_col.green + title_col.blue) / 3.0
    if title_avg > 200
      # For very bright families like Primordium Genesis, use golden text
      title_col = Color.new(255, 230, 150)
    end

    bmp.font.size = 20
    bmp.font.bold = true
    bmp.font.color = title_col
    bmp.draw_text(rx + 10, ry + 8, rw - 20, 24, item[:name], 2)

    # Details
    bmp.font.size = 14
    bmp.font.bold = false
    bmp.font.color = Color.new(220, 220, 220)

    if @mode == :family
      family_id = item[:id]
      talent_base = PokemonFamilyConfig.get_family_talent(family_id)
      talent_name = (GameData::Ability.get(talent_base).name rescue talent_base.to_s) if talent_base

      # Family tagline
      tagline = FAMILY_TAGLINES[family_id] || ""
      bmp.font.size = 13
      bmp.font.italic = true
      bmp.font.color = Color.new(200, 200, 210)
      bmp.draw_text(rx + 10, ry + 36, rw - 20, 18, tagline, 2)
      bmp.font.italic = false

      # Talent
      bmp.font.size = 14
      bmp.font.color = Color.new(220, 220, 220)
      bmp.draw_text(rx + 10, ry + 62, rw - 20, 18, "Talent: #{talent_name || 'None'}", 0)

      # Subfamily names
      bmp.font.size = 12
      bmp.font.color = Color.new(220, 220, 220)
      bmp.draw_text(rx + 10, ry + 86, rw - 20, 16, "Subfamilies:", 0)
      base_idx = family_id * 4
      sub_names = (0..3).map { |i| PokemonFamilyConfig::SUBFAMILIES[base_idx + i][:name] }
      bmp.font.color = Color.new(180, 180, 180)
      bmp.draw_text(rx + 10, ry + 102, rw - 20, 16, sub_names.join("  /  "), 0)
    else
      # Subfamily info
      subfamily_idx = item[:global_index]
      sub_data = PokemonFamilyConfig::SUBFAMILIES[subfamily_idx]

      bmp.draw_text(rx + 10, ry + 36, rw - 20, 18, "Color Palette:", 0)
      colors_arr = sub_data[:colors]
      swatch_w = 40
      swatch_h = 20
      start_x = rx + (rw - swatch_w * 5 - 4 * 4) / 2
      colors_arr.each_with_index do |hex, i|
        sx = start_x + i * (swatch_w + 4)
        sy = ry + 56
        col = PokemonFamilyConfig.hex_to_color(hex)
        bmp.fill_rect(sx, sy, swatch_w, swatch_h, col)
        bmp.fill_rect(sx, sy, swatch_w, 1, Color.new(255, 255, 255, 80))
        bmp.fill_rect(sx, sy + swatch_h - 1, swatch_w, 1, Color.new(0, 0, 0, 80))
      end

      bmp.font.color = Color.new(180, 180, 180)
      bmp.draw_text(rx + 10, ry + 82, rw - 20, 16, "Rarity weight: #{sub_data[:weight]}%", 0)
    end
  end

  #=============================================================================
  # Circle drawing helpers (midpoint circle algorithm)
  #=============================================================================
  def draw_filled_circle(bmp, cx, cy, radius, color)
    return if radius <= 0
    x = 0
    y = radius
    d = 1 - radius

    while x <= y
      draw_hline(bmp, cx - y, cx + y, cy + x, color)
      draw_hline(bmp, cx - y, cx + y, cy - x, color)
      draw_hline(bmp, cx - x, cx + x, cy + y, color)
      draw_hline(bmp, cx - x, cx + x, cy - y, color)
      if d < 0
        d += 2 * x + 3
      else
        d += 2 * (x - y) + 5
        y -= 1
      end
      x += 1
    end
  end

  def draw_hline(bmp, x1, x2, y, color)
    return if y < 0 || y >= bmp.height
    x1 = [x1, 0].max
    x2 = [x2, bmp.width - 1].min
    return if x1 > x2
    bmp.fill_rect(x1, y, x2 - x1 + 1, 1, color)
  end

  def draw_circle_outline(bmp, cx, cy, radius, color)
    return if radius <= 0
    x = 0
    y = radius
    d = 1 - radius

    while x <= y
      plot_circle_points(bmp, cx, cy, x, y, color)
      if d < 0
        d += 2 * x + 3
      else
        d += 2 * (x - y) + 5
        y -= 1
      end
      x += 1
    end
  end

  def plot_circle_points(bmp, cx, cy, x, y, color)
    points = [
      [cx + x, cy + y], [cx - x, cy + y],
      [cx + x, cy - y], [cx - x, cy - y],
      [cx + y, cy + x], [cx - y, cy + x],
      [cx + y, cy - x], [cx - y, cy - x]
    ]
    points.each do |px, py|
      next if px < 0 || px >= bmp.width || py < 0 || py >= bmp.height
      bmp.fill_rect(px, py, 1, 1, color)
    end
  end

  #=============================================================================
  # Primordium Genesis Pulse Effect
  #=============================================================================
  PRIMORDIUM_FAMILY_ID = 0
  PRIMORDIUM_MOTE_COUNT = 50        # Max motes alive
  PRIMORDIUM_SPAWN_RATE = 2         # Motes spawned per frame
  PRIMORDIUM_BREATH_SPEED = 0.025   # Speed of the breathing pulse

  def primordium_active?
    @mode == :family && @items[@selected] && @items[@selected][:id] == PRIMORDIUM_FAMILY_ID &&
      !animating_slide? && !animating_zoom?
  end

  def update_primordium(cx, cy, radius)
    return unless primordium_active?

    # Spawn motes - half radiate outward (creation), half drift inward (destruction)
    mote_count = @particles.count { |p| p[:type] == :genesis_mote }
    if mote_count < PRIMORDIUM_MOTE_COUNT
      PRIMORDIUM_SPAWN_RATE.times do
        angle = rand(628) / 100.0
        outward = rand(2) == 0  # 50% creation (out), 50% destruction (in)
        if outward
          # Spawn near circle edge, drift outward
          dist = radius + rand(8)
          spd = 0.3 + rand(10) / 10.0
        else
          # Spawn far out, drift inward
          dist = radius + 30 + rand(40)
          spd = -(0.2 + rand(8) / 10.0)
        end
        @particles << {
          type: :genesis_mote,
          angle: angle,
          dist: dist,
          start_dist: dist,
          speed: spd,                       # Radial speed (+ = out, - = in)
          angular_drift: (rand(20) - 10) / 1000.0,  # Slow orbital drift
          life: 0,
          max_life: 40 + rand(30),
          size: rand(4) == 0 ? 3 : (rand(3) == 0 ? 2 : 1),
          bright: rand(3) == 0              # 33% are extra bright golden
        }
      end
    end

    # Update motes
    @particles.each do |p|
      next unless p[:type] == :genesis_mote
      p[:life] += 1
      p[:dist] += p[:speed]
      p[:angle] += p[:angular_drift]
    end

    # Remove expired or out-of-range motes
    @particles.reject! do |p|
      p[:type] == :genesis_mote && (p[:life] >= p[:max_life] || p[:dist] < 5 || p[:dist] > radius + 90)
    end
  end

  def draw_primordium_fx(cx, cy, radius)
    bmp = @sprites["fx"].bitmap
    bmp.clear

    return if @particles.none? { |p| p[:type] == :genesis_mote }

    # Breathing golden aura - pulse ring that expands and contracts
    breath = Math.sin(@frame * PRIMORDIUM_BREATH_SPEED)
    breath_r = radius + 4 + (breath * 8).to_i
    breath_alpha = (40 + breath * 20).to_i.clamp(15, 65)
    glow_col = Color.new(255, 215, 80, breath_alpha)
    draw_circle_outline(bmp, cx, cy, breath_r, glow_col)
    draw_circle_outline(bmp, cx, cy, breath_r + 1, glow_col)

    # Soft warm halo
    2.times do |i|
      ring_r = radius + 2 + i * 5
      pulse = Math.sin(@frame * 0.03 + i * 1.5)
      alpha = (18 + pulse * 10).to_i.clamp(8, 38)
      halo_col = Color.new(255, 230, 150, alpha)
      draw_circle_outline(bmp, cx, cy, ring_r, halo_col)
    end

    # Draw motes
    @particles.each do |p|
      next unless p[:type] == :genesis_mote
      fade = 1.0 - (p[:life].to_f / p[:max_life])
      # Also fade based on distance from circle edge for smooth appearance
      edge_dist = (p[:dist] - radius).abs
      edge_fade = edge_dist < 10 ? edge_dist / 10.0 : 1.0
      alpha = (200 * fade * edge_fade).to_i.clamp(0, 200)
      next if alpha < 10

      px = (cx + Math.cos(p[:angle]) * p[:dist]).to_i
      py = (cy + Math.sin(p[:angle]) * p[:dist]).to_i
      next if px < 0 || px >= bmp.width || py < 0 || py >= bmp.height

      if p[:bright]
        # Bright golden mote
        col = Color.new(255, 230, 130, alpha)
      else
        # Soft warm white
        r = (240 * fade + 180 * (1.0 - fade)).to_i.clamp(0, 255)
        g = (220 * fade + 150 * (1.0 - fade)).to_i.clamp(0, 255)
        b = (160 * fade + 80 * (1.0 - fade)).to_i.clamp(0, 255)
        col = Color.new(r, g, b, alpha)
      end
      bmp.fill_rect(px, py, p[:size], p[:size], col)

      # Small sparkle on bright motes
      if p[:bright] && p[:size] >= 2 && alpha > 100
        bmp.fill_rect(px + 1, py + 1, 1, 1, Color.new(255, 255, 240, alpha))
      end
    end
  end

  #=============================================================================
  # Vacuum Event Horizon Effect
  #=============================================================================
  VACUUM_FAMILY_ID = 1
  VACUUM_PARTICLE_COUNT = 400       # Max particles alive at once
  VACUUM_SPAWN_BATCH = 8            # Particles spawned per frame
  VACUUM_PARTICLE_LIFE = 60         # Max lifetime in frames
  VACUUM_RING_LAYERS = 4            # Concentric distortion rings
  VACUUM_BLEND_RINGS = 10           # Gradient rings to blend circle edge

  def vacuum_active?
    @mode == :family && @items[@selected] && @items[@selected][:id] == VACUUM_FAMILY_ID &&
      !animating_slide? && !animating_zoom?
  end

  def spawn_vacuum_particle(cx, cy, radius)
    angle = rand(628) / 100.0
    # Spawn at a random distance outside the circle (1.3x to 2.0x radius)
    dist = radius * (1.3 + rand(70) / 100.0)
    @particles << {
      x: cx + Math.cos(angle) * dist,
      y: cy + Math.sin(angle) * dist,
      angle: angle,
      dist: dist,
      start_dist: dist,
      speed: 0.4 + rand(60) / 100.0,       # Inward speed (pixels/frame)
      angular_speed: 0.03 + rand(40) / 1000.0,  # Spiral rotation speed
      life: 0,
      max_life: VACUUM_PARTICLE_LIFE,
      size: rand(3) == 0 ? 3 : 2,
      brightness: rand(60) + 100        # Grey tone
    }
  end

  def update_vacuum_particles(cx, cy, radius)
    return unless vacuum_active?

    # Spawn batch of particles each frame
    if @particles.length < VACUUM_PARTICLE_COUNT
      spawn_count = [VACUUM_SPAWN_BATCH, VACUUM_PARTICLE_COUNT - @particles.length].min
      spawn_count.times { spawn_vacuum_particle(cx, cy, radius) }
    end

    # Update existing particles (skip non-vacuum particles from other effects)
    @particles.each do |p|
      next if p[:type]  # Skip Astrum orbiters/shooting stars
      p[:life] += 1
      # Spiral inward: decrease distance, rotate angle
      # Accelerate as they get closer (gravitational pull feel)
      pull = 1.0 + (1.0 - p[:dist] / p[:start_dist]) * 2.0
      p[:dist] -= p[:speed] * pull
      p[:angle] += p[:angular_speed] * pull
      p[:x] = cx + Math.cos(p[:angle]) * p[:dist]
      p[:y] = cy + Math.sin(p[:angle]) * p[:dist]
    end

    # Remove particles that reached center or expired (only vacuum ones)
    @particles.reject! { |p| !p[:type] && (p[:dist] <= 8 || p[:life] >= p[:max_life]) }
  end

  def draw_vacuum_fx(cx, cy, radius)
    bmp = @sprites["fx"].bitmap
    bmp.clear

    return if @particles.empty?

    # Blend circle edge into event horizon - gradient fade from circle fill outward
    # Uses the Vacuum fill color (dark grey 50,50,50) fading to transparent
    VACUUM_BLEND_RINGS.times do |i|
      t = i.to_f / VACUUM_BLEND_RINGS
      # Inner rings = more opaque, outer = transparent
      blend_alpha = ((1.0 - t) * 160).to_i.clamp(0, 255)
      # Slight purple tint as it fades out
      br = (50 + t * 20).to_i
      bg = (50 - t * 20).to_i.clamp(0, 255)
      bb = (50 + t * 40).to_i
      blend_color = Color.new(br, bg, bb, blend_alpha)
      ring_r = radius + i
      draw_circle_outline(bmp, cx, cy, ring_r, blend_color)
      draw_circle_outline(bmp, cx, cy, ring_r + 1, blend_color) if i < VACUUM_BLEND_RINGS - 1
    end

    # Distortion rings beyond the blend zone
    VACUUM_RING_LAYERS.times do |i|
      ring_r = radius + VACUUM_BLEND_RINGS + 2 + i * 5
      # Pulsing opacity based on frame
      pulse = Math.sin(@frame * 0.06 + i * 0.8)
      alpha = (40 + pulse * 20).to_i.clamp(15, 70)
      # Dark purple-grey rings
      ring_color = Color.new(30 + i * 8, 20 + i * 5, 50 + i * 10, alpha)
      draw_circle_outline(bmp, cx, cy, ring_r, ring_color)
      draw_circle_outline(bmp, cx, cy, ring_r + 1, ring_color)
    end

    # Accretion disc - bright ring at the outer blend edge
    disc_pulse = Math.sin(@frame * 0.04) * 0.3 + 0.7
    disc_alpha = (80 * disc_pulse).to_i.clamp(30, 100)
    disc_color = Color.new(120, 100, 140, disc_alpha)
    draw_circle_outline(bmp, cx, cy, radius + VACUUM_BLEND_RINGS + 1, disc_color)
    draw_circle_outline(bmp, cx, cy, radius + VACUUM_BLEND_RINGS + 2, disc_color)

    # Draw particles as small dots spiraling inward
    @particles.each do |p|
      # Fade out as they approach center
      fade = (p[:dist] / p[:start_dist]).clamp(0.0, 1.0)
      alpha = (p[:brightness] * fade).to_i.clamp(0, 255)
      next if alpha < 10

      px = p[:x].to_i
      py = p[:y].to_i
      next if px < 0 || px >= bmp.width || py < 0 || py >= bmp.height

      # Color: pale grey-blue, brightening as they fall in
      r = (80 + (1.0 - fade) * 80).to_i.clamp(0, 255)
      g = (70 + (1.0 - fade) * 60).to_i.clamp(0, 255)
      b = (120 + (1.0 - fade) * 100).to_i.clamp(0, 255)
      col = Color.new(r, g, b, alpha)
      bmp.fill_rect(px, py, p[:size], p[:size], col)
    end
  end

  def clear_fx
    @sprites["fx"].bitmap.clear if @sprites["fx"]
    @particles.clear
    @particle_timer = 0
    @silva_roots = nil
    @silva_flowers = nil
    @silva_grow_frame = 0
    @machina_gears = nil
    @machina_arcs = nil
    @humanitas_nodes = nil
    @humanitas_connections = nil
    @humanitas_pulses = nil
    @humanitas_pulse_timer = 0
    @aetheris_wisps = nil
    @infernum_flames = nil
    @fx_opacity = 0
    @fx_target_opacity = 0
    @sprites["fx"].opacity = 0 if @sprites["fx"]
  end

  #=============================================================================
  # Astrum Orbiting Stars Effect
  #=============================================================================
  ASTRUM_FAMILY_ID = 2
  ASTRUM_ORBIT_COUNT = 30             # Permanent orbiting stars
  ASTRUM_SHOOTING_STAR_CHANCE = 30    # 1 in N frames to spawn a shooting star
  ASTRUM_MAX_SHOOTING_STARS = 6       # Max shooting stars at once
  ASTRUM_TRAIL_LENGTH = 5             # Trail positions remembered per orbiter

  def astrum_active?
    @mode == :family && @items[@selected] && @items[@selected][:id] == ASTRUM_FAMILY_ID &&
      !animating_slide? && !animating_zoom?
  end

  def spawn_astrum_orbiters(cx, cy, radius)
    @particles.clear
    ASTRUM_ORBIT_COUNT.times do
      angle = rand(628) / 100.0
      # Orbit at varying distances from the circle edge
      orbit_dist = radius + 10 + rand(60)
      # Different orbital speeds - closer = faster (Kepler-ish)
      speed = 0.008 + rand(15) / 1000.0 + (30.0 / orbit_dist) * 0.005
      # Randomize direction (some clockwise, some counter)
      speed = -speed if rand(3) == 0
      @particles << {
        type: :orbiter,
        angle: angle,
        dist: orbit_dist,
        speed: speed,
        size: rand(4) == 0 ? 3 : (rand(3) == 0 ? 2 : 1),
        brightness: rand(100) + 155,
        twinkle_phase: rand(628) / 100.0,
        twinkle_speed: 0.03 + rand(60) / 1000.0,
        trail: [],       # Array of previous [x, y] positions
        has_trail: rand(4) == 0   # 25% of stars leave trails
      }
    end
  end

  def update_astrum_particles(cx, cy, radius)
    return unless astrum_active?

    # Initialize orbiters on first frame
    if @particles.empty? || @particles.none? { |p| p[:type] == :orbiter }
      spawn_astrum_orbiters(cx, cy, radius)
    end

    # Update orbiters
    @particles.each do |p|
      if p[:type] == :orbiter
        # Rotate around center
        p[:angle] += p[:speed]
        px = cx + Math.cos(p[:angle]) * p[:dist]
        py = cy + Math.sin(p[:angle]) * p[:dist]
        # Store trail
        if p[:has_trail]
          p[:trail] << [px, py]
          p[:trail].shift if p[:trail].length > ASTRUM_TRAIL_LENGTH
        end
      elsif p[:type] == :shooting_star
        p[:life] += 1
        p[:x] += p[:vx]
        p[:y] += p[:vy]
        # Store trail
        p[:trail] << [p[:x], p[:y]]
        p[:trail].shift if p[:trail].length > 8
      end
    end

    # Remove expired shooting stars
    @particles.reject! { |p| p[:type] == :shooting_star && p[:life] > p[:max_life] }

    # Spawn shooting stars occasionally
    shooting_count = @particles.count { |p| p[:type] == :shooting_star }
    if rand(ASTRUM_SHOOTING_STAR_CHANCE) == 0 && shooting_count < ASTRUM_MAX_SHOOTING_STARS
      # Spawn from a random point around the circle
      angle = rand(628) / 100.0  # 0 to ~2π (safe float)
      start_dist = radius + 15 + rand(40)
      speed = 2.5 + rand(20) / 10.0
      # Streak in a fully random direction
      streak_angle = rand(628) / 100.0
      @particles << {
        type: :shooting_star,
        x: cx + Math.cos(angle) * start_dist,
        y: cy + Math.sin(angle) * start_dist,
        vx: Math.cos(streak_angle) * speed,
        vy: Math.sin(streak_angle) * speed,
        life: 0,
        max_life: 25 + rand(15),
        size: 2,
        brightness: 255,
        trail: []
      }
    end
  end

  def draw_astrum_fx(cx, cy, radius)
    bmp = @sprites["fx"].bitmap
    bmp.clear

    return if @particles.empty?

    # Soft glow halo around the circle
    3.times do |i|
      ring_r = radius + 2 + i * 3
      pulse = Math.sin(@frame * 0.03 + i * 1.2)
      alpha = (30 + pulse * 15).to_i.clamp(10, 60)
      # Warm golden-white glow
      glow_color = Color.new(200, 180 + i * 20, 120 + i * 30, alpha)
      draw_circle_outline(bmp, cx, cy, ring_r, glow_color)
      draw_circle_outline(bmp, cx, cy, ring_r + 1, glow_color)
    end

    # Draw particles
    @particles.each do |p|
      if p[:type] == :orbiter
        px = (cx + Math.cos(p[:angle]) * p[:dist]).to_i
        py = (cy + Math.sin(p[:angle]) * p[:dist]).to_i

        # Twinkle
        twinkle = Math.sin(p[:twinkle_phase] + @frame * p[:twinkle_speed])
        alpha = (p[:brightness] * (0.6 + twinkle * 0.4)).to_i.clamp(30, 255)

        # Draw trail first (fading)
        if p[:has_trail]
          p[:trail].each_with_index do |pos, idx|
            t_alpha = (alpha * (idx + 1).to_f / (p[:trail].length + 1) * 0.5).to_i
            next if t_alpha < 5
            tx = pos[0].to_i
            ty = pos[1].to_i
            next if tx < 0 || tx >= bmp.width || ty < 0 || ty >= bmp.height
            trail_col = Color.new(180, 200, 255, t_alpha)
            bmp.fill_rect(tx, ty, 1, 1, trail_col)
          end
        end

        # Draw star
        next if px < 0 || px >= bmp.width || py < 0 || py >= bmp.height
        # Color varies: white, pale blue, pale gold
        case p[:size]
        when 3  # Bright large stars: warm gold
          col = Color.new(255, 240, 180, alpha)
        when 2  # Medium stars: pale blue
          col = Color.new(180, 200, 255, alpha)
        else    # Small stars: white
          col = Color.new(255, 255, 255, alpha)
        end
        bmp.fill_rect(px, py, p[:size], p[:size], col)

        # Cross sparkle on large stars
        if p[:size] >= 3 && alpha > 180
          spark_alpha = (alpha * 0.4).to_i
          spark_col = Color.new(255, 255, 255, spark_alpha)
          bmp.fill_rect(px - 1, py + 1, 1, 1, spark_col) if px - 1 >= 0
          bmp.fill_rect(px + 3, py + 1, 1, 1, spark_col) if px + 3 < bmp.width
          bmp.fill_rect(px + 1, py - 1, 1, 1, spark_col) if py - 1 >= 0
          bmp.fill_rect(px + 1, py + 3, 1, 1, spark_col) if py + 3 < bmp.height
        end

      elsif p[:type] == :shooting_star
        # Draw shooting star trail
        p[:trail].each_with_index do |pos, idx|
          t = (idx + 1).to_f / (p[:trail].length + 1)
          t_alpha = (255 * t * (1.0 - p[:life].to_f / p[:max_life])).to_i.clamp(0, 255)
          next if t_alpha < 5
          tx = pos[0].to_i
          ty = pos[1].to_i
          next if tx < 0 || tx >= bmp.width || ty < 0 || ty >= bmp.height
          trail_col = Color.new(220, 230, 255, t_alpha)
          bmp.fill_rect(tx, ty, 2, 2, trail_col)
        end

        # Draw head
        fade = (1.0 - p[:life].to_f / p[:max_life]).clamp(0.0, 1.0)
        head_alpha = (255 * fade).to_i
        next if head_alpha < 10
        hx = p[:x].to_i
        hy = p[:y].to_i
        next if hx < 0 || hx >= bmp.width || hy < 0 || hy >= bmp.height
        head_col = Color.new(255, 255, 240, head_alpha)
        bmp.fill_rect(hx, hy, 3, 3, head_col)
        # Bright core
        bmp.fill_rect(hx + 1, hy + 1, 1, 1, Color.new(255, 255, 255, head_alpha))
      end
    end
  end

  #=============================================================================
  # Silva Roots & Flowers Effect
  #=============================================================================
  SILVA_FAMILY_ID = 3
  SILVA_ROOT_COUNT = 6                # Number of root vines
  SILVA_GROW_SPEED = 1.5              # Segments revealed per frame
  SILVA_SEGMENTS_PER_ROOT = 25        # Segments in each root path
  SILVA_BRANCH_CHANCE = 55            # % chance to branch at each segment
  SILVA_MIN_DIST = 15                 # Don't grow closer than this to center
  SILVA_FLOWER_COLORS = [
    [255, 140, 180],  # Pink
    [255, 220, 100],  # Yellow
    [200, 130, 255],  # Lavender
    [255, 255, 200],  # Cream
    [140, 220, 255],  # Light blue
  ]

  def silva_active?
    @mode == :family && @items[@selected] && @items[@selected][:id] == SILVA_FAMILY_ID &&
      !animating_slide? && !animating_zoom?
  end

  def generate_silva_roots(cx, cy, radius)
    @silva_roots = []
    @silva_flowers = []
    @silva_grow_frame = 0

    root_count = SILVA_ROOT_COUNT + rand(7)  # 6 to 12
    root_count.times do
      angle = rand(628) / 100.0
      root = generate_one_root(cx, cy, radius, angle, SILVA_SEGMENTS_PER_ROOT, 3)
      @silva_roots << root
    end
  end

  def generate_one_root(cx, cy, radius, start_angle, segments, thickness)
    # Start at the circle edge
    sx = cx + Math.cos(start_angle) * radius
    sy = cy + Math.sin(start_angle) * radius

    points = [[sx, sy]]
    angle = start_angle + Math::PI  # Point inward
    branches = []
    step = (radius - SILVA_MIN_DIST) / segments.to_f * 0.9

    segments.times do |i|
      # Wander the angle slightly for organic feel
      angle += (rand(60) - 30) / 100.0
      # Each step moves inward
      nx = points.last[0] + Math.cos(angle) * step
      ny = points.last[1] + Math.sin(angle) * step

      # Don't go past center
      dist_to_center = Math.sqrt((nx - cx) ** 2 + (ny - cy) ** 2)
      break if dist_to_center < SILVA_MIN_DIST

      points << [nx, ny]

      # Maybe branch
      if i > 3 && i < segments - 3 && rand(100) < SILVA_BRANCH_CHANCE && thickness > 1
        branch_angle = angle + (rand(2) == 0 ? 1 : -1) * (0.4 + rand(40) / 100.0)
        branch = generate_one_root(cx, cy, 0, 0, segments - i - 2, thickness - 1)
        # Override the branch to start from this point with the branch angle
        branch_pts = [[nx, ny]]
        branch_step = step * 0.7
        b_angle = branch_angle
        (segments - i - 2).times do
          b_angle += (rand(50) - 25) / 100.0
          bx = branch_pts.last[0] + Math.cos(b_angle) * branch_step
          by = branch_pts.last[1] + Math.sin(b_angle) * branch_step
          dist = Math.sqrt((bx - cx) ** 2 + (by - cy) ** 2)
          break if dist < SILVA_MIN_DIST
          branch_pts << [bx, by]
        end
        if branch_pts.length > 2
          branches << {
            points: branch_pts,
            drawn: 0,
            thickness: 1,
            start_at: i  # Branch starts growing when main root reaches this segment
          }
        end
      end
    end

    # Add a flower at the tip
    if points.length > 3
      flower_color = SILVA_FLOWER_COLORS[rand(SILVA_FLOWER_COLORS.length)]
      @silva_flowers << {
        x: points.last[0], y: points.last[1],
        color: flower_color,
        bloom: 0.0, max_size: 3 + rand(3),
        owner: :root, ready_at: points.length
      }
    end

    # Add flowers at branch tips too
    branches.each do |b|
      if b[:points].length > 2
        flower_color = SILVA_FLOWER_COLORS[rand(SILVA_FLOWER_COLORS.length)]
        @silva_flowers << {
          x: b[:points].last[0], y: b[:points].last[1],
          color: flower_color,
          bloom: 0.0, max_size: 2 + rand(2),
          owner: :branch, ready_at: b[:start_at] + b[:points].length
        }
      end
    end

    { points: points, drawn: 0, thickness: thickness, branches: branches }
  end

  def update_silva(cx, cy, radius)
    return unless silva_active?

    # Initialize on first frame
    if !@silva_roots || @silva_roots.empty?
      generate_silva_roots(cx, cy, radius)
    end

    @silva_grow_frame = (@silva_grow_frame || 0) + 1
    total_drawn = (@silva_grow_frame * SILVA_GROW_SPEED).to_i

    # Grow main roots
    @silva_roots.each do |root|
      root[:drawn] = [total_drawn, root[:points].length].min

      # Grow branches once main root passes their start point
      root[:branches].each do |branch|
        if root[:drawn] >= branch[:start_at]
          branch_progress = total_drawn - branch[:start_at]
          branch[:drawn] = [branch_progress, branch[:points].length].min
        end
      end
    end

    # Bloom flowers once their root/branch is fully drawn
    @silva_flowers.each do |f|
      if total_drawn >= f[:ready_at]
        f[:bloom] = [f[:bloom] + 0.04, 1.0].min
      end
    end
  end

  def draw_silva_fx(cx, cy, radius)
    bmp = @sprites["fx"].bitmap
    bmp.clear

    return if !@silva_roots || @silva_roots.empty?

    # Soft green glow around circle
    2.times do |i|
      ring_r = radius + 2 + i * 3
      pulse = Math.sin(@frame * 0.025 + i * 1.0)
      alpha = (25 + pulse * 12).to_i.clamp(8, 50)
      glow_color = Color.new(80, 180 + i * 20, 60, alpha)
      draw_circle_outline(bmp, cx, cy, ring_r, glow_color)
      draw_circle_outline(bmp, cx, cy, ring_r + 1, glow_color)
    end

    # Draw roots
    @silva_roots.each do |root|
      draw_silva_vine(bmp, root[:points], root[:drawn], root[:thickness])

      # Draw branches
      root[:branches].each do |branch|
        next if branch[:drawn] <= 0
        draw_silva_vine(bmp, branch[:points], branch[:drawn], branch[:thickness])
      end
    end

    # Draw flowers
    @silva_flowers.each do |f|
      next if f[:bloom] <= 0.0
      draw_silva_flower(bmp, f)
    end
  end

  def draw_silva_vine(bmp, points, drawn_count, thickness)
    return if drawn_count < 2

    drawn_count.times do |i|
      next if i == 0
      x1 = points[i - 1][0].to_i
      y1 = points[i - 1][1].to_i
      x2 = points[i][0].to_i
      y2 = points[i][1].to_i

      # Color: dark brown at base, greener toward tip
      t = i.to_f / points.length
      r = (60 + t * 20).to_i
      g = (40 + t * 80).to_i
      b = (20 + t * 20).to_i
      col = Color.new(r, g, b, 220)

      # Draw line between points (simple bresenham-ish)
      draw_thick_line(bmp, x1, y1, x2, y2, col, thickness)
    end
  end

  def draw_thick_line(bmp, x1, y1, x2, y2, color, thickness)
    dx = (x2 - x1).abs
    dy = (y2 - y1).abs
    sx = x1 < x2 ? 1 : -1
    sy = y1 < y2 ? 1 : -1
    err = dx - dy
    x, y = x1, y1

    loop do
      if x >= 0 && x < bmp.width && y >= 0 && y < bmp.height
        if thickness > 1
          bmp.fill_rect(x, y, thickness, thickness, color)
        else
          bmp.fill_rect(x, y, 1, 1, color)
        end
      end
      break if x == x2 && y == y2
      e2 = 2 * err
      if e2 > -dy
        err -= dy
        x += sx
      end
      if e2 < dx
        err += dx
        y += sy
      end
    end
  end

  def draw_silva_flower(bmp, flower)
    fx = flower[:x].to_i
    fy = flower[:y].to_i
    bloom = flower[:bloom]
    max_s = flower[:max_size]
    col = flower[:color]

    # Current size based on bloom progress
    size = (max_s * bloom).to_i
    return if size < 1

    # Pulsing brightness
    pulse = Math.sin(@frame * 0.06 + fx * 0.1)
    alpha = (180 + pulse * 40).to_i.clamp(120, 240)

    # Flower center
    fc = Color.new(col[0], col[1], col[2], alpha)
    if size <= 2
      bmp.fill_rect(fx, fy, size, size, fc)
    else
      draw_filled_circle(bmp, fx, fy, size, fc)
    end

    # Bright core
    if size >= 3
      core_col = Color.new(255, 255, 220, alpha)
      bmp.fill_rect(fx, fy, 1, 1, core_col)
    end

    # Tiny glow around flower
    if bloom > 0.8
      glow_alpha = ((bloom - 0.8) * 5.0 * 60).to_i.clamp(0, 60)
      glow_col = Color.new(col[0], col[1], col[2], glow_alpha)
      draw_circle_outline(bmp, fx, fy, size + 1, glow_col)
    end
  end

  #=============================================================================
  # Machina Clockwork Forge Effect
  #=============================================================================
  MACHINA_FAMILY_ID = 4
  MACHINA_SPARK_COUNT = 80         # Max welding sparks alive
  MACHINA_SPARK_SPAWN = 3          # Sparks spawned per frame
  MACHINA_ARC_CHANCE = 10          # 1 in N frames to spawn a lightning arc
  MACHINA_MAX_ARCS = 3             # Max simultaneous lightning arcs

  def machina_active?
    @mode == :family && @items[@selected] && @items[@selected][:id] == MACHINA_FAMILY_ID &&
      !animating_slide? && !animating_zoom?
  end

  def init_machina_gears(cx, cy, radius)
    @machina_gears = [
      { dist: radius + 8,  teeth: 16, tooth_h: 4, speed:  0.012, angle_offset: rand(628) / 100.0, thickness: 2 },
      { dist: radius + 24, teeth: 12, tooth_h: 5, speed: -0.008, angle_offset: rand(628) / 100.0, thickness: 2 },
      { dist: radius + 44, teeth: 20, tooth_h: 3, speed:  0.015, angle_offset: rand(628) / 100.0, thickness: 2 },
    ]
    @machina_arcs = []
  end

  def update_machina(cx, cy, radius)
    return unless machina_active?

    # Initialize gears on first frame
    if !@machina_gears || @machina_gears.empty?
      init_machina_gears(cx, cy, radius)
    end

    # Rotate gears
    @machina_gears.each { |g| g[:angle_offset] += g[:speed] }

    # Spawn sparks from random gear teeth
    spark_count = @particles.count { |p| p[:type] == :spark }
    if spark_count < MACHINA_SPARK_COUNT
      MACHINA_SPARK_SPAWN.times do
        gear = @machina_gears[rand(@machina_gears.length)]
        tooth_idx = rand(gear[:teeth])
        tooth_angle = gear[:angle_offset] + (tooth_idx.to_f / gear[:teeth]) * 2.0 * Math::PI
        spawn_dist = gear[:dist] + gear[:tooth_h]
        sx = cx + Math.cos(tooth_angle) * spawn_dist
        sy = cy + Math.sin(tooth_angle) * spawn_dist
        # Fly outward with spread and some speed variation
        spread = (rand(60) - 30) / 100.0
        spd = 1.0 + rand(30) / 10.0
        @particles << {
          type: :spark,
          x: sx, y: sy,
          vx: Math.cos(tooth_angle + spread) * spd,
          vy: Math.sin(tooth_angle + spread) * spd,
          life: 0,
          max_life: 15 + rand(20),
          size: rand(3) == 0 ? 2 : 1,
          brightness: 200 + rand(56),
          electric: rand(5) == 0   # 20% are blue-white electric sparks
        }
      end
    end

    # Update sparks - gravity + air resistance
    @particles.each do |p|
      next unless p[:type] == :spark
      p[:life] += 1
      p[:x] += p[:vx]
      p[:y] += p[:vy]
      p[:vy] += 0.08   # Gravity
      p[:vx] *= 0.98    # Air drag
    end

    # Remove dead sparks
    @particles.reject! { |p| p[:type] == :spark && p[:life] >= p[:max_life] }

    # Lightning arcs between gear points
    if rand(MACHINA_ARC_CHANCE) == 0 && @machina_arcs.length < MACHINA_MAX_ARCS
      g1 = @machina_gears[rand(@machina_gears.length)]
      g2 = @machina_gears[rand(@machina_gears.length)]
      a1 = g1[:angle_offset] + rand(628) / 100.0
      a2 = g2[:angle_offset] + rand(628) / 100.0
      x1 = cx + Math.cos(a1) * g1[:dist]
      y1 = cy + Math.sin(a1) * g1[:dist]
      x2 = cx + Math.cos(a2) * g2[:dist]
      y2 = cy + Math.sin(a2) * g2[:dist]
      path = generate_lightning_path(x1, y1, x2, y2, 6)
      @machina_arcs << { path: path, life: 0, max_life: 6 + rand(8) }
    end

    @machina_arcs.each { |a| a[:life] += 1 }
    @machina_arcs.reject! { |a| a[:life] >= a[:max_life] }
  end

  # Recursive midpoint displacement for jagged lightning
  def generate_lightning_path(x1, y1, x2, y2, depth)
    return [[x1, y1], [x2, y2]] if depth <= 0
    dx = x2 - x1
    dy = y2 - y1
    len = Math.sqrt(dx * dx + dy * dy)
    return [[x1, y1], [x2, y2]] if len < 2
    # Midpoint with perpendicular jitter
    mx = (x1 + x2) / 2.0 + (-dy / len) * ((rand(100) - 50) / 100.0 * len * 0.4)
    my = (y1 + y2) / 2.0 + (dx / len) * ((rand(100) - 50) / 100.0 * len * 0.4)
    left  = generate_lightning_path(x1, y1, mx, my, depth - 1)
    right = generate_lightning_path(mx, my, x2, y2, depth - 1)
    left + right[1..-1]
  end

  def draw_machina_fx(cx, cy, radius)
    bmp = @sprites["fx"].bitmap
    bmp.clear

    return if !@machina_gears || @machina_gears.empty?

    # Warm industrial glow halo
    3.times do |i|
      ring_r = radius + 2 + i * 3
      pulse = Math.sin(@frame * 0.04 + i * 0.9)
      alpha = (25 + pulse * 15).to_i.clamp(8, 55)
      glow_color = Color.new(220, 150 + i * 15, 60, alpha)
      draw_circle_outline(bmp, cx, cy, ring_r, glow_color)
      draw_circle_outline(bmp, cx, cy, ring_r + 1, glow_color)
    end

    # Draw spinning gears (toothed ring outlines)
    @machina_gears.each_with_index do |gear, gi|
      teeth = gear[:teeth]
      base_r = gear[:dist]
      tooth_h = gear[:tooth_h]
      offset = gear[:angle_offset]
      steps = teeth * 8  # Smooth enough for teeth shape

      pulse = Math.sin(@frame * 0.03 + gi * 2.0)
      alpha = (160 + pulse * 40).to_i.clamp(100, 220)
      # Metallic color - increasingly blue-white per gear layer
      grey = 120 + gi * 30
      blue = 140 + gi * 20
      col = Color.new(grey, grey + 10, [blue, 255].min, alpha)

      prev_px = nil
      prev_py = nil
      first_px = nil
      first_py = nil

      (steps + 1).times do |s|
        angle = offset + (s.to_f / steps) * 2.0 * Math::PI
        # Square wave: in tooth or in valley
        tooth_frac = ((s % (steps / teeth)).to_f / (steps / teeth))
        r = tooth_frac < 0.5 ? base_r + tooth_h : base_r
        px = (cx + Math.cos(angle) * r).to_i
        py = (cy + Math.sin(angle) * r).to_i

        if s == 0
          first_px = px
          first_py = py
        end

        if prev_px
          draw_thick_line(bmp, prev_px, prev_py, px, py, col, gear[:thickness])
        end
        prev_px = px
        prev_py = py
      end
    end

    # Draw lightning arcs
    @machina_arcs.each do |arc|
      fade = 1.0 - (arc[:life].to_f / arc[:max_life])
      path = arc[:path]
      next if path.length < 2
      alpha = (255 * fade).to_i.clamp(0, 255)
      glow_alpha = (alpha * 0.5).to_i

      core_col = Color.new(255, 255, 255, alpha)
      glow_col = Color.new(100, 180, 255, glow_alpha)

      (path.length - 1).times do |i|
        x1 = path[i][0].to_i
        y1 = path[i][1].to_i
        x2 = path[i + 1][0].to_i
        y2 = path[i + 1][1].to_i
        # White core
        draw_thick_line(bmp, x1, y1, x2, y2, core_col, 1)
        # Blue glow offset
        draw_thick_line(bmp, x1 + 1, y1, x2 + 1, y2, glow_col, 1)
        draw_thick_line(bmp, x1, y1 + 1, x2, y2 + 1, glow_col, 1)
      end
    end

    # Draw sparks
    @particles.each do |p|
      next unless p[:type] == :spark
      fade = 1.0 - (p[:life].to_f / p[:max_life])
      alpha = (p[:brightness] * fade).to_i.clamp(0, 255)
      next if alpha < 10
      px = p[:x].to_i
      py = p[:y].to_i
      next if px < 0 || px >= bmp.width || py < 0 || py >= bmp.height

      if p[:electric]
        col = Color.new(180, 220, 255, alpha)
      else
        r_val = (255 * fade + 200 * (1.0 - fade)).to_i.clamp(0, 255)
        col = Color.new(r_val, (180 * fade).to_i.clamp(0, 255), 40, alpha)
      end
      bmp.fill_rect(px, py, p[:size], p[:size], col)
    end
  end

  #=============================================================================
  # Humanitas Civilization Network Effect
  #=============================================================================
  HUMANITAS_FAMILY_ID = 5
  HUMANITAS_NODE_COUNT = 28        # Network nodes around circle
  HUMANITAS_CONNECT_DIST = 55      # Max distance to draw a connection
  HUMANITAS_PULSE_INTERVAL = 80    # Frames between heartbeat pulses
  HUMANITAS_PULSE_SPEED = 1.8      # Pixels per frame the pulse ring expands
  HUMANITAS_MAX_PULSES = 3         # Max concurrent pulse rings

  def humanitas_active?
    @mode == :family && @items[@selected] && @items[@selected][:id] == HUMANITAS_FAMILY_ID &&
      !animating_slide? && !animating_zoom?
  end

  def init_humanitas_network(cx, cy, radius)
    @humanitas_nodes = []
    HUMANITAS_NODE_COUNT.times do
      angle = rand(628) / 100.0
      dist = radius + 8 + rand(55)
      @humanitas_nodes << {
        x: cx + Math.cos(angle) * dist,
        y: cy + Math.sin(angle) * dist,
        dist: dist,             # Distance from center (constant - only angle drifts)
        angle: angle,
        size: rand(4) == 0 ? 4 : (rand(3) == 0 ? 3 : 2),
        base_brightness: 120 + rand(80),
        pulse_glow: 0.0,
        drift_speed: (rand(30) - 15) / 1000.0,
        breathe_phase: rand(628) / 100.0
      }
    end

    # Precompute connections between nearby nodes + cache midpoint dist
    @humanitas_connections = []
    @humanitas_nodes.each_with_index do |a, i|
      ((i + 1)...@humanitas_nodes.length).each do |j|
        b = @humanitas_nodes[j]
        dx = a[:x] - b[:x]
        dy = a[:y] - b[:y]
        dist_sq = dx * dx + dy * dy
        if dist_sq < HUMANITAS_CONNECT_DIST * HUMANITAS_CONNECT_DIST
          # Cache midpoint distance from center (average of the two node dists)
          mid_dist = (a[:dist] + b[:dist]) / 2.0
          @humanitas_connections << { a: i, b: j, mid_dist: mid_dist, pulse_glow: 0.0 }
        end
      end
    end

    @humanitas_pulses = []
    @humanitas_pulse_timer = 0
  end

  def update_humanitas(cx, cy, radius)
    return unless humanitas_active?

    if !@humanitas_nodes || @humanitas_nodes.empty?
      init_humanitas_network(cx, cy, radius)
    end

    # Drift nodes gently in orbit (dist stays constant, only angle changes)
    @humanitas_nodes.each do |node|
      node[:angle] += node[:drift_speed]
      node[:x] = cx + Math.cos(node[:angle]) * node[:dist]
      node[:y] = cy + Math.sin(node[:angle]) * node[:dist]
    end

    # Spawn pulse waves periodically
    @humanitas_pulse_timer = (@humanitas_pulse_timer || 0) + 1
    if @humanitas_pulse_timer >= HUMANITAS_PULSE_INTERVAL
      @humanitas_pulse_timer = 0
      if @humanitas_pulses.length < HUMANITAS_MAX_PULSES
        @humanitas_pulses << { radius: 0.0, max_radius: radius + 80.0 }
      end
    end

    # Expand pulses
    @humanitas_pulses.each { |p| p[:radius] += HUMANITAS_PULSE_SPEED }
    @humanitas_pulses.reject! { |p| p[:radius] > p[:max_radius] }

    # Update node glow from passing pulses (use cached dist, no sqrt)
    @humanitas_nodes.each do |node|
      node[:pulse_glow] *= 0.92
      @humanitas_pulses.each do |pulse|
        if (pulse[:radius] - node[:dist]).abs < 8
          node[:pulse_glow] = 1.0 if node[:pulse_glow] < 1.0
        end
      end
    end

    # Update connection glow (use cached mid_dist, no sqrt)
    @humanitas_connections.each do |conn|
      conn[:pulse_glow] *= 0.90
      @humanitas_pulses.each do |pulse|
        if (pulse[:radius] - conn[:mid_dist]).abs < 12
          conn[:pulse_glow] = 1.0 if conn[:pulse_glow] < 1.0
        end
      end
    end
  end

  def draw_humanitas_fx(cx, cy, radius)
    bmp = @sprites["fx"].bitmap
    bmp.clear

    return if !@humanitas_nodes || @humanitas_nodes.empty?

    # Warm amber glow halo (2 rings instead of 3)
    2.times do |i|
      ring_r = radius + 2 + i * 4
      pulse = Math.sin(@frame * 0.035 + i * 1.1)
      alpha = (22 + pulse * 12).to_i.clamp(8, 48)
      glow_color = Color.new(220, 180 + i * 15, 80 + i * 20, alpha)
      draw_circle_outline(bmp, cx, cy, ring_r, glow_color)
    end

    # Draw pulse rings (expanding, fading) - single outline per ring
    @humanitas_pulses.each do |pulse|
      progress = pulse[:radius] / pulse[:max_radius]
      ring_alpha = ((1.0 - progress) * 80).to_i.clamp(0, 80)
      next if ring_alpha < 5
      ring_col = Color.new(255, 200, 100, ring_alpha)
      draw_circle_outline(bmp, cx, cy, pulse[:radius].to_i, ring_col)
    end

    # Draw connections as sampled dots (every 4px instead of full Bresenham)
    @humanitas_connections.each do |conn|
      na = @humanitas_nodes[conn[:a]]
      nb = @humanitas_nodes[conn[:b]]
      ax = na[:x].to_i
      ay = na[:y].to_i
      bx = nb[:x].to_i
      by = nb[:y].to_i

      base_alpha = 30
      glow_boost = (conn[:pulse_glow] * 150).to_i
      alpha = (base_alpha + glow_boost).clamp(15, 200)

      r = (140 + conn[:pulse_glow] * 115).to_i.clamp(0, 255)
      g = (100 + conn[:pulse_glow] * 100).to_i.clamp(0, 255)
      b = (40 + conn[:pulse_glow] * 60).to_i.clamp(0, 255)
      col = Color.new(r, g, b, alpha)

      # Sampled dots along line instead of full Bresenham
      dx = bx - ax
      dy = by - ay
      len = dx.abs > dy.abs ? dx.abs : dy.abs
      next if len < 1
      steps = len / 4 + 1  # One dot every ~4 pixels
      steps.times do |s|
        t = s.to_f / steps
        px = (ax + dx * t).to_i
        py = (ay + dy * t).to_i
        next if px < 0 || px >= bmp.width || py < 0 || py >= bmp.height
        bmp.fill_rect(px, py, 2, 2, col)
      end
    end

    # Draw nodes (all as fill_rect - no draw_filled_circle or draw_circle_outline)
    @humanitas_nodes.each do |node|
      breathe = Math.sin(node[:breathe_phase] + @frame * 0.04)
      base_alpha = (node[:base_brightness] * (0.7 + breathe * 0.3)).to_i
      glow_boost = (node[:pulse_glow] * 120).to_i
      alpha = (base_alpha + glow_boost).clamp(30, 255)

      px = node[:x].to_i
      py = node[:y].to_i
      next if px < 0 || px >= bmp.width || py < 0 || py >= bmp.height

      r = (200 + node[:pulse_glow] * 55).to_i.clamp(0, 255)
      g = (160 + node[:pulse_glow] * 60).to_i.clamp(0, 255)
      b = (60 + node[:pulse_glow] * 80).to_i.clamp(0, 255)
      col = Color.new(r, g, b, alpha)

      s = node[:size]
      bmp.fill_rect(px - s / 2, py - s / 2, s, s, col)

      # Bright core + glow cross on pulsed nodes (cheap alternative to circle outline)
      if s >= 3 && node[:pulse_glow] > 0.3
        bmp.fill_rect(px, py, 1, 1, Color.new(255, 240, 200, alpha))
        # Diamond glow: 4 cardinal points around the node
        g_alpha = (node[:pulse_glow] * 60).to_i.clamp(0, 60)
        g_col = Color.new(255, 220, 140, g_alpha)
        g_r = s + 2
        bmp.fill_rect(px - g_r, py, 1, 1, g_col) if px - g_r >= 0
        bmp.fill_rect(px + g_r, py, 1, 1, g_col) if px + g_r < bmp.width
        bmp.fill_rect(px, py - g_r, 1, 1, g_col) if py - g_r >= 0
        bmp.fill_rect(px, py + g_r, 1, 1, g_col) if py + g_r < bmp.height
        # Diagonal points for fuller glow
        d = g_r - 1
        bmp.fill_rect(px - d, py - d, 1, 1, g_col) if px - d >= 0 && py - d >= 0
        bmp.fill_rect(px + d, py - d, 1, 1, g_col) if px + d < bmp.width && py - d >= 0
        bmp.fill_rect(px - d, py + d, 1, 1, g_col) if px - d >= 0 && py + d < bmp.height
        bmp.fill_rect(px + d, py + d, 1, 1, g_col) if px + d < bmp.width && py + d < bmp.height
      end
    end
  end

  #=============================================================================
  # Aetheris Ethereal Wisps Effect
  #=============================================================================
  AETHERIS_FAMILY_ID = 6
  AETHERIS_WISP_COUNT = 8           # Number of flowing wisps
  AETHERIS_TRAIL_LENGTH = 18        # Trail points remembered per wisp
  AETHERIS_SPARKLE_CHANCE = 8       # 1 in N frames per wisp to shed a sparkle
  AETHERIS_MAX_SPARKLES = 30        # Max sparkle particles

  def aetheris_active?
    @mode == :family && @items[@selected] && @items[@selected][:id] == AETHERIS_FAMILY_ID &&
      !animating_slide? && !animating_zoom?
  end

  def init_aetheris_wisps(cx, cy, radius)
    @aetheris_wisps = []
    AETHERIS_WISP_COUNT.times do |i|
      angle = (i.to_f / AETHERIS_WISP_COUNT) * 2.0 * Math::PI + rand(30) / 100.0
      dist = radius + 10 + rand(40)
      @aetheris_wisps << {
        angle: angle,
        dist: dist,
        speed: 0.010 + rand(10) / 1000.0,
        wave_amp: 8 + rand(12),          # Radial wave amplitude
        wave_freq: 0.08 + rand(40) / 1000.0,  # Wave frequency
        wave_phase: rand(628) / 100.0,
        trail: [],                        # Array of [x, y] positions
        color_idx: i % 3                  # 0=lavender, 1=pale blue, 2=soft pink
      }
    end
  end

  def update_aetheris(cx, cy, radius)
    return unless aetheris_active?

    if !@aetheris_wisps || @aetheris_wisps.empty?
      init_aetheris_wisps(cx, cy, radius)
    end

    # Update wisps - orbit with sinusoidal radial wobble
    @aetheris_wisps.each do |wisp|
      wisp[:angle] += wisp[:speed]
      wisp[:wave_phase] += wisp[:wave_freq]
      wave = Math.sin(wisp[:wave_phase]) * wisp[:wave_amp]
      r = wisp[:dist] + wave
      px = cx + Math.cos(wisp[:angle]) * r
      py = cy + Math.sin(wisp[:angle]) * r

      wisp[:trail] << [px, py]
      wisp[:trail].shift if wisp[:trail].length > AETHERIS_TRAIL_LENGTH
    end

    # Spawn sparkles from wisp heads
    sparkle_count = @particles.count { |p| p[:type] == :aetheris_sparkle }
    @aetheris_wisps.each do |wisp|
      next if wisp[:trail].empty?
      next if sparkle_count >= AETHERIS_MAX_SPARKLES
      if rand(AETHERIS_SPARKLE_CHANCE) == 0
        head = wisp[:trail].last
        @particles << {
          type: :aetheris_sparkle,
          x: head[0] + rand(7) - 3,
          y: head[1] + rand(7) - 3,
          life: 0,
          max_life: 20 + rand(20),
          size: rand(3) == 0 ? 2 : 1,
          brightness: 180 + rand(76),
          color_idx: wisp[:color_idx]
        }
        sparkle_count += 1
      end
    end

    # Update sparkles - gentle float upward
    @particles.each do |p|
      next unless p[:type] == :aetheris_sparkle
      p[:life] += 1
      p[:y] -= 0.3
      p[:x] += (rand(3) - 1) * 0.2
    end

    @particles.reject! { |p| p[:type] == :aetheris_sparkle && p[:life] >= p[:max_life] }
  end

  # Wisp color palettes (lavender, pale blue, soft pink)
  AETHERIS_WISP_COLORS = [
    [180, 140, 255],  # Lavender
    [140, 180, 255],  # Pale blue
    [220, 160, 230],  # Soft pink
  ]

  def draw_aetheris_fx(cx, cy, radius)
    bmp = @sprites["fx"].bitmap
    bmp.clear

    return if !@aetheris_wisps || @aetheris_wisps.empty?

    # Soft lavender glow halo
    2.times do |i|
      ring_r = radius + 2 + i * 4
      pulse = Math.sin(@frame * 0.03 + i * 1.0)
      alpha = (20 + pulse * 10).to_i.clamp(8, 40)
      glow_color = Color.new(160, 120 + i * 20, 220 + i * 15, alpha)
      draw_circle_outline(bmp, cx, cy, ring_r, glow_color)
    end

    # Draw wisp trails
    @aetheris_wisps.each do |wisp|
      trail = wisp[:trail]
      next if trail.length < 2
      base_col = AETHERIS_WISP_COLORS[wisp[:color_idx]]

      trail.each_with_index do |pos, idx|
        # Fade from tail (0) to head (last)
        t = (idx + 1).to_f / trail.length
        alpha = (t * 180).to_i.clamp(0, 180)
        next if alpha < 10

        px = pos[0].to_i
        py = pos[1].to_i
        next if px < 0 || px >= bmp.width || py < 0 || py >= bmp.height

        # Brighter toward head
        r = (base_col[0] * (0.5 + t * 0.5)).to_i.clamp(0, 255)
        g = (base_col[1] * (0.5 + t * 0.5)).to_i.clamp(0, 255)
        b = (base_col[2] * (0.5 + t * 0.5)).to_i.clamp(0, 255)
        col = Color.new(r, g, b, alpha)

        # Trail gets wider toward head
        s = t > 0.7 ? 3 : (t > 0.3 ? 2 : 1)
        bmp.fill_rect(px, py, s, s, col)
      end

      # Bright head dot
      head = trail.last
      hx = head[0].to_i
      hy = head[1].to_i
      if hx >= 0 && hx < bmp.width && hy >= 0 && hy < bmp.height
        head_col = Color.new(
          [base_col[0] + 60, 255].min,
          [base_col[1] + 60, 255].min,
          255, 220
        )
        bmp.fill_rect(hx, hy, 3, 3, head_col)
        # Tiny white core
        bmp.fill_rect(hx + 1, hy + 1, 1, 1, Color.new(255, 255, 255, 200))
      end
    end

    # Draw sparkles
    @particles.each do |p|
      next unless p[:type] == :aetheris_sparkle
      fade = 1.0 - (p[:life].to_f / p[:max_life])
      alpha = (p[:brightness] * fade).to_i.clamp(0, 255)
      next if alpha < 10

      px = p[:x].to_i
      py = p[:y].to_i
      next if px < 0 || px >= bmp.width || py < 0 || py >= bmp.height

      sc = AETHERIS_WISP_COLORS[p[:color_idx]]
      col = Color.new(sc[0], sc[1], sc[2], alpha)
      bmp.fill_rect(px, py, p[:size], p[:size], col)
    end
  end

  #=============================================================================
  # Infernum Hellfire Effect
  #=============================================================================
  INFERNUM_FAMILY_ID = 7
  INFERNUM_EMBER_COUNT = 60          # Max embers alive
  INFERNUM_EMBER_SPAWN = 3           # Embers spawned per frame
  INFERNUM_FLAME_COUNT = 20          # Flame tongue positions around circle

  def infernum_active?
    @mode == :family && @items[@selected] && @items[@selected][:id] == INFERNUM_FAMILY_ID &&
      !animating_slide? && !animating_zoom?
  end

  def init_infernum_flames(cx, cy, radius)
    # Pre-generate flame tongue positions evenly around the circle edge
    @infernum_flames = []
    INFERNUM_FLAME_COUNT.times do |i|
      angle = (i.to_f / INFERNUM_FLAME_COUNT) * 2.0 * Math::PI
      @infernum_flames << {
        angle: angle,
        base_x: cx + Math.cos(angle) * radius,
        base_y: cy + Math.sin(angle) * radius,
        height: 5 + rand(10),        # Max flame height in pixels
        speed: 0.1 + rand(80) / 1000.0,  # Flicker speed
        phase: rand(628) / 100.0
      }
    end
  end

  def update_infernum(cx, cy, radius)
    return unless infernum_active?

    if !@infernum_flames || @infernum_flames.empty?
      init_infernum_flames(cx, cy, radius)
    end

    # Spawn embers from random points along the circle edge
    ember_count = @particles.count { |p| p[:type] == :ember }
    if ember_count < INFERNUM_EMBER_COUNT
      INFERNUM_EMBER_SPAWN.times do
        angle = rand(628) / 100.0
        sx = cx + Math.cos(angle) * (radius + rand(6))
        sy = cy + Math.sin(angle) * (radius + rand(6))
        @particles << {
          type: :ember,
          x: sx, y: sy,
          vx: (rand(20) - 10) / 10.0,   # Slight horizontal drift
          vy: -(1.0 + rand(20) / 10.0),  # Rise upward
          life: 0,
          max_life: 30 + rand(30),
          size: rand(4) == 0 ? 3 : (rand(3) == 0 ? 2 : 1),
          heat: rand(3)  # 0=hot white-yellow, 1=orange, 2=deep red
        }
      end
    end

    # Update embers - rise with slight drift and deceleration
    @particles.each do |p|
      next unless p[:type] == :ember
      p[:life] += 1
      p[:x] += p[:vx]
      p[:y] += p[:vy]
      p[:vx] *= 0.97
      p[:vy] *= 0.99   # Slowly decelerate upward
      p[:vx] += (rand(5) - 2) * 0.05  # Gentle random sway
    end

    @particles.reject! { |p| p[:type] == :ember && p[:life] >= p[:max_life] }
  end

  def draw_infernum_fx(cx, cy, radius)
    bmp = @sprites["fx"].bitmap
    bmp.clear

    has_flames = @infernum_flames && !@infernum_flames.empty?
    has_embers = @particles.any? { |p| p[:type] == :ember }
    return if !has_flames && !has_embers

    # Hot glow halo - deep orange/red
    2.times do |i|
      ring_r = radius + 2 + i * 4
      pulse = Math.sin(@frame * 0.05 + i * 1.2)
      alpha = (30 + pulse * 15).to_i.clamp(10, 55)
      glow_color = Color.new(255, 100 + i * 30, 20, alpha)
      draw_circle_outline(bmp, cx, cy, ring_r, glow_color)
    end

    # Draw flame tongues along circle edge
    if has_flames
      @infernum_flames.each do |flame|
        flicker = Math.sin(flame[:phase] + @frame * flame[:speed])
        h = ((flame[:height] * (0.4 + flicker * 0.6))).to_i
        next if h < 2

        bx = flame[:base_x].to_i
        by = flame[:base_y].to_i
        # Flame direction: outward from center
        dx = Math.cos(flame[:angle])
        dy = Math.sin(flame[:angle])

        # Draw flame as a few pixels stepping outward, getting dimmer
        h.times do |step|
          px = (bx + dx * step).to_i
          py = (by + dy * step).to_i
          next if px < 0 || px >= bmp.width || py < 0 || py >= bmp.height

          t = step.to_f / h  # 0 at base, 1 at tip
          # Color: bright yellow at base → orange → red at tip
          r = 255
          g = (255 - t * 200).to_i.clamp(30, 255)
          b_val = (80 - t * 80).to_i.clamp(0, 80)
          alpha = (200 - t * 140).to_i.clamp(30, 200)
          col = Color.new(r, g, b_val, alpha)
          bmp.fill_rect(px, py, 2, 2, col)
        end
      end
    end

    # Draw embers
    @particles.each do |p|
      next unless p[:type] == :ember
      fade = 1.0 - (p[:life].to_f / p[:max_life])
      alpha = (220 * fade).to_i.clamp(0, 220)
      next if alpha < 10

      px = p[:x].to_i
      py = p[:y].to_i
      next if px < 0 || px >= bmp.width || py < 0 || py >= bmp.height

      # Color based on heat level, fading to red as they die
      case p[:heat]
      when 0  # Hot: white-yellow → orange
        r = 255
        g = (255 * fade).to_i.clamp(100, 255)
        b_val = (120 * fade).to_i.clamp(0, 120)
      when 1  # Medium: orange → deep red
        r = 255
        g = (180 * fade).to_i.clamp(40, 180)
        b_val = (30 * fade).to_i.clamp(0, 30)
      else    # Cool: deep red → dark
        r = (220 * fade).to_i.clamp(60, 220)
        g = (60 * fade).to_i.clamp(10, 60)
        b_val = 0
      end
      col = Color.new(r, g, b_val, alpha)
      bmp.fill_rect(px, py, p[:size], p[:size], col)
    end
  end

  #=============================================================================
  # FX Fade helpers
  #=============================================================================
  def fx_wants_effect?
    return false if animating_slide? || animating_zoom?
    primordium_active? || vacuum_active? || astrum_active? || silva_active? || machina_active? || humanitas_active? || aetheris_active? || infernum_active?
  end

  def update_fx_opacity
    if fx_wants_effect?
      @fx_target_opacity = 255
    else
      @fx_target_opacity = 0
    end

    # Smoothly move toward target
    if @fx_opacity < @fx_target_opacity
      @fx_opacity = [@fx_opacity + @fx_fade_speed, @fx_target_opacity].min
    elsif @fx_opacity > @fx_target_opacity
      @fx_opacity = [@fx_opacity - @fx_fade_speed, @fx_target_opacity].max
    end

    # Apply to sprite
    @sprites["fx"].opacity = @fx_opacity if @sprites["fx"]

    # Once fully faded out, clean up all effect data
    if @fx_opacity <= 0
      has_anything = @particles.length > 0 || (@silva_roots && !@silva_roots.empty?) ||
                     (@machina_gears && !@machina_gears.empty?) ||
                     (@humanitas_nodes && !@humanitas_nodes.empty?) ||
                     (@aetheris_wisps && !@aetheris_wisps.empty?) ||
                     (@infernum_flames && !@infernum_flames.empty?)
      if has_anything
        @particles.clear
        @particle_timer = 0
        @silva_roots = nil
        @silva_flowers = nil
        @silva_grow_frame = 0
        @machina_gears = nil
        @machina_arcs = nil
        @humanitas_nodes = nil
        @humanitas_connections = nil
        @humanitas_pulses = nil
        @humanitas_pulse_timer = 0
        @aetheris_wisps = nil
        @infernum_flames = nil
        @sprites["fx"].bitmap.clear if @sprites["fx"]
      end
    end
  end

  #=============================================================================
  # Update (animation tick)
  #=============================================================================
  def update
    @frame += 1

    # Animate stars every 3 frames
    if @frame % 3 == 0
      draw_stars(@sprites["bg"].bitmap)
    end

    # Slide animation
    if animating_slide?
      update_slide
    elsif @frame % 2 == 0
      # Glow animation when idle
      draw_circles
    end

    # Zoom animation
    update_zoom if animating_zoom?

    # Family-specific effects (keep rendering during fade-out)
    cx = Graphics.width / 2
    cy = CIRCLE_LAYOUT[0][:y]
    r  = CIRCLE_LAYOUT[0][:radius]

    # Track which effect is active to detect switches
    current_fx = if primordium_active? then :primordium
                 elsif vacuum_active? then :vacuum
                 elsif astrum_active? then :astrum
                 elsif silva_active? then :silva
                 elsif machina_active? then :machina
                 elsif humanitas_active? then :humanitas
                 elsif aetheris_active? then :aetheris
                 elsif infernum_active? then :infernum
                 else nil end

    # If the effect type changed, let the old one fade out naturally
    if @fx_opacity > 0 || current_fx
      has_primordium = @particles.any? { |p| p[:type] == :genesis_mote }
      has_vacuum     = @particles.any? { |p| !p[:type] }
      has_astrum     = @particles.any? { |p| p[:type] == :orbiter }
      has_silva      = @silva_roots && !@silva_roots.empty?
      has_machina    = @machina_gears && !@machina_gears.empty?
      has_humanitas  = @humanitas_nodes && !@humanitas_nodes.empty?
      has_aetheris   = @aetheris_wisps && !@aetheris_wisps.empty?
      has_infernum   = @infernum_flames && !@infernum_flames.empty?

      # Helper to clean other effects when switching
      if current_fx
        @silva_roots = nil unless current_fx == :silva
        @machina_gears = nil unless current_fx == :machina
        @humanitas_nodes = nil unless current_fx == :humanitas
        @aetheris_wisps = nil unless current_fx == :aetheris
        @infernum_flames = nil unless current_fx == :infernum
      end

      if current_fx == :primordium || (!current_fx && has_primordium)
        @particles.reject! { |p| p[:type] != :genesis_mote } if current_fx == :primordium
        update_primordium(cx, cy, r)
        draw_primordium_fx(cx, cy, r)
      elsif current_fx == :vacuum || (!current_fx && has_vacuum && !has_astrum && !has_silva && !has_machina && !has_humanitas && !has_aetheris && !has_infernum)
        @particles.reject! { |p| p[:type] } if current_fx == :vacuum
        update_vacuum_particles(cx, cy, r)
        draw_vacuum_fx(cx, cy, r)
      elsif current_fx == :astrum || (!current_fx && has_astrum)
        @particles.reject! { |p| !p[:type] } if current_fx == :astrum
        update_astrum_particles(cx, cy, r)
        draw_astrum_fx(cx, cy, r)
      elsif current_fx == :silva || (!current_fx && has_silva)
        @particles.clear if current_fx == :silva
        update_silva(cx, cy, r)
        draw_silva_fx(cx, cy, r)
      elsif current_fx == :machina || (!current_fx && has_machina)
        @particles.reject! { |p| p[:type] != :spark } if current_fx == :machina
        update_machina(cx, cy, r)
        draw_machina_fx(cx, cy, r)
      elsif current_fx == :humanitas || (!current_fx && has_humanitas)
        @particles.clear if current_fx == :humanitas
        update_humanitas(cx, cy, r)
        draw_humanitas_fx(cx, cy, r)
      elsif current_fx == :aetheris || (!current_fx && has_aetheris)
        @particles.reject! { |p| p[:type] != :aetheris_sparkle } if current_fx == :aetheris
        update_aetheris(cx, cy, r)
        draw_aetheris_fx(cx, cy, r)
      elsif current_fx == :infernum || (!current_fx && has_infernum)
        @particles.reject! { |p| p[:type] != :ember } if current_fx == :infernum
        update_infernum(cx, cy, r)
        draw_infernum_fx(cx, cy, r)
      end
    end

    # Smooth fade in/out
    update_fx_opacity

    pbUpdateSpriteHash(@sprites)
  end

  def move_left
    return if animating_slide? || animating_zoom?
    start_slide(-1)
    @slide_frame = 1
  end

  def move_right
    return if animating_slide? || animating_zoom?
    start_slide(1)
    @slide_frame = 1
  end

  def busy?
    animating_slide? || animating_zoom?
  end

  def current_selection
    return @selected
  end

  def pbEndScene(restore_bgm: true)
    pbFadeOutAndHide(@sprites)
    pbDisposeSpriteHash(@sprites)
    @viewport.dispose
    # Restore BGM
    if restore_bgm && @old_bgm
      pbBGMPlay(@old_bgm)
      @old_bgm = nil
    end
  end

  def pbEndSceneNoFade
    pbDisposeSpriteHash(@sprites)
    @viewport.dispose
  end
end

#===============================================================================
# Screen controller - handles input loop and returns selection
#===============================================================================
class ResonanceCoreUI_Screen
  def initialize(scene)
    @scene = scene
  end

  # Returns selected index or -1 if cancelled
  def pbSelectFromList(items, mode = :family)
    @scene.pbStartScene(items, mode)
    ret = -1

    loop do
      @scene.update
      Graphics.update
      Input.update
      pbUpdateSceneMap

      # Don't accept input during animations
      next if @scene.busy?

      if Input.trigger?(Input::LEFT)
        pbPlayCursorSE
        @scene.move_left
      elsif Input.trigger?(Input::RIGHT)
        pbPlayCursorSE
        @scene.move_right
      elsif Input.trigger?(Input::USE)
        pbPlayDecisionSE
        # Start zoom-in animation
        @scene.start_zoom(:zoom_in)
        # Wait for zoom to finish
        while !@scene.zoom_finished?
          @scene.update
          Graphics.update
          Input.update
        end
        ret = @scene.current_selection
        break
      elsif Input.trigger?(Input::BACK)
        pbPlayCloseMenuSE
        if mode == :subfamily
          # Zoom-out animation when going back to families
          @scene.start_zoom(:zoom_out)
          while !@scene.zoom_finished?
            @scene.update
            Graphics.update
            Input.update
          end
        end
        ret = -1
        break
      end
    end

    @scene.pbEndScene(restore_bgm: false)
    return ret
  end
end

#===============================================================================
# Public helper: Open the Resonance Core selection flow
# Returns [family, subfamily] or nil if cancelled
#===============================================================================
def pbResonanceCoreSelectFamily
  # Save BGM once at the start
  old_bgm = $game_system.playing_bgm.clone if $game_system.playing_bgm
  if ResonanceCoreUI_Scene::SELECTION_BGM
    pbBGMPlay(ResonanceCoreUI_Scene::SELECTION_BGM, ResonanceCoreUI_Scene::SELECTION_VOLUME)
  end

  # Build family items list
  family_items = []
  PokemonFamilyConfig::FAMILIES.each do |id, data|
    base_idx = id * 4
    colors = PokemonFamilyConfig::SUBFAMILIES[base_idx][:colors]
    family_items << {
      id: id,
      name: data[:name],
      colors: colors,
      effect: data[:effect],
      weight: data[:weight]
    }
  end

  shared_stars = nil
  chosen_family = nil
  chosen_subfamily = nil
  last_family_idx = 0       # Remember which family was selected
  pending_family_scene = nil # Pre-created family scene from seamless back transition

  loop do
    # Phase 1: Pick family
    if pending_family_scene
      # Reuse the family scene that was created during the seamless zoom-out
      scene = pending_family_scene
      pending_family_scene = nil
    else
      scene = ResonanceCoreUI_Scene.new
      scene.instance_variable_set(:@old_bgm, nil)  # Don't let scene touch BGM
      scene.pbStartScene(family_items, :family, skip_bgm: true, shared_stars: shared_stars,
                         starting_index: last_family_idx)
    end
    family_idx = -1

    loop do
      scene.update
      Graphics.update
      Input.update
      pbUpdateSceneMap
      next if scene.busy?

      if Input.trigger?(Input::LEFT)
        pbPlayCursorSE
        scene.move_left
      elsif Input.trigger?(Input::RIGHT)
        pbPlayCursorSE
        scene.move_right
      elsif Input.trigger?(Input::USE)
        pbPlayDecisionSE
        scene.start_zoom(:zoom_in)
        while !scene.zoom_finished?
          scene.update
          Graphics.update
          Input.update
        end
        family_idx = scene.current_selection
        break
      elsif Input.trigger?(Input::BACK)
        pbPlayCloseMenuSE
        family_idx = -1
        break
      end
    end

    shared_stars = scene.stars
    scene.pbEndSceneNoFade

    if family_idx < 0
      # Cancelled from family selection - exit entirely
      chosen_family = nil
      break
    end

    last_family_idx = family_idx  # Remember for if we come back
    chosen_family_id = family_items[family_idx][:id]

    # Build subfamily items
    sub_items = []
    base = chosen_family_id * 4
    (0..3).each do |local_sub|
      global_idx = base + local_sub
      sub_data = PokemonFamilyConfig::SUBFAMILIES[global_idx]
      sub_items << {
        id: local_sub,
        global_index: global_idx,
        name: sub_data[:name],
        colors: sub_data[:colors],
        weight: sub_data[:weight]
      }
    end

    # Phase 2: Pick subfamily
    scene2 = ResonanceCoreUI_Scene.new
    scene2.pbStartScene(sub_items, :subfamily, skip_bgm: true, shared_stars: shared_stars)
    sub_idx = -1

    loop do
      scene2.update
      Graphics.update
      Input.update
      pbUpdateSceneMap
      next if scene2.busy?

      if Input.trigger?(Input::LEFT)
        pbPlayCursorSE
        scene2.move_left
      elsif Input.trigger?(Input::RIGHT)
        pbPlayCursorSE
        scene2.move_right
      elsif Input.trigger?(Input::USE)
        pbPlayDecisionSE
        scene2.start_zoom(:zoom_in)
        while !scene2.zoom_finished?
          scene2.update
          Graphics.update
          Input.update
        end
        sub_idx = scene2.current_selection
        break
      elsif Input.trigger?(Input::BACK)
        pbPlayCloseMenuSE
        sub_idx = -1
        break
      end
    end

    shared_stars = scene2.stars

    if sub_idx < 0
      # Seamless zoom-out transition back to families:
      # 1. Create family scene underneath (lower z, no fade-in, instant)
      family_bg = ResonanceCoreUI_Scene.new
      family_bg.instance_variable_set(:@old_bgm, nil)
      family_bg.pbStartScene(family_items, :family, skip_bgm: true, shared_stars: shared_stars,
                             starting_index: last_family_idx, no_fade_in: true, viewport_z: 99998)
      # 2. Shrink out the subfamily scene on top - family is visible underneath
      scene2.start_zoom(:shrink_out)
      while !scene2.zoom_finished?
        family_bg.update  # Keep family scene alive (stars, effects)
        scene2.update
        Graphics.update
        Input.update
      end
      # 3. Destroy the subfamily overlay - family is fully revealed
      scene2.pbEndSceneNoFade
      # 4. Promote the family viewport to normal z
      family_bg.instance_variable_get(:@viewport).z = 99999
      # 5. Hand off to next iteration - reuse this scene instead of creating a new one
      pending_family_scene = family_bg
      next
    end

    scene2.pbEndSceneNoFade

    # Both selected!
    chosen_family = chosen_family_id
    chosen_subfamily = sub_items[sub_idx][:id]
    break
  end

  # Restore original BGM
  if old_bgm
    pbBGMPlay(old_bgm)
  else
    pbBGMStop(1.0)
  end

  return nil if chosen_family.nil?
  return [chosen_family, chosen_subfamily]
end

#===============================================================================
# Debug
#===============================================================================
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("RESONANCE-CORE", "=" * 60)
  MultiplayerDebug.info("RESONANCE-CORE", "011_ResonanceCoreUI.rb loaded")
  MultiplayerDebug.info("RESONANCE-CORE", "  Carousel UI with slide animation, zoom transitions, BGM")
  MultiplayerDebug.info("RESONANCE-CORE", "=" * 60)
end
