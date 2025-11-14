--!SERVER_SCRIPT
-- Initial D-style Tachometer for CSP server HUD
-- Uses theme folders like themes/D6/ (background, digits, gear, units)

local STORAGE_THEME = ac.storage({ group = 'DTacho', name = 'Theme', value = 6 })
local STORAGE_UNIT  = ac.storage({ group = 'DTacho', name = 'UnitKmh', value = true })
local STORAGE_SIZE  = ac.storage({ group = 'DTacho', name = 'Scale', value = 1.0 })

local themeIndex = STORAGE_THEME.value or 6
local isKmh      = STORAGE_UNIT.value and true or false
local Size       = STORAGE_SIZE.value or 1.0

-- Where your theme folders live relative to this script
-- Adjust if you put them somewhere else
local THEME_ROOT = string.format('themes/D%d/', themeIndex)

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

-- Colors / constants
local KMH_TO_MPH    = 0.621371
local KM_TO_MI      = 0.621371
local HUD_RADIUS    = 150            -- base radius before scaling
local windowPos     = nil
local draggingHud   = false

local colors = {
  white  = rgbm(1, 1, 1, 1),
  bgDark = rgbm(0, 0, 0, 0.65),
  pillBg = rgbm(0, 0, 0, 0.5),
  pillBorder = rgbm(1, 1, 1, 0.8),
}

-- Cached car data
local rpm        = 0
local speedKmh   = 0
local gear       = 0
local odometerKm = 0

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

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

----------------------------------------------------------------------
-- DRAW: INITIAL-D STYLE TACH + SPEED
----------------------------------------------------------------------

local function drawInitialDTacho(car, center, radius, dt)
  -- Background gauge
  local bgSize = vec2(radius * 2.3, radius * 2.3)
  local bgPos  = center - bgSize / 2
  ui.setCursor(bgPos)
  ui.image(TEX_BACKGROUND, bgSize, colors.white, ui.ImageFit.Fit)

  -- RPM arc (inner ring)
  local maxRpm = car.rpmLimiter
  if maxRpm <= 0 then maxRpm = 8000 end
  local rpmFraction = math.clamp(rpm / (maxRpm * 1.05), 0, 1)

  local arcRadiusOuter = radius * 0.95
  local arcRadiusInner = radius * 0.78
  local startAngle     = math.rad(-210)
  local endAngle       = math.rad(  30)

  -- Background arc
  ui.pathClear()
  ui.pathArcTo(center, arcRadiusOuter, startAngle, endAngle, 64)
  ui.pathArcTo(center, arcRadiusInner, endAngle, startAngle, 64)
  ui.pathStroke(rgbm(0.1, 0.1, 0.1, 0.85), true, 1.0)

  -- Filled RPM arc
  local filledEnd = math.lerp(startAngle, endAngle, rpmFraction)
  local rpmColor  = rgbm(0.95, 0.95, 0.95, 1)
  if rpmFraction > 0.8 then
    rpmColor = rgbm(1.0, 0.9, 0.0, 1.0)
  end
  if rpmFraction > 0.95 then
    rpmColor = rgbm(1.0, 0.2, 0.2, 1.0)
  end

  ui.pathClear()
  ui.pathArcTo(center, arcRadiusOuter, startAngle, filledEnd, 64)
  ui.pathArcTo(center, arcRadiusInner, filledEnd, startAngle, 64)
  ui.pathStroke(rpmColor, true, 1.0)

  --------------------------------------------------------------------
  -- DIGITAL SPEED (Initial-D style digits)
  --------------------------------------------------------------------
  local spd       = getSpeed()
  local digits    = splitDigits(spd)
  local digitW    = radius * 0.23
  local digitH    = radius * 0.32
  local totalW    = (#digits) * digitW + (#digits - 1) * (radius * 0.03)
  local startX    = center.x - totalW / 2
  local y         = center.y + radius * 0.35

  for i = 1, #digits do
    local d = digits[i] or 0
    local pos = vec2(startX + (i - 1) * (digitW + radius * 0.03), y)
    ui.setCursor(pos)
    ui.image(speedDigitTex[d], vec2(digitW, digitH), colors.white, ui.ImageFit.Fit)
  end

  -- Unit icon (kmh/mph texture)
  local unitTex  = isKmh and TEX_KMH or TEX_MPH
  local unitSize = vec2(radius * 0.55, radius * 0.14)
  local unitPos  = vec2(center.x - unitSize.x / 2, y + digitH + radius * 0.04)
  ui.setCursor(unitPos)
  ui.image(unitTex, unitSize, colors.white, ui.ImageFit.Fit)

  --------------------------------------------------------------------
  -- GEAR (texture from theme)
  --------------------------------------------------------------------
  local gearIndex = gear
  if gearIndex < 0 then
    gearIndex = 0 -- reverse can reuse 0 or you can add dedicated texture
  end
  if gearIndex > 10 then gearIndex = 10 end

  local gearSize = vec2(radius * 0.6, radius * 0.35)
  local gearPos  = vec2(center.x - gearSize.x / 2, center.y - radius * 0.2)
  ui.setCursor(gearPos)
  ui.image(gearTex[gearIndex], gearSize, colors.white, ui.ImageFit.Fit)

  --------------------------------------------------------------------
  -- RPM numeric text & odometer
  --------------------------------------------------------------------
  local rpmText = string.format('%4d', math.floor(rpm))
  ui.dwriteDrawText(rpmText, radius * 0.16,
    vec2(center.x + radius * 0.55, center.y + radius * 0.05),
    colors.white)

  local dist = odometerKm
  if not isKmh then dist = dist * KM_TO_MI end
  local odoText = string.format('%06d %s',
    math.floor(dist),
    isKmh and 'km' or 'mi'
  )
  ui.dwriteDrawText(odoText, radius * 0.10,
    vec2(center.x - radius * 0.5, center.y + radius * 0.75),
    colors.white)
end

----------------------------------------------------------------------
-- WINDOW + INPUT: modern KMH/MPH pill + draggable handle
----------------------------------------------------------------------

local function windowMain(dt, winSize)
  local car = getCar()
  if not car then return end

  -- Mouse in local window coords
  local winPos     = ui.windowPos()
  local mp         = ui.mousePos()
  local localMouse = vec2(mp.x - winPos.x, mp.y - winPos.y)

  --------------------------------------------------------------------
  -- KMH / MPH pill switch (top-left)
  --------------------------------------------------------------------
  local togglePos  = vec2(10, 10)
  local toggleSize = vec2(90, 26)
  local toggleEnd  = vec2(togglePos.x + toggleSize.x, togglePos.y + toggleSize.y)
  local midX       = togglePos.x + toggleSize.x * 0.5

  -- pill bg & border
  ui.drawRectFilled(togglePos, toggleEnd, colors.pillBg)
  ui.drawRect(togglePos, toggleEnd, colors.pillBorder)

  local kmhMin = togglePos
  local kmhMax = vec2(midX, toggleEnd.y)
  local mphMin = vec2(midX, togglePos.y)
  local mphMax = toggleEnd

  if isKmh then
    ui.drawRectFilled(kmhMin, kmhMax, rgbm(0.0, 0.55, 0.2, 0.95))
  else
    ui.drawRectFilled(mphMin, mphMax, rgbm(0.1, 0.35, 0.9, 0.95))
  end

  ui.drawLine(vec2(midX, togglePos.y), vec2(midX, toggleEnd.y), rgbm(1,1,1,0.6), 1)

  ui.dwriteDrawText('KMH', 13, vec2(kmhMin.x + 8, kmhMin.y + 4), colors.white)
  ui.dwriteDrawText('MPH', 13, vec2(mphMin.x + 8, mphMin.y + 4), colors.white)

  if ui.mouseClicked(0) then
    if localMouse.x >= kmhMin.x and localMouse.x <= kmhMax.x
    and localMouse.y >= kmhMin.y and localMouse.y <= kmhMax.y then
      isKmh = true
      STORAGE_UNIT.value = true
    elseif localMouse.x >= mphMin.x and localMouse.x <= mphMax.x
    and localMouse.y >= mphMin.y and localMouse.y <= mphMax.y then
      isKmh = false
      STORAGE_UNIT.value = false
    end
  end

  --------------------------------------------------------------------
  -- Move handle (top-right)
  --------------------------------------------------------------------
  local dragSize = 22
  local dragPos  = vec2(winSize.x - dragSize - 10, 10)
  local dragMin  = dragPos
  local dragMax  = vec2(dragPos.x + dragSize, dragPos.y + dragSize)

  ui.drawRectFilled(dragMin, dragMax, colors.bgDark)
  ui.drawRect(dragMin, dragMax, rgbm(1,1,1,0.7))

  local cx = (dragMin.x + dragMax.x) * 0.5
  local cy = (dragMin.y + dragMax.y) * 0.5
  local arm = dragSize * 0.35

  ui.drawLine(vec2(cx - arm, cy), vec2(cx + arm, cy), rgbm(1,1,1,0.9), 1.4)
  ui.drawLine(vec2(cx, cy - arm), vec2(cx, cy + arm), rgbm(1,1,1,0.9), 1.4)

  ui.drawLine(vec2(cx + arm, cy), vec2(cx + arm-4, cy-3), rgbm(1,1,1,0.9), 1.2)
  ui.drawLine(vec2(cx + arm, cy), vec2(cx + arm-4, cy+3), rgbm(1,1,1,0.9), 1.2)
  ui.drawLine(vec2(cx - arm, cy), vec2(cx - arm+4, cy-3), rgbm(1,1,1,0.9), 1.2)
  ui.drawLine(vec2(cx - arm, cy), vec2(cx - arm+4, cy+3), rgbm(1,1,1,0.9), 1.2)
  ui.drawLine(vec2(cx, cy - arm), vec2(cx-3, cy - arm+4), rgbm(1,1,1,0.9), 1.2)
  ui.drawLine(vec2(cx, cy - arm), vec2(cx+3, cy - arm+4), rgbm(1,1,1,0.9), 1.2)
  ui.drawLine(vec2(cx, cy + arm), vec2(cx-3, cy + arm-4), rgbm(1,1,1,0.9), 1.2)
  ui.drawLine(vec2(cx, cy + arm), vec2(cx+3, cy + arm-4), rgbm(1,1,1,0.9), 1.2)

  local overDrag =
    localMouse.x >= dragMin.x and localMouse.x <= dragMax.x and
    localMouse.y >= dragMin.y and localMouse.y <= dragMax.y

  if overDrag and ui.mouseClicked(0) then
    draggingHud = true
  end
  if not ui.mouseDown(0) then
    draggingHud = false
  end
  if draggingHud and ui.mouseDown(0) then
    local d = ui.mouseDelta()
    if d.x ~= 0 or d.y ~= 0 then
      windowPos = vec2(windowPos.x + d.x, windowPos.y + d.y)
    end
  end

  --------------------------------------------------------------------
  -- Main gauge
  --------------------------------------------------------------------
  local center = vec2(winSize.x / 2, winSize.y / 2)
  drawInitialDTacho(car, center, HUD_RADIUS * Size, dt)
end

----------------------------------------------------------------------
-- SCRIPT LIFECYCLE
----------------------------------------------------------------------

function script.update(dt)
  local car = getCar()
  if not car then return end

  rpm        = car.rpm
  speedKmh   = car.speedKmh
  odometerKm = car.distanceDrivenTotalKm
  gear       = car.gear

  -- (We could add drift / pedal logic here later using more physics data.)
end

function script.drawUI(dt)
  local fullSize = ui.windowSize()
  local radius   = HUD_RADIUS * Size
  local winSize  = vec2(radius * 2.8, radius * 2.8)

  if not windowPos then
    windowPos = vec2(
      fullSize.x - winSize.x - 30,
      fullSize.y - winSize.y - 30
    )
  end

  ui.beginTransparentWindow('DTacho_InitialD', windowPos, winSize)
  windowMain(dt or 0.016, winSize)
  ui.endTransparentWindow()
end
