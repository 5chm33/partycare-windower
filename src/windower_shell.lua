local ResourceStyle = require('src.resource_style');

local Shell = {};
Shell.__index = Shell;

local function color_for_resource(percent, kind, config)
    local color = kind == 'hp' and ResourceStyle.hp_color(percent, config.thresholds.warning_hp, config.thresholds.critical_hp) or ResourceStyle.mp_color(percent);
    return math.floor(color[1] * 255), math.floor(color[2] * 255), math.floor(color[3] * 255);
end

local function bar(percent, width)
    local filled = math.max(0, math.min(width, math.floor(percent * width + 0.5)));
    return string.rep('|', filled) .. string.rep('.', width - filled);
end

local function group_members(members, config)
    local groups = {{id = 1, label = 'Party', members = {}}};
    if config.ui.show_alliance_2 then table.insert(groups, {id = 2, label = 'Alliance 2', members = {}}); end
    if config.ui.show_alliance_3 then table.insert(groups, {id = 3, label = 'Alliance 3', members = {}}); end
    local lookup = {};
    for _, group in ipairs(groups) do lookup[group.id] = group; end
    for _, member in ipairs(members) do
        local group = lookup[member.alliance_group or 1];
        if group and (not config.ui.debuff_alert_mode or member.remedy_recommendation ~= nil) then table.insert(group.members, member); end
    end
    local visible = {};
    for _, group in ipairs(groups) do if #group.members > 0 then table.insert(visible, group); end end
    return visible;
end

local function make_text(defaults)
    local widget = texts.new('', defaults);
    widget:show();
    return widget;
end

function Shell.new()
    return setmetatable({cards = {}, settings = nil, hitboxes = {}}, Shell);
end

function Shell:available()
    return type(texts) == 'table' and type(texts.new) == 'function';
end

function Shell:dispose()
    for _, card in pairs(self.cards) do if card.text then card.text:hide(); end end
    if self.settings then self.settings:hide(); end
    self.cards, self.hitboxes = {}, {};
end

function Shell:ensure_settings()
    if not self.settings then self.settings = make_text({font = 'Consolas', size = 10, alpha = 255, bg_alpha = 180, bg_red = 10, bg_green = 15, bg_blue = 24}); end
end

function Shell:ensure_card(key)
    if not self.cards[key] then
        self.cards[key] = {text = make_text({font = 'Consolas', size = 10, alpha = 255, bg_alpha = 145, bg_red = 12, bg_green = 20, bg_blue = 34})};
    end
    return self.cards[key];
end

function Shell:render(model, now)
    if not self:available() then return nil, 'Windower texts library is unavailable'; end
    local view, config = model:view(), model:view().config;
    local used = {};
    self.hitboxes = {};
    local x, y = config.ui.x, config.ui.y;
    local width, height, columns = config.ui.card_width, config.ui.card_height, config.ui.grid_columns;
    local scale = config.ui.font_scale or 1;
    local groups = group_members(view.members, config);
    local compact_idle = config.ui.debuff_alert_mode and #groups == 0;

    if compact_idle and not config.ui.debuff_alert_preview then
        for _, card in pairs(self.cards) do card.text:hide(); end
        self:ensure_settings();
        if config.ui.settings_open then
            self.settings:text('PartyCare Windower settings\n\nCompact alert is idle-hidden.\nUse //pc alertpreview on to show a placement box.\nUse //pc alertpos <x> <y> to move it.\n\nUse //pc help for Refresh pulse and compact commands.');
            self.settings:pos(config.ui.settings_x, config.ui.settings_y); self.settings:show();
        else self.settings:hide(); end
        return true, nil;
    end

    if compact_idle then
        local preview = self:ensure_card('compact_preview');
        used.compact_preview = true;
        preview.text:text(string.rep(' ', math.max(8, math.floor(width / 6))));
        preview.text:pos(x, y); preview.text:size(math.max(8, math.floor(10 * scale)));
        preview.text:color(100, 100, 100); preview.text:bg_alpha(math.floor(math.max(0.15, config.ui.background_alpha) * 255)); preview.text:show();
    else
        for group_index, group in ipairs(groups) do
            if #groups > 1 and not config.ui.debuff_alert_mode then
                local header = self:ensure_card('header_' .. group.id);
                used['header_' .. group.id] = true;
                header.text:text(group.label); header.text:pos(x, y); header.text:color(170, 200, 255); header.text:size(math.max(8, math.floor(10 * scale))); header.text:show();
                y = y + 16 * scale;
            end
            for index, member in ipairs(group.members) do
                local column = config.ui.debuff_alert_mode and 0 or (index - 1) % columns;
                local row = config.ui.debuff_alert_mode and (index - 1) or math.floor((index - 1) / columns);
                local cx, cy = x + column * (width + 8), y + row * (height + 6);
                local key = 'member_' .. tostring(member.id);
                local card = self:ensure_card(key);
                used[key] = true;
                local lines, card_height = {}, height;
                if config.ui.debuff_alert_mode then
                    local recommendation = member.remedy_recommendation;
                    lines = {member.name, 'Remedy: ' .. recommendation.spell .. ' (' .. recommendation.debuff .. ')'};
                    local pulse = (math.sin((tonumber(now) or 0) * 4.0) + 1) / 2;
                    card.text:color(math.floor(160 + pulse * 95), math.floor(10 + pulse * 20), math.floor(10 + pulse * 20));
                    card.text:bg_alpha(math.floor((0.55 + pulse * 0.30) * 255));
                    card_height = 36 * scale;
                    self.hitboxes[#self.hitboxes + 1] = {member = member, kind = 'direct', x = cx, y = cy, width = width, height = 18 * scale};
                    self.hitboxes[#self.hitboxes + 1] = {member = member, kind = 'remedy', x = cx, y = cy + 18 * scale, width = width, height = 18 * scale};
                else
                    local hp_r, hp_g, hp_b = color_for_resource(member.hp_percent / 100, 'hp', config);
                    lines = {member.name, string.format('HP %s %3d%%', bar(member.hp_percent / 100, 16), member.hp_percent)};
                    if config.ui.show_mp and member.mp_max > 0 then table.insert(lines, string.format('MP %s %3d%%', bar(member.mp_percent / 100, 16), member.mp_percent)); end
                    if config.ui.show_remedy_button and member.remedy_recommendation then table.insert(lines, 'Remedy: ' .. member.remedy_recommendation.spell .. ' (' .. member.remedy_recommendation.debuff .. ')'); end
                    card.text:color(hp_r, hp_g, hp_b); card.text:bg_alpha(math.floor(config.ui.background_alpha * 255));
                    self.hitboxes[#self.hitboxes + 1] = {member = member, kind = 'direct', x = cx, y = cy, width = width, height = card_height};
                end
                card.text:text(table.concat(lines, '\n')); card.text:pos(cx, cy); card.text:size(math.max(8, math.floor(10 * scale))); card.text:show();
            end
            local rows = config.ui.debuff_alert_mode and #group.members or math.ceil(#group.members / columns);
            y = y + rows * ((config.ui.debuff_alert_mode and 36 or height) + 6) + (#groups > 1 and 6 or 0);
        end
    end

    for key, card in pairs(self.cards) do if not used[key] then card.text:hide(); end end
    self:ensure_settings();
    if config.ui.settings_open then
        self.settings:text('PartyCare Windower settings\n\nUse //pc help for commands.\nRefresh pulse: //pc refreshpulse on|off\nCompact alert: //pc compact on|off\nPlacement preview: //pc alertpreview on|off\nMove preview: //pc alertpos <x> <y>\n\nCurrent: ' .. (config.direct_click.enabled and 'Direct click enabled' or 'Direct click disabled'));
        self.settings:pos(config.ui.settings_x, config.ui.settings_y); self.settings:show();
    else self.settings:hide(); end
    return true, nil;
end

function Shell:handle_mouse(model, event_type, x, y, blocked, now)
    if blocked then return false; end
    local button = ({[2] = 'left', [5] = 'right', [8] = 'middle'})[event_type];
    if not button then return false; end
    for _, box in ipairs(self.hitboxes) do
        if x >= box.x and x <= box.x + box.width and y >= box.y and y <= box.y + box.height then
            if box.kind == 'remedy' then model:select_member(box.member.id); model:request_remedy(now);
            else model:request_direct_click(box.member.id, button, now); end
            return true;
        end
    end
    return false;
end

return Shell;
