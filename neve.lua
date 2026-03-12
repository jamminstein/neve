-- NEVE
-- vocal chain: transient → preamp → comp → soothe → air
-- enc1: intensity  |  k1: clip mode  |  k2: mono  |  k3: bypass
-- inspired by Rupert Neve 1073, SSL comp, Soothe2

engine.name = "Neve"

local intensity  = 0
local bypassed   = false
local clip_mode  = 0      -- 0=tube  1=tape
local mono_sum   = false
local stage_name = "---"
local frame      = 0
local vu_level   = 0
local vu_peak    = 0
local vu_peak_ttl= 0

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

local knobs = {}

--------------------------------------
-- INIT
--------------------------------------

function init()
  math.randomseed(os.time())

  for i = 1, NUM_KNOBS do
    knobs[i] = { angle = BASE_ANGLE }
  end

  params:add_separator("NEVE VOCAL CHAIN")

  apply_intensity()

  clock.run(function()
    while true do
      clock.sleep(1/30)
      frame = frame + 1
      animate_knobs()
      update_vu()
      redraw()
    end
  end)
end

--------------------------------------
-- INTENSITY → ENGINE
--------------------------------------

function apply_intensity()
  local t = intensity / 100

  if     intensity == 0  then stage_name = "---"
  elseif intensity <= 25 then stage_name = "PRE"
  elseif intensity <= 50 then stage_name = "CMP"
  elseif intensity <= 75 then stage_name = "SOO"
  else                        stage_name = "AIR"
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
  engine.trans_attackhutil.linlin(0, 1, 0.005, 0.001, t))
  engine.trans_sustain(util.linlin(0, 1, 0.5, 0.15, t))
  engine.trans_mix(util.linlin(0, 1, 0.0, 0.65, t))

  -- compressor
  engine.comp_thresh(util.linlin(0, 1, 0.9, 0.15, t))
  engine.comp_ratio(util.linlin(0, 1, 1.5, 8.0, t))
  engine.comp_attackhutil.linlin(0, 1, 0.05, 0.003, t))
  engine.comp_release(util.linlin(0, 1, 0.4, 0.08, t))
  engine.comp_mix(util.linlin(0, 1, 0.0, 0.9, t))

  -- spectral smooth
  engine.sooth_q(util.linlin(0, 1, 0.5, 0.2, t))
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
-- SCREEN
--------------------------------------

local function draw_knob(k, def, t)
  local x, y, r = def.x, def.y, def.r

  screen.level(2)
  screen.arc(x, y, r + 1, BASE_ANGLE, BASE_ANGLE + 5.0)
  screen.stroke()

  screen.level(math.floor(util.linlin(0, 1, 3, 11, t)))
  screen.circle(x, y, r)
  screen.stroke()

  screen.level(bypassed and 5 or 15)
  screen.move(x, y)
  screen.line(
    x + (r - 1) * math.cos(k.angle),
    y + (r - 1) * math.sin(k.angle)
  )
  screen.stroke()

  screen.level(stage_name ~= "---" and math.floor(util.linlin(0, 1, 2, 8, t)) or 2)
  screen.font_size(4)
  screen.font_face(1)
  screen.move(x, y + r + 5)
  screen.text_center(def.l)
end

local function draw_vu()
  local cx, cy, R = 64, 33, 9
  local min_a = math.pi * (210 / 180)
  local max_a = math.pi * (330 / 180)
  local vu_a  = util.linlin(0, 1, min_a, max_a, math.min(vu_level, 1))
  local pk_a  = util.linlin(0, 1, min_a, max_a, math.min(vu_peak,  1))

  screen.level(2)
  screen.arc(cx, cy, R, min_a, max_a)
  screen.stroke()

  if not bypassed and vu_level > 0.01 then
    screen.level(math.floor(util.linlin(0, 1, 4, 14, vu_level)))
    screen.arc(cx, cy, R, min_a, vu_a)
    screen.stroke()
  end

  screen.level(bypassed and 4 or 15)
  screen.move(cx, cy)
  screen.line(cx + R * math.cos(vu_a), cy + R * math.sin(vu_a))
  screen.stroke()

  if vu_peak > 0.02 then
    screen.level(7)
    screen.move(cx + (R-1) * math.cos(pk_a), cy + (R-1) * math.sin(pk_a))
    screen.line(cx + (R+1) * math.cos(pk_a), cy + (R+1) * math.sin(pk_a))
    screen.stroke()
  end

  screen.level(3)
  screen.font_size(4)
  screen.move(cx, cy + 5)
  screen.text_center("VU")
end

function redraw()
  local t = intensity / 100
  screen.clear()

  -- grid
  screen.level(1)
  for gx = 0, 128, 16 do
    screen.move(gx, 0) screen.line(gx, 64) screen.stroke()
  end
  for gy = 0, 64, 16 do
    screen.move(0, gy) screen.line(128, gy) screen.stroke()
  end

  -- knobs
  for i = 1, NUM_KNOBS do
    draw_knob(knobs[i], KNOB_DEFS[i], t)
  end

  -- VU
  draw_vu()

  -- intensity bar (segmented)
  for s = 0, 4 do
    local fill  = t * 5
    local bright
    if s < math.floor(fill) then
      bright = 15
    elseif s == math.floor(fill) then
      bright = math.floor((fill % 1) * 12)
    else
      bright = 2
    end
    screen.level(bright)
    screen.rect(s * 26, 60, 24, 3)
    screen.fill()
  end

  -- header
  screen.level(bypassed and 3 or math.floor(util.linlin(0, 1, 4, 15, t)))
  screen.font_size(8)
  screen.font_face(4)
  screen.move(2, 8)
  screen.text("NEVE")

  screen.level(bypassed and 2 or math.floor(util.linlin(0, 1, 2, 10, t)))
  screen.font_size(5)
  screen.font_face(1)
  screen.move(36, 8)
  screen.text(stage_name)

  screen.level(clip_mode == 1 and 10 or 4)
  screen.move(60, 8)
  screen.text(clip_mode == 0 and "TUBE" or "TAPE")

  if mono_sum then
    screen.level(10)
    screen.move(86, 8)
    screen.text("MONO")
  end

  if bypassed then
    screen.level(8)
    screen.move(110, 8)
    screen.text("BYP")
  end

  screen.level(6)
  screen.font_size(5)
  screen.move(126, 8)
  screen.text_right(string.format("%3d", intensity))

  screen.update()
end

--------------------------------------
-- CONTROLS
--------------------------------------

function enc(n, d)
  if n == 1 then
    intensity = util.clamp(intensity + d, 0, 100)
    apply_intensity()
  end
end

function key(n, z)
  if n == 1 and z == 1 then
    clip_mode = 1 - clip_mode
    engine.clip_mode(clip_mode)
  elseif n == 2 and z == 1 then
    mono_sum = not mono_sum
    engine.pan(mono_sum and 0.0 or 1.0)
  elseif n == 3 and z == 1 then
    bypassed = not bypassed
    apply_intensity()
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
