#===============================================================================
# MODULE 7: Boss Pokemon System - Custom UI
#===============================================================================
# Creates custom boss battle UI with:
#   - Centered name display at top (Family / Subfamily / Species)
#   - Full-width HP bar
#   - Phase counter (x4, x3, x2, x1)
#   - Shield display (7 pink icons)
#   - Hidden standard databox
#
# Works with both EBDX and standard battle systems.
#
# Test: Encounter boss, visually verify UI elements.
#===============================================================================

MultiplayerDebug.info("BOSS", "Loading 206_Boss_UI.rb...") if defined?(MultiplayerDebug)

#===============================================================================
# Boss Databox Sprite
#===============================================================================
class BossDataBoxSprite
  attr_accessor :visible
  attr_reader :animatingHP  # EBDX checks this to know when HP animation is done

  # Damage color constant (same as EBDX)
  DAMAGE_COLOR = Color.new(221, 82, 71)

  def initialize(viewport, battler)
    @viewport = viewport
    @battler = battler
    @pokemon = battler.pokemon
    @sprites = {}
    @visible = true
    @damage_alpha = 0  # Track damage flash alpha for fade-out

    # HP animation state (matches EBDX)
    @animatingHP = false
    @currenthp = @battler.hp.to_f
    @starthp = @battler.hp.to_f
    @endhp = @battler.hp.to_f

    # Track shield/phase state for detecting changes during update
    @prev_shields = @pokemon.boss_shields
    @prev_phase = @pokemon.boss_hp_phase

    create_sprites
    refresh

    MultiplayerDebug.info("BOSS-UI", "Created BossDataBoxSprite for #{@pokemon.speciesName}, shields=#{@prev_shields}, phase=#{@prev_phase}") if defined?(MultiplayerDebug)
  end

  #=============================================================================
  # Create All Sprite Components
  #=============================================================================
  def create_sprites
    # Name label (centered at top)
    @sprites[:name_bg] = Sprite.new(@viewport)
    @sprites[:name_bg].bitmap = Bitmap.new(Graphics.width, 50)
    @sprites[:name_bg].bitmap.fill_rect(0, 0, Graphics.width, 50, Color.new(0, 0, 0, 150))
    @sprites[:name_bg].y = 0
    @sprites[:name_bg].z = 200

    @sprites[:name] = Sprite.new(@viewport)
    @sprites[:name].bitmap = Bitmap.new(Graphics.width, 50)
    @sprites[:name].y = 0
    @sprites[:name].z = 201

    # HP bar background (full width - margins)
    hp_bar_width = Graphics.width - 60
    @sprites[:hpbg] = Sprite.new(@viewport)
    @sprites[:hpbg].bitmap = Bitmap.new(hp_bar_width + 4, 24)
    @sprites[:hpbg].bitmap.fill_rect(0, 0, hp_bar_width + 4, 24, Color.new(20, 20, 20))
    @sprites[:hpbg].bitmap.fill_rect(2, 2, hp_bar_width, 20, Color.new(60, 60, 60))
    @sprites[:hpbg].x = 30
    @sprites[:hpbg].y = 55
    @sprites[:hpbg].z = 200

    # HP bar fill - created at full width, use zoom_x to animate
    @hp_bar_max_width = hp_bar_width - 4
    @sprites[:hpbar] = Sprite.new(@viewport)
    @sprites[:hpbar].bitmap = Bitmap.new(@hp_bar_max_width, 16)
    @sprites[:hpbar].bitmap.fill_rect(0, 0, @hp_bar_max_width, 16, Color.new(0, 200, 50))  # Green by default
    @sprites[:hpbar].x = 34
    @sprites[:hpbar].y = 59
    @sprites[:hpbar].z = 201

    # Phase counter (right side)
    @sprites[:phase] = Sprite.new(@viewport)
    @sprites[:phase].bitmap = Bitmap.new(80, 30)
    @sprites[:phase].x = Graphics.width - 100
    @sprites[:phase].y = 82
    @sprites[:phase].z = 201

    # Shield display (below HP bar) - sized by this boss's max shields
    @max_shields = @pokemon.boss_max_shields
    @sprites[:shields] = Sprite.new(@viewport)
    @sprites[:shields].bitmap = Bitmap.new(@max_shields * 24 + 10, 28)
    @sprites[:shields].x = 30
    @sprites[:shields].y = 82
    @sprites[:shields].z = 201

    # Shield label
    @sprites[:shield_label] = Sprite.new(@viewport)
    @sprites[:shield_label].bitmap = Bitmap.new(100, 28)
    @sprites[:shield_label].x = 30 + @max_shields * 24 + 15
    @sprites[:shield_label].y = 82
    @sprites[:shield_label].z = 201

    # Status effects display (next to phase counter)
    @sprites[:status] = Sprite.new(@viewport)
    @sprites[:status].bitmap = Bitmap.new(150, 30)
    @sprites[:status].x = Graphics.width - 250
    @sprites[:status].y = 82
    @sprites[:status].z = 201
  end

  #=============================================================================
  # Refresh All Elements
  #=============================================================================
  def refresh
    return unless @pokemon&.is_boss?

    draw_boss_name
    draw_hp_bar
    draw_phase_counter
    draw_shields
    draw_status
  end

  #=============================================================================
  # Draw Boss Name: "Family  Subfamily  Species" (no slashes, scaled if needed)
  # Family and Subfamily use standard font, only Species uses custom family font
  #=============================================================================
  def draw_boss_name
    bitmap = @sprites[:name].bitmap
    bitmap.clear

    # Get family and subfamily names
    family_name = nil
    subfamily_name = nil
    family_font = nil

    if defined?(PokemonFamilyConfig) && @pokemon.respond_to?(:family) && @pokemon.family
      family_data = PokemonFamilyConfig::FAMILIES[@pokemon.family]
      if family_data
        family_name = family_data[:name]
        family_font = family_data[:font_name]
      end

      if @pokemon.respond_to?(:subfamily) && @pokemon.subfamily
        global_subfamily = @pokemon.family * 4 + @pokemon.subfamily
        subfamily_data = PokemonFamilyConfig::SUBFAMILIES[global_subfamily]
        subfamily_name = subfamily_data[:name] if subfamily_data
      end
    end

    species_name = @pokemon.speciesName rescue @pokemon.species.to_s

    text_color = Color.new(255, 255, 255)
    outline_color = Color.new(40, 40, 40)
    standard_font = "Pokemon DS"

    # Start with base font size, scale down if too wide
    base_size = 28
    bitmap.font.bold = true

    # Build the parts without slashes
    parts = []
    parts << { text: family_name, font: standard_font } if family_name
    parts << { text: subfamily_name, font: standard_font } if subfamily_name
    parts << { text: species_name, font: family_font || standard_font }

    # If no family, just show "BOSS Species"
    if parts.length == 1
      parts.unshift({ text: "BOSS", font: standard_font })
    end

    # Calculate total width and scale if needed
    font_size = base_size
    spacing = 20  # Space between parts
    max_width = Graphics.width - 40

    loop do
      bitmap.font.size = font_size
      total_width = 0
      parts.each_with_index do |part, i|
        bitmap.font.name = part[:font] rescue standard_font
        total_width += bitmap.text_size(part[:text]).width
        total_width += spacing if i < parts.length - 1
      end

      break if total_width <= max_width || font_size <= 16
      font_size -= 2
    end

    # Calculate starting position for centered text
    bitmap.font.size = font_size
    total_width = 0
    parts.each_with_index do |part, i|
      bitmap.font.name = part[:font] rescue standard_font
      total_width += bitmap.text_size(part[:text]).width
      total_width += spacing if i < parts.length - 1
    end
    start_x = (Graphics.width - total_width) / 2
    y_pos = (50 - font_size) / 2  # Center vertically in 50px height

    # Draw each part
    current_x = start_x
    parts.each_with_index do |part, i|
      bitmap.font.name = part[:font] rescue standard_font
      bitmap.font.size = font_size
      part_width = bitmap.text_size(part[:text]).width
      pbDrawOutlineText(bitmap, current_x, y_pos, part_width + 10, font_size + 4, part[:text], text_color, outline_color, 0)
      current_x += part_width + spacing
    end

    bitmap.font.name = standard_font
  end

  #=============================================================================
  # Draw HP Bar - Shows FULL bar per phase (x4 = full bar, x3 = full bar, etc.)
  #=============================================================================
  def draw_hp_bar
    # Use @currenthp if animating, otherwise use battler.hp
    current = @animatingHP ? @currenthp : @battler.hp
    total = @battler.totalhp
    phase = @pokemon.boss_hp_phase
    num_phases = BossConfig::HP_PHASES  # 4

    # Calculate HP per phase
    hp_per_phase = total.to_f / num_phases

    # Calculate the HP range for the current phase
    # Phase 4: 100%-75%, Phase 3: 75%-50%, etc.
    phase_max = phase * hp_per_phase
    phase_min = (phase - 1) * hp_per_phase

    # Calculate ratio within the current phase (0.0 to 1.0)
    if phase > 0
      hp_in_phase = current - phase_min
      hp_ratio = hp_in_phase / hp_per_phase
      hp_ratio = 0 if hp_ratio < 0
      hp_ratio = 1 if hp_ratio > 1
    else
      hp_ratio = 0
    end

    # Use zoom_x for fast width changes (no bitmap redraw needed)
    @sprites[:hpbar].zoom_x = hp_ratio

    # Determine color zone based on phase HP ratio
    new_zone = hp_ratio > 0.5 ? 0 : (hp_ratio > 0.25 ? 1 : 2)
    @hp_color_zone ||= -1

    # Only redraw bitmap when color zone changes (not every frame)
    if new_zone != @hp_color_zone
      @hp_color_zone = new_zone
      color = case new_zone
        when 0 then Color.new(0, 200, 50)   # Green
        when 1 then Color.new(255, 200, 0)  # Yellow
        else Color.new(220, 50, 50)         # Red
      end
      bitmap = @sprites[:hpbar].bitmap
      bitmap.clear
      bitmap.fill_rect(0, 0, @hp_bar_max_width, 16, color)
      # Add darker edge for 3D effect
      darker = Color.new([color.red - 40, 0].max, [color.green - 40, 0].max, [color.blue - 40, 0].max)
      bitmap.fill_rect(0, 13, @hp_bar_max_width, 3, darker)
    end
  end

  #=============================================================================
  # Draw Phase Counter
  #=============================================================================
  def draw_phase_counter
    bitmap = @sprites[:phase].bitmap
    bitmap.clear

    phase = @pokemon.boss_hp_phase

    text = "x#{phase}"
    bitmap.font.size = 24
    bitmap.font.bold = true

    # Color based on remaining phases
    color = case phase
      when 4 then Color.new(100, 255, 100)
      when 3 then Color.new(200, 255, 100)
      when 2 then Color.new(255, 200, 100)
      when 1 then Color.new(255, 100, 100)
      else Color.new(150, 150, 150)
    end

    pbDrawOutlineText(bitmap, 0, 0, 80, 30, text, color, Color.new(0, 0, 0), 2)
  end

  #=============================================================================
  # Draw Shield Icons
  #=============================================================================
  def draw_shields
    bitmap = @sprites[:shields].bitmap
    bitmap.clear

    shields = @pokemon.boss_shields
    max_shields = @max_shields || @pokemon.boss_max_shields

    # Draw each shield slot
    max_shields.times do |i|
      x = i * 24 + 2
      y = 4

      if i < shields
        # Active shield - pink/magenta
        draw_shield_icon(bitmap, x, y, true)
      else
        # Broken shield - gray
        draw_shield_icon(bitmap, x, y, false)
      end
    end

    # Draw shield count label (electric blue to match shields)
    label_bitmap = @sprites[:shield_label].bitmap
    label_bitmap.clear
    if shields > 0
      label_bitmap.font.size = 18
      # Electric blue color matching the shields
      pbDrawOutlineText(label_bitmap, 0, 4, 100, 24, "#{shields}/#{max_shields}", Color.new(100, 200, 255), Color.new(0, 0, 0), 0)
    end
  end

  #=============================================================================
  # Draw Single Shield Icon - Looks like actual shield with electric blue glow
  #=============================================================================
  def draw_shield_icon(bitmap, x, y, active)
    if active
      # Active shield - Deep blue electric color with cyan glow
      outline = Color.new(0, 100, 200)       # Deep blue outline
      color1 = Color.new(30, 144, 255)       # Electric blue (dodger blue)
      color2 = Color.new(0, 191, 255)        # Deep sky blue (brighter)
      highlight = Color.new(135, 206, 250)   # Light sky blue highlight
      glow = Color.new(0, 255, 255, 100)     # Cyan glow (semi-transparent)
    else
      # Inactive shield - Gray/faded
      outline = Color.new(60, 60, 60)
      color1 = Color.new(80, 80, 80)
      color2 = Color.new(70, 70, 70)
      highlight = Color.new(100, 100, 100)
      glow = nil
    end

    # Shield shape - pointed bottom like a heraldic shield
    # Width: 18, Height: 22

    # Glow effect for active shields
    if glow
      bitmap.fill_rect(x, y - 1, 20, 24, glow)
    end

    # Outer outline (shield shape)
    bitmap.fill_rect(x + 1, y, 18, 2, outline)       # Top
    bitmap.fill_rect(x, y + 2, 2, 12, outline)       # Left side
    bitmap.fill_rect(x + 18, y + 2, 2, 12, outline)  # Right side
    bitmap.fill_rect(x + 1, y + 14, 4, 2, outline)   # Bottom left angle
    bitmap.fill_rect(x + 15, y + 14, 4, 2, outline)  # Bottom right angle
    bitmap.fill_rect(x + 4, y + 16, 3, 2, outline)   # Lower left
    bitmap.fill_rect(x + 13, y + 16, 3, 2, outline)  # Lower right
    bitmap.fill_rect(x + 7, y + 18, 6, 2, outline)   # Bottom point

    # Inner fill (main shield body)
    bitmap.fill_rect(x + 2, y + 2, 16, 12, color1)

    # Gradient effect - darker at bottom
    bitmap.fill_rect(x + 2, y + 10, 16, 4, color2)

    # Bottom triangle fill
    bitmap.fill_rect(x + 4, y + 14, 12, 2, color1)
    bitmap.fill_rect(x + 6, y + 16, 8, 2, color1)
    bitmap.fill_rect(x + 8, y + 18, 4, 1, color2)

    # Highlight on top-left for 3D effect
    bitmap.fill_rect(x + 3, y + 3, 6, 2, highlight)
    bitmap.fill_rect(x + 3, y + 5, 3, 3, highlight)
  end

  #=============================================================================
  # Draw Status Effects
  #=============================================================================
  def draw_status
    bitmap = @sprites[:status].bitmap
    bitmap.clear

    status = @battler.status
    return if status == :NONE || status.nil?

    # Get status name and color
    status_data = GameData::Status.get(status) rescue nil
    return unless status_data

    status_name = status_data.name rescue status.to_s
    status_color = case status
      when :POISON, :TOXIC then Color.new(180, 80, 200)
      when :BURN then Color.new(255, 100, 50)
      when :PARALYSIS then Color.new(255, 220, 50)
      when :SLEEP then Color.new(150, 150, 200)
      when :FROZEN then Color.new(100, 200, 255)
      else Color.new(200, 200, 200)
    end

    bitmap.font.size = 18
    bitmap.font.bold = true
    pbDrawOutlineText(bitmap, 0, 4, 150, 24, status_name, status_color, Color.new(0, 0, 0), 2)
  end

  #=============================================================================
  # Visibility Control
  #=============================================================================
  def visible=(val)
    @visible = val
    @sprites.each_value { |s| s.visible = val if s }
  end

  def show
    self.visible = true
  end

  def hide
    self.visible = false
  end

  #=============================================================================
  # Dispose
  #=============================================================================
  def dispose
    @sprites.each_value { |s| s.dispose if s && !s.disposed? }
    @sprites.clear
  end

  def disposed?
    @sprites.empty? || @sprites.values.all? { |s| s.nil? || s.disposed? }
  end

  #=============================================================================
  # Update (called each frame) - Handles animations
  #=============================================================================
  def update
    return if disposed?

    # DEBUG: Log every update call
    @update_count ||= 0
    @update_count += 1
    if @update_count % 10 == 1  # Log every 10th frame to avoid spam
      MultiplayerDebug.info("BOSS-UPDATE", "Frame #{@update_count}: dmg_alpha=#{@damage_alpha}, animHP=#{@animatingHP}, cur=#{@currenthp.to_i}, end=#{@endhp.to_i}") if defined?(MultiplayerDebug)
    end

    # Gradually fade out damage color (same as EBDX: alpha -= 16 per frame)
    if @damage_alpha > 0
      @damage_alpha -= 16
      @damage_alpha = 0 if @damage_alpha < 0
      apply_damage_color
    end

    # Track previous shield/phase values to detect changes
    @prev_shields ||= @pokemon.boss_shields
    @prev_phase ||= @pokemon.boss_hp_phase

    # Check if shields or phase changed (e.g., after damage inflicted)
    shields_changed = @prev_shields != @pokemon.boss_shields
    phase_changed = @prev_phase != @pokemon.boss_hp_phase

    if shields_changed || phase_changed
      MultiplayerDebug.info("BOSS-UPDATE", "State changed! Shields: #{@prev_shields}->#{@pokemon.boss_shields}, Phase: #{@prev_phase}->#{@pokemon.boss_hp_phase}") if defined?(MultiplayerDebug)
      draw_shields
      draw_phase_counter
      @prev_shields = @pokemon.boss_shields
      @prev_phase = @pokemon.boss_hp_phase
    end

    # HP animation (matches EBDX logic)
    if @animatingHP
      if @currenthp < @endhp
        @currenthp += (@endhp - @currenthp) / 10.0
        @currenthp = @currenthp.ceil
        @currenthp = @endhp if @currenthp > @endhp
      elsif @currenthp > @endhp
        @currenthp -= (@currenthp - @endhp) / 10.0
        @currenthp = @currenthp.floor
        @currenthp = @endhp if @currenthp < @endhp
      end
      draw_hp_bar
      # Use integer comparison to avoid float precision issues
      if @currenthp.to_i == @endhp.to_i
        @animatingHP = false
        # Force clear damage color when HP animation ends
        @damage_alpha = 0
        apply_damage_color
      end
    end
  end

  #=============================================================================
  # HP Animation (called by EBDX scene)
  #=============================================================================
  def animateHP(oldHP, newHP)
    @currenthp = oldHP.to_f
    @endhp = newHP.to_f
    @animatingHP = true
    MultiplayerDebug.info("BOSS-UI", "Boss HP animation: #{oldHP} -> #{newHP}") if defined?(MultiplayerDebug)
  end

  #=============================================================================
  # Damage Flash Animation (matches EBDX behavior)
  #=============================================================================
  def damage
    return if disposed?
    # Set damage alpha to full (EBDX uses 255 implicitly)
    @damage_alpha = 255
    apply_damage_color
    MultiplayerDebug.info("BOSS-UI", "Boss damage flash triggered") if defined?(MultiplayerDebug)
  end

  def undamage
    return if disposed?
    @damage_alpha = 0
    apply_damage_color
  end

  # Apply the current damage color to all sprites
  def apply_damage_color
    # When alpha is 0, use fully transparent color (not red with 0 alpha)
    if @damage_alpha <= 0
      color = Color.new(0, 0, 0, 0)
    else
      color = Color.new(DAMAGE_COLOR.red, DAMAGE_COLOR.green, DAMAGE_COLOR.blue, @damage_alpha)
    end
    @sprites.each_value do |sprite|
      next unless sprite && !sprite.disposed? && sprite.respond_to?(:color=)
      sprite.color = color
    end
  end
end

#===============================================================================
# Scene Integration: Create/Manage Boss UI
#===============================================================================
module BossUIManager
  @boss_databoxes = {}

  def self.create_boss_databox(viewport, battler)
    return nil unless battler&.is_boss?

    key = battler.index
    @boss_databoxes[key]&.dispose
    @boss_databoxes[key] = BossDataBoxSprite.new(viewport, battler)
    MultiplayerDebug.info("BOSS-UI", "BossUIManager created databox for battler #{key}") if defined?(MultiplayerDebug)
    @boss_databoxes[key]
  end

  def self.get_boss_databox(battler)
    return nil unless battler
    @boss_databoxes[battler.index]
  end

  def self.update_boss_databox(battler)
    return unless battler
    db = @boss_databoxes[battler.index]
    db&.refresh
  end

  def self.dispose_boss_databox(battler)
    return unless battler
    db = @boss_databoxes[battler.index]
    db&.dispose
    @boss_databoxes.delete(battler.index)
  end

  def self.dispose_all
    @boss_databoxes.each_value(&:dispose)
    @boss_databoxes.clear
    MultiplayerDebug.info("BOSS-UI", "Disposed all boss databoxes") if defined?(MultiplayerDebug)
  end

  def self.refresh_all
    @boss_databoxes.each_value(&:refresh)
  end

  def self.has_boss_databox?(battler)
    return false unless battler
    @boss_databoxes.key?(battler.index) && !@boss_databoxes[battler.index].disposed?
  end

  def self.damage_boss_databox(battler)
    return unless battler
    db = @boss_databoxes[battler.index]
    db&.damage
  end

  def self.undamage_boss_databox(battler)
    return unless battler
    db = @boss_databoxes[battler.index]
    db&.undamage
  end
end

#===============================================================================
# NOTE: EBDX hooks are in 661_BossUIHooks/001_Boss_UI_EBDX.rb
# (Loads after 660_EBDX so DataBoxEBDX class exists)
#===============================================================================

#===============================================================================
# NOTE: Vanilla PokemonDataBox hooks are in 661_BossUIHooks/002_Boss_UI_NonEBDX.rb
# (Loads after EBDX check, uses self.viewport instead of @viewport)
#===============================================================================

#===============================================================================
# Hook into Battle Scene pbRefresh to update boss UI
#===============================================================================
class PokeBattle_Scene
  alias boss_ui_pbRefresh pbRefresh if method_defined?(:pbRefresh)

  def pbRefresh
    boss_ui_pbRefresh if defined?(boss_ui_pbRefresh)
    BossUIManager.refresh_all
  end
end

#===============================================================================
# Cleanup on Battle End
#===============================================================================
class PokeBattle_Battle
  alias boss_ui_pbEndOfBattle pbEndOfBattle

  def pbEndOfBattle
    BossUIManager.dispose_all
    boss_ui_pbEndOfBattle
  end
end

MultiplayerDebug.info("BOSS-UI", "Boss UI system loaded") if defined?(MultiplayerDebug)
