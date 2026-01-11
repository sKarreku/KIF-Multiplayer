#===============================================================================
# MODULE: Couch Co-op Input Handler
#===============================================================================
# Handles unfocused input capture using Win32API
# Allows keyboard-only or controller-only input modes
#===============================================================================

module CouchCoopInput
  # Win32API declarations
  begin
    @@GetForegroundWindow = Win32API.new('user32', 'GetForegroundWindow', [], 'i')
    @@GetWindowThreadProcessId = Win32API.new('user32', 'GetWindowThreadProcessId', ['i', 'p'], 'i')
    @@GetAsyncKeyState = Win32API.new('user32', 'GetAsyncKeyState', ['i'], 'i')

    @win32_available = true
  rescue
    @win32_available = false
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("COUCH-COOP-INPUT", "Win32API not available - couch co-op mode disabled")
    end
  end

  # Virtual Key Codes for Pokemon Essentials default controls
  VK_CODES = {
    :LEFT    => 0x25,
    :UP      => 0x26,
    :RIGHT   => 0x27,
    :DOWN    => 0x28,
    :RETURN  => 0x0D,
    :ESCAPE  => 0x1B,
    :SHIFT   => 0x10,
    :CTRL    => 0x11,
    :ALT     => 0x12,
    :Z       => 0x5A,
    :X       => 0x58,
    :C       => 0x43,
    :A       => 0x41,
    :S       => 0x53,
    :D       => 0x44,
    :W       => 0x57
  }

  # Mapping of Input constants to VK codes (based on default Pokemon Essentials controls)
  INPUT_TO_VK = {
    Input::DOWN   => [:DOWN, :S],
    Input::LEFT   => [:LEFT, :A],
    Input::RIGHT  => [:RIGHT, :D],
    Input::UP     => [:UP, :W],
    Input::USE    => [:C, :RETURN],     # C or Enter
    Input::BACK   => [:X, :ESCAPE],     # X or Escape
    Input::ACTION => [:Z],              # Z
    Input::SHIFT  => [:SHIFT],          # Shift
    Input::CTRL   => [:CTRL],           # Ctrl
    Input::ALT    => [:ALT],            # Alt
  }

  @last_key_states = {}  # For tracking trigger events (was pressed last frame?)
  @repeat_timers = {}    # For tracking repeat events (frames held down)

  REPEAT_DELAY = 20      # Frames before repeat starts
  REPEAT_RATE = 2        # Frames between repeats

  # Check if this window is currently focused
  def self.window_active?
    return true unless @win32_available
    return true unless @@GetForegroundWindow && @@GetWindowThreadProcessId

    begin
      foreground = @@GetForegroundWindow.call
      return true if foreground == 0

      process_id = [0].pack('L')
      @@GetWindowThreadProcessId.call(foreground, process_id)
      foreground_pid = process_id.unpack('L')[0]
      current_pid = Process.pid

      return foreground_pid == current_pid
    rescue
      return true  # Fallback to assuming focused
    end
  end

  # Check if a specific VK code is currently pressed
  def self.key_pressed?(vk_code)
    return false unless @win32_available
    return false unless @@GetAsyncKeyState

    begin
      state = @@GetAsyncKeyState.call(vk_code)
      return (state & 0x8000) != 0  # High bit indicates key is currently down
    rescue
      return false
    end
  end

  # Main processing method called from Input.update hook
  def self.process
    return unless @win32_available
    return unless defined?(CouchCoopConfig) && CouchCoopConfig.enabled?

    # Update repeat timers
    update_repeat_timers
  end

  # Update repeat timers for all buttons
  def self.update_repeat_timers
    INPUT_TO_VK.keys.each do |button|
      is_pressed = input_pressed_via_keyboard?(button)

      if is_pressed
        @repeat_timers[button] = (@repeat_timers[button] || 0) + 1
      else
        @repeat_timers[button] = 0
      end
    end
  end

  # Check if button is currently pressed (for Input.press?)
  def self.input_pressed_via_keyboard?(button)
    vk_keys = INPUT_TO_VK[button]
    return false unless vk_keys

    vk_keys.any? { |key_sym| key_pressed?(VK_CODES[key_sym]) }
  end

  # Check if button was just pressed this frame (for Input.trigger?)
  def self.input_triggered_via_keyboard?(button)
    is_pressed = input_pressed_via_keyboard?(button)
    was_pressed = @last_key_states[button] || false

    @last_key_states[button] = is_pressed

    return is_pressed && !was_pressed
  end

  # Check if button is being repeated (for Input.repeat?)
  def self.input_repeated_via_keyboard?(button)
    return false unless input_pressed_via_keyboard?(button)

    timer = @repeat_timers[button] || 0

    # First press
    return true if timer == 1

    # After delay, repeat at rate
    return false if timer < REPEAT_DELAY
    return ((timer - REPEAT_DELAY) % REPEAT_RATE) == 0
  end

  # Get 4-direction input (for Input.dir4)
  def self.dir4_via_keyboard
    return 2 if input_pressed_via_keyboard?(Input::DOWN)
    return 4 if input_pressed_via_keyboard?(Input::LEFT)
    return 6 if input_pressed_via_keyboard?(Input::RIGHT)
    return 8 if input_pressed_via_keyboard?(Input::UP)
    return 0
  end

  # Get 8-direction input (for Input.dir8)
  def self.dir8_via_keyboard
    down  = input_pressed_via_keyboard?(Input::DOWN)
    left  = input_pressed_via_keyboard?(Input::LEFT)
    right = input_pressed_via_keyboard?(Input::RIGHT)
    up    = input_pressed_via_keyboard?(Input::UP)

    return 1 if down && left
    return 2 if down && !left && !right
    return 3 if down && right
    return 4 if left && !down && !up
    return 6 if right && !down && !up
    return 7 if up && left
    return 8 if up && !left && !right
    return 9 if up && right
    return 0
  end

  # Check if Win32API is available
  def self.available?
    @win32_available
  end
end

#===============================================================================
# Hook Input module to override press/trigger/repeat/dir4/dir8 when unfocused
#===============================================================================
module Input
  class << self
    # Store original MKXP-Z methods
    alias couch_coop_original_update update unless method_defined?(:couch_coop_original_update)
    alias couch_coop_original_press? press? unless method_defined?(:couch_coop_original_press?)
    alias couch_coop_original_trigger? trigger? unless method_defined?(:couch_coop_original_trigger?)
    alias couch_coop_original_repeat? repeat? unless method_defined?(:couch_coop_original_repeat?)
    alias couch_coop_original_dir4 dir4 unless method_defined?(:couch_coop_original_dir4)
    alias couch_coop_original_dir8 dir8 unless method_defined?(:couch_coop_original_dir8)

    def update
      # Call original update first
      couch_coop_original_update

      # Process couch co-op input if enabled
      CouchCoopInput.process if defined?(CouchCoopInput)
    end

    def press?(button)
      if defined?(CouchCoopInput) && defined?(CouchCoopConfig) && CouchCoopConfig.enabled?
        mode = CouchCoopConfig.input_mode
        is_focused = CouchCoopInput.window_active?

        # Keyboard-only mode: Use Win32API when unfocused, normal MKXP-Z when focused
        if mode == "keyboard"
          return CouchCoopInput.input_pressed_via_keyboard?(button) unless is_focused
          return couch_coop_original_press?(button)

        # Controller-only mode: Block keyboard if focused, otherwise passthrough
        elsif mode == "controller"
          # Only check keyboard state when focused (local input for THIS window)
          if is_focused && CouchCoopInput.input_pressed_via_keyboard?(button)
            return false  # Block keyboard when focused
          end
          return couch_coop_original_press?(button)
        end
      end

      # Default: use MKXP-Z's normal input
      couch_coop_original_press?(button)
    end

    def trigger?(button)
      if defined?(CouchCoopInput) && defined?(CouchCoopConfig) && CouchCoopConfig.enabled?
        mode = CouchCoopConfig.input_mode
        is_focused = CouchCoopInput.window_active?

        if mode == "keyboard"
          return CouchCoopInput.input_triggered_via_keyboard?(button) unless is_focused
          return couch_coop_original_trigger?(button)
        elsif mode == "controller"
          # Only check keyboard state when focused (local input for THIS window)
          if is_focused && CouchCoopInput.input_triggered_via_keyboard?(button)
            return false  # Block keyboard when focused
          end
          return couch_coop_original_trigger?(button)
        end
      end

      couch_coop_original_trigger?(button)
    end

    def repeat?(button)
      if defined?(CouchCoopInput) && defined?(CouchCoopConfig) && CouchCoopConfig.enabled?
        mode = CouchCoopConfig.input_mode
        is_focused = CouchCoopInput.window_active?

        if mode == "keyboard"
          return CouchCoopInput.input_repeated_via_keyboard?(button) unless is_focused
          return couch_coop_original_repeat?(button)
        elsif mode == "controller"
          # Only check keyboard state when focused (local input for THIS window)
          if is_focused && CouchCoopInput.input_repeated_via_keyboard?(button)
            return false  # Block keyboard when focused
          end
          return couch_coop_original_repeat?(button)
        end
      end

      couch_coop_original_repeat?(button)
    end

    def dir4
      if defined?(CouchCoopInput) && defined?(CouchCoopConfig) && CouchCoopConfig.enabled?
        mode = CouchCoopConfig.input_mode
        is_focused = CouchCoopInput.window_active?

        if mode == "keyboard"
          return CouchCoopInput.dir4_via_keyboard unless is_focused
          return couch_coop_original_dir4
        elsif mode == "controller"
          # Only check keyboard state when focused (local input for THIS window)
          if is_focused
            if CouchCoopInput.input_pressed_via_keyboard?(Input::UP) ||
               CouchCoopInput.input_pressed_via_keyboard?(Input::DOWN) ||
               CouchCoopInput.input_pressed_via_keyboard?(Input::LEFT) ||
               CouchCoopInput.input_pressed_via_keyboard?(Input::RIGHT)
              return 0  # Block keyboard directional input when focused
            end
          end
          return couch_coop_original_dir4
        end
      end

      couch_coop_original_dir4
    end

    def dir8
      if defined?(CouchCoopInput) && defined?(CouchCoopConfig) && CouchCoopConfig.enabled?
        mode = CouchCoopConfig.input_mode
        is_focused = CouchCoopInput.window_active?

        if mode == "keyboard"
          return CouchCoopInput.dir8_via_keyboard unless is_focused
          return couch_coop_original_dir8
        elsif mode == "controller"
          # Only check keyboard state when focused (local input for THIS window)
          if is_focused
            if CouchCoopInput.input_pressed_via_keyboard?(Input::UP) ||
               CouchCoopInput.input_pressed_via_keyboard?(Input::DOWN) ||
               CouchCoopInput.input_pressed_via_keyboard?(Input::LEFT) ||
               CouchCoopInput.input_pressed_via_keyboard?(Input::RIGHT)
              return 0  # Block keyboard directional input when focused
            end
          end
          return couch_coop_original_dir8
        end
      end

      couch_coop_original_dir8
    end
  end
end

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("COUCH-COOP-INPUT", "=" * 60)
  MultiplayerDebug.info("COUCH-COOP-INPUT", "Couch Co-op Input module loaded")
  MultiplayerDebug.info("COUCH-COOP-INPUT", "Win32API available: #{CouchCoopInput.available?}")
  MultiplayerDebug.info("COUCH-COOP-INPUT", "Unfocused input capture: #{CouchCoopConfig.enabled? ? 'Enabled' : 'Disabled'}")
  MultiplayerDebug.info("COUCH-COOP-INPUT", "=" * 60)
end
