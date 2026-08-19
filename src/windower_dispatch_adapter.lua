local Util = require('src.util');

local Adapter = {};
Adapter.__index = Adapter;

local function safe_spell(spell)
    return Util.is_nonempty_string(spell) and spell:match("^[%a%d %-%']+$") ~= nil;
end

local function target_token(slot)
    if not Util.is_integer(slot) or slot < 0 or slot > 17 then return nil, 'party slot must be an integer from 0 to 17'; end
    if slot <= 5 then return string.format('<p%d>', slot), nil; end
    if slot <= 11 then return string.format('<a1%d>', slot - 6), nil; end
    return string.format('<a2%d>', slot - 12), nil;
end

function Adapter.new()
    return setmetatable({audit = {}}, Adapter);
end

function Adapter.build_command(intent)
    if type(intent) ~= 'table' or intent.kind ~= 'MANUAL_CLICK_CAST_REQUEST' then return nil, 'unsupported intent'; end
    if not safe_spell(intent.spell) then return nil, 'spell contains unsupported characters'; end
    local target, target_error = target_token(intent.party_slot);
    if not target then return nil, target_error; end
    return string.format('/ma "%s" %s', intent.spell, target), nil;
end

function Adapter:dispatch(intent, live_test)
    if type(live_test) ~= 'table' or live_test.manual_dispatch_enabled ~= true then return false, 'manual dispatch is disabled'; end
    if live_test.emergency_stop == true then return false, 'emergency stop is active'; end
    if type(windower) ~= 'table' or type(windower.send_command) ~= 'function' then return false, 'Windower command API is unavailable'; end
    local command, command_error = Adapter.build_command(intent);
    if not command then return false, command_error; end
    windower.send_command('input ' .. command);
    table.insert(self.audit, {sequence = intent.sequence, command = command, member_name = intent.member_name, spell = intent.spell});
    return true, command;
end

function Adapter:drain_audit()
    local audit = self.audit;
    self.audit = {};
    return audit;
end

return Adapter;
