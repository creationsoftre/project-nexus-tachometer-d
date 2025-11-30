------------------------------------------------------------
-- Project Nexus Tachometer HUD (CSS-to-Lua conversion) NEW
-- Pure Lua resource that mirrors ui/index.html + style.css
------------------------------------------------------------

local SCALE    = 1.0
local MARGIN_X = 36
local MARGIN_Y = 36

------------------------------------------------------------
-- Layout derived from the HTML/CSS mock
------------------------------------------------------------

local layout = {
  cardW = 640,
  cardH = 300,
  tachCenter = { x = 410, y = 215 },
  tachRadius = 140,
  leftX = 42,
  gearY = 56,
  gearW = 150,
  gearH = 88,
  speedY = 160,
  speedW = 150,
  speedH = 115,
}

local dial = {
  maxValue = 8,
  startDeg = 330,   -- right-bottom anchor (8 mark)
  sweepDeg = 240,   -- counter-clockwise sweep across top leaving gap at bottom
  subdivisions = 5, -- minor ticks per 1k rpm
}
dial.startRad = math.rad(dial.startDeg)
dial.sweepRad = math.rad(dial.sweepDeg)
dial.endRad   = dial.startRad + dial.sweepRad
dial.stepRad  = dial.sweepRad / dial.maxValue

local settings = {
  position = nil,
  dragActive = false,
  dragOffset = nil,
  useMph = nil,
  speedPrefResolved = false,
}


local theme = {
  cardBg     = rgbm(0.08, 0.08, 0.08, 0.0),
  cardBorder = rgbm(0, 0, 0, 0),
  panelGlass = rgbm(0.05, 0.05, 0.05, 0.78),
  speedBg    = rgbm(0.01, 0.01, 0.01, 0.92),
  speedBorder= rgbm(1.0, 1.0, 1.0, 0.9),
  gearText   = rgbm(1.00, 0.75, 0.30, 1.0),
  labelText  = rgbm(0.90, 0.90, 0.90, 0.95),
  assistTextOn  = rgbm(0.24, 0.62, 0.95, 1.0),
  assistGlow    = rgbm(0.24, 0.62, 0.95, 0.45),
  assistTextOff = rgbm(0.62, 0.62, 0.62, 0.9),
  tachOuter  = rgbm(0.03, 0.03, 0.03, 0.92),
  tachInner  = rgbm(0.01, 0.01, 0.01, 0.96),
  ringDim    = rgbm(1.0, 1.0, 1.0, 0.12),
  ticks      = rgbm(1.0, 1.0, 1.0, 0.95),
  tickWarn   = rgbm(0.98, 0.92, 0.30, 1.0),
  tickHot    = rgbm(0.98, 0.34, 0.20, 1.0),
  needleGlow = rgbm(1.0, 0.28, 0.10, 0.45),
  needleCore = rgbm(1.0, 0.50, 0.18, 1.0),
  hubOuter   = rgbm(0.05, 0.05, 0.05, 1.0),
  hubInner   = rgbm(0.02, 0.02, 0.02, 1.0),
}

local carRPM      = 0
local carSpeedKmh = 0
local carGear     = 0
local absEnabled  = false
local tcEnabled   = false

local defaultMaxRpm = dial.maxValue * 1000
local minAllowedMax = 4000
local maxAllowedMax = 16000
local tachMaxRpm    = defaultMaxRpm

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function clamp(v, mn, mx)
  if v < mn then return mn end
  if v > mx then return mx end
  return v
end

local function drawRectFilled(min, max, col, rounding)
  ui.drawRectFilled(min, max, col, rounding or 0)
end

local function drawRectStroke(min, max, col, thickness, rounding)
  ui.drawRect(min, max, col, thickness or 1.0, rounding or 0)
end

local function rel(cardMin, scale, x, y)
  return vec2(cardMin.x + x * scale, cardMin.y + y * scale)
end

local function sinY(angle)
  return -math.sin(angle)
end

local function angleForRatio(ratio)
  local t = clamp(ratio, 0, 1)
  return dial.startRad + dial.sweepRad * (1 - t)
end

local function getSpeedDisplay()
  local useMph = settings.useMph
  if useMph == nil then
    useMph = true
  end

  if useMph then
    return math.floor(carSpeedKmh * 0.621371 + 0.5), "mph"
  end
  return math.floor(carSpeedKmh + 0.5), "km/h"
end



local function pathArc(center, radius, startAngle, endAngle, steps)
  for i = 0, steps do
    local t = i / steps
    local angle = startAngle + (endAngle - startAngle) * t
    local px = center.x + math.cos(angle) * radius
    local py = center.y + sinY(angle) * radius
    ui.pathLineTo(vec2(px, py))
  end
end

local function pointInRect(pos, min, max)
  return pos.x >= min.x and pos.x <= max.x and pos.y >= min.y and pos.y <= max.y
end

local function pointInCircle(pos, center, radius)
  local dx = pos.x - center.x
  local dy = pos.y - center.y
  return dx * dx + dy * dy <= radius * radius
end

local function sanitizeRpmValue(value)
  local rpm = tonumber(value)
  if rpm and rpm > 0 and rpm < 20000 then
    return rpm
  end
  return nil
end

local function normalizeRpmToHundred(value)
  if not value then return nil end
  return math.floor((value + 50) / 100) * 100
end

local function safeRead(obj, field)
  local ok, value = pcall(function() return obj[field] end)
  if ok then return value end
  return nil
end

local function resolveCarMaxRpm(car, carIndex)
  if not car then return nil end

  local idx = carIndex
  if idx == nil then
    idx = safeRead(car, "index") or 0
  end

  local carFields = { "rpmLimiter", "revLimiterRpm", "maxRpm", "engineMaxRpm", "redlineRPM" }
  for _, field in ipairs(carFields) do
    local rpm = sanitizeRpmValue(safeRead(car, field))
    if rpm then
      return rpm
    end
  end

  local physicsGetter = ac and ac.getCarPhysics
  local physics = physicsGetter and physicsGetter(idx)
  if physics then
    local physicsFields = { "rpmLimiter", "maxRpm", "engineMaxRpm" }
    for _, field in ipairs(physicsFields) do
      local rpm = sanitizeRpmValue(safeRead(physics, field))
      if rpm then
        return rpm
      end
    end
  end

  return nil
end

local function resolveCarMaxRpmSafe(car, carIndex)
  local ok, rpm = pcall(resolveCarMaxRpm, car, carIndex)
  if not ok then
    return nil
  end
  return sanitizeRpmValue(rpm)
end

local function chooseMaxRpm(car, carIndex)
  local limiter = resolveCarMaxRpmSafe(car, carIndex)
  local candidate = limiter or nil

  -- fall back to observed rpm if we have exceeded our current scale
  if not candidate and carRPM > tachMaxRpm then
    candidate = carRPM
  end

  if not candidate then
    return nil
  end

  -- normalize and clamp so bad values do not break the UI
  candidate = normalizeRpmToHundred(candidate)
  candidate = clamp(candidate, minAllowedMax, maxAllowedMax)
  return candidate
end

local function currentMaxRpm()
  if tachMaxRpm and tachMaxRpm > 0 then
    return tachMaxRpm
  end
  return defaultMaxRpm
end

local function interpretAssistValue(value)
  if value == nil then return nil end
  local t = type(value)
  if t == "boolean" then return value end
  if t == "number" then
    if value > 0 then return true end
    if value == 0 then return false end
  end
  if t == "string" then
    local lower = value:lower()
    if lower == "on" or lower == "enabled" or lower == "true" or lower == "1" or lower == "yes" then
      return true
    end
    if lower == "off" or lower == "disabled" or lower == "false" or lower == "0" or lower == "no" then
      return false
    end
  end
  if t == "table" then
    local keys = { "enabled", "active", "isOn", "on", "value", "state" }
    for _, key in ipairs(keys) do
      local nested = value[key]
      local interpreted = interpretAssistValue(nested)
      if interpreted ~= nil then
        return interpreted
      end
    end
  end
  return nil
end

local function readAssistFields(source, fields)
  if not source then return nil end
  for _, field in ipairs(fields) do
    local candidate = safeRead(source, field)
    local interpreted = interpretAssistValue(candidate)
    if interpreted ~= nil then
      return interpreted
    end
  end
  return nil
end

local absFields = { "abs", "absEnabled", "isAbsEnabled", "absOn", "absActive", "absState", "antiLock", "antilock", "antiLockBrakes", "antiLockBraking" }
local tcFields  = { "tc", "tcEnabled", "isTcEnabled", "tcOn", "tcActive", "tcState", "tractionControl", "tractionControlEnabled", "tractionControlActive" }

local function resolveAssistState(car, physics, fields)
  return readAssistFields(car, fields)
      or readAssistFields(safeRead(car, "electronics"), fields)
      or readAssistFields(physics, fields)
      or false
end

local function interpretSpeedUnitValue(value)
  local t = type(value)
  if t == "boolean" then
    return value
  end

  if t == "number" then
    if value < 0.5 then return false end
    if value > 0.5 then return true end
  end

  if t == "string" then
    local lower = value:lower()
    if lower == "1" or lower == "true" or lower == "mph" or lower == "mi/h" or lower == "miles" or lower == "imperial" then
      return true
    end
    if lower == "0" or lower == "false" or lower == "kmh" or lower == "km/h" or lower == "km" then
      return false
    end
  end

  if t == "table" then
    local keys = { "speedUnits", "unitsSpeed", "speedUnit", "unit", "unitSystem" }
    for _, key in ipairs(keys) do
      local nested = value[key]
      local interpreted = interpretSpeedUnitValue(nested)
      if interpreted ~= nil then
        return interpreted
      end
    end
  end

  return nil
end

local function detectSpeedUnitsFromIni()
  local folderId = safeRead(ac, "FolderID")
  local getFolder = safeRead(ac, "getFolder")
  local loader = ac and ac.INIConfig and ac.INIConfig.load
  if not folderId or not getFolder or not loader then return nil end

  local documentsId = safeRead(folderId, "Documents") or safeRead(folderId, "Root")
  if not documentsId then return nil end

  local base = getFolder(documentsId)
  if not base then return nil end

  local paths = {
    base .. "\\cfg\\assetto_corsa.ini",
    base .. "\\system\\cfg\\assetto_corsa.ini",
  }

  local sections = { "BASIC", "SETTINGS", "OPTIONS" }
  local keys = { "UNITS", "UNIT", "UNIT_SYSTEM", "SPEED_UNIT" }

  for _, path in ipairs(paths) do
    local ok, cfg = pcall(loader, path)
    if ok and cfg then
      for _, section in ipairs(sections) do
        for _, key in ipairs(keys) do
          local value = nil
          local got, result = pcall(function() return cfg:get(section, key) end)
          if got then value = result end
          local interpreted = interpretSpeedUnitValue(value)
          if interpreted ~= nil then
            return interpreted
          end
        end
      end
    end
  end

  return nil
end

local function detectSpeedUnitsFromCsp()
  local candidates = {
    function()
      if not ac or not ac.getSettings then return nil end
      return ac.getSettings()
    end,
    function()
      if not ac or not ac.getSim then return nil end
      return ac.getSim()
    end,
  }

  for _, getter in ipairs(candidates) do
    local ok, value = pcall(getter)
    if ok then
      local interpreted = interpretSpeedUnitValue(value)
      if interpreted ~= nil then
        return interpreted
      end
    end
  end

  return nil
end

local function resolveSpeedPreference()
  return detectSpeedUnitsFromCsp() or detectSpeedUnitsFromIni()
end

local function ensureSpeedPreference()
  if settings.useMph ~= nil then return end
  if settings.speedPrefResolved then return end

  local preferred = resolveSpeedPreference()
  settings.useMph = (preferred ~= nil) and preferred or true
  settings.speedPrefResolved = true
end

local function clampPosition(pos, win, size)
  local maxX = math.max(0, win.x - size.x)
  local maxY = math.max(0, win.y - size.y)
  return vec2(
    clamp(pos.x, 0, maxX),
    clamp(pos.y, 0, maxY)
  )
end

local function resolveCardMin(win, size)
  if not settings.dragOffset then
    settings.dragOffset = vec2(0, 0)
  end

  if not settings.position then
    settings.position = vec2(win.x - size.x - MARGIN_X, win.y - size.y - MARGIN_Y)
  end
  if settings.dragActive and ui.mouseDown(0) then
    local mouse = ui.mousePos()
    local newPos = vec2(mouse.x - settings.dragOffset.x, mouse.y - settings.dragOffset.y)
    settings.position = clampPosition(newPos, win, size)
  elseif not ui.mouseDown(0) then
    settings.dragActive = false
  end
  settings.position = clampPosition(settings.position, win, size)
  return settings.position
end

local function drawMoveHandle(win, cardMin, cardSize)
  local radius = 16
  local handle = cardMin + vec2(cardSize.x - radius - 8, -radius - 8)
  ui.drawCircleFilled(handle, radius, rgbm(0, 0, 0, 0.55))
  ui.drawCircle(handle, radius, rgbm(1, 1, 1, 0.2), 1.4)
  ui.drawLine(vec2(handle.x - 6, handle.y), vec2(handle.x + 6, handle.y), rgbm(1, 1, 1, 0.4), 1.4)
  ui.drawLine(vec2(handle.x, handle.y - 6), vec2(handle.x, handle.y + 6), rgbm(1, 1, 1, 0.4), 1.4)

  local mouse = ui.mousePos()
  if pointInCircle(mouse, handle, radius) and ui.mouseClicked(0) then
    settings.dragActive = true
    settings.dragOffset = vec2(mouse.x - cardMin.x, mouse.y - cardMin.y)
  end
end

local function drawSpeedToggle(cardMin, cardSize)
  local pillSize = vec2(150, 34)
  local pillMin = cardMin + vec2(8, -pillSize.y + 8)
  pillMin.x = math.max(pillMin.x, 12)
  pillMin.y = math.max(pillMin.y, 30)
  local pillMax = pillMin + pillSize
  local mouse = ui.mousePos()
  local hovered = pointInRect(mouse, pillMin, pillMax)

  ui.drawRectFilled(pillMin, pillMax, rgbm(0, 0, 0, 0.35), pillSize.y / 2)

  local halfWidth = pillSize.x / 2
  local leftBounds = { min = pillMin, max = vec2(pillMin.x + halfWidth, pillMax.y) }
  local rightBounds = { min = vec2(pillMin.x + halfWidth, pillMin.y), max = pillMax }

  local highlight = rgbm(theme.gearText.r, theme.gearText.g, theme.gearText.b, 0.92)
  local inactiveText = rgbm(1, 1, 1, 0.65)
  local activeText = rgbm(0.05, 0.05, 0.05, 1)

  if not settings.useMph then
    ui.drawRectFilled(vec2(leftBounds.min.x + 3, leftBounds.min.y + 3), vec2(leftBounds.max.x - 3, leftBounds.max.y - 3), highlight, pillSize.y / 2 - 3)
  else
    ui.drawRectFilled(vec2(rightBounds.min.x + 3, rightBounds.min.y + 3), vec2(rightBounds.max.x - 3, rightBounds.max.y - 3), highlight, pillSize.y / 2 - 3)
  end

  local function centerText(bounds, text, color)
    local measure = ui.measureDWriteText(text, 14)
    local pos = vec2(bounds.min.x + (bounds.max.x - bounds.min.x - measure.x) / 2, bounds.min.y + (pillSize.y - measure.y) / 2)
    ui.dwriteDrawText(text, 14, pos, color)
  end

  centerText(leftBounds, "km/h", settings.useMph and inactiveText or activeText)
  centerText(rightBounds, "mph", settings.useMph and activeText or inactiveText)

  if hovered and ui.mouseClicked(0) then
    if pointInRect(mouse, leftBounds.min, leftBounds.max) then
      settings.useMph = false
    elseif pointInRect(mouse, rightBounds.min, rightBounds.max) then
      settings.useMph = true
    end
  end
end

function script.update(dt)
  ensureSpeedPreference()

  local car = ac.getCar(0)
  if not car then return end

  carRPM      = car.rpm or 0
  carSpeedKmh = car.speedKmh or 0
  carGear     = car.gear or 0

  local physics = nil
  if ac and ac.getCarPhysics then
    local ok, ph = pcall(ac.getCarPhysics, 0)
    if ok then physics = ph end
  end

  absEnabled = resolveAssistState(car, physics, absFields)
  tcEnabled  = resolveAssistState(car, physics, tcFields)

  local newMax = chooseMaxRpm(car, 0)
  if newMax then
    tachMaxRpm = newMax
  elseif tachMaxRpm <= 0 then
    tachMaxRpm = defaultMaxRpm
  end
end

------------------------------------------------------------
-- Left cluster (gear + speed)
------------------------------------------------------------

local function gearDisplayText()
  if carGear < 0 then
    return "R"
  end
  if carGear == 0 then
    return "N"
  end
  return tostring(carGear)
end

local function drawAssistLabelText(pos, label, active, scale)
  local size = 18 * scale
  if active then
    local glow = theme.assistGlow
    ui.dwriteDrawText(label, size, vec2(pos.x + 1.2 * scale, pos.y + 1.2 * scale), glow)
  end
  local color = active and theme.assistTextOn or theme.assistTextOff
  ui.dwriteDrawText(label, size, pos, color)
end

local function drawAssistLabels(cardMin, scale)
  local center = rel(cardMin, scale, layout.tachCenter.x, layout.tachCenter.y)
  local radius = layout.tachRadius * scale
  local y = center.y - radius * 0.4

  local absPos = vec2(center.x - radius - 38 * scale, y)
  local tcPos  = vec2(center.x + radius + 18 * scale, y)

  drawAssistLabelText(absPos, "ABS", absEnabled, scale)
  drawAssistLabelText(tcPos,  "TC",  tcEnabled,  scale)
end

local function drawLeftCluster(cardMin, scale)
  local gearMin = rel(cardMin, scale, layout.leftX, layout.gearY)
  local gearMax = gearMin + vec2(layout.gearW * scale, layout.gearH * scale)

  drawRectFilled(gearMin, gearMax, theme.panelGlass, 14 * scale)
  ui.drawRectFilledMultiColor(
    gearMin, gearMax,
    rgbm(0.25, 0.25, 0.25, 0.18),
    rgbm(0.10, 0.10, 0.10, 0.02),
    rgbm(0.05, 0.05, 0.05, 0.02),
    rgbm(0.20, 0.20, 0.20, 0.18)
  )

  local gearText = gearDisplayText()
  local gearSize = 74 * scale
  local gearPos  = gearMin + vec2(10 * scale, -6 * scale)
  ui.dwriteDrawText(gearText, gearSize, gearPos, theme.gearText)

  local mtSize = 22 * scale
  local mtPos  = vec2(gearMax.x - 40 * scale, gearMin.y + 26 * scale)
  ui.dwriteDrawText("MT", mtSize, mtPos, theme.labelText)

  local speedMin = rel(cardMin, scale, layout.leftX, layout.speedY)
  local speedMax = speedMin + vec2(layout.speedW * scale, layout.speedH * scale)
  drawRectFilled(speedMin, speedMax, theme.speedBg, 16 * scale)
  drawRectStroke(speedMin, speedMax, theme.speedBorder, 3.0, 16 * scale)

  local speedValue, speedLabel = getSpeedDisplay()
  local speedText = tostring(speedValue)
  local speedSize = 76 * scale
  local speedMeasure = ui.measureDWriteText(speedText, speedSize)
  local speedPos = vec2(
    speedMin.x + (layout.speedW * scale - speedMeasure.x) / 2,
    speedMin.y - 4 * scale
  )
  ui.dwriteDrawText(speedText, speedSize, speedPos, theme.labelText)

  local unitSize = 18 * scale
  local unitPos  = vec2(speedMin.x + 18 * scale, speedMax.y - 28 * scale)
  ui.dwriteDrawText(speedLabel, unitSize, unitPos, theme.labelText)

  drawAssistLabels(cardMin, scale)
end

------------------------------------------------------------
-- Tachometer face (ticks, labels, needle)
------------------------------------------------------------

local function drawTicks(center, radius)
  local subdivisions = dial.subdivisions
  local maxRpm = currentMaxRpm()
  if maxRpm <= 0 then return end

  local stepRpm = 1000 / subdivisions
  local totalSteps = math.max(1, math.ceil(maxRpm / stepRpm))
  local warnBand = clamp(maxRpm * 0.18, 1200, 2400)
  local hotBand  = clamp(maxRpm * 0.12, 900, 1600)

  local function formatTickLabel(value)
    -- Force whole-number labels to avoid decimals like 8.2 on the tach face
    return string.format("%d", math.floor(value + 1e-3))
  end

  local lastLabel = nil

  for i = 0, totalSteps do
    local rpmValue = math.min(i * stepRpm, maxRpm)
    local ratio = rpmValue / maxRpm
    local angle = angleForRatio(ratio)
    local c, s = math.cos(angle), sinY(angle)
    local isMajor = (i % subdivisions == 0) or (i == totalSteps)

    local inner = radius * (isMajor and 0.66 or 0.74)
    local outer = radius * (isMajor and 0.97 or 0.89)
    local thickness = isMajor and 3.0 or 1.4

    local color = theme.ticks
    if rpmValue >= maxRpm - hotBand then
      color = theme.tickHot
    elseif rpmValue >= maxRpm - warnBand then
      color = theme.tickWarn
    end

    ui.drawLine(
      vec2(center.x + c * inner, center.y + s * inner),
      vec2(center.x + c * outer, center.y + s * outer),
      color,
      thickness
    )

    if isMajor then
      local label = formatTickLabel(rpmValue / 1000)
      if label ~= lastLabel then
        lastLabel = label
        local labelSize = 18 * SCALE
        local labelPos = vec2(
          center.x + c * (radius * 0.60),
          center.y + s * (radius * 0.60)
        )
        local labelMeasure = ui.measureDWriteText(label, labelSize)
        ui.dwriteDrawText(
          label,
          labelSize,
          vec2(labelPos.x - labelMeasure.x / 2, labelPos.y - labelMeasure.y / 2),
          theme.labelText
        )
      end
    end
  end
end

local function drawNeedle(center, radius)
  local rpmMax   = currentMaxRpm()
  if rpmMax <= 0 then return end
  local rpmValue = clamp(carRPM, 0, rpmMax)
  local ratio    = rpmValue / rpmMax
  local angle    = angleForRatio(ratio)

  local c, s = math.cos(angle), sinY(angle)
  local dir  = vec2(c, s)
  local norm = vec2(-s, c)

  local tail    = center + dir * (-radius * 0.12)
  local tip     = center + dir * (radius * 0.95)

  local function strip(halfW, col)
    ui.pathClear()
    ui.pathLineTo(vec2(tail.x + norm.x * halfW, tail.y + norm.y * halfW))
    ui.pathLineTo(vec2(tail.x - norm.x * halfW, tail.y - norm.y * halfW))
    ui.pathLineTo(vec2(tip.x  - norm.x * halfW, tip.y  - norm.y * halfW))
    ui.pathLineTo(vec2(tip.x  + norm.x * halfW, tip.y  + norm.y * halfW))
    ui.pathFillConvex(col)
  end

  strip(radius * 0.055, theme.needleGlow)
  strip(radius * 0.026, theme.needleCore)
end

local function drawDialBase(center, radius)
  local startAngle = dial.startRad
  local endAngle   = dial.endRad
  local segments   = 96

  ui.pathClear()
  pathArc(center, radius, startAngle, endAngle, segments)
  pathArc(center, radius * 0.78, endAngle, startAngle, segments)
  ui.pathFillConvex(theme.tachOuter)

  ui.pathClear()
  pathArc(center, radius * 0.76, startAngle, endAngle, segments)
  ui.pathLineTo(center)
  ui.pathFillConvex(theme.tachInner)

  ui.pathClear()
  pathArc(center, radius, startAngle, endAngle, segments)
  ui.pathStroke(rgbm(0, 0, 0, 0.9), false, 2.6)

  ui.pathClear()
  pathArc(center, radius * 0.94, startAngle, endAngle, segments)
  ui.pathStroke(rgbm(1, 1, 1, 0.08), false, 1.2)

  ui.pathClear()
  pathArc(center, radius * 0.84, startAngle, endAngle, segments)
  ui.pathStroke(theme.ringDim, false, 1.0)
end

local function drawDialHighlight(center, radius)
  ui.pathClear()
  pathArc(center, radius * 0.98, dial.startRad + 0.04, dial.endRad - 0.04, 48)
  ui.pathStroke(rgbm(1, 1, 1, 0.08), false, 6.0)
end

local function drawTach(cardMin, scale)
  local center = rel(cardMin, scale, layout.tachCenter.x, layout.tachCenter.y)
  local radius = layout.tachRadius * scale

  drawDialBase(center, radius)
  drawDialHighlight(center, radius)
  drawTicks(center, radius)

  -- draw hub first so needle renders on top of center circle
  ui.drawCircleFilled(center, radius * 0.11, theme.hubOuter)
  ui.drawCircleFilled(center, radius * 0.07, theme.hubInner)

  drawNeedle(center, radius)

  local rpmLabelSize = 20 * scale
  local rpmText = "RPM"
  local rpmMeasure = ui.measureDWriteText(rpmText, rpmLabelSize)
  local rpmPos = vec2(center.x - rpmMeasure.x / 2, center.y + radius * 0.12)
  ui.dwriteDrawText(rpmText, rpmLabelSize, rpmPos, theme.labelText)

  local subLabel = "x1000"
  local subSize  = 14 * scale
  local subMeasure = ui.measureDWriteText(subLabel, subSize)
  local subPos = vec2(center.x - subMeasure.x / 2, center.y + radius * 0.34)
  ui.dwriteDrawText(subLabel, subSize, subPos, theme.labelText)
end

------------------------------------------------------------
-- Main HUD draw
------------------------------------------------------------

function script.drawUI(dt)
  ensureSpeedPreference()

  local win = ui.windowSize()
  local scale = SCALE
  local cardSize = vec2(layout.cardW * scale, layout.cardH * scale)

  local cardMin = resolveCardMin(win, cardSize)

  drawMoveHandle(win, cardMin, cardSize)
  drawSpeedToggle(cardMin, cardSize)

  drawLeftCluster(cardMin, scale)
  drawTach(cardMin, scale)
end














