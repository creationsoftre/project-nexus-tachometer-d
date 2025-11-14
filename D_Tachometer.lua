--!SERVER_SCRIPT
-- Project Nexus - Initial D Style Tachometer HUD (vector-only, multi-theme, refined layout)

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
-- Themes (color + slight layout accent)
------------------------------------------------------------

local themes = {
  {
    id        = 1,
    name      = "4th Stage",
    arcBase   = rgbm(0.10, 0.04, 0.00, 0.95),
    arcFill   = rgbm(1.00, 0.70, 0.10, 1.00),
    arcRed    = rgbm(1.00, 0.25, 0.05, 1.00),
    bgInner   = rgbm(0.02, 0.02, 0.02, 0.90),
    bgOuter   = rgbm(0.00, 0.00, 0.00, 1.00),
    digital   = rgbm(1.00, 0.86, 0.50, 1.00),
    label     = rgbm(1.00, 0.75, 0.45, 1.00),
    chrome    = rgbm(0.9, 0.9, 0.9, 0.7),
    revWarn   = 0.88,
  },
  {
    id        = 2,
    name      = "D3 White",
    arcBase   = rgbm(0.12, 0.12, 0.12, 0.95),
    arcFill   = rgbm(0.95, 0.95, 0.95, 1.00),
    arcRed    = rgbm(1.00, 0.35, 0.35, 1.00),
    bgInner   = rgbm(0.02, 0.02, 0.02, 0.92),
    bgOuter   = rgbm(0.00, 0.00, 0.00, 1.00),
    digital   = rgbm(0.80, 1.00, 1.00, 1.00),
    label     = rgbm(0.90, 0.90, 0.90, 1.00),
    chrome    = rgbm(0.9, 0.9, 0.9, 0.7),
    revWarn   = 0.90,
  },
  {
    id        = 3,
    name      = "D4X Neo",
    arcBase   = rgbm(0.06, 0.06, 0.07, 0.95),
    arcFill   = rgbm(0.35, 0.90, 0.45, 1.00),
    arcRed    = rgbm(1.00, 0.35, 0.35, 1.00),
    bgInner   = rgbm(0.03, 0.03, 0.05, 0.95),
    bgOuter   = rgbm(0.00, 0.00, 0.00, 1.00),
    digital   = rgbm(0.96, 0.96, 0.96, 1.00),
    label     = rgbm(0.78, 0.88, 1.00, 1.00),
    chrome    = rgbm(0.8, 0.9, 1.0, 0.7),
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
-- Small rounded pill helper using paths (for modern buttons)
------------------------------------------------------------

local function drawPill(min, max, colFill, colBorder)
  local r = (max.y - min.y) / 2
  local centerLeft  = vec2(min.x + r, (min.y + max.y) * 0.5)
  local centerRight = vec2(max.x - r, (min.y + max.y) * 0.5)

  ui.pathClear()
  ui.pathArcTo(centerLeft,  r, math.rad(90),  math.rad(270), 16)
  ui.pathArcTo(centerRight, r, math.rad(-90), math.rad(90), 16)
  ui.pathFillConvex(colFill)

  ui.pathClear()
  ui.pathArcTo(centerLeft,  r, math.rad(90),  math.rad(270), 16)
  ui.pathArcTo(centerRight, r, math.rad(-90), math.rad(90), 16)
  ui.pathStroke(colBorder, true, 1.0)
end

------------------------------------------------------------
-- Gauge drawing (modern Initial D cluster)
------------------------------------------------------------

local function drawInitialDStyleGauge(car, center, radius, dt)
  local t      = getTheme()
  local maxRpm = car.rpmLimiter
  if maxRpm <= 0 then maxRpm = 8000 end
  local rpmFraction = clamp(rpm / (maxRpm * 1.05), 0, 1)

  --------------------------------------------------------
  -- Background disc with subtle “glass” gradient & glow
  --------------------------------------------------------
  local outerR = radius * 1.05
  local innerR = radius * 0.70

  -- Outer soft glow ring
  for i = 1, 3 do
    local r = outerR + i * 4
    local a = 0.11 - i * 0.03
    ui.drawCircleStroke(center, r, rgbm(t.arcFill.r, t.arcFill.g, t.arcFill.b, a), 2.0)
  end

  -- Outer dark ring
  ui.drawCircleFilled(center, outerR, t.bgOuter)
  -- Inner disc
  ui.drawCircleFilled(center, innerR, t.bgInner)

  --------------------------------------------------------
  -- Base arc (semi-circle) and filled RPM arc
  --------------------------------------------------------
  local startA = math.rad(-210)
  local endA   = math.rad(  30)
  local arcOuter = radius * 0.98
  local arcInner = radius * 0.78

  -- Base track
  ui.pathClear()
  ui.pathArcTo(center, arcOuter, startA, endA, 96)
  ui.pathArcTo(center, arcInner, endA, startA, 96)
  ui.pathStroke(t.arcBase, true, 1.0)

  -- Filled main section (up to warning fraction)
  local warnFrac   = t.revWarn or 0.90
  local currentEnd = lerp(startA, endA, rpmFraction)

  if rpmFraction > 0 then
    local fillEnd = lerp(startA, endA, math.min(rpmFraction, warnFrac))
    ui.pathClear()
    ui.pathArcTo(center, arcOuter, startA, fillEnd, 64)
    ui.pathArcTo(center, arcInner, fillEnd, startA, 64)
    ui.pathStroke(t.arcFill, true, 1.8)

    -- Redline
    if rpmFraction > warnFrac then
      local redStart = lerp(startA, endA, warnFrac)
      local redEnd   = currentEnd
      ui.pathClear()
      ui.pathArcTo(center, arcOuter, redStart, redEnd, 32)
      ui.pathArcTo(center, arcInner, redEnd, redStart, 32)
      ui.pathStroke(t.arcRed, true, 1.8)
    end
  end

  --------------------------------------------------------
  -- Tick marks and RPM numbers (0–maxK)
  --------------------------------------------------------
  local step = 1000
  local maxK = math.ceil(maxRpm / step)
  for k = 0, maxK do
    local frac = k / maxK
    local a    = lerp(startA, endA, frac)
    local r1   = arcOuter * 0.96
    local r2   = arcOuter * ((k % 2 == 0) and 1.06 or 1.03)

    local sx = center.x + math.cos(a) * r1
    local sy = center.y + math.sin(a) * r1
    local ex = center.x + math.cos(a) * r2
    local ey = center.y + math.sin(a) * r2

    ui.drawLine(
      vec2(sx, sy),
      vec2(ex, ey),
      rgbm(1, 1, 1, (k % 2 == 0) and 0.95 or 0.6),
      (k % 2 == 0) and 2.2 or 1.3
    )

    -- numeric labels for every 1000 rpm except 0
    if k > 0 then
      local labelR = arcOuter * 1.15
      local lx     = center.x + math.cos(a) * labelR
      local ly     = center.y + math.sin(a) * labelR
      local text   = tostring(k)
      local size   = radius * 0.11
      local w      = ui.measureDWriteText(text, size).x
      ui.dwriteDrawText(
        text,
        size,
        vec2(lx - w / 2, ly - size / 2),
        t.chrome
      )
    end
  end

  --------------------------------------------------------
  -- Cluster: digital speed & gear in “rounded square”
  --------------------------------------------------------
  local clusterW  = radius * 1.35
  local clusterH  = radius * 0.60
  local clusterY  = center.y + radius * 0.15
  local clusterMin = vec2(center.x - clusterW / 2, clusterY)
  local clusterMax = clusterMin + vec2(clusterW, clusterH)

  -- layered rects for gradient-ish look
  ui.drawRectFilled(clusterMin, clusterMax, rgbm(0, 0, 0, 0.92))
  ui.drawRectFilled(
    clusterMin + vec2(2, 2),
    clusterMax - vec2(2, 2),
    rgbm(0.10, 0.10, 0.12, 0.95)
  )
  ui.drawRect(clusterMin, clusterMax, rgbm(1, 1, 1, 0.25))

  -- left: SPEED
  local spd       = getSpeed()
  local speedText = string.format("%d", spd)
  local gearText  = getGearText()

  local speedSize = radius * 0.38
  local speedW    = ui.measureDWriteText(speedText, speedSize).x
  local speedPos  = vec2(
    clusterMin.x + clusterW * 0.28 - speedW / 2,
    clusterMin.y + clusterH * 0.18
  )

  ui.dwriteDrawText(speedText, speedSize, speedPos, t.digital)

  -- speed unit below
  local unitText  = isKmh and "km/h" or "mph"
  local unitSize  = radius * 0.14
  local unitW     = ui.measureDWriteText(unitText, unitSize).x
  local unitPos   = vec2(
    clusterMin.x + clusterW * 0.28 - unitW / 2,
    clusterMin.y + clusterH * 0.60
  )
  ui.dwriteDrawText(unitText, unitSize, unitPos, t.label)

  -- right: gear + MT
  local gearSize = radius * 0.40
  local gearW    = ui.measureDWriteText(gearText, gearSize).x
  local gearPos  = vec2(
    clusterMin.x + clusterW * 0.77 - gearW / 2,
    clusterMin.y + clusterH * 0.20
  )
  ui.dwriteDrawText(gearText, gearSize, gearPos, t.digital)

  local mtText  = "MT"
  local mtSize  = radius * 0.16
  local mtW     = ui.measureDWriteText(mtText, mtSize).x
  local mtPos   = vec2(
    clusterMin.x + clusterW * 0.77 - mtW / 2,
    clusterMin.y + clusterH * 0.63
  )
  ui.dwriteDrawText(mtText, mtSize, mtPos, t.label)

  --------------------------------------------------------
  -- Odometer just below cluster
  --------------------------------------------------------
  local dist = odometerKm
  if not isKmh then dist = dist * KM_TO_MI end

  local odoText = string.format("%06d %s",
    math.floor(dist),
    isKmh and "km" or "mi"
  )
  local odoSize = radius * 0.12
  local odoW    = ui.measureDWriteText(odoText, odoSize).x
  local odoPos  = vec2(center.x - odoW / 2, clusterMax.y + radius * 0.10)
  ui.dwriteDrawText(odoText, odoSize, odoPos, t.label)

  --------------------------------------------------------
  -- Rev warning “jewel”
  --------------------------------------------------------
  if rpmFraction >= (t.revWarn or 0.9) then
    local lightR = radius * 0.06
    local lx     = center.x + radius * 0.60
    local ly     = center.y - radius * 0.35
    ui.drawCircleFilled(vec2(lx, ly), lightR, t.arcRed)
    ui.drawCircleStroke(vec2(lx, ly), lightR + 2,
      rgbm(1, 1, 1, 0.9), 1.2)

    ui.dwriteDrawText("REV", radius * 0.12,
      vec2(lx - radius * 0.16, ly + lightR + 2),
      t.label)
  end

  --------------------------------------------------------
  -- ABS / TC indicators under odo (compact, centered)
  --------------------------------------------------------
  local boxW  = radius * 0.33
  local boxH  = radius * 0.13
  local gap   = radius * 0.08
  local baseY = odoPos.y + radius * 0.18

  local absMin = vec2(center.x - boxW - gap/2, baseY)
  local tcMin  = vec2(center.x + gap/2,       baseY)

  local function drawIndicator(minPos, label, active, colOn)
    local maxPos = minPos + vec2(boxW, boxH)
    ui.drawRectFilled(minPos, maxPos, rgbm(0, 0, 0, 0.90))
    ui.drawRectFilled(
      minPos + vec2(1, 1),
      maxPos - vec2(1, 1),
      rgbm(0.10, 0.10, 0.10, 0.95)
    )
    ui.drawRect(minPos, maxPos,
      rgbm(1, 1, 1, active and 0.9 or 0.4))

    local size = radius * 0.13
    local w    = ui.measureDWriteText(label, size).x
    local pos  = vec2(
      minPos.x + boxW / 2 - w / 2,
      minPos.y + boxH / 2 - size / 2
    )
    ui.dwriteDrawText(label, size, pos,
      active and colOn or t.label)
  end

  drawIndicator(absMin, "ABS", absOn, rgbm(1.0, 0.95, 0.35, 1.0))
  drawIndicator(tcMin,  "TC",  tcOn,  rgbm(0.4, 0.9, 1.0, 1.0))
end

------------------------------------------------------------
-- Window controls (unit/theme buttons, drag handle)
------------------------------------------------------------

local function windowMain(dt, winSize)
  local car = getCar()
  if not car then return end

  local t = getTheme()

  local winOrigin = ui.windowPos()
  local mouse     = ui.mousePos()
  local localPos  = vec2(mouse.x - winOrigin.x, mouse.y - winOrigin.y)

  ------------------------------------------------------
  -- KPH / MPH pill (top-left, rounded)
  ------------------------------------------------------
  local pillMin = vec2(16, 12)
  local pillMax = pillMin + vec2(120, 26)
  drawPill(pillMin, pillMax, rgbm(0, 0, 0, 0.9), rgbm(1,1,1,0.8))

  local midX = (pillMin.x + pillMax.x) * 0.5

  local kmhMin = pillMin
  local kmhMax = vec2(midX, pillMax.y)
  local mphMin = vec2(midX, pillMin.y)
  local mphMax = pillMax

  if isKmh then
    drawPill(kmhMin, kmhMax, rgbm(0.0, 0.60, 0.25, 1.0), rgbm(1,1,1,0.9))
  else
    drawPill(mphMin, mphMax, rgbm(0.10, 0.40, 0.95, 1.0), rgbm(1,1,1,0.9))
  end

  ui.dwriteDrawText("KPH", 13, vec2(kmhMin.x + 12, kmhMin.y + 4), rgbm(1,1,1,1))
  ui.dwriteDrawText("MPH", 13, vec2(mphMin.x + 12, mphMin.y + 4), rgbm(1,1,1,1))

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
  -- Theme selector pill (top-center)
  ------------------------------------------------------
  local themeW   = 130
  local themeH   = 24
  local themeMin = vec2(winSize.x / 2 - themeW / 2, 14)
  local themeMax = themeMin + vec2(themeW, themeH)

  drawPill(themeMin, themeMax, rgbm(0, 0, 0, 0.85), rgbm(1,1,1,0.7))

  local label = t.name
  local fSize = 13
  local w     = ui.measureDWriteText(label, fSize).x
  local pos   = vec2(
    themeMin.x + themeW / 2 - w / 2,
    themeMin.y + themeH / 2 - fSize / 2
  )
  ui.dwriteDrawText(label, fSize, pos, rgbm(1,1,1,1))

  if ui.mouseClicked(0) and
     localPos.x >= themeMin.x and localPos.x <= themeMax.x and
     localPos.y >= themeMin.y and localPos.y <= themeMax.y then
    themeIndex = themeIndex + 1
    if themeIndex > #themes then themeIndex = 1 end
    STORAGE_THEME.value = themeIndex
  end

  ------------------------------------------------------
  -- Drag handle (top-right) – rounded square with plus
  ------------------------------------------------------
  local dragSize = 24
  local dragMin  = vec2(winSize.x - dragSize - 16, 12)
  local dragMax  = dragMin + vec2(dragSize, dragSize)

  ui.drawRectFilled(dragMin, dragMax, rgbm(0, 0, 0, 0.9))
  ui.drawRectFilled(
    dragMin + vec2(1, 1),
    dragMax - vec2(1, 1),
    rgbm(0.12, 0.12, 0.12, 0.95)
  )
  ui.drawRect(dragMin, dragMax, rgbm(1,1,1,0.85))

  local cx  = (dragMin.x + dragMax.x) * 0.5
  local cy  = (dragMin.y + dragMax.y) * 0.5
  local arm = dragSize * 0.32

  ui.drawLine(vec2(cx - arm, cy), vec2(cx + arm, cy), rgbm(1,1,1,1), 1.4)
  ui.drawLine(vec2(cx, cy - arm), vec2(cx, cy + arm), rgbm(1,1,1,1), 1.4)

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
  -- Main gauge
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

  -- adjust these fields if your CSP build uses different names
  absOn      = car.absInAction or car.absEnabled or false
  tcOn       = car.tcInAction  or car.tcEnabled  or false
end

function script.drawUI(dt)
  local car = getCar()
  if not car then return end

  dt = dt or 0.016
  local full    = ui.windowSize()
  local radius  = HUD_RADIUS * Scale
  local winSize = vec2(radius * 3.0, radius * 3.0)

  if not winPos then
    -- default bottom-left like the arcade UIs
    winPos = vec2(60, full.y - winSize.y - 60)
  end

  ui.beginTransparentWindow("PN_InitialD_Tacho", winPos, winSize)
  windowMain(dt, winSize)
  ui.endTransparentWindow()
end
