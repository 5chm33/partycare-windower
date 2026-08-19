_addon.name = 'partycare'
_addon.author = 'Schmeee'
_addon.version = '1.2.0-windower'
_addon.commands = {'partycare', 'pc'}
_addon.desc = 'Manual party and alliance healing and remedy panel for Windower.'

local Config = require('src.config')
local PanelModel = require('src.panel_model')
local SettingsStore = require('src.settings_store')
local PartyProvider = require('src.windower_party_provider')
local DispatchAdapter = require('src.windower_dispatch_adapter')
local Shell = require('src.windower_shell')

local state = {model = nil, shell = Shell.new(), dispatch = DispatchAdapter.new(), next_snapshot = 0, settings_path = windower.addon_path .. 'settings.lua'}

local function message(text)
    windower.add_to_chat(207, '[PartyCare] ' .. text)
end

local function load_settings()
    local chunk = loadfile(state.settings_path)
    if not chunk then return Config.DEFAULT end
    local ok, raw = pcall(chunk)
    if not ok then message('Settings could not be read; using defaults.'); return Config.DEFAULT end
    local config, errors = Config.validate(raw)
    if not config then message('Settings are invalid; using defaults.'); return Config.DEFAULT end
    return config
end

local function save_settings()
    if not state.model then return false, 'panel unavailable' end
    return SettingsStore.save(state.settings_path, state.model:export_config())
end

local function update_members()
    local members = PartyProvider.snapshot()
    if members then state.model:update_members(members) else state.model:update_members({}) end
end

local function dispatch_audit(audit)
    for _, intent in ipairs(audit or {}) do
        if intent.kind == 'MANUAL_CLICK_CAST_REQUEST' then state.dispatch:dispatch(intent, state.model:view().config.live_test) end
    end
end

windower.register_event('load', function()
    local model, errors = PanelModel.new(load_settings())
    if not model then error(table.concat(errors, '; ')) end
    state.model = model
    message('Loaded. Use //partycare or //pc for settings.')
end)

windower.register_event('prerender', function()
    if not state.model then return end
    local now = os.clock()
    if now >= state.next_snapshot then update_members(); state.next_snapshot = now + 0.25 end
    local _, shell_error = state.shell:render(state.model, now)
    if shell_error then message(shell_error) end
    dispatch_audit(state.model:drain_audit())
end)

windower.register_event('mouse', function(kind, x, y, delta, blocked)
    if not state.model then return false end
    local consumed = state.shell:handle_mouse(state.model, kind, x, y, blocked, os.clock())
    if consumed then dispatch_audit(state.model:drain_audit()) end
    return consumed
end)

windower.register_event('addon command', function(command, ...)
    if not state.model then return end
    command = (command or ''):lower()
    local args = {...}
    if command == '' or command == 'config' or command == 'settings' then
        state.model:update_config(function(candidate) candidate.ui.settings_open = not candidate.ui.settings_open end)
    elseif command == 'save' then
        local ok, err = save_settings(); if not ok then message('Unable to save settings: ' .. tostring(err)) end
    elseif command == 'dispatch' then
        local value = tostring(args[1] or ''):lower()
        if value == 'on' or value == 'off' then
            state.model:update_config(function(candidate)
                candidate.live_test.manual_dispatch_enabled = value == 'on'
                candidate.live_test.emergency_stop = value ~= 'on'
            end)
        else
            message('Use //pc dispatch on or //pc dispatch off.')
        end
    elseif command == 'hide' or command == 'show' then
        state.model:update_config(function(candidate) candidate.ui.visible = command == 'show' end)
    else
        message('Commands: //pc, //pc save, //pc dispatch on|off, //pc show|hide')
    end
end)

windower.register_event('unload', function()
    if state.shell then state.shell:dispose() end
    save_settings()
end)
