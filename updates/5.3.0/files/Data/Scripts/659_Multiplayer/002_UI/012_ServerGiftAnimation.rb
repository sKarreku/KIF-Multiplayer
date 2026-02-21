#===============================================================================
# ServerGiftAnimation
# Plays a gift-falling-from-sky animation on the overworld when the server
# gives an item to the player. Queued and played when player is not busy.
#===============================================================================
module ServerGiftAnimation
  @gift_queue = []
  @mutex      = Mutex.new
  @playing    = false

  module_function

  def queue(item_name, qty)
    @mutex.synchronize { @gift_queue << { item_name: item_name.to_s, qty: qty.to_i } }
  end

  def pending?
    @mutex.synchronize { !@gift_queue.empty? }
  end

  def playing?
    @playing
  end

  def play_next
    gift = @mutex.synchronize { @gift_queue.shift }
    return unless gift
    @playing = true
    begin
      run_animation(gift[:item_name], gift[:qty])
    rescue => e
      # Never crash the game
    ensure
      @playing = false
    end
  end

  # ---------------------------------------------------------------------------
  # Draws a 3D isometric gift box using only fill_rect.
  # 48x48 bitmap:
  #   - Top face   (y  0..11) : lighter red, parallelogram going top-right
  #   - Right face (x 36..47) : dark red,    parallelogram going down-right
  #   - Front face (x  0..35, y 12..47) : medium red
  #   - Gold ribbon on all three faces
  #   - Gold bow on top
  # ---------------------------------------------------------------------------
  def draw_3d_gift_bitmap
    bmp = Bitmap.new(48, 48)

    c_top   = Color.new(250, 110, 110)   # light red  — top face (bright)
    c_front = Color.new(210,  40,  40)   # medium red — front face
    c_right = Color.new(135,  10,  10)   # dark red   — right face (shadow)
    c_edge  = Color.new( 55,   0,   0)   # near-black edge
    c_rib   = Color.new(255, 210,   0)   # gold ribbon
    c_bow   = Color.new(255, 230,  70)   # bow petals
    c_knot  = Color.new(255, 248, 150)   # bow centre knot
    c_hi    = Color.new(255, 160, 160)   # top-left highlight edge

    # Top face  — for row y: starts at x=(12-y), width=36
    12.times { |y| bmp.fill_rect(12 - y, y, 36, 1, c_top) }

    # Right face — for column offset i (x=36+i): starts at y=(12-i), height=36
    12.times { |i| bmp.fill_rect(36 + i, 12 - i, 1, 36, c_right) }

    # Front face
    bmp.fill_rect(0, 12, 36, 36, c_front)

    # Edge: top-face/front-face junction (horizontal dark line at y=12)
    bmp.fill_rect(0, 12, 36, 1, c_edge)

    # Edge: top-face/right-face junction (diagonal)
    12.times { |i| bmp.fill_rect(35 + i, 12 - i, 1, 1, c_edge) }

    # Highlight: top-face left edge (diagonal bright strip)
    12.times { |y| bmp.fill_rect(12 - y, y, 1, 1, c_hi) }

    # Bottom edge of right face (dark line)
    12.times { |i| bmp.fill_rect(36 + i, 47 - i, 1, 1, c_edge) }

    # --- Ribbon: vertical strip on FRONT ---
    bmp.fill_rect(14, 12, 6, 36, c_rib)

    # --- Ribbon: horizontal strip on FRONT ---
    bmp.fill_rect(0, 27, 36, 6, c_rib)

    # --- Ribbon on TOP (vertical strip going "back", shifts right as y falls) ---
    # At front edge y=12: x=14. Each row up adds 1 to x (iso shift).
    # fill_rect(14+(12-y), y, 6, 1) = fill_rect(26-y, y, 6, 1)
    12.times { |y| bmp.fill_rect(26 - y, y, 6, 1, c_rib) }

    # --- Ribbon on RIGHT face (horizontal strip, same height as front's horiz ribbon) ---
    # Front ribbon at y=27..32. Relative to front top (y=12): offset=15, height=6.
    # Right face column i: top_y=12-i. ribbon_y = (12-i)+15 = 27-i
    12.times { |i| bmp.fill_rect(36 + i, 27 - i, 1, 6, c_rib) }

    # --- Bow on TOP face (centred roughly on the ribbon intersection) ---
    bmp.fill_rect(12, 2,  9, 6, c_bow)    # left petal
    bmp.fill_rect(24, 2,  9, 6, c_bow)    # right petal
    bmp.fill_rect(19, 1,  7, 8, c_knot)   # centre knot

    bmp
  end

  def run_animation(item_name, qty)
    vp   = Viewport.new(0, 0, Graphics.width, Graphics.height)
    vp.z = 99999

    # --- Black cinematic overlay ---
    bbmp = Bitmap.new(Graphics.width, Graphics.height)
    bbmp.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0))
    bspr         = Sprite.new(vp)
    bspr.bitmap  = bbmp
    bspr.z       = 0
    bspr.opacity = 0

    # --- 3D Gift (drawn in code) ---
    gspr         = Sprite.new(vp)
    gspr.bitmap  = draw_3d_gift_bitmap
    gspr.ox      = 24          # pivot at horizontal centre of 48px bitmap
    gspr.oy      = 24          # pivot at vertical  centre
    gspr.zoom_x  = 2.0         # scale 48px → 96px on screen
    gspr.zoom_y  = 2.0
    gspr.z       = 2
    gspr.x       = Graphics.width / 2
    gspr.y       = -110        # start above screen

    # --- Confetti ---
    palette = [
      Color.new(255,  60,  60), Color.new( 60, 220,  60), Color.new( 60, 100, 255),
      Color.new(255, 230,   0), Color.new(220,  60, 220), Color.new(  0, 220, 220),
      Color.new(255, 140,   0), Color.new(140,  60, 255)
    ]
    confetti = []
    vels     = []
    28.times do
      cb = Bitmap.new(7, 5)
      cb.fill_rect(0, 0, 7, 5, palette[rand(palette.length)])
      cs         = Sprite.new(vp)
      cs.bitmap  = cb
      cs.ox = 3; cs.oy = 2
      cs.x       = Graphics.width  / 2
      cs.y       = Graphics.height / 2
      cs.opacity = 0
      cs.z       = 3
      confetti << cs
      ang  = rand(360) * Math::PI / 180.0
      spd  = rand(40) / 10.0 + 2.0
      vels << [Math.cos(ang) * spd, -Math.sin(ang).abs * spd - 2.0, rand(8) - 4]
    end

    # --- Message ---
    label        = "The server blesses you with #{item_name} x#{qty}!"
    mbmp         = Bitmap.new(Graphics.width, 52)
    mbmp.font.size = 20
    mbmp.font.bold = true
    mbmp.font.color = Color.new(0, 0, 0, 200)
    mbmp.draw_text(2, 2, Graphics.width, 48, label, 1)
    mbmp.font.color = Color.new(255, 240, 150)
    mbmp.draw_text(0, 0, Graphics.width, 48, label, 1)
    mspr         = Sprite.new(vp)
    mspr.bitmap  = mbmp
    mspr.x       = 0
    mspr.y       = Graphics.height - 80
    mspr.z       = 4
    mspr.opacity = 0

    cy = Graphics.height / 2 - 30   # gift landing Y

    # =========================================================================
    # Phase 0 — Black fade in (25 frames)
    # =========================================================================
    25.times do |i|
      bspr.opacity = (170 * (i + 1) / 25)
      Graphics.update
    end

    # =========================================================================
    # Phase 1 — Fall (55 frames, ease-in / accelerating)
    # =========================================================================
    55.times do |i|
      t      = i / 54.0
      gspr.y = -110 + (cy + 110) * (t * t)
      Graphics.update
    end
    gspr.y = cy

    # =========================================================================
    # Phase 2 — Bounce (settle into landing position)
    # =========================================================================
    [[cy - 22, 7], [cy + 5, 6], [cy - 9, 6], [cy + 2, 5], [cy, 4]].each do |ty, steps|
      sy = gspr.y
      steps.times do |i|
        gspr.y = sy + (ty - sy) * ((i + 1).to_f / steps)
        Graphics.update
      end
    end

    # =========================================================================
    # Phase 3 — Awkward rotation + confetti explosion
    # =========================================================================
    confetti.each { |s| s.opacity = 255 }
    gravity = 0.35
    # pendulum sequence: overshoots and dampens to 0
    [[42, 10], [-58, 12], [36, 10], [-27, 9], [20, 8], [-12, 7], [7, 6], [-3, 5], [0, 5]].each do |ta, steps|
      sa = gspr.angle
      steps.times do |i|
        t          = (i + 1).to_f / steps
        gspr.angle = sa + (ta - sa) * t
        confetti.each_with_index do |s, idx|
          v    = vels[idx]
          s.x += v[0]; s.y += v[1]
          v[1] += gravity
          v[0] *= 0.97
          s.angle = (s.angle + v[2]) % 360
        end
        mspr.opacity = [mspr.opacity + 15, 255].min
        Graphics.update
      end
      gspr.angle = ta
    end

    # =========================================================================
    # Phase 4 — Hold (70 frames)
    # =========================================================================
    70.times do
      confetti.each_with_index do |s, idx|
        v    = vels[idx]
        s.x += v[0]; s.y += v[1]
        v[1] += gravity
        v[0] *= 0.97
        s.angle = (s.angle + v[2]) % 360
      end
      Graphics.update
    end

    # =========================================================================
    # Phase 5 — Fade everything out including black overlay (40 frames)
    # =========================================================================
    40.times do |i|
      t            = i / 39.0
      gspr.opacity = (255 * (1 - t)).to_i
      mspr.opacity = (255 * (1 - t)).to_i
      bspr.opacity = (170 * (1 - t)).to_i
      confetti.each { |s| s.opacity = [(255 * (1 - t)).to_i, s.opacity].min }
      Graphics.update
    end

  ensure
    bspr.bitmap.dispose rescue nil; bspr.dispose rescue nil
    gspr.bitmap.dispose rescue nil; gspr.dispose rescue nil
    mspr.bitmap.dispose rescue nil; mspr.dispose rescue nil
    confetti.each { |s| s.bitmap.dispose rescue nil; s.dispose rescue nil }
    vp.dispose rescue nil
  end
end
