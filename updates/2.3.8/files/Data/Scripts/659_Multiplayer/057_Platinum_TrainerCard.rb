#===============================================================================
# Platinum Currency - Trainer Card UI Display
# Displays platinum balance on trainer card with brushed aluminum "Pt" icon
#===============================================================================

class PokemonTrainerCard_Scene
  alias platinum_drawTrainerCardFront pbDrawTrainerCardFront
  def pbDrawTrainerCardFront
    platinum_drawTrainerCardFront

    # Request fresh balance from server when opening trainer card
    request_platinum_balance_from_server

    # Draw platinum display (always show, even when offline)
    draw_platinum_display
  end

  def request_platinum_balance_from_server
    # Only request if connected
    return unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)

    begin
      # Send request to server for current balance
      MultiplayerClient.send_data("PLATINUM_BALANCE_REQ")
      ##MultiplayerDebug.info("PLATINUM-UI", "Requested balance update from server")
    rescue => e
      ##MultiplayerDebug.warn("PLATINUM-UI", "Failed to request balance: #{e.message}")
    end
  end

  def draw_platinum_display
    # Safety check
    return unless @sprites && @sprites["overlay"]
    overlay = @sprites["overlay"].bitmap

    # Get cached platinum balance
    balance = MultiplayerPlatinum.cached_balance

    # Colors - harsh dark grey with light grey text
    textColor = Color.new(220, 220, 220)         # Light grey text
    textShadow = Color.new(100, 100, 100)        # Dark grey shadow
    boxBgColor = Color.new(45, 45, 45)           # Harsh dark grey background
    boxBorderDark = Color.new(180, 180, 180)     # Light grey border
    boxBorderLight = Color.new(200, 200, 200)    # Lighter grey highlight

    # Position: Under character sprite on right side
    center_x = 400  # Center of character area
    display_y = 265  # Below character sprite

    # Draw styled background box with rounded corners
    box_width = 140
    box_height = 28
    box_x = center_x - box_width / 2
    box_y = display_y - 2

    # Inset colors - lighter grey for carved-in effect
    insetBgColor = Color.new(60, 60, 60)         # Lighter grey for inset

    # Draw rounded rectangle with harsh dark grey background
    # Main body
    overlay.fill_rect(box_x + 2, box_y, box_width - 4, box_height, boxBgColor)
    overlay.fill_rect(box_x + 1, box_y + 1, box_width - 2, box_height - 2, boxBgColor)
    overlay.fill_rect(box_x, box_y + 2, box_width, box_height - 4, boxBgColor)

    # Rounded corners (dark border)
    overlay.fill_rect(box_x + 1, box_y, box_width - 2, 1, boxBorderDark) # Top edge
    overlay.fill_rect(box_x + 1, box_y + box_height - 1, box_width - 2, 1, boxBorderDark) # Bottom edge
    overlay.fill_rect(box_x, box_y + 1, 1, box_height - 2, boxBorderDark) # Left edge
    overlay.fill_rect(box_x + box_width - 1, box_y + 1, 1, box_height - 2, boxBorderDark) # Right edge

    # Corner pixels
    overlay.set_pixel(box_x + 1, box_y + 1, boxBorderDark) # Top-left
    overlay.set_pixel(box_x + box_width - 2, box_y + 1, boxBorderDark) # Top-right
    overlay.set_pixel(box_x + 1, box_y + box_height - 2, boxBorderDark) # Bottom-left
    overlay.set_pixel(box_x + box_width - 2, box_y + box_height - 2, boxBorderDark) # Bottom-right

    # Inner inset area (lighter grey, carved-in look)
    inset_x = box_x + 3
    inset_y = box_y + 3
    inset_width = box_width - 6
    inset_height = box_height - 6

    # Draw inset background
    overlay.fill_rect(inset_x, inset_y, inset_width, inset_height, insetBgColor)

    # Inset shadow at top-left for depth (with 1px margin from edges)
    shadow_color = Color.new(30, 30, 30)  # Dark shadow for inset effect
    overlay.fill_rect(inset_x + 1, inset_y + 1, inset_width - 2, 1, shadow_color) # Top shadow
    overlay.fill_rect(inset_x + 1, inset_y + 1, 1, inset_height - 2, shadow_color) # Left shadow

    # Try to load custom platinum icon (position in inset area)
    icon_width = 16  # Target size for scaled icon
    icon_x = inset_x + 4
    icon_y = inset_y + (inset_height - icon_width) / 2  # Vertically centered
    icon_loaded = false

    begin
      # Cycle through 3 icons: platinum_icon, platinum_icon2, platinum_icon3
      # Track which icon to show next (cycles 1→2→3→1)
      # Use class variable to persist across scene instances
      @@platinum_icon_cycle ||= 1
      icon_name = "platinum_icon#{@@platinum_icon_cycle == 1 ? '' : @@platinum_icon_cycle}"

      # Try to load from Trainer Card folder first
      if pbResolveBitmap("Graphics/Pictures/Trainer Card/#{icon_name}")
        icon_bitmap = RPG::Cache.load_bitmap("Graphics/Pictures/Trainer Card/", icon_name)

        # Create a scaled bitmap
        src_rect = Rect.new(0, 0, icon_bitmap.width, icon_bitmap.height)
        dest_rect = Rect.new(icon_x, icon_y, icon_width, icon_width)

        # Scale and draw the icon
        overlay.stretch_blt(dest_rect, icon_bitmap, src_rect)
        icon_loaded = true

        # Advance to next icon for next time trainer card opens
        @@platinum_icon_cycle = (@@platinum_icon_cycle % 3) + 1

      elsif pbResolveBitmap("Graphics/Pictures/#{icon_name}")
        icon_bitmap = RPG::Cache.load_bitmap("Graphics/Pictures/", icon_name)

        # Create a scaled bitmap
        src_rect = Rect.new(0, 0, icon_bitmap.width, icon_bitmap.height)
        dest_rect = Rect.new(icon_x, icon_y, icon_width, icon_width)

        # Scale and draw the icon
        overlay.stretch_blt(dest_rect, icon_bitmap, src_rect)
        icon_loaded = true

        # Advance to next icon for next time trainer card opens
        @@platinum_icon_cycle = (@@platinum_icon_cycle % 3) + 1
      end
    rescue => e
      ##MultiplayerDebug.warn("PLATINUM-UI", "Failed to load icon: #{e.message}")
    end

    # Fallback: Draw "Pt" text if icon not loaded
    unless icon_loaded
      oldTextSize = overlay.font.size
      overlay.font.size = 14

      pbDrawTextPositions(overlay, [
        [_INTL("Pt"), icon_x, icon_y - 2, 0, textColor, textShadow]
      ])

      overlay.font.size = oldTextSize
      icon_width = 20
    end

    # Draw balance value - directly on the bitmap
    balance_text = balance.to_s_formatted

    # Calculate position: center the text in the right half of the inset
    # Icon takes up left side (0 to ~24px), so center text in remaining space
    text_area_start = icon_x + icon_width + 4
    text_area_width = (inset_x + inset_width) - text_area_start

    # Dynamic font scaling: shrink if text is too wide
    oldFontSize = overlay.font.size
    current_font_size = oldFontSize
    text_size = overlay.text_size(balance_text)
    text_width = text_size.width

    # If text is too wide, scale down font size
    max_text_width = text_area_width - 4  # Leave 2px padding on each side
    if text_width > max_text_width
      scale_factor = max_text_width.to_f / text_width
      current_font_size = (oldFontSize * scale_factor).to_i
      current_font_size = [current_font_size, 10].max  # Minimum font size of 10
      overlay.font.size = current_font_size

      # Recalculate text width with new font size
      text_size = overlay.text_size(balance_text)
      text_width = text_size.width
    end

    value_x = text_area_start + (text_area_width - text_width) / 2

    # Calculate proper vertical centering
    # Use the actual text height, not font size, and center in the inset area
    text_height = text_size.height
    value_y = inset_y + (inset_height - text_height) / 2

    # Draw shadow first (offset by 1 pixel)
    overlay.font.color = textShadow
    overlay.draw_text(value_x + 1, value_y + 1, text_width + 20, text_height + 4, balance_text)

    # Draw main text
    overlay.font.color = textColor
    overlay.draw_text(value_x, value_y, text_width + 20, text_height + 4, balance_text)

    # Restore original font size
    overlay.font.size = oldFontSize
  end
end
