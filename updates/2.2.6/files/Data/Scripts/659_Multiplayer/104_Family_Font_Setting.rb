#===============================================================================
# Family Font Setting - Initialize familyfont toggle
#===============================================================================
# Adds familyfont attribute to PokemonSystem if not already present
# Uses getter with default value for compatibility with old save files
# Also fixes shinyodds nil issue for old saves
#===============================================================================

class PokemonSystem
  # Custom getter that returns default if not set (handles old save files)
  def familyfont
    return @familyfont if instance_variable_defined?(:@familyfont) && !@familyfont.nil?
    @familyfont = 1
    return @familyfont
  end

  def familyfont=(value)
    @familyfont = value
  end

  # Fix shinyodds nil issue for old saves
  alias original_shinyodds shinyodds if method_defined?(:shinyodds)

  def shinyodds
    if defined?(original_shinyodds)
      result = original_shinyodds
      return result unless result.nil?
    end
    return @shinyodds if instance_variable_defined?(:@shinyodds) && !@shinyodds.nil?
    @shinyodds = 512  # Default shiny odds
    return @shinyodds
  end

  alias family_font_original_initialize initialize if method_defined?(:initialize)

  def initialize
    family_font_original_initialize if defined?(family_font_original_initialize)
    @familyfont = 1 if !instance_variable_defined?(:@familyfont) || @familyfont.nil?
  end
end
