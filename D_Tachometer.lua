--!SERVER_SCRIPT
-- Project Nexus - Initial D Inspired Tachometer (vector-only)

------------------------------------------------------------
-- Persistent settings
------------------------------------------------------------

local STORAGE_UNIT  = ac.storage({ group = 'PN_D_Tacho', name = 'UnitKmh', value = true })
local STORAGE_SCALE = ac.storage({ group = 'PN_D_Tacho', name = 'Scale',   value = 1.0 })

local isKmh  = STORAGE_UNIT.value and true or false
local Scale  = STORAGE_SCALE.value or 1.0

------------------------------------------------------------
-- Constants & runtime state
------------------------------------------------------------

local KMH_TO_MPH    = 0.621371
local KM_TO_MI      = 0.621371
local HUD_RADIUS    = 150.0  -- base logical radius

local winPos        = nil
local draggingHud   = false

local rpm           = 0
local speedKmh      = 0
local gear          = 0
local odometerKm    = 0

local colors = {
  white      = rgbm(1, 1, 1, 1),
  faintWhite = rgbm(1, 1, 1, 0.15),
  arcBase    = rgbm(0.10, 0.10, 0.10, 0.85),
  pillBg     = rgbm(0, 0, 0, 0.55),
  pillBorder = rgbm(1, 1, 1, 0.8),
  handleBg   = rgbm(0, 0, 0, 0.65),
  handleBrd  = rgbm(1, 1, 1, 0.8),
}

------------------------------------------------------------
-- Small helpers
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

------------------------------------------------------------
-- Initial D–style vector gauge
------------------------------------------------------------

local function drawInitialDStyledGauge(car, center, radius, dt)
  dt = dt or 0.016

  --------------------------------------------------------
  -- Base dual-ring arc, like the Initial D themes
  --------------------------------------------------------

  local outerR = radius * 1.02
  local innerR = radius * 0.78
  local innerInnerR = radius * 0.60

  local startA = math.rad(-210)
  local endA   = math.rad(  30)

  -- Outer faint ring
  ui.pathClear()
  ui.pathArcTo(center, outerR, startA, endA, 80)
  ui.pathStroke(colors.arcBase, false, 8.0)

  -- Second faint inner ring
  ui.pathClear()
  ui.pathArcTo(center, innerInnerR, startA, endA, 80)
  ui.pathStroke(colors.faintWhite, false, 2.0)

  --------------------------------------------------------
  -- RPM fill arc (white -> yellow -> red)
  --------------------------------------------------------

  local maxRpm = car.rpmLimiter
  if maxRpm <= 0 then maxRpm = 8000 end
  local rpmFraction = clamp(rpm / (maxRpm * 1.05), 0, 1)

  local filledEnd = lerp(startA, endA, rpmFraction)

  local rpmColor = rgbm(1, 1, 1, 0.95)           -- white
  if rpmFraction > 0.80 then
    rpmColor = rgbm(1.0, 0.9, 0.1, 1.0)         -- yellow
  end
  if rpmFraction > 0.95 then
    rpmColor = rgbm(1.0, 0.25, 0.25, 1.0)       -- red
  end

  ui.pathClear()
  ui.pathArcTo(center, outerR, startA, filledEnd, 80)
  ui.pathStroke(rpmColor, false, 10.0)

  --------------------------------------------------------
  -- Small tick marks along the arc (Initial D feel)
  --------------------------------------------------------

  local ticks = 12
  for i = 0, ticks do
    local t = i / ticks
    local a = lerp(startA, endA, t)
    local sR = innerInnerR * 0.99
    local eR = innerInnerR * 1.04

    local sx = center.x + math.cos(a) * sR
    local sy = center.y + math.sin(a) * sR
    local ex = center.x + math.cos(a) * eR
    local ey = center.y + math.sin(a) * eR

    ui.drawLine(vec2(sx, sy), vec2(ex, ey), colors.faintWhite, (i % 3 == 0) and 2.0 or 1.0)
  end

  --------------------------------------------------------
  -- Digital speed in the center
  --------------------------------------------------------

  local spd       = getSpeed()
  local speedText = string.format('%d', spd)

  local speedSize = radius * 0.40
  local speedW    = ui.measureDWriteText(speedText, speedSize).x
  local speedPos  = vec2(center.x - speedW / 2, center.y - radius * 0.10)

  ui.dwriteDrawText(speedText, speedSize, speedPos, colors.white)

  -- Speed unit below (km/h or mph)
  local unitText  = isKmh and 'km/h' or 'mph'
  local unitSize  = radius * 0.13
  local unitW     = ui.measureDWriteText(unitText, unitSize).x
  local unitPos   = vec2(center.x - unitW / 2, center.y + radius * 0.16)

  ui.dwriteDrawText(unitText, unitSize, unitPos, colors.white)

  --------------------------------------------------------
  -- Gear (large letter / number at bottom of arc)
  --------------------------------------------------------

  local gearText
  if gear == 0 then
    gearText = 'N'
  elseif gear == -1 then
    gearText = 'R'
  else
    gearText = tostring(gear)
  end

  local gearSize = radius * 0.30
  local gearW    = ui.measureDWriteText(gearText, gearSize).x
  local gearPos  = vec2(center.x - gearW / 2, center.y + radius * 0.36)

  ui.dwriteDrawText(gearText, gearSize, gearPos, colors.white)

  --------------------------------------------------------
  -- Odometer at very bottom (like Initial D: six digits)
  --------------------------------------------------------

  local dist = odometerKm
  if not isKmh then dist = dist * KM_TO_MI end

  local odoText = string.format('%06d %s', math.floor(dist), isKmh and 'km' or 'mi')
  local odoSize = radius * 0.12
  local odoW    = ui.measureDWriteText(odoText, odoSize).x
  local odoPos  = vec2(center.x - odoW / 2, center.y + radius * 0.60)

  ui.dwriteDrawText(odoText, odoSize, odoPos, colors.white)

  --------------------------------------------------------
  -- Small "x1000 rpm" label in the inner right
  --------------------------------------------------------

  local rpmLabel = 'x1000 rpm'
  local labelSize = radius * 0.12
  local labelPos  = vec2(center.x + radius * 0.45, center.y - radius * 0.05)

  ui.dwriteDrawText(rpmLabel, labelSize, labelPos, colors.faintWhite)
end

------------------------------------------------------------
-- Window + input (KMH/MPH pill + drag handle)
------------------------------------------------------------

local function windowMain(dt, winSize)
  local car = getCar()
  if not car then return end

  local winOrigin = ui.windowPos()
  local mouse     = ui.mousePos()
  local localPos  = vec2(mouse.x - winOrigin.x, mouse.y - winOrigin.y)

  ------------------------------------------------------
  -- KMH / MPH toggle pill (top-left)
  ------------------------------------------------------

  local pillPos  = vec2(10, 10)
  local pillSize = vec2(90, 26)
  local pillEnd  = vec2(pillPos.x + pillSize.x, pillPos.y + pillSize.y)
  local midX     = pillPos.x + pillSize.x * 0.5

  ui.drawRectFilled(pillPos, pillEnd, colors.pillBg)
  ui.drawRect(pillPos, pillEnd, colors.pillBorder)

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

  ui.dwriteDrawText('KMH', 13, vec2(kmhMin.x + 8, kmhMin.y + 4), colors.white)
  ui.dwriteDrawText('MPH', 13, vec2(mphMin.x + 8, mphMin.y + 4), colors.white)

  if ui.mouseClicked(0) then
    if localPos.x >= kmhMin.x and localPos.x <= kmhMax.x
    and localPos.y >= kmhMin.y and localPos.y <= kmhMax.y then
      isKmh = true
      STORAGE_UNIT.value = true
    elseif localPos.x >= mphMin.x and localPos.x <= mphMax.x
    and localPos.y >= mphMin.y and localPos.y <= mphMax.y then
      isKmh = false
      STORAGE_UNIT.value = false
    end
  end

  ------------------------------------------------------
  -- Drag handle (top-right) – Initial D style move icon
  ------------------------------------------------------

  local dragSize = 22
  local dragPos  = vec2(winSize.x - dragSize - 10, 10)
  local dragMin  = dragPos
  local dragMax  = vec2(dragPos.x + dragSize, dragPos.y + dragSize)

  ui.drawRectFilled(dragMin, dragMax, colors.handleBg)
  ui.drawRect(dragMin, dragMax, colors.handleBrd)

  local cx  = (dragMin.x + dragMax.x) * 0.5
  local cy  = (dragMin.y + dragMax.y) * 0.5
  local arm = dragSize * 0.35

  ui.drawLine(vec2(cx - arm, cy), vec2(cx + arm, cy), colors.white, 1.4)
  ui.drawLine(vec2(cx, cy - arm), vec2(cx, cy + arm), colors.white, 1.4)

  local overDrag =
    localPos.x >= dragMin.x and localPos.x <= dragMax.x and
    localPos.y >= dragMin.y and localPos.y <= dragMax.y

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
  -- Draw the main gauge
  ------------------------------------------------------

  local center = vec2(winSize.x / 2, winSize.y / 2)
  drawInitialDStyledGauge(car, center, HUD_RADIUS * Scale, dt)
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
  odometerKm = car.distanceDrivenTotalKm
end

function script.drawUI(dt)
  dt = dt or 0.016

  local full    = ui.windowSize()
  local radius  = HUD_RADIUS * Scale
  local winSize = vec2(radius * 2.6, radius * 2.6)

  if not winPos then
    -- default bottom-right placement
    winPos = vec2(
      full.x - winSize.x - 30,
      full.y - winSize.y - 30
    )
  end

  ui.beginTransparentWindow('PN_D_Tachometer', winPos, winSize)
  windowMain(dt, winSize)
  ui.endTransparentWindow()
end
