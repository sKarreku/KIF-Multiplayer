#===============================================================================
# MODULE: Family/Subfamily System - Font Rendering Helpers
#===============================================================================
# Helper module for applying family fonts with dynamic scaling.
# Fonts are loaded from: Fonts/Primordium.ttf (or .otf), Fonts/Vacuum.ttf, etc.
#
# Key Features:
#   - Win32API-based font rendering (bypasses RGSS font limitation)
#   - Dynamic font scaling to fit text within max_width/max_height
#   - Minimum font size of 16px (readability limit)
#   - Safe fallback if custom font not found
#===============================================================================

module FamilyFontHelper
  # Win32API declarations for GDI font rendering
  begin
    # Windows GDI functions
    @@CreateDC = Win32API.new('gdi32', 'CreateDC', 'PPPP', 'L')
    @@DeleteDC = Win32API.new('gdi32', 'DeleteDC', 'L', 'I')
    @@CreateFontIndirect = Win32API.new('gdi32', 'CreateFontIndirect', 'P', 'L')
    @@SelectObject = Win32API.new('gdi32', 'SelectObject', 'LL', 'L')
    @@DeleteObject = Win32API.new('gdi32', 'DeleteObject', 'L', 'I')
    @@SetTextColor = Win32API.new('gdi32', 'SetTextColor', 'LL', 'L')
    @@SetBkMode = Win32API.new('gdi32', 'SetBkMode', 'LI', 'I')
    @@TextOut = Win32API.new('gdi32', 'TextOutA', 'LIIPI', 'I')
    @@GetDIBits = Win32API.new('gdi32', 'GetDIBits', 'LLIIPPI', 'I')  # (HDC, HBITMAP, start, lines, lpvBits, lpbi, usage)
    @@CreateCompatibleBitmap = Win32API.new('gdi32', 'CreateCompatibleBitmap', 'LII', 'L')

    @@WIN32_AVAILABLE = true

    if defined?(MultiplayerDebug)
      #MultiplayerDebug.info("FAMILY-FONT", "Win32API loaded successfully - custom fonts enabled")
    end
  rescue => e
    @@WIN32_AVAILABLE = false
    if defined?(MultiplayerDebug)
      #MultiplayerDebug.error("FAMILY-FONT", "Win32API unavailable: #{e.message} - custom fonts disabled")
    end
  end

  # Render text to bitmap using Windows GDI (bypasses RGSS font limitation)
  # @param text [String] Text to render
  # @param font_name [String] Font family name (e.g., "Infernum")
  # @param font_size [Integer] Font size in pixels
  # @param width [Integer] Bitmap width
  # @param height [Integer] Bitmap height
  # @return [Bitmap, nil] Rendered bitmap or nil on failure
  def self.render_text_with_gdi(text, font_name, font_size, width, height)
    return nil unless @@WIN32_AVAILABLE

    begin
      # Create device context
      hdc = @@CreateDC.call("DISPLAY", nil, nil, nil)
      return nil if hdc == 0

      # Create LOGFONT structure for custom font
      # LOGFONT struct (92 bytes total on 32-bit Windows):
      # https://docs.microsoft.com/en-us/windows/win32/api/wingdi/ns-wingdi-logfonta
      logfont = [
        -font_size,        # lfHeight (LONG, 4 bytes)
        0,                 # lfWidth (LONG, 4 bytes)
        0,                 # lfEscapement (LONG, 4 bytes)
        0,                 # lfOrientation (LONG, 4 bytes)
        400,               # lfWeight (LONG, 4 bytes) - 400 = normal
        0,                 # lfItalic (BYTE, 1 byte)
        0,                 # lfUnderline (BYTE, 1 byte)
        0,                 # lfStrikeOut (BYTE, 1 byte)
        0,                 # lfCharSet (BYTE, 1 byte) - 0 = ANSI
        0,                 # lfOutPrecision (BYTE, 1 byte)
        0,                 # lfClipPrecision (BYTE, 1 byte)
        5,                 # lfQuality (BYTE, 1 byte) - 5 = CLEARTYPE
        0,                 # lfPitchAndFamily (BYTE, 1 byte)
      ].pack('l5C8') + font_name.ljust(32, "\0")  # lfFaceName (CHAR[32], 32 bytes)

      # Create font object
      hfont = @@CreateFontIndirect.call(logfont)
      return nil if hfont == 0

      # Create compatible bitmap FIRST
      hbitmap = @@CreateCompatibleBitmap.call(hdc, width, height)
      old_bitmap = @@SelectObject.call(hdc, hbitmap)

      # Select font into DC
      old_font = @@SelectObject.call(hdc, hfont)

      # Set text color (white) and transparent background
      @@SetTextColor.call(hdc, 0x00FFFFFF)
      @@SetBkMode.call(hdc, 1)  # TRANSPARENT

      # Draw text
      @@TextOut.call(hdc, 0, 0, text, text.length)

      # Get bitmap bits
      bmi_header = [40, width, -height, 1, 32, 0, 0, 0, 0, 0, 0].pack('L11')
      bits = "\0" * (width * height * 4)
      @@GetDIBits.call(hdc, hbitmap, 0, height, bits, bmi_header, 0)

      # Create RGSS bitmap from raw bits
      result_bitmap = Bitmap.new(width, height)

      # Copy pixel data (BGRA format)
      height.times do |y|
        width.times do |x|
          offset = (y * width + x) * 4
          b = bits[offset].ord
          g = bits[offset + 1].ord
          r = bits[offset + 2].ord
          a = bits[offset + 3].ord

          result_bitmap.set_pixel(x, y, Color.new(r, g, b, a))
        end
      end

      # Cleanup
      @@SelectObject.call(hdc, old_bitmap)
      @@SelectObject.call(hdc, old_font)
      @@DeleteObject.call(hbitmap)
      @@DeleteObject.call(hfont)
      @@DeleteDC.call(hdc)

      return result_bitmap

    rescue => e
      if defined?(MultiplayerDebug)
        #MultiplayerDebug.error("FAMILY-FONT", "GDI rendering failed: #{e.message}")
      end
      return nil
    end
  end
  # Check if Pokemon has a family assigned
  def self.has_family_font?(pokemon)
    return false unless pokemon
    return !pokemon.family.nil? && !pokemon.subfamily.nil?
  end

  # Apply family font with dynamic scaling to fit text box
  # @param bitmap [Bitmap] The bitmap to render text on
  # @param pokemon [Pokemon] The Pokemon with family data
  # @param max_width [Integer] Maximum width for text (will scale down if needed)
  # @param max_height [Integer] Maximum height for text (not currently used)
  def self.apply_family_font(bitmap, pokemon, max_width, max_height)
    return unless has_family_font?(pokemon)

    # Get family font name
    font_name = PokemonFamilyConfig.get_family_font(pokemon.family)

    if defined?(MultiplayerDebug)
      #MultiplayerDebug.info("FAMILY-FONT", "=== FONT APPLICATION START ===")
      #MultiplayerDebug.info("FAMILY-FONT", "Pokemon: #{pokemon.name}, Family: #{pokemon.family}")
      #MultiplayerDebug.info("FAMILY-FONT", "Target font: #{font_name}")
      #MultiplayerDebug.info("FAMILY-FONT", "Current bitmap.font.name BEFORE: #{bitmap.font.name.inspect}")
    end

    # Try to apply custom font (with fallback to default)
    begin
      # Check if font exists
      font_path_ttf = "Fonts/#{font_name}.ttf"
      font_path_otf = "Fonts/#{font_name}.otf"

      if defined?(MultiplayerDebug)
        #MultiplayerDebug.info("FAMILY-FONT", "Checking: #{font_path_ttf} exists? #{File.exist?(font_path_ttf)}")
        #MultiplayerDebug.info("FAMILY-FONT", "Checking: #{font_path_otf} exists? #{File.exist?(font_path_otf)}")
        #MultiplayerDebug.info("FAMILY-FONT", "Font.default_name = #{Font.default_name.inspect}")
      end

      if File.exist?(font_path_ttf) || File.exist?(font_path_otf)
        bitmap.font.name = font_name
        if defined?(MultiplayerDebug)
          #MultiplayerDebug.info("FAMILY-FONT", "Set bitmap.font.name = #{font_name}")
          #MultiplayerDebug.info("FAMILY-FONT", "Actual bitmap.font.name AFTER: #{bitmap.font.name.inspect}")
        end
      else
        # Font file not found - log warning and use default
        if defined?(MultiplayerDebug)
          #MultiplayerDebug.warn("FAMILY-FONT", "Font file not found: #{font_path_ttf} or #{font_path_otf} - using default font")
        end
        bitmap.font.name = MessageConfig.pbGetSystemFontName
      end
    rescue => e
      if defined?(MultiplayerDebug)
        #MultiplayerDebug.error("FAMILY-FONT", "Failed to load font #{font_name}: #{e.message}")
      end
      bitmap.font.name = MessageConfig.pbGetSystemFontName
    end

    # Start with default font size (29px)
    bitmap.font.size = 29

    # Measure text size at default font size
    text_width = bitmap.text_size(pokemon.name).width
    text_height = bitmap.text_size(pokemon.name).height

    if defined?(MultiplayerDebug)
      #MultiplayerDebug.info("FAMILY-FONT", "Text size: #{text_width}x#{text_height}, Max: #{max_width}x#{max_height}")
    end

    # Scale down if text exceeds max width
    if text_width > max_width
      scale_factor = max_width.to_f / text_width
      new_size = (29 * scale_factor).floor

      if defined?(MultiplayerDebug)
        #MultiplayerDebug.info("FAMILY-FONT", "Scaling font: 29 → #{new_size} (factor: #{scale_factor.round(2)})")
      end

      bitmap.font.size = new_size
    end

    # Clamp to minimum readable size (16px)
    if bitmap.font.size < 16
      bitmap.font.size = 16
      if defined?(MultiplayerDebug)
        #MultiplayerDebug.info("FAMILY-FONT", "Font clamped to minimum 16px")
      end
    end

    if defined?(MultiplayerDebug)
      #MultiplayerDebug.info("FAMILY-FONT", "Final font: #{bitmap.font.name} @ #{bitmap.font.size}px")
    end
  end

  # Restore default font after rendering
  # @param bitmap [Bitmap] The bitmap to restore font on
  def self.restore_default_font(bitmap)
    bitmap.font.name = MessageConfig.pbGetSystemFontName
    bitmap.font.size = 29

    if defined?(MultiplayerDebug)
      #MultiplayerDebug.info("FAMILY-FONT", "Restored default font: #{bitmap.font.name} @ #{bitmap.font.size}px")
    end
  end

  # Helper to check if a custom font file exists
  # @param font_name [String] Internal font name (e.g., "Hellgrazer")
  # @return [Boolean] True if .ttf or .otf file exists
  def self.font_exists?(font_name)
    # Map internal font name to file name
    file_name = FONT_FILE_MAP[font_name] || font_name
    font_path_ttf = "Fonts/#{file_name}.ttf"
    font_path_otf = "Fonts/#{file_name}.otf"
    return File.exist?(font_path_ttf) || File.exist?(font_path_otf)
  end
end

# Module loaded successfully
if defined?(MultiplayerDebug)
  #MultiplayerDebug.info("FAMILY-FONT", "=" * 60)
  #MultiplayerDebug.info("FAMILY-FONT", "103_Family_Font_Rendering.rb loaded successfully")
  #MultiplayerDebug.info("FAMILY-FONT", "Font helper module initialized")
  #MultiplayerDebug.info("FAMILY-FONT", "Features: Dynamic scaling, fallback handling, restoration")
  #MultiplayerDebug.info("FAMILY-FONT", "Font location: Fonts/[FamilyName].ttf or .otf")

  # Check which fonts exist
  missing_fonts = []
  PokemonFamilyConfig::FAMILIES.each do |family_id, family_data|
    font_name = family_data[:font_name]
    unless FamilyFontHelper.font_exists?(font_name)
      missing_fonts << font_name
    end
  end

  if missing_fonts.empty?
    #MultiplayerDebug.info("FAMILY-FONT", "✓ All 8 family fonts found!")
  else
    #MultiplayerDebug.warn("FAMILY-FONT", "⚠ Missing fonts: #{missing_fonts.join(', ')}")
    #MultiplayerDebug.warn("FAMILY-FONT", "Will fall back to default font for missing fonts")
  end

  #MultiplayerDebug.info("FAMILY-FONT", "=" * 60)
end
