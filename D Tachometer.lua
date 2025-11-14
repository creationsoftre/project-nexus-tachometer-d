local ac = ac
local acsys = acsys
local math = math

local abs = math.abs
local sin = math.sin
local cos = math.cos
local tan = math.tan
local rad = math.rad

-- Override this with the absolute folder that contains D Tachometer.lua
-- (for example "C:/Users/Administrator/Desktop/Project Nexus - Drift/apps/python/D Tachometer")
-- when the runtime does not expose the debug library.
local CUSTOM_APP_PATH = nil

local function normalizePath(path)
  path = path or ""
  path = path:gsub("\\", "/")
  path = path:gsub("/+", "/")
  return path
end

local function joinPath(base, relative)
  base = normalizePath(base or "")
  relative = normalizePath(relative or "")
  if base == "" then
    return relative
  end
  if relative == "" then
    return base
  end
  if base:sub(-1) == "/" then
    return base .. relative
  end
  return base .. "/" .. relative
end

local function dirname(path)
  local dir = path:match("^(.*[/\\])")
  if not dir or dir == "" then
    return "./"
  end
  return normalizePath(dir)
end

local function detectScriptDir()
  if CUSTOM_APP_PATH and CUSTOM_APP_PATH ~= "" then
    return normalizePath(CUSTOM_APP_PATH)
  end
  if debug and debug.getinfo then
    local info = debug.getinfo(1, "S")
    if info and info.source then
      local source = info.source
      if source:sub(1, 1) == "@" then
        source = source:sub(2)
      end
      return dirname(source)
    end
  end
  return normalizePath("./")
end

local script_dir = detectScriptDir()
local app_path = script_dir
local config_path = joinPath(app_path, "config.ini")
local themes_root = joinPath(app_path, "themes")

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parseBool(value)
  if value == nil then
    return nil
  end
  if type(value) == "boolean" then
    return value
  end
  local str = tostring(value):lower()
  if str == "1" or str == "true" or str == "yes" or str == "on" then
    return true
  end
  if str == "0" or str == "false" or str == "no" or str == "off" then
    return false
  end
  return nil
end

local function readIni(path)
  local sections = {}
  local current = nil
  local file = io.open(path, "r")
  if not file then
    return sections
  end
  for line in file:lines() do
    local clean = trim(line)
    if clean ~= "" and clean:sub(1, 1) ~= "#" and clean:sub(1, 1) ~= ";" then
      local section = clean:match("^%[(.+)%]$")
      if section then
        current = section
        sections[current] = sections[current] or {}
      else
        local key, value = clean:match("^(.-)=(.-)$")
        if key and value then
          key = trim(key)
          value = trim(value)
          local target = current or "default"
          sections[target] = sections[target] or {}
          sections[target][key] = value
        end
      end
    end
  end
  file:close()
  return sections
end

local function sortedKeys(tbl)
  local keys = {}
  for key in pairs(tbl) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

local function writeIni(path, sections, ordered)
  local file = io.open(path, "w")
  if not file then
    return false
  end
  local written = {}
  local function writeSection(name)
    local content = sections[name]
    if content and not written[name] then
      file:write("[", name, "]\n")
      for _, key in ipairs(sortedKeys(content)) do
        file:write(key, " = ", tostring(content[key]), "\n")
      end
      file:write("\n")
      written[name] = true
    end
  end
  if ordered then
    for _, section in ipairs(ordered) do
      writeSection(section)
    end
  end
  for section in pairs(sections) do
    writeSection(section)
  end
  file:close()
  return true
end

local config_data = readIni(config_path)
config_data["D Tachometer"] = config_data["D Tachometer"] or {}
local config_section = config_data["D Tachometer"]
local config_dirty = false

local function getConfigNumber(key, default)
  local value = tonumber(config_section[key])
  if value == nil then
    config_section[key] = tostring(default)
    config_dirty = true
    return default
  end
  return value
end

local function getConfigBool(key, default)
  local parsed = parseBool(config_section[key])
  if parsed == nil then
    config_section[key] = default and "1" or "0"
    config_dirty = true
    return default
  end
  return parsed
end

local function setConfigValue(key, value)
  config_section[key] = tostring(value)
  config_dirty = true
end

local function saveConfig()
  if config_dirty then
    writeIni(config_path, config_data, {"D Tachometer"})
    config_dirty = false
  end
end

local app_window = nil
local settings_window = nil
local theme_label = nil
local theme_spinner = nil
local scale_label = nil
local scale_spinner = nil
local redLimit_offset_label = nil
local redLimit_offset_spinner = nil
local speedo_color_label = nil
local speedo_color_checkbox = nil
local unit_kmh_label = nil
local unit_kmh_checkbox = nil
local show_drift_label = nil
local show_drift_checkbox = nil
local show_pedal_label = nil
local show_pedal_checkbox = nil
local refresh_rate_label = nil
local refresh_rate_checkbox = nil
local preview_label = nil

local background = nil
local background_pedal = nil
local drift_background = nil
local drift_background_pedal = nil
local kmh_texture = nil
local mph_texture = nil
local gas_texture = nil
local brake_texture = nil
local gear_textures = {}
local speed_digits = {}
local speed_red = {}
local speed_yellow = {}
local speed_blue = {}
local drift_blue = nil
local drift_yellow = nil
local rev_light_texture = nil
local rpm_bar_texture = nil
local night_rpm_bar_texture = nil
local rpm_gauge_textures = {}
local night_rpm_gauge_textures = {}

local timer = 0
local timer2 = 0
local timer3 = 0
local status = 0
local current_car = 0
local maxRpm = maxRpm_state_2
local rpm = 0
local speed = 0
local gear = 0
local gas = 0
local brake = 0
local flash_rate = 7.2
local alpha = -0.1
local speed_list = {0}
local gas_value = 0
local brake_value = 0
local get_headlights = false
local car_name = ""
local angle_car = 0
local settings_window_visibility = 0

local function refreshSpeedList(value)
  local formatted = string.format("%.0f", value or 0)
  speed_list = {}
  for i = 1, #formatted do
    local digit = tonumber(formatted:sub(i, i)) or 0
    speed_list[#speed_list + 1] = digit
  end
  if #speed_list == 0 then
    speed_list[1] = 0
  end
end

local function updateWindowSize()
  if not app_window then
    return
  end
  if pedal_gauge_available and show_pedal then
    ac.setSize(app_window, background_pedal_width * scale, background_pedal_height * scale)
  else
    ac.setSize(app_window, background_width * scale, background_height * scale)
  end
  if settings_window then
    ac.setSize(settings_window, 360 * scale, 480 * scale)
  end
end

local function loadTextures()
  background = ac.newTexture(joinPath(app_path, string.format("themes/D%d/background/background.png", theme)))
  background_pedal = ac.newTexture(joinPath(app_path, string.format("themes/D%d/background/background_pedal.png", theme)))
  drift_background = ac.newTexture(joinPath(app_path, string.format("themes/D%d/background/drift_background.png", theme)))
  drift_background_pedal = ac.newTexture(joinPath(app_path, string.format("themes/D%d/background/drift_background_pedal.png", theme)))
  kmh_texture = ac.newTexture(joinPath(app_path, string.format("themes/D%d/speed_unit/kmh.png", theme)))
  mph_texture = ac.newTexture(joinPath(app_path, string.format("themes/D%d/speed_unit/mph.png", theme)))
  gas_texture = ac.newTexture(joinPath(app_path, string.format("themes/D%d/pedal/gas.png", theme)))
  brake_texture = ac.newTexture(joinPath(app_path, string.format("themes/D%d/pedal/brake.png", theme)))

  gear_textures = {}
  for i = 0, 10 do
    gear_textures[i] = ac.newTexture(joinPath(app_path, string.format("themes/D%d/gears/gear_%d.png", theme, i)))
  end

  if variable_speed_color then
    speed_red = {}
    speed_yellow = {}
    speed_blue = {}
    for i = 0, 9 do
      speed_red[i] = ac.newTexture(joinPath(app_path, string.format("themes/D%d/speed_red/speed_digits_%d.png", theme, i)))
      speed_yellow[i] = ac.newTexture(joinPath(app_path, string.format("themes/D%d/speed_yellow/speed_digits_%d.png", theme, i)))
      speed_blue[i] = ac.newTexture(joinPath(app_path, string.format("themes/D%d/speed_blue/speed_digits_%d.png", theme, i)))
    end
  else
    speed_digits = {}
    for i = 0, 9 do
      speed_digits[i] = ac.newTexture(joinPath(app_path, string.format("themes/D%d/speed_digits/speed_digits_%d.png", theme, i)))
    end
  end

  if drift_light_available then
    drift_blue = ac.newTexture(joinPath(app_path, string.format("themes/D%d/drift/drift_blue.png", theme)))
    drift_yellow = ac.newTexture(joinPath(app_path, string.format("themes/D%d/drift/drift_yellow.png", theme)))
  end

  if rev_light_available then
    rev_light_texture = ac.newTexture(joinPath(app_path, string.format("themes/D%d/rev_light.png", theme)))
  end

  if night_mode_available then
    night_rpm_bar_texture = ac.newTexture(joinPath(app_path, string.format("themes/D%d/rpm_bar/night_rpm_bar.png", theme)))
  end
  rpm_bar_texture = ac.newTexture(joinPath(app_path, string.format("themes/D%d/rpm_bar/rpm_bar.png", theme)))

  rpm_gauge_textures = {}
  local suffixes = {"8k", "9k", "10k", "13k", "16k", "18k", "20k"}
  for index, suffix in ipairs(suffixes) do
    rpm_gauge_textures[index - 1] = ac.newTexture(joinPath(app_path,
      string.format("themes/D%d/background/labels_%s.png", theme, suffix)))
  end
  if has_ae86_gauge then
    rpm_gauge_textures[7] = ac.newTexture(joinPath(app_path, string.format("themes/D%d/background/labels_86.png", theme)))
  end

  if night_mode_available then
    night_rpm_gauge_textures = {}
    for index, suffix in ipairs(suffixes) do
      night_rpm_gauge_textures[index - 1] = ac.newTexture(joinPath(app_path,
        string.format("themes/D%d/background/night_labels_%s.png", theme, suffix)))
    end
    if has_ae86_gauge then
      night_rpm_gauge_textures[7] = ac.newTexture(joinPath(app_path, string.format("themes/D%d/background/night_labels_86.png", theme)))
    end
  end
end

loadTextures()

local function settings_window_activated()
  settings_window_visibility = 1
end

local function settings_window_deactivated()
  settings_window_visibility = 0
end

local function scale_spinner_clicked()
  scale = ac.getValue(scale_spinner) / 100.0
  setConfigValue("scale", string.format("%.0f", ac.getValue(scale_spinner)))
  updateWindowSize()
end

local function unit_kmh_checkbox_clicked()
  unit_kmh = not unit_kmh
  setConfigValue("unit_kmh", unit_kmh and "1" or "0")
end

local function refresh_rate_checkbox_clicked()
  lower_refresh_rate = not lower_refresh_rate
  setConfigValue("lower_refresh_rate", lower_refresh_rate and "1" or "0")
  timer3 = 0
end

local function theme_spinner_clicked()
  local selected = math.floor(ac.getValue(theme_spinner))
  setConfigValue("theme", tostring(selected))
  ac.setBackgroundTexture(preview_label,
    joinPath(app_path, string.format("themes/D%d/preview.png", selected)))
end

local function redLimit_offset_spinner_clicked()
  redLimit_offset = ac.getValue(redLimit_offset_spinner)
  setConfigValue("redLimit_offset", string.format("%.0f", redLimit_offset))
end

local function speedo_color_checkbox_clicked()
  fixed_speedo_color = not fixed_speedo_color
  setConfigValue("fixed_speedo_color", fixed_speedo_color and "1" or "0")
end

local function show_drift_checkbox_clicked()
  show_drift = not show_drift
  setConfigValue("show_drift", show_drift and "1" or "0")
end

local function show_pedal_checkbox_clicked()
  show_pedal = not show_pedal
  setConfigValue("show_pedal", show_pedal and "1" or "0")
  updateWindowSize()
end

function acMain(ac_version)
  app_window = ac.newApp("D Tachometer")
  ac.setTitle(app_window, "")
  ac.drawBorder(app_window, 0)
  ac.setIconPosition(app_window, 0, -10000)
  updateWindowSize()
  ac.setBackgroundOpacity(app_window, 0)
  ac.addRenderCallback(app_window, appGL)

  settings_window = ac.newApp("Tachometer Settings")
  ac.drawBorder(settings_window, 0)
  ac.setVisible(settings_window, settings_window_visibility)
  ac.setSize(settings_window, 360 * scale, 480 * scale)
  ac.addOnAppActivatedListener(settings_window, settings_window_activated)
  ac.addOnAppDismissedListener(settings_window, settings_window_deactivated)

  theme_label = ac.addLabel(settings_window, "Theme (requires restart)")
  ac.setPosition(theme_label, 10 * scale, 40 * scale)
  ac.setFontSize(theme_label, 20 * scale)

  theme_spinner = ac.addSpinner(settings_window, "")
  ac.setRange(theme_spinner, 3, 7)
  ac.setStep(theme_spinner, 1)
  ac.setValue(theme_spinner, theme)
  ac.setPosition(theme_spinner, 260 * scale, 40 * scale)
  ac.setSize(theme_spinner, 90 * scale, 25 * scale)
  ac.setFontSize(theme_spinner, 20 * scale)
  ac.addOnValueChangeListener(theme_spinner, theme_spinner_clicked)

  scale_label = ac.addLabel(settings_window, "Scale")
  ac.setPosition(scale_label, 10 * scale, 80 * scale)
  ac.setFontSize(scale_label, 20 * scale)

  scale_spinner = ac.addSpinner(settings_window, "")
  ac.setRange(scale_spinner, 50, 200)
  ac.setStep(scale_spinner, 10)
  ac.setValue(scale_spinner, scale * 100)
  ac.setPosition(scale_spinner, 260 * scale, 80 * scale)
  ac.setSize(scale_spinner, 90 * scale, 25 * scale)
  ac.setFontSize(scale_spinner, 20 * scale)
  ac.addOnValueChangeListener(scale_spinner, scale_spinner_clicked)

  redLimit_offset_label = ac.addLabel(settings_window, "Shift indicator offset (RPM)")
  ac.setPosition(redLimit_offset_label, 10 * scale, 120 * scale)
  ac.setFontSize(redLimit_offset_label, 20 * scale)

  redLimit_offset_spinner = ac.addSpinner(settings_window, "")
  ac.setRange(redLimit_offset_spinner, 1000, 3000)
  ac.setStep(redLimit_offset_spinner, 500)
  ac.setValue(redLimit_offset_spinner, redLimit_offset)
  ac.setPosition(redLimit_offset_spinner, 260 * scale, 120 * scale)
  ac.setSize(redLimit_offset_spinner, 90 * scale, 25 * scale)
  ac.setFontSize(redLimit_offset_spinner, 20 * scale)
  ac.addOnValueChangeListener(redLimit_offset_spinner, redLimit_offset_spinner_clicked)

  show_drift_label = ac.addLabel(settings_window, "Show drift light")
  ac.setPosition(show_drift_label, 10 * scale, 160 * scale)
  ac.setFontSize(show_drift_label, 20 * scale)

  show_drift_checkbox = ac.addCheckBox(settings_window, "")
  ac.setValue(show_drift_checkbox, show_drift and 1 or 0)
  ac.setPosition(show_drift_checkbox, 330 * scale, 160 * scale)
  ac.setSize(show_drift_checkbox, 20 * scale, 20 * scale)
  ac.addOnCheckBoxChanged(show_drift_checkbox, show_drift_checkbox_clicked)

  show_pedal_label = ac.addLabel(settings_window, "Show pedal gauge")
  ac.setPosition(show_pedal_label, 10 * scale, 200 * scale)
  ac.setFontSize(show_pedal_label, 20 * scale)

  show_pedal_checkbox = ac.addCheckBox(settings_window, "")
  ac.setValue(show_pedal_checkbox, show_pedal and 1 or 0)
  ac.setPosition(show_pedal_checkbox, 330 * scale, 200 * scale)
  ac.setSize(show_pedal_checkbox, 20 * scale, 20 * scale)
  ac.addOnCheckBoxChanged(show_pedal_checkbox, show_pedal_checkbox_clicked)

  unit_kmh_label = ac.addLabel(settings_window, "Speed in km/h")
  ac.setPosition(unit_kmh_label, 10 * scale, 240 * scale)
  ac.setFontSize(unit_kmh_label, 20 * scale)

  unit_kmh_checkbox = ac.addCheckBox(settings_window, "")
  ac.setValue(unit_kmh_checkbox, unit_kmh and 1 or 0)
  ac.setPosition(unit_kmh_checkbox, 330 * scale, 240 * scale)
  ac.setSize(unit_kmh_checkbox, 20 * scale, 20 * scale)
  ac.addOnCheckBoxChanged(unit_kmh_checkbox, unit_kmh_checkbox_clicked)

  speedo_color_label = ac.addLabel(settings_window, "Fixed speedometer color")
  ac.setPosition(speedo_color_label, 10 * scale, 280 * scale)
  ac.setFontSize(speedo_color_label, 20 * scale)

  speedo_color_checkbox = ac.addCheckBox(settings_window, "")
  ac.setValue(speedo_color_checkbox, fixed_speedo_color and 1 or 0)
  ac.setPosition(speedo_color_checkbox, 330 * scale, 280 * scale)
  ac.setSize(speedo_color_checkbox, 20 * scale, 20 * scale)
  ac.addOnCheckBoxChanged(speedo_color_checkbox, speedo_color_checkbox_clicked)

  refresh_rate_label = ac.addLabel(settings_window, "Lower refresh rate")
  ac.setPosition(refresh_rate_label, 10 * scale, 320 * scale)
  ac.setFontSize(refresh_rate_label, 20 * scale)

  refresh_rate_checkbox = ac.addCheckBox(settings_window, "")
  ac.setValue(refresh_rate_checkbox, lower_refresh_rate and 1 or 0)
  ac.setPosition(refresh_rate_checkbox, 330 * scale, 320 * scale)
  ac.setSize(refresh_rate_checkbox, 20 * scale, 20 * scale)
  ac.addOnCheckBoxChanged(refresh_rate_checkbox, refresh_rate_checkbox_clicked)

  preview_label = ac.addLabel(settings_window, "")
  ac.setPosition(preview_label, 0, 336 * scale)
  ac.setSize(preview_label, 360 * scale, 144 * scale)
  ac.setBackgroundTexture(preview_label, preview_path)
end

function appGL(deltaT)
  ac.glColor4f(1, 1, 1, 1)
  if drift_light_available and show_drift then
    if pedal_gauge_available and show_pedal then
      ac.glQuadTextured(0, 0, background_pedal_width * scale, background_pedal_height * scale, drift_background_pedal)
    else
      ac.glQuadTextured(0, 0, background_width * scale, background_height * scale, drift_background)
    end
  else
    if pedal_gauge_available and show_pedal then
      ac.glQuadTextured(0, 0, background_pedal_width * scale, background_pedal_height * scale, background_pedal)
    else
      ac.glQuadTextured(0, 0, background_width * scale, background_height * scale, background)
    end
  end

  if unit_kmh then
    ac.glQuadTextured(unit_x * scale, unit_y * scale, unit_width * scale, unit_height * scale, kmh_texture)
  else
    ac.glQuadTextured(unit_x * scale, unit_y * scale, unit_width * scale, unit_height * scale, mph_texture)
  end

  ac.glColor4f(1, 1, 1, 1)
  ac.glBegin(acsys.GL.Quads)

  local gauge_table = rpm_gauge_textures
  if night_mode_available and get_headlights then
    gauge_table = night_rpm_gauge_textures
  end

  local selected_index = 2
  if has_ae86_gauge and car_name ~= "" and car_name:lower():find("ae86", 1, true) and maxRpm < 8500 then
    selected_index = 7
  else
    if maxRpm > maxRpm_state_6 then
      selected_index = 6
    elseif maxRpm > maxRpm_state_5 then
      selected_index = 5
    elseif maxRpm > maxRpm_state_4 then
      selected_index = 4
    elseif maxRpm > maxRpm_state_3 then
      selected_index = 3
    elseif maxRpm > maxRpm_state_2 then
      selected_index = 2
    elseif maxRpm > maxRpm_state_1 then
      selected_index = 1
    elseif maxRpm > maxRpm_state_0 then
      selected_index = 0
    else
      selected_index = 2
    end
  end

  local selected_texture = gauge_table[selected_index] or gauge_table[2]

  local spin_rate = 10000 / degree_available
  if selected_index == 0 then
    spin_rate = 8000 / degree_available
  elseif selected_index == 1 then
    spin_rate = 9000 / degree_available
  elseif selected_index == 2 then
    spin_rate = 10000 / degree_available
  elseif selected_index == 3 then
    spin_rate = 13000 / degree_available
  elseif selected_index == 4 then
    spin_rate = 16000 / degree_available
  elseif selected_index == 5 then
    spin_rate = 18000 / degree_available
  elseif selected_index == 6 then
    spin_rate = 20000 / degree_available
  elseif selected_index == 7 then
    spin_rate = 8000 / degree_available
  end

  ac.ext_glSetTexture(selected_texture)
  ac.ext_glVertexTex(gauge_x * scale, gauge_y * scale, 0, 0)
  ac.ext_glVertexTex(gauge_x * scale, (gauge_y + gauge_height) * scale, 0, 1)
  ac.ext_glVertexTex((gauge_x + gauge_width) * scale, (gauge_y + gauge_height) * scale, 1, 1)
  ac.ext_glVertexTex((gauge_x + gauge_width) * scale, gauge_y * scale, 1, 0)
  ac.glEnd()

  ac.glColor4f(1, 1, 1, 1)
  ac.glBegin(acsys.GL.Quads)
  if night_mode_available and get_headlights then
    ac.ext_glSetTexture(night_rpm_bar_texture or rpm_bar_texture)
  else
    ac.ext_glSetTexture(rpm_bar_texture)
  end

  local angle = rad(rpm / spin_rate + degree_offset)
  local cx = rpm_center_x
  local cy = rpm_center_y
  local function rotate(x, y)
    return (cx + (x - cx) * cos(angle) - (y - cy) * sin(angle)) * scale,
      (cy + (x - cx) * sin(angle) + (y - cy) * cos(angle)) * scale
  end

  ac.ext_glTexCoord2f(0, 0)
  local x1, y1 = rotate(rpm_x, rpm_y)
  ac.glVertex2f(x1, y1)

  ac.ext_glTexCoord2f(0, 1)
  local x2, y2 = rotate(rpm_x, rpm_y + rpm_height)
  ac.glVertex2f(x2, y2)

  ac.ext_glTexCoord2f(1, 1)
  local x3, y3 = rotate(rpm_x + rpm_width, rpm_y + rpm_height)
  ac.glVertex2f(x3, y3)

  ac.ext_glTexCoord2f(1, 0)
  local x4, y4 = rotate(rpm_x + rpm_width, rpm_y)
  ac.glVertex2f(x4, y4)

  ac.glEnd()

  if pedal_gauge_available and show_pedal then
    local degreeGas = gas_value * degree_gas
    local degreeBrake = brake_value * degree_brake
    local pedal_angle = rad(pedal_offset)

    local function rotatePedalPoint(px, py, center_x, center_y)
      return (center_x + (px - center_x) * cos(pedal_angle) - (py - center_y) * sin(pedal_angle)) * scale,
        (center_y + (px - center_x) * sin(pedal_angle) + (py - center_y) * cos(pedal_angle)) * scale
    end

    local function drawPedal(texture, base_x, base_y, width, height, degreeValue)
      local center_x = base_x
      local center_y = base_y + (height / 2)
      local coord_1 = degreeValue < 45 and tan(rad(degreeValue)) or 1
      ac.glColor4f(1, 1, 1, 1)
      ac.glBegin(acsys.GL.Triangles)
      ac.ext_glSetTexture(texture)
      local vx1, vy1 = rotatePedalPoint(base_x, base_y, center_x, center_y)
      ac.ext_glTexCoord2f(0, 0)
      ac.glVertex2f(vx1, vy1)

      ac.ext_glTexCoord2f(0, 0.5)
      ac.glVertex2f(center_x * scale, center_y * scale)

      local vx2, vy2 = rotatePedalPoint(base_x + (width * coord_1), base_y, center_x, center_y)
      ac.ext_glTexCoord2f(coord_1, 0)
      ac.glVertex2f(vx2, vy2)
      ac.glEnd()

      if degreeValue > 45 then
        local coord_2 = degreeValue > 90 and 0.5 or (1 - tan(rad(90 - degreeValue))) / 2
        ac.glColor4f(1, 1, 1, 1)
        ac.glBegin(acsys.GL.Triangles)
        ac.ext_glSetTexture(texture)
        local vx3, vy3 = rotatePedalPoint(base_x + width, base_y, center_x, center_y)
        ac.ext_glTexCoord2f(1, 0)
        ac.glVertex2f(vx3, vy3)

        ac.ext_glTexCoord2f(0, 0.5)
        ac.glVertex2f(center_x * scale, center_y * scale)

        local vx4, vy4 = rotatePedalPoint(base_x + width, base_y + (height * coord_2), center_x, center_y)
        ac.ext_glTexCoord2f(1, coord_2)
        ac.glVertex2f(vx4, vy4)
        ac.glEnd()
      end

      if degreeValue > 90 then
        local coord_3
        if degreeValue > 135 then
          coord_3 = 1
        else
          coord_3 = 0.5 + (tan(rad(degreeValue - 90)) / 2)
        end
        ac.glColor4f(1, 1, 1, 1)
        ac.glBegin(acsys.GL.Triangles)
        ac.ext_glSetTexture(texture)
        local vx5, vy5 = rotatePedalPoint(base_x + width, base_y + (height / 2), center_x, center_y)
        ac.ext_glTexCoord2f(1, 0.5)
        ac.glVertex2f(vx5, vy5)

        ac.ext_glTexCoord2f(0, 0.5)
        ac.glVertex2f(center_x * scale, center_y * scale)

        local vx6, vy6 = rotatePedalPoint(base_x + width, base_y + (height * coord_3), center_x, center_y)
        ac.ext_glTexCoord2f(1, coord_3)
        ac.glVertex2f(vx6, vy6)
        ac.glEnd()
      end
    end

    drawPedal(gas_texture, gas_x, gas_y, gas_width, gas_height, degreeGas)
    drawPedal(brake_texture, brake_x, brake_y, brake_width, brake_height, degreeBrake)
  end

  if status ~= 1 and drift_light_available and show_drift then
    if angle_car > 30 and speed > 5 then
      ac.glColor4f(1, 1, 1, 1)
      ac.glQuadTextured(drift_x * scale, drift_y * scale, drift_width * scale, drift_height * scale, drift_yellow)
    elseif angle_car > 15 and speed > 5 then
      ac.glColor4f(1, 1, 1, alpha)
      ac.glQuadTextured(drift_x * scale, drift_y * scale, drift_width * scale, drift_height * scale, drift_blue)
    end
  end

  if rev_light_available and rev_light_texture then
    if maxRpm - rpm < 250 then
      ac.glColor4f(1, 1, 1, 1)
      ac.glQuadTextured(rev_x * scale, rev_y * scale, rev_width * scale, rev_height * scale, rev_light_texture)
    elseif maxRpm - rpm < redLimit_offset then
      ac.glColor4f(1, 1, 1, ((rpm - maxRpm) / redLimit_offset) + 1)
      ac.glQuadTextured(rev_x * scale, rev_y * scale, rev_width * scale, rev_height * scale, rev_light_texture)
    end
  end

  ac.glColor4f(1, 1, 1, 1)
  local speedTextures = speed_digits
  if variable_speed_color then
    if fixed_speedo_color then
      speedTextures = speed_blue
    elseif speed < 100 then
      speedTextures = speed_red
    elseif speed < 150 then
      speedTextures = speed_yellow
    else
      speedTextures = speed_blue
    end
  end

  for i = 1, #speed_list do
    local digit = speed_list[#speed_list - (i - 1)] or 0
    local texture = speedTextures[digit]
    if texture then
      ac.glQuadTextured((speed_x - (i - 1) * (speed_width + speed_gap)) * scale,
        speed_y * scale,
        speed_width * scale,
        speed_height * scale,
        texture)
    end
  end

  local gear_texture = gear_textures[gear] or gear_textures[0]
  if gear_texture then
    ac.glColor4f(1, 1, 1, 1)
    ac.glQuadTextured(gear_x * scale, gear_y * scale, gear_width * scale, gear_height * scale, gear_texture)
  end
end

function acUpdate(deltaT)
  if alpha < 0 then
    flash_rate = 7.2
  elseif alpha > 1.2 then
    flash_rate = -7.2
  end

  if status ~= 1 and drift_light_available and show_drift then
    alpha = alpha + (deltaT * flash_rate)
  end

  timer = timer + deltaT
  timer2 = timer2 + deltaT
  if lower_refresh_rate then
    timer3 = timer3 + deltaT
  end

  if timer > 1 then
    timer = 0
    if info and info.static and info.graphics then
      maxRpm = tonumber(info.static.maxRpm) or maxRpm
      status = tonumber(info.graphics.status) or status
    end
    ac.setBackgroundOpacity(app_window, 0)
  end

  if timer2 > 0.1 then
    timer2 = 0
    current_car = ac.getFocusedCar()
    get_headlights = ac.ext_getHeadlights(current_car)
    if has_ae86_gauge then
      car_name = ac.getCarName(current_car) or ""
    end
    if status ~= 1 and drift_light_available and show_drift then
      local angle_fl, angle_fr, angle_rl, angle_rr = ac.getCarState(current_car, acsys.CS.SlipAngle)
      angle_car = abs((angle_rl + angle_rr) / 2)
    end
    gear = ac.getCarState(current_car, acsys.CS.Gear)
    if lower_refresh_rate then
      if unit_kmh then
        speed = ac.getCarState(current_car, acsys.CS.SpeedKMH)
      else
        speed = ac.getCarState(current_car, acsys.CS.SpeedMPH)
      end
      refreshSpeedList(speed)
    end
  end

  if lower_refresh_rate then
    if timer3 > 0.0333 then
      timer3 = 0
      rpm = ac.getCarState(current_car, acsys.CS.RPM)
      if not info then
        maxRpm = math.max(maxRpm, rpm)
      end
      if pedal_gauge_available and show_pedal then
        gas_value = ac.getCarState(current_car, acsys.CS.Gas)
        brake_value = ac.getCarState(current_car, acsys.CS.Brake)
      end
    end
  else
    rpm = ac.getCarState(current_car, acsys.CS.RPM)
    if not info then
      maxRpm = math.max(maxRpm, rpm)
    end
    if unit_kmh then
      speed = ac.getCarState(current_car, acsys.CS.SpeedKMH)
    else
      speed = ac.getCarState(current_car, acsys.CS.SpeedMPH)
    end
    refreshSpeedList(speed)
    if pedal_gauge_available and show_pedal then
      gas_value = ac.getCarState(current_car, acsys.CS.Gas)
      brake_value = ac.getCarState(current_car, acsys.CS.Brake)
    end
  end
end

function acShutdown()
  saveConfig()
  closeSimInfo()
end

local theme = getConfigNumber("theme", 6)
if type(theme) ~= "number" then
  theme = 6
end
theme = math.max(3, math.min(7, theme))
local scale = getConfigNumber("scale", 100.0) / 100.0
local unit_kmh = getConfigBool("unit_kmh", true)
local show_drift = getConfigBool("show_drift", true)
local show_pedal = getConfigBool("show_pedal", true)
local redLimit_offset = getConfigNumber("redLimit_offset", 2000)
local fixed_speedo_color = getConfigBool("fixed_speedo_color", false)
local lower_refresh_rate = getConfigBool("lower_refresh_rate", false)

saveConfig()

local active_theme_dir = joinPath(themes_root, string.format("D%d", theme))
local theme_config = readIni(joinPath(active_theme_dir, "theme_config.ini"))

local function themeBool(section, key, default)
  local sec = theme_config[section]
  if not sec then
    return default
  end
  local parsed = parseBool(sec[key])
  if parsed == nil then
    return default
  end
  return parsed
end

local function themeNumber(section, key, default)
  local sec = theme_config[section]
  if not sec then
    return default
  end
  local value = tonumber(sec[key])
  if value == nil then
    return default
  end
  return value
end

local night_mode_available = themeBool("General", "night_mode_available", false)
local pedal_gauge_available = themeBool("General", "pedal_gauge_available", false)
local drift_light_available = themeBool("General", "drift_light_available", false)
local rev_light_available = themeBool("General", "rev_light_available", false)
local variable_speed_color = themeBool("General", "variable_speed_color", false)
local has_ae86_gauge = themeBool("General", "has_ae86_gauge", false)

local background_width = themeNumber("Background", "background_width", 335)
local background_height = themeNumber("Background", "background_height", 335)
local background_pedal_width = themeNumber("Background", "background_pedal_width", background_width)
local background_pedal_height = themeNumber("Background", "background_pedal_height", background_height)

local gear_x = themeNumber("Gear", "gear_x", 249)
local gear_y = themeNumber("Gear", "gear_y", 301)
local gear_width = themeNumber("Gear", "gear_width", 33)
local gear_height = themeNumber("Gear", "gear_height", 27)

local gauge_x = themeNumber("RPM Gauge", "gauge_x", 0)
local gauge_y = themeNumber("RPM Gauge", "gauge_y", 0)
local gauge_width = themeNumber("RPM Gauge", "gauge_width", 335)
local gauge_height = themeNumber("RPM Gauge", "gauge_height", 270)
local maxRpm_state_0 = themeNumber("RPM Gauge", "maxRpm_state_0", 500)
local maxRpm_state_1 = themeNumber("RPM Gauge", "maxRpm_state_1", 7000)
local maxRpm_state_2 = themeNumber("RPM Gauge", "maxRpm_state_2", 8000)
local maxRpm_state_3 = themeNumber("RPM Gauge", "maxRpm_state_3", 10000)
local maxRpm_state_4 = themeNumber("RPM Gauge", "maxRpm_state_4", 12000)
local maxRpm_state_5 = themeNumber("RPM Gauge", "maxRpm_state_5", 14000)
local maxRpm_state_6 = themeNumber("RPM Gauge", "maxRpm_state_6", 16000)

local degree_available = themeNumber("RPM Bar", "degree_available", 250)
local degree_offset = themeNumber("RPM Bar", "degree_offset", -125)
local rpm_x = themeNumber("RPM Bar", "rpm_x", 161.5)
local rpm_y = themeNumber("RPM Bar", "rpm_y", 21.5)
local rpm_width = themeNumber("RPM Bar", "rpm_width", 12)
local rpm_height = themeNumber("RPM Bar", "rpm_height", 175)
local rpm_center_x = themeNumber("RPM Bar", "rpm_center_x", 167.5)
local rpm_center_y = themeNumber("RPM Bar", "rpm_center_y", 167.5)

local speed_x = themeNumber("Speed", "speed_x", 130)
local speed_y = themeNumber("Speed", "speed_y", 282)
local speed_width = themeNumber("Speed", "speed_width", 38)
local speed_height = themeNumber("Speed", "speed_height", 35)
local speed_gap = themeNumber("Speed", "speed_gap", 0)

local unit_x = themeNumber("Speed Unit", "unit_x", 166)
local unit_y = themeNumber("Speed Unit", "unit_y", 297)
local unit_width = themeNumber("Speed Unit", "unit_width", 68)
local unit_height = themeNumber("Speed Unit", "unit_height", 24)

local gas_x = 0
local gas_y = 0
local gas_width = 0
local gas_height = 0
local brake_x = 0
local brake_y = 0
local brake_width = 0
local brake_height = 0
local degree_gas = 0
local degree_brake = 0
local pedal_offset = 0

if pedal_gauge_available then
  gas_x = themeNumber("Pedal", "gas_x", 375)
  gas_y = themeNumber("Pedal", "gas_y", 107.5)
  gas_width = themeNumber("Pedal", "gas_width", 77.5)
  gas_height = themeNumber("Pedal", "gas_height", 155)
  brake_x = themeNumber("Pedal", "brake_x", 375)
  brake_y = themeNumber("Pedal", "brake_y", 132.5)
  brake_width = themeNumber("Pedal", "brake_width", 52.5)
  brake_height = themeNumber("Pedal", "brake_height", 105)
  degree_gas = themeNumber("Pedal", "degree_gas", 135)
  degree_brake = themeNumber("Pedal", "degree_brake", 135)
  pedal_offset = themeNumber("Pedal", "pedal_offset", 3)
end

local drift_x = 0
local drift_y = 0
local drift_width = 0
local drift_height = 0

if drift_light_available then
  drift_x = themeNumber("Drift Light", "drift_x", 0)
  drift_y = themeNumber("Drift Light", "drift_y", 0)
  drift_width = themeNumber("Drift Light", "drift_width", 0)
  drift_height = themeNumber("Drift Light", "drift_height", 0)
end

local rev_x = 0
local rev_y = 0
local rev_width = 0
local rev_height = 0

if rev_light_available then
  rev_x = themeNumber("Rev Light", "rev_x", 0)
  rev_y = themeNumber("Rev Light", "rev_y", 0)
  rev_width = themeNumber("Rev Light", "rev_width", 0)
  rev_height = themeNumber("Rev Light", "rev_height", 0)
end

local preview_path = joinPath(active_theme_dir, "preview.png")

local info = nil

local function closeSimInfo()
  if info and info._maps then
    local C = info._c
    for _, map in ipairs(info._maps) do
      if map.view and map.view ~= info._ffi.NULL then
        C.UnmapViewOfFile(map.view)
      end
      if map.handle and map.handle ~= info._ffi.NULL then
        C.CloseHandle(map.handle)
      end
    end
    info = nil
  end
end

do
  local ok, ffi = pcall(require, "ffi")
  if ok then
    local C = ffi.C
    ffi.cdef[[
      typedef void* HANDLE;
      typedef unsigned long DWORD;
      typedef const char* LPCSTR;
      HANDLE OpenFileMappingA(DWORD dwDesiredAccess, int bInheritHandle, LPCSTR lpName);
      void* MapViewOfFile(HANDLE hFileMappingObject, DWORD dwDesiredAccess, DWORD dwFileOffsetHigh, DWORD dwFileOffsetLow, size_t dwNumberOfBytesToMap);
      int UnmapViewOfFile(void* lpBaseAddress);
      int CloseHandle(HANDLE hObject);
#pragma pack(push, 4)
      typedef struct {
        int packetId;
        float gas;
        float brake;
        float fuel;
        int gear;
        int rpms;
        float steerAngle;
        float speedKmh;
        float velocity[3];
        float accG[3];
        float wheelSlip[4];
        float wheelLoad[4];
        float wheelsPressure[4];
        float wheelAngularSpeed[4];
        float tyreWear[4];
        float tyreDirtyLevel[4];
        float tyreCoreTemperature[4];
        float camberRAD[4];
        float suspensionTravel[4];
        float drs;
        float tc;
        float heading;
        float pitch;
        float roll;
        float cgHeight;
        float carDamage[5];
        int numberOfTyresOut;
        int pitLimiterOn;
        float abs;
        float kersCharge;
        float kersInput;
        int autoShifterOn;
        float rideHeight[2];
        float turboBoost;
        float ballast;
        float airDensity;
        float airTemp;
        float roadTemp;
        float localAngularVel[3];
        float finalFF;
        float performanceMeter;
        int engineBrake;
        int ersRecoveryLevel;
        int ersPowerLevel;
        int ersHeatCharging;
        int ersIsCharging;
        float kersCurrentKJ;
        int drsAvailable;
        int drsEnabled;
        float brakeTemp[4];
        float clutch;
        float tyreTempI[4];
        float tyreTempM[4];
        float tyreTempO[4];
        int isAIControlled;
        float tyreContactPoint[4][3];
        float tyreContactNormal[4][3];
        float tyreContactHeading[4][3];
        float brakeBias;
        float localVelocity[3];
      } SPageFilePhysics;

      typedef struct {
        int packetId;
        int status;
        int session;
        wchar_t currentTime[15];
        wchar_t lastTime[15];
        wchar_t bestTime[15];
        wchar_t split[15];
        int completedLaps;
        int position;
        int iCurrentTime;
        int iLastTime;
        int iBestTime;
        float sessionTimeLeft;
        float distanceTraveled;
        int isInPit;
        int currentSectorIndex;
        int lastSectorTime;
        int numberOfLaps;
        wchar_t tyreCompound[33];
        float replayTimeMultiplier;
        float normalizedCarPosition;
        float carCoordinates[3];
        float penaltyTime;
        int flag;
        int idealLineOn;
        int isInPitLine;
        float surfaceGrip;
        int mandatoryPitDone;
        float windSpeed;
        float windDirection;
      } SPageFileGraphic;

      typedef struct {
        wchar_t smVersion[15];
        wchar_t acVersion[15];
        int numberOfSessions;
        int numCars;
        wchar_t carModel[33];
        wchar_t track[33];
        wchar_t playerName[33];
        wchar_t playerSurname[33];
        wchar_t playerNick[33];
        int sectorCount;
        float maxTorque;
        float maxPower;
        int maxRpm;
        float maxFuel;
        float suspensionMaxTravel[4];
        float tyreRadius[4];
        float maxTurboBoost;
        float airTemp;
        float roadTemp;
        int penaltiesEnabled;
        float aidFuelRate;
        float aidTireRate;
        float aidMechanicalDamage;
        int aidAllowTyreBlankets;
        float aidStability;
        int aidAutoClutch;
        int aidAutoBlip;
        int hasDRS;
        int hasERS;
        int hasKERS;
        float kersMaxJ;
        int engineBrakeSettingsCount;
        int ersPowerControllerCount;
        float trackSPlineLength;
        wchar_t trackConfiguration[33];
        float ersMaxJ;
        int isTimedRace;
        int hasExtraLap;
        wchar_t carSkin[33];
        int reversedGridPositions;
        int pitWindowStart;
        int pitWindowEnd;
      } SPageFileStatic;
#pragma pack(pop)
    ]]

    local FILE_MAP_READ = 0x0004

    local function openMapping(name, typeName)
      local size = ffi.sizeof(typeName)
      local handle = C.OpenFileMappingA(FILE_MAP_READ, 0, name)
      if handle == nil or handle == ffi.NULL then
        return nil
      end
      local view = C.MapViewOfFile(handle, FILE_MAP_READ, 0, 0, size)
      if view == nil or view == ffi.NULL then
        C.CloseHandle(handle)
        return nil
      end
      return {handle = handle, view = view, ptr = ffi.cast(typeName .. "*", view)}
    end

    local static_map = openMapping("acpmf_static", "SPageFileStatic")
    local graphics_map = openMapping("acpmf_graphics", "SPageFileGraphic")
    if static_map and graphics_map then
      info = {
        _ffi = ffi,
        _c = C,
        static = static_map.ptr,
        graphics = graphics_map.ptr,
        _maps = {static_map, graphics_map}
      }
    else
      if static_map then
        C.UnmapViewOfFile(static_map.view)
        C.CloseHandle(static_map.handle)
      end
      if graphics_map then
        C.UnmapViewOfFile(graphics_map.view)
        C.CloseHandle(graphics_map.handle)
      end
    end
  end
end
