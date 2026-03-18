-- NEVE
-- vocal chain: transient → preamp → comp → soothe → air
-- enc1: intensity  |  k1: clip mode  |  k2: mono  |  k3: A/B toggle
-- inspired by Rupert Neve 1073, SSL comp, Soothe2
-- Features: A/B comparison mode, vocal presets

engine.name = "Neve"

local intensity  = 0
local bypassed   = false
local ab_mode    = false       -- false=A (processed), true=B (bypass)
local clip_mode  = 0           -- 0=tube  1=tape
local mono_sum   = false
local vocal_preset = 1         -- 1=warm, 2=bright, 3=aggressive, 4=broadcast
local saturation_type = 1      -- 1=even (warm), 2=odd (bright)
local parallel_mix = 0.0       -- 0.0-1.0 dry/wet of compression stage
local stage_name = "---"
local frame      = 0
local vu_level   = 0
local vu_peak    = 0
local vu_peak_ttl= 0
local amp_in_l   = 0           -- input level poll

-- NEW: Screen redesign state
local beat_phase = 0
local popup_param = nil
local popup_val = nil
local popup_time = 0

local NUM_KNOBS = 12

local KNOB_DEFS = {
  { l="GAIN",  x=14,  y=18, r=5  },
  { l="COMP",  x=30,  y=14, r=4  },
  { l="THRSH", x=46,  y=20, r=5  },
  { l="RATIO", x=62,  y=14, r=4  },
  { l="ATK",   x=78,  y=19, r=4  },
  { l="REL",   x=94,  y=14, r=5  },
  { l="HIGH",  x=110, y=20, r=4  },
  { l="LOW",   x=20,  y=44, r=5  },
  { l="MID",   x=38,  y=48, r=4  },
  { l="SAT",   x=58,  y=43, r=5  },
  { l="AIR",   x=76,  y=49, r=4  },
  { l="DRV",   x=96,  y=43, r=5  },
}

local ANGLE_MAP  = { 2.5, 3.0, -2.0, 2.8, -1.8, 2.2, 1.5, 1.2, 1.8, 3.2, 2.0, 2.6 }
local BASE_ANGLE = -2.35

local VOCAL_PRESETS = {
  warm       = { name = "WARM",       range_min = 0.3, range_max = 0.6, bias = "low"  },
  bright     = { name = "BRIGHT",     range_min = 0.5, range_max = 0.8, bias = "high" },
  aggressive = { name = "AGGRESSIVE", range_min = 0.7, range_max = 1.0, bias = "high" },
  broadcast  = { name = "BROADCAST",  range_min = 0.4, range_max = 0.7, bias = "mid"  },
}

local PRESET_NAMES = { "warm", "bright", "aggressive", "broadcast" }

local knobs = {}

--------------------------------------
-- INTENSITY → ENGINE (with preset mapping)
--------------------------------------

local function apply_intensity()
  -- Apply vocal preset intensity curve if a preset is active
  local effective_intensity = intensity
  
  if vocal_preset >= 1 and vocal_preset <= #PRESET_NAMES then
    local preset = VOCAL_PRESETS[PRESET_NAMES[vocal_preset]]
    if preset then
      -- Map intensity through preset range
      local t = intensity / 100
      if preset.bias == "low" then
        -- Bias toward lower range
        effective_intensity = util.linlin(0, 1, preset.range_min, preset.range_max, t * 0.7) * 100
      elseif preset.bias == "high" then
        -- Bias toward higher range
        effective_intensity = util.linlin(0, 1, preset.range_min, preset.range_max, 0.3 + t * 0.7) * 100
      else
        -- Mid bias (balanced)
        effective_intensity = util.linlin(0, 1, preset.range_min, preset.range_max, t) * 100
      end
    end
  end

  local t = effective_intensity / 100

  if     effective_intensity == 0  then stage_name = "---"
  elseif effective_intensity <= 25 then stage_name = "PRE"
  elseif effective_intensity <= 50 then stage_name = "CMP"
  elseif effective_intensity <= 75 then stage_name = "SOO"
  else                                  stage_name = "AIR"
  end

  -- A/B comparison: if in B mode, temporarily bypass by setting intensity to 0
  if ab_mode then
    engine.input_gain(1.0)
    engine.sat_drive(0.0)
    engine.trans_mix(0.0)
    engine.comp_mix(0.0)
    engine.sooth_depth(0.0)
    engine.air_gain(0.0)
    engine.out_gain(1.0)
    return
  end

  if bypassed then
    engine.input_gain(1.0)
    engine.sat_drive(0.0)
    engine.trans_mix(0.0)
    engine.comp_mix(0.0)
    engine.sooth_depth(0.0)
    engine.air_gain(0.0)
    engine.out_gain(1.0)
    return
  end

  -- preamp
  engine.input_gain(util.linlin(0, 1, 0.9, 1.5, t))
  engine.sat_drive(util.linlin(0, 1, 0.0, 0.7, t))
  engine.clip_mode(clip_mode)

  -- transient shaper
  engine.trans_attack(util.linlin(0, 1, 0.005, 0.001, t))
  engine.trans_sustain(util.linlin(0, 1, 0.5, 0.15, t))
  engine.trans_mix(util.linlin(0, 1, 0.0, 0.65, t))

  -- compressor
  engine.comp_thresh(util.linlin(0, 1, 0.9, 0.15, t))
  engine.comp_ratio(util.linlin(0, 1, 1.5, 8.0, t))
  engine.comp_attack(util.linlin(0, 1, 0.05, 0.003, t))
  engine.comp_release(util.linlin(0, 1, 0.4, 0.08, t))
  local comp_wet = util.linlin(0, 1, 0.0, 0.9, t)
  engine.comp_mix(util.linlin(0, parallel_mix, comp_wet, comp_wet * parallel_mix, 1))

  -- harmonic character via saturation type (even=warm low mids, odd=bright highs)
  if saturation_type == 1 then
    -- even harmonics: warm, add low-mid presence
    engine.sooth_q(util.linlin(0, 1, 0.5, 0.3, t))
  else
    -- odd harmonics: bright, enhance highs
    engine.sooth_q(util.linlin(0, 1, 0.5, 0.15, t))
  end
  engine.sooth_depth(util.linlin(0, 1, 0.0, 0.75, t))

  -- air shelf (fades in above 50%)
  local air_t = util.linlin(0.5, 1.0, 0.0, 1.0, math.max(t, 0.5))
  engine.air_gain(util.linlin(0, 1, 0.0, 6.0, air_t))

  -- output
  engine.out_gain(util.linlin(0, 1, 0.8, 0.72, t))

  -- mono
  engine.pan(mono_sum and 0.0 or 1.0)
end

--------------------------------------
-- VU (intensity-driven animation)
--------------------------------------

function update_vu()
  local t = intensity / 100
  local target = t * (0.6 + math.sin(frame * 0.13) * 0.2 + math.random() * 0.2)
  vu_level = vu_level + (target - vu_level) * 0.12

  if vu_level > vu_peak then
    vu_peak    = vu_level
    vu_peak_ttl = 45
  else
    vu_peak_ttl = vu_peak_ttl - 1
    if vu_peak_ttl <= 0 then
      vu_peak = math.max(0, vu_peak - 0.005)
    end
  end
end

--------------------------------------
-- KNOB ANIMATION
--------------------------------------

function animate_knobs()
  local t        = intensity / 100
  local activity = 0.008 + t * 0.045
  for i = 1, NUM_KNOBS do
    local target  = BASE_ANGLE + ANGLE_MAP[i] * t
    knobs[i].angle = knobs[i].angle + (target - knobs[i].angle) * 0.065
    knobs[i].angle = knobs[i].angle + (math.random() - 0.5) * activity
  end
end

--------------------------------------
-- SCREEN: NEW DESIGN SYSTEM
--------------------------------------

-- Helper: Get vocal preset name
local function get_preset_name()
  if vocal_preset >= 1 and vocal_preset <= #PRESET_NAMES then
    return PRESET_NAMES[vocal_preset]:upper()
  end
  return nil
end

-- Helper: Draw signal chain node
local function draw_chain_node(x, y, brightness, stage_index, total_stages, t)
  screen.aa(1)
  local node_r = 3
  
  -- Node circle with brightness reflecting activity
  local level = brightness == 0 and 3 or math.floor(util.linlin(0, 1, 3, 15, brightness))
  screen.level(level)
  screen.circle(x, y, node_r)
  screen.fill()
  
  -- Highlight ring if this stage is active (filled stages <= intensity threshold)
  local fill_threshold = intensity / 100 * total_stages
  if stage_index <= fill_threshold then
    screen.level(12)
    screen.circle(x, y, node_r + 1)
    screen.stroke()
  end
end

-- Helper: Draw waveform segment between nodes
local function draw_waveform(x1, y1, x2, y2, complexity)
  screen.aa(1)
  local steps = 8
  local height = 2 + complexity * 3
  
  screen.level(4 + complexity * 2)
  screen.move(x1, y1)
  
  for i = 1, steps do
    local t_pos = i / steps
    local x = x1 + (x2 - x1) * t_pos
    local y = y1 + (y2 - y1) * t_pos + math.sin(t_pos * math.pi + beat_phase) * height
    screen.line(x, y)
  end
  screen.stroke()
end

-- Helper: Draw the signal chain live zone
local function draw_live_zone(t)
  local y_base = 25
  local x_start = 5
  local x_spacing = 24
  
  -- Stage names and their current activity level
  local stages = {
    { name = "TRANS", x = x_start },
    { name = "PREAMP", x = x_start + x_spacing * 1 },
    { name = "COMP", x = x_start + x_spacing * 2 },
    { name = "SOOTHE", x = x_start + x_spacing * 3 },
    { name = "AIR", x = x_start + x_spacing * 4 },
  }
  
  -- Draw connecting lines and waveforms
  for i = 1, #stages - 1 do
    local complexity = (i / (#stages - 1)) * t
    draw_waveform(stages[i].x + 3, y_base, stages[i + 1].x - 3, y_base, complexity)
  end
  
  -- Draw nodes
  local fill_threshold = t * #stages
  for i, stage in ipairs(stages) do
    local brightness = i <= fill_threshold and 1.0 or 0.0
    draw_chain_node(stage.x, y_base, brightness, i, #stages, t)
  end
  
  -- A/B indicator (if toggle active)
  if ab_mode then
    screen.level(10)
    screen.font_size(5)
    screen.move(120, 18)
    screen.text("B")
  end
end

-- Helper: Draw context bar with intensity and VU meter
local function draw_context_bar()
  local y = 54

  -- "INTENSITY" label
  screen.level(4)
  screen.font_size(4)
  screen.font_face(1)
  screen.move(2, y + 4)
  screen.text("INTENSITY")

  -- Intensity value as number
  screen.level(5)
  screen.font_size(4)
  screen.move(60, y + 4)
  screen.text_right(string.format("%3d", intensity))

  -- Mini bar graph (5 segments)
  local bar_x = 65
  for s = 0, 4 do
    local fill = intensity / 100 * 5
    local bright = s < math.floor(fill) and 10 or (s == math.floor(fill) and math.floor((fill % 1) * 8 + 2) or 3)
    screen.level(bright)
    screen.rect(bar_x + s * 11, y + 1, 10, 4)
    screen.fill()
  end

  -- VU meter: horizontal bar showing input level
  screen.level(3)
  screen.rect(2, y - 4, 55, 2)
  screen.stroke()
  local vu_width = math.floor(vu_level * 55)
  if vu_width > 0 then
    local vu_bright = vu_level > 0.8 and 15 or (vu_level > 0.6 and 12 or 8)
    screen.level(vu_bright)
    screen.rect(2, y - 4, vu_width, 2)
    screen.fill()
  end

  -- MIDI channel (placeholder)
  screen.level(5)
  screen.font_size(4)
  screen.move(128, y + 4)
  screen.text_right("CH1")
end

-- Helper: Draw parameter popup
local function draw_popup()
  if popup_param == nil or popup_time <= 0 then return end
  
  local fade = math.min(1.0, popup_time / 0.8)
  local bg_level = math.floor(fade * 15)
  
  -- Dark background box
  screen.level(1)
  screen.rect(20, 30, 88, 12)
  screen.fill()
  
  -- Param name and value
  screen.level(15)
  screen.font_size(5)
  screen.font_face(1)
  screen.move(64, 37)
  screen.text_center(popup_param .. ": " .. popup_val)
end

function redraw()
  local t = intensity / 100
  screen.clear()
  
  -- STATUS STRIP (y 0-8)
  screen.level(4)
  screen.font_size(8)
  screen.font_face(4)
  screen.move(2, 7)
  screen.text("NEVE")
  
  local preset_name = get_preset_name()
  if preset_name then
    screen.level(6)
    screen.font_size(5)
    screen.font_face(1)
    screen.move(126, 7)
    screen.text_right(preset_name)
  end
  
  -- Beat pulse dot at x=124
  beat_phase = (beat_phase + 0.15) % (math.pi * 2)
  local pulse_intensity = 3 + math.sin(beat_phase) * 6
  screen.level(math.floor(pulse_intensity))
  screen.circle(124, 4, 1)
  screen.fill()
  
  -- LIVE ZONE (y 9-52)
  draw_live_zone(t)
  
  -- CONTEXT BAR (y 53-58)
  draw_context_bar()
  
  -- PARAMETER POPUP
  draw_popup()
  
  screen.update()
end

--------------------------------------
-- MIDI CC AUTOMATION (CC1 → intensity)
--------------------------------------

function midi.event(data)
  local msg = midi.to_msg(data)
  if msg.type == "cc" and msg.cc == 1 then
    -- CC1 (modulation) controls intensity knob
    intensity = util.clamp(msg.val / 127 * 100, 0, 100)
    apply_intensity()
  end
end

--------------------------------------
-- INIT
--------------------------------------

function init()
  math.randomseed(os.time())

  for i = 1, NUM_KNOBS do
    knobs[i] = { angle = BASE_ANGLE }
  end

  params:add_separator("NEVE VOCAL CHAIN")

  params:add_option("vocal_preset", "vocal preset", PRESET_NAMES, vocal_preset)
  params:set_action("vocal_preset", function(v)
    vocal_preset = v
    apply_intensity()
  end)

  params:add_option("saturation_type", "saturation type", {"even (warm)", "odd (bright)"}, saturation_type)
  params:set_action("saturation_type", function(v)
    saturation_type = v
    apply_intensity()
  end)

  params:add_control("parallel_mix", "parallel mix",
    controlspec.new(0, 1, "lin", 0.01, 0.0, ""))
  params:set_action("parallel_mix", function(v)
    parallel_mix = v
    apply_intensity()
  end)

  apply_intensity()

  -- Set up input level poll
  if poll then
    poll.set("amp_in_l", function(val) vu_level = math.min(1.0, val / 1.0) end)
  end

  -- 10fps refresh for animation
  clock.run(function()
    while true do
      clock.sleep(1/10)
      frame = frame + 1
      animate_knobs()
      update_vu()
      popup_time = math.max(0, popup_time - 0.1)
      redraw()
    end
  end)
end

--------------------------------------
-- CONTROLS
--------------------------------------

function enc(n, d)
  if n == 1 then
    intensity = util.clamp(intensity + d, 0, 100)
    apply_intensity()
    
    -- Show popup for intensity change
    popup_param = "INTENSITY"
    popup_val = string.format("%d", intensity)
    popup_time = 0.8
  end
end

function key(n, z)
  if n == 1 and z == 1 then
    clip_mode = 1 - clip_mode
    engine.clip_mode(clip_mode)
    popup_param = "CLIP"
    popup_val = clip_mode == 0 and "TUBE" or "TAPE"
    popup_time = 0.8
  elseif n == 2 and z == 1 then
    mono_sum = not mono_sum
    engine.pan(mono_sum and 0.0 or 1.0)
    popup_param = "MONO"
    popup_val = mono_sum and "ON" or "OFF"
    popup_time = 0.8
  elseif n == 3 and z == 1 then
    ab_mode = not ab_mode
    apply_intensity()
    popup_param = "MODE"
    popup_val = ab_mode and "B" or "A"
    popup_time = 0.8
  end
end

--------------------------------------
-- CLEANUP
--------------------------------------

function cleanup()
  engine.input_gain(1.0)
  engine.sat_drive(0.0)
  engine.trans_mix(0.0)
  engine.comp_mix(0.0)
  engine.sooth_depth(0.0)
  engine.air_gain(0.0)
  engine.out_gain(1.0)
end
