#==============================================================================
# Overworld Zoom
#
# Zooms out the overworld camera so more of the map is visible.
# Implemented via Graphics.resize_screen — the internal render canvas is made
# larger than the window, so the engine scales everything down to fit, showing
# more tiles without changing any tile or character logic.
#
# Zoom levels (stored as mp_overworld_zoom in PokemonSystem):
#   0 => Off      — 512×384  (normal)
#   1 => 25% Out  — 640×480  (see ~25% more content in each direction)
#   2 => 50% Out  — 768×576  (see ~50% more content in each direction)
#==============================================================================

module OverworldZoom
  # [label, internal width, internal height]
  LEVELS = [
    ["Off",     Settings::SCREEN_WIDTH,                        Settings::SCREEN_HEIGHT],
    ["25% Out", (Settings::SCREEN_WIDTH * 1.25).round,        (Settings::SCREEN_HEIGHT * 1.25).round],
    ["50% Out", (Settings::SCREEN_WIDTH * 1.50).round,        (Settings::SCREEN_HEIGHT * 1.50).round],
  ]

  # Which zoom index was active when the TilemapRenderer was last created.
  # Lets us detect when the tile grid needs rebuilding after a setting change.
  @applied_index = nil

  def self.setting_index
    ($PokemonSystem&.mp_overworld_zoom || 0).clamp(0, LEVELS.length - 1)
  end

  def self.active?
    setting_index != 0
  end

  # Apply the current zoom setting.
  #   force_recreate: if true, dispose and rebuild the TilemapRenderer when the
  #                   zoom index has changed since spritesets were last created.
  #                   Pass false (default) when called before createSpritesets.
  def self.apply!(force_recreate: false)
    idx = setting_index
    resize_if_needed(LEVELS[idx][1], LEVELS[idx][2])
    if force_recreate && @applied_index != idx
      recreate_in_scene
    end
    @applied_index = idx
  end

  # Restore normal resolution while inside a menu so UI text is full-size.
  # Does NOT recreate spritesets — extra tiles just sit off-screen.
  def self.restore!
    resize_if_needed(Settings::SCREEN_WIDTH, Settings::SCREEN_HEIGHT)
  end

  # -----------------------------------------------------------------------
  private

  def self.resize_if_needed(w, h)
    return if Graphics.width == w && Graphics.height == h
    Graphics.resize_screen(w, h)
    Spriteset_Map.update_static_viewport_rects
  end

  def self.recreate_in_scene
    scene = $scene
    return unless scene.is_a?(Scene_Map)
    renderer = scene.instance_variable_get(:@map_renderer)
    return unless renderer && !renderer.disposed?
    Graphics.freeze
    scene.send(:disposeSpritesets)
    renderer.dispose
    scene.instance_variable_set(:@map_renderer, nil)
    scene.send(:createSpritesets)
    # Re-center the camera on the player using the new canvas dimensions
    $game_player.center($game_player.x, $game_player.y) if $game_player
    Graphics.transition(8)
  end
end

#==============================================================================
# Expose the static viewports so OverworldZoom can update their rects
#==============================================================================
class Spriteset_Map
  def self.update_static_viewport_rects
    @@viewport0.rect.set(0, 0, Graphics.width, Graphics.height)
    @@viewport3.rect.set(0, 0, Graphics.width, Graphics.height)
  end
end

#==============================================================================
# Game_Player — dynamic screen center
#
# SCREEN_CENTER_X/Y are constants fixed to Settings::SCREEN_WIDTH/HEIGHT.
# After resize_screen the canvas is larger but those constants don't update,
# so the camera locks onto the old mid-point instead of the actual center.
# We patch the three methods that read those constants to use Graphics.width/
# height instead so the player always stays in the middle of the real canvas.
#==============================================================================
class Game_Player
  def dynamic_screen_center_x
    (Graphics.width  / 2 - Game_Map::TILE_WIDTH  / 2) * Game_Map::X_SUBPIXELS
  end

  def dynamic_screen_center_y
    (Graphics.height / 2 - Game_Map::TILE_HEIGHT / 2) * Game_Map::Y_SUBPIXELS
  end

  alias _owzoom_orig_center center unless method_defined?(:_owzoom_orig_center)
  def center(x, y)
    self.map.display_x = x * Game_Map::REAL_RES_X - dynamic_screen_center_x
    self.map.display_y = y * Game_Map::REAL_RES_Y - dynamic_screen_center_y
  end

  alias _owzoom_orig_isCentered isCentered unless method_defined?(:_owzoom_orig_isCentered)
  def isCentered
    x_centered = self.map.display_x == x * Game_Map::REAL_RES_X - dynamic_screen_center_x
    y_centered = self.map.display_y == y * Game_Map::REAL_RES_Y - dynamic_screen_center_y
    return x_centered && y_centered
  end

  alias _owzoom_orig_update_screen_position update_screen_position unless method_defined?(:_owzoom_orig_update_screen_position)
  def update_screen_position(last_real_x, last_real_y)
    return if self.map.scrolling? || !(@moved_last_frame || @moved_this_frame)
    self.map.display_x = @real_x - dynamic_screen_center_x
    self.map.display_y = @real_y - dynamic_screen_center_y
  end
end

#==============================================================================
# Scene_Map hooks
#==============================================================================
class Scene_Map
  # Apply zoom before createSpritesets runs, restore when the scene exits.
  alias _owzoom_orig_main main unless method_defined?(:_owzoom_orig_main)
  def main
    OverworldZoom.apply!     # resize before the internal createSpritesets call
    _owzoom_orig_main        # full original main (createSpritesets + loop + dispose)
    OverworldZoom.restore!   # restore on scene exit
  end

  # The menu stays at the current zoom level — no resize on open/close.
  # If the player changes the zoom setting inside the menu, rebuild the
  # tile renderer when they return to the map.
  alias _owzoom_orig_call_menu call_menu unless method_defined?(:_owzoom_orig_call_menu)
  def call_menu
    prev_index = OverworldZoom.instance_variable_get(:@applied_index)
    _owzoom_orig_call_menu
    if OverworldZoom.setting_index != prev_index
      OverworldZoom.apply!(force_recreate: true)
      $game_player.center($game_player.x, $game_player.y) if $game_player
    end
  end
end
