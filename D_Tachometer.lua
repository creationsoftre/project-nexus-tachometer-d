--!SERVER_SCRIPT
-- Initial D-style Tachometer HUD (NEW RESOURCE)
-- Does NOT touch project-nexus-tachometer code.

-- Persistent settings (separate group)
local STORAGE_THEME = ac.storage({ group = 'InitialD_Tacho', name = 'Theme', value = 6 })
local STORAGE_UNIT  = ac.storage({ group = 'InitialD_Tacho', name = 'UnitKmh', value = true })
local STORAGE_SCALE = ac.storage({ group = 'InitialD_Tacho', name = 'Scale',   value = 1.0 })

local themeIndex = STORAGE_THEME.value or 6
local isKmh      = STORAGE_UNIT.value and true or false
local Scale      = STORAGE_SCALE.value or 1.0

-- Adjust this root to wherever you put your theme folders
local THEME_ROOT = string.format('initiald_tachometer/themes/D%d/', themeIndex)

-- Textures (match your Python theme folder structure)
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

-- Constants
local KMH_TO_MPH = 0.621371
local KM_TO_MI   = 0.621371
local HUD_RADIUS_BASE = 150

local winPos      = nil     -- window top-left
local draggingHud = false

local colors = {
  white      = rgbm(1, 1, 1, 1),
  pillBg     = rgbm(0, 0, 0, 0.5),
  pillBorder = rgbm(1, 1, 1, 0.8),
  handleBg   = rgbm(0, 0, 0, 0.65),
  handleBrd  = rgbm(1, 1, 1, 0.7),
}

-- Runtime car data cache
local rpm        = 0
local speedKmh   = 0
local gear       = 0
local odometerKm = 0

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
  if not isKmh then
    v = v * KMH_TO_MPH
  end
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
-- Main gauge drawing (Initial D style)
------------------------------------------------------------

local function drawInitialDGauge(car, center, radius, dt)
  -- Background
  local bgSize = vec2(radius * 2.3, radius * 2.3)
  local bgPos  = center - bgSize / 2
  ui.setCursor(bgPos)
  ui.image(TEX_BACKGROUND, bgSize, colors.white, ui.ImageFit.Fit)

  -- RPM arc
  local maxRpm = car.rpmLimiter
  if maxRpm <= 0 then maxRpm = 8000 end
  local rpmFrac = math.clamp(rpm / (maxRpm * 1.05), 0, 1)

  local outerR = radius * 0.96
  local innerR = radius * 0.80
  local startA = math.rad(-210)
  local endA   = math.rad(  30)

  -- Background arc
  ui.pathClear()
  ui.pathArcTo(center, outerR, startA, endA, 64)
  ui.pathArcTo(center, innerR, endA, startA, 64)
  ui.pathStroke(rgbm(0.1, 0.1, 0.1, 0.85), true, 1.0)

  -- Filled RPM arc
  local filledEnd = math.lerp(startA, endA, rpmFrac)
  local rpmColor  = rgbm(0.95, 0.95, 0.95, 1)
  if rpmFrac > 0.8 then rpmColor = rgbm(1.0, 0.9, 0.0, 1.0) end
  if rpmFrac > 0.95 then rpmColor = rgbm(1.0, 0.2, 0.2, 1.0) end

  ui.pathClear()
  ui.pathArcTo(center, outerR, startA, filledEnd, 64)
  ui.pathArcTo(center, innerR, filledEnd, startA, 64)
  ui.pathStroke(rpmColor, true, 1.0)

  --------------------------------------------------------
  -- Digital speed (texture digits)
  --------------------------------------------------------
  local spd       = getSpeed()
  local digits    = splitDigits(spd)
  local digitW    = radius * 0.23
  local digitH    = radius * 0.32
  local gap       = radius * 0.03
  local totalW    = (#digits) * digitW + (#digits - 1) * gap
  local startX    = center.x - totalW / 2
  local y         = center.y + radius * 0.35

  for i = 1, #digits do
    local d = digits[i] or 0
    local pos = vec2(startX + (i - 1) * (digitW + gap), y)
    ui.setCursor(pos)
    ui.image(speedDigitTex[d], vec2(digitW, digitH), colors.white, ui.ImageFit.Fit)
  end

  -- Unit texture (kmh / mph)
  local unitTex  = isKmh and TEX_KMH or TEX_MPH
  local unitSize = vec2(radius * 0.55, radius * 0.14)
  local unitPos  = vec2(center.x - unitSize.x / 2, y + digitH + radius * 0.04)
  ui.setCursor(unitPos)
  ui.image(unitTex, unitSize, colors.white, ui.ImageFit.Fit)

  --------------------------------------------------------
  -- Gear texture
  --------------------------------------------------------
  local gIdx = gear
  if gIdx < 0 then gIdx = 0 end
  if gIdx > 10 then gIdx = 10 end

  local gSize = vec2(radius * 0.6, radius * 0.35)
  local gPos  = vec2(center.x - gSize.x / 2, center.y - radius * 0.2)
  ui.setCursor(gPos)
  ui.image(gearTex[gIdx], gSize, colors.white, ui.ImageFit.Fit)

  --------------------------------------------------------
  -- RPM numeric / Odometer text
  --------------------------------------------------------
  local rpmText = string.format('%4d', math.floor(rpm))
  ui.dwriteDrawText(
    rpmText,
    radius * 0.16,
    vec2(center.x + radius * 0.55, center.y + radius * 0.05),
    colors.white
  )

  local dist = odometerKm
  if not isKmh then dist = dist * KM_TO_MI end
  local odoText = string.format('%06d %s', math.floor(dist), isKmh and 'km' or 'mi')
  ui.dwriteDrawText(
    odoText,
    radius * 0.10,
    vec2(center.x - radius * 0.5, center.y + radius * 0.75),
    colors.white
  )
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
    ui.drawRectFilled(mphMin, mphMax, rgbm(0.1, 0.35, 0.9, 0.95))
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

  local cx = (dragMin.x + dragMax.x) * 0.5
  local cy = (dragMin.y + dragMax.y) * 0.5
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
  -- Draw main Initial D gauge
  ------------------------------------------------------
  local center = vec2(winSize.x / 2, winSize.y / 2)
  drawInitialDGauge(car, center, HUD_RADIUS_BASE * Scale, dt)
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
  local radius  = HUD_RADIUS_BASE * Scale
  local winSize = vec2(radius * 2.8, radius * 2.8)

  if not winPos then
    winPos = vec2(
      full.x - winSize.x - 30,
      full.y - winSize.y - 30
    )
  end

  ui.beginTransparentWindow('InitialD_Tachometer', winPos, winSize)
  windowMain(dt, winSize)
  ui.endTransparentWindow()
end
