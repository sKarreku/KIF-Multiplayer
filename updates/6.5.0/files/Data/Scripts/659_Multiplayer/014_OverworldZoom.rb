#==============================================================================
# Overworld Zoom
#
# Zooms out the overworld camera so more of the map is visible.
# Uses Graphics.resize_screen to render at a larger internal resolution,
# then forces the OS window back to its original size via Win32API so the
# player never sees the window change.
#
# Zoom levels (stored as mp_overworld_zoom in PokemonSystem):
#   0 => Off      — 512×384  (normal)
#   1 => 25% Out  — 640×480  (see ~25% more content in each direction)
#   2 => 50% Out  — 768×576  (see ~50% more content in each direction)
#==============================================================================

module OverworldZoom
  BASE_W = Settings::SCREEN_WIDTH
  BASE_H = Settings::SCREEN_HEIGHT

  LEVELS = [
    ["Off",     BASE_W,                  BASE_H],
    ["25% Out", (BASE_W * 1.25).round,   (BASE_H * 1.25).round],
    ["50% Out", (BASE_W * 1.50).round,   (BASE_H * 1.50).round],
  ]

  @applied_index = nil

  # Win32API handles for window manipulation
  @getActiveWindow  = nil
  @getWindowRect    = nil
  @setWindowPos     = nil
  @saved_window_rect = nil   # [x, y, w, h] of the window BEFORE any zoom

  def self.setting_index
    ($PokemonSystem&.mp_overworld_zoom || 0).clamp(0, LEVELS.length - 1)
  end

  def self.active?
    setting_index != 0
  end

  # Apply the current zoom setting.
  def self.apply!(force_recreate: false)
    idx = setting_index
    w = LEVELS[idx][1]
    h = LEVELS[idx][2]

    if Graphics.width != w || Graphics.height != h
      _save_window_rect   # capture window position/size before resize
      Graphics.resize_screen(w, h)
      _restore_window_rect # force window back to saved size
      _update_viewports
    end

    if force_recreate && @applied_index != idx
      recreate_in_scene
    end
    @applied_index = idx
  end

  # Restore normal resolution (for menus, battles, etc.)
  def self.restore!
    return if Graphics.width == BASE_W && Graphics.height == BASE_H
    _save_window_rect
    Graphics.resize_screen(BASE_W, BASE_H)
    _restore_window_rect
    _update_viewports
  end

  # -----------------------------------------------------------------------
  private

  def self._init_win32
    return if @getActiveWindow
    @getActiveWindow = Win32API.new('user32', 'GetActiveWindow', [], 'l')
    @getWindowRect   = Win32API.new('user32', 'GetWindowRect', ['l', 'p'], 'i')
    @setWindowPos    = Win32API.new('user32', 'SetWindowPos', ['l', 'l', 'i', 'i', 'i', 'i', 'i'], 'i')
  rescue
    @getActiveWindow = nil
  end

  def self._save_window_rect
    _init_win32
    return unless @getActiveWindow
    hwnd = @getActiveWindow.call
    return if hwnd == 0
    rect = [0, 0, 0, 0].pack('l4')
    @getWindowRect.call(hwnd, rect)
    l, t, r, b = rect.unpack('l4')
    @saved_window_rect = [l, t, r - l, b - t]
  rescue
    nil
  end

  def self._restore_window_rect
    return unless @saved_window_rect && @setWindowPos
    hwnd = @getActiveWindow.call
    return if hwnd == 0
    x, y, w, h = @saved_window_rect
    # SWP_NOZORDER (0x0004) | SWP_NOACTIVATE (0x0010)
    @setWindowPos.call(hwnd, 0, x, y, w, h, 0x0014)
  rescue
    nil
  end

  def self._update_viewports
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
  alias _owzoom_orig_main main unless method_defined?(:_owzoom_orig_main)
  def main
    OverworldZoom.apply!
    _owzoom_orig_main
    OverworldZoom.restore!
  end

  alias _owzoom_orig_call_menu call_menu unless method_defined?(:_owzoom_orig_call_menu)
  def call_menu
    prev_index = OverworldZoom.instance_variable_get(:@applied_index)
    OverworldZoom.restore!
    _owzoom_orig_call_menu
    OverworldZoom.apply!(force_recreate: OverworldZoom.setting_index != prev_index)
    $game_player.center($game_player.x, $game_player.y) if $game_player
  end
end

#==============================================================================
# pbSceneStandby hook — restore zoom before battles, re-apply after
#==============================================================================
alias _owzoom_orig_pbSceneStandby pbSceneStandby unless defined?(_owzoom_orig_pbSceneStandby)
def pbSceneStandby
  OverworldZoom.restore!
  _owzoom_orig_pbSceneStandby {
    yield
  }
  OverworldZoom.apply!
  $game_player.center($game_player.x, $game_player.y) if $game_player
end
