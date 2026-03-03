#===============================================================================
#  EBDX Environment Configurations
#  Adapted from Elite Battle DX Environments.rb
#===============================================================================
module EnvironmentEBDX
  #-----------------------------------------------------------------------------
  # Default outdoor environment
  #-----------------------------------------------------------------------------
  OUTDOOR = {
    "backdrop" => "Field",
    "sky" => true,
    "outdoor" => true,
    "trees" => {
      :elements => 9,
      :x => [150, 271, 78, 288, 176, 42, 118, 348, 321],
      :y => [108, 117, 118, 126, 126, 128, 136, 136, 145],
      :zoom => [0.44, 0.44, 0.59, 0.59, 0.59, 0.64, 0.85, 0.7, 1],
      :mirror => [false, false, true, true, true, false, false, true, false]
    }
  }
  #-----------------------------------------------------------------------------
  # Default indoor environment
  #-----------------------------------------------------------------------------
  INDOOR = {
    "backdrop" => "IndoorA",
    "outdoor" => false,
    "img001" => {
      :bitmap => "decor007",
      :oy => 0, :z => 1, :flat => true, :scrolling => true, :speed => 0.5
    },
    "img002" => {
      :bitmap => "decor008",
      :oy => 0, :z => 1, :flat => true, :scrolling => true, :direction => -1
    },
    "lightsA" => true
  }
  #-----------------------------------------------------------------------------
  # Cave environment
  #-----------------------------------------------------------------------------
  CAVE = {
    "backdrop" => "Cave",
    "outdoor" => false,
    "img001" => {
      :scrolling => true, :speed => 2, :direction => -1,
      :bitmap => "decor006",
      :oy => 0, :z => 3, :flat => true, :opacity => 155
    },
    "img002" => {
      :scrolling => true, :speed => 1, :direction => 1,
      :bitmap => "decor009",
      :oy => 0, :z => 3, :flat => true, :opacity => 96
    },
    "img003" => {
      :scrolling => true, :speed => 0.5, :direction => 1,
      :bitmap => "fog",
      :oy => 0, :z => 4, :flat => true
    }
  }
  #-----------------------------------------------------------------------------
  # Water environment
  #-----------------------------------------------------------------------------
  WATER = {
    "backdrop" => "Water",
    "sky" => true,
    "water" => true,
    "outdoor" => true
  }
  #-----------------------------------------------------------------------------
  # Forest environment
  #-----------------------------------------------------------------------------
  FOREST = {
    "backdrop" => "Forest",
    "outdoor" => false,
    "lightsC" => true,
    "img001" => {
      :bitmap => "forestShade", :z => 1, :flat => true,
      :oy => 0, :y => 94, :sheet => true, :frames => 2, :speed => 16
    },
    "trees" => {
      :bitmap => "treePine", :colorize => false, :elements => 8,
      :x => [92, 248, 300, 40, 138, 216, 274, 318],
      :y => [132, 132, 144, 118, 112, 118, 110, 110],
      :zoom => [1, 1, 1.1, 0.9, 0.8, 0.85, 0.75, 0.75],
      :z => [2, 2, 2, 1, 1, 1, 1, 1]
    }
  }
  #-----------------------------------------------------------------------------
  # Simple field (fallback for missing graphics)
  #-----------------------------------------------------------------------------
  FIELD = {
    "backdrop" => "Field",
    "outdoor" => true
  }
end

#===============================================================================
#  Terrain additions
#===============================================================================
module TerrainEBDX
  MOUNTAIN = { "img001" => { :bitmap => "mountain", :x => 192, :y => 107 } }
  PUDDLE = { "base" => "Puddle" }
  DIRT = { "base" => "Dirt" }
  CONCRETE = { "base" => "Concrete" }
  WATER = { "base" => "Water", "water" => true }
  TALLGRASS = {
    "tallGrass" => {
      :elements => 7,
      :x => [124, 274, 204, 62, 248, 275, 182],
      :y => [160, 140, 140, 185, 246, 174, 170],
      :z => [2, 1, 2, 17, 27, 17, 17],
      :zoom => [0.7, 0.35, 0.5, 1, 1.5, 0.7, 1],
      :mirror => [false, true, false, true, false, true, false]
    }
  }
end
