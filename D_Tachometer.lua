--!SERVER_SCRIPT
-- Project Nexus - Initial D Style Tachometer HUD (vector-only, multi-theme)

------------------------------------------------------------
-- Persistent settings
------------------------------------------------------------

local STORAGE_UNIT  = ac.storage({ group = 'PN_ID_Tacho', name = 'UnitKmh',  value = true  })
local STORAGE_THEME = ac.storage({ group = 'PN_ID_Tacho', name = 'ThemeIdx', value = 1     })
local STORAGE_SCALE = ac.storage({ group = 'PN_ID_Tacho', name = 'Scale',    value = 1.00  })

local isKmh       = STORAGE_UNIT.value and true or false
local themeIndex  = STORAGE_THEME.value or 1
local Scale       = STORAGE_SCALE.value or 1.0

------------------------------------------------------------
-- Themes (colors & slight layout tweaks)
------------------------------------------------------------

local themes = {
  {
    id   = 1,
    name = "4th Stage",
    arcBase   = rgbm(0.18, 0.08, 0.0, 0.9),
    arcFill   = rgbm(1.00, 0.60, 0.00, 1.0),
    arcRed    = rgbm(1.00, 0.20, 0.05, 1.0),
    bgAlpha   = 0.20,
    digital   = rgbm(1.00, 0.86, 0.50, 1.0),
    label     = rgbm(1.00, 0.70, 0.35, 1.0),
    revWarn   = 0.88,
  },
  {
    id   = 2,
    name = "D3 White",
    arcBase   = rgbm(0.10, 0.10, 0.10, 0.9),
    arcFill   = rgbm(0.95, 0.95, 0.95, 1.0),
    arcRed    = rgbm(1.00, 0.25, 0.25, 1.0),
    bgAlpha   = 0.22,
    digital   = rgbm(0.80, 1.00, 1.00, 1.0),
    label     = rgbm(0.90, 0.90, 0.90, 1.0),
    revWarn   = 0.90,
  },
  {
    id   = 3,
    name = "D4X Dark",
    arcBase   = rgbm(0.05, 0.05, 0.05, 0.95),
    arcFill   = rgbm(0.40, 0.90, 0.30, 1.0),
    arcRed    = rgbm(1.00, 0.35, 0.35, 1.0),
    bgAlpha   = 0.30,
    digital   = rgbm(0.95, 0.95, 0.95, 1.0),
    label     = rgbm(0.75, 0.85, 1.00, 1.0),
    revWarn   = 0.92,
  }
}

local function getTheme()
  if themeIndex < 1 or themeIndex > #themes then
    themeIndex = 1
  end
  return themes[themeIndex]
end

------------------------------------------------------------
-- Constants & runtime state
------------------------------------------------------------

local KMH_TO_MPH = 0.621371
local KM_TO_MI   = 0.621371
local HUD_RADIUS = 150.0

local winPos      = nil
local draggingHud = false

local rpm        = 0
local speedKmh   = 0
local gear       = 0
local odometerKm = 0
local absOn      = false
local tcOn       = false

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function clamp(x, a, b)
  if x < a then return a end
  if x > b then return b end
  return x
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function getCar()
  local sim = ac.getSim()
  if not sim then return nil end
  return ac.getCar(sim.focusedCar)
end

local function getSpeed()
  local v = speedKmh
  if not isKmh then v = v * KMH_TO_MPH end
  return math.floor(v + 0.5)
end

local function getGearText()
  if gear == 0 then
    return "N"
  elseif gear == -1 then
    return "R"
  else
    return tostring(gear)
  end
end

------------------------------------------------------------
-- Core gauge drawing
------------------------------------------------------------

local function drawInitialDStyleGauge(car, center, radius, dt)
  local t      = getTheme()
  local maxRpm = car.rpmLimiter
  if maxRpm <= 0 then maxRpm = 8000 end

  local rpmFraction = clamp(rpm / (maxRpm * 1.05), 0, 1)

  --------------------------------------------------------
  -- Background circle (subtle)
  --------------------------------------------------------
  local bgR = radius * 1.08
  ui.pathClear()
  ui.pathArcTo(center, bgR, math.rad(-215), math.rad(35), 96)
  ui.pathStroke(rgbm(0, 0, 0, t.bgAlpha), false, radius * 0.40)

  --------------------------------------------------------
  -- Base arc (full range)
  --------------------------------------------------------
  local startA = math.rad(-210)
  local endA   = math.rad(  30)
  local outerR = radius * 0.98
  local innerR = radius * 0.78

  ui.pathClear()
  ui.pathArcTo(center, outerR, startA, endA, 96)
  ui.pathArcTo(center, innerR, endA, startA, 96)
  ui.pathStroke(t.arcBase, true, 1.0)

  --------------------------------------------------------
  -- Filled RPM arc with redline section
  --------------------------------------------------------
  local warnFrac = t.revWarn or 0.90
  local currentEnd = lerp(startA, endA, rpmFraction)

  if rpmFraction > 0 then
    local fillEnd = lerp(startA, endA, math.min(rpmFraction, warnFrac))
    ui.pathClear()
    ui.pathArcTo(center, outerR, startA, fillEnd, 64)
    ui.pathArcTo(center, innerR, fillEnd, startA, 64)
    ui.pathStroke(t.arcFill, true, 1.0)

    if rpmFraction > warnFrac then
      local redStart = lerp(startA, endA, warnFrac)
      local redEnd   = currentEnd
      ui.pathClear()
      ui.pathArcTo(center, outerR, redStart, redEnd, 48)
      ui.pathArcTo(center, innerR, redEnd, redStart, 48)
      ui.pathStroke(t.arcRed, true, 1.0)
    end
  end

  --------------------------------------------------------
  -- Tick marks and numeric RPM labels (0–max based on car)
  --------------------------------------------------------
  local step = 1000
  local maxK = math.ceil(maxRpm / step)
  for k = 0, maxK do
    local frac = k / maxK
    local a    = lerp(startA, endA, frac)
    local r1   = outerR * 0.97
    local r2   = outerR * ((k % 2 == 0) and 1.03 or 1.01)

    local sx = center.x + math.cos(a) * r1
    local sy = center.y + math.sin(a) * r1
    local ex = center.x + math.cos(a) * r2
    local ey = center.y + math.sin(a) * r2

    ui.drawLine(vec2(sx, sy), vec2(ex, ey),
      rgbm(1, 1, 1, (k % 2 == 0) and 0.9 or 0.5),
      (k % 2 == 0) and 2.0 or 1.0)

    if k > 0 then
      local labelR = outerR * 1.10
      local lx     = center.x + math.cos(a) * labelR
      local ly     = center.y + math.sin(a) * labelR
      local text   = tostring(k)
      local size   = radius * 0.11
      local w      = ui.measureDWriteText(text, size).x
      ui.dwriteDrawText(text, size, vec2(lx - w / 2, ly - size / 2),
        t.label)
    end
  end

  --------------------------------------------------------
  -- Digital speed & gear cluster (D4/D5/D4X style)
  --------------------------------------------------------
  local spd       = getSpeed()
  local speedText = string.format("%d", spd)
  local gearText  = getGearText()

  -- Speed (big, central)
  local speedSize = radius * 0.42
  local speedW    = ui.measureDWriteText(speedText, speedSize).x
  local speedPos  = vec2(center.x - speedW / 2, center.y - radius * 0.05)
  ui.dwriteDrawText(speedText, speedSize, speedPos, t.digital)

  -- Unit text under it
  local unitText  = isKmh and "km/h" or "mph"
  local unitSize  = radius * 0.13
  local unitW     = ui.measureDWriteText(unitText, unitSize).x
  local unitPos   = vec2(center.x - unitW / 2, center.y + radius * 0.20)
  ui.dwriteDrawText(unitText, unitSize, unitPos, t.label)

  -- Gear to the right (like D5/D4X)
  local gearSize = radius * 0.35
  local gearW    = ui.measureDWriteText(gearText, gearSize).x
  local gearPos  = vec2(center.x + radius * 0.55 - gearW / 2, center.y - radius * 0.03)
  ui.dwriteDrawText(gearText, gearSize, gearPos, t.digital)

  -- "MT" label under gear
  local mtText  = "MT"
  local mtSize  = radius * 0.14
  local mtW     = ui.measureDWriteText(mtText, mtSize).x
  local mtPos   = vec2(gearPos.x + gearW / 2 - mtW / 2, center.y + radius * 0.26)
  ui.dwriteDrawText(mtText, mtSize, mtPos, t.label)

  --------------------------------------------------------
  -- Odometer at bottom
  --------------------------------------------------------
  local dist = odometerKm
  if not isKmh then dist = dist * KM_TO_MI end

  local odoText = string.format("%06d %s", math.floor(dist), isKmh and "km" or "mi")
  local odoSize = radius * 0.11
  local odoW    = ui.measureDWriteText(odoText, odoSize).x
  local odoPos  = vec2(center.x - odoW / 2, center.y + radius * 0.55)
  ui.dwriteDrawText(odoText, odoSize, odoPos, t.label)

  --------------------------------------------------------
  -- Rev warning light
  --------------------------------------------------------
  if rpmFraction >= (t.revWarn or 0.9) then
    local lightR = radius * 0.06
    local lx     = center.x
    local ly     = center.y - radius * 0.75
    ui.drawCircleFilled(vec2(lx, ly), lightR, t.arcRed)
    ui.dwriteDrawText("REV", radius * 0.11,
      vec2(lx - radius * 0.13, ly + lightR + 2),
      t.label)
  end

  --------------------------------------------------------
  -- ABS / TC indicator lights
  --------------------------------------------------------
  local boxW  = radius * 0.32
  local boxH  = radius * 0.12
  local gap   = radius * 0.06
  local baseY = center.y + radius * 0.72

  local absPos = vec2(center.x - boxW - gap / 2, baseY)
  local tcPos  = vec2(center.x + gap / 2,       baseY)

  local function drawIndicator(pos, text, active, colorOn)
    local bg    = rgbm(0, 0, 0, 0.85)
    local brd   = rgbm(1, 1, 1, 0.7)
    local fill  = active and colorOn or rgbm(0.25, 0.25, 0.25, 0.9)
    ui.drawRectFilled(pos, pos + vec2(boxW, boxH), bg)
    ui.drawRect(pos, pos + vec2(boxW, boxH), brd)
    ui.drawRectFilled(pos, pos + vec2(boxW, boxH),
      rgbm(fill.r, fill.g, fill.b, 0.18))

    local size = radius * 0.12
    local w    = ui.measureDWriteText(text, size).x
    local c    = vec2(pos.x + boxW / 2 - w / 2, pos.y + boxH / 2 - size / 2)
    ui.dwriteDrawText(text, size, c, active and colorOn or t.label)
  end

  drawIndicator(absPos, "ABS", absOn, rgbm(1.0, 0.95, 0.3, 1.0))
  drawIndicator(tcPos,  "TC",  tcOn,  rgbm(0.4, 0.9, 1.0, 1.0))
end

------------------------------------------------------------
-- Window & controls (unit toggle, theme, drag)
------------------------------------------------------------

local function windowMain(dt, winSize)
  local car = getCar()
  if not car then return end

  local theme = getTheme()

  local winOrigin = ui.windowPos()
  local mouse     = ui.mousePos()
  local localPos  = vec2(mouse.x - winOrigin.x, mouse.y - winOrigin.y)

  ------------------------------------------------------
  -- KMH / MPH toggle pill (top left)
  ------------------------------------------------------
  local pillPos  = vec2(10, 10)
  local pillSize = vec2(90, 26)
  local pillEnd  = pillPos + pillSize
  local midX     = pillPos.x + pillSize.x * 0.5

  ui.drawRectFilled(pillPos, pillEnd, rgbm(0, 0, 0, 0.6))
  ui.drawRect(pillPos, pillEnd, rgbm(1, 1, 1, 0.8))

  local kmhMin = pillPos
  local kmhMax = vec2(midX, pillEnd.y)
  local mphMin = vec2(midX, pillPos.y)
  local mphMax = pillEnd

  if isKmh then
    ui.drawRectFilled(kmhMin, kmhMax, rgbm(0.0, 0.55, 0.2, 0.95))
  else
    ui.drawRectFilled(mphMin, mphMax, rgbm(0.10, 0.35, 0.90, 0.95))
  end

  ui.drawLine(vec2(midX, pillPos.y), vec2(midX, pillEnd.y), rgbm(1,1,1,0.6), 1)

  ui.dwriteDrawText("KPH", 13, vec2(kmhMin.x + 8, kmhMin.y + 4), rgbm(1,1,1,1))
  ui.dwriteDrawText("MPH", 13, vec2(mphMin.x + 8, mphMin.y + 4), rgbm(1,1,1,1))

  if ui.mouseClicked(0) then
    if localPos.x >= kmhMin.x and localPos.x <= kmhMax.x and
       localPos.y >= kmhMin.y and localPos.y <= kmhMax.y then
      isKmh = true
      STORAGE_UNIT.value = true
    elseif localPos.x >= mphMin.x and localPos.x <= mphMax.x and
           localPos.y >= mphMin.y and localPos.y <= mphMax.y then
      isKmh = false
      STORAGE_UNIT.value = false
    end
  end

  ------------------------------------------------------
  -- Theme cycle button (top centre)
  ------------------------------------------------------
  local themeW  = 110
  local themeH  = 22
  local themePos = vec2(winSize.x / 2 - themeW / 2, 12)
  local themeEnd = themePos + vec2(themeW, themeH)

  ui.drawRectFilled(themePos, themeEnd, rgbm(0, 0, 0, 0.7))
  ui.drawRect(themePos, themeEnd, rgbm(1, 1, 1, 0.6))

  local themeLabel = theme.name
  local themeSize  = 13
  local labelW     = ui.measureDWriteText(themeLabel, themeSize).x
  local labelPos   = vec2(
    themePos.x + themeW / 2 - labelW / 2,
    themePos.y + themeH / 2 - themeSize / 2
  )
  ui.dwriteDrawText(themeLabel, themeSize, labelPos, rgbm(1,1,1,1))

  if ui.mouseClicked(0) then
    if localPos.x >= themePos.x and localPos.x <= themeEnd.x and
       localPos.y >= themePos.y and localPos.y <= themeEnd.y then
      themeIndex = themeIndex + 1
      if themeIndex > #themes then themeIndex = 1 end
      STORAGE_THEME.value = themeIndex
    end
  end

  ------------------------------------------------------
  -- Drag handle (top right)
  ------------------------------------------------------
  local dragSize = 22
  local dragPos  = vec2(winSize.x - dragSize - 10, 10)
  local dragEnd  = dragPos + vec2(dragSize, dragSize)

  ui.drawRectFilled(dragPos, dragEnd, rgbm(0, 0, 0, 0.65))
  ui.drawRect(dragPos, dragEnd, rgbm(1, 1, 1, 0.8))

  local cx  = (dragPos.x + dragEnd.x) * 0.5
  local cy  = (dragPos.y + dragEnd.y) * 0.5
  local arm = dragSize * 0.35

  ui.drawLine(vec2(cx - arm, cy), vec2(cx + arm, cy), rgbm(1,1,1,1), 1.4)
  ui.drawLine(vec2(cx, cy - arm), vec2(cx, cy + arm), rgbm(1,1,1,1), 1.4)

  local overDrag = (
    localPos.x >= dragPos.x and localPos.x <= dragEnd.x and
    localPos.y >= dragPos.y and localPos.y <= dragEnd.y
  )

  if overDrag and ui.mouseClicked(0) then
    draggingHud = true
  end
  if not ui.mouseDown(0) then
    draggingHud = false
  end
  if draggingHud and ui.mouseDown(0) then
    local d = ui.mouseDelta()
    if d.x ~= 0 or d.y ~= 0 then
      winPos = vec2(winPos.x + d.x, winPos.y + d.y)
    end
  end

  ------------------------------------------------------
  -- Draw the gauge itself
  ------------------------------------------------------
  local center = vec2(winSize.x / 2, winSize.y / 2 + 10)
  drawInitialDStyleGauge(car, center, HUD_RADIUS * Scale, dt)
end

------------------------------------------------------------
-- Script lifecycle
------------------------------------------------------------

function script.update(dt)
  local car = getCar()
  if not car then return end

  rpm        = car.rpm
  speedKmh   = car.speedKmh
  gear       = car.gear
  odometerKm = car.distanceDrivenTotalKm or 0

  -- These fields may vary slightly between CSP versions; adjust if needed.
  absOn      = car.absEnabled or car.absInAction or false
  tcOn       = car.tcEnabled  or car.tcInAction  or false
end

function script.drawUI(dt)
  local car = getCar()
  if not car then return end

  dt = dt or 0.016
  local full    = ui.windowSize()
  local radius  = HUD_RADIUS * Scale
  local winSize = vec2(radius * 2.9, radius * 2.7)

  if not winPos then
    -- default bottom-left like the arcade
    winPos = vec2(40, full.y - winSize.y - 40)
  end

  ui.beginTransparentWindow("PN_InitialD_Tacho", winPos, winSize)
  windowMain(dt, winSize)
  ui.endTransparentWindow()
end
