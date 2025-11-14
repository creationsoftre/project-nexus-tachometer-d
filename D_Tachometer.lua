--!SERVER_SCRIPT
-- Project Nexus - Initial D Tachometer (D3 theme)
-- Standalone HUD script, uses textures from:
--   themes/D3/background/background.png
--   themes/D3/speed_digits/speed_digits_0.png ... 9
--   themes/D3/speed_unit/kmh.png, mph.png
--   themes/D3/gears/gear_0.png ... gear_10.png

------------------------------------------------------------
-- Persistent settings (own namespace)
------------------------------------------------------------

local STORAGE_UNIT  = ac.storage({ group = 'PN_D_Tacho', name = 'UnitKmh', value = true })
local STORAGE_SCALE = ac.storage({ group = 'PN_D_Tacho', name = 'Scale',   value = 1.0 })

local isKmh  = STORAGE_UNIT.value and true or false
local Scale  = STORAGE_SCALE.value or 1.0

------------------------------------------------------------
-- Theme root (matches your GitHub repo structure)
------------------------------------------------------------

-- We hard-select D3 here because that’s the theme you pointed me to:
-- https://github.com/creationsoftre/project-nexus-tachometer-d/blob/main/themes/D3/background/background.png
local THEME_ID   = 3
local THEME_ROOT = string.format('themes/D%d/', THEME_ID)

local TEX_BACKGROUND = THEME_ROOT .. 'background/background.png'
local TEX_KMH        = THEME_ROOT .. 'speed_unit/kmh.png'
local TEX_MPH        = THEME_ROOT .. 'speed_unit/mph.png'

local speedDigitTex = {}
for i = 0, 9 do
  speedDigitTex[i] = string.format('%sspeed_digits/speed_digits_%d.png', THEME_ROOT, i)
end

local gearTex = {}
for i = 0, 10 do
  gearTex[i] = string.format('%sgears/gear_%d.png', THEME_ROOT, i)
end

------------------------------------------------------------
-- Constants & runtime state
------------------------------------------------------------

local KMH_TO_MPH    = 0.621371
local KM_TO_MI      = 0.621371
local HUD_RADIUS    = 150          -- base logical radius before scaling

local winPos        = nil          -- top-left of HUD window
local draggingHud   = false

local rpm        = 0
local speedKmh   = 0
local gear       = 0
local odometerKm = 0

local colors = {
  white      = rgbm(1, 1, 1, 1),
  pillBg     = rgbm(0, 0, 0, 0.55),
  pillBorder = rgbm(1, 1, 1, 0.8),
  handleBg   = rgbm(0, 0, 0, 0.65),
  handleBrd  = rgbm(1, 1, 1, 0.8),
}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

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

local function splitDigits(n)
  local s = tostring(math.floor(math.abs(n)))
  local t = {}
  for i = 1, #s do
    t[i] = tonumber(s:sub(i, i))
  end
  return t
end

------------------------------------------------------------
-- Initial-D style gauge drawing using D3 textures
------------------------------------------------------------

local function drawInitialDGauge(car, center, radius, dt)
  dt = dt or 0.016

  --------------------------------------------------------
  -- Background texture (full Initial D gauge)
  --------------------------------------------------------
  local bgSize = vec2(radius * 2.4, radius * 2.4)
  local bgPos  = center - bgSize / 2

  ui.setCursor(bgPos)
  ui.image(TEX_BACKGROUND, bgSize, colors.white, ui.ImageFit.Fit)

  --------------------------------------------------------
  -- RPM overlay arc (subtle, on top of background)
  --------------------------------------------------------
  local maxRpm = car.rpmLimiter
  if maxRpm <= 0 then maxRpm = 8000 end
  local rpmFraction = math.clamp(rpm / (maxRpm * 1.05), 0, 1)

  local arcRadiusOuter = radius * 0.96
  local arcRadiusInner = radius * 0.81
  local startAngle     = math.rad(-210)
  local endAngle       = math.rad(  30)

  -- Soft gray arc as base
  ui.pathClear()
  ui.pathArcTo(center, arcRadiusOuter, startAngle, endAngle, 64)
  ui.pathArcTo(center, arcRadiusInner, endAngle, startAngle, 64)
  ui.pathStroke(rgbm(0.12, 0.12, 0.12, 0.80), true, 1.0)

  -- Filled portion for current RPM
  local filledEnd = math.lerp(startAngle, endAngle, rpmFraction)
  local rpmColor  = rgbm(1.0, 1.0, 1.0, 0.98)
  if rpmFraction > 0.80 then
    rpmColor = rgbm(1.0, 0.9, 0.1, 1.0)
  end
  if rpmFraction > 0.95 then
    rpmColor = rgbm(1.0, 0.25, 0.25, 1.0)
  end

  ui.pathClear()
  ui.pathArcTo(center, arcRadiusOuter, startAngle, filledEnd, 64)
  ui.pathArcTo(center, arcRadiusInner, filledEnd, startAngle, 64)
  ui.pathStroke(rpmColor, true, 1.0)

  --------------------------------------------------------
  -- SPEED (Initial D digits)
  --------------------------------------------------------
  local spd    = getSpeed()
  local digits = splitDigits(spd)

  -- Positioning roughly matched to your D themes:
  local digitW = radius * 0.23
  local digitH = radius * 0.32
  local gap    = radius * 0.03

  local totalW = (#digits) * digitW + (#digits - 1) * gap
  local startX = center.x - totalW / 2
  local y      = center.y + radius * 0.30

  for i = 1, #digits do
    local d   = digits[i] or 0
    local pos = vec2(startX + (i - 1) * (digitW + gap), y)
    ui.setCursor(pos)
    ui.image(speedDigitTex[d], vec2(digitW, digitH), colors.white, ui.ImageFit.Fit)
  end

  --------------------------------------------------------
  -- Speed unit (km/h or mph) – texture from theme
  --------------------------------------------------------
  local unitTex  = isKmh and TEX_KMH or TEX_MPH
  local unitSize = vec2(radius * 0.55, radius * 0.14)
  local unitPos  = vec2(center.x - unitSize.x / 2, y + digitH + radius * 0.03)

  ui.setCursor(unitPos)
  ui.image(unitTex, unitSize, colors.white, ui.ImageFit.Fit)

  --------------------------------------------------------
  -- Gear (gear_0..10 textures)
  --------------------------------------------------------
  local gIdx = gear
  if gIdx < 0 then gIdx = 0 end
  if gIdx > 10 then gIdx = 10 end

  local gSize = vec2(radius * 0.60, radius * 0.35)
  local gPos  = vec2(center.x - gSize.x / 2, center.y - radius * 0.15)

  ui.setCursor(gPos)
  ui.image(gearTex[gIdx], gSize, colors.white, ui.ImageFit.Fit)

  --------------------------------------------------------
  -- Odometer text (bottom center, km or mi)
  --------------------------------------------------------
  local dist = odometerKm
  if not isKmh then dist = dist * KM_TO_MI end

  local odoText = string.format('%06d %s',
    math.floor(dist),
    isKmh and 'km' or 'mi'
  )

  ui.dwriteDrawText(
    odoText,
    radius * 0.10,
    vec2(center.x - radius * 0.35, center.y + radius * 0.80),
    colors.white
  )
end

------------------------------------------------------------
-- Window render + input (KMH/MPH pill + drag handle)
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
  -- Drag handle (top-right)
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
  -- Draw the themed gauge
  ------------------------------------------------------
  local center = vec2(winSize.x / 2, winSize.y / 2)
  drawInitialDGauge(car, center, HUD_RADIUS * Scale, dt)
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
  local winSize = vec2(radius * 2.8, radius * 2.8)

  if not winPos then
    winPos = vec2(
      full.x - winSize.x - 30,
      full.y - winSize.y - 30
    )
  end

  ui.beginTransparentWindow('PN_D_Tachometer', winPos, winSize)
  windowMain(dt, winSize)
  ui.endTransparentWindow()
end
