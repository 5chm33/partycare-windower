local Provider = {};

local PARTY_KEYS = {'p%d', 'a1%d', 'a2%d'};

local function group_for_slot(slot)
    return math.floor(slot / 6) + 1;
end

function Provider.available()
    return type(windower) == 'table' and type(windower.ffxi) == 'table' and type(windower.ffxi.get_party) == 'function';
end

function Provider.snapshot()
    if not Provider.available() then return nil, 'Windower party API is unavailable'; end
    local party = windower.ffxi.get_party();
    if type(party) ~= 'table' then return nil, 'Windower returned no party snapshot'; end

    local members = {};
    for slot = 0, 17 do
        local group = group_for_slot(slot);
        local key = string.format(PARTY_KEYS[group], slot % 6);
        local source = party[key];
        if type(source) == 'table' and type(source.name) == 'string' and source.name:match('%S') then
            local hp_percent = tonumber(source.hpp) or 0;
            local mp_percent = tonumber(source.mpp) or 0;
            table.insert(members, {
                id = (source.mob and source.mob.id) or source.id or (100000 + slot),
                name = source.name,
                party_slot = slot,
                alliance_group = group,
                hp = hp_percent,
                hp_max = 100,
                mp = mp_percent,
                mp_max = 100,
                status = '',
                -- Windower party snapshots do not provide an equivalent remote party-status stream.
                debuffs = {},
            });
        end
    end
    return members, nil;
end

return Provider;
