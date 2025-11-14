--!SERVER_SCRIPT

local KMH_TO_MPH      = 0.621371
local WINDOW_ID       = 'Nexus_DTachometer'
local WINDOW_SIZE     = vec2(540, 360)
local INITIAL_PADDING = vec2(30, 40)

local hudPos

local clamp = clamp or function(v, minV, maxV)
  if v < minV then return minV end
  if v > maxV then return maxV end
  return v
end

local lerp = lerp or function(a, b, t)
  return a + (b - a) * t
end

local isKmh = true

local function trySimField(sim, field)
  local ok, value = pcall(function()
    return sim[field]
  end)
  if ok then return value end
end

local function updateUnitPreference()
  if not ac or not ac.getSim then return end
  local sim = ac.getSim()
  if not sim then return end

  local km = trySimField(sim, 'isInKilometers')
  if km ~= nil then
    isKmh = km
    return
  end

  local metric = trySimField(sim, 'isMetric')
  if metric ~= nil then
    isKmh = metric
    return
  end

  local mph = trySimField(sim, 'isMPH')
  if mph ~= nil then
    isKmh = not mph
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
  revWarn        = 0.88,
  bgOuter        = rgbm(0.08, 0.10, 0.15, 0.90),
  bgInner        = rgbm(0.02, 0.04, 0.07, 0.92),
  arcBase        = rgbm(0.18, 0.21, 0.26, 0.95),
  arcFill        = rgbm(0.12, 0.65, 1.00, 0.95),
  arcRed         = rgbm(1.00, 0.35, 0.30, 1.0),
  chrome         = rgbm(0.95, 0.96, 1.00, 1.0),
  label          = rgbm(0.84, 0.88, 0.95, 0.95),
  digital        = rgbm(0.55, 1.00, 1.00, 1.0),
  glassTop       = rgbm(0.05, 0.40, 0.55, 0.55),
  glassBottom    = rgbm(0.00, 0.15, 0.25, 0.85),
  glow           = rgbm(0.05, 0.65, 0.95, 0.55),
  shadow         = rgbm(0, 0, 0, 0.55),
  clusterStroke  = rgbm(0.65, 0.95, 1.0, 0.9)
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
  -- Background disc with shadow + subtle gradient
  --------------------------------------------------------
  local outerR = radius * 1.05
  local innerR = radius * 0.72
  local dropShadowOffset = vec2(0, radius * 0.15)

  ui.drawCircleFilled(center + dropShadowOffset, radius * 1.18, rgbm(0, 0, 0, 0.35))
  ui.drawCircleFilled(center, radius * 1.12, rgbm(0, 0, 0, 0.25))

  ui.drawCircleFilled(center, outerR, t.bgOuter)
  ui.drawCircleFilled(center, outerR * 0.94, rgbm(t.bgOuter.r, t.bgOuter.g, t.bgOuter.b, 0.65))

  ui.drawCircleFilled(center, innerR * 1.05, rgbm(0, 0, 0, 0.35))
  ui.drawCircleFilled(center, innerR, t.bgInner)
  ui.drawCircleFilled(center, innerR * 0.85, rgbm(0.01, 0.01, 0.02, 0.65))

  -- subtle outer ring
  ui.drawCircle(center, outerR, rgbm(0.15, 0.20, 0.28, 0.8), 2.0)
  ui.drawCircle(center, outerR * 0.98, rgbm(0.8, 0.9, 1.0, 0.08), 1.4)

  -- centre cap
  local hubR = radius * 0.10
  ui.drawCircleFilled(center, hubR * 2.4, rgbm(0, 0, 0, 0.35))
  ui.drawCircleFilled(center, hubR, rgbm(0.08, 0.08, 0.10, 0.9))
  ui.drawCircleFilled(center, hubR * 0.65, rgbm(0.05, 0.05, 0.07, 1.0))
  ui.drawCircle(center, hubR, rgbm(0.35, 0.35, 0.4, 0.6), 2.2)

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
    local safeEndA = lerp(startA, endA, safeFrac)

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
        local segStartA  = lerp(startA, endA, segStartFrac)
        local segEndA    = lerp(startA, endA, segEndFrac)

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
  -- Tick marks & RPM numbers
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
      (k % 2 == 0) and 2.0 or 1.2
    )

    if k > 0 then
      local labelR = arcOuter * 1.14
      local lx     = center.x + math.cos(a) * labelR
      local ly     = center.y + math.sin(a) * labelR
      local text   = tostring(k)
      local size   = radius * 0.10
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
  -- RPM needle (bar with soft glow)
  --------------------------------------------------------
  if rpmFraction > 0 then
    -- angle for current RPM (same sweep as arc)
    local angle = lerp(startA, endA, rpmFraction)

    local dirX = math.cos(angle)
    local dirY = math.sin(angle)
    local px   = -dirY   -- perpendicular (for width)
    local py   =  dirX

    -- from just outside the hub to near arc outer edge
    local innerR = radius * 0.16
    local outerR = arcOuter * 0.98

    -- outer “glow” bar
    local outerHalfW = radius * 0.055
    local ix = center.x + dirX * innerR
    local iy = center.y + dirY * innerR
    local ox = center.x + dirX * outerR
    local oy = center.y + dirY * outerR

    local function quad(halfW, col)
      ui.pathClear()
      ui.pathLineTo(vec2(ix + px * halfW, iy + py * halfW))
      ui.pathLineTo(vec2(ix - px * halfW, iy - py * halfW))
      ui.pathLineTo(vec2(ox - px * halfW, oy - py * halfW))
      ui.pathLineTo(vec2(ox + px * halfW, oy + py * halfW))
      ui.pathFillConvex(col)
    end

    -- darker red outer layer (soft edges)
    quad(
      outerHalfW,
      rgbm(t.arcRed.r * 0.6, t.arcRed.g * 0.15, t.arcRed.b * 0.15, 0.9)
    )

    -- bright inner core (thin, sharp)
    quad(
      radius * 0.026,
      rgbm(1.0, 0.15, 0.0, 1.0)
    )
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
  -- Digital speed / gear cluster (no logos)
  --------------------------------------------------------
  local clusterW   = radius * 1.10
  local clusterH   = radius * 0.42
  local clusterY   = center.y + radius * 0.08
  local clusterMin = vec2(center.x - clusterW / 2, clusterY)
  local clusterMax = clusterMin + vec2(clusterW, clusterH)

  -- outer bezel + drop shadow
  ui.drawRectFilled(clusterMin + vec2(4, 6), clusterMax + vec2(4, 6), rgbm(0, 0, 0, 0.35))
  ui.drawRectFilled(clusterMin, clusterMax, rgbm(0, 0, 0, 0.45))

  -- inner glass cyan gradient
  local innerMin = clusterMin + vec2(4, 4)
  local innerMax = clusterMax - vec2(4, 4)
  ui.drawRectFilledMultiColor(
    innerMin, innerMax,
    t.glassTop,
    rgbm(t.glassTop.r, t.glassTop.g, t.glassTop.b, 0.65),
    t.glassBottom,
    rgbm(t.glassBottom.r, t.glassBottom.g, t.glassBottom.b, 0.95)
  )

  ui.drawRect(innerMin, innerMax, rgbm(1, 1, 1, 0.12), 1.2)
  ui.drawRect(clusterMin, clusterMax, rgbm(0.7, 0.9, 1.0, 0.25))
  ui.drawLine(
    vec2(innerMin.x + 6, innerMin.y + 6),
    vec2(innerMax.x - 6, innerMin.y + 6),
    rgbm(1, 1, 1, 0.15),
    1.0
  )

  local baseSpeed   = getCarSpeedKmh(car)
  local displaySpd  = math.abs(isKmh and baseSpeed or baseSpeed * KMH_TO_MPH)
  local speedText   = string.format("%d", math.floor(displaySpd + 0.5))
  local gearText    = formatGearText(car.gear)

  -- speed digits (left)
  local speedSize = radius * 0.26
  local speedW    = ui.measureDWriteText(speedText, speedSize).x
  local speedPos  = vec2(
    clusterMin.x + clusterW * 0.30 - speedW / 2,
    clusterMin.y + clusterH * 0.18
  )
  ui.dwriteDrawText(speedText, speedSize, speedPos, t.digital)

  -- km/h / mph text
  local unitText  = isKmh and "km/h" or "mph"
  local unitSize  = radius * 0.11
  local unitW     = ui.measureDWriteText(unitText, unitSize).x
  local unitPos   = vec2(
    clusterMin.x + clusterW * 0.32 - unitW / 2,
    clusterMin.y + clusterH * 0.60
  )
  ui.dwriteDrawText(unitText, unitSize, unitPos, rgbm(0.92, 0.98, 1.0, 0.95))

  -- gear / MT box (right)
  local gearBoxW   = clusterW * 0.24
  local gearBoxH   = clusterH * 0.70
  local gearBoxMin = vec2(clusterMin.x + clusterW * 0.68, clusterMin.y + clusterH * 0.15)
  local gearBoxMax = gearBoxMin + vec2(gearBoxW, gearBoxH)

  ui.drawRectFilled(gearBoxMin + vec2(2, 4), gearBoxMax + vec2(6, 8), rgbm(0, 0, 0, 0.35))
  ui.drawRectFilled(gearBoxMin, gearBoxMax, rgbm(0, 0, 0, 0.55))
  ui.drawRectFilledMultiColor(
    gearBoxMin + vec2(3, 3),
    gearBoxMax - vec2(3, 3),
    rgbm(0.25, 0.85, 1.0, 0.55),
    rgbm(0.35, 1.00, 1.0, 0.95),
    rgbm(0.00, 0.45, 0.65, 0.92),
    rgbm(0.00, 0.30, 0.45, 0.85)
  )
  ui.drawRect(gearBoxMin, gearBoxMax, rgbm(1, 1, 1, 0.25), 1.3)

  local gearSize = radius * 0.24
  local gearW    = ui.measureDWriteText(gearText, gearSize).x
  local gearPos  = vec2(
    gearBoxMin.x + gearBoxW / 2 - gearW / 2,
    gearBoxMin.y + gearBoxH / 2 - gearSize * 0.55
  )
  ui.dwriteDrawText(gearText, gearSize, gearPos, t.digital)

  local mtText = "MT"
  local mtSize = radius * 0.13
  local mtW    = ui.measureDWriteText(mtText, mtSize).x
  local mtPos  = vec2(
    gearBoxMin.x + gearBoxW / 2 - mtW / 2,
    gearBoxMin.y + gearBoxH / 2 + mtSize * 0.05
  )
  ui.dwriteDrawText(mtText, mtSize, mtPos, rgbm(0.92, 0.98, 1.0, 0.9))

  --------------------------------------------------------
  -- Accel / Brake mini gauge (right disc, GRADIENT)
  --------------------------------------------------------
  local subR      = radius * 0.55
  local subCenter = vec2(center.x + radius * 1.10, center.y + radius * 0.08)

  ui.drawCircleFilled(subCenter + vec2(0, subR * 0.12), subR * 1.05, rgbm(0, 0, 0, 0.35))
  ui.drawCircleFilled(subCenter, subR, rgbm(t.bgOuter.r, t.bgOuter.g, t.bgOuter.b, 0.85))
  ui.drawCircleFilled(subCenter, subR * 0.85, rgbm(0.03, 0.05, 0.08, 0.8))
  ui.drawCircleFilled(subCenter, subR * 0.70, rgbm(0.01, 0.02, 0.04, 0.95))
  ui.drawCircle(subCenter, subR * 0.95, rgbm(0.6, 0.9, 1.0, 0.35), 1.8)

  local accel = clamp(car.gas or car.throttle or 0.0, 0.0, 1.0)
  local brake = clamp(car.brake or 0.0, 0.0, 1.0)

  local sStart = math.rad(-210)
  local sEnd   = math.rad(  30)
  local sOuter = subR * 0.98
  local sInner = subR * 0.78

  -- tiny helper for color interpolation
  local function lerpColor(c1, c2, t)
    return rgbm(
      c1.r + (c2.r - c1.r) * t,
      c1.g + (c2.g - c1.g) * t,
      c1.b + (c2.b - c1.b) * t,
      c1.a + (c2.a - c1.a) * t
    )
  end

  ------------------------------------------------------
  -- ACCEL (blue gradient)
  ------------------------------------------------------
  if accel > 0.0 then
    local aStartFrac = 0.0
    local aEndFrac   = 0.55 * accel      -- only fills upper half of arc
    local segs       = 28

    local cBright = rgbm(0.05, 0.95, 1.00, 1.0)  -- start of arc
    local cDark   = rgbm(0.00, 0.40, 0.80, 1.0)  -- tail of arc

    for i = 0, segs - 1 do
      local f0   = aStartFrac + (aEndFrac - aStartFrac) * (i     / segs)
      local f1   = aStartFrac + (aEndFrac - aStartFrac) * ((i+1) / segs)
      local midT = (i + 0.5) / segs       -- 0 → 1 along the drawn part
      local col  = lerpColor(cBright, cDark, midT)

      local a0 = lerp(sStart, sEnd, f0)
      local a1 = lerp(sStart, sEnd, f1)

      ui.pathClear()
      ui.pathArcTo(subCenter, sOuter, a0, a1, 4)
      ui.pathArcTo(subCenter, sInner, a1, a0, 4)
      ui.pathStroke(col, true, 3.0)
    end
  end

  ------------------------------------------------------
  -- BRAKE (red gradient)
  ------------------------------------------------------
  if brake > 0.0 then
    local bBaseFrac = 0.55              -- where brake section starts
    local bEndFrac  = bBaseFrac + 0.45 * brake
    local segs      = 28

    local cBright = rgbm(1.00, 0.30, 0.10, 1.0)  -- start
    local cDark   = rgbm(0.70, 0.00, 0.00, 1.0)  -- tail

    for i = 0, segs - 1 do
      local f0   = bBaseFrac + (bEndFrac - bBaseFrac) * (i     / segs)
      local f1   = bBaseFrac + (bEndFrac - bBaseFrac) * ((i+1) / segs)
      local midT = (i + 0.5) / segs
      local col  = lerpColor(cBright, cDark, midT)

      local a0 = lerp(sStart, sEnd, f0)
      local a1 = lerp(sStart, sEnd, f1)

      ui.pathClear()
      ui.pathArcTo(subCenter, sOuter, a0, a1, 4)
      ui.pathArcTo(subCenter, sInner, a1, a0, 4)
      ui.pathStroke(col, true, 3.0)
    end
  end

  -- labels stay the same
  local pSize = radius * 0.11
  ui.dwriteDrawText("ACCEL", pSize,
    vec2(subCenter.x + subR * 0.05, subCenter.y - subR * 0.25),
    rgbm(0.85, 0.96, 1.0, 0.95))
  ui.dwriteDrawText("BRAKE", pSize,
    vec2(subCenter.x + subR * 0.05, subCenter.y),
    rgbm(0.95, 0.85, 0.85, 0.95))
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

  local radius = math.min(winSize.x, winSize.y) * 0.45
  local center = vec2(winSize.x * 0.5, winSize.y * 0.58)
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
