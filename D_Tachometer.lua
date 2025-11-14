--!SERVER_SCRIPT

local KMH_TO_MPH      = 0.621371
local WINDOW_ID       = 'Nexus_DTachometer'
local WINDOW_SIZE     = vec2(560, 400)
local INITIAL_PADDING = vec2(30, 40)
local HEADER_HEIGHT   = 48

local STORAGE_UNIT = ac and ac.storage and ac.storage({ group = 'NexusDTacho', name = 'UnitIsKMH', value = true }) or nil

local hudPos
local draggingHud = false
local unitLocked = false
local isKmh = STORAGE_UNIT and STORAGE_UNIT.value or true

local function setUnit(value)
  isKmh = value
  if STORAGE_UNIT then STORAGE_UNIT.value = value end
end

local clamp = clamp or function(v, minV, maxV)
  if v < minV then return minV end
  if v > maxV then return maxV end
  return v
end

local function scalarLerp(a, b, t)
  a = a or 0
  b = b or 0
  t = t or 0
  return a + (b - a) * t
end

do
  local originalLerp = _G.lerp
  local function fallbackLerp(a, b, t)
    return scalarLerp(a, b, t)
  end
  if type(originalLerp) == "function" then
    _G.lerp = function(a, b, t)
      if a == nil or b == nil then
        return fallbackLerp(a, b, t)
      end
      return originalLerp(a, b, t or 0)
    end
  else
    _G.lerp = fallbackLerp
  end
end

local function trySimField(sim, field)
  local ok, value = pcall(function()
    return sim[field]
  end)
  if ok then return value end
end

local function updateUnitPreference()
  if unitLocked then return end
  if not ac or not ac.getSim then return end
  local sim = ac.getSim()
  if not sim then return end

  local km = trySimField(sim, 'isInKilometers')
  if km ~= nil then
    setUnit(km)
    return
  end

  local metric = trySimField(sim, 'isMetric')
  if metric ~= nil then
    setUnit(metric)
    return
  end

  local mph = trySimField(sim, 'isMPH')
  if mph ~= nil then
    setUnit(not mph)
  end
end

local function getCarSpeedKmh(car)
  if not car then return 0 end
  return car.speedKmh or car.speedKMH or ((car.speed or 0) * 3.6) or 0
end

local function formatGearText(gear)
  if not gear or gear == 0 then return 'N' end
  if gear < 0 then return 'R' end
  return tostring(gear)
end

local theme = {
  revWarn        = 0.80,
  bgOuter        = rgbm(0.02, 0.02, 0.02, 1.0),
  bgInner        = rgbm(0.01, 0.01, 0.01, 1.0),
  arcBase        = rgbm(0.95, 0.95, 0.95, 1.0),
  arcFill        = rgbm(0.95, 0.95, 0.95, 1.0),
  arcRed         = rgbm(1.00, 0.25, 0.20, 1.0),
  chrome         = rgbm(0.98, 0.98, 0.98, 1.0),
  label          = rgbm(0.95, 0.95, 0.95, 1.0),
  digital        = rgbm(0.15, 0.85, 0.95, 1.0),
  glassTop       = rgbm(0.20, 0.85, 0.95, 0.7),
  glassBottom    = rgbm(0.00, 0.25, 0.30, 0.95),
  glow           = rgbm(0.35, 0.60, 0.95, 0.5),
  shadow         = rgbm(0, 0, 0, 0.75),
  clusterStroke  = rgbm(0, 0, 0, 1.0)
}

local function getTheme()
  return theme
end

local function drawInitialDStyleGauge(car, center, radius, dt)
  local t      = getTheme()
  local maxRpm = car.rpmLimiter
  local rpm    = car.rpm or 0
  if maxRpm <= 0 then maxRpm = 8000 end
  local rpmFraction = clamp(rpm / (maxRpm * 1.05), 0, 1)

  --------------------------------------------------------
  -- Background disc with gradients and glow
  --------------------------------------------------------
  local outerR = radius * 1.05
  local innerR = radius * 0.72
  local dropOffset = vec2(0, radius * 0.14)
  ui.drawCircleFilled(center + dropOffset, outerR * 1.05, rgbm(0, 0, 0, 0.35))

  ui.drawCircleFilled(center, outerR, rgbm(0.01, 0.01, 0.01, 1.0))
  ui.drawCircleFilled(center, outerR * 0.98, rgbm(0.05, 0.05, 0.05, 1.0))
  ui.drawCircleFilled(center, outerR * 0.90, rgbm(0.08, 0.08, 0.08, 1.0))

  ui.pathClear()
  ui.pathArcTo(center, outerR * 0.96, math.rad(-150), math.rad(60), 64)
  ui.pathStroke(rgbm(1, 1, 1, 0.10), false, radius * 0.04)

  ui.drawCircle(center, outerR * 0.98, rgbm(0.6, 0.85, 1.0, 0.12), radius * 0.015)
  ui.drawCircle(center, outerR * 0.94, rgbm(0, 0, 0, 0.9), radius * 0.02)

  ui.drawCircleFilled(center, innerR * 1.03, rgbm(0, 0, 0, 0.65))
  ui.drawCircleFilled(center, innerR, rgbm(0.02, 0.02, 0.02, 1.0))
  ui.drawCircleFilled(center, innerR * 0.82, rgbm(0.0, 0.0, 0.0, 0.7))
  ui.drawCircle(center, innerR * 0.88, rgbm(1, 1, 1, 0.06), radius * 0.012)

  -- centre cap
  local hubR = radius * 0.12
  ui.drawCircleFilled(center, hubR * 1.3, rgbm(0, 0, 0, 0.8))
  ui.drawCircleFilled(center, hubR * 0.85, rgbm(0.05, 0.05, 0.05, 1.0))
  ui.drawCircle(center, hubR * 0.85, rgbm(0.8, 0.1, 0.1, 0.2), radius * 0.01)

  --------------------------------------------------------
  -- Main tachometer arc + red block overlay
  --------------------------------------------------------
  local startA   = math.rad(-210)
  local endA     = math.rad(  30)
  local arcOuter = radius * 0.98
  local arcInner = radius * 0.78

  -- base arc
  ui.pathClear()
  ui.pathArcTo(center, arcOuter, startA, endA, 128)
  ui.pathArcTo(center, arcInner, endA, startA, 128)
  ui.pathStroke(t.arcBase, true, 1.0)
  ui.pathClear()
  ui.pathArcTo(center, arcOuter * 1.02, startA, endA, 96)
  ui.pathStroke(t.glow, false, 4.5)

  -- filled arc up to warning
  local warnFrac = t.revWarn or 0.90
  if rpmFraction > 0.0 then
    local safeFrac = math.min(rpmFraction, warnFrac)
    local safeEndA = scalarLerp(startA, endA, safeFrac)

    ui.pathClear()
    ui.pathArcTo(center, arcOuter, startA, safeEndA, 96)
    ui.pathArcTo(center, arcInner, safeEndA, startA, 96)
    ui.pathStroke(t.arcFill, true, 1.8)

    -- red “blocks” section (like D3 overlay)
    if rpmFraction > warnFrac then
      local maxFrac  = math.min(rpmFraction, 1.0)
      local segCount = 7
      local span     = (1.0 - warnFrac) / segCount

      for i = 0, segCount - 1 do
        local segStartFrac = warnFrac + i * span
        if segStartFrac >= maxFrac then break end

        local segEndFrac = math.min(segStartFrac + span * 0.80, maxFrac)
        local segStartA  = scalarLerp(startA, endA, segStartFrac)
        local segEndA    = scalarLerp(startA, endA, segEndFrac)

        if segEndA > segStartA then
          ui.pathClear()
          ui.pathArcTo(center, arcOuter, segStartA, segEndA, 16)
          ui.pathArcTo(center, arcInner, segEndA, segStartA, 16)
          ui.pathStroke(t.arcRed, true, 2.2)
        end
      end
    end
  end

  --------------------------------------------------------
  -- Tick marks & RPM numbers (0-10 white)
  --------------------------------------------------------
  local maxK = 10
  for k = 0, maxK do
    local frac = k / maxK
    local a    = scalarLerp(startA, endA, frac)
    local r1   = arcOuter * 0.94
    local r2   = arcOuter * ((k % 1 == 0) and 1.08 or 1.03)

    local sx = center.x + math.cos(a) * r1
    local sy = center.y + math.sin(a) * r1
    local ex = center.x + math.cos(a) * r2
    local ey = center.y + math.sin(a) * r2

    ui.drawLine(
      vec2(sx, sy),
      vec2(ex, ey),
      rgbm(1, 1, 1, 0.95),
      (k % 1 == 0) and 2.2 or 1.2
    )

    local labelR = arcOuter * 1.12
    local lx     = center.x + math.cos(a) * labelR
    local ly     = center.y + math.sin(a) * labelR
    local text   = tostring(k)
    local size   = radius * 0.11
    local w      = ui.measureDWriteText(text, size).x

    ui.dwriteDrawText(
      text,
      size,
      vec2(lx - w / 2, ly - size / 2),
      rgbm(1, 1, 1, 0.95)
    )
  end

  --------------------------------------------------------
  -- RPM needle (long thin triangle)
  --------------------------------------------------------
  if rpmFraction > 0 then
    local angle = scalarLerp(startA, endA, rpmFraction)
    local dirX = math.cos(angle)
    local dirY = math.sin(angle)
    local px   = -dirY
    local py   =  dirX

    local tailR = -radius * 0.04
    local tipR  = arcOuter * 1.06
    local halfW = radius * 0.03

    local tip   = vec2(center.x + dirX * tipR, center.y + dirY * tipR)
    local base  = vec2(center.x + dirX * tailR, center.y + dirY * tailR)
    local left  = vec2(base.x + px * halfW, base.y + py * halfW)
    local right = vec2(base.x - px * halfW, base.y - py * halfW)

    ui.pathClear()
    ui.pathLineTo(left)
    ui.pathLineTo(tip)
    ui.pathLineTo(right)
    ui.pathFillConvex(rgbm(1.0, 0.2, 0.1, 1.0))

    ui.drawLine(base, tip, rgbm(1.0, 0.25, 0.15, 0.7), radius * 0.01)
  end


  --------------------------------------------------------
  -- "x1000r/min" label
  --------------------------------------------------------
  local rpmLabel = "x1000r/min"
  local rpmSize  = radius * 0.13
  local rpmWidth = ui.measureDWriteText(rpmLabel, rpmSize).x
  local rpmPos   = vec2(center.x - rpmWidth / 2, center.y - radius * 0.55)
  ui.dwriteDrawText(rpmLabel, rpmSize, rpmPos, rgbm(0.9, 0.95, 1.0, 0.9))

  --------------------------------------------------------
  -- Digital speed / gear cluster
  --------------------------------------------------------
  local function drawRoundedRectFilled(minPt, maxPt, radius, color)
    local r = math.max(0, math.min(radius, (maxPt.x - minPt.x) * 0.5, (maxPt.y - minPt.y) * 0.5))
    ui.pathClear()
    ui.pathArcTo(vec2(maxPt.x - r, maxPt.y - r), r, 0, math.pi / 2, 16)
    ui.pathArcTo(vec2(minPt.x + r, maxPt.y - r), r, math.pi / 2, math.pi, 16)
    ui.pathArcTo(vec2(minPt.x + r, minPt.y + r), r, math.pi, math.pi * 1.5, 16)
    ui.pathArcTo(vec2(maxPt.x - r, minPt.y + r), r, math.pi * 1.5, math.pi * 2, 16)
    ui.pathFillConvex(color)
  end

  local function strokeRoundedRect(minPt, maxPt, radius, color, thickness)
    local r = math.max(0, math.min(radius, (maxPt.x - minPt.x) * 0.5, (maxPt.y - minPt.y) * 0.5))
    ui.pathClear()
    ui.pathArcTo(vec2(maxPt.x - r, maxPt.y - r), r, 0, math.pi / 2, 16)
    ui.pathArcTo(vec2(minPt.x + r, maxPt.y - r), r, math.pi / 2, math.pi, 16)
    ui.pathArcTo(vec2(minPt.x + r, minPt.y + r), r, math.pi, math.pi * 1.5, 16)
    ui.pathArcTo(vec2(maxPt.x - r, minPt.y + r), r, math.pi * 1.5, math.pi * 2, 16)
    ui.pathStroke(color, true, thickness)
  end

  local function drawGloss(minPt, maxPt, color)
    ui.drawRectFilledMultiColor(
      minPt, maxPt,
      color,
      color,
      rgbm(color.r, color.g, color.b, 0),
      rgbm(color.r, color.g, color.b, 0)
    )
  end

  local totalWidth   = radius * 1.20
  local mainWidth    = totalWidth * 0.76
  local gearWidth    = totalWidth - mainWidth
  local gap          = radius * 0.02
  local panelHeight  = radius * 0.24
  local baseMinX     = center.x - (totalWidth + gap) * 0.5
  local panelY       = center.y + radius * 0.40

  local lcdMin = vec2(baseMinX, panelY)
  local lcdMax = vec2(lcdMin.x + mainWidth, panelY + panelHeight)
  drawRoundedRectFilled(lcdMin, lcdMax, panelHeight * 0.42, rgbm(0.04, 0.15, 0.17, 0.95))
  drawRoundedRectFilled(lcdMin + vec2(panelHeight * 0.04, panelHeight * 0.04), lcdMax - vec2(panelHeight * 0.04, panelHeight * 0.04), panelHeight * 0.34, rgbm(0.10, 0.65, 0.70, 0.9))
  strokeRoundedRect(lcdMin, lcdMax, panelHeight * 0.42, rgbm(0, 0, 0, 1.0), 2.4)
  drawGloss(
    vec2(lcdMin.x + panelHeight * 0.12, lcdMin.y + panelHeight * 0.07),
    vec2(lcdMax.x - panelHeight * 0.12, lcdMin.y + panelHeight * 0.18),
    rgbm(1, 1, 1, 0.12)
  )

  local baseSpeed   = getCarSpeedKmh(car)
  local displaySpd  = math.abs(isKmh and baseSpeed or baseSpeed * KMH_TO_MPH)
  local speedText   = string.format("%03d", math.floor(math.max(displaySpd, 0)))
  local rawGear     = car.gear or 0
  local gearText    = formatGearText(rawGear)
  local transLabel  = (car.transmission and car.transmission.isAutomatic) and "AT" or "MT"

  local speedSize = panelHeight * 0.60
  local speedW    = ui.measureDWriteText(speedText, speedSize).x
  local speedPos  = vec2(
    lcdMin.x + (mainWidth - speedW) * 0.5,
    lcdMin.y + panelHeight * 0.12
  )
  ui.dwriteDrawText(speedText, speedSize, speedPos, rgbm(0.90, 0.98, 1.0, 0.95))

  local unitText  = isKmh and "km/h" or "mph"
  local unitSize  = panelHeight * 0.35
  local unitW     = ui.measureDWriteText(unitText, unitSize).x
  local unitPos   = vec2(
    lcdMin.x + (mainWidth - unitW) * 0.5,
    lcdMax.y - unitSize * 1.2
  )
  ui.dwriteDrawText(unitText, unitSize, unitPos, rgbm(0.92, 0.98, 1.0, 0.95))

  local gearBoxMin = vec2(lcdMax.x + gap, lcdMin.y)
  local gearBoxMax = vec2(gearBoxMin.x + gearWidth - gap, lcdMin.y + panelHeight)
  local gearRectWidth = gearBoxMax.x - gearBoxMin.x

  drawRoundedRectFilled(gearBoxMin, gearBoxMax, panelHeight * 0.38, rgbm(0.04, 0.15, 0.17, 0.95))
  drawRoundedRectFilled(gearBoxMin + vec2(panelHeight * 0.035, panelHeight * 0.035),
                        gearBoxMax - vec2(panelHeight * 0.035, panelHeight * 0.035),
                        panelHeight * 0.30,
                        rgbm(0.13, 0.70, 0.75, 0.9))
  strokeRoundedRect(gearBoxMin, gearBoxMax, panelHeight * 0.38, rgbm(0, 0, 0, 1.0), 2.0)
  drawGloss(
    vec2(gearBoxMin.x + panelHeight * 0.08, gearBoxMin.y + panelHeight * 0.07),
    vec2(gearBoxMax.x - panelHeight * 0.08, gearBoxMin.y + panelHeight * 0.18),
    rgbm(1, 1, 1, 0.12)
  )

  local gearSize = panelHeight * 0.48
  local gearW    = ui.measureDWriteText(gearText, gearSize).x
  local gearPos  = vec2(
    gearBoxMin.x + (gearRectWidth - gearW) * 0.5,
    gearBoxMin.y + panelHeight * 0.42
  )
  ui.dwriteDrawText(gearText, gearSize, gearPos, rgbm(0.92, 0.98, 1.0, 0.95))

  local mtText = transLabel
  local mtSize = panelHeight * 0.32
  local mtW    = ui.measureDWriteText(mtText, mtSize).x
  local mtPos  = vec2(
    gearBoxMin.x + (gearRectWidth - mtW) * 0.5,
    gearBoxMin.y + panelHeight * 0.08
  )
  ui.dwriteDrawText(mtText, mtSize, mtPos, rgbm(0.92, 0.98, 1.0, 0.9))

  --------------------------------------------------------
  -- Accel / Brake semi gauge hugging main dial (optional)
  --------------------------------------------------------
  do
    local showPedals = false
    if showPedals then
      local accel = clamp(car.gas or car.throttle or 0.0, 0.0, 1.0)
      local brake = clamp(car.brake or 0.0, 0.0, 1.0)
      local pedalCenter = vec2(center.x + radius * 0.84, center.y + radius * 0.02)
      local semiOuter   = radius * 0.92
      local semiInner   = semiOuter - radius * 0.18
      local halfStart   = math.rad(-105)
      local halfEnd     = math.rad( 105)

      local function lerpColor(colA, colB, amount)
        return rgbm(
          scalarLerp(colA.r, colB.r, amount),
          scalarLerp(colA.g, colB.g, amount),
          scalarLerp(colA.b, colB.b, amount),
          scalarLerp(colA.a, colB.a, amount)
        )
      end

      local function fillSemi(startA, endA, value, c1, c2)
        if value <= 0 then return end
        local span = endA - startA
        local finish = startA + span * value
        ui.pathClear()
        ui.pathArcTo(pedalCenter, semiOuter, startA, finish, 48)
        ui.pathArcTo(pedalCenter, semiInner, finish, startA, 48)
        ui.pathFillConvex(lerpColor(c1, c2, value))
      end

      ui.pathClear()
      ui.pathArcTo(pedalCenter, semiOuter, halfStart, halfEnd, 64)
      ui.pathArcTo(pedalCenter, semiInner, halfEnd, halfStart, 64)
      ui.pathFillConvex(rgbm(0.02, 0.04, 0.08, 0.65))
      ui.drawCircle(pedalCenter, semiOuter, rgbm(0.45, 0.75, 1.0, 0.32), 1.5, 64)

      fillSemi(halfStart, 0, accel, rgbm(0.15, 0.65, 1.0, 0.35), rgbm(0.35, 0.95, 1.0, 0.95))
      fillSemi(0, halfEnd, brake, rgbm(0.8, 0.1, 0.1, 0.35), rgbm(1.0, 0.35, 0.2, 0.95))

      local pSize = radius * 0.11
      ui.dwriteDrawText("ACCEL", pSize,
        vec2(pedalCenter.x + radius * 0.20, pedalCenter.y - radius * 0.30),
        rgbm(0.85, 0.96, 1.0, 0.95))
      ui.dwriteDrawText("BRAKE", pSize,
        vec2(pedalCenter.x + radius * 0.20, pedalCenter.y + radius * 0.20),
        rgbm(0.95, 0.85, 0.85, 0.95))
    end
  end
end

local function ensureHudPosition(winSize)
  if hudPos then return end
  local view = ui.windowSize()
  hudPos = vec2(
    view.x - winSize.x - INITIAL_PADDING.x,
    view.y - winSize.y - INITIAL_PADDING.y
  )
end

local function drawGaugeWindow(dt, winSize)
  dt = dt or 0.016
  local sim = ac and ac.getSim and ac.getSim()
  if not sim then
    ui.dwriteDrawText("Waiting for sim...", 16, vec2(16, 20), rgbm(1, 0.4, 0.4, 1))
    return
  end

  local car = ac.getCar(sim.focusedCar)
  if not car then
    ui.dwriteDrawText("No car data", 16, vec2(16, 20), rgbm(1, 0.4, 0.4, 1))
    return
  end

  local winPos     = ui.windowPos()
  local mousePos   = ui.mousePos()
  local localMouse = vec2(mousePos.x - winPos.x, mousePos.y - winPos.y)

  -- toggle pill
  local togglePos  = vec2(16, 10)
  local toggleSize = vec2(120, 28)
  local toggleEnd  = togglePos + toggleSize
  local toggleMidX = togglePos.x + toggleSize.x * 0.5

  ui.drawRectFilled(togglePos, toggleEnd, rgbm(0, 0, 0, 0.45))
  ui.drawRect(togglePos, toggleEnd, rgbm(1, 1, 1, 0.2))

  local kmhRectMin = togglePos
  local kmhRectMax = vec2(toggleMidX, toggleEnd.y)
  local mphRectMin = vec2(toggleMidX, togglePos.y)
  local mphRectMax = toggleEnd

  if isKmh then
    ui.drawRectFilled(kmhRectMin, kmhRectMax, rgbm(0.05, 0.55, 0.95, 0.85))
  else
    ui.drawRectFilled(mphRectMin, mphRectMax, rgbm(0.05, 0.35, 0.95, 0.85))
  end

  ui.dwriteDrawText("KMH", 14, vec2(kmhRectMin.x + 10, kmhRectMin.y + 5), rgbm(1, 1, 1, 0.9))
  ui.dwriteDrawText("MPH", 14, vec2(mphRectMin.x + 10, mphRectMin.y + 5), rgbm(1, 1, 1, 0.9))

  if ui.mouseClicked(0) then
    if localMouse.x >= kmhRectMin.x and localMouse.x <= kmhRectMax.x
      and localMouse.y >= kmhRectMin.y and localMouse.y <= kmhRectMax.y then
      unitLocked = true
      setUnit(true)
    elseif localMouse.x >= mphRectMin.x and localMouse.x <= mphRectMax.x
      and localMouse.y >= mphRectMin.y and localMouse.y <= mphRectMax.y then
      unitLocked = true
      setUnit(false)
    end
  end

  -- drag handle top right
  local dragSize = 26
  local dragMin  = vec2(winSize.x - dragSize - 16, 10)
  local dragMax  = dragMin + vec2(dragSize, dragSize)
  ui.drawRectFilled(dragMin, dragMax, rgbm(0, 0, 0, 0.4))
  ui.drawRect(dragMin, dragMax, rgbm(1, 1, 1, 0.2))

  local dragCenter = vec2((dragMin.x + dragMax.x) * 0.5, (dragMin.y + dragMax.y) * 0.5)
  local arm = dragSize * 0.35
  ui.drawLine(vec2(dragCenter.x - arm, dragCenter.y), vec2(dragCenter.x + arm, dragCenter.y), rgbm(1,1,1,0.75), 1.3)
  ui.drawLine(vec2(dragCenter.x, dragCenter.y - arm), vec2(dragCenter.x, dragCenter.y + arm), rgbm(1,1,1,0.75), 1.3)

  local overDrag =
    localMouse.x >= dragMin.x and localMouse.x <= dragMax.x and
    localMouse.y >= dragMin.y and localMouse.y <= dragMax.y

  if overDrag and ui.mouseClicked(0) then
    draggingHud = true
  end
  if not ui.mouseDown(0) then
    draggingHud = false
  end
  if draggingHud and ui.mouseDown(0) and hudPos then
    local delta = ui.mouseDelta()
    hudPos = vec2(hudPos.x + delta.x, hudPos.y + delta.y)
  end

  local radius = math.min(winSize.x * 0.48, (winSize.y - HEADER_HEIGHT) * 0.52)
  local center = vec2(winSize.x * 0.5, HEADER_HEIGHT + radius * 1.02)
  drawInitialDStyleGauge(car, center, radius, dt)
end

function script.update(dt)
  -- Reserved for future logic (input, state caching, etc.)
end

function script.drawUI(dt)
  updateUnitPreference()
  local winSize = WINDOW_SIZE
  ensureHudPosition(winSize)

  ui.beginTransparentWindow(WINDOW_ID, hudPos, winSize)
    drawGaugeWindow(dt, winSize)
  ui.endTransparentWindow()
end

