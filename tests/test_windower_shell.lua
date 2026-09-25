package.path = './?.lua;./?/init.lua;' .. package.path

local widgets = {}
texts = {
    new = function(_, defaults)
        local widget = {shown = false, hidden = false, defaults = defaults}
        function widget:show() self.shown, self.hidden = true, false end
        function widget:hide() self.shown, self.hidden = false, true end
        function widget:text(value) self.value = value end
        function widget:pos(x, y) self.x, self.y = x, y end
        function widget:size(value) self.font_size = value end
        function widget:color(r, g, b) self.color = {r, g, b} end
        function widget:bg_alpha(value) self.background_alpha = value end
        table.insert(widgets, widget)
        return widget
    end,
}

local Config = require('src.config')
local Shell = require('src.windower_shell')
local config = Config.DEFAULT
local member = {
    id = 7, name = 'TestMember', hp_percent = 100, mp_percent = 50, mp_max = 100,
    alliance_group = 1, remedy_recommendation = nil,
}
local model = {view = function() return {config = config, members = {member}} end}
local shell = Shell.new()

local ok, err = shell:render(model, 0)
assert(ok and not err, 'visible render should succeed')
assert(#shell.hitboxes == 1, 'visible render should create a hitbox')
assert(#widgets >= 2, 'visible render should create a card and settings widget')
local card = shell.cards.member_7.text
assert(card.shown, 'visible card should be shown')

local hidden_config = {}
for key, value in pairs(config) do hidden_config[key] = value end
hidden_config.ui = {}
for key, value in pairs(config.ui) do hidden_config.ui[key] = value end
hidden_config.ui.visible = false
model.view = function() return {config = hidden_config, members = {member}} end

ok, err = shell:render(model, 1)
assert(ok and not err, 'hidden render should succeed')
assert(#shell.hitboxes == 0, 'hidden render should clear all hitboxes')
assert(next(shell.cards) == nil, 'hidden render should dispose all cards')
assert(shell.settings.hidden, 'hidden render should hide settings widget')
assert(card.hidden, 'previously visible card should be hidden')

print('windower shell visibility test passed')
