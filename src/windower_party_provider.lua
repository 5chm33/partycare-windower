local Provider = {};
local StatusCache = require('src.windower_party_status_cache');

local PARTY_KEYS = {'p%d', 'a1%d', 'a2%d'};
local REFRESH_STATUS_ID = 43;

local STATUS_TO_REMEDY_RULE = {
    [3] = 'poison', [4] = 'paralyze', [5] = 'blind', [6] = 'silence',
    [7] = 'petrify', [8] = 'disease', [9] = 'curse', [10] = 'stun',
    [11] = 'bind', [12] = 'gravity', [13] = 'slow', [15] = 'doom', [21] = 'addle', [31] = 'plague',
    [128] = 'elemental_dot', [129] = 'elemental_dot', [130] = 'elemental_dot',
    [131] = 'elemental_dot', [132] = 'elemental_dot', [133] = 'elemental_dot',
    [134] = 'dia', [135] = 'bio',
    -- Suppress generic stat-down icons until a platform-specific verified
    -- remedy mapping is available; a single broad Erase rule is ambiguous.
    [156] = 'flash', [186] = 'helix', [192] = 'requiem', [194] = 'elegy',
};

local function group_for_slot(slot)
    return math.floor(slot / 6) + 1;
end

local function get_resources()
    local ok, resources = pcall(require, 'resources');
    return ok and type(resources) == 'table' and resources or nil;
end

local function bool(value)
    if type(value) == 'boolean' then return value; end
    if type(value) == 'number' then return value ~= 0; end
    return nil;
end

local function spell_availability(remedy_rules)
    local known = type(windower) == 'table' and type(windower.ffxi) == 'table'
        and type(windower.ffxi.get_spells) == 'function' and windower.ffxi.get_spells() or nil;
    local resources = get_resources();
    local availability = {};
    if type(known) ~= 'table' or not resources or type(resources.spells) ~= 'table' then return availability; end

    local ids_by_name = {};
    for spell_id, spell in pairs(resources.spells) do
        if type(spell) == 'table' and type(spell.en) == 'string' then ids_by_name[spell.en] = tonumber(spell.id or spell_id); end
    end
    for _, rule in pairs(remedy_rules or {}) do
        local name = type(rule) == 'table' and rule.spell or nil;
        local spell_id = name and ids_by_name[name];
        if spell_id and availability[name] == nil then
            local value = known[spell_id];
            local has = bool(value);
            if has ~= nil then availability[name] = has; end
        end
    end
    return availability;
end

local function decode_statuses(statuses)
    if type(statuses) ~= 'table' then return {}, 0, false, false, false; end
    local debuffs, found, count, has_refresh = {}, {}, 0, false;
    for index = 1, 32 do
        local status_id = tonumber(statuses[index]);
        if status_id == 255 then break; end
        if status_id and status_id > 0 then
            count = count + 1;
            if status_id == REFRESH_STATUS_ID then has_refresh = true; end
            local rule_id = STATUS_TO_REMEDY_RULE[status_id];
            if rule_id and not found[rule_id] then found[rule_id] = true; table.insert(debuffs, rule_id); end
        end
    end
    table.sort(debuffs);
    return debuffs, count, true, has_refresh, true;
end

function Provider.available()
    return type(windower) == 'table' and type(windower.ffxi) == 'table' and type(windower.ffxi.get_party) == 'function';
end

function Provider.update_status_packet(original)
    return StatusCache.update(original);
end

function Provider.clear_status_cache()
    StatusCache.clear();
end

function Provider.snapshot(remedy_rules)
    if not Provider.available() then return nil, 'Windower party API is unavailable'; end
    local party = windower.ffxi.get_party();
    if type(party) ~= 'table' then return nil, 'Windower returned no party snapshot'; end
    local player = type(windower.ffxi.get_player) == 'function' and windower.ffxi.get_player() or nil;
    local local_id = type(player) == 'table' and tonumber(player.id) or nil;
    local local_buffs = type(player) == 'table' and player.buffs or nil;
    local availability = spell_availability(remedy_rules);

    local members = {};
    for slot = 0, 17 do
        local group = group_for_slot(slot);
        local key = string.format(PARTY_KEYS[group], slot % 6);
        local source = party[key];
        if type(source) == 'table' and type(source.name) == 'string' and source.name:match('%S') then
            local id = tonumber((source.mob and source.mob.id) or source.id) or (100000 + slot);
            local status_values = nil;
            local status_source = '';
            if local_id and id == local_id and type(local_buffs) == 'table' then
                status_values = local_buffs;
                status_source = 'local_player_buffs';
            elseif group == 1 then
                status_values = StatusCache.get(id);
                status_source = status_values and 'party_status_packet_0x076' or '';
            end
            local debuffs, status_count, available, has_refresh, refresh_known = decode_statuses(status_values);
            local actual_mp = tonumber(source.mp) or tonumber(source.mpp) or 0;
            local actual_mp_max = tonumber(source.mp_max) or tonumber(source.max_mp) or 0;
            if actual_mp_max <= 0 then
                -- Percentage values retain normal bar rendering but are intentionally not used for Refresh alerts.
                actual_mp, actual_mp_max = tonumber(source.mpp) or 0, 100;
            end
            table.insert(members, {
                id = id,
                name = source.name,
                party_slot = slot,
                alliance_group = group,
                hp = tonumber(source.hp) or tonumber(source.hpp) or 0,
                hp_max = tonumber(source.hp_max) or tonumber(source.max_hp) or 100,
                mp = actual_mp,
                mp_max = actual_mp_max,
                status = '',
                debuffs = debuffs,
                status_feed_available = available,
                status_icon_count = status_count,
                status_source = status_source,
                has_refresh = has_refresh,
                refresh_known = refresh_known,
                spell_availability = availability,
            });
        end
    end
    return members, nil;
end

return Provider;
