--[[
    PartyCare Windower Party Status Cache

    Windower exposes remote party status effects through incoming packet 0x076.
    This cache preserves the packet-backed records by server ID so remedy alerts
    use the same authoritative party status source as established Windower
    party-list add-ons. The packet covers remote members of the active party;
    alliance members beyond that packet scope remain status-unknown.
]]
local Cache = {};

local statuses_by_server_id = {};

local function read_u32_le(data, offset)
    local b1, b2, b3, b4 = data:byte(offset, offset + 3);
    if not b4 then return nil; end
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216;
end

function Cache.update(original)
    if type(original) ~= 'string' then return false; end
    local next_statuses = {};

    -- Packet 0x076 carries five 48-byte remote-party records. Offsets follow
    -- the established Windower pattern: ID at record+5, high status bits at
    -- record+13, and low status bytes at record+21.
    for record = 0, 4 do
        local base = record * 48;
        local server_id = read_u32_le(original, base + 5);
        if server_id and server_id > 0 then
            local statuses = {};
            for index = 1, 32 do
                local high_source = original:byte(base + 5 + 8 + math.floor((index - 1) / 4));
                local low = original:byte(base + 5 + 16 + index - 1);
                if not high_source or not low then break; end
                local high = math.floor(high_source / (4 ^ ((index - 1) % 4))) % 4;
                local status_id = high * 256 + low;
                if status_id == 255 then break; end
                if status_id > 0 then table.insert(statuses, status_id); end
            end
            next_statuses[server_id] = statuses;
        end
    end

    statuses_by_server_id = next_statuses;
    return true;
end

function Cache.get(server_id)
    return statuses_by_server_id[tonumber(server_id)];
end

function Cache.clear()
    statuses_by_server_id = {};
end

return Cache;
