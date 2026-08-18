--[[
    ========================================================================================================================
    ||                                                                                                                    ||
    ||                                               catboy.lua for gamesense                                             ||
    ||                                                    build: latest                                                   ||
    ||                                                 date: April 9, 2026                                                ||
    ||                                                                                                                    ||
    ========================================================================================================================
    ||  credits:                                                                                                          ||
    ||  - althea (lanes)                        [lead dev]                                                                ||
    ||  - mar (pecroz)                          [suggesting ideas + pointing out bugs]                                    ||
    ||  - sleepycatboy                          [suggesting ideas + pointing out bugs]                                    ||
    ||  - RiseAndRage (davariousdeshawnhoodclips.2014) [major helper + ideas + bug testing]                               ||
    ||                                                                                                                    ||
    ========================================================================================================================
    ||  changelog:                                                                                                        ||
    ||                                                                                                                    ||
    ||  [2026-04-09]                                                                                                      ||
    ||  [+] Added invert chance (chance before inverting)                                                                 ||
    ||  [+] Added enhanced grenade release                                                                                ||
    ||  [+] Added auto buy                                                                                                ||
    ||  [+] Added x-way jitter for defensive                                                                              ||
    ||  [+] Added automatic body yaw when x-way jitter is enabled                                                         ||
    ||  [*] Optimized codebase & cleaned up functions                                                                     ||
    ||                                                                                                                    ||
    ||  [previous updates]                                                                                                ||
    ||  [*] fuck if i know                                                                                                ||
    ||                                                                                                                    ||
    ||  [2026-03-10]                                                                                                      ||
    ||  [!] initial gamesense build release                                                                               ||
    ||                                                                                                                    ||
    ========================================================================================================================
]]

local ffi = require 'ffi'
local vector = require 'vector'
local inspect = require 'gamesense/inspect'
local base64 = require 'gamesense/base64'
local clipboard = require 'gamesense/clipboard'
local c_entity = require 'gamesense/entity'
local csgo_weapons = require 'gamesense/csgo_weapons'
local trace = require 'gamesense/trace'
local antiaim_funcs = require 'gamesense/antiaim_funcs'
local images = require 'gamesense/images'
local http = require 'gamesense/http'
local surface = require 'gamesense/surface'
local gif_decoder = require 'gamesense/gif_decoder'

math.exploit = function ()
    local me = entity.get_local_player()
    if not me then return end
    local tickcount = globals.tickcount()
    local tickbase = entity.get_prop(me, 'm_nTickBase')
    return tickcount > tickbase
end

local function round(x)
    return math.floor(x + 0.5)
end

local function contains(list, value)
    for i = 1, #list do
        if list[i] == value then
            return i
        end
    end

    return nil
end

local script do
    script = { }

    local user = nil
    local build = nil

    if _USER_NAME ~= nil then
        user = _USER_NAME
    end

    if _SCRIPT_NAME ~= nil then
        build = string.match(
            _SCRIPT_NAME, 'catboy (.*)'
        )
    end

    if user == nil then
        user = 'althea'
    end

    if build == nil then
        build = 'dev'
    end

    script.name = 'catboy' do
        script.user = user
        script.build = build
    end
end

local utils do
    utils = { }

    function utils.clamp(x, min, max)
        return math.max(min, math.min(x, max))
    end

    function utils.lerp(a, b, t)
        return a + t * (b - a)
    end

    function utils.inverse_lerp(a, b, x)
        return (x - a) / (b - a)
    end

    function utils.map(x, in_min, in_max, out_min, out_max, should_clamp)
        if should_clamp then
            x = utils.clamp(x, in_min, in_max)
        end

        local rel = utils.inverse_lerp(in_min, in_max, x)
        local value = utils.lerp(out_min, out_max, rel)

        return value
    end

    function utils.normalize(x, min, max)
        local d = max - min

        while x < min do
            x = x + d
        end

        while x > max do
            x = x - d
        end

        return x
    end

    function utils.trim(str)
        return str
    end

    function utils.from_hex(hex)
        hex = string.gsub(hex, '#', '')

        local r = tonumber(string.sub(hex, 1, 2), 16)
        local g = tonumber(string.sub(hex, 3, 4), 16)
        local b = tonumber(string.sub(hex, 5, 6), 16)
        local a = tonumber(string.sub(hex, 7, 8), 16)

        return r, g, b, a or 255
    end

    function utils.to_hex(r, g, b, a)
        return string.format('%02x%02x%02x%02x', r, g, b, a)
    end

    function utils.event_callback(event_name, callback, value)
        if callback == nil or event_name == nil then
            return
        end

        local fn = value and client.set_event_callback
            or client.unset_event_callback

        fn(event_name, callback)
    end

    function utils.get_player_weapons(ent)
        local weapons = { }

        for i = 0, 63 do
            local weapon = entity.get_prop(
                ent, 'm_hMyWeapons', i
            )

            if weapon ~= nil then
                table.insert(weapons, weapon)
            end
        end

        return weapons
    end

    function utils.get_eye_position(ent)
        local origin_x, origin_y, origin_z = entity.get_origin(ent)
        local offset_x, offset_y, offset_z = entity.get_prop(ent, 'm_vecViewOffset')

        if origin_x == nil or offset_x == nil then
            return nil
        end

        local eye_pos_x = origin_x + offset_x
        local eye_pos_y = origin_y + offset_y
        local eye_pos_z = origin_z + offset_z

        return eye_pos_x, eye_pos_y, eye_pos_z
    end

    function utils.closest_ray_point(a, b, p, should_clamp)
        local ray_delta = p - a
        local line_delta = b - a

        local lengthsqr = line_delta.x * line_delta.x + line_delta.y * line_delta.y
        local dot_product = ray_delta.x * line_delta.x + ray_delta.y * line_delta.y

        local t = dot_product / lengthsqr

        if should_clamp then
            if t <= 0.0 then
                return a
            end

            if t >= 1.0 then
                return b
            end
        end

        return a + t * line_delta
    end

    function utils.extrapolate(pos, vel, ticks)
        return pos + vel * (ticks * globals.tickinterval())
    end

    function utils.random_int(min, max)
        if min > max then
            min, max = max, min
        end

        return client.random_int(min, max)
    end

    function utils.random_float(min, max)
        if min > max then
            min, max = max, min
        end

        return client.random_float(min, max)
    end

    function utils.find_signature(module_name, pattern, offset)
        local match = client.find_signature(module_name, pattern)

        if match == nil then
            return nil
        end

        if offset ~= nil then
            local address = ffi.cast('char*', match)
            address = address + offset

            return address
        end

        return match
    end
end

local BOOT_IMAGE_PATH = "boot.png"

local boot do
    boot = {
        image = nil,
        done = false,
        alpha = 0,
        duration = 2.5,
        start_time = 0,
    }

    local data = readfile(BOOT_IMAGE_PATH)
    if data then
        boot.image = images.load(data)
        boot.start_time = globals.realtime()
    else
        http.get('https://raw.githubusercontent.com/lanesuwu/catboy.lua/refs/heads/main/assets/boot.png', function(s, r)
            if s and r.status == 200 then
                writefile(BOOT_IMAGE_PATH, r.body)
                boot.image = images.load(r.body)
                boot.start_time = globals.realtime()
            end
        end)
    end
end

local software do
    software = { }

    software.ragebot = {
        weapon_type = ui.reference(
            'Rage', 'Weapon type', 'Weapon type'
        ),

        aimbot = {
            enabled = {
                ui.reference('Rage', 'Aimbot', 'Enabled')
            },

            double_tap = {
                ui.reference('Rage', 'Aimbot', 'Double tap')
            },

            minimum_hit_chance = ui.reference(
                'Rage', 'Aimbot', 'Minimum hit chance'
            ),

            minimum_damage = ui.reference(
                'Rage', 'Aimbot', 'Minimum damage'
            ),

            minimum_damage_override = {
                ui.reference('Rage', 'Aimbot', 'Minimum damage override')
            },

            prefer_safe_point = ui.reference(
                'Rage', 'Aimbot', 'Prefer safe point'
            ),

            quick_stop = {
                ui.reference('Rage', 'Aimbot', 'Quick stop')
            }
        },

        other = {
            accuracy_boost = ui.reference(
                'Rage', 'Other', 'Accuracy boost'
            ),

            remove_recoil = ui.reference(
                'Rage', 'Other', 'Remove recoil'
            ),

            delay_shot = ui.reference(
                'Rage', 'Other', 'Delay shot'
            ),

            quick_peek_assist = {
                ui.reference('Rage', 'Other', 'Quick peek assist')
            },

            duck_peek_assist = ui.reference(
                'Rage', 'Other', 'Duck peek assist'
            )
        }
    }

    software.antiaimbot = {
        angles = {
            enabled = ui.reference(
                'AA', 'Anti-aimbot angles', 'Enabled'
            ),

            pitch = {
                ui.reference('AA', 'Anti-aimbot angles', 'Pitch')
            },

            yaw_base = ui.reference(
                'AA', 'Anti-aimbot angles', 'Yaw base'
            ),

            yaw = {
                ui.reference('AA', 'Anti-aimbot angles', 'Yaw')
            },

            yaw_jitter = {
                ui.reference('AA', 'Anti-aimbot angles', 'Yaw jitter')
            },

            body_yaw = {
                ui.reference('AA', 'Anti-aimbot angles', 'Body yaw')
            },

            freestanding_body_yaw = ui.reference(
                'AA', 'Anti-aimbot angles', 'Freestanding body yaw'
            ),

            edge_yaw = ui.reference(
                'AA', 'Anti-aimbot angles', 'Edge yaw'
            ),

            freestanding = {
                ui.reference('AA', 'Anti-aimbot angles', 'Freestanding')
            },

            roll = ui.reference(
                'AA', 'Anti-aimbot angles', 'Roll'
            )
        },

        fake_lag = {
            enabled = {
                ui.reference('AA', 'Fake lag', 'Enabled')
            },

            amount = ui.reference(
                'AA', 'Fake lag', 'Amount'
            ),

            variance = ui.reference(
                'AA', 'Fake lag', 'Variance'
            ),

            limit = ui.reference(
                'AA', 'Fake lag', 'Limit'
            ),
        },

        other = {
            slow_motion = {
                ui.reference('AA', 'Other', 'Slow motion')
            },

            on_shot_antiaim = {
                ui.reference('AA', 'Other', 'On shot anti-aim')
            },

            fake_peek = {
                ui.reference('AA', 'Other', 'Fake peek')
            },

            leg_movement = ui.reference(
                'AA', 'Other', 'Leg movement'
            )
        }
    }

    software.visuals = {
        effects = {
            remove_scope_overlay = ui.reference(
                'Visuals', 'Effects', 'Remove scope overlay'
            )
        }
    }

    software.misc = {
        miscellaneous = {
            ping_spike = {
                ui.reference('Misc', 'Miscellaneous', 'Ping spike')
            }
        },

        movement = {
            air_strafe = ui.reference(
                'Misc', 'Movement', 'Air strafe'
            )
        },

        settings = {
            menu_color = ui.reference(
                'Misc', 'Settings', 'Menu color'
            )
        }
    }

    function software.get_color(to_hex)
        if to_hex then
            return utils.to_hex(ui.get(software.misc.settings.menu_color))
        end

        return ui.get(software.misc.settings.menu_color)
    end

    function software.get_override_damage()
        return ui.get(software.ragebot.aimbot.minimum_damage_override[3])
    end

    function software.get_minimum_damage()
        return ui.get(software.ragebot.aimbot.minimum_damage)
    end

    function software.is_slow_motion()
        return ui.get(software.antiaimbot.other.slow_motion[1])
            and ui.get(software.antiaimbot.other.slow_motion[2])
    end

    function software.is_duck_peek_active()
        return ui.get(software.ragebot.other.duck_peek_assist)
    end

    function software.is_double_tap_active()
        return ui.get(software.ragebot.aimbot.double_tap[1])
            and ui.get(software.ragebot.aimbot.double_tap[2])
    end

    function software.is_override_minimum_damage()
        return ui.get(software.ragebot.aimbot.minimum_damage_override[1])
            and ui.get(software.ragebot.aimbot.minimum_damage_override[2])
    end

    function software.is_on_shot_antiaim_active()
        return ui.get(software.antiaimbot.other.on_shot_antiaim[1])
            and ui.get(software.antiaimbot.other.on_shot_antiaim[2])
    end

    function software.is_duck_peek_assist()
        return ui.get(software.ragebot.other.duck_peek_assist)
    end

    function software.is_quick_peek_assist()
        return ui.get(software.ragebot.other.quick_peek_assist[1])
            and ui.get(software.ragebot.other.quick_peek_assist[2])
    end

    software._hitchance_override_active = false

    function software.is_hitchance_override_active()
        return software._hitchance_override_active
    end
end

local iinput do
    iinput = { }

	--- https://gitlab.com/KittenPopo/csgo-2018-source/-/blob/main/game/client/iinput.h

	local vector_t = ffi.typeof [[
		struct {
			float x;
			float y;
			float z;
		}
	]]

	local cusercmd_t = ffi.typeof([[
		struct {
			void     *vfptr;
			int      command_number;
			int      tickcount;
			$        viewangles;
			$        aimdirection;
			float    forwardmove;
			float    sidemove;
			float    upmove;
			int      buttons;
			uint8_t  impulse;
			int      weaponselect;
			int      weaponsubtype;
			int      random_seed;
			short    mousedx;
			short    mousedy;
			bool     hasbeenpredicted;
			$        headangles;
			$        headoffset;
			char	 pad_0x4C[0x18];
		}
	]], vector_t, vector_t, vector_t, vector_t)

    local signature = {
        'client.dll', '\xB9\xCC\xCC\xCC\xCC\x8B\x40\x38\xFF\xD0\x84\xC0\x0F\x85', 1
    }

	local vtable_addr = utils.find_signature(unpack(signature))
    local vtable_ptr = ffi.cast('uintptr_t***', vtable_addr)[0]

    local native_GetUserCmd = ffi.cast(ffi.typeof('$*(__thiscall*)(void*, int nSlot, int sequence_number)', cusercmd_t), vtable_ptr[0][8])

    function iinput.get_usercmd(slot, command_number)
        if command_number == 0 then
            return nil
        end

        return native_GetUserCmd(vtable_ptr, slot, command_number)
    end
end

local event_system do
    event_system = { }

    local function find(list, value)
        for i = 1, #list do
            if value == list[i] then
                return i
            end
        end

        return nil
    end

    local EventList = { } do
        EventList.__index = EventList

        function EventList:new()
            return setmetatable({
                list = { },
                count = 0
            }, self)
        end

        function EventList:__len()
            return self.count
        end

        function EventList:set(callback)
            if not find(self.list, callback) then
                self.count = self.count + 1
                table.insert(self.list, callback)
            end

            return self
        end

        function EventList:unset(callback)
            local index = find(self.list, callback)

            if index ~= nil then
                self.count = self.count - 1
                table.remove(self.list, index)
            end

            return self
        end

        function EventList:fire(...)
            local list = self.list

            for i = 1, #list do
                list[i](...)
            end

            return self
        end
    end

    local EventBus = { } do
        local function __index(list, k)
            local value = rawget(list, k)

            if value == nil then
                value = EventList:new()
                rawset(list, k, value)
            end

            return value
        end

        function EventBus:new()
            return setmetatable({ }, {
                __index = __index
            })
        end
    end

    function event_system:new()
        return EventBus:new()
    end
end

local logging_system do
    logging_system = { }

    local SOUND_SUCCESS = 'ui\\beepclear.wav'
    local SOUND_FAILURE = 'resource\\warning.wav'

    local play = cvar.play

    local function display_tag(r, g, b)
        client.color_log(r, g, b, script.name, '\0')
        client.color_log(255, 255, 255, ' ✦ ', '\0')
    end

    function logging_system.success(msg)
        display_tag(135, 135, 245)

        client.color_log(255, 255, 255, msg)
        play:invoke_callback(SOUND_SUCCESS)
    end

    function logging_system.default(msg)
        display_tag(135, 135, 245)

        client.color_log(255, 255, 255, msg)
        --play:invoke_callback(SOUND_SUCCESS)
    end


    function logging_system.error(msg)
        display_tag(250, 50, 75)

        client.color_log(255, 255, 255, msg)
        play:invoke_callback(SOUND_FAILURE)
    end
end

local config_system do
    config_system = { }

    local KEY = 'irEa5PqmVkMlw2Nj8B43dfnoeI9tHxzK1DX0JF6ULGAWcQuCTZpvh7syRgbYSO+/='

    local item_list = { }
    local item_data = { }

    local function get_key_values(arr)
        local list = { }

        if arr ~= nil then
            for i = 1, #arr do
                list[arr[i]] = i
            end
        end

        return list
    end

    function config_system.push(tab, name, item)
        if item_data[tab] == nil then
            item_data[tab] = { }
        end

        local data = {
            tab = tab,
            name = name,
            item = item
        }

        item_data[tab][name] = item
        table.insert(item_list, data)

        return item
    end

    function config_system.encode(data)
        local ok, result = pcall(json.stringify, data)

        if not ok then
            return false, result
        end

        ok, result = pcall(base64.encode, result, KEY)

        if not ok then
            return false, result
        end

        result = string.gsub(
            result, '[%+%/%=]', {
                ['+'] = 'g2134',
                ['/'] = 'g2634',
                ['='] = '_'
            }
        )

        result = string.format(
            'catboy: %s', result
        )

        return true, result
    end

    function config_system.decode(str)
        -- prefix detect + windows 11 notepad fix
        local matched, pad = str:match 'catboy: ([%w%+%/]+)(_*)'

        if matched == nil then
            return false, 'Config not supported'
        end

        pad = pad and string.rep('=', #pad) or ''

        local data = string.gsub(matched, 'g2%d%d34', {
            ['g2134'] = '+',
            ['g2634'] = '/'
        })

        local ok, result = pcall(base64.decode, data .. pad, KEY)

        if not ok then
            return false, result
        end

        ok, result = pcall(json.parse, result)

        if not ok then
            return false, result
        end

        return true, result
    end

    function config_system.import(data, categories)
        if data == nil then
            return false, 'config is empty'
        end

        local keys = get_key_values(categories)

        for k, v in pairs(data) do
            if (categories == nil or keys[k] ~= nil) and item_data[k] ~= nil then
                local items = item_data[k]

                for m, n in pairs(v) do
                    local item = items[m]

                    if item ~= nil then
                        item:set(unpack(n))
                    end
                end
            end
        end

        return true, nil
    end

    function config_system.export(categories)
        local list = { }

        local keys = get_key_values(categories)

        for k, v in pairs(item_data) do
            if categories ~= nil and keys[k] == nil then
                goto continue
            end

            local values = { }

            for m, n in pairs(v) do
                if n.type ~= 'hotkey' then
                    values[m] = n.value
                end
            end

            list[k] = values
            ::continue::
        end

        return list
    end
end


local shot_system do
    shot_system = { }

    local event_bus = event_system:new()

    local shot_list = { }

    local function create_shot_data(player)
        local tick = globals.tickcount()

        local eye_pos = vector(
            utils.get_eye_position(player)
        )

        local data = {
            tick = tick,

            player = player,
            victim = nil,

            eye_pos = eye_pos,
            impacts = { },

            damage = nil,
            hitgroup = nil
        }

        return data
    end

    local function on_weapon_fire(e)
        local userid = client.userid_to_entindex(e.userid)

        if userid == nil then
            return
        end

        table.insert(shot_list, create_shot_data(userid))
    end

    local function on_player_hurt(e)
        local userid = client.userid_to_entindex(e.userid)
        local attacker = client.userid_to_entindex(e.attacker)

        if userid == nil or attacker == nil then
            return
        end

        for i = #shot_list, 1, -1 do
            local data = shot_list[i]

            if data.player == attacker then
                data.victim = userid

                data.damage = e.dmg_health
                data.hitgroup = e.hitgroup

                break
            end
        end
    end

    local function on_bullet_impact(e)
        local userid = client.userid_to_entindex(e.userid)

        if userid == nil then
            return
        end

        for i = #shot_list, 1, -1 do
            local data = shot_list[i]

            if data.player == userid then
                local pos = vector(e.x, e.y, e.z)
                table.insert(data.impacts, pos)

                break
            end
        end
    end

    local function on_net_update_start()
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        local head_pos = nil do
            if entity.is_alive(me) then
                head_pos = vector(entity.hitbox_position(me, 0))
            end
        end

        for i = 1, #shot_list do
            local data = shot_list[i]

            local impact_count = #data.impacts

            if impact_count == 0 then
                goto continue
            end

            local eye_pos = data.eye_pos
            local end_pos = data.impacts[impact_count]

            event_bus.player_shot:fire {
                tick = data.tick,

                player = data.player,
                victim = data.victim,

                eye_pos = eye_pos,
                end_pos = end_pos,

                damage = data.damage,
                hitgroup = data.hitgroup
            }

            if head_pos ~= nil and entity.is_enemy(data.player) then
                local closest_point = utils.closest_ray_point(
                    eye_pos, end_pos, head_pos, true
                )

                local distancesqr = head_pos:distsqr(closest_point)

                if distancesqr <= 80 * 80 then
                    local distance = math.sqrt(distancesqr)

                    event_bus.enemy_shot:fire {
                        tick = data.tick,
                        distance = distance,

                        player = data.player,
                        victim = data.victim,

                        eye_pos = eye_pos,
                        end_pos = end_pos,

                        damage = data.damage,
                        hitgroup = data.hitgroup
                    }
                end
            end

            ::continue::
        end

        for i = 1, #shot_list do
            shot_list[i] = nil
        end
    end

    function shot_system.get_event_bus()
        return event_bus
    end

    client.set_event_callback('weapon_fire', on_weapon_fire)
    client.set_event_callback('player_hurt', on_player_hurt)
    client.set_event_callback('bullet_impact', on_bullet_impact)
    client.set_event_callback('net_update_start', on_net_update_start)
end

local menu do
    menu = { }

    local event_bus = event_system:new()

    local Item = { } do
        Item.__index = Item

        local function pack(ok, ...)
            if not ok then
                return nil
            end

            return ...
        end

        local function get_value_array(ref)
            return { pack(pcall(ui.get, ref)) }
        end

        local function get_key_values(arr)
            local list = { }

            for i = 1, #arr do
                list[arr[i]] = i
            end

            return list
        end

        local function update_item_values(item, initial)
            local value = get_value_array(item.ref)

            item.value = value

            if initial then
                item.default = value
            end

            if item.type == 'multiselect' then
                item.key_values = get_key_values(unpack(value))
            end
        end

        function Item:new(ref)
            return setmetatable({
                ref = ref,
                type = nil,

                list = { },
                value = { },
                default = { },
                key_values = { },

                callbacks = { }
            }, self)
        end

        function Item:init(...)
            local function callback()
                update_item_values(self, false)
                self:fire_events()

                event_bus.item_changed:fire(self)
            end

            self.type = ui.type(self.ref)

            if self.type ~= 'label' then
                update_item_values(self, true)
                pcall(ui.set_callback, self.ref, callback)
            end

            if self.type == 'multiselect' or self.type == 'list' then
                self.list = select(4, ...)
            end

            if self.type == 'button' then
                local fn = select(4, ...)

                if fn ~= nil then
                    self:set_callback(fn)
                end
            end

            event_bus.item_init:fire(self)
        end

        function Item:get(key)
            if self.type == 'hotkey' or self.type == 'textbox' then
                return ui.get(self.ref)
            end

            if key ~= nil then
                return self.key_values[key] ~= nil
            end

            return unpack(self.value)
        end

        function Item:set(...)
            ui.set(self.ref, ...)
            update_item_values(self, false)
        end

        function Item:update(...)
            ui.update(self.ref, ...)
        end

        function Item:reset()
            pcall(ui.set, self.ref, unpack(self.default))
        end

        function Item:set_enabled(value)
            return ui.set_enabled(self.ref, value)
        end

        function Item:set_visible(value)
            return ui.set_visible(self.ref, value)
        end

        function Item:set_callback(callback, force_call)
            local index = contains(self.callbacks, callback)

            if index == nil then
                table.insert(self.callbacks, callback)
            end

            if force_call then
                callback(self)
            end

            return self
        end

        function Item:unset_callback(callback)
            local index = contains(self.callbacks, callback)

            if index ~= nil then
                table.remove(self.callbacks, index)
            end

            return self
        end

        function Item:fire_events()
            local list = self.callbacks

            for i = 1, #list do
                list[i](self)
            end
        end
    end

    function menu.new(fn, ...)
        local ref = fn(...)

        local item = Item:new(ref) do
            item:init(...)
        end

        return item
    end

    function menu.get_event_bus()
        return event_bus
    end
end

local menu_logic do
    menu_logic = { }

    local item_data = { }
    local item_list = { }

    local logic_events = event_system:new()

    function menu_logic.get_event_bus()
        return logic_events
    end

    function menu_logic.set(item, value)
        if item == nil or item.ref == nil then
            return
        end

        item_data[item.ref] = value
    end

    function menu_logic.force_update()
        for i = 1, #item_list do
            local item = item_list[i]

            if item == nil then
                goto continue
            end

            local ref = item.ref

            if ref == nil then
                goto continue
            end

            local value = item_data[ref]

            if value == nil then
                goto continue
            end

            item:set_visible(value)
            item_data[ref] = false

            ::continue::
        end
    end

    local menu_events = menu.get_event_bus() do
        local function on_item_init(item)
            item_data[item.ref] = false
            item:set_visible(false)

            table.insert(item_list, item)
        end

        local function on_item_changed(...)
            logic_events.update:fire(...)
            menu_logic.force_update()
        end

        menu_events.item_init:set(on_item_init)
        menu_events.item_changed:set(on_item_changed)
    end
end

local text_anims do
    text_anims = { }

    local function u8(str)
        local chars = { }
        local count = 0

        for c in string.gmatch(str, '.[\128-\191]*') do
            count = count + 1
            chars[count] = c
        end

        return chars, count
    end

    function text_anims.gradient(str, time, r1, g1, b1, a1, r2, g2, b2, a2)
        local list = { }

        local strbuf, strlen = u8(str)
        local div = 1 / (strlen - 1)

        local delta_r = r2 - r1
        local delta_g = g2 - g1
        local delta_b = b2 - b1
        local delta_a = a2 - a1

        for i = 1, strlen do
            local char = strbuf[i]

            local t = time do
                t = t % 2

                if t > 1 then
                    t = 2 - t
                end
            end

            local r = r1 + t * delta_r
            local g = g1 + t * delta_g
            local b = b1 + t * delta_b
            local a = a1 + t * delta_a

            local hex = utils.to_hex(r, g, b, a)

            table.insert(list, '\a')
            table.insert(list, hex)
            table.insert(list, char)

            time = time + div
        end

        return table.concat(list)
    end
end

local text_fmt do
    text_fmt = { }

    local function decompose(str)
        local result, len = { }, #str

        local i, j = str:find('\a', 1)

        if i == nil then
            table.insert(result, {
                str, nil
            })
        end

        if i ~= nil and i > 1 then
            table.insert(result, {
                str:sub(1, i - 1), nil
            })
        end

        while i ~= nil do
            local hex = nil

            if str:sub(j + 1, j + 7) == 'DEFAULT' then
                j = j + 8
            else
                hex = str:sub(j + 1, j + 8)
                j = j + 9
            end

            local m, n = str:find('\a', j + 1)

            if m == nil then
                if j <= len then
                    table.insert(result, {
                        str:sub(j), hex
                    })
                end

                break
            end

            table.insert(result, {
                str:sub(j, m - 1), hex
            })

            i, j = m, n
        end

        return result
    end

    function text_fmt.color(str)
        local list = decompose(str)
        local len = #list

        return list, len
    end
end

local const do
    const = { }

    const.states = {
        'Default',
        'Standing',
        'Moving',
        'Slow Walk',
        'Jumping',
        'Jumping+',
        'Crouch',
        'Move-Crouch',
        'Legit AA',
        'Fakelag',
        'Dormant',
        'Manual AA',
        'Freestanding',
        'Safe Head'
    }
end

local localplayer do
    localplayer = { }

    local pre_flags = 0
    local post_flags = 0

    localplayer.is_moving = false
    localplayer.is_onground = false
    localplayer.is_crouched = false

    localplayer.duck_amount = 0.0
    localplayer.velocity2d_sqr = 0

    localplayer.is_peeking = false
    localplayer.is_vulnerable = false

    -- from @enq
    local function is_peeking(player)
        local should, vulnerable = false, false
        local velocity = vector(entity.get_prop(player, 'm_vecVelocity'))

        local eye = vector(client.eye_position())
        local peye = utils.extrapolate(eye, velocity, 14)

        local enemies = entity.get_players(true)

        for i = 1, #enemies do
            local enemy = enemies[i]

            local esp_data = entity.get_esp_data(enemy)

            if esp_data == nil then
                goto continue
            end

            if bit.band(esp_data.flags, bit.lshift(1, 11)) ~= 0 then
                vulnerable = true
                goto continue
            end

            local head = vector(entity.hitbox_position(enemy, 0))
            local phead = utils.extrapolate(head, velocity, 4)
            local entindex, damage = client.trace_bullet(player, peye.x, peye.y, peye.z, phead.x, phead.y, phead.z)

            if damage ~= nil and damage > 0 then
                should = true
                break
            end

            ::continue::
        end

        return should, vulnerable
    end

    local function on_pre_predict_command(cmd)
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        pre_flags = entity.get_prop(me, 'm_fFlags')
    end

    local function on_predict_command(cmd)
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        post_flags = entity.get_prop(me, 'm_fFlags')
    end

    local function on_setup_command(cmd)
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        local peeking, vulnerable = is_peeking(me)

        local is_onground = bit.band(pre_flags, 1) ~= 0
            and bit.band(post_flags, 1) ~= 0

        local velocity = vector(entity.get_prop(me, 'm_vecVelocity'))
        local duck_amount = entity.get_prop(me, 'm_flDuckAmount')

        local velocity2d_sqr = velocity:length2dsqr()

        localplayer.is_moving = velocity2d_sqr > 5 * 5
        localplayer.is_onground = is_onground

        localplayer.is_peeking = peeking
        localplayer.is_vulnerable = vulnerable

        if cmd.chokedcommands == 0 then
            localplayer.is_crouched = duck_amount > 0.5
            localplayer.duck_amount = duck_amount
        end

        localplayer.velocity2d_sqr = velocity2d_sqr
    end

    client.set_event_callback('pre_predict_command', on_pre_predict_command)
    client.set_event_callback('predict_command', on_predict_command)
    client.set_event_callback('setup_command', on_setup_command)
end

local get_defensive_mode = function() return 'Default' end
local get_defensive_callback = function() return 'predict_command' end

local debug_panel_info = {
    breaking_lc = false,
    resolver_active = false,
    resolver_target = '?',
    resolver_eye_yaw = 0,
    resolver_feet_yaw = 0,
    resolver_side = 0,
    resolver_desync = 0,
    resolver_max_desync = 58,
    resolver_mode = 'kittysolver',
    dragging = false,
    dragging_panel = false,
    dragging_graph = false,
    dragging_spotify = false,
    hovering_spotify = false,
    hovering_panel = false,
    hovering_netgraph = false,
    dragging_netgraph = false,
}

client.set_event_callback('setup_command', function(cmd)
    if debug_panel_info.dragging_panel or debug_panel_info.dragging_graph or debug_panel_info.dragging_spotify or debug_panel_info.hovering_spotify or debug_panel_info.hovering_panel or debug_panel_info.hovering_netgraph or debug_panel_info.dragging_netgraph then
        cmd.in_attack = 0
    end
end)

local exploit do
    exploit = { }

    local BREAK_LAG_COMPENSATION_DISTANCE_SQR = 64 * 64

    local max_tickbase = 0
    local run_command_number = 0
    local ember_choked_commands = 0
    local ember_max_process_ticks = math.abs(client.get_cvar('sv_maxusrcmdprocessticks') or 16) - 1

    local static_pitch = 0
    local static_yaw = 0

    local data = {
        old_origin = vector(),
        old_simtime = 0.0,

        shift = false,
        breaking_lc = false,

        defensive = {
            force = false,
            left = 0,
            max = 0,
        },

        lagcompensation = {
            distance = 0.0,
            teleport = false
        }
    }

    local function update_tickbase(me)
        data.shift = globals.tickcount() > entity.get_prop(me, 'm_nTickBase')
    end

    local function update_teleport(old_origin, new_origin)
        local delta = new_origin - old_origin
        local distance = delta:lengthsqr()

        local is_teleport = distance > BREAK_LAG_COMPENSATION_DISTANCE_SQR

        data.breaking_lc = is_teleport

        data.lagcompensation.distance = distance
        data.lagcompensation.teleport = is_teleport
    end

    local function update_lagcompensation(me)
        local old_origin = data.old_origin
        local old_simtime = data.old_simtime

        local origin = vector(entity.get_origin(me))
        local simtime = toticks(entity.get_prop(me, 'm_flSimulationTime'))

        if old_simtime ~= nil then
            local delta = simtime - old_simtime

            if delta < 0 or delta > 0 and delta <= 64 then
                update_teleport(old_origin, origin)
            end
        end

        data.old_origin = origin
        data.old_simtime = simtime
    end

    local function update_defensive_tick_default(me)
        local tickbase = entity.get_prop(me, 'm_nTickBase')

        if math.abs(tickbase - max_tickbase) > 64 then
            max_tickbase = 0
        end

        local defensive_ticks_left = 0

        if tickbase > max_tickbase then
            max_tickbase = tickbase
        elseif max_tickbase > tickbase then
            defensive_ticks_left = math.min(14, math.max(0, max_tickbase - tickbase - 1))
        end

        if defensive_ticks_left > 0 then
            data.breaking_lc = true
            data.defensive.left = defensive_ticks_left

            if data.defensive.max == 0 then
                data.defensive.max = defensive_ticks_left
            end
        else
            data.defensive.left = 0
            data.defensive.max = 0
        end
    end

    local function update_defensive_tick_ember(me)
        local tickbase = entity.get_prop(me, 'm_nTickBase') or 0

        local ticks_processed = utils.clamp(
            math.abs(tickbase - (max_tickbase or 0)),
            0,
            (ember_max_process_ticks or 0) - (ember_choked_commands or 0)
        )

        max_tickbase = math.max(tickbase, max_tickbase or 0)

        local is_active = software.is_double_tap_active() or software.is_on_shot_antiaim_active()
        local in_defensive = is_active and (ticks_processed > 1 and ticks_processed < ember_max_process_ticks)

        if in_defensive then
            data.breaking_lc = true
            data.defensive.left = ticks_processed

            if data.defensive.max == 0 then
                data.defensive.max = ticks_processed
            end
        else
            data.defensive.left = 0
            data.defensive.max = 0
        end
    end

    local gs_last_sim_time = 0
    local gs_defensive_until = 0

    local function update_defensive_tick_gs(me)
        local tickcount = globals.tickcount()
        local sim_time = toticks(entity.get_prop(me, 'm_flSimulationTime'))
        local sim_diff = sim_time - gs_last_sim_time

        if sim_diff < 0 then
            gs_defensive_until = tickcount + math.abs(sim_diff) - toticks(client.latency())
        end

        gs_last_sim_time = sim_time

        local in_defensive = gs_defensive_until > tickcount

        if in_defensive then
            local ticks_left = gs_defensive_until - tickcount

            data.breaking_lc = true
            data.defensive.left = ticks_left

            if data.defensive.max == 0 then
                data.defensive.max = ticks_left
            end
        else
            data.defensive.left = 0
            data.defensive.max = 0
        end
    end

    local function update_defensive_tick_wraith(me)
        local tickbase = entity.get_prop(me, 'm_nTickBase') or 0

        local tickbase_diff = tickbase - (max_tickbase or 0)
        max_tickbase = math.max(tickbase, max_tickbase or 0)

        if tickbase_diff <= -1 and tickbase_diff >= -14 then
            local ticks_left = math.abs(tickbase_diff)

            data.breaking_lc = true
            data.defensive.left = ticks_left

            if data.defensive.max == 0 then
                data.defensive.max = ticks_left
            end
        else
            data.defensive.left = 0
            data.defensive.max = 0
        end
    end

    local function update_defensive_tick(me)
        local mode = get_defensive_mode()

        if mode == 'Ember' then
            update_defensive_tick_ember(me)
        elseif mode == 'Wraith' then
            update_defensive_tick_wraith(me)
        elseif mode == 'GS Tools' then
            update_defensive_tick_gs(me)
        else
            update_defensive_tick_default(me)
        end
    end

    function exploit.get()
        debug_panel_info.breaking_lc = data.breaking_lc
        return data
    end

    local NET_UPDATE_SAFE_MODES = {
        ['Default'] = true,
        ['GS Tools'] = true,
    }

    local function on_predict_command(cmd)
        local mode = get_defensive_mode()
        local callback = get_defensive_callback()

        if callback == 'net_update_end' and not NET_UPDATE_SAFE_MODES[mode] then
            callback = 'predict_command'
        end

        if callback ~= 'predict_command' then
            return
        end

        local me = entity.get_local_player()

        if me == nil then
            return
        end

        if cmd.command_number == run_command_number then
            update_defensive_tick(me)
            run_command_number = nil
        end
    end

    local function on_net_update_end()
        local mode = get_defensive_mode()

        if get_defensive_callback() ~= 'net_update_end' or not NET_UPDATE_SAFE_MODES[mode] then
            return
        end

        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then return end

        update_defensive_tick(me)
    end

    local function on_run_command(e)
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        update_tickbase(me)
        ember_choked_commands = e.chokedcommands or 0

        run_command_number = e.command_number
    end

    local function on_net_update_start()
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        update_lagcompensation(me)
    end

    local function on_level_init()
        max_tickbase = 0
        run_command_number = 0
        ember_choked_commands = 0
        gs_last_sim_time = 0
        gs_defensive_until = 0
        data.shift = false
        data.breaking_lc = false
        data.defensive.force = false
        data.defensive.left = 0
        data.defensive.max = 0
    end

    client.set_event_callback('predict_command', on_predict_command)
    client.set_event_callback('net_update_end', on_net_update_end)
    client.set_event_callback('run_command', on_run_command)
    client.set_event_callback('net_update_start', on_net_update_start)
    client.set_event_callback('level_init', on_level_init)
end

local statement do
    statement = { }

    local list = { }
    local count = 0

    local function add(state)
        count = count + 1
        list[count] = state
    end

    local function clear_list()
        for i = 1, count do
            list[i] = nil
        end

        count = 0
    end

    local function update_onground()
        if not localplayer.is_onground then
            return
        end

        if localplayer.is_moving then
            add 'Moving'

            if localplayer.is_crouched then
                return
            end

            if software.is_slow_motion() then
                add 'Slow Walk'
            end

            return
        end

        add 'Standing'
    end

    local function update_crouched()
        if not localplayer.is_crouched then
            return
        end

        add 'Crouch'

        if localplayer.is_moving then
            add 'Move-Crouch'
        end
    end

    local function update_in_air()
        if localplayer.is_onground then
            return
        end

        add 'Jumping'

        if localplayer.is_crouched then
            add 'Jumping+'
        end
    end

    function statement.get()
        return list
    end

    local function on_setup_command()
        clear_list()

        update_onground()
        update_crouched()
        update_in_air()
    end

    client.set_event_callback(
        'setup_command',
        on_setup_command
    )
end

-- clipboard FFI (file-level for auth button access)
local sp_clipboard_count = vtable_bind('vgui2.dll', 'VGUI_System010', 7, 'int(__thiscall*)(void*)')
local sp_clipboard_text = vtable_bind('vgui2.dll', 'VGUI_System010', 11, 'int(__thiscall*)(void*, int, const char*, int)')
local sp_char_buf = ffi.typeof('char[?]')

local function sp_read_clipboard()
    local len = sp_clipboard_count()
    if len > 0 then
        local buf = sp_char_buf(len)
        sp_clipboard_text(0, buf, len)
        return ffi.string(buf, len - 1)
    end
    return nil
end

-- set later by force_update_scene
local sp_on_auth_change = nil

-- shared auth state for spotify
local sp_auth_state = {
    refresh_token = nil,
    apikey = nil,
    authed = false,
    status = 'idle',
    pending = false,
    device_id = nil,
}

local function sp_save_token()
    database.write('catboy#spotify_auth', { refresh_token = sp_auth_state.refresh_token })
end

local function sp_fetch_token()
    if sp_auth_state.pending or not sp_auth_state.refresh_token then return end
    sp_auth_state.pending = true
    sp_auth_state.status = 'connecting'
    if sp_on_auth_change then sp_on_auth_change() end
    http.get('https://spotify.stbrouwers.cc/refresh_token?refresh_token=' .. sp_auth_state.refresh_token, function(s, r)
        sp_auth_state.pending = false
        if not s or r.status ~= 200 then
            sp_auth_state.status = 'failed'
            if sp_on_auth_change then sp_on_auth_change() end
            return
        end
        local ok, parsed = pcall(json.parse, r.body)
        if ok and parsed and parsed.access_token then
            sp_auth_state.apikey = parsed.access_token
            sp_auth_state.authed = true
            sp_auth_state.status = 'connected'
            if sp_on_auth_change then sp_on_auth_change() end
        else
            sp_auth_state.status = 'failed'
        end
    end)
end

-- restore saved spotify token
do
    local saved = database.read('catboy#spotify_auth') or {}
    if saved.refresh_token then
        sp_auth_state.refresh_token = saved.refresh_token
        sp_fetch_token()
    end
end

local ref do
    ref = { }

    local function new_key(str, key)
        if str:find '\n' == nil then
            str = str .. '\n'
        end

        return str .. key
    end

    local function lock_unselection(item, default_value)
        local old_value = item:get()

        if #old_value == 0 then
            if default_value == nil then
                if item.type == 'multiselect' then
                    default_value = item.list
                elseif item.type == 'list' then
                    default_value = { }

                    for i = 1, #item.list do
                        default_value[i] = i
                    end
                end
            end

            old_value = default_value
            item:set(default_value)
        end

        item:set_callback(function()
            local value = item:get()

            if #value > 0 then
                old_value = value
            else
                item:set(old_value)
            end
        end)
    end

    local general = { } do
        local categories do
            categories = {
                'Configs',
                'Ragebot',
                'Anti-Aim',
                'Visuals',
                'Misc'
            }

            table.insert(categories, 'Debug')
            table.insert(categories, 'Credits')
        end

        general.label = menu.new(
            ui.new_label, 'AA', 'Fake lag', 'catboy'
        )

        general.category = menu.new(
            ui.new_combobox, 'AA', 'Fake lag', '\n catboy.category', categories
        )

        general.empty_bag = menu.new(
            ui.new_label, 'AA', 'Fake lag', '\n o0o0o0o0o0oo0oooo00o0ooo0ooo0o0o0o0o'
        )

        general.line = menu.new(
            ui.new_label, 'AA', 'Fake lag', '\n catboy.line'
        )

        general.welcome_text = menu.new(
            ui.new_label, 'AA', 'Fake lag', '\n catboy.welcome_text'
        )

        general.build_name = menu.new(
            ui.new_label, 'AA', 'Fake lag', '\n catboy.build_name'
        )

        local function update_welcome_text(item)
            local hex = utils.to_hex(
                ui.get(item)
            )

            general.welcome_text:set(string.format(
                '\a%s✦  \aC8C8C8FFWelcome, \a%s%s', hex, hex, script.user
            ))

            general.build_name:set(string.format(
                '\a%s✦  \aC8C8C8FFYour build is \a%s%s', hex, hex, script.build
            ))

        end

        ui.set_callback(software.misc.settings.menu_color, update_welcome_text)
        update_welcome_text(software.misc.settings.menu_color)

        client.set_event_callback('paint_ui', function()
            if not boot.done then return end
            if not ui.is_menu_open() then
                return
            end

            local min, max = 660, 750
            local width = ui.menu_size()

            local content_region = utils.map(width, min, max, 0, 1, true)

            local r1, g1, b1, a1 = 80, 80, 80, 255
            local r2, g2, b2, a2 = software.get_color()

            local name = string.format(
                '%s', 'catboy.lua'
            )

            local text = text_anims.gradient(
                name, -globals.realtime(),
                r1, g1, b1, a1, r2, g2, b2, a2
            )

            -- padding
            text = string.rep('\u{0020}', utils.lerp(15, 22, content_region)) .. text

            general.label:set(text)

            -- underline

            local underline_name = string.format(
                '%s', '‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾'
            )

            local underline = text_anims.gradient(
                underline_name, -globals.realtime(),
                r1, g1, b1, a1, r2, g2, b2, a2
            )

            general.line:set(underline)
        end)

        -- credits tab
        do
            local function lerp_alpha(current, target, speed)
                local goal = target and 1 or 0
                local diff = goal - current
                if math.abs(diff) < 0.001 then return goal end
                return current + diff * speed
            end

            local sparkles = { }
            local NUM_SPARKLES = 12
            local credits_alpha = 0

            for i = 1, NUM_SPARKLES do
                sparkles[i] = {
                    x = math.random() * 100,
                    y = math.random() * 100,
                    speed = 0.3 + math.random() * 0.7,
                    size = 0.5 + math.random() * 1.5,
                    phase = math.random() * 6.28,
                    drift = (math.random() - 0.5) * 0.3,
                }
            end

            client.set_event_callback('paint_ui', function()
                if not ui.is_menu_open() then
                    credits_alpha = lerp_alpha(credits_alpha, false, 0.1)
                    if credits_alpha <= 0.01 then return end
                end

                local is_credits = general.category:get() == 'Credits'
                credits_alpha = lerp_alpha(credits_alpha, is_credits, 0.06)

                if credits_alpha <= 0.01 then return end

                local time = globals.realtime()

                -- title
                local r1, g1, b1, a1 = 255, 176, 176, 255
                local r2, g2, b2, a2 = 200, 160, 255, 255
                local title_text = text_anims.gradient(
                    '✦  Credits', -time * 0.8,
                    r1, g1, b1, a1, r2, g2, b2, a2
                )
                ref.credits.title:set(title_text)

                -- separators
                local sep_text = text_anims.gradient(
                    '─── ♡ ───────────────', -time * 0.5,
                    80, 80, 80, 255, r1, g1, b1, 180
                )
                ref.credits.main_dev_label:set(sep_text)
                ref.credits.thank_you_line:set(sep_text)

                local sep_text2 = text_anims.gradient(
                    '─── ✦ ───────────────', -time * 0.5,
                    80, 80, 80, 255, r2, g2, b2, 180
                )
                ref.credits.helpers_label:set(sep_text2)

                -- dev name
                local dev_text = text_anims.gradient(
                    'althea/altheauwu', -time * 0.6,
                    255, 255, 255, 255, r1, g1, b1, 255
                )
                ref.credits.main_dev_name:set(dev_text)

                if not boot.done then return end

                local mx, my = ui.menu_position()
                local mw, mh = ui.menu_size()
                local alpha = credits_alpha

                -- sparkles
                for i = 1, NUM_SPARKLES do
                    local s = sparkles[i]
                    local px = mx + 20 + (s.x / 100) * (mw - 40)
                    local py = my + 60 + (s.y / 100) * (mh - 80)

                    s.y = s.y - s.speed * 0.15
                    s.x = s.x + s.drift * 0.1

                    if s.y < -2 then
                        s.y = 102
                        s.x = math.random() * 100
                        s.speed = 0.3 + math.random() * 0.7
                        s.phase = math.random() * 6.28
                    end

                    local sparkle_alpha = math.sin(time * 2.5 + s.phase) * 0.5 + 0.5
                    local sa = math.floor(sparkle_alpha * 60 * alpha)

                    if sa > 0 then
                        local sz = math.floor(s.size)
                        renderer.rectangle(math.floor(px), math.floor(py), sz, sz, r1, g1, b1, sa)
                        if sz > 1 then
                            renderer.rectangle(math.floor(px) - 1, math.floor(py) + math.floor(sz / 2), sz + 2, 1, r1, g1, b1, math.floor(sa * 0.4))
                            renderer.rectangle(math.floor(px) + math.floor(sz / 2), math.floor(py) - 1, 1, sz + 2, r1, g1, b1, math.floor(sa * 0.4))
                        end
                    end
                end

                -- bottom glow line
                local line_y = my + mh - 8
                local line_w = math.floor(mw * 0.6)
                local line_x = mx + math.floor((mw - line_w) * 0.5)
                local glow_shift = math.sin(time * 1.5) * 0.5 + 0.5

                local lr = math.floor(r1 + (r2 - r1) * glow_shift)
                local lg = math.floor(g1 + (g2 - g1) * glow_shift)
                local lb = math.floor(b1 + (b2 - b1) * glow_shift)

                local half = math.floor(line_w * 0.5)
                renderer.gradient(
                    line_x, line_y, half, 1,
                    lr, lg, lb, 0,
                    lr, lg, lb, math.floor(80 * alpha),
                    true
                )
                renderer.gradient(
                    line_x + half, line_y, half, 1,
                    lr, lg, lb, math.floor(80 * alpha),
                    lr, lg, lb, 0,
                    true
                )

                -- glow
                renderer.gradient(
                    line_x, line_y - 2, half, 3,
                    lr, lg, lb, 0,
                    lr, lg, lb, math.floor(25 * alpha),
                    true
                )
                renderer.gradient(
                    line_x + half, line_y - 2, half, 3,
                    lr, lg, lb, math.floor(25 * alpha),
                    lr, lg, lb, 0,
                    true
                )
            end)
        end
    end

    local config = { } do
        local DB_NAME = 'catboy#db'
        local DB_DATA = database.read(DB_NAME) or { }

        local config_data = { }
        local config_list = { }

        local config_defaults = {
            [1] = {
                name = 'default',
                data = 'catboy: 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'
            }
        }

        for i = 1, #DB_DATA do
            config_data[i] = DB_DATA[i]
        end

        for i = #config_defaults, 1, -1 do
            local list = config_defaults[i]

            if list.data == nil then
                goto continue
            end

            local ok, result = config_system.decode(list.data)

            if not ok then
                -- invalid, skip
                table.remove(config_defaults, i)

                goto continue
            end

            list.data = result
            ::continue::
        end

        local function create_config(name, data, is_default)
            local list = { }

            list.name = name
            list.data = data
            list.default = is_default

            return list
        end

        local function find_by_name(list, name)
            for i = 1, #list do
                local data = list[i]

                if data.name == name then
                    return data, i
                end
            end

            return nil, -1
        end

        local function save_config_data()
            database.write(DB_NAME, config_data)
        end

        local function update_config_list()
            for i = 1, #config_list do
                config_list[i] = nil
            end

            for i = 1, #config_defaults do
                local list = config_defaults[i]

                local cell = create_config(
                    list.name, list.data, true
                )

                table.insert(config_list, cell)
            end

            for i = 1, #config_data do
                local list = config_data[i]

                local cell = create_config(
                    list.name, list.data, false
                )

                cell.data_index = i

                table.insert(config_list, cell)
            end
        end

        local function get_render_list()
            local result = { }

            for i = 1, #config_list do
                local list = config_list[i]

                local name = list.name

                table.insert(result, name)
            end

            return result
        end

        local function find_config(name)
            return find_by_name(
                config_list, name
            )
        end

        local function load_config(name)
            local list, idx = find_config(name)

            if list == nil or idx == -1 then
                return
            end

            local ok, result = config_system.import(list.data)

            if not ok then
                return logging_system.error(string.format(
                    'failed to import %s config: %s', name, result
                ))
            end

            logging_system.success(string.format(
                'successfully loaded %s config', name
            ))
        end

        local function save_config(name)
            local cfg_data = config_system.export()

            local list, idx = find_config(name)

            if list == nil or idx == -1 then
                table.insert(config_data, create_config(
                    name, cfg_data, false
                ))

                save_config_data()
                update_config_list()

                config.list:update(
                    get_render_list()
                )

                return logging_system.success(string.format(
                    'successfully created %s config', name
                ))
            end

            if list.default then
                return logging_system.error(string.format(
                    'cannot modify %s config', name
                ))
            end

            list.data = cfg_data

            if list.data_index ~= nil then
                local data_cell = config_data[
                    list.data_index
                ]

                if data_cell ~= nil then
                    data_cell.data = cfg_data
                end
            end

            save_config_data()
            update_config_list()

            logging_system.success(string.format(
                'successfully modified %s config', name
            ))
        end

        local function delete_config(name)
            local list, idx = find_config(name)

            if list == nil or idx == -1 then
                return
            end

            if list.default then
                return logging_system.error(string.format(
                    'cannot delete %s config', name
                ))
            end

            local data_index = list.data_index

            if data_index == nil then
                return
            end

            table.remove(config_data, data_index)

            save_config_data()
            update_config_list()

            config.list:update(
                get_render_list()
            )

            local next_input = ''

            local index = math.min(
                config.list:get() + 1,
                #config_list
            )

            local data = config_list[index]

            if data ~= nil then
                next_input = data.name
            end

            config.input:set(next_input)

            logging_system.success(string.format(
                'successfully deleted %s config', name
            ))
        end

        config.list = menu.new(
            ui.new_listbox, 'AA', 'Anti-aimbot angles', '\n config.list', { }
        )

        config.input = menu.new(
            ui.new_textbox, 'AA', 'Anti-aimbot angles', '\n config.input', ''
        )

        config.load_button = menu.new(
            ui.new_button, 'AA', 'Anti-aimbot angles', 'load', function()
                local name = utils.trim(
                    config.input:get()
                )

                if name == '' then
                    return
                end

                load_config(name)
            end
        )

        config.save_button = menu.new(
            ui.new_button, 'AA', 'Anti-aimbot angles', 'save', function()
                local name = utils.trim(
                    config.input:get()
                )

                if name == '' then
                    return
                end

                save_config(name)
            end
        )

        config.delete_button = menu.new(
            ui.new_button, 'AA', 'Anti-aimbot angles', 'delete', function()
                local name = utils.trim(
                    config.input:get()
                )

                if name == '' then
                    return
                end

                delete_config(name)
            end
        )

        config.export_button = menu.new(
            ui.new_button, 'AA', 'Anti-aimbot angles', 'export', function()
                local ok, result = config_system.encode(
                    config_system.export()
                )

                if not ok then
                    return
                end

                clipboard.set(result)

                logging_system.success 'exported config to clipboard'
            end
        )

        config.import_button = menu.new(
            ui.new_button, 'AA', 'Anti-aimbot angles', 'import', function()
                local ok, result = config_system.decode(
                    clipboard.get()
                )

                if not ok then
                    return
                end

                config_system.import(result)

                logging_system.success 'imported config from clipboard'
            end
        )

        update_config_list()

        config.list:update(
            get_render_list()
        )

        config.list:set_callback(function(item)
            local index = item:get()

            if index == nil then
                return
            end

            local list = config_list[index + 1]

            if list == nil then
                return
            end

            config.input:set(list.name)
        end)

        ref.config = config
    end

    local ragebot = { } do
        local aimtools = { } do
            local weapons = {
                'G3SG1 / SCAR-20',
                'SSG 08',
                'AWP',
                'R8 Revolver',
                'Desert Eagle',
                'Pistol',
                'Zeus'
            }

            local states = {
                'Standing',
                'Moving',
                'Crouch',
                'Move-Crouch',
                'Air'
            }

            aimtools.enabled = config_system.push(
                'ragebot', 'aimtools.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Aim tools', 'aimtools')
                )
            )

            aimtools.weapon = menu.new(
                ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Weapon', 'aimtools'), weapons
            )

            for i = 1, #weapons do
                local weapon = weapons[i]

                local key = 'aimtools[' .. weapon .. ']'

                local items = { } do
                    local body_aim = { } do
                        body_aim.enabled = config_system.push(
                            'ragebot', key .. '.body_aim.enabled', menu.new(
                                ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('›  Body aim', key)
                            )
                        )

                        body_aim.select = config_system.push(
                            'ragebot', key .. '.body_aim.select', menu.new(
                                ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Prefer body aim on', key .. '.body_aim'), {
                                    'Higher than you',
                                    'Lower than you',
                                    'Lethal',
                                    'After X misses',
                                    'HP lower than X'
                                }
                            )
                        )

                        body_aim.misses = config_system.push(
                            'ragebot', key .. '.body_aim.misses', menu.new(
                                ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Misses', key .. '.body_aim'), 1, 10, 3, true, ''
                            )
                        )

                        body_aim.health = config_system.push(
                            'ragebot', key .. '.body_aim.health', menu.new(
                                ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Health', key .. '.body_aim'), 1, 100, 50, true, '%'
                            )
                        )

                        items.body_aim = body_aim
                    end

                    local safe_points = { } do
                        safe_points.enabled = config_system.push(
                            'ragebot', key .. '.safe_points.enabled', menu.new(
                                ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('›  Safe points', key)
                            )
                        )

                        safe_points.select = config_system.push(
                            'ragebot', key .. '.safe_points.select', menu.new(
                                ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Force safe point on', key .. '.safe_points'), {
                                    'Higher than you',
                                    'Lower than you',
                                    'Lethal',
                                    'After X misses',
                                    'HP lower than X'
                                }
                            )
                        )

                        safe_points.misses = config_system.push(
                            'ragebot', key .. '.safe_points.misses', menu.new(
                                ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Misses', key .. '.safe_points'), 1, 10, 3, true, ''
                            )
                        )

                        safe_points.health = config_system.push(
                            'ragebot', key .. '.safe_points.health', menu.new(
                                ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Health', key .. '.safe_points'), 1, 100, 50, true, '%'
                            )
                        )

                        items.safe_points = safe_points
                    end

                    local multipoints = { } do
                        multipoints.enabled = config_system.push(
                            'ragebot', key .. '.multipoints.enabled', menu.new(
                                ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('›  Adaptive multipoint', key)
                            )
                        )

                        multipoints.note = menu.new(
                            ui.new_label, 'AA', 'Anti-aimbot angles', new_key('\aFFB0B0FFAdjusts multipoint scale based on enemy state', key .. '.multipoints.note')
                        )

                        for j = 1, #states do
                            local state = states[j]

                            local key = key .. '.multipoints[' .. state .. ']'

                            multipoints[state] = config_system.push(
                                'ragebot', key .. '.value', menu.new(
                                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key(state, key), 25, 100, 50, true, '%'
                                )
                            )
                        end

                        items.multipoints = multipoints
                    end

                    local accuracy_boost = { } do
                        accuracy_boost.enabled = config_system.push(
                            'ragebot', key .. '.accuracy_boost.enabled', menu.new(
                                ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('›  Accuracy boost', key)
                            )
                        )

                        accuracy_boost.value = config_system.push(
                            'ragebot', key .. '.accuracy_boost.value', menu.new(
                                ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('\n accuracy_boost.value', key), {
                                    'Low',
                                    'Medium',
                                    'High',
                                    'Maximum'
                                }
                            )
                        )

                        items.accuracy_boost = accuracy_boost
                    end

                end

                aimtools[weapon] = items
            end

            local hitchance_override = { } do
                hitchance_override.enabled = config_system.push(
                    'ragebot', 'aimtools.hitchance_override.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('›  Hitchance override', 'aimtools')
                    )
                )

                hitchance_override.hotkey = config_system.push(
                    'ragebot', 'aimtools.hitchance_override.hotkey', menu.new(
                        ui.new_hotkey, 'AA', 'Anti-aimbot angles', new_key('Hotkey', 'aimtools.hitchance_override'), true
                    )
                )

                hitchance_override.value = config_system.push(
                    'ragebot', 'aimtools.hitchance_override.value', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Hitchance', 'aimtools.hitchance_override'), 1, 100, 50, true, '%'
                    )
                )

                aimtools.hitchance_override = hitchance_override
            end

            aimtools.weapons = weapons
            aimtools.states = states

            ragebot.aimtools = aimtools
        end

        local aimbot_logs = { } do
            aimbot_logs.enabled = config_system.push(
                'visuals', 'aimbot_logs.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Aimbot logs', 'aimbot_logs')
                )
            )

            aimbot_logs.select = config_system.push(
                'visuals', 'aimbot_logs.select', menu.new(
                    ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Log selection', 'aimbot_logs'), {
                        'Notify',
                        'Screen',
                        'Console'
                    }
                )
            )

            aimbot_logs.color_hit = config_system.push(
                'visuals', 'aimbot_logs.color_hit', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', '\n aimbot_logs.color_hit', 150, 255, 125, 255
                )
            )

            aimbot_logs.color_miss = config_system.push(
                'visuals', 'aimbot_logs.color_miss', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', '\n aimbot_logs.color_miss', 255, 125, 150, 255
                )
            )

            aimbot_logs.glow = config_system.push(
                'visuals', 'aimbot_logs.glow', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Glow', 'aimbot_logs'), 0, 125, 100, true, '%'
                )
            )

            aimbot_logs.offset = config_system.push(
                'visuals', 'aimbot_logs.offset', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Offset', 'aimbot_logs'), 30, 325, 200, true, 'px', 2
                )
            )

            aimbot_logs.duration = config_system.push(
                'visuals', 'aimbot_logs.duration', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Duration', 'aimbot_logs'), 30, 80, 40, true, 's.', 0.1
                )
            )

            aimbot_logs.transparency = config_system.push(
                'visuals', 'aimbot_logs.transparency', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Transparency', 'aimbot_logs'), 0, 100, 100, true, '%'
                )
            )

            lock_unselection(aimbot_logs.select)

            ragebot.aimbot_logs = aimbot_logs
        end

        local defensive_fix = { } do
            defensive_fix.enabled = config_system.push(
                'visuals', 'defensive_fix.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Defensive fix', 'defensive_fix')
                )
            )

            defensive_fix.pop_up = config_system.push(
                'visuals', 'defensive_fix.pop_up', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key(' ›  Enable defensive fix logger', 'defensive_pop_up')
                )
            )

            ragebot.defensive_fix = defensive_fix
        end

        local recharge_fix = { } do
            recharge_fix.enabled = config_system.push(
                'visuals', 'recharge_fix.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Unsafe charge', 'recharge_fix')
                )
            )

            ragebot.recharge_fix = recharge_fix
        end

        local recharge_fix_experimental = { } do
            recharge_fix_experimental.enabled = config_system.push(
                'visuals', 'recharge_fix_experimental.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('\aFF0000FFUnsafe charge (experimental)', 'recharge_fix_experimental')
                )
            )

            ragebot.recharge_fix_experimental = recharge_fix_experimental
        end

        local auto_hide_shots = { } do
            local weapon_list = {
                'Auto Snipers',
                'AWP',
                'Scout',
                'Desert Eagle',
                'Pistols',
                'SMG',
                'Rifles'
            }

            local state_list = {
                'Standing',
                'Moving',
                'Slow Walk',
                'Air',
                'Air-Crouch',
                'Crouch',
                'Move-Crouch',
            }

            auto_hide_shots.enabled = config_system.push(
                'Ragebot', 'auto_hide_shots.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Auto hide shots', 'auto_hide_shots')
                )
            )

            auto_hide_shots.weapons = config_system.push(
                'Ragebot', 'auto_hide_shots.weapons', menu.new(
                    ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Weapons', 'auto_hide_shots'), weapon_list
                )
            )

            auto_hide_shots.states = config_system.push(
                'Ragebot', 'auto_hide_shots.states', menu.new(
                    ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('States', 'auto_hide_shots'), state_list
                )
            )

            lock_unselection(auto_hide_shots.weapons)

            lock_unselection(auto_hide_shots.states, {
                'Slow Walk',
                'Crouch',
                'Move-Crouch'
            })

            ragebot.auto_hide_shots = auto_hide_shots
        end

        local jump_scout = { } do
            jump_scout.enabled = config_system.push(
                'visuals', 'jump_scout.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Allow Jump scout', 'jump_scout')
                )
            )

            ragebot.jump_scout = jump_scout
        end

        local dt_boost = { } do
            dt_boost.enabled = config_system.push(
                'ragebot', 'dt_boost.enabled', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('DT Boost', 'dt_boost'), {
                        'Off',
                        'Boost',
                        'Fast',
                        'Top Speed'
                    }
                )
            )

            ragebot.dt_boost = dt_boost
        end

        ref.ragebot = ragebot
    end

    local antiaim = { } do
        local function create_defensive_items(name)
            local items = { }

            local function hash(key)
                return name .. ':defensive_' .. key
            end

            local function fmt_key(key)
                return new_key(fmt(key), hash(key))
            end

            items.force_break_lc = config_system.push(
                'antiaim', hash 'force_break_lc', menu.new(
                    ui.new_checkbox, 'AA', 'Other', new_key(
                        'Force break lc', hash 'force_break_lc'
                    )
                )
            )

            items.enabled = config_system.push(
                'antiaim', hash 'enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Other', new_key(
                        'Defensive anti-aim', hash 'enabled'
                    )
                )
            )

            items.activation = config_system.push(
                'antiaim', hash 'activation', menu.new(
                    ui.new_combobox, 'AA', 'Other', new_key('Activation', hash 'activation'), {
                        'Sensitivity',
                        'Twilight'
                    }
                )
            )

            items.sensitivity_start = config_system.push(
                'antiaim', hash 'sensitivity_start', menu.new(
                    ui.new_slider, 'AA', 'Other', new_key('Start', hash 'sensitivity_start'), 0, 14, 0
                )
            )

            items.sensitivity_end = config_system.push(
                'antiaim', hash 'sensitivity_end', menu.new(
                    ui.new_slider, 'AA', 'Other', new_key('End', hash 'sensitivity_end'), 0, 14, 14
                )
            )

            items.pitch = config_system.push(
                'antiaim', hash 'pitch', menu.new(
                    ui.new_combobox, 'AA', 'Other', new_key('Pitch', hash 'pitch'), {
                        'Off',
                        'Static',
                        'Jitter',
                        'Spin',
                        'Sway',
                        'Static Random',
                        'Random'
                    }
                )
            )

            items.pitch_label_1 = menu.new(
                ui.new_label, 'AA', 'Other', 'From'
            )

            items.pitch_offset_1 = config_system.push(
                'antiaim', hash 'pitch_offset_1', menu.new(
                    ui.new_slider, 'AA', 'Other', new_key('\n', hash 'pitch_offset_1'), -89, 89, 0, true, '°'
                )
            )

            items.pitch_label_2 = menu.new(
                ui.new_label, 'AA', 'Other', 'To'
            )

            items.pitch_offset_2 = config_system.push(
                'antiaim', hash 'pitch_offset_2', menu.new(
                    ui.new_slider, 'AA', 'Other', new_key('\n', hash 'pitch_offset_2'), -89, 89, 0, true, '°'
                )
            )

            items.pitch_speed = config_system.push(
                'antiaim', hash 'pitch_speed', menu.new(
                    ui.new_slider, 'AA', 'Other', new_key('Speed', hash 'pitch_speed'), -100, 100, 20, true, nil, 0.1
                )
            )

            items.pitch_randomize_offset = config_system.push(
                'antiaim', hash 'pitch_randomize_offset', menu.new(
                    ui.new_checkbox, 'AA', 'Other', new_key('Randomize offset', hash 'pitch_randomize_offset')
                )
            )

            items.yaw = config_system.push(
                'antiaim', hash 'yaw', menu.new(
                    ui.new_combobox, 'AA', 'Other', new_key('Yaw', hash 'yaw'), {
                        'Off',
                        'Static',
                        'Static LR',
                        'Spin',
                        'Sway',
                        'X-Way',
                        'Static Random',
                        'Random'
                    }
                )
            )

            items.ways_count = config_system.push(
                'antiaim', hash 'ways_count', menu.new(
                    ui.new_slider, 'AA', 'Other', new_key('\n', hash 'ways_count'), 3, 7, 3, true, ''
                )
            )

            items.ways_custom = config_system.push(
                'antiaim', hash 'ways_custom', menu.new(
                    ui.new_checkbox, 'AA', 'Other', new_key('Custom ways', hash 'ways_custom')
                )
            )

            for i = 1, 7 do
                items['way_' .. i] = config_system.push(
                    'antiaim', hash('way_' .. i), menu.new(
                        ui.new_slider, 'AA', 'Other', new_key('\n', hash('way_' .. i)), -180, 180, 0, true, '°'
                    )
                )
            end

            items.ways_auto_body_yaw = config_system.push(
                'antiaim', hash 'ways_auto_body_yaw', menu.new(
                    ui.new_checkbox, 'AA', 'Other', new_key('Automatic body yaw', hash 'ways_auto_body_yaw')
                )
            )

            items.yaw_left = config_system.push(
                'antiaim', hash 'yaw_left', menu.new(
                    ui.new_slider, 'AA', 'Other', new_key('Yaw left', hash 'yaw_left'), -180, 180, 0, true, '°'
                )
            )

            items.yaw_right = config_system.push(
                'antiaim', hash 'yaw_right', menu.new(
                    ui.new_slider, 'AA', 'Other', new_key('Yaw right', hash 'yaw_right'), -180, 180, 0, true, '°'
                )
            )

            items.yaw_offset = config_system.push(
                'antiaim', hash 'yaw_offset', menu.new(
                    ui.new_slider, 'AA', 'Other', new_key('\n', hash 'yaw_offset'), 0, 360, 0, true, '°'
                )
            )

            items.yaw_speed = config_system.push(
                'antiaim', hash 'yaw_speed', menu.new(
                    ui.new_slider, 'AA', 'Other', new_key('Speed', hash 'yaw_speed'), -100, 100, 20, true, '', 0.1
                )
            )

            items.yaw_randomize_offset = config_system.push(
                'antiaim', hash 'yaw_randomize_offset', menu.new(
                    ui.new_checkbox, 'AA', 'Other', new_key('Randomize offset', hash 'yaw_randomize_offset')
                )
            )

            items.yaw_modifier = config_system.push(
                'antiaim', hash 'yaw_modifier', menu.new(
                    ui.new_combobox, 'AA', 'Other', new_key('Yaw modifier', hash 'yaw_modifier'), {
                        'Off',
                        'Offset',
                        'Center',
                        'Skitter'
                    }
                )
            )

            items.yaw_label_1 = menu.new(
                ui.new_label, 'AA', 'Other', 'From'
            )

            items.yaw_offset_1 = config_system.push(
                'antiaim', hash 'yaw_offset_1', menu.new(
                    ui.new_slider, 'AA', 'Other', new_key('\n', hash 'pitch_offset_1'), -89, 89, 0, true, '°'
                )
            )

            items.yaw_label_2 = menu.new(
                ui.new_label, 'AA', 'Other', 'To'
            )

            items.yaw_offset_2 = config_system.push(
                'antiaim', hash 'yaw_offset_2', menu.new(
                    ui.new_slider, 'AA', 'Other', new_key('\n', hash 'pitch_offset_2'), -89, 89, 0, true, '°'
                )
            )

            items.modifier_offset = config_system.push(
                'antiaim', hash 'modifier_offset', menu.new(
                    ui.new_slider, 'AA', 'Other', new_key('\n', hash 'modifier_offset'), -180, 180, 0, true, '°'
                )
            )

            items.body_yaw = config_system.push(
                'antiaim', hash 'modifier_delay_2', menu.new(
                    ui.new_combobox, 'AA', 'Other', new_key('Body yaw', hash 'body_yaw'), {
                        'Off',
                        'Opposite',
                        'Static',
                        'Jitter',
                        'LBY'
                    }
                )
            )

            items.body_yaw_offset = config_system.push(
                'antiaim', hash 'body_yaw_offset', menu.new(
                    ui.new_slider, 'AA', 'Other', new_key('\n', hash 'body_yaw_offset'), -180, 180, 0, true, '°'
                )
            )

            items.freestanding_body_yaw = config_system.push(
                'antiaim', hash 'freestanding_body_yaw', menu.new(
                    ui.new_checkbox, 'AA', 'Other', new_key('Freestanding body yaw', hash 'freestanding_body_yaw')
                )
            )

            items.delay_1 = config_system.push(
                'antiaim', hash 'delay_1', menu.new(
                    ui.new_slider, 'AA', 'Other', new_key('Delay from', hash 'delay_1'), 1, 14, 0, true, 't'
                )
            )

            items.delay_2 = config_system.push(
                'antiaim', hash 'delay_2', menu.new(
                    ui.new_slider, 'AA', 'Other', new_key('Delay to', hash 'delay_2'), 1, 14, 0, true, 't'
                )
            )

            return items
        end

        local function create_builder_items(name, std_key)
            local items = { }

            local is_default = name == 'Default'
            local is_legit_aa = name == 'Legit AA'

            local function hash(key)
                return name .. ':' .. key
            end

            local function fmt_key(key)
                return new_key(fmt(key), hash(key))
            end

            if std_key ~= nil then
                function hash(key)
                    return name .. ':' .. key .. ':' .. std_key
                end
            end

            if not is_default then
                local enabled_name = string.format(
                    'Redefine %s', name
                )

                items.enabled = config_system.push(
                    'antiaim', hash 'enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key(
                            enabled_name, hash 'enabled'
                        )
                    )
                )
            end

            if not is_legit_aa then
                items.pitch = config_system.push(
                    'antiaim', hash 'pitch', menu.new(
                        ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Pitch', hash 'pitch'), {
                            'Off',
                            'Default',
                            'Up',
                            'Down',
                            'Minimal',
                            'Random',
                            'Custom'
                        }
                    )
                )

                items.pitch_offset = config_system.push(
                    'antiaim', hash 'pitch_offset', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', hash 'pitch_offset'), -89, 89, 0, true, '°'
                    )
                )

                items.pitch:set 'Default'
            end

            if name ~= 'Freestanding' then
                items.yaw = config_system.push(
                    'antiaim', hash 'yaw', menu.new(
                        ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Yaw', hash 'yaw'), {
                            'Off',
                            '180',
                            '180 LR',
                            'Spin',
                            'Static',
                            '180 Z',
                            'Crosshair'
                        }
                    )
                )

                items.yaw_offset = config_system.push(
                    'antiaim', hash 'yaw_offset', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', hash 'yaw_offset'), -180, 180, 0, true, '°'
                    )
                )

                items.yaw_left = config_system.push(
                    'antiaim', hash 'yaw_left', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Yaw left', hash 'yaw_left'), -180, 180, 0, true, '°'
                    )
                )

                items.yaw_right = config_system.push(
                    'antiaim', hash 'yaw_right', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Yaw right', hash 'yaw_right'), -180, 180, 0, true, '°'
                    )
                )

                items.yaw_asynced = config_system.push(
                    'antiaim', hash 'yaw_asynced', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Asynced', hash 'yaw_asynced')
                    )
                )

                items.yaw_jitter = config_system.push(
                    'antiaim', hash 'yaw_jitter', menu.new(
                        ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Yaw jitter', hash 'yaw_jitter'), {
                            'Off',
                            'Offset',
                            'Center',
                            'Random',
                            'Skitter'
                        }
                    )
                )

                items.jitter_offset = config_system.push(
                    'antiaim', hash 'jitter_offset', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', hash 'jitter_offset'), -180, 180, 0, true, '°'
                    )
                )

                items.yaw:set '180'
            end

            items.body_yaw = config_system.push(
                'antiaim', hash 'body_yaw', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Body yaw', hash 'body_yaw'), {
                        'Off',
                        'Opposite',
                        'Static',
                        'Jitter',
                        'Smart',
                        'Hold Yaw',
                        'Tick'
                    }
                )
            )

            items.lby_desync = config_system.push(
                'antiaim', hash 'lby_desync', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Desync', hash 'lby_desync'), 0, 65, 65, true, ''
                )
            )

            items.lby_inverter = config_system.push(
                'antiaim', hash 'lby_inverter', menu.new(
                    ui.new_hotkey, 'AA', 'Anti-aimbot angles', new_key('Inverter', hash 'lby_inverter'), true
                )
            )

            items.body_yaw_offset = config_system.push(
                'antiaim', hash 'body_yaw_offset', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', hash 'body_yaw_offset'), -180, 180, 0, true, '°'
                )
            )

            items.freestanding_body_yaw = config_system.push(
                'antiaim', hash 'freestanding_body_yaw', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key(
                        'Freestanding body yaw', hash 'freestanding_body_yaw'
                    )
                )
            )

            items.roll_value = config_system.push(
                'antiaim', hash 'roll_value', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Roll', hash 'roll_value'), -90, 90, 0, true, '°'
                )
            )

            if name ~= 'Fakelag' then
                items.delay_body_1 = config_system.push(
                    'antiaim', hash 'delay_body_1', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Delay from', hash 'delay_body_1'), 1, 14, 0, true, 't'
                    )
                )

                items.delay_body_2 = config_system.push(
                    'antiaim', hash 'delay_body_2', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Delay to', hash 'delay_body_2'), 1, 14, 0, true, 't'
                    )
                )

                items.invert_chance = config_system.push(
                    'antiaim', hash 'invert_chance', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Invert chance', hash 'invert_chance'), 0, 100, 100, true, '%'
                    )
                )

                items.hold_time = config_system.push(
                    'antiaim', hash 'hold_time', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Hold time', hash 'hold_time'), 1, 7, 2, true, 't'
                    )
                )

                items.hold_delay = config_system.push(
                    'antiaim', hash 'hold_delay', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Hold delay', hash 'hold_delay'), 1, 32, 2, true, 'x'
                    )
                )

                items.tick_speed = config_system.push(
                    'antiaim', hash 'tick_speed', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Tick speed', hash 'tick_speed'), 1, 50, 4, true, 'x'
                    )
                )

                items.tick_delay = config_system.push(
                    'antiaim', hash 'tick_delay', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Tick delay', hash 'tick_delay'), 1, 10, 2, true, 'd'
                    )
                )

            end

            return items
        end

        antiaim.select = menu.new(
            ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('\n Select', 'antiaim'), {
                'Builder',
                'Settings'
            }
        )

        local builder = { } do
            builder.state = menu.new(
                ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('State', 'builder'), const.states
            )

            for i = 1, #const.states do
                local state = const.states[i]

                local items = create_builder_items(state)

                if state ~= 'Fakelag' then
                    items.separator = menu.new(
                        ui.new_label, 'AA', 'Anti-aimbot angles', new_key('\n', 'separator')
                    )

                    items.defensive = create_defensive_items(state)
                end

                builder[state] = items
            end

            antiaim.builder = builder
        end

        local settings = { } do
            local disablers = { } do
                disablers.enabled = config_system.push(
                    'antiaim', 'disablers.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Fake lag', new_key('Spin if', 'Spin if')
                    )
                )

                disablers.select = menu.new(
                    ui.new_multiselect, 'AA', 'Fake lag', new_key('\n Select', 'Spin if'), {
                        'Warmup',
                        'No enemies'
                    }
                )

                lock_unselection(disablers.select)

                settings.disablers = disablers
            end

            local avoid_backstab = { } do
                avoid_backstab.enabled = config_system.push(
                    'antiaim', 'avoid_backstab.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Fake lag', new_key('Avoid backstab', 'avoid_backstab')
                    )
                )

                settings.avoid_backstab = avoid_backstab
            end

            local freestanding = { } do
                freestanding.enabled = config_system.push(
                    'antiaim', 'freestanding.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Fake lag', new_key('Freestanding', 'freestanding')
                    )
                )

                freestanding.hotkey = config_system.push(
                    'antiaim', 'freestanding.hotkey', menu.new(
                        ui.new_hotkey, 'AA', 'Fake lag', new_key('Hotkey', 'freestanding'), true
                    )
                )

                settings.freestanding = freestanding
            end

            local manual_yaw = { } do
                manual_yaw.enabled = config_system.push(
                    'antiaim', 'manual_yaw.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Fake lag', new_key('Manual yaw', 'manual_yaw')
                    )
                )

                manual_yaw.disable_yaw_modifiers = config_system.push(
                    'antiaim', 'manual_yaw.disable_yaw_modifiers', menu.new(
                        ui.new_checkbox, 'AA', 'Fake lag', new_key('Disable yaw modifiers', 'manual_yaw')
                    )
                )

                manual_yaw.body_freestanding = config_system.push(
                    'antiaim', 'manual_yaw.body_freestanding', menu.new(
                        ui.new_checkbox, 'AA', 'Fake lag', new_key('Body freestanding', 'manual_yaw')
                    )
                )

                manual_yaw.left_hotkey = config_system.push(
                    'antiaim', 'manual_yaw.left_hotkey', menu.new(
                        ui.new_hotkey, 'AA', 'Fake lag', new_key(
                            'Left manual', 'manual_yaw'
                        )
                    )
                )

                manual_yaw.right_hotkey = config_system.push(
                    'antiaim', 'manual_yaw.right_hotkey', menu.new(
                        ui.new_hotkey, 'AA', 'Fake lag', new_key(
                            'Right manual', 'manual_yaw'
                        )
                    )
                )

                manual_yaw.forward_hotkey = config_system.push(
                    'antiaim', 'manual_yaw.forward_hotkey', menu.new(
                        ui.new_hotkey, 'AA', 'Fake lag', new_key(
                            'Forward manual', 'manual_yaw'
                        )
                    )
                )

                manual_yaw.backward_hotkey = config_system.push(
                    'antiaim', 'manual_yaw.backward_hotkey', menu.new(
                        ui.new_hotkey, 'AA', 'Fake lag', new_key(
                            'Backward manual', 'manual_yaw'
                        )
                    )
                )

                manual_yaw.reset_hotkey = config_system.push(
                    'antiaim', 'manual_yaw.reset_hotkey', menu.new(
                        ui.new_hotkey, 'AA', 'Fake lag', new_key(
                            'Reset manual', 'manual_yaw'
                        )
                    )
                )

                manual_yaw.left_hotkey:set 'Toggle'
                manual_yaw.right_hotkey:set 'Toggle'
                manual_yaw.forward_hotkey:set 'Toggle'
                manual_yaw.backward_hotkey:set 'Toggle'

                manual_yaw.reset_hotkey:set 'On hotkey'

                settings.manual_yaw = manual_yaw
            end

            local safe_head = { } do
                safe_head.enabled = config_system.push(
                    'antiaim', 'antiaim.settings.safe_head.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Fake lag', new_key('Safe head', 'safe_head')
                    )
                )

                safe_head.states = config_system.push(
                    'antiaim', 'antiaim.settings.safe_head.states', menu.new(
                        ui.new_multiselect, 'AA', 'Fake lag', new_key('States', 'safe_head'), {
                            'Knife',
                            'Taser',
                            'Above enemy',
                            'Distance'
                        }
                    )
                )

                lock_unselection(safe_head.states)

                settings.safe_head = safe_head
            end

            local defensive_flick = { } do
                defensive_flick.enabled = config_system.push(
                    'antiaim', 'defensive_flick.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Fake lag', new_key('Defensive flick', 'defensive_flick')
                    )
                )

                defensive_flick.states = config_system.push(
                    'antiaim', 'defensive_flick.inverter', menu.new(
                        ui.new_multiselect, 'AA', 'Fake lag', new_key('States', 'defensive_flick'), {
                            'Standing',
                            'Slow Walk',
                            'Jumping',
                            'Jumping+',
                            'Crouch',
                            'Move-Crouch'
                        }
                    )
                )

                defensive_flick.inverter = config_system.push(
                    'antiaim', 'defensive_flick.inverter', menu.new(
                        ui.new_hotkey, 'AA', 'Fake lag', new_key('Inverter', 'defensive_flick')
                    )
                )

                defensive_flick.pitch = config_system.push(
                    'antiaim', 'defensive_flick.pitch', menu.new(
                        ui.new_slider, 'AA', 'Fake lag', new_key('Pitch', 'defensive_flick'), -89, 89, 0
                    )
                )

                defensive_flick.yaw = config_system.push(
                    'antiaim', 'defensive_flick.yaw', menu.new(
                        ui.new_slider, 'AA', 'Fake lag', new_key('Yaw', 'defensive_flick'), 0, 360, 120
                    )
                )

                defensive_flick.yaw_random = config_system.push(
                    'antiaim', 'defensive_flick.yaw_random', menu.new(
                        ui.new_slider, 'AA', 'Fake lag', new_key('Yaw Random', 'defensive_flick'), 0, 180, 0
                    )
                )

                defensive_flick.auto_body_yaw = config_system.push(
                    'antiaim', 'defensive_flick.auto_body_yaw', menu.new(
                        ui.new_checkbox, 'AA', 'Fake lag', new_key('Auto body yaw', 'defensive_flick')
                    )
                )

                defensive_flick.speed = config_system.push(
                    'antiaim', 'defensive_flick.speed', menu.new(
                        ui.new_slider, 'AA', 'Fake lag', new_key('Speed', 'defensive_flick'), 2, 10, 7
                    )
                )

                defensive_flick.speed_random = config_system.push(
                    'antiaim', 'defensive_flick.speed_random', menu.new(
                        ui.new_slider, 'AA', 'Fake lag', new_key('Speed Random', 'defensive_flick'), 0, 8, 0
                    )
                )

                lock_unselection(defensive_flick.states, {
                    'Standing',
                    'Crouch'
                })

                settings.defensive_flick = defensive_flick
            end

            antiaim.settings = settings
        end

        ref.antiaim = antiaim
    end

    local visuals = { } do
        local aspect_ratio = { } do
            local tooltips = {
                [125] = '5:4',
                [133] = '4:3',
                [160] = '16:10',
                [177] = '16:9'
            }

            aspect_ratio.enabled = config_system.push(
                'visuals', 'aspect_ratio.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Aspect ratio', 'aspect_ratio')
                )
            )

            aspect_ratio.value = config_system.push(
                'visuals', 'aspect_ratio.value', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', 'aspect_ratio'), 0, 200, 133, true, '', 0.01, tooltips
                )
            )

            visuals.aspect_ratio = aspect_ratio
        end

        local third_person = { } do
            third_person.enabled = config_system.push(
                'visuals', 'third_person.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Third person', 'third_person')
                )
            )

            third_person.distance = config_system.push(
                'visuals', 'third_person.distance', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Distance', 'third_person'), 0, 180, 100
                )
            )

            third_person.zoom_speed = config_system.push(
                'visuals', 'third_person.zoom_speed', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Zoom speed', 'third_person'), 1, 100, 25, true, '%'
                )
            )

            visuals.third_person = third_person
        end

        local viewmodel = { } do
            viewmodel.enabled = config_system.push(
                'visuals', 'viewmodel.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Viewmodel', 'viewmodel')
                )
            )

            viewmodel.fov = config_system.push(
                'visuals', 'viewmodel.fov', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Field of fov', 'viewmodel'), 0, 1000, 680, true, '°', 0.1
                )
            )

            viewmodel.offset_x = config_system.push(
                'visuals', 'viewmodel.offset_x', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Offset X', 'viewmodel'), -100, 100, 25, true, '', 0.1
                )
            )

            viewmodel.offset_y = config_system.push(
                'visuals', 'viewmodel.offset_y', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Offset Y', 'viewmodel'), -100, 100, 25, true, '', 0.1
                )
            )

            viewmodel.offset_z = config_system.push(
                'visuals', 'viewmodel.offset_z', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Offset Z', 'viewmodel'), -100, 100, 25, true, '', 0.1
                )
            )

            viewmodel.opposite_knife_hand = config_system.push(
                'visuals', 'viewmodel.opposite_knife_hand', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Opposite knife hand', 'viewmodel')
                )
            )

            viewmodel.separator = menu.new(
                ui.new_label, 'AA', 'Anti-aimbot angles', '\n'
            )

            visuals.viewmodel = viewmodel
        end

        local scope_animation = { } do
            scope_animation.enabled = config_system.push(
                'visuals', 'scope_animation.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Scope animation', 'scope_animation')
                )
            )

            visuals.scope_animation = scope_animation
        end

        local custom_scope = { } do
            custom_scope.enabled = config_system.push(
                'visuals', 'custom_scope.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Custom scope', 'custom_scope')
                )
            )

            custom_scope.color = config_system.push(
                'visuals', 'custom_scope.color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color', 'custom_scope'), 0, 255, 255, 255
                )
            )

            custom_scope.position = config_system.push(
                'visuals', 'custom_scope.size', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Position', 'custom_scope'), 0, 500, 105
                )
            )

            custom_scope.offset = config_system.push(
                'visuals', 'custom_scope.offset', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Offset', 'custom_scope'), 0, 500, 5
                )
            )

            custom_scope.animation_speed = config_system.push(
                'visuals', 'custom_scope.animation_speed', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Animation speed', 'custom_scope'), 1, 100, 25, true, '%'
                )
            )

            visuals.custom_scope = custom_scope
        end

        local world_marker = { } do
            world_marker.enabled = config_system.push(
                'visuals', 'world_marker.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('World marker', 'world_marker')
                )
            )

            world_marker.color = config_system.push(
                'visuals', 'world_marker.color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color', 'world_marker'), 255, 255, 255, 255
                )
            )

            visuals.world_marker = world_marker
        end

        local damage_marker = { } do
            damage_marker.enabled = config_system.push(
                'visuals', 'damage_marker.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Damage marker', 'damage_marker')
                )
            )

            damage_marker.color = config_system.push(
                'visuals', 'damage_marker.color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color', 'damage_marker'), 0, 255, 255, 255
                )
            )

            visuals.damage_marker = damage_marker
        end

        local watermark = { } do
            watermark.select = config_system.push(
                'visuals', 'watermark.enabled', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Watermark', 'watermark'), {
                        'Default',
                        'Alternative'
                    }
                )
            )

            watermark.color = config_system.push(
                'visuals', 'watermark.color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color', 'watermark'), 0, 255, 255, 255
                )
            )

            visuals.watermark = watermark
        end

        local indicators = { } do
            indicators.enabled = config_system.push(
                'visuals', 'indicators.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Indicators', 'indicators')
                )
            )

            indicators.style = config_system.push(
                'visuals', 'indicators.style', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Style', 'indicators'), {
                        'Default',
                        'Sparkles'
                    }
                )
            )

            indicators.color_accent = config_system.push(
                'visuals', 'indicators.color_accent', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color accent', 'indicators'), 0, 255, 255, 255
                )
            )

            indicators.color_secondary = config_system.push(
                'visuals', 'indicators.color_secondary', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color secondary', 'indicators'), 255, 255, 255, 255
                )
            )

            indicators.offset = config_system.push(
                'visuals', 'indicators.offset', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Offset', 'indicators'), 3, 40, 11, true, 'px', 2
                )
            )

            indicators.scope_dim = config_system.push(
                'visuals', 'indicators.scope_dim', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Scope dim', 'indicators')
                )
            )

            indicators.scope_dim_alpha = config_system.push(
                'visuals', 'indicators.scope_dim_alpha', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Scope dim alpha', 'indicators'), 0, 100, 50, true, '%'
                )
            )

            visuals.indicators = indicators
        end

        local defensive_bar = { } do
            defensive_bar.enabled = config_system.push(
                'visuals', 'defensive_bar.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Defensive bar', 'defensive_bar')
                )
            )

            defensive_bar.color = config_system.push(
                'visuals', 'defensive_bar.color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color', 'defensive_bar'), 120, 255, 255, 255
                )
            )

            defensive_bar.glow = config_system.push(
                'visuals', 'defensive_bar.glow', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Glow effect', 'defensive_bar')
                )
            )

            defensive_bar.segmented = config_system.push(
                'visuals', 'defensive_bar.segmented', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Segmented', 'defensive_bar')
                )
            )

            defensive_bar.fade_color = config_system.push(
                'visuals', 'defensive_bar.fade_color', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Color fade', 'defensive_bar')
                )
            )

            defensive_bar.position_y = config_system.push(
                'visuals', 'defensive_bar.position_y', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Y offset', 'defensive_bar'), -500, 500, -80, true, 'px'
                )
            )

            defensive_bar.height = config_system.push(
                'visuals', 'defensive_bar.height', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Height', 'defensive_bar'), 2, 12, 4, true, 'px'
                )
            )

            visuals.defensive_bar = defensive_bar
        end

        local cat_whiskers = { } do
            cat_whiskers.enabled = config_system.push(
                'visuals', 'cat_whiskers.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Cat whiskers', 'cat_whiskers')
                )
            )

            cat_whiskers.color = config_system.push(
                'visuals', 'cat_whiskers.color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color', 'cat_whiskers'), 255, 180, 220, 255
                )
            )

            cat_whiskers.size = config_system.push(
                'visuals', 'cat_whiskers.size', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Size', 'cat_whiskers'), 20, 80, 45, true, 'px'
                )
            )

            cat_whiskers.glow = config_system.push(
                'visuals', 'cat_whiskers.glow', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Glow effect', 'cat_whiskers')
                )
            )

            cat_whiskers.animate = config_system.push(
                'visuals', 'cat_whiskers.animate', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Animate', 'cat_whiskers')
                )
            )

            visuals.cat_whiskers = cat_whiskers
        end

        local manual_arrows = { } do
            manual_arrows.enabled = config_system.push(
                'visuals', 'manual_arrows.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Manual arrows', 'manual_arrows')
                )
            )

            manual_arrows.style = config_system.push(
                'visuals', 'manual_arrows.style', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Style', 'manual_arrows'), {
                        'Default',
                        'Alternative'
                    }
                )
            )

            manual_arrows.color_accent = config_system.push(
                'visuals', 'manual_arrows.color_accent', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color accent', 'manual_arrows'), 255, 255, 255, 200
                )
            )

            manual_arrows.color_secondary = config_system.push(
                'visuals', 'manual_arrows.color_secondary', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color secondary', 'manual_arrows'), 255, 255, 255, 200
                )
            )

            visuals.manual_arrows = manual_arrows
        end

        local velocity_warning = { } do
            velocity_warning.enabled = config_system.push(
                'visuals', 'velocity_warning.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Velocity warning', 'velocity_warning')
                )
            )

            velocity_warning.color = config_system.push(
                'visuals', 'velocity_warning.color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color', 'velocity_warning'), 0, 255, 255, 255
                )
            )

            velocity_warning.offset = config_system.push(
                'visuals', 'velocity_warning.color', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Offset', 'velocity_warning'), 30, 250, 125, true, 'px', 2
                )
            )

            visuals.velocity_warning = velocity_warning
        end

        local velocity_graph = { } do
            velocity_graph.enabled = config_system.push(
                'visuals', 'velocity_graph.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Velocity graph', 'velocity_graph')
                )
            )

            velocity_graph.color = config_system.push(
                'visuals', 'velocity_graph.color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color', 'velocity_graph'), 0, 200, 255, 255
                )
            )

            velocity_graph.height = config_system.push(
                'visuals', 'velocity_graph.height', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Height', 'velocity_graph'), 30, 120, 50, true, 'px'
                )
            )

            velocity_graph.width = config_system.push(
                'visuals', 'velocity_graph.width', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Width', 'velocity_graph'), 100, 400, 250, true, 'px'
                )
            )

            visuals.velocity_graph = velocity_graph
        end

        local custom_killfeed = { } do
            custom_killfeed.enabled = config_system.push(
                'visuals', 'custom_killfeed.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Custom killfeed', 'custom_killfeed')
                )
            )

            custom_killfeed.bg_active = config_system.push(
                'visuals', 'custom_killfeed.bg_active', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Background active', 'custom_killfeed'), 80, 40, 40, 200
                )
            )

            custom_killfeed.bg_inactive = config_system.push(
                'visuals', 'custom_killfeed.bg_inactive', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Background inactive', 'custom_killfeed'), 20, 20, 20, 150
                )
            )

            custom_killfeed.attacker_color = config_system.push(
                'visuals', 'custom_killfeed.attacker_color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Attacker color', 'custom_killfeed'), 200, 200, 200, 255
                )
            )

            custom_killfeed.attacked_color = config_system.push(
                'visuals', 'custom_killfeed.attacked_color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Attacked color', 'custom_killfeed'), 200, 200, 200, 255
                )
            )

            custom_killfeed.weapon_color = config_system.push(
                'visuals', 'custom_killfeed.weapon_color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Weapon color', 'custom_killfeed'), 180, 180, 180, 255
                )
            )

            custom_killfeed.headshot_color = config_system.push(
                'visuals', 'custom_killfeed.headshot_color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Headshot color', 'custom_killfeed'), 255, 80, 80, 255
                )
            )

            custom_killfeed.size = config_system.push(
                'visuals', 'custom_killfeed.size', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Size', 'custom_killfeed'), 8, 32, 14, true, 'px'
                )
            )

            visuals.custom_killfeed = custom_killfeed
        end

        local damage_indicator = { } do
            damage_indicator.enabled = config_system.push(
                'visuals', 'damage_indicator.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Damage indicator', 'damage_indicator')
                )
            )

            damage_indicator.only_if_active = config_system.push(
                'visuals', 'damage_indicator.only_if_active', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Only if active', 'damage_indicator')
                )
            )

            damage_indicator.font = config_system.push(
                'visuals', 'damage_indicator.font', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Font', 'damage_indicator'), {
                        'Default',
                        'Small',
                        'Bold'
                    }
                )
            )

            damage_indicator.offset = config_system.push(
                'visuals', 'damage_indicator.offset', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Offset', 'damage_indicator'), 1, 24, 8, true, 'px'
                )
            )

            damage_indicator.active_label = menu.new(
                ui.new_label, 'AA', 'Anti-aimbot angles', new_key('Active color', 'damage_indicator')
            )

            damage_indicator.active_color = config_system.push(
                'visuals', 'damage_indicator.active_color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Active color picker', 'damage_indicator'), 255, 255, 255, 255
                )
            )

            damage_indicator.inactive_label = menu.new(
                ui.new_label, 'AA', 'Anti-aimbot angles', new_key('Inactive color', 'damage_indicator')
            )

            damage_indicator.inactive_color = config_system.push(
                'visuals', 'damage_indicator.inactive_color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Inactive color picker', 'damage_indicator'), 255, 255, 255, 150
                )
            )

            damage_indicator.separator = menu.new(
                ui.new_label, 'AA', 'Anti-aimbot angles', '\n'
            )

            visuals.damage_indicator = damage_indicator
        end

        ref.visuals = visuals
    end

    local misc = { } do
        local clantag = { } do
            clantag.enabled = config_system.push(
                'visuals', 'clantag.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Clantag', 'clantag')
                )
            )

            misc.clantag = clantag
        end


        local increase_ladder_movement = { } do
            increase_ladder_movement.enabled = config_system.push(
                'visuals', 'increase_ladder_movement.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Increase ladder movement', 'increase_ladder_movement')
                )
            )

            misc.increase_ladder_movement = increase_ladder_movement
        end

        local animation_breaker = { } do
            animation_breaker.enabled = config_system.push(
                'visuals', 'animation_breaker.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Animation breaker', 'animation_breaker')
                )
            )

            animation_breaker.in_air_legs = config_system.push(
                'visuals', 'animation_breaker.in_air_legs', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('In-air legs', 'animation_breaker'), {
                        'Off',
                        'Static',
                        'Alien'
                    }
                )
            )

            animation_breaker.onground_legs = config_system.push(
                'visuals', 'animation_breaker.onground_legs', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('On-ground legs', 'animation_breaker'), {
                        'Off',
                        'Static',
                        'Break',
                        'Alien'
                    }
                )
            )

            animation_breaker.adjust_lean = config_system.push(
                'visuals', 'animation_breaker.adjust_lean', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Adjust lean', 'animation_breaker'), 0, 100, 0, true, '%', 1, {
                        [0] = 'Off'
                    }
                )
            )

            animation_breaker.pitch_on_land = config_system.push(
                'visuals', 'animation_breaker.pitch_on_land', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Pitch on land', 'animation_breaker')
                )
            )

            animation_breaker.freeburger = config_system.push(
                'visuals', 'animation_breaker.freeburger', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Freeburger', 'animation_breaker')
                )
            )

            animation_breaker.perfect = config_system.push(
                'visuals', 'animation_breaker.perfect', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Perfect animation breaker', 'animation_breaker')
                )
            )

            animation_breaker.perfect_slider = config_system.push(
                'visuals', 'animation_breaker.perfect_slider', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Perfect slider', 'animation_breaker'), 0, 10, 1, false, '', 1
                )
            )

            misc.animation_breaker = animation_breaker
        end

        local walking_on_quick_peek = { } do
            walking_on_quick_peek.enabled = config_system.push(
                'visuals', 'walking_on_quick_peek.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Walking on quick peek', 'walking_on_quick_peek')
                )
            )

            misc.walking_on_quick_peek = walking_on_quick_peek
        end

        local enhance_grenade_release = { } do
            enhance_grenade_release.enabled = config_system.push(
                'visuals', 'enhance_grenade_release.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Other', new_key('Enhance grenade release', 'enhance_grenade_release')
                )
            )

            enhance_grenade_release.disablers = config_system.push(
                'visuals', 'enhance_grenade_release.disablers', menu.new(
                    ui.new_multiselect, 'AA', 'Other', new_key('Disablers', 'enhance_grenade_release'), {
                        'Molotov',
                        'HE Grenade',
                        'Smoke Grenade'
                    }
                )
            )

            enhance_grenade_release.only_with_dt = config_system.push(
                'visuals', 'enhance_grenade_release.only_with_dt', menu.new(
                    ui.new_checkbox, 'AA', 'Other', new_key('Only with dt', 'enhance_grenade_release')
                )
            )

            enhance_grenade_release.separator = menu.new(
                ui.new_label, 'AA', 'Other', '\n'
            )

            misc.enhance_grenade_release = enhance_grenade_release
        end

        local fps_optimize = { } do
            fps_optimize.enabled = config_system.push(
                'visuals', 'fps_optimize.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Other', new_key('Fps optimize', 'fps_optimize')
                )
            )

            fps_optimize.always_on = config_system.push(
                'visuals', 'fps_optimize.always_on', menu.new(
                    ui.new_checkbox, 'AA', 'Other', new_key('Always on', 'fps_optimize')
                )
            )

            fps_optimize.detections = config_system.push(
                'visuals', 'fps_optimize.detections', menu.new(
                    ui.new_multiselect, 'AA', 'Other', new_key('Detections', 'fps_optimize'), {
                        'Peeking',
                        'Hit flag'
                    }
                )
            )

            fps_optimize.list = config_system.push(
                'visuals', 'fps_optimize.list', menu.new(
                    ui.new_multiselect, 'AA', 'Other', new_key('Optimizations', 'fps_optimize'), {
                        'Blood',
                        'Bloom',
                        'Decals',
                        'Shadows',
                        'Sprites',
                        'Particles',
                        'Ropes',
                        'Dynamic lights',
                        'Map details',
                        'Weapon effects'
                    }
                )
            )

            fps_optimize.separator = menu.new(
                ui.new_label, 'AA', 'Other', '\n'
            )

            lock_unselection(fps_optimize.detections)

            lock_unselection(fps_optimize.list, {
                'Blood',
                'Decals',
                'Sprites',
                'Ropes',
                'Dynamic lights',
                'Weapon effects'
            })

            misc.fps_optimize = fps_optimize
        end

        local automatic_purchase = { } do
            automatic_purchase.enabled = config_system.push(
                'visuals', 'buy_bot.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Other', new_key('Auto buy', 'buy_bot')
                )
            )

            automatic_purchase.primary = config_system.push(
                'visuals', 'buy_bot.primary', menu.new(
                    ui.new_combobox, 'AA', 'Other', new_key('Primary', 'buy_bot'), {
                        'Off',
                        'AWP',
                        'Scout',
                        'G3SG1 / SCAR-20'
                    }
                )
            )

            automatic_purchase.alternative = config_system.push(
                'visuals', 'buy_bot.alternative', menu.new(
                    ui.new_combobox, 'AA', 'Other', new_key('Alternative', 'buy_bot'), {
                        'Off',
                        'Scout',
                        'G3SG1 / SCAR-20'
                    }
                )
            )

            automatic_purchase.secondary = config_system.push(
                'visuals', 'buy_bot.secondary', menu.new(
                    ui.new_combobox, 'AA', 'Other', new_key('Secondary', 'buy_bot'), {
                        'Off',
                        'P250',
                        'Elites',
                        'Five-seven / Tec-9 / CZ75',
                        'Deagle / Revolver'
                    }
                )
            )

            automatic_purchase.equipment = config_system.push(
                'visuals', 'buy_bot.equipment', menu.new(
                    ui.new_multiselect, 'AA', 'Other', new_key('Equipment', 'buy_bot'), {
                        'Kevlar',
                        'Kevlar + Helmet',
                        'Defuse kit',
                        'HE',
                        'Smoke',
                        'Molotov',
                        'Taser'
                    }
                )
            )

            automatic_purchase.ignore_pistol_round = config_system.push(
                'visuals', 'buy_bot.ignore_pistol_round', menu.new(
                    ui.new_checkbox, 'AA', 'Other', new_key('Ignore pistol round', 'buy_bot')
                )
            )

            automatic_purchase.only_16k = config_system.push(
                'visuals', 'buy_bot.only_16k', menu.new(
                    ui.new_checkbox, 'AA', 'Other', new_key('Only $16k', 'buy_bot')
                )
            )

            misc.automatic_purchase = automatic_purchase
        end

        local discord_rpc = { } do
            discord_rpc.enabled = config_system.push(
                'visuals', 'discord_rpc.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Other', new_key('Discord RPC', 'discord_rpc')
                )
            )

            misc.discord_rpc = discord_rpc
        end

        local killsay = { } do
            killsay.enabled = config_system.push(
                'visuals', 'killsay.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Killsay', 'killsay')
                )
            )

            misc.killsay = killsay
        end

        local net_graph = { } do
            net_graph.enabled = config_system.push(
                'visuals', 'net_graph.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Net graph', 'net_graph')
                )
            )

            net_graph.color = config_system.push(
                'visuals', 'net_graph.color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Net graph', 'net_graph'), 90, 200, 130, 255
                )
            )

            misc.net_graph = net_graph
        end

        local compensate_throw = { } do
            compensate_throw.enabled = config_system.push(
                'visuals', 'compensate_throw.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Other', new_key('Compensate throw', 'compensate_throw')
                )
            )

            misc.compensate_throw = compensate_throw
        end

        ref.misc = misc
    end

    local debug = { } do
        local correction = { } do
            correction.enabled = config_system.push(
                'visuals', 'correction.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('\ab6b665ffkittysolver', 'correction')
                )
            )

            correction.mode = config_system.push(
                'visuals', 'correction.mode', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Resolver mode', 'correction'), {
                        'kittysolver',
                        'desync resolver'
                    }
                )
            )

            correction.offset = config_system.push(
                'visuals', 'correction.offset', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Offset', 'correction'), -20, 20, 0, true, '°'
                )
            )

            ragebot.correction = correction
        end

        local defensive_mode = { } do
            defensive_mode.mode = config_system.push(
                'visuals', 'defensive_mode.mode', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Defensive mode', 'defensive_mode'), {
                        'Default',
                        'Ember',
                        'Wraith',
                        'GS Tools'
                    }
                )
            )

            defensive_mode.callback = config_system.push(
                'visuals', 'defensive_mode.callback', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Defensive check type', 'defensive_callback'), {
                        'predict_command',
                        'net_update_end'
                    }
                )
            )

            defensive_mode.callback_note = menu.new(
                ui.new_label, 'AA', 'Anti-aimbot angles', new_key('\aFFB0B0FFnet_update_end only works with Default & GS Tools', 'defensive_callback_note')
            )

            debug.defensive_mode = defensive_mode

            get_defensive_mode = function()
                return defensive_mode.mode:get()
            end

            get_defensive_callback = function()
                return defensive_mode.callback:get()
            end
        end

        local debug_panel = { } do
            debug_panel.enabled = config_system.push(
                'visuals', 'debug_panel.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Debug panel', 'debug_panel')
                )
            )

            debug_panel.color = config_system.push(
                'visuals', 'debug_panel.color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Accent color', 'debug_panel'), 200, 130, 255, 255
                )
            )

            debug_panel.gc_monitor = config_system.push(
                'visuals', 'debug_panel.gc_monitor', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('GC monitor', 'debug_panel')
                )
            )

            debug_panel.layout = config_system.push(
                'visuals', 'debug_panel.layout', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Layout', 'debug_panel'), 'Vertical', 'Horizontal'
                )
            )

            debug.debug_panel = debug_panel
        end

        local clock_correction = { } do
            clock_correction.enabled = config_system.push(
                'visuals', 'clock_correction.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Clock correction', 'clock_correction')
                )
            )

            clock_correction.adaptive = config_system.push(
                'visuals', 'clock_correction.adaptive', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Adaptive latency', 'clock_correction')
                )
            )

            clock_correction.override = config_system.push(
                'visuals', 'clock_correction.override', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Override', 'clock_correction'), 1, 100, 30, true, 'ms'
                )
            )

            debug.clock_correction = clock_correction
        end

        local anti_defensive = { } do
            anti_defensive.enabled = config_system.push(
                'visuals', 'anti_defensive.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('\aFF6060FFAnti-Defensive', 'anti_defensive')
                )
            )

            anti_defensive.hotkey = config_system.push(
                'visuals', 'anti_defensive.hotkey', menu.new(
                    ui.new_hotkey, 'AA', 'Anti-aimbot angles', new_key('Anti-Defensive key', 'anti_defensive'), true
                )
            )

            debug.anti_defensive = anti_defensive
        end

        local spotify_player = { } do
            spotify_player.enabled = config_system.push(
                'visuals', 'spotify_player.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Spotify player', 'spotify_player')
                )
            )

            spotify_player.color = config_system.push(
                'visuals', 'spotify_player.color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Accent color', 'spotify_player'), 30, 215, 96, 255
                )
            )

            spotify_player.auth_label = menu.new(
                ui.new_label, 'AA', 'Anti-aimbot angles', new_key('\aFF9090FF1. Get token  2. Copy it  3. Click Auth', 'spotify_auth_label')
            )

            spotify_player.get_token_ref = ui.new_button('AA', 'Anti-aimbot angles', 'Get Spotify Token', function()
                local js = panorama.loadstring([[
                    return {
                        open_url: function(url){
                            SteamOverlayAPI.OpenURL(url)
                        }
                    }
                ]])()
                js.open_url('https://spotify.stbrouwers.cc/')
            end)
            ui.set_visible(spotify_player.get_token_ref, false)

            spotify_player.auth_button_ref = ui.new_button('AA', 'Anti-aimbot angles', 'Authenticate Spotify', function()
                local token = sp_read_clipboard()
                if token and #token > 10 then
                    sp_auth_state.refresh_token = token
                    sp_save_token()
                    sp_fetch_token()
                end
            end)
            ui.set_visible(spotify_player.auth_button_ref, false)

            spotify_player.connected_label = ui.new_label('AA', 'Anti-aimbot angles', '\a1ED760FFConnected to Spotify')
            ui.set_visible(spotify_player.connected_label, false)

            spotify_player.connecting_label = ui.new_label('AA', 'Anti-aimbot angles', '\aAAAAAAFFConnecting...')
            ui.set_visible(spotify_player.connecting_label, false)

            -- label gradient animation
            client.set_event_callback('paint_ui', function()
                local t = globals.realtime()
                if sp_auth_state.authed then
                    local text = 'Connected to Spotify'
                    local result = ''
                    for i = 1, #text do
                        local s = (math.sin((t * 3.0) + (i * 0.4)) + 1) * 0.5
                        local r = math.floor(30 + (255 - 30) * s * 0.7)
                        local g = math.floor(215 + (255 - 215) * s * 0.7)
                        local b = math.floor(96 + (255 - 96) * s * 0.7)
                        result = result .. string.format('\a%02x%02x%02xFF', r, g, b) .. text:sub(i, i)
                    end
                    ui.set(spotify_player.connected_label, result)
                elseif sp_auth_state.status == 'connecting' then
                    local text = 'Connecting...'
                    local result = ''
                    for i = 1, #text do
                        local s = (math.sin((t * 4.0) + (i * 0.5)) + 1) * 0.5
                        local c = math.floor(100 + 155 * s)
                        result = result .. string.format('\a%02x%02x%02xFF', c, c, math.min(255, c + 10)) .. text:sub(i, i)
                    end
                    ui.set(spotify_player.connecting_label, result)
                end
            end)

            spotify_player.disconnect_ref = ui.new_button('AA', 'Anti-aimbot angles', 'Disconnect Spotify', function()
                sp_auth_state.refresh_token = nil
                sp_auth_state.apikey = nil
                sp_auth_state.authed = false
                sp_auth_state.status = 'idle'
                sp_auth_state.pending = false
                sp_auth_state.device_id = nil
                database.write('catboy#spotify_auth', {})
                if sp_on_auth_change then sp_on_auth_change() end
            end)
            ui.set_visible(spotify_player.disconnect_ref, false)

            spotify_player.layout = config_system.push(
                'visuals', 'spotify_player.layout', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Layout', 'spotify_player'), 'Default', 'Minimal'
                )
            )

            debug.spotify_player = spotify_player
        end

        ref.debug = debug

        local credits = { } do
            credits.title = menu.new(
                ui.new_label, 'AA', 'Fake lag', new_key('\aFFB0B0FF✦  Credits', 'credits.title')
            )

            credits.separator1 = menu.new(
                ui.new_label, 'AA', 'Fake lag', new_key('\n', 'credits.sep1')
            )

            credits.main_dev_label = menu.new(
                ui.new_label, 'AA', 'Fake lag', new_key('\a808080FF─── \aFFB0B0FF♡ \a808080FF───────────────', 'credits.main_dev_label')
            )

            credits.main_dev = menu.new(
                ui.new_label, 'AA', 'Fake lag', new_key('\aC8C8C8FFMain Developer', 'credits.main_dev')
            )

            credits.main_dev_name = menu.new(
                ui.new_label, 'AA', 'Fake lag', new_key('\aFFFFFFFFalthea/altheauwu', 'credits.main_dev_name')
            )

            credits.separator2 = menu.new(
                ui.new_label, 'AA', 'Fake lag', new_key('\n', 'credits.sep2')
            )

            credits.helpers_label = menu.new(
                ui.new_label, 'AA', 'Fake lag', new_key('\a808080FF─── \aFFB0B0FF✦ \a808080FF───────────────', 'credits.helpers_label')
            )

            credits.helpers = menu.new(
                ui.new_label, 'AA', 'Fake lag', new_key('\aC8C8C8FFHelpers & Contributors', 'credits.helpers')
            )

            credits.helpers_names = menu.new(
                ui.new_label, 'AA', 'Fake lag', new_key('\aFFFFFFFFmar, eccolife, davariousdeshawnhoodclips.2013, sleepycatboy', 'credits.helpers_names')
            )

            credits.separator3 = menu.new(
                ui.new_label, 'AA', 'Fake lag', new_key('\n', 'credits.sep3')
            )

            credits.thank_you_line = menu.new(
                ui.new_label, 'AA', 'Fake lag', new_key('\a808080FF─── \aFFB0B0FF♡ \a808080FF───────────────', 'credits.thank_you_line')
            )

            credits.thank_you = menu.new(
                ui.new_label, 'AA', 'Fake lag', new_key('\aC8C8C8FFThank you to everyone who helped', 'credits.thank_you')
            )

            credits.thank_you2 = menu.new(
                ui.new_label, 'AA', 'Fake lag', new_key('\aC8C8C8FFmake catboy possible!', 'credits.thank_you2')
            )

            credits.separator4 = menu.new(
                ui.new_label, 'AA', 'Fake lag', new_key('\n', 'credits.sep4')
            )

            credits.socials_button = menu.new(
                ui.new_button, 'AA', 'Fake lag', '\aFFB0B0FF♡ My socials!', function()
                    panorama.loadstring([[SteamOverlayAPI.OpenExternalBrowserURL("https://slat.cc/lanes")]])()
                end
            )
        end

        ref.credits = credits

        local fakelag = { } do
            local HOTKEY_MODE = {
                [0] = 'Always on',
                [1] = 'On hotkey',
                [2] = 'Toggle',
                [3] = 'Off hotkey'
            }

            local function get_hotkey_value(_, mode, key)
                return HOTKEY_MODE[mode], key or 0
            end

            fakelag.enabled = config_system.push(
                'fakelag', 'fakelag.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Fake lag', new_key('Enabled', 'fakelag')
                )
            )

            fakelag.hotkey = config_system.push(
                'fakelag', 'fakelag.hotkey', menu.new(
                    ui.new_hotkey, 'AA', 'Fake lag', new_key('Hotkey', 'fakelag'), true
                )
            )

            fakelag.amount = config_system.push(
                'fakelag', 'fakelag.amount', menu.new(
                    ui.new_combobox, 'AA', 'Fake lag', new_key('Amount', 'fakelag'), {
                        'Dynamic',
                        'Maximum',
                        'Fluctuate'
                    }
                )
            )

            fakelag.variance = config_system.push(
                'fakelag', 'fakelag.variance', menu.new(
                    ui.new_slider, 'AA', 'Fake lag', new_key('Variance', 'fakelag'), 0, 100, 0, true, '%'
                )
            )

            fakelag.limit = config_system.push(
                'fakelag', 'fakelag.limit', menu.new(
                    ui.new_slider, 'AA', 'Fake lag', new_key('Limit', 'fakelag'), 1, 15, 13
                )
            )

            fakelag.enabled:set(ui.get(software.antiaimbot.fake_lag.enabled[1]))
            fakelag.hotkey:set(get_hotkey_value(ui.get(software.antiaimbot.fake_lag.enabled[2])))

            fakelag.amount:set(ui.get(software.antiaimbot.fake_lag.amount))

            fakelag.variance:set(ui.get(software.antiaimbot.fake_lag.variance))
            fakelag.limit:set(ui.get(software.antiaimbot.fake_lag.limit))

            ref.fakelag = fakelag
        end
    end

    local scene do
        local set_antiaimbot_angles do
            local ref = software.antiaimbot.angles

            function set_antiaimbot_angles(value)
                local pitch_value = ui.get(ref.pitch[1])
                local yaw_value = ui.get(ref.yaw[1])
                local body_yaw_value = ui.get(ref.body_yaw[1])

                ui.set_visible(ref.enabled, value)
                ui.set_visible(ref.pitch[1], value)

                if pitch_value == 'Custom' then
                    ui.set_visible(ref.pitch[2], value)
                end

                ui.set_visible(ref.yaw_base, value)
                ui.set_visible(ref.yaw[1], value)

                if yaw_value ~= 'Off' then
                    local yaw_jitter_value = ui.get(ref.yaw_jitter[1])

                    ui.set_visible(ref.yaw[2], value)
                    ui.set_visible(ref.yaw_jitter[1], value)

                    if yaw_jitter_value ~= 'Off' then
                        ui.set_visible(ref.yaw_jitter[2], value)
                    end
                end

                ui.set_visible(ref.body_yaw[1], value)

                if body_yaw_value ~= 'Off' then
                    if body_yaw_value ~= 'Opposite' then
                        ui.set_visible(ref.body_yaw[2], value)
                    end

                    ui.set_visible(ref.freestanding_body_yaw, value)
                end

                ui.set_visible(ref.edge_yaw, value)

                ui.set_visible(ref.freestanding[1], value)
                ui.set_visible(ref.freestanding[2], value)

                ui.set_visible(ref.roll, value)
            end
        end

        local set_antiaimbot_fakelag do
            local ref = software.antiaimbot.fake_lag

            function set_antiaimbot_fakelag(value)
                ui.set_visible(ref.enabled[1], value)
                ui.set_visible(ref.enabled[2], value)

                ui.set_visible(ref.amount, value)
                ui.set_visible(ref.variance, value)
                ui.set_visible(ref.limit, value)
            end
        end

        local set_other_display do
            local ref = software.antiaimbot.other

            function set_other_display(value)
                ui.set_visible(ref.slow_motion[1], value)
                ui.set_visible(ref.slow_motion[2], value)

                ui.set_visible(ref.leg_movement, value)

                ui.set_visible(ref.on_shot_antiaim[1], value)
                ui.set_visible(ref.on_shot_antiaim[2], value)

                ui.set_visible(ref.fake_peek[1], value)
                ui.set_visible(ref.fake_peek[2], value)
            end
        end

        local function update_builder_items(items)
            local defensive = items.defensive

            if items.enabled ~= nil then
                menu_logic.set(items.enabled, true)

                if not items.enabled:get() then
                    return
                end
            end

            if items.pitch ~= nil then
                menu_logic.set(items.pitch, true)

                if items.pitch:get() == 'Custom' then
                    menu_logic.set(items.pitch_offset, true)
                end
            end

            if items.yaw ~= nil then
                menu_logic.set(items.yaw, true)

                if items.yaw:get() ~= 'Off' then
                    if items.yaw:get() == '180 LR' then
                        menu_logic.set(items.yaw_left, true)
                        menu_logic.set(items.yaw_right, true)

                        menu_logic.set(items.yaw_asynced, true)
                    else
                        menu_logic.set(items.yaw_offset, true)
                    end

                    menu_logic.set(items.yaw_jitter, true)

                    if items.yaw_jitter:get() ~= 'Off' then
                        menu_logic.set(items.jitter_offset, true)
                    end
                end
            end

            menu_logic.set(items.body_yaw, true)

            if items.body_yaw:get() ~= 'Off' then
                if items.body_yaw:get() ~= 'Opposite' then
                    menu_logic.set(items.body_yaw_offset, true)
                end

                menu_logic.set(items.freestanding_body_yaw, true)

                if items.body_yaw:get() == 'Jitter' then
                    menu_logic.set(items.delay_body_1, true)
                    menu_logic.set(items.delay_body_2, true)
                end

                if items.body_yaw:get() == 'Jitter' and items.invert_chance ~= nil then
                    menu_logic.set(items.invert_chance, true)
                end

                if items.body_yaw:get() == 'LBY' then
                    menu_logic.set(items.lby_desync, true)
                    menu_logic.set(items.lby_inverter, true)
                end

                if items.body_yaw:get() == 'Hold Yaw' and items.hold_time ~= nil then
                    menu_logic.set(items.hold_time, true)
                    menu_logic.set(items.hold_delay, true)
                end

                if items.body_yaw:get() == 'Tick' and items.tick_speed ~= nil then
                    menu_logic.set(items.tick_speed, true)
                    menu_logic.set(items.tick_delay, true)
                end
            end

            menu_logic.set(items.roll_value, true)

            if items.separator ~= nil then
                menu_logic.set(items.separator, true)
            end

            if defensive ~= nil then
                if defensive.force_break_lc ~= nil then
                    menu_logic.set(defensive.force_break_lc, true)
                end

                menu_logic.set(defensive.enabled, true)

                if defensive.enabled:get() then
                    menu_logic.set(defensive.pitch, true)

                    if defensive.pitch:get() ~= 'Off' then
                        menu_logic.set(defensive.pitch_offset_1, true)

                        if defensive.pitch:get() ~= 'Static' then
                            menu_logic.set(defensive.pitch_label_1, true)
                            menu_logic.set(defensive.pitch_label_2, true)

                            menu_logic.set(defensive.pitch_offset_2, true)
                        end

                        if defensive.pitch:get() == 'Spin' then
                            menu_logic.set(defensive.pitch_speed, true)
                        end

                        if defensive.pitch:get() == 'Sway' then
                            menu_logic.set(defensive.pitch_randomize_offset, true)
                            menu_logic.set(defensive.pitch_speed, true)
                        end
                    end

                    menu_logic.set(defensive.yaw, true)

                    if defensive.yaw:get() ~= 'Off' then

                        if defensive.yaw:get() == 'Static LR' then
                            menu_logic.set(defensive.yaw_left, true)
                            menu_logic.set(defensive.yaw_right, true)
                        else
                            menu_logic.set(defensive.yaw_offset, true)
                        end

                        if defensive.yaw:get() == 'Spin' then
                            menu_logic.set(defensive.yaw_speed, true)
                        end

                        if defensive.yaw:get() == 'Sway' then
                            menu_logic.set(defensive.yaw_randomize_offset, true)
                            menu_logic.set(defensive.yaw_left, true)
                            menu_logic.set(defensive.yaw_right, true)
                            menu_logic.set(defensive.yaw_offset, false)
                            menu_logic.set(defensive.yaw_speed, true)
                        end

                        if defensive.yaw:get() == 'Static Random' then
                            --menu_logic.set(defensive.yaw_randomize_offset, true)
                            menu_logic.set(defensive.yaw_left, true)
                            menu_logic.set(defensive.yaw_right, true)
                            menu_logic.set(defensive.yaw_offset, false)
                            --menu_logic.set(defensive.yaw_speed, true)
                        end

                        if defensive.yaw:get() == 'X-Way' then
                            menu_logic.set(defensive.ways_count, true)
                            menu_logic.set(defensive.ways_custom, true)

                            if defensive.ways_custom:get() then
                                local ways_count = defensive.ways_count:get()
                                for i = 1, ways_count do
                                    menu_logic.set(defensive['way_' .. i], true)
                                end
                            else
                                menu_logic.set(defensive.yaw_offset, true)
                            end

                            menu_logic.set(defensive.ways_auto_body_yaw, true)
                        end

                        menu_logic.set(defensive.yaw_modifier, true)

                        if defensive.yaw_modifier:get() ~= 'Off' then
                            menu_logic.set(defensive.modifier_offset, true)
                        end
                    end

                    menu_logic.set(defensive.body_yaw, true)

                    if defensive.body_yaw:get() ~= 'Off' then
                        if defensive.body_yaw:get() ~= 'Opposite' then
                            menu_logic.set(defensive.body_yaw_offset, true)
                        end

                        menu_logic.set(defensive.freestanding_body_yaw, true)

                        if defensive.body_yaw:get() == 'Jitter' then
                            menu_logic.set(defensive.delay_1, true)
                            menu_logic.set(defensive.delay_2, true)
                        end
                    end

                    local activation = defensive.activation:get()
                    menu_logic.set(defensive.activation, true)

                    if activation == 'Sensitivity' then
                        menu_logic.set(defensive.sensitivity_start, true)
                        menu_logic.set(defensive.sensitivity_end, true)
                    end
                end
            end
        end

        local function force_update_scene()
            menu_logic.set(general.label, true)

            local category = general.category:get()
            menu_logic.set(general.category, true)
            ui.set_visible(debug.spotify_player.get_token_ref, false)
            ui.set_visible(debug.spotify_player.auth_button_ref, false)
            ui.set_visible(debug.spotify_player.connected_label, false)
            ui.set_visible(debug.spotify_player.disconnect_ref, false)
            ui.set_visible(debug.spotify_player.connecting_label, false)

            if category == 'Configs' then
                menu_logic.set(general.welcome_text, true)
                menu_logic.set(general.build_name, true)
                menu_logic.set(general.empty_bag, true)
                menu_logic.set(general.line, true)


                menu_logic.set(config.list, true)
                menu_logic.set(config.input, true)

                menu_logic.set(config.load_button, true)
                menu_logic.set(config.save_button, true)
                menu_logic.set(config.delete_button, true)
                menu_logic.set(config.import_button, true)
                menu_logic.set(config.export_button, true)
            end

            if category == 'Ragebot' then
                local is_aimbot_logs = ragebot.aimbot_logs.enabled:get() do
                    menu_logic.set(ragebot.aimbot_logs.enabled, true)

                    if is_aimbot_logs then
                        menu_logic.set(ragebot.aimbot_logs.select, true)

                        if ragebot.aimbot_logs.select:get 'Screen' then
                            menu_logic.set(ragebot.aimbot_logs.color_hit, true)
                            menu_logic.set(ragebot.aimbot_logs.color_miss, true)

                            menu_logic.set(ragebot.aimbot_logs.glow, true)
                            menu_logic.set(ragebot.aimbot_logs.offset, true)
                            menu_logic.set(ragebot.aimbot_logs.duration, true)
                            menu_logic.set(ragebot.aimbot_logs.transparency, true)
                        end
                    end
                end

                local is_aimtools = ragebot.aimtools.enabled:get() do
                    menu_logic.set(ragebot.aimtools.enabled, true)

                    if is_aimtools then
                        menu_logic.set(ragebot.aimtools.weapon, true)

                        local weapon = ragebot.aimtools.weapon:get()
                        local items = ragebot.aimtools[weapon]

                        if items ~= nil then
                            menu_logic.set(items.body_aim.enabled, true)

                            if items.body_aim.enabled:get() then
                                menu_logic.set(items.body_aim.select, true)

                                if items.body_aim.select:get 'After X misses' then
                                    menu_logic.set(items.body_aim.misses, true)
                                end

                                if items.body_aim.select:get 'HP lower than X' then
                                    menu_logic.set(items.body_aim.health, true)
                                end
                            end

                            menu_logic.set(items.safe_points.enabled, true)

                            if items.safe_points.enabled:get() then
                                menu_logic.set(items.safe_points.select, true)

                                if items.safe_points.select:get 'After X misses' then
                                    menu_logic.set(items.safe_points.misses, true)
                                end

                                if items.safe_points.select:get 'HP lower than X' then
                                    menu_logic.set(items.safe_points.health, true)
                                end
                            end

                            menu_logic.set(items.multipoints.enabled, true)

                            if items.multipoints.enabled:get() then
                                menu_logic.set(items.multipoints.note, true)

                                for i = 1, #ragebot.aimtools.states do
                                    local state = ragebot.aimtools.states[i]

                                    menu_logic.set(items.multipoints[state], true)
                                end
                            end

                            menu_logic.set(items.accuracy_boost.enabled, true)

                            if items.accuracy_boost.enabled:get() then
                                menu_logic.set(items.accuracy_boost.value, true)
                            end
                        end

                        menu_logic.set(ragebot.aimtools.hitchance_override.enabled, true)

                        if ragebot.aimtools.hitchance_override.enabled:get() then
                            menu_logic.set(ragebot.aimtools.hitchance_override.hotkey, true)
                            menu_logic.set(ragebot.aimtools.hitchance_override.value, true)
                        end
                    end
                end

                menu_logic.set(ragebot.dt_boost.enabled, true)

                menu_logic.set(ragebot.recharge_fix.enabled, true)
                menu_logic.set(ragebot.recharge_fix_experimental.enabled, true)

                local is_auto_hide_shots = ragebot.auto_hide_shots.enabled:get() do
                    menu_logic.set(ragebot.auto_hide_shots.enabled, true)

                    if not is_auto_hide_shots then
                        goto continue
                    end

                    menu_logic.set(ragebot.auto_hide_shots.weapons, true)
                    menu_logic.set(ragebot.auto_hide_shots.states, true)

                    ::continue::
                end

                menu_logic.set(ragebot.jump_scout.enabled, true)

                local is_defensive_fix = ragebot.defensive_fix.enabled:get() do
                    menu_logic.set(ragebot.defensive_fix.enabled, true)

                    if not is_defensive_fix then
                        goto continue
                    end

                    menu_logic.set(ragebot.defensive_fix.pop_up, true)

                    ::continue::
                end
                    

                menu_logic.set(ref.fakelag.enabled, true)
                menu_logic.set(ref.fakelag.hotkey, true)
                menu_logic.set(ref.fakelag.amount, true)
                menu_logic.set(ref.fakelag.variance, true)
                menu_logic.set(ref.fakelag.limit, true)
            end

            if category == 'Anti-Aim' then
                local builder do
                    local ref = antiaim.builder

                    local state = ref.state:get()
                    menu_logic.set(ref.state, true)

                    local items = ref[state]

                    if items ~= nil then
                        update_builder_items(items)
                    end
                end

                local settings do
                    local ref = antiaim.settings

                    local is_disablers = ref.disablers.enabled:get() do
                        menu_logic.set(ref.disablers.enabled, true)

                        if is_disablers then
                            menu_logic.set(ref.disablers.select, true)
                        end
                    end

                    menu_logic.set(ref.avoid_backstab.enabled, true)

                    local is_safe_head = ref.safe_head.enabled:get() do
                        menu_logic.set(ref.safe_head.enabled, true)

                        if is_safe_head then
                            menu_logic.set(ref.safe_head.states, true)
                        end
                    end

                    menu_logic.set(ref.freestanding.enabled, true)
                    menu_logic.set(ref.freestanding.hotkey, true)

                    local is_manual_yaw = ref.manual_yaw.enabled:get() do
                        menu_logic.set(ref.manual_yaw.enabled, true)

                        if is_manual_yaw then
                            menu_logic.set(ref.manual_yaw.disable_yaw_modifiers, true)
                            menu_logic.set(ref.manual_yaw.body_freestanding, true)

                            menu_logic.set(ref.manual_yaw.left_hotkey, true)
                            menu_logic.set(ref.manual_yaw.right_hotkey, true)
                            menu_logic.set(ref.manual_yaw.forward_hotkey, true)
                            menu_logic.set(ref.manual_yaw.backward_hotkey, true)
                            menu_logic.set(ref.manual_yaw.reset_hotkey, true)
                        end
                    end

                    local is_defensive_flick = ref.defensive_flick.enabled:get() do
                        menu_logic.set(ref.defensive_flick.enabled, true)

                        if is_defensive_flick then
                            menu_logic.set(ref.defensive_flick.states, true)
                            menu_logic.set(ref.defensive_flick.inverter, true)
                            menu_logic.set(ref.defensive_flick.pitch, true)
                            menu_logic.set(ref.defensive_flick.yaw, true)
                            menu_logic.set(ref.defensive_flick.yaw_random, true)
                            menu_logic.set(ref.defensive_flick.auto_body_yaw, true)
                            menu_logic.set(ref.defensive_flick.speed, true)
                            menu_logic.set(ref.defensive_flick.speed_random, true)
                        end
                    end
                end
            end

            if category == 'Visuals' then
                menu_logic.set(general.welcome_text, true)
                menu_logic.set(general.build_name, true)
                menu_logic.set(general.empty_bag, true)
                menu_logic.set(general.line, true)
                local is_aspect_ratio = visuals.aspect_ratio.enabled:get() do
                    menu_logic.set(visuals.aspect_ratio.enabled, true)

                    if is_aspect_ratio then
                        menu_logic.set(visuals.aspect_ratio.value, true)
                    end
                end

                local is_third_person = visuals.third_person.enabled:get() do
                    menu_logic.set(visuals.third_person.enabled, true)

                    if is_third_person then
                        menu_logic.set(visuals.third_person.distance, true)
                        menu_logic.set(visuals.third_person.zoom_speed, true)
                    end
                end

                local is_viewmodel = visuals.viewmodel.enabled:get() do
                    menu_logic.set(visuals.viewmodel.enabled, true)

                    if is_viewmodel then
                        menu_logic.set(visuals.viewmodel.fov, true)
                        menu_logic.set(visuals.viewmodel.offset_x, true)
                        menu_logic.set(visuals.viewmodel.offset_y, true)
                        menu_logic.set(visuals.viewmodel.offset_z, true)
                        menu_logic.set(visuals.viewmodel.opposite_knife_hand, true)
                    end
                end

                menu_logic.set(visuals.scope_animation.enabled, true)

                local is_custom_scope = visuals.custom_scope.enabled:get() do
                    menu_logic.set(visuals.custom_scope.enabled, true)

                    if is_custom_scope then
                        menu_logic.set(visuals.custom_scope.color, true)
                        menu_logic.set(visuals.custom_scope.position, true)
                        menu_logic.set(visuals.custom_scope.size, true)
                        menu_logic.set(visuals.custom_scope.offset, true)
                        menu_logic.set(visuals.custom_scope.animation_speed, true)
                    end
                end

                local is_world_marker = visuals.world_marker.enabled:get() do
                    menu_logic.set(visuals.world_marker.enabled, true)

                    if is_world_marker then
                        menu_logic.set(visuals.world_marker.color, true)
                    end
                end

                local is_damage_marker = visuals.damage_marker.enabled:get() do
                    menu_logic.set(visuals.damage_marker.enabled, true)

                    if is_damage_marker then
                        menu_logic.set(visuals.damage_marker.color, true)
                    end
                end

                local is_damage_indicator = visuals.damage_indicator.enabled:get() do
                    menu_logic.set(visuals.damage_indicator.enabled, true)

                    if is_damage_indicator then
                        menu_logic.set(visuals.damage_indicator.only_if_active, true)
                        menu_logic.set(visuals.damage_indicator.font, true)
                        menu_logic.set(visuals.damage_indicator.offset, true)

                        menu_logic.set(visuals.damage_indicator.active_label, true)
                        menu_logic.set(visuals.damage_indicator.active_color, true)

                        if not visuals.damage_indicator.only_if_active:get() then
                            menu_logic.set(visuals.damage_indicator.inactive_label, true)
                            menu_logic.set(visuals.damage_indicator.inactive_color, true)
                        end

                        menu_logic.set(visuals.damage_indicator.separator, true)
                    end
                end

                local watermark_value = visuals.watermark.select:get() do
                    menu_logic.set(visuals.watermark.select, true)

                    if watermark_value == 'Alternative' then
                        menu_logic.set(visuals.watermark.color, true)
                    end
                end

                local is_indicators = visuals.indicators.enabled:get() do
                    menu_logic.set(visuals.indicators.enabled, true)

                    if is_indicators then
                        menu_logic.set(visuals.indicators.style, true)

                        menu_logic.set(visuals.indicators.color_accent, true)
                        menu_logic.set(visuals.indicators.color_secondary, true)

                        menu_logic.set(visuals.indicators.offset, true)
                    end
                end

                local is_defensive_bar = visuals.defensive_bar.enabled:get() do
                    menu_logic.set(visuals.defensive_bar.enabled, true)

                    if is_defensive_bar then
                        menu_logic.set(visuals.defensive_bar.color, true)
                        menu_logic.set(visuals.defensive_bar.glow, true)
                        menu_logic.set(visuals.defensive_bar.segmented, true)
                        menu_logic.set(visuals.defensive_bar.fade_color, true)
                        menu_logic.set(visuals.defensive_bar.position_y, true)
                        menu_logic.set(visuals.defensive_bar.height, true)
                    end
                end

                local is_cat_whiskers = visuals.cat_whiskers.enabled:get() do
                    menu_logic.set(visuals.cat_whiskers.enabled, true)

                    if is_cat_whiskers then
                        menu_logic.set(visuals.cat_whiskers.color, true)
                        menu_logic.set(visuals.cat_whiskers.size, true)
                        menu_logic.set(visuals.cat_whiskers.glow, true)
                        menu_logic.set(visuals.cat_whiskers.animate, true)
                    end
                end

                local is_manual_arrows = visuals.manual_arrows.enabled:get() do
                    menu_logic.set(visuals.manual_arrows.enabled, true)

                    if is_manual_arrows then
                        menu_logic.set(visuals.manual_arrows.style, true)

                        menu_logic.set(visuals.manual_arrows.color_accent, true)

                        if visuals.manual_arrows.style:get() == 'Alternative' then
                            menu_logic.set(visuals.manual_arrows.color_secondary, true)
                        end
                    end
                end

                local is_velocity_warning = visuals.velocity_warning.enabled:get() do
                    menu_logic.set(visuals.velocity_warning.enabled, true)
                    menu_logic.set(visuals.velocity_warning.color, true)

                    if is_velocity_warning then
                        menu_logic.set(visuals.velocity_warning.offset, true)
                    end
                end

                local is_velocity_graph = visuals.velocity_graph.enabled:get() do
                    menu_logic.set(visuals.velocity_graph.enabled, true)

                    if is_velocity_graph then
                        menu_logic.set(visuals.velocity_graph.color, true)
                        menu_logic.set(visuals.velocity_graph.height, true)
                        menu_logic.set(visuals.velocity_graph.width, true)
                    end
                end

                local is_custom_killfeed = visuals.custom_killfeed.enabled:get() do
                    menu_logic.set(visuals.custom_killfeed.enabled, true)

                    if is_custom_killfeed then
                        menu_logic.set(visuals.custom_killfeed.bg_active, true)
                        menu_logic.set(visuals.custom_killfeed.bg_inactive, true)
                        menu_logic.set(visuals.custom_killfeed.attacker_color, true)
                        menu_logic.set(visuals.custom_killfeed.attacked_color, true)
                        menu_logic.set(visuals.custom_killfeed.weapon_color, true)
                        menu_logic.set(visuals.custom_killfeed.headshot_color, true)
                        menu_logic.set(visuals.custom_killfeed.size, true)
                    end
                end
            end

            if category == 'Misc' then
                menu_logic.set(general.welcome_text, true)
                menu_logic.set(general.build_name, true)
                menu_logic.set(general.empty_bag, true)
                menu_logic.set(general.line, true)
                menu_logic.set(misc.clantag.enabled, true)

                menu_logic.set(misc.increase_ladder_movement.enabled, true)

                local is_animation_breaker = misc.animation_breaker.enabled:get() do
                    menu_logic.set(misc.animation_breaker.enabled, true)

                    if is_animation_breaker then
                        menu_logic.set(misc.animation_breaker.in_air_legs, true)
                        menu_logic.set(misc.animation_breaker.onground_legs, true)
                        menu_logic.set(misc.animation_breaker.adjust_lean, true)
                        menu_logic.set(misc.animation_breaker.pitch_on_land, true)
                        menu_logic.set(misc.animation_breaker.freeburger, true)
                        menu_logic.set(misc.animation_breaker.perfect, true)

                        if misc.animation_breaker.perfect:get() then
                            menu_logic.set(misc.animation_breaker.perfect_slider, true)
                        end
                    end
                end

                menu_logic.set(misc.walking_on_quick_peek.enabled, true)

                local is_enhance_grenade_release = misc.enhance_grenade_release.enabled:get() do
                    menu_logic.set(misc.enhance_grenade_release.enabled, true)

                    if is_enhance_grenade_release then
                        menu_logic.set(misc.enhance_grenade_release.disablers, true)
                        menu_logic.set(misc.enhance_grenade_release.only_with_dt, true)
                        menu_logic.set(misc.enhance_grenade_release.separator, true)
                    end
                end

                local is_fps_optimize = misc.fps_optimize.enabled:get() do
                    menu_logic.set(misc.fps_optimize.enabled, true)

                    if is_fps_optimize then
                        menu_logic.set(misc.fps_optimize.always_on, true)

                        if not misc.fps_optimize.always_on:get() then
                            menu_logic.set(misc.fps_optimize.detections, true)
                        end

                        menu_logic.set(misc.fps_optimize.list, true)
                        menu_logic.set(misc.fps_optimize.separator, true)
                    end
                end

                local is_auto_buy = misc.automatic_purchase.enabled:get() do
                    menu_logic.set(misc.automatic_purchase.enabled, true)

                    if is_auto_buy then
                        menu_logic.set(misc.automatic_purchase.primary, true)

                        if misc.automatic_purchase.primary:get() == 'AWP' then
                            menu_logic.set(misc.automatic_purchase.alternative, true)
                        end

                        menu_logic.set(misc.automatic_purchase.secondary, true)
                        menu_logic.set(misc.automatic_purchase.equipment, true)
                        menu_logic.set(misc.automatic_purchase.ignore_pistol_round, true)
                        menu_logic.set(misc.automatic_purchase.only_16k, true)
                    end
                end

                menu_logic.set(misc.discord_rpc.enabled, true)

                menu_logic.set(misc.killsay.enabled, true)

                menu_logic.set(misc.net_graph.enabled, true)

                if misc.net_graph.enabled:get() then
                    menu_logic.set(misc.net_graph.color, true)
                end

                menu_logic.set(misc.compensate_throw.enabled, true)
            end

            if category == 'Debug' then
                menu_logic.set(general.welcome_text, true)
                menu_logic.set(general.build_name, true)
                menu_logic.set(general.empty_bag, true)
                menu_logic.set(general.line, true)

                menu_logic.set(debug.defensive_mode.mode, true)
                menu_logic.set(debug.defensive_mode.callback, true)

                if debug.defensive_mode.callback:get() == 'net_update_end' then
                    menu_logic.set(debug.defensive_mode.callback_note, true)
                end

                menu_logic.set(debug.debug_panel.enabled, true)

                if debug.debug_panel.enabled:get() then
                    menu_logic.set(debug.debug_panel.color, true)
                    menu_logic.set(debug.debug_panel.gc_monitor, true)
                    menu_logic.set(debug.debug_panel.layout, true)
                end

                menu_logic.set(debug.clock_correction.enabled, true)

                if debug.clock_correction.enabled:get() then
                    menu_logic.set(debug.clock_correction.adaptive, true)

                    if not debug.clock_correction.adaptive:get() then
                        menu_logic.set(debug.clock_correction.override, true)
                    end
                end

                menu_logic.set(debug.anti_defensive.enabled, true)

                if debug.anti_defensive.enabled:get() then
                    menu_logic.set(debug.anti_defensive.hotkey, true)
                end

                menu_logic.set(debug.spotify_player.enabled, true)

                if debug.spotify_player.enabled:get() then
                    menu_logic.set(debug.spotify_player.color, true)
                    menu_logic.set(debug.spotify_player.layout, true)
                    if sp_auth_state.authed then
                        ui.set_visible(debug.spotify_player.connected_label, true)
                        ui.set_visible(debug.spotify_player.disconnect_ref, true)
                    elseif sp_auth_state.status == 'connecting' then
                        ui.set_visible(debug.spotify_player.connecting_label, true)
                    else
                        menu_logic.set(debug.spotify_player.auth_label, true)
                        ui.set_visible(debug.spotify_player.get_token_ref, true)
                        ui.set_visible(debug.spotify_player.auth_button_ref, true)
                    end
                end

                menu_logic.set(ragebot.correction.enabled, true)
                if ragebot.correction.enabled:get() then
                    menu_logic.set(ragebot.correction.mode, true)
                end
                menu_logic.set(ragebot.correction.offset, true)
            end

            if category == 'Credits' then
                menu_logic.set(ref.credits.title, true)
                menu_logic.set(ref.credits.separator1, true)
                menu_logic.set(ref.credits.main_dev_label, true)
                menu_logic.set(ref.credits.main_dev, true)
                menu_logic.set(ref.credits.main_dev_name, true)
                menu_logic.set(ref.credits.separator2, true)
                menu_logic.set(ref.credits.helpers_label, true)
                menu_logic.set(ref.credits.helpers, true)
                menu_logic.set(ref.credits.helpers_names, true)
                menu_logic.set(ref.credits.separator3, true)
                menu_logic.set(ref.credits.thank_you_line, true)
                menu_logic.set(ref.credits.thank_you, true)
                menu_logic.set(ref.credits.thank_you2, true)
                menu_logic.set(ref.credits.separator4, true)
                menu_logic.set(ref.credits.socials_button, true)
            end
        end

        local function on_shutdown()
            set_antiaimbot_angles(true)
            set_antiaimbot_fakelag(true)
            set_other_display(true)
        end

        local function on_paint_ui()
            local category = general.category:get()

            set_antiaimbot_angles(false)
            set_antiaimbot_fakelag(false)
            set_other_display(category == 'Ragebot')
        end

        local logic_events = menu_logic.get_event_bus() do
            logic_events.update:set(force_update_scene)

            force_update_scene()
            menu_logic.force_update()
        end

        sp_on_auth_change = function()
            force_update_scene()
            menu_logic.force_update()
        end

        client.set_event_callback('shutdown', on_shutdown)
        client.set_event_callback('paint_ui', on_paint_ui)
    end
end

local override do
    override = { }

    local item_data = { }

    local e_hotkey_mode = {
        [0] = 'Always on',
        [1] = 'On hotkey',
        [2] = 'Toggle',
        [3] = 'Off hotkey'
    }

    local function get_value(item)
        local type = ui.type(item)
        local value = { ui.get(item) }

        if type == 'hotkey' then
            local mode = e_hotkey_mode[value[2]]
            local keycode = value[3] or 0

            return { mode, keycode }
        end

        return value
    end

    function override.get(item)
        local value = item_data[item]

        if value == nil then
            return nil
        end

        return unpack(value)
    end

    function override.set(item, ...)
        if item_data[item] == nil then
            item_data[item] = get_value(item)
        end

        ui.set(item, ...)
    end

    function override.unset(item)
        local value = item_data[item]

        if value == nil then
            return
        end

        ui.set(item, unpack(value))
        item_data[item] = nil
    end
end

local ragebot do
    ragebot = { }

    local item_data = { }

    local ref_weapon_type = ui.reference(
        'Rage', 'Weapon type', 'Weapon type'
    )

    local e_hotkey_mode = {
        [0] = 'Always on',
        [1] = 'On hotkey',
        [2] = 'Toggle',
        [3] = 'Off hotkey'
    }

    local function get_value(item)
        local type = ui.type(item)
        local value = { ui.get(item) }

        if type == 'hotkey' then
            local mode = e_hotkey_mode[value[2]]
            local keycode = value[3] or 0

            return { mode, keycode }
        end

        return value
    end

    function ragebot.set(item, ...)
        local weapon_type = ui.get(ref_weapon_type)

        if item_data[item] == nil then
            item_data[item] = { }
        end

        local data = item_data[item]

        if data[weapon_type] == nil then
            data[weapon_type] = {
                type = weapon_type,
                value = get_value(item)
            }
        end

        ui.set(item, ...)
    end

    function ragebot.unset(item)
        local data = item_data[item]

        if data == nil then
            return
        end

        local weapon_type = ui.get(ref_weapon_type)

        for k, v in pairs(data) do
            ui.set(ref_weapon_type, v.type)
            ui.set(item, unpack(v.value))

            data[k] = nil
        end

        ui.set(ref_weapon_type, weapon_type)
        item_data[item] = nil
    end
end

local motion do
    motion = { }

    local function linear(t, b, c, d)
        return c * t / d + b
    end

    local function get_deltatime()
        return globals.frametime()
    end

    local function solve(easing_fn, prev, new, clock, duration)
        if clock <= 0 then return new end
        if clock >= duration then return new end

        prev = easing_fn(clock, prev, new - prev, duration)

        if type(prev) == 'number' then
            if math.abs(new - prev) < 0.001 then
                return new
            end

            local remainder = prev % 1.0

            if remainder < 0.001 then
                return math.floor(prev)
            end

            if remainder > 0.999 then
                return math.ceil(prev)
            end
        end

        return prev
    end

    function motion.interp(a, b, t, easing_fn)
        easing_fn = easing_fn or linear

        if type(b) == 'boolean' then
            b = b and 1 or 0
        end

        return solve(easing_fn, a, b, get_deltatime(), t)
    end
end

local color do
    color = ffi.typeof [[
        struct {
            unsigned char r;
            unsigned char g;
            unsigned char b;
            unsigned char a;
        }
    ]]

    local M = { } do
        M.__index = M

        function M.lerp(a, b, t)
            return color(
                a.r + t * (b.r - a.r),
                a.g + t * (b.g - a.g),
                a.b + t * (b.b - a.b),
                a.a + t * (b.a - a.a)
            )
        end

        function M:unpack()
            return self.r, self.g, self.b, self.a
        end

        function M:clone()
            return color(self:unpack())
        end

        function M:__tostring()
            return string.format(
                '%i, %i, %i, %i',
                self:unpack()
            )
        end
    end

    ffi.metatype(color, M)
end

local render do
    render = { }

    local function sign(x)
        if x > 0 then
            return 1
        end

        if x < 0 then
            return -1
        end

        return 0
    end

    local function interpolate_colors(color1, color2, factor)
        local temp_array, temp_array_count = { }, 1
        local color3 = { color1[1], color1[2], color1[3], color1[4] }

        for i = 1, 4 do
            temp_array[temp_array_count] = tonumber(('%.0f'):format(
                color3[i] + factor * (color2[i] - color1[i])
            ))

            temp_array_count = temp_array_count + 1
        end

        return temp_array
    end

    local function interpolate_colors_range(color1, color2, steps)
        local factor = 1 / (steps - 1)
        local temp_array, temp_array_count = { }, 1

        for i = 0, steps-1 do
            temp_array[temp_array_count] = interpolate_colors(color1, color2, factor*i)
            temp_array_count = temp_array_count + 1
        end

        return temp_array
    end

    function render.glow(x, y, w, h, r, g, b, a, radius, steps, range)
        steps = math.max(2, steps)
        range = range or 1.0

        local outline_thickness = 1

        local colors = interpolate_colors_range(
            { r, g, b, 0 },
            { r, g, b, a * range },
            steps
        )

        for i = 1, steps do
            renderer.circle_outline(x + radius, y + radius, colors[i][1], colors[i][2], colors[i][3], colors[i][4], radius+outline_thickness+(steps-i), 180, 0.25, 1)
            renderer.circle_outline(x + w - radius, y + radius, colors[i][1], colors[i][2], colors[i][3], colors[i][4], radius+outline_thickness+(steps-i), 270, 0.25, 1)
            renderer.circle_outline(x + w - radius, y + h - radius, colors[i][1], colors[i][2], colors[i][3], colors[i][4], radius+outline_thickness+(steps-i), 0, 0.25, 1)
            renderer.circle_outline(x + radius, y + h - radius, colors[i][1], colors[i][2], colors[i][3], colors[i][4], radius+outline_thickness+(steps-i), 90, 0.25, 1)

            renderer.rectangle(x + w + i - 1, y + radius, 1, h - 2 * radius, colors[steps-i+1][1], colors[steps-i+1][2], colors[steps-i+1][3], colors[steps-i+1][4])
            renderer.rectangle(x - i, y + radius, 1, h - 2 * radius, colors[steps-i+1][1], colors[steps-i+1][2], colors[steps-i+1][3], colors[steps-i+1][4])

            renderer.rectangle(x + radius, y - i, w - 2 * radius, 1, colors[steps-i+1][1], colors[steps-i+1][2], colors[steps-i+1][3], colors[steps-i+1][4])
            renderer.rectangle(x + radius, y + h + i - 1, w - 2 * radius, 1, colors[steps-i+1][1], colors[steps-i+1][2], colors[steps-i+1][3], colors[steps-i+1][4])
        end
    end

    function render.rectangle_outline(x, y, w, h, r, g, b, a, thickness, radius)
        if thickness == nil or thickness == 0 then
            thickness = 1
        end

        if radius == nil then
            radius = 0
        end

        local wt = sign(w) * thickness
        local ht = sign(h) * thickness

        local pad = radius == 1 and 1 or 0

        local pad_2 = pad * 2
        local radius_2 = radius * 2

        renderer.circle_outline(x + radius, y + radius, r, g, b, a, radius, 180, 0.25, thickness)
        renderer.circle_outline(x + radius, y + h - radius, r, g, b, a, radius, 90, 0.25, thickness)
        renderer.circle_outline(x + w - radius, y + radius, r, g, b, a, radius, 270, 0.25, thickness)
        renderer.circle_outline(x + w - radius, y + h - radius, r, g, b, a, radius, 0, 0.25, thickness)

        renderer.rectangle(x, y + radius, wt, h - radius_2, r, g, b, a)
        renderer.rectangle(x + w, y + radius, -wt, h - radius_2, r, g, b, a)

        renderer.rectangle(x + pad + radius, y, w - pad_2 - radius_2, ht, r, g, b, a)
        renderer.rectangle(x + pad + radius, y + h, w - pad_2 - radius_2, -ht, r, g, b, a)
    end

    function render.rectangle(x, y, w, h, r, g, b, a, radius)
        radius = math.min(radius, w / 2, h / 2)

        local radius_2 = radius * 2

        renderer.rectangle(x + radius, y, w - radius_2, h, r, g, b, a)
        renderer.rectangle(x, y + radius, radius, h - radius_2, r, g, b, a)
        renderer.rectangle(x + w - radius, y + radius, radius, h - radius_2, r, g, b, a)

        renderer.circle(x + radius, y + radius, r, g, b, a, radius, 180, 0.25)
        renderer.circle(x + radius, y + h - radius, r, g, b, a, radius, 270, 0.25)
        renderer.circle(x + w - radius, y + radius, r, g, b, a, radius, 90, 0.25)
        renderer.circle(x + w - radius, y + h - radius, r, g, b, a, radius, 0, 0.25)
    end
end

local features do
    local rage do
        local air_autostop do
            local HEIGHT_PEAK = 18

            local cl_sidespeed = cvar.cl_sidespeed

            local item_enabled = ui.new_checkbox(
                'Rage', 'Aimbot', 'Air autostop'
            )

            local item_air_autoscope = ui.new_checkbox(
                'Rage', 'Aimbot', 'Air autoscope'
            )

            local item_on_peak_of_height = ui.new_checkbox(
                'Rage', 'Aimbot', 'On peak of height'
            )

            local item_distance = ui.new_slider(
                'Rage', 'Aimbot', 'Distance', 0, 1000, 350, true, 'u', 1, {
                    [0] = '∞'
                }
            )

            local item_delay = ui.new_slider(
                'Rage', 'Aimbot', 'Delay', 0, 16, 0, true, 't', 1, {
                    [0] = 'Off'
                }
            )

            local item_minimum_damage = ui.new_slider(
                'Rage', 'Aimbot', 'Minimum damage', -1, 130, -1, true, 'hp', 1, (function()
                    local hint = {
                        [-1] = 'Inherited'
                    }

                    for i = 1, 30 do
                        hint[100 + i] = string.format(
                            'HP + %d', i
                        )
                    end

                    return hint
                end)()
            )

            local stop_tick = -1
            local prediction_data = nil

            local function entity_is_ready(ent)
                return globals.curtime() >= entity.get_prop(ent, 'm_flNextAttack')
            end

            local function entity_can_fire(ent)
                return globals.curtime() >= entity.get_prop(ent, 'm_flNextPrimaryAttack')
            end

            function create_data(flags, velocity)
                local data = { }

                data.flags = flags or 0
                data.velocity = velocity or vector()

                return data
            end

            local function get_highest_damage(player, target)
                local eye_pos = nil

                if player == entity.get_local_player() then
                    eye_pos = vector(client.eye_position())
                else
                    eye_pos = vector(utils.get_eye_position(player))
                end

                local head = vector(entity.hitbox_position(target, 0))
                local stomach = vector(entity.hitbox_position(target, 3))

                local _, head_damage = client.trace_bullet(player, eye_pos.x, eye_pos.y, eye_pos.z, head.x, head.y, head.z)
                local _, stomach_damage = client.trace_bullet(player, eye_pos.x, eye_pos.y, eye_pos.z, stomach.x, stomach.y, stomach.z)

                return math.max(head_damage, stomach_damage)
            end

            local function update_autostop(cmd, minimum)
                local me = entity.get_local_player()

                if me == nil or prediction_data == nil then
                    return
                end

                local velocity = prediction_data.velocity
                local speed = velocity:length2d()

                if minimum ~= nil and speed < minimum then
                    return
                end

                local direction = vector(velocity:angles())
                local real_view = vector(client.camera_angles())

                direction.y = real_view.y - direction.y

                local forward = vector():init_from_angles(
                    direction:unpack()
                )

                local negative_side_move = -cl_sidespeed:get_float()
                local negative_direction = negative_side_move * forward

                cmd.in_speed = 1

                cmd.forwardmove = negative_direction.x
                cmd.sidemove = negative_direction.y
            end

            local function on_predict_command(cmd)
                local me = entity.get_local_player()

                if me == nil then
                    return
                end

                local flags = entity.get_prop(me, 'm_fFlags')
                local velocity = vector(entity.get_prop(me, 'm_vecVelocity'))

                prediction_data = create_data(flags, velocity)
            end

            local function on_setup_command(cmd)
                local me = entity.get_local_player()
                local threat = client.current_threat()

                if me == nil or threat == nil then
                    return
                end

                local wpn = entity.get_player_weapon(me)

                if wpn == nil or not entity_is_ready(me) or not entity_can_fire(wpn) then
                    return
                end

                local wpn_info = csgo_weapons(wpn)
                if wpn_info == nil or wpn_info.type == 'grenade' or wpn_info.type == 'knife' then
                    return
                end

                local origin = vector(client.eye_position())
                local pos = vector(entity.get_origin(threat))

                pos.z = pos.z + 60

                local distance = pos:dist(origin)
                local max_distance = ui.get(item_distance)

                if max_distance ~= 0 and distance > max_distance then
                    return
                end

                local velocity = vector(entity.get_prop(me, 'm_vecVelocity'))
                local animstate = c_entity(me):get_anim_state()

                if animstate == nil or animstate.on_ground then
                    return
                end

                local tick = cmd.command_number
                local delay = ui.get(item_delay)

                local is_delaying = delay ~= 0
                local check_peak = ui.get(item_on_peak_of_height)

                local is_scoped = entity.get_prop(me, 'm_bIsScoped') ~= 0
                local is_force = is_delaying and (stop_tick > tick) or true

                local is_peaking = check_peak and (math.abs(velocity.z) < HEIGHT_PEAK) or true
                local is_downgoing = origin.z < animstate.last_origin_z

                if not is_force then
                    if is_downgoing or not is_peaking then
                        return
                    end

                    if is_delaying then
                        stop_tick = tick + delay
                    end
                end

                local max_damage = software.is_override_minimum_damage()
                    and software.get_override_damage()
                    or software.get_minimum_damage()

                local damage = get_highest_damage(me, threat)
                local health = entity.get_prop(threat, 'm_iHealth')

                if max_damage > 100 then
                    max_damage = health + (max_damage - 100)
                end

                if damage < max_damage then
                    return
                end

                local data = csgo_weapons(wpn)

                local max_speed = is_scoped
                    and data.max_player_speed_alt
                    or data.max_player_speed

                max_speed = max_speed * 0.34

                -- autoscope snipers
                if ui.get(item_air_autoscope) then
                    if data.type == 'sniperrifle' and not is_scoped then
                        cmd.in_attack2 = 1
                    end
                end

                update_autostop(cmd, max_speed)
            end

            local callbacks do
                local function on_enabled(item)
                    local value = ui.get(item)

                    ui.set_visible(item_air_autoscope, value)
                    ui.set_visible(item_on_peak_of_height, value)
                    ui.set_visible(item_distance, value)
                    ui.set_visible(item_delay, value)
                    ui.set_visible(item_minimum_damage, value)

                    utils.event_callback('predict_command', on_predict_command, value)
                    utils.event_callback('setup_command', on_setup_command, value)
                end

                ui.set_callback(item_enabled, on_enabled)
                on_enabled(item_enabled)
            end
        end

        
        local aimtools do
            local ref = ref.ragebot.aimtools

            local ref_multipoint_scale = ui.reference(
                'Rage', 'Aimbot', 'Multi-point scale'
            )

            local ref_accuracy_boost = ui.reference(
                'Rage', 'Other', 'Accuracy boost'
            )

            local ref_min_hitchance = ui.reference(
                'Rage', 'Aimbot', 'Minimum hit chance'
            )

            local WEAPON_DEAGLE = 1
            local WEAPON_REVOLVER = 64
            local WEAPON_AWP = 9
            local WEAPON_SSG08 = 40
            local WEAPON_TASER = 31

            local manipulation do
                manipulation = { }

                local item_data = { }

                function manipulation.set(entindex, item_name, ...)
                    if item_data[entindex] == nil then
                        item_data[entindex] = { }
                    end

                    if item_data[entindex][item_name] == nil then
                        item_data[entindex][item_name] = {
                            plist.get(entindex, item_name)
                        }
                    end

                    plist.set(entindex, item_name, ...)
                end

                function manipulation.unset(entindex, item_name)
                    local entity_data = item_data[entindex]

                    if entity_data == nil then
                        return
                    end

                    local item_values = entity_data[item_name]

                    if item_values == nil then
                        return
                    end

                    plist.set(entindex, item_name, unpack(item_values))

                    entity_data[item_name] = nil
                end

                function manipulation.override(entindex, item_name, ...)
                    if ... ~= nil then
                        manipulation.set(entindex, item_name, ...)
                    else
                        manipulation.unset(entindex, item_name)
                    end
                end
            end

            local function is_enemy_higher_than_me(enemy)
                local me = entity.get_local_player()

                local enemy_origin = vector(entity.get_origin(enemy))
                local my_origin = vector(entity.get_origin(me))

                local distance = enemy_origin.z - my_origin.z

                return distance > 32
            end

            local function is_enemy_lower_than_me(enemy)
                local me = entity.get_local_player()

                local enemy_origin = vector(entity.get_origin(enemy))
                local my_origin = vector(entity.get_origin(me))

                local distance = my_origin.z - enemy_origin.z

                return distance > 32
            end

            local miss_counts = { }

            for i = 1, 64 do
                miss_counts[i] = 0
            end

            local function on_aim_miss(e)
                local target = e.target
                if target ~= nil and target > 0 and target <= 64 then
                    miss_counts[target] = miss_counts[target] + 1
                end
            end

            local function on_aim_hit(e)
                local target = e.target
                if target ~= nil and target > 0 and target <= 64 then
                    miss_counts[target] = 0
                end
            end

            local function on_round_start()
                for i = 1, 64 do
                    miss_counts[i] = 0
                end
            end

            local function is_lethal_body(me, enemy)
                local health = entity.get_prop(enemy, 'm_iHealth')

                if health == nil or health <= 0 then
                    return false
                end

                local eye_pos = vector(client.eye_position())
                local stomach = vector(entity.hitbox_position(enemy, 3))

                if stomach == nil then
                    return false
                end

                local _, body_damage = client.trace_bullet(me, eye_pos.x, eye_pos.y, eye_pos.z, stomach.x, stomach.y, stomach.z)

                return body_damage >= health
            end

            local ba_active = { }
            local sp_active = { }

            local function get_weapon_type(weapon)
                local weapon_info = csgo_weapons(weapon)

                if weapon_info == nil then
                    return nil
                end

                local weapon_idx = weapon_info.idx
                local weapon_type = weapon_info.type

                if weapon_type == 'pistol' then
                    if weapon_idx == WEAPON_DEAGLE then
                        return 'Desert Eagle'
                    end

                    if weapon_idx == WEAPON_REVOLVER then
                        return 'R8 Revolver'
                    end

                    return 'Pistol'
                end

                if weapon_type == 'sniperrifle' then
                    if weapon_idx == WEAPON_AWP then
                        return 'AWP'
                    end

                    if weapon_idx == WEAPON_SSG08 then
                        return 'SSG 08'
                    end

                    return 'G3SG1 / SCAR-20'
                end

                if weapon_idx == WEAPON_TASER then
                    return 'Zeus'
                end

                return nil
            end

            local function evaluate_conditions(me, enemy, select, misses_slider, health_slider)
                if select:get 'Higher than you' then
                    if is_enemy_higher_than_me(enemy) then
                        return true
                    end
                end

                if select:get 'Lower than you' then
                    if is_enemy_lower_than_me(enemy) then
                        return true
                    end
                end

                if select:get 'Lethal' then
                    if is_lethal_body(me, enemy) then
                        return true
                    end
                end

                if select:get 'After X misses' then
                    local count = miss_counts[enemy] or 0

                    if count >= misses_slider:get() then
                        return true
                    end
                end

                if select:get 'HP lower than X' then
                    local health = entity.get_prop(enemy, 'm_iHealth')

                    if health ~= nil and health <= health_slider:get() then
                        return true
                    end
                end

                return false
            end

            local function get_body_aim_value(me, enemy, items)
                if not items.body_aim.enabled:get() then
                    return false
                end

                return evaluate_conditions(me, enemy, items.body_aim.select, items.body_aim.misses, items.body_aim.health)
            end

            local function get_safe_point_value(me, enemy, items)
                if not items.safe_points.enabled:get() then
                    return false
                end

                return evaluate_conditions(me, enemy, items.safe_points.select, items.safe_points.misses, items.safe_points.health)
            end

            local function get_enemy_state(enemy)
                local flags = entity.get_prop(enemy, 'm_fFlags')
                if flags == nil then
                    return nil
                end

                local is_onground = bit.band(flags, 1) ~= 0
                local duck_amount = entity.get_prop(enemy, 'm_flDuckAmount') or 0
                local is_crouched = duck_amount > 0.5

                if not is_onground then
                    return 'Air'
                end

                local velocity = vector(entity.get_prop(enemy, 'm_vecVelocity'))
                local velocity2d_sqr = velocity:length2dsqr()
                local is_moving = velocity2d_sqr > 5 * 5

                if is_crouched then
                    if is_moving then
                        return 'Move-Crouch'
                    end
                    return 'Crouch'
                end

                if is_moving then
                    return 'Moving'
                end

                return 'Standing'
            end

            local function get_multipoints_value(enemy, items)
                if not items.multipoints.enabled:get() then
                    return nil
                end

                local state = get_enemy_state(enemy)

                local value = items.multipoints[state]

                if value == nil then
                    return nil
                end

                return value:get()
            end

            local function get_accuracy_boost_value(enemy, items)
                if not items.accuracy_boost.enabled:get() then
                    return nil
                end

                return items.accuracy_boost.value:get()
            end

            local function get_hitchance_override_value()
                if not ref.hitchance_override.enabled:get() then
                    software._hitchance_override_active = false
                    return nil
                end

                if not ref.hitchance_override.hotkey:get() then
                    software._hitchance_override_active = false
                    return nil
                end

                software._hitchance_override_active = true
                return ref.hitchance_override.value:get()
            end

            local function reset_player_list()
                for i = 1, 64 do
                    manipulation.unset(i, 'Override prefer body aim')
                    manipulation.unset(i, 'Override safe point')
                    ba_active[i] = false
                    sp_active[i] = false
                end
            end

            local function update_aim_tools()
                local me = entity.get_local_player()

                if me == nil then
                    return false
                end

                local weapon = entity.get_player_weapon(me)

                if weapon == nil then
                    return false
                end

                local enemies = entity.get_players(true)
                local weapon_type = get_weapon_type(weapon)

                local items = ref[weapon_type]

                if items == nil then
                    return false
                end

                local hitchance = get_hitchance_override_value()

                if hitchance ~= nil then
                    ragebot.set(ref_min_hitchance, hitchance)
                else
                    ragebot.unset(ref_min_hitchance)
                end

                for i = 1, #enemies do
                    local enemy = enemies[i]

                    local body_aim = get_body_aim_value(me, enemy, items)
                    local safe_point = get_safe_point_value(me, enemy, items)
                    local multipoints = get_multipoints_value(enemy, items)
                    local accuracy_boost = get_accuracy_boost_value(enemy, items)

                    ba_active[enemy] = body_aim
                    sp_active[enemy] = safe_point

                    if safe_point then
                        manipulation.set(enemy, 'Override safe point', 'On')
                    else
                        manipulation.unset(enemy, 'Override safe point')
                    end

                    if body_aim then
                        manipulation.set(enemy, 'Override prefer body aim', 'Force')
                    else
                        manipulation.unset(enemy, 'Override prefer body aim')
                    end

                    if multipoints ~= nil then
                        ragebot.set(ref_multipoint_scale, multipoints)
                    else
                        ragebot.unset(ref_multipoint_scale)
                    end

                    if accuracy_boost ~= nil then
                        override.set(ref_accuracy_boost, accuracy_boost)
                    else
                        override.unset(ref_accuracy_boost)
                    end
                end

                return true
            end

            local function on_shutdown()
                reset_player_list()
                ragebot.unset(ref_min_hitchance)
            end

            local function on_run_command()
                if not update_aim_tools() then
                    reset_player_list()
                    ragebot.unset(ref_min_hitchance)
                end
            end

            -- esp flags
            client.register_esp_flag('', 100, 200, 255, function(player)
                if not ref.enabled:get() then
                    return
                end

                if ba_active[player] then
                    return true, 'BA'
                end
            end)

            client.register_esp_flag('', 255, 180, 100, function(player)
                if not ref.enabled:get() then
                    return
                end

                if sp_active[player] then
                    return true, 'SP'
                end
            end)

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        reset_player_list()
                    end

                    utils.event_callback('shutdown', on_shutdown, value)
                    utils.event_callback('run_command', on_run_command, value)
                    utils.event_callback('aim_miss', on_aim_miss, value)
                    utils.event_callback('aim_hit', on_aim_hit, value)
                    utils.event_callback('round_start', on_round_start, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local defensive_fix do
            local ref = ref.ragebot.defensive_fix

            local ref_doubletap = {
                ui.reference('Rage', 'Aimbot', 'Double tap')
            }

            local function extrapolate(pos, velocity, ticks)
                return pos + velocity * (globals.tickinterval() * ticks)
            end

            local function is_double_tap()
                return ui.get(ref_doubletap[1])
                    and ui.get(ref_doubletap[2])
            end

            local function is_player_peeking(ticks)
                local me = entity.get_local_player()

                if me == nil then
                    return
                end

                local enemies = entity.get_players(true)

                if next(enemies) == nil then
                    return false
                end

                local eye_pos = extrapolate(
                    vector(client.eye_position()),
                    vector(entity.get_prop(me, 'm_vecVelocity')),
                    ticks
                )

                for i = 1, #enemies do
                    local enemy = enemies[i]

                    local head_pos = extrapolate(
                        vector(entity.hitbox_position(enemy, 0)),
                        vector(entity.get_prop(enemy, 'm_vecVelocity')),
                        ticks
                    )

                    local _, damage = client.trace_bullet(me, eye_pos.x, eye_pos.y, eye_pos.z, head_pos.x, head_pos.y, head_pos.z)

                    if damage > 0 then
                        --print(damage)
                        return true
                    end
                end

                return false
            end


            local function should_update()
                if not is_double_tap() then
                    return false
                end

                if not is_player_peeking(8) then
                    return false
                end

                return true
            end

            local should_print = false

            local function on_setup_command(cmd)
                if not should_update() then
                    should_print = true
                    return
                end

                cmd.force_defensive = true

                local tickcount = entity.get_prop(entity.get_local_player(), 'm_nTickBase')

                if should_print and ref.pop_up:get() then
                    if cmd.quick_stop then
                        --print("~ defensive required due to skeet's autostop")
                        logging_system.default(string.format(
                            "defensive required due to skeet's autostop (%s tickcount)", tickcount
                        ))
                    else
                        --print('~ defensive fixed on ' .. tickcount .. ' tickcount')
                        logging_system.default(string.format(
                            'defensive successfully modified on %s tickcount', tickcount
                        ))
                    end

                    should_print = false
                end

            end

            local callbacks do
                local function on_enabled(item)
                    utils.event_callback(
                        'setup_command',
                        on_setup_command,
                        item:get()
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local correction do
            local ref = ref.ragebot.correction

            -- ffi anim state access
            local classptr = ffi.typeof('void***')
            local get_client_entity_type = ffi.typeof('void*(__thiscall*)(void*, int)')
            local raw_entity_list = client.create_interface('client_panorama.dll', 'VClientEntityList003')
            local ks_entity_list_ptr = ffi.cast(classptr, raw_entity_list) or error('Entity list interface not found', 2)
            local ks_get_client_entity = ffi.cast(get_client_entity_type, ks_entity_list_ptr[0][3])

            ffi.cdef[[
                typedef struct KS_CBasePlayer KS_CBasePlayer;
                typedef struct KS_CBaseCombatWeapon KS_CBaseCombatWeapon;

//                typedef struct { --accessing animation layers were causing crashes, so for now i'm just leaving this here for future reference
//                    bool m_bClientBlend;
//                    float m_flBlendIn;
//                    void* m_pStudioHdr;
//                    int m_nDispatchSequence;
//                    int m_nDispatchSequence_2;
//                    uint32_t m_nOrder;
//                    uint32_t m_nSequence;
//                    float m_flPrevCycle;
//                    float m_flWeight;
//                    float m_flWeightDeltaRate;
//                    float m_flPlaybackRate;
//                    float m_flCycle;
//                    KS_CBasePlayer* m_pOwner;
//                    char pad_0038[4];
//                } KS_AnimationLayer;

                typedef struct {
                    char pad0[0x60];
                    KS_CBasePlayer* pEntity;
                    KS_CBaseCombatWeapon* pWeapon;
                    KS_CBaseCombatWeapon* pWeaponLast;
                    float flLastUpdateTime;
                    int nLastUpdateFrame;
                    float flLastUpdateIncrement;
                    float flEyeYaw;
                    float flEyePitch;
                    float flFootYaw;
                    float flLastFootYaw;
                    float flMoveYaw;
                    float flMoveYawIdeal;
                    float flMoveYawCurrentToIdeal;
                    float flTimeToAlignLowerBody;
                    float flPrimaryCycle;
                    float flMoveWeight;
                    float flMoveWeightSmoothed;
                    float flDuckAmount;
                    float flDuckAdditional;
                    float flRecrouchWeight;
                    float vecOrigin[3];
                    float vecLastOrigin[3];
                    float vecVelocity[3];
                    float vecVelocityNormalized[3];
                    float vecVelocityNormalizedNonZero[3];
                    float flVelocityLenght2D;
                    float flVelocityZ;
                    float flRunSpeedNormalized;
                    float flWalkSpeedNormalized;
                    float flCrouchSpeedNormalized;
                    float flDurationMoving;
                    float flDurationStill;
                    bool bOnGround;
                    bool bLanding;
                    char pad_landing[2];
                    float flJumpToFall;
                    float flDurationInAir;
                    float flLeftGroundHeight;
                    float flHitGroundWeight;
                    float flWalkToRunTransition;
                    char pad3[0x4];
                    float flInAirSmoothValue;
                    bool bOnLadder;
                    char pad_ladder[3];
                    float flLadderWeights;
                    float flLadderSpeed;
                    bool bWalkToRunTransitionState;
                    bool bDefuseStarted;
                    bool bPlantAnimStarted;
                    bool bTwitchAnimStarted;
                    bool bAdjustStarted;
                    char vecActivityModifiers[20];
                    char pad_activity[3];
                    float flNextTwitchTime;
                    float flTimeOfLastKnownInjury;
                    float flLastVelocityTestTime;
                    char pad_velocity_test[4];
                    float vecVelocityLast[3];
                    float vecTargetAcceleration[3];
                    float vecAcceleration[3];
                    float flAccelerationWeight;
                    float flAimMatrixTransition;
                    float flAimMatrixTransitionDelay;
                    bool bFlashed;
                    char pad_flash[3];
                    float flStrafeChangeWeight;
                    float flStrafeChangeTargetWeight;
                    float flStrafeChangeCycle;
                    int nStrafeSequence;
                    bool bStrafeChanging;
                    char pad_strafe[3];
                    float flDurationStrafing;
                    float flFootLerp;
                    bool bFeetCrossed;
                    bool bPlayerIsAccelerating;
                    char pad4[0x178];
                    float flCameraSmoothHeight;
                    bool bSmoothHeightValid;
                    char pad_smooth[3];
                    float flLastTimeVelocityOverTen;
                    float flAimYawMin;
                    float flAimYawMax;
                    float flAimPitchMin;
                    float flAimPitchMax;
                    int iAnimsetVersion;
                } KS_CCSGOPlayerAnimState;
            ]]

            local function ks_get_entity_address(ent_index)
                if ent_index == nil then
                    print('[catboy] ks_get_entity_address: ent_index is nil')
                    return nil
                end
                local ptr = ks_get_client_entity(ks_entity_list_ptr, ent_index)
                if ptr == nil then
                    print('[catboy] ks_get_entity_address: returned NULL for index ' .. tostring(ent_index))
                    return nil
                end
                return ptr
            end

            local function ks_get_anim_state(player)
                local entity_ptr = ks_get_entity_address(player)
                if entity_ptr == nil then
                    print('[catboy] ks_get_anim_state: entity_ptr is NULL for player index ' .. tostring(player))
                    return nil
                end
                local animstate_ptr = ffi.cast("KS_CCSGOPlayerAnimState**", ffi.cast("char*", entity_ptr) + 0x9960)
                if animstate_ptr == nil or animstate_ptr[0] == nil then
                    print('[catboy] ks_get_anim_state: animstate_ptr is NULL for player index ' .. tostring(player))
                    return nil
                end
                return animstate_ptr[0]
            end

            --[[
            local function ks_get_anim_layer(player, layer_index) -- not used for now since accessing animation layers was causing crashes, but i'll probably try to implement this again in the future since it can be useful for resolver data
                local entity_ptr = ks_get_entity_address(player)
                if entity_ptr == nil then
                    print('[catboy] ks_get_anim_layer: entity_ptr is NULL for player index ' .. tostring(player))
                    return nil
                end
                local anim_layer_ptr = ffi.cast('KS_AnimationLayer**', ffi.cast('char*', entity_ptr) + 0x348)
                if anim_layer_ptr == nil or anim_layer_ptr[0] == nil then
                    print('[catboy] ks_get_anim_layer: anim_layer_ptr is NULL for player index ' .. tostring(player))
                    return nil
                end
                return (layer_index >= 0 and layer_index <= 12) and anim_layer_ptr[0][layer_index] or nil
            end
            ]]

            -- constants which are used for desync calculation, taken from csgo's animstate and animation code
            local CSGO_ANIM_AIMMATRIX_DEFAULT_YAW_MAX = 58.0
            local CS_PLAYER_SPEED_RUN = 260.0
            local CS_PLAYER_SPEED_WALK_MODIFIER = 0.52
            local CS_PLAYER_SPEED_DUCK_MODIFIER = 0.34
            local CSGO_ANIM_AIM_NARROW_WALK = 0.8
            local CSGO_ANIM_AIM_NARROW_RUN = 0.5
            local CSGO_ANIM_AIM_NARROW_CROUCHMOVING = 0.5

            -- helpers
            local function ks_angle_diff(dest, src)
                local delta = (dest - src) % 360
                if delta > 180 then delta = delta - 360 end
                if delta < -180 then delta = delta + 360 end
                return delta
            end

            local function ks_clamp(val, min, max)
                if val < min then return min end
                if val > max then return max end
                return val
            end

            local function ks_lerp(t, a, b)
                return a + t * (b - a)
            end

            -- this function tries to replicate the aim matrix width calculation from csgo's animstate code, which is used to determine the maximum desync angle based on player's speed and duck amount. it's not perfect since there are some other factors that can influence the final value, but it should be close enough for resolver purposes
            local function calculate_aim_matrix_width_range(speed, duck_amount, walk_to_run_transition)
                local speed_walk = speed / (CS_PLAYER_SPEED_RUN * CS_PLAYER_SPEED_WALK_MODIFIER)
                local speed_crouch = speed / (CS_PLAYER_SPEED_RUN * CS_PLAYER_SPEED_DUCK_MODIFIER)

                local width = ks_lerp(
                    ks_clamp(speed_walk, 0, 1),
                    1.0,
                    ks_lerp(walk_to_run_transition, CSGO_ANIM_AIM_NARROW_WALK, CSGO_ANIM_AIM_NARROW_RUN)
                )

                if duck_amount > 0 then
                    width = ks_lerp(
                        duck_amount * ks_clamp(speed_crouch, 0, 1),
                        width,
                        CSGO_ANIM_AIM_NARROW_CROUCHMOVING
                    )
                end

                return width
            end

            local function calculate_max_desync(animstate)
                if not animstate then return CSGO_ANIM_AIMMATRIX_DEFAULT_YAW_MAX end

                local speed = animstate.flVelocityLenght2D
                local duck_amount = animstate.flDuckAmount
                local walk_to_run = animstate.flWalkToRunTransition

                return CSGO_ANIM_AIMMATRIX_DEFAULT_YAW_MAX * calculate_aim_matrix_width_range(speed, duck_amount, walk_to_run)
            end

            -- lag compensation records for resolver, storing the last 32 records for each player. this is used to analyze player's movement and animation data over time, which can help with determining their real orientation and desync angle. the records are created on every tick for alive and non-dormant enemies, and cleared when a player dies or becomes dormant.
            -- Why clear it? Because of two things. 
            local lag_records = { }
            for i = 1, 64 do lag_records[i] = { } end

            local function create_lag_record(player)
                local animstate = ks_get_anim_state(player)
                return {
                    tick = globals.tickcount(),
                    sim_time = entity.get_prop(player, "m_flSimulationTime"),
                    eye_yaw = select(2, entity.get_prop(player, "m_angEyeAngles")),
                    goal_feet_yaw = animstate and animstate.flFootYaw or 0,
                    current_feet_yaw = animstate and animstate.flLastFootYaw or 0,
                    origin = vector(entity.get_prop(player, "m_vecOrigin")),
                    velocity = vector(entity.get_prop(player, "m_vecVelocity")),
                    flags = entity.get_prop(player, "m_fFlags"),
                }
            end

            local tickbase_data = { }
            for i = 1, 64 do tickbase_data[i] = { shifting = false, sim_delta = 0 } end

            local function update_lag_records() -- this function should be called on every tick to update the lag compensation records for all players. it checks if the player is alive and not dormant, then creates a new record and adds it to the player's record list. if the player is dead or dormant, it clears their records and resets their tickbase data. this ensures that we have up-to-date information for the resolver to work with, while also preventing stale data from affecting calculations when a player dies or leaves.
                local enemies = entity.get_players(true)

                for _, player in ipairs(enemies) do
                    if entity.is_alive(player) and not entity.is_dormant(player) then
                        local record = create_lag_record(player)

                        tickbase_data[player].shifting = false
                        tickbase_data[player].sim_delta = 0

                        table.insert(lag_records[player], record)

                        while #lag_records[player] > 32 do
                            table.remove(lag_records[player], 1)
                        end
                    else
                        lag_records[player] = { }
                        tickbase_data[player].shifting = false
                        tickbase_data[player].sim_delta = 0
                    end
                end
            end

            -- resolver data
            local resolver_data = { }
            for i = 1, 64 do
                resolver_data[i] = {
                    resolved_side = 0,
                    resolved_desync = 0,
                    last_side = 0,
                }
            end

            local function resolve_player(player) 
                local idx = player
                if not idx or idx < 1 or idx > 64 then return end

                local records = lag_records[idx]
                if not records or #records < 3 then return end

                local data = resolver_data[idx]
                local animstate = ks_get_anim_state(player)
                if not animstate then return end

                local max_desync = calculate_max_desync(animstate)

                local eye_yaw = select(2, entity.get_prop(player, "m_angEyeAngles"))
                local goal_feet_yaw = animstate.flFootYaw
                local current_feet_yaw = animstate.flLastFootYaw

                local desync_from_goal = ks_angle_diff(eye_yaw, goal_feet_yaw)
                local desync_from_current = ks_angle_diff(eye_yaw, current_feet_yaw)

                local goal_current_delta = math.abs(ks_angle_diff(goal_feet_yaw, current_feet_yaw))

                local side = 0
                local actual_desync = 0

                if math.abs(desync_from_current) > 5.0 then
                    side = (desync_from_current > 0) and 1 or -1
                    actual_desync = ks_clamp(math.abs(desync_from_current), 0, max_desync)
                    data.last_side = side
                else
                    side = data.last_side ~= 0 and data.last_side or -1
                end

                if goal_current_delta > 10.0 then
                    local goal_side = (desync_from_goal > 0) and 1 or -1
                    local current_side = (desync_from_current > 0) and 1 or -1

                    if goal_side ~= current_side then
                        side = -side
                    end
                end

                if side == 0 then
                    side = -1
                end

                data.resolved_side = side
                data.resolved_desync = actual_desync
                data.max_desync = max_desync

                return side, actual_desync, max_desync
            end

            local function apply_resolver()
                local enemies = entity.get_players(true)
                local offset = ref.offset:get()

                local me = entity.get_local_player()
                local my_origin = me and vector(entity.get_prop(me, 'm_vecOrigin'))
                local closest_dist = math.huge
                local closest_player = nil

                for _, player in ipairs(enemies) do
                    if entity.is_alive(player) and not entity.is_dormant(player) then
                        local side, desync = resolve_player(player)
                        if side and desync then
                            local value = math.max(-CSGO_ANIM_AIMMATRIX_DEFAULT_YAW_MAX, math.min(CSGO_ANIM_AIMMATRIX_DEFAULT_YAW_MAX, side * desync + offset))
                            plist.set(player, "Force body yaw", true)
                            plist.set(player, "Force body yaw value", value)
                        end

                        -- closest enemy for debug panel
                        if my_origin then
                            local enemy_origin = vector(entity.get_prop(player, 'm_vecOrigin'))
                            local dist = (enemy_origin - my_origin):length2dsqr()
                            if dist < closest_dist then
                                closest_dist = dist
                                closest_player = player
                            end
                        end
                    else
                        plist.set(player, "Force body yaw", false)
                    end
                end

                -- debug panel data for closest enemy
                if closest_player then
                    local data = resolver_data[closest_player]
                    local animstate = ks_get_anim_state(closest_player)
                    local eye_yaw = select(2, entity.get_prop(closest_player, 'm_angEyeAngles')) or 0
                    local feet_yaw = animstate and animstate.flFootYaw or 0
                    local max_desync = animstate and calculate_max_desync(animstate) or 58

                    debug_panel_info.resolver_active = true
                    debug_panel_info.resolver_target = entity.get_player_name(closest_player) or '?'
                    debug_panel_info.resolver_eye_yaw = eye_yaw
                    debug_panel_info.resolver_feet_yaw = feet_yaw
                    debug_panel_info.resolver_side = data.resolved_side
                    debug_panel_info.resolver_desync = data.resolved_desync
                    debug_panel_info.resolver_max_desync = max_desync
                else
                    debug_panel_info.resolver_active = false
                end
            end

            -- desync resolver (alternative mode)
            local dr_normalize_angle = function(angle)
                while angle > 180 do angle = angle - 360 end
                while angle < -180 do angle = angle + 360 end
                return angle
            end

            local dr_calculate_angle = function(from_pos, to_pos)
                local delta = to_pos - from_pos
                local yaw = math.atan(delta.y / delta.x)
                yaw = dr_normalize_angle(yaw * 180 / math.pi)
                if delta.x >= 0 then
                    yaw = dr_normalize_angle(yaw + 180)
                end
                return yaw
            end

            local dr_player_data = { cur = {}, prev = {}, pre_prev = {}, pre_pre_prev = {} }
            local dr_anti_aim_data = {}

            local function dr_track_player_data(local_player)
                local enemy_players = entity.get_players(true)
                if #enemy_players == 0 then
                    dr_player_data = { cur = {}, prev = {}, pre_prev = {}, pre_pre_prev = {} }
                    return
                end
                for _, player in ipairs(enemy_players) do
                    if entity.is_alive(player) and not entity.is_dormant(player) then
                        local simtime = entity.get_prop(player, "m_flSimulationTime")
                        local simtime_ticks = math.floor(simtime / globals.tickinterval())
                        local esp_flags = entity.get_esp_data(player).flags or 0
                        if bit.band(esp_flags, bit.lshift(1, 17)) ~= 0 then
                            simtime_ticks = simtime_ticks - 14
                        end
                        if dr_player_data.cur[player] == nil or simtime_ticks - dr_player_data.cur[player].simtime >= 1 then
                            dr_player_data.pre_pre_prev[player] = dr_player_data.pre_prev[player]
                            dr_player_data.pre_prev[player] = dr_player_data.prev[player]
                            dr_player_data.prev[player] = dr_player_data.cur[player]
                            local local_origin = vector(entity.get_prop(local_player, "m_vecOrigin"))
                            local player_eye_angles = vector(entity.get_prop(player, "m_angEyeAngles"))
                            local player_origin = vector(entity.get_prop(player, "m_vecOrigin"))
                            local yaw_delta = math.floor(dr_normalize_angle(player_eye_angles.y - dr_calculate_angle(local_origin, player_origin)))
                            local duck_amount = entity.get_prop(player, "m_flDuckAmount")
                            local on_ground = bit.band(entity.get_prop(player, "m_fFlags"), 1) == 1
                            local velocity_2d = vector(entity.get_prop(player, 'm_vecVelocity')):length2d()
                            local stance = on_ground and (duck_amount == 1 and "duck" or (velocity_2d > 1.2 and "running" or "standing")) or "air"
                            local weapon = entity.get_player_weapon(player)
                            local last_shot_time = weapon and entity.get_prop(weapon, "m_fLastShotTime") or nil
                            dr_player_data.cur[player] = {
                                id = player,
                                origin = vector(entity.get_origin(player)),
                                pitch = player_eye_angles.x,
                                yaw = yaw_delta,
                                yaw_backwards = math.floor(dr_normalize_angle(dr_calculate_angle(local_origin, player_origin))),
                                simtime = simtime_ticks,
                                stance = stance,
                                esp_flags = esp_flags,
                                last_shot_time = last_shot_time
                            }
                        end
                    end
                end
            end

            local function dr_analyze_and_apply(local_player)
                if not entity.is_alive(local_player) then return end
                local enemy_players = entity.get_players(true)
                if #enemy_players == 0 then return end

                local offset = ref.offset:get()
                local my_origin = vector(entity.get_prop(local_player, 'm_vecOrigin'))
                local closest_dist = math.huge
                local closest_player = nil

                for _, player in ipairs(enemy_players) do
                    if entity.is_alive(player) and not entity.is_dormant(player) then
                        if dr_player_data.cur[player] ~= nil and dr_player_data.prev[player] ~= nil
                            and dr_player_data.pre_prev[player] ~= nil and dr_player_data.pre_pre_prev[player] ~= nil then

                            local aa_type = nil
                            local is_on_shot = nil
                            local cur = dr_player_data.cur[player]
                            local prev = dr_player_data.prev[player]
                            local pre_prev = dr_player_data.pre_prev[player]
                            local pre_pre_prev = dr_player_data.pre_pre_prev[player]

                            local yaw_change = math.abs(dr_normalize_angle(cur.yaw - prev.yaw))
                            local yaw_delta = dr_normalize_angle(cur.yaw - prev.yaw)

                            if cur.last_shot_time ~= nil then
                                local time_since_shot = globals.curtime() - cur.last_shot_time
                                local ticks_since_shot = time_since_shot / globals.tickinterval()
                                is_on_shot = ticks_since_shot <= math.floor(0.2 / globals.tickinterval())
                            end

                            local cur_yaw = cur.yaw
                            local prev_yaw = prev.yaw
                            local pre_prev_yaw = pre_prev.yaw
                            local pre_pre_prev_yaw = pre_pre_prev.yaw
                            local delta1 = dr_normalize_angle(cur_yaw - prev_yaw)
                            local delta2 = dr_normalize_angle(cur_yaw - pre_prev_yaw)
                            local delta3 = dr_normalize_angle(prev_yaw - pre_pre_prev_yaw)
                            local delta4 = dr_normalize_angle(prev_yaw - pre_prev_yaw)
                            local delta5 = dr_normalize_angle(pre_prev_yaw - pre_pre_prev_yaw)
                            local delta6 = dr_normalize_angle(pre_pre_prev_yaw - cur_yaw)

                            -- classification
                            if is_on_shot and math.abs(math.abs(cur.pitch) - math.abs(prev.pitch)) > 30 and cur.pitch < prev.pitch then
                                aa_type = "ON SHOT"
                            else
                                if math.abs(cur.pitch) > 60 then
                                    if yaw_change > 30 and math.abs(delta2) < 15 and math.abs(delta3) < 15 then
                                        aa_type = "[!!]"
                                    elseif math.abs(delta1) > 15 or math.abs(delta4) > 15 or math.abs(delta5) > 15 or math.abs(delta6) > 15 then
                                        aa_type = "[!!!]"
                                    end
                                end
                            end

                            -- body yaw correction (clamped to real max desync from animstate)
                            -- lanes: [!!] = significant indication of desync side, can be used for more aggressive correction since it's more certain
                            local animstate = ks_get_anim_state(player)
                            local max_desync = calculate_max_desync(animstate)

                            if aa_type == "[!!!]" or aa_type == "[!!]" then
                                if aa_type == "[!!]" then
                                    if dr_normalize_angle(cur_yaw - prev_yaw) > 0 then
                                        plist.set(player, "Force body yaw", true)
                                        plist.set(player, "Force body yaw value", ks_clamp(max_desync + offset, -CSGO_ANIM_AIMMATRIX_DEFAULT_YAW_MAX, CSGO_ANIM_AIMMATRIX_DEFAULT_YAW_MAX))
                                    elseif dr_normalize_angle(cur_yaw - prev_yaw) < 0 then
                                        plist.set(player, "Force body yaw", true)
                                        plist.set(player, "Force body yaw value", ks_clamp(-max_desync + offset, -CSGO_ANIM_AIMMATRIX_DEFAULT_YAW_MAX, CSGO_ANIM_AIMMATRIX_DEFAULT_YAW_MAX))
                                    end
                                elseif aa_type == "[!!!]" then
                                    if (prev_yaw == dr_normalize_angle(cur_yaw - yaw_change) or prev_yaw == dr_normalize_angle(cur_yaw + yaw_change))
                                        and (pre_prev_yaw == dr_normalize_angle(cur_yaw + yaw_change) or pre_prev_yaw == cur_yaw) then
                                        plist.set(player, "Force body yaw", true)
                                        plist.set(player, "Force body yaw value", ks_clamp(0 + offset, -CSGO_ANIM_AIMMATRIX_DEFAULT_YAW_MAX, CSGO_ANIM_AIMMATRIX_DEFAULT_YAW_MAX))
                                    else
                                        if cur_yaw < 0 then
                                            plist.set(player, "Force body yaw", true)
                                            plist.set(player, "Force body yaw value", ks_clamp(max_desync + offset, -CSGO_ANIM_AIMMATRIX_DEFAULT_YAW_MAX, CSGO_ANIM_AIMMATRIX_DEFAULT_YAW_MAX))
                                        else
                                            plist.set(player, "Force body yaw", true)
                                            plist.set(player, "Force body yaw value", ks_clamp(-max_desync + offset, -CSGO_ANIM_AIMMATRIX_DEFAULT_YAW_MAX, CSGO_ANIM_AIMMATRIX_DEFAULT_YAW_MAX))
                                        end
                                    end
                                end
                            else
                                plist.set(player, "Force body yaw", false)
                                plist.set(player, "Force body yaw value", 0)
                            end

                            dr_anti_aim_data[player] = { anti_aim_type = aa_type, yaw_delta = yaw_delta }

                            -- update resolver_data for debug panel compatibility
                            local side = 0
                            local desync = ks_clamp(yaw_change, 0, max_desync)
                            if aa_type == "[!!]" or aa_type == "[!!!]" then
                                side = dr_normalize_angle(cur_yaw - prev_yaw) >= 0 and 1 or -1
                            end
                            resolver_data[player] = {
                                resolved_side = side,
                                resolved_desync = desync,
                                max_desync = max_desync,
                                last_side = side,
                            }
                        end

                        -- closest enemy for debug panel
                        if my_origin then
                            local enemy_origin = vector(entity.get_prop(player, 'm_vecOrigin'))
                            local dist = (enemy_origin - my_origin):length2dsqr()
                            if dist < closest_dist then
                                closest_dist = dist
                                closest_player = player
                            end
                        end
                    else
                        plist.set(player, "Force body yaw", false)
                    end
                end

                -- debug panel data for closest enemy
                if closest_player then
                    local data = resolver_data[closest_player]
                    local animstate = ks_get_anim_state(closest_player)
                    local eye_yaw = select(2, entity.get_prop(closest_player, 'm_angEyeAngles')) or 0
                    local feet_yaw = animstate and animstate.flFootYaw or 0
                    local max_desync = animstate and calculate_max_desync(animstate) or 58

                    debug_panel_info.resolver_active = true
                    debug_panel_info.resolver_target = entity.get_player_name(closest_player) or '?'
                    debug_panel_info.resolver_eye_yaw = eye_yaw
                    debug_panel_info.resolver_feet_yaw = feet_yaw
                    debug_panel_info.resolver_side = data.resolved_side
                    debug_panel_info.resolver_desync = data.resolved_desync
                    debug_panel_info.resolver_max_desync = max_desync
                else
                    debug_panel_info.resolver_active = false
                end
            end

            -- esp flag
            client.register_esp_flag('', 255, 255, 255, function(player)
                if not ref.enabled:get() then
                    return
                end

                if ref.mode:get() == 'desync resolver' then
                    -- desync resolver ESP: show AA type
                    if dr_anti_aim_data[player] ~= nil and dr_anti_aim_data[player].anti_aim_type ~= nil then
                        return true, "\affffffc8" .. string.upper(dr_anti_aim_data[player].anti_aim_type)
                    end
                    return
                end

                local data = resolver_data[player]
                if not data then return end

                local angle = math.floor(data.resolved_side * data.resolved_desync + ref.offset:get())

                if angle > 1 then
                    return true, 'R: ' .. angle
                end

                if angle < -1 then
                    return true, 'L: ' .. angle
                end

                if angle == 0 then
                    return true, 'C: 0'
                end
            end)

            -- callbacks
            local function on_net_update()
                local me = entity.get_local_player()
                if ref.mode:get() == 'desync resolver' then
                    debug_panel_info.resolver_mode = 'desync resolver'
                    dr_track_player_data(me)
                    dr_analyze_and_apply(me)
                else
                    debug_panel_info.resolver_mode = 'kittysolver'
                    update_lag_records()
                    apply_resolver()
                end
            end

            local function on_round_start()
                for i = 1, 64 do
                    lag_records[i] = { }
                    resolver_data[i] = {
                        resolved_side = 0,
                        resolved_desync = 0,
                        last_side = 0,
                    }
                end
                dr_player_data = { cur = {}, prev = {}, pre_prev = {}, pre_pre_prev = {} }
                dr_anti_aim_data = {}
            end

            local function on_shutdown()
                for i = 1, 64 do
                    plist.set(i, "Force body yaw", false)
                end
                debug_panel_info.resolver_active = false
                dr_player_data = { cur = {}, prev = {}, pre_prev = {}, pre_pre_prev = {} }
                dr_anti_aim_data = {}
            end

            local function update_event_callbacks(value)
                utils.event_callback('net_update_end', on_net_update, value)
                utils.event_callback('round_start', on_round_start, value)
                utils.event_callback('shutdown', on_shutdown, value)
            end

            local function on_enabled(item)
                local value = item:get()
                update_event_callbacks(value)

                if not value then
                    on_shutdown()
                end
            end

            ref.enabled:set_callback(
                on_enabled, true
            )

            -- debug panel fallback (when kittysolver is off, we can still show resolver data from gamesense built-in resolver)
            debug_panel_info.get_gs_resolver = function()
                local me = entity.get_local_player()
                if not me or not entity.is_alive(me) then return nil end

                local my_origin = vector(entity.get_prop(me, 'm_vecOrigin'))
                local enemies = entity.get_players(true)
                local closest_dist = math.huge
                local closest_player = nil

                for _, player in ipairs(enemies) do
                    if entity.is_alive(player) and not entity.is_dormant(player) then
                        local enemy_origin = vector(entity.get_prop(player, 'm_vecOrigin'))
                        local dist = (enemy_origin - my_origin):length2dsqr()
                        if dist < closest_dist then
                            closest_dist = dist
                            closest_player = player
                        end
                    end
                end

                if not closest_player then return nil end

                local animstate = ks_get_anim_state(closest_player)
                if not animstate then return nil end

                local eye_yaw = select(2, entity.get_prop(closest_player, 'm_angEyeAngles')) or 0
                local feet_yaw = animstate.flFootYaw or 0
                local max_desync = calculate_max_desync(animstate)
                local desync = math.abs(ks_angle_diff(eye_yaw, feet_yaw))
                local side = desync > 5 and ((ks_angle_diff(eye_yaw, feet_yaw) > 0) and 1 or -1) or 0

                -- gs body yaw override
                local gs_force = plist.get(closest_player, 'Force body yaw')
                local gs_value = plist.get(closest_player, 'Force body yaw value') or 0

                return {
                    target = entity.get_player_name(closest_player) or '?',
                    eye_yaw = eye_yaw,
                    feet_yaw = feet_yaw,
                    side = side,
                    desync = desync,
                    max_desync = max_desync,
                    gs_override = gs_force,
                    gs_value = gs_value,
                }
            end
        end

        local recharge_fix do
            local ref = ref.ragebot.recharge_fix

            local ref_enabled_checkbox, ref_enabled_hotkey =
                ui.reference('Rage', 'Aimbot', 'Enabled')

            local ref_double_tap = {
                ui.reference('Rage', 'Aimbot', 'Double tap')
            }

            local single_fire = {
                [9]  = true, -- AWP
                [27] = true, -- MAG-7
                [29] = true, -- Sawed-Off
                [35] = true, -- Nova
                [40] = true, -- SSG 08
            }

            local function is_double_tap_active()
                return ui.get(ref_double_tap[1])
                    and ui.get(ref_double_tap[2])
            end

            local function on_shutdown()
                ragebot.unset(ref_enabled_hotkey)
            end

            local function is_dt_shifting()
                local me = entity.get_local_player()
                if not me then return false end

                local tickbase = entity.get_prop(me, 'm_nTickBase')
                local tickcount = globals.tickcount()

                return tickbase > tickcount
            end

            local function on_setup_command()
                local me = entity.get_local_player()
                if me == nil then
                    ragebot.unset(ref_enabled_hotkey)
                    return
                end

                local enabled = is_double_tap_active()
                    and not software.is_duck_peek_active()

                local active_weapon = entity.get_player_weapon(me)
                if active_weapon == nil then
                    ragebot.unset(ref_enabled_hotkey)
                    return
                end

                local weapon_idx = entity.get_prop(active_weapon, 'm_iItemDefinitionIndex')
                if weapon_idx == nil or weapon_idx == 64 then
                    ragebot.unset(ref_enabled_hotkey)
                    return
                end

                local lastshot = entity.get_prop(active_weapon, 'm_fLastShotTime')
                if lastshot == nil then
                    ragebot.unset(ref_enabled_hotkey)
                    return
                end

                local window = single_fire[weapon_idx] and 1.50 or 0.50
                local in_attack = globals.curtime() - lastshot <= window

                ragebot.set(ref_enabled_hotkey, 'Always on')
                if enabled and is_dt_shifting() then
                    ragebot.set(ref_enabled_hotkey, in_attack and 'Always on' or 'On hotkey')
                end
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        ragebot.unset(ref_enabled_hotkey)
                    end

                    utils.event_callback('shutdown', on_shutdown, value)
                    utils.event_callback('run_command', on_setup_command, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local recharge_fix_experimental do
            local ref = ref.ragebot.recharge_fix_experimental

            local patch_size = 0x1D
            local ptr = ffi.cast('char*', 0x433AC04B)

            local ogbytes = ffi.new('char[?]', patch_size)
            ffi.copy(ogbytes, ptr, patch_size)

            local patched = ffi.new('char[?]', patch_size)
            ffi.copy(patched, ogbytes, patch_size)
            ffi.fill(patched, 0x18, 0x90)
            patched[0x18] = 0xE9

            local is_patched = false

            local function apply_patch()
                if not is_patched then
                    ffi.copy(ptr, patched, patch_size)
                    is_patched = true
                end
            end

            local function restore_patch()
                if is_patched then
                    ffi.copy(ptr, ogbytes, patch_size)
                    is_patched = false
                end
            end

            local function on_shutdown()
                restore_patch()
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if value then
                        apply_patch()
                    else
                        restore_patch()
                    end

                    utils.event_callback('shutdown', on_shutdown, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local auto_hide_shots do
            local ref = ref.ragebot.auto_hide_shots

            local ref_duck_peek_assist = ui.reference(
                'Rage', 'Other', 'Duck peek assist'
            )

            local ref_quick_peek_assist = {
                ui.reference('Rage', 'Other', 'Quick peek assist')
            }

            local ref_double_tap = {
                ui.reference('Rage', 'Aimbot', 'Double tap')
            }

            local ref_on_shot_antiaim = {
                ui.reference('AA', 'Other', 'On shot anti-aim')
            }

            local function get_state()
                if not localplayer.is_onground then
                    if localplayer.is_crouched then
                        return 'Air-Crouch'
                    end

                    return 'Air'
                end

                if localplayer.is_crouched then
                    if localplayer.is_moving then
                        return 'Move-Crouch'
                    end

                    return 'Crouch'
                end

                if localplayer.is_moving then
                    if software.is_slow_motion() then
                        return 'Slow Walk'
                    end

                    return 'Moving'
                end

                return 'Standing'
            end

            local function get_weapon_type(weapon)
                local weapon_info = csgo_weapons(weapon)

                if weapon_info == nil then
                    return nil
                end

                local weapon_type = weapon_info.type
                local weapon_index = weapon_info.idx

                if weapon_type == 'smg' then
                    return 'SMG'
                end

                if weapon_type == 'rifle' then
                    return 'Rifles'
                end

                if weapon_type == 'pistol' then
                    if weapon_index == 1 then
                        return 'Desert Eagle'
                    end

                    if weapon_index == 64 then
                        return 'Revolver R8'
                    end

                    return 'Pistols'
                end

                if weapon_type == 'sniperrifle' then
                    if weapon_index == 40 then
                        return 'Scout'
                    end

                    if weapon_index == 9 then
                        return 'AWP'
                    end

                    return 'Auto Snipers'
                end

                return nil
            end

            local function restore_values()
                ragebot.unset(ref_double_tap[1])

                override.unset(ref_on_shot_antiaim[1])
                override.unset(ref_on_shot_antiaim[2])
            end

            local function update_values()
                ragebot.set(ref_double_tap[1], false)

                override.set(ref_on_shot_antiaim[1], true)
                override.set(ref_on_shot_antiaim[2], 'Always on')
            end

            local function should_update()
                if ui.get(ref_duck_peek_assist) then
                    return false
                end

                local is_quick_peek_assist = (
                    ui.get(ref_quick_peek_assist[1]) and
                    ui.get(ref_quick_peek_assist[2])
                )

                if is_quick_peek_assist then
                    return false
                end

                if not ui.get(ref_double_tap[2]) then
                    return false
                end

                local me = entity.get_local_player()

                if me == nil then
                    return false
                end

                local weapon = entity.get_player_weapon(me)

                if weapon == nil then
                    return false
                end

                local weapon_type = get_weapon_type(weapon)

                if weapon_type == nil or not ref.weapons:get(weapon_type) then
                    return false
                end

                local state = get_state()

                if not ref.states:get(state) then
                    return false
                end

                return true
            end

            local function on_shutdown()
                restore_values()
            end

            local function on_setup_command()
                if should_update() then
                    update_values()
                else
                    restore_values()
                end
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        restore_values()
                    end

                    utils.event_callback(
                        'shutdown',
                        on_shutdown,
                        value
                    )

                    utils.event_callback(
                        'setup_command',
                        on_setup_command,
                        value
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local jump_scout do
            local ref = ref.ragebot.jump_scout

            local function should_update()
                local me = entity.get_local_player()

                if me == nil then
                    return false
                end

                local weapon = entity.get_player_weapon(me)

                if weapon == nil then
                    return false
                end

                local weapon_info = csgo_weapons(weapon)

                if weapon_info == nil then
                    return nil
                end

                if weapon_info.idx ~= 40 then -- scout
                    return false
                end

                if localplayer.velocity2d_sqr > (10 * 10) then
                    return false
                end

                return true
            end

            local function restore_values()
                override.unset(software.misc.movement.air_strafe)
            end

            local function on_shutdown()
                restore_values()
            end

            local function on_paint_ui()
                restore_values()
            end

            local function on_setup_command(cmd)
                if should_update() then
                    override.set(software.misc.movement.air_strafe, false)
                else
                    override.unset(software.misc.movement.air_strafe)
                end
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        restore_values()
                    end

                    utils.event_callback('shutdown', on_shutdown, value)
                    utils.event_callback('paint_ui', on_paint_ui, value)
                    utils.event_callback('setup_command', on_setup_command, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local dt_boost do
            local ref_clock = ref.debug.clock_correction
            local ref = ref.ragebot.dt_boost

            local ref_doubletap = {
                ui.reference('Rage', 'Aimbot', 'Double tap')
            }

            local ref_usrcmdprocessticks = ui.reference('Misc', 'Settings', 'sv_maxusrcmdprocessticks2')

            local primary_weapons = {
                [9]  = true, -- AWP
                [25] = true, -- XM1014
                [27] = true, -- MAG-7
                [29] = true, -- Sawed-Off
                [35] = true, -- Nova
                [40] = true, -- SSG 08
                [64] = true, -- Revolver R8
            }

            local is_modified = false

            local function is_double_tap()
                return ui.get(ref_doubletap[1])
                    and ui.get(ref_doubletap[2])
                    and not software.is_duck_peek_active()
            end

            local function restore()
                if is_modified then
                    is_modified = false
                    ui.set(ref_usrcmdprocessticks, 16)
                end
            end

            local function on_shutdown()
                restore()
            end

            local function on_setup_command()
                local mode = ref.enabled:get()

                if mode == 'Off' then
                    restore()
                    return
                end

                if not is_double_tap() then
                    restore()
                    return
                end

                local me = entity.get_local_player()
                if me == nil then
                    restore()
                    return
                end

                local extra = mode == 'Boost' and 1 or mode == 'Fast' and 2 or 3

                -- adaptive latency tiers override tick amount
                if ref_clock.adaptive:get() and ref_clock.enabled:get() then
                    local latency = math.min(1000, client.latency() * 1000)

                    if latency >= 75 then
                        extra = 0
                    elseif latency >= 45 then
                        extra = 1
                    elseif latency >= 25 then
                        extra = 2
                    elseif latency >= 5 then
                        extra = 3
                    else
                        extra = 4
                    end
                end

                local weapon = entity.get_player_weapon(me)
                if weapon ~= nil then
                    local weapon_idx = entity.get_prop(weapon, 'm_iItemDefinitionIndex')
                    if weapon_idx ~= nil and primary_weapons[weapon_idx] then
                        extra = 0
                    end
                end

                is_modified = true
                ui.set(ref_usrcmdprocessticks, 16 + extra)
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get() ~= 'Off'

                    if not value then
                        restore()
                    end

                    utils.event_callback('shutdown', on_shutdown, value)
                    utils.event_callback('setup_command', on_setup_command, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local clock_correction do
            local ref = ref.debug.clock_correction

            local ref_doubletap = {
                ui.reference('Rage', 'Aimbot', 'Double tap')
            }

            local ref_clockcorrection_msecs = ui.reference('Misc', 'Settings', 'sv_clockcorrection_msecs2')

            local is_modified = false
            local last_logged_msecs = nil

            local primary_weapons = {
                [9]  = true, -- AWP
                [25] = true, -- XM1014
                [27] = true, -- MAG-7
                [29] = true, -- Sawed-Off
                [35] = true, -- Nova
                [40] = true, -- SSG 08
                [64] = true, -- Revolver R8
            }

            local function is_double_tap()
                return ui.get(ref_doubletap[1])
                    and ui.get(ref_doubletap[2])
            end

            local function restore_cvar()
                if is_modified then
                    is_modified = false
                    last_logged_msecs = nil
                    ui.set(ref_clockcorrection_msecs, 30)
                    logging_system.default('clock correction restored to 30ms')
                end
            end

            local function on_shutdown()
                restore_cvar()
            end

            local function on_setup_command()
                if not is_double_tap() then
                    restore_cvar()
                    return
                end

                local me = entity.get_local_player()
                if me == nil then
                    restore_cvar()
                    return
                end

                local msecs

                if ref.adaptive:get() then
                    local latency = math.min(1000, client.latency() * 1000)

                    if latency >= 75 then
                        msecs = 65
                    elseif latency >= 45 then
                        msecs = 55
                    elseif latency >= 25 then
                        msecs = 45
                    elseif latency >= 5 then
                        msecs = 30
                    else
                        msecs = 25
                    end

                    local weapon = entity.get_player_weapon(me)
                    if weapon ~= nil then
                        local weapon_idx = entity.get_prop(weapon, 'm_iItemDefinitionIndex')
                        if weapon_idx ~= nil and primary_weapons[weapon_idx] then
                            msecs = 30
                        end
                    end
                else
                    msecs = ref.override:get()
                end

                is_modified = true
                ui.set(ref_clockcorrection_msecs, msecs)

                local actual = ui.get(ref_clockcorrection_msecs)
                if actual ~= last_logged_msecs then
                    last_logged_msecs = actual
                    logging_system.default(string.format(
                        'clock correction set to %dms (requested: %d, actual: %d)', msecs, msecs, actual
                    ))
                end
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        restore_cvar()
                    end

                    utils.event_callback('shutdown', on_shutdown, value)
                    utils.event_callback('setup_command', on_setup_command, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local anti_defensive do
            local ref = ref.debug.anti_defensive

            local ref_doubletap = {
                ui.reference('Rage', 'Aimbot', 'Double tap')
            }

            -- FFI convar structs for direct memory access
            if not pcall(ffi.sizeof, 'ConvarInfo') then
                ffi.cdef[[
                    typedef struct {
                        char pad[0x14];
                        int flags;
                        char pad1[0x2c];
                    } ConvarFlag;

                    typedef struct {
                        void** virtual_function_table;
                        unsigned char pad[20];
                        void* changeCallback;
                        void* parent;
                        const char* defaultValue;
                        char* string;
                        int m_StringLength;
                        float m_fValue;
                        int m_nValue;
                        int m_bHasMin;
                        float m_fMinVal;
                        int m_bHasMax;
                        float m_fMaxVal;
                        void* onChangeCallbacks_memory;
                        int onChangeCallbacks_allocationCount;
                        int onChangeCallbacks_growSize;
                        int onChangeCallbacks_size;
                        void* onChangeCallbacks_elements;
                    } ConvarInfo;
                ]]
            end

            local native_get_cvar = vtable_bind('vstdlib.dll', 'VEngineCvar007', 16, 'ConvarInfo*(__thiscall*)(void*, const char*)')

            -- resolve SetInt from vtable using 'rate' as base.
            local base_rate = native_get_cvar('rate')
            local set_int_fn = ffi.cast('void(__thiscall*)(ConvarInfo*, float)', base_rate.virtual_function_table[16])

            -- cl_lagcompensation cvar pointers
            local lc_ptr = native_get_cvar('cl_lagcompensation')
            local lc_flags = ffi.cast('ConvarFlag*', lc_ptr)
            local lc_original_flags = lc_flags.flags
            local lc_original_value = tonumber(ffi.string(lc_ptr.defaultValue))
            local lc_fallback = cvar.cl_lagcompensation

            local is_modified = false
            local is_active = false

            local primary_weapons = {
                [9]  = true, -- AWP
                [25] = true, -- XM1014
                [27] = true, -- MAG-7
                [29] = true, -- Sawed-Off
                [35] = true, -- Nova
                [40] = true, -- SSG 08
                [64] = true, -- Revolver R8
            }

            local function is_double_tap()
                return ui.get(ref_doubletap[1])
                    and ui.get(ref_doubletap[2])
                    and not software.is_duck_peek_active()
            end

            local function lc_set(value)
                is_modified = true
                is_active = true
                lc_flags.flags = 0
                lc_fallback:set_int(value)
                pcall(set_int_fn, lc_ptr, value)
            end

            local function lc_reset()
                is_active = false
                if is_modified then
                    is_modified = false
                    lc_flags.flags = lc_original_flags
                    lc_fallback:set_int(lc_original_value)
                    pcall(set_int_fn, lc_ptr, lc_original_value)
                end
            end

            local function on_shutdown()
                lc_reset()
            end

            local function on_setup_command()
                local me = entity.get_local_player()
                if me == nil then
                    lc_reset()
                    return
                end

                if not entity.is_alive(me) then
                    lc_reset()
                    return
                end

                local active = ref.hotkey:get()

                if not active then
                    lc_reset()
                    return
                end

                -- primary weapons always reset lag compensation
                local weapon = entity.get_player_weapon(me)
                if weapon ~= nil then
                    local weapon_idx = entity.get_prop(weapon, 'm_iItemDefinitionIndex')
                    if weapon_idx ~= nil and primary_weapons[weapon_idx] then
                        lc_reset()
                        return
                    end
                end

                lc_set(0)
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        lc_reset()
                    end

                    utils.event_callback('shutdown', on_shutdown, value)
                    utils.event_callback('setup_command', on_setup_command, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end

            function exploit.is_anti_defensive_active()
                return is_active
            end
        end

        local aimbot_logs do
            local ref = ref.ragebot.aimbot_logs

            local ref_draw_console_output = ui.reference(
                'Misc', 'Miscellaneous', 'Draw console output'
            )

            local ref_log_misses_due_to_spread = ui.reference(
                'Rage', 'Other', 'Log misses due to spread'
            )

            local PADDING_W = 8
            local PADDING_H = 6

            local GAP_BETWEEN = 4

            local e_hitgroup = {
                [0]  = 'generic',
                [1]  = 'head',
                [2]  = 'chest',
                [3]  = 'stomach',
                [4]  = 'left arm',
                [5]  = 'right arm',
                [6]  = 'left leg',
                [7]  = 'right leg',
                [8]  = 'neck',
                [10] = 'gear'
            }

            local hurt_weapons = {
                ['c4'] = 'bombed',
                ['knife'] = 'knifed',
                ['decoy'] = 'decoyed',
                ['inferno'] = 'burned',
                ['molotov'] = 'harmed',
                ['flashbang'] = 'harmed',
                ['hegrenade'] = 'naded',
                ['incgrenade'] = 'harmed',
                ['smokegrenade'] = 'harmed'
            }

            local log_glow = 0
            local log_offset = 0
            local log_duration = 5
            local log_transparency = 1.0

            local shotcounter = 0

            local fire_data = { }

            local draw_queue = { }
            local notify_queue = { }

            local function remove_hex(str)
                local result = string.gsub(
                    str, '\a%x%x%x%x%x%x%x%x', ''
                )

                return result
            end

            local function clear_draw_queue()
                for i = 1, #draw_queue do
                    draw_queue[i] = nil
                end
            end

            local function clear_notify_queue()
                for i = 1, #notify_queue do
                    notify_queue[i] = nil
                end
            end

            local function add_log(r, g, b, a, text)
                if not ref.select:get 'Screen' then
                    return
                end

                local time = log_duration

                local id = #draw_queue + 1
                local color = { r, g, b, a }

                text = remove_hex(text)

                draw_queue[id] = {
                    text = text,
                    color = color,

                    time = time,
                    alpha = 0.0
                }

                return id
            end

            local function notify_log(r, g, b, a, text)
                if not ref.select:get 'Notify' then
                    return
                end

                local list, count = text_fmt.color(text)

                for i = 1, count do
                    local value = list[i]

                    local hex = value[2]

                    if hex == nil then
                        hex = utils.to_hex(r, g, b, a)
                    end

                    value[2] = color(utils.from_hex(hex))
                end

                table.insert(notify_queue, {
                    time = 7.0,
                    alpha = 1.0,

                    list = list,
                    count = count
                })

                if #notify_queue > 7 then
                    table.remove(notify_queue, 1)
                end

                ui.set(ref_draw_console_output, false)
                ui.set(ref_log_misses_due_to_spread, false)
            end

            local function console_log(r, g, b, text)
                if not ref.select:get 'Console' then
                    return
                end

                local list, count = text_fmt.color(text)

                for i = 1, count do
                    local value = list[i]

                    local str = value[1]
                    local hex = value[2]

                    if i ~= count then
                        str = str .. '\0'
                    end

                    if hex == nil then
                        client.color_log(
                            r, g, b, str
                        )

                        goto continue
                    end

                    local hex_r, hex_g, hex_b = utils.from_hex(hex)

                    client.color_log(
                        hex_r, hex_g, hex_b, str
                    )

                    ::continue::
                end
            end

            local function format_text(text, hex_a, hex_b)
                local result = string.gsub(text, '${(.-)}', string.format(
                    '\a%s%%1\a%s', hex_a, hex_b
                ))

                if result:sub(1, 1) ~= '\a' then
                    result = '\a' .. hex_b .. result
                end

                return result
            end

            local function get_logo_text(logo_type)
                return "catboy"
            end

            local function update_text_alpha(text, alpha)
                local result = text:gsub("\a(%x%x%x%x%x%x)(%x%x)", function(rgb, a)
                    local new_a = math.floor(math.min(255, tonumber(a, 16) * alpha))
                    return "\a" .. rgb .. string.format("%02x", new_a)
                end)

                return result
            end


            local function draw_box(x, y, w, h, r1, g1, b1, a1, r2, g2, b2, a2, alpha)
                local rad = math.floor(h / 2)

                -- shadow
                render.rectangle(x + 2, y + 2, w, h, 0, 0, 0, math.floor(30 * alpha), rad)
                render.rectangle(x + 1, y + 1, w, h, 0, 0, 0, math.floor(45 * alpha), rad)

                -- glow
                if log_glow > 0 then
                    local glow_str = math.min(log_glow / 2.5, 1.0)
                    local ga = a2 * 0.5 * glow_str * alpha
                    local steps = math.max(2, math.min(6, round(2 + 4 * glow_str)))
                    render.glow(x, y, w, h, r2, g2, b2, ga, rad, steps)
                end

                -- bg
                render.rectangle(x, y, w, h, r1, g1, b1, math.floor(a1 * 0.45 * alpha), rad)

                -- left accent
                renderer.gradient(x + 1, y + rad, 2, h - rad * 2, r2, g2, b2, math.floor(a2 * 0.9 * alpha), r2, g2, b2, math.floor(a2 * 0.2 * alpha), false)

                -- top shimmer
                renderer.gradient(x + rad, y + 1, math.floor((w - rad * 2) * 0.5), 1, r2, g2, b2, math.floor(a2 * 0.4 * alpha), r2, g2, b2, 0, true)

                -- border
                render.rectangle_outline(x, y, w, h, 50, 50, 60, math.floor(40 * alpha), 1, rad)
            end

            local function paint_notify()
                if not boot.done then return end
                local dt = globals.frametime()
                local position = vector(8, 5)

                for i = #notify_queue, 1, -1 do
                    local data = notify_queue[i]

                    data.time = data.time - dt

                    if data.time <= 0.0 then
                        data.alpha = motion.interp(
                            data.alpha, 0.0, 0.075
                        )

                        if data.alpha <= 0.0 then
                            table.remove(notify_queue, i)
                        end
                    end
                end

                for i = 1, #notify_queue do
                    local data = notify_queue[i]

                    local list = data.list
                    local count = data.count
                    local alpha = data.alpha

                    local text_pos = position:clone()

                    for j = 1, count do
                        local value = list[j]

                        local text = value[1]
                        local col = value[2]

                        local text_size = vector(renderer.measure_text(flags, text))

                        renderer.text(text_pos.x, text_pos.y, col.r, col.g, col.b, col.a * alpha, '', nil, text:lower())

                        text_pos.x = text_pos.x + text_size.x
                    end

                    position.y = position.y + 14 * alpha
                end
            end

            local function paint_screen()
                if not boot.done then return end

                local dt = globals.frametime()
                local base_dt = 1 / 60
                local len = #draw_queue

                local screen_w, screen_h = client.screen_size()

                local base_y = math.floor(screen_h / 2) + log_offset

                local icon_text = 'catboy'
                local icon_flags = 'b'
                local sep_text = '  ·  '

                local icon_size_x, icon_size_y = renderer.measure_text(icon_flags, icon_text)
                local sep_size_x = renderer.measure_text('', sep_text)

                local PAD_X = 14
                local PAD_Y = 8
                local ENTRY_GAP = 10

                for i = len, 1, -1 do
                    local data = draw_queue[i]

                    local is_life = data.time > 0 and (len - i) < 6

                    data.alpha = motion.interp(
                        data.alpha, is_life, 0.075
                    )

                    -- slide-in
                    if data.slide == nil then data.slide = 30 end
                    local slide_target = is_life and 0 or 20
                    data.slide = data.slide + (slide_target - data.slide) * (1 - math.pow(1 - 0.12, dt / base_dt))

                    if is_life then
                        data.time = data.time - dt
                    else
                        if data.alpha <= 0.0 then
                            table.remove(draw_queue, i)
                        end
                    end
                end

                local flags = ''
                local position_y = base_y

                for i = 1, #draw_queue do
                    local data = draw_queue[i]

                    local r, g, b, a = unpack(data.color)
                    local text, alpha = data.text, data.alpha * log_transparency

                    if alpha < 0.01 then goto continue end

                    local text_w, text_h = renderer.measure_text(flags, text)
                    local total_text_w = icon_size_x + sep_size_x + text_w
                    local box_w = PAD_X + total_text_w + PAD_X
                    local box_h = PAD_Y + math.max(text_h, icon_size_y) + PAD_Y

                    local box_x = math.floor(screen_w / 2 - box_w / 2) + math.floor(data.slide)
                    local box_y = math.floor(position_y)

                    -- box
                    draw_box(box_x, box_y, box_w, box_h, 14, 14, 18, 235, r, g, b, a, alpha)

                    -- icon
                    local ix = box_x + PAD_X
                    local iy = box_y + math.floor((box_h - icon_size_y) / 2)
                    local now_t = globals.realtime()
                    local ox = 0
                    for ci = 1, #icon_text do
                        local ch = icon_text:sub(ci, ci)
                        local t = (math.sin((now_t * 3.0) + (ci * 0.7)) + 1) * 0.5
                        local cr = math.floor(r + (255 - r) * t * 0.6)
                        local cg = math.floor(g + (255 - g) * t * 0.6)
                        local cb = math.floor(b + (255 - b) * t * 0.6)
                        -- shadow
                        renderer.text(ix + ox + 1, iy + 1, 0, 0, 0, math.floor(90 * alpha), icon_flags, nil, ch)
                        -- glow behind char
                        renderer.text(ix + ox, iy, cr, cg, cb, math.floor(a * alpha * 0.3), icon_flags, nil, ch)
                        renderer.text(ix + ox, iy, cr, cg, cb, math.floor(a * alpha), icon_flags, nil, ch)
                        ox = ox + renderer.measure_text(icon_flags, ch)
                    end

                    -- separator
                    local sx = ix + icon_size_x
                    renderer.text(sx + 1, iy + 2, 0, 0, 0, math.floor(50 * alpha), '', nil, sep_text)
                    renderer.text(sx, iy + 1, r, g, b, math.floor(80 * alpha), '', nil, sep_text)

                    -- text
                    local tx = sx + sep_size_x
                    local ty = box_y + math.floor((box_h - text_h) / 2)

                    text = update_text_alpha(text, alpha)

                    renderer.text(tx + 1, ty + 1, 0, 0, 0, math.floor(60 * alpha), flags, nil, text)
                    renderer.text(tx, ty, 255, 255, 255, math.floor(210 * alpha), flags, nil, text)

                    position_y = position_y - round((box_h + ENTRY_GAP) * alpha)

                    ::continue::
                end
            end

            local function on_aim_hit(e)
                local data = fire_data[e.id]

                if data == nil then
                    return
                end

                local target = e.target

                if target == nil then
                    return
                end

                local r, g, b, a = ref.color_hit:get()

                local player_name = entity.get_player_name(target)
                local player_health = entity.get_prop(target, 'm_iHealth')

                local hit_chance = e.hit_chance or 0
                local aim_history = data.history or 0

                local damage = e.damage or 0
                local aim_damage = data.aim.damage or 0

                local hitgroup = e_hitgroup[e.hitgroup] or '?'
                local aim_hitgroup = e_hitgroup[data.aim.hitgroup] or '?'

                local damage_mismatch = (aim_damage - damage) > 0
                local hitgroup_mismatch = aim_hitgroup ~= hitgroup

                local body_yaw = data.body_yaw or 0

                local aim_history_ms = math.floor(aim_history * globals.tickinterval() * 1000 + 0.5)

                local details = { } do
                    table.insert(details, string.format('hc: ${%d%%}', hit_chance))
                    table.insert(details, string.format('bt: ${%dt} (${%dms})', aim_history, aim_history_ms))
                end



                local screen_text do
                    if player_health == 0 then
                        screen_text = string.format(
                            'hit ${%s} in ${%s} for ${%s} damage',
                            player_name, hitgroup, damage
                        )
                    else
                        screen_text = string.format(
                            'hit ${%s} in ${%s} for ${%s} damage',
                            player_name, hitgroup, damage
                        )
                    end
                end

                local console_text do
                    local damage_text = string.format('${%d}', damage)
                    local hitgroup_text = string.format('${%s}', hitgroup)

                    if damage_mismatch then
                        damage_text = string.format(
                            '%s(${%d})', damage_text, aim_damage
                        )
                    end

                    if hitgroup_mismatch then
                        hitgroup_text = string.format(
                            '%s(${%s})', hitgroup_text, aim_hitgroup
                        )
                    end

                    local details = { } do
                        table.insert(details, string.format('hc: ${%d%%}', hit_chance))
                        table.insert(details, string.format('bt: ${%dt} (${%dms})', aim_history, aim_history_ms))
                        table.insert(details, string.format('by: ${%d°}', body_yaw))
                    end

                    if player_health == 0 then
                        console_text = string.format(
                            '${✦ (>.<) catboy} inflicted ${lethal %sth shot} at ${%s} in ${%s} for ${%s} damage [${killed}] (%s)',
                            shotcounter, player_name, hitgroup, damage, table.concat(details, ' ∙ ')
                        )
                    else
                        console_text = string.format(
                            '${✦ (>.<) catboy} registred ${%sth} ${shot} at ${%s} in ${%s} for ${%s} damage (${%d} health remaining ∙ %s)',
                            shotcounter, player_name, hitgroup, damage, player_health, table.concat(details, ' ∙ ')
                        )
                    end
                end

                screen_text = format_text(
                    screen_text, utils.to_hex(r, g, b, a), 'c8c8c8ff'
                )

                console_text = format_text(
                    console_text, utils.to_hex(r, g, b, a), 'c8c8c8ff'
                )

                add_log(r, g, b, a, screen_text)
                notify_log(255, 255, 255, 255, console_text)
                console_log(255, 255, 255, console_text)
            end

            local function on_aim_miss(e)
                local data = fire_data[e.id]

                if data == nil then
                    return
                end

                local target = e.target

                if target == nil then
                    return
                end

                local r, g, b, a = ref.color_miss:get()

                local player_name = entity.get_player_name(target)

                local miss_reason = e.reason or '?'
                local hit_chance = e.hit_chance or 0

                local aim_damage = data.aim.damage or 0
                local aim_history = data.history or 0

                local aim_hitgroup = e_hitgroup[data.aim.hitgroup] or '?'
                local body_yaw = data.body_yaw or 0

                local aim_history_ms = math.floor(aim_history * globals.tickinterval() * 1000 + 0.5)

                local details = { } do
                    table.insert(details, string.format('hc: ${%d%%}', hit_chance))
                    table.insert(details, string.format('bt: ${%dt} (${%dms})', aim_history, aim_history_ms))
                end

                local screen_text do
                    screen_text = string.format(
                        'missed ${%s} in ${%s} due to ${%s}',
                        player_name, aim_hitgroup, miss_reason
                    )
                end

                local console_text do
                    local details = { } do
                        table.insert(details, string.format('hc: ${%d%%}', hit_chance))
                        table.insert(details, string.format('history: ${%dt} (${%dms})', aim_history, aim_history_ms))
                        table.insert(details, string.format('by: ${%d°}', body_yaw))
                    end

                    console_text = string.format(
                        '${✦ (>.<) catboy} missed ${%s} in ${%s} due to ${%s} (%s)',
                        player_name, aim_hitgroup, miss_reason, table.concat(details, ' ∙ ')
                    )
                end

                screen_text = format_text(
                    screen_text, utils.to_hex(r, g, b, a), 'c8c8c8ff'
                )

                console_text = format_text(
                    console_text, utils.to_hex(r, g, b, a), 'c8c8c8ff'
                )

                add_log(r, g, b, a, screen_text)
                notify_log(255, 255, 255, 255, console_text)
                console_log(255, 255, 255, console_text)
            end

            local function on_aim_fire(e)
                local safe = plist.get(e.target, 'Override safe point')
                local history = globals.tickcount() - e.tick
                local body_yaw = plist.get(e.target, 'Force body yaw value')

                fire_data[e.id] = {
                    aim = e,

                    safe = safe == 'On',
                    history = history,
                    body_yaw = body_yaw
                }

                shotcounter = shotcounter + 1
            end

            local function on_player_hurt(e)
                local me = entity.get_local_player()

                local userid = client.userid_to_entindex(e.userid)
                local attacker = client.userid_to_entindex(e.attacker)

                if attacker ~= me or userid == me then
                    return
                end

                local weapon = e.weapon
                local action = hurt_weapons[weapon]

                if action == nil then
                    return
                end

                local r, g, b, a = ref.color_hit:get()

                local player_name = entity.get_player_name(userid)
                local player_health = entity.get_prop(userid, 'm_iHealth')

                local damage = e.dmg_health

                local screen_text do
                    screen_text = string.format(
                        '%s ${%s} for ${%d} dmg',
                        action, player_name, damage
                    )
                end

                local console_text do
                    console_text = string.format(
                        '${✦ (>.<) catboy} %s ${%s} for ${%d} dmg',
                        action, player_name, damage
                    )
                end

                screen_text = format_text(
                    screen_text, utils.to_hex(r, g, b, a), 'c8c8c8ff'
                )

                console_text = format_text(
                    console_text, utils.to_hex(r, g, b, a), 'c8c8c8ff'
                )

                add_log(r, g, b, a, screen_text)
                notify_log(255, 255, 255, 255, console_text)
                console_log(255, 255, 255, console_text)
            end

            local callbacks do
                local function on_glow(item)
                    log_glow = item:get() * 0.02
                end

                local function on_offset(item)
                    log_offset = item:get() * 2
                end

                local function on_duration(item)
                    log_duration = item:get() * 0.1
                end

                local function on_transparency(item)
                    log_transparency = item:get() / 100
                end

                local function on_select(item)
                    local is_notify = item:get 'Notify'
                    local is_screen = item:get 'Screen'

                    if is_screen then
                        ref.glow:set_callback(on_glow, true)
                        ref.offset:set_callback(on_offset, true)
                        ref.duration:set_callback(on_duration, true)
                        ref.transparency:set_callback(on_transparency, true)
                    else
                        ref.glow:unset_callback(on_glow)
                        ref.offset:unset_callback(on_offset)
                        ref.duration:unset_callback(on_duration)
                        ref.transparency:unset_callback(on_transparency)
                    end

                    if not is_notify then
                        clear_notify_queue()
                    end

                    if not is_screen then
                        clear_draw_queue()
                    end

                    utils.event_callback('paint', paint_notify, is_notify)
                    utils.event_callback('paint', paint_screen, is_screen)
                end

                local function on_enabled(item)
                    local value = item:get()

                    if value then
                        ref.select:set_callback(on_select, true)
                    else
                        ref.select:unset_callback(on_select)
                    end

                    if not value then
                        ref.glow:unset_callback(on_glow)
                        ref.offset:unset_callback(on_offset)
                        ref.duration:unset_callback(on_duration)
                        ref.transparency:unset_callback(on_transparency)

                        utils.event_callback('paint', paint_notify, false)
                        utils.event_callback('paint', paint_screen, false)

                        clear_draw_queue()
                        clear_notify_queue()
                    end

                    utils.event_callback('aim_hit', on_aim_hit, value)
                    utils.event_callback('aim_miss', on_aim_miss, value)
                    utils.event_callback('aim_fire', on_aim_fire, value)
                    utils.event_callback('player_hurt', on_player_hurt, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end
    end

    local antiaim = { } do
        local inverts = 0
        local inverted = false

        local micromove_inverted = false

        -- MM roll spoof
        local mm_roll_spoofed = false
        local mm_game_rule_ptr = (function()
            local ok, sig = pcall(client.find_signature, 'client.dll', '\x83\x3D\xCC\xCC\xCC\xCC\xCC\x74\x2A\xA1')
            if not ok or sig == nil then return nil end
            local ptr = ffi.cast('intptr_t**', ffi.cast('intptr_t', sig) + 2)
            if ptr == nil then return nil end
            return ptr[0]
        end)()

        local delay_ptr = {
            default = 0,
            defensive = 0
        }

        local hold_yaw_state = {
            time = 0,
            delay = 0,
            side = false
        }

        local tick_yaw_state = {
            counter = 0,
            side = false
        }

        local skitter = {
            -1, 1, 0,
            -1, 1, 0,
            -1, 0, 1,
            -1, 0, 1
        }

        local buffer = { } do
            local ref = software.antiaimbot.angles

            local function override_value(item, ...)
                if ... == nil then
                    return
                end

                override.set(item, ...)
            end

            local Buffer = { } do
                Buffer.__index = Buffer

                function Buffer:clear()
                    for k in pairs(self) do
                        self[k] = nil
                    end
                end

                function Buffer:copy(target)
                    for k, v in pairs(target) do
                        self[k] = v
                    end
                end

                function Buffer:unset()
                    override.unset(ref.roll)

                    override.unset(ref.freestanding[2])
                    override.unset(ref.freestanding[1])

                    override.unset(ref.edge_yaw)

                    override.unset(ref.freestanding_body_yaw)

                    override.unset(ref.body_yaw[2])
                    override.unset(ref.body_yaw[1])

                    override.unset(ref.yaw[2])
                    override.unset(ref.yaw[1])

                    override.unset(ref.yaw_jitter[2])
                    override.unset(ref.yaw_jitter[1])

                    override.unset(ref.yaw_base)

                    override.unset(ref.pitch[2])
                    override.unset(ref.pitch[1])

                    override.unset(ref.enabled)
                end


                function Buffer:set()
                    if self.pitch_offset ~= nil then
                        self.pitch_offset = utils.clamp(
                            self.pitch_offset, -89, 89
                        )
                    end

                    if self.yaw_offset ~= nil then
                        self.yaw_offset = utils.normalize(
                            self.yaw_offset, -180, 180
                        )
                    end

                    if self.jitter_offset ~= nil then
                        self.jitter_offset = utils.normalize(
                            self.jitter_offset, -180, 180
                        )
                    end

                    if self.body_yaw_offset ~= nil then
                        self.body_yaw_offset = utils.clamp(
                            self.body_yaw_offset, -180, 180
                        )
                    end

                    override_value(ref.enabled, self.enabled)

                    override_value(ref.pitch[1], self.pitch)
                    override_value(ref.pitch[2], self.pitch_offset)

                    override_value(ref.yaw_base, self.yaw_base)

                    override_value(ref.yaw[1], self.yaw)
                    override_value(ref.yaw[2], self.yaw_offset)

                    override_value(ref.yaw_jitter[1], self.yaw_jitter)
                    override_value(ref.yaw_jitter[2], self.jitter_offset)

                    override_value(ref.body_yaw[1], self.body_yaw)
                    override_value(ref.body_yaw[2], self.body_yaw_offset)

                    override_value(ref.freestanding_body_yaw, self.freestanding_body_yaw)

                    override_value(ref.edge_yaw, self.edge_yaw)

                    if self.freestanding == true then
                        override_value(ref.freestanding[1], true)
                        override_value(ref.freestanding[2], 'Always on')
                    elseif self.freestanding == false then
                        override_value(ref.freestanding[1], false)
                        override_value(ref.freestanding[2], 'On hotkey')
                    end

                    override_value(ref.roll, self.roll)
                end
            end

            setmetatable(buffer, Buffer)
            antiaim.buffer = buffer
        end

        local defensive = { } do
            local pitch_inverted = false
            local modifier_delay_ticks = 0
            local xway_tick = 0

            local function update_pitch_inverter()
                pitch_inverted = not pitch_inverted
            end

            local function update_modifier_inverter()
                modifier_delay_ticks = modifier_delay_ticks + 1
            end

            local function update_pitch(buffer, items)
                if items.pitch == nil then
                    return
                end

                local value = items.pitch:get()
                local speed = items.pitch_speed:get()

                local pitch_offset_1 = items.pitch_offset_1:get()
                local pitch_offset_2 = items.pitch_offset_2:get()

                if value == 'Off' then
                    return
                end

                local can_be_randomized = (
                    value == 'Sway'
                )

                if can_be_randomized and items.pitch_randomize_offset:get() then
                    pitch_offset_1 = utils.random_int(-89, 89)
                    pitch_offset_2 = utils.random_int(-89, 89)
                end

                if value == 'Static' then
                    buffer.pitch = 'Custom'
                    buffer.pitch_offset = pitch_offset_1

                    return
                end

                if value == 'Jitter' then
                    local offset = pitch_inverted
                        and pitch_offset_2
                        or pitch_offset_1

                    buffer.pitch = 'Custom'
                    buffer.pitch_offset = offset

                    return
                end

                if value == 'Spin' then
                    local time = globals.curtime() * speed * 0.1

                    local offset = utils.lerp(
                        pitch_offset_1,
                        pitch_offset_2,
                        time % 1
                    )

                    buffer.pitch = 'Custom'
                    buffer.pitch_offset = offset

                    return
                end

                if value == 'Sway' then
                    local time = globals.curtime() * speed * 0.1
                    local t = math.abs(time % 2.0 - 1.0)

                    local offset = utils.lerp(
                        pitch_offset_1,
                        pitch_offset_2,
                        t
                    )

                    buffer.pitch = 'Custom'
                    buffer.pitch_offset = offset

                    return
                end

                if value == 'Static Random' then

                    local function get_static_pitch(pitch_from, pitch_to)
                        if exploit.get().defensive.left == exploit.get().defensive.max then
                            static_pitch = utils.random_int(pitch_from, pitch_to)
                        end
                        return static_pitch
                    end

                    buffer.pitch = 'Custom'

                    buffer.pitch_offset = get_static_pitch(pitch_offset_1, pitch_offset_2)

                    return
                end

                if value == 'Random' then
                    buffer.pitch = 'Custom'

                    buffer.pitch_offset = utils.random_int(
                        pitch_offset_1, pitch_offset_2
                    )

                    return
                end
            end

            local function update_yaw_modifier(buffer, items)
                if items.yaw_modifier == nil then
                    return
                end

                local value = items.yaw_modifier:get()
                local offset = items.modifier_offset:get()

                if value == 'Off' then
                    return
                end

                if value == 'Offset' then
                    buffer.yaw_offset = buffer.yaw_offset + (
                        inverted and 0 or offset
                    )

                    return
                end

                if value == 'Center' then
                    if buffer.body_yaw == 'Jitter' then
                        buffer.yaw_left = buffer.yaw_left - offset * 0.5
                        buffer.yaw_right = buffer.yaw_right + offset * 0.5
                    else
                        buffer.yaw_offset = buffer.yaw_offset + 0.5 * (
                            inverted and -offset or offset
                        )
                    end

                    return
                end

                if value == 'Skitter' then
                    local index = inverts % #skitter
                    local multiplier = skitter[index + 1]

                    buffer.yaw_offset = buffer.yaw_offset + (
                        offset * multiplier
                    )

                    return
                end
            end

            local function update_yaw(buffer, items)
                if items.yaw == nil then
                    return
                end

                local value = items.yaw:get()
                local speed = items.yaw_speed:get()

                local yaw_offset = items.yaw_offset:get()

                local yaw_left = items.yaw_left:get()
                local yaw_right = items.yaw_right:get()

                if value == 'off' then
                    return
                end

                local can_be_randomized = (
                    value == 'Sway'
                )

                if can_be_randomized and items.yaw_randomize_offset:get() then
                    yaw_left = utils.random_int(-180, 180)
                    yaw_right = utils.random_int(-180, 180)
                end

                buffer.freestanding = false

                buffer.yaw_left = 0
                buffer.yaw_right = 0

                buffer.yaw_offset = 0
                buffer.yaw_base = 'At targets'

                buffer.yaw_jitter = 'Off'
                buffer.jitter_offset = nil

                if value == 'Static' then
                    buffer.yaw = '180'
                    buffer.yaw_offset = yaw_offset
                end

                if value == 'Spin' then
                    local time = globals.curtime() * speed * 0.1
                    local offset = yaw_offset * 0.5

                    offset = 180 + utils.lerp(
                        -offset, offset, time % 1
                    )

                    buffer.yaw = '180'
                    buffer.yaw_offset = offset
                end

                if value == 'Sway' then
                    local time = globals.curtime() * speed * 0.1
                    local t = math.abs(time % 2.0 - 1.0)

                    local offset = utils.lerp(
                        yaw_left,
                        yaw_right,
                        t
                    )
                    buffer.yaw = '180'
                    buffer.yaw_offset = offset
                end

                if value == 'Static Random' then
                    local function get_static_yaw(yaw_from, yaw_to)
                        if exploit.get().defensive.left == exploit.get().defensive.max then
                            static_yaw = utils.random_int(yaw_from, yaw_to)
                        end
                        return static_yaw
                    end

                    buffer.yaw = '180'
                    buffer.yaw_offset = get_static_yaw(yaw_left, yaw_right)
                end

                if value == 'Random' then
                    local offset = math.abs(
                        yaw_offset * 0.5
                    )

                    offset = 180 + utils.random_int(
                        -offset, offset
                    )

                    buffer.yaw = '180'
                    buffer.yaw_offset = offset
                end

                if value == 'Static LR' then
                    buffer.yaw = '180'
                    buffer.yaw_offset = 0

                    buffer.yaw_left = buffer.yaw_left + yaw_left
                    buffer.yaw_right = buffer.yaw_right + yaw_right
                end

                if value == 'X-Way' then
                    local ways_count = items.ways_count:get()
                    local ways_custom = items.ways_custom:get()

                    xway_tick = xway_tick + 1
                    local stage = xway_tick % ways_count

                    if ways_custom then
                        local way_item = items['way_' .. stage + 1]

                        if way_item ~= nil then
                            buffer.yaw = '180'
                            buffer.yaw_offset = way_item:get()
                        end
                    else
                        local progress = stage / (ways_count - 1)
                        local add = utils.lerp(-yaw_offset, yaw_offset, progress)

                        buffer.yaw = '180'
                        buffer.yaw_offset = add
                    end

                    if items.ways_auto_body_yaw:get() then
                        local body_yaw_offset = 0

                        if buffer.yaw_offset < 0 then
                            body_yaw_offset = -1
                        end

                        if buffer.yaw_offset > 0 then
                            body_yaw_offset = 1
                        end

                        buffer.body_yaw = 'Static'
                        buffer.body_yaw_offset = body_yaw_offset
                    end
                end

                update_yaw_modifier(buffer, items)
            end

            local function update_body_yaw(buffer, items)
                if items.body_yaw == nil then
                    return
                end

                local value = items.body_yaw:get()
                local offset = items.body_yaw_offset:get()

                if value == 'Off' then
                    return
                end

                buffer.body_yaw = value
                buffer.body_yaw_offset = offset

                buffer.delay = nil

                local should_update_delay = (
                    value == 'Jitter'
                    and items.delay_1 ~= nil
                    and items.delay_2 ~= nil
                )

                if should_update_delay then
                    local delay = utils.random_int(
                        items.delay_1:get(),
                        items.delay_2:get()
                    )

                    buffer.delay = math.max(1, delay)
                end
            end

            function defensive:update(cmd)
                if cmd.chokedcommands == 0 then
                    update_pitch_inverter()
                    update_modifier_inverter()
                end
            end

            function defensive:apply(cmd, items)
                if items.force_break_lc ~= nil and items.force_break_lc:get() then
                    cmd.force_defensive = true
                end

                local is_exploit_active = software.is_double_tap_active()
                    or software.is_on_shot_antiaim_active()

                local is_duck_peek_active = software.is_duck_peek_assist()

                if not is_exploit_active or is_duck_peek_active then
                    return false
                end

                local exploit_data = exploit.get()
                local defensive_data = exploit_data.defensive

                if defensive_data.left == 0 or not math.exploit() then
                    return false
                end

                local is_defensive = true

                local activation = items.activation:get()

                if activation == 'Sensitivity' then
                    local start_tick = items.sensitivity_start:get()
                    local end_tick = items.sensitivity_end:get()

                    is_defensive = defensive_data.left > start_tick and defensive_data.left < end_tick
                end

                if not items.enabled:get() or not is_defensive then
                    return false
                end

                local buffer_ctx = { }

                update_body_yaw(buffer_ctx, items)
                update_pitch(buffer_ctx, items)
                update_yaw(buffer_ctx, items)

                buffer.defensive = buffer_ctx

                if activation == 'Twilight' then
                    cmd.force_defensive = cmd.command_number % 7 == 0
                end

                return true
            end
        end

        local fakelag_clone = { } do
            local ref = ref.fakelag

            local HOTKEY_MODE = {
                [0] = 'Always on',
                [1] = 'On hotkey',
                [2] = 'Toggle',
                [3] = 'Off hotkey'
            }

            local function get_hotkey_value(_, mode, key)
                return HOTKEY_MODE[mode], key or 0
            end

            local function on_paint_ui()
                ui.set(software.antiaimbot.fake_lag.enabled[1], ref.enabled:get())
                ui.set(software.antiaimbot.fake_lag.enabled[2], get_hotkey_value(ref.hotkey:get()))

                ui.set(software.antiaimbot.fake_lag.amount, ref.amount:get())

                ui.set(software.antiaimbot.fake_lag.variance, ref.variance:get())
                ui.set(software.antiaimbot.fake_lag.limit, ref.limit:get())
            end

            client.set_event_callback('paint_ui', on_paint_ui)
        end

        local builder = { } do
            local ref = ref.antiaim.builder

            local function is_dormant()
                return next(entity.get_players(true)) == nil
            end

            local function update_pitch(items)
                if items.pitch == nil then
                    return
                end

                buffer.pitch = items.pitch:get()
                buffer.pitch_offset = items.pitch_offset:get()
            end

            local function update_yaw(items)
                if items.yaw == nil then
                    return
                end

                buffer.yaw_base = 'At targets'

                buffer.yaw = items.yaw:get()
                buffer.yaw_offset = items.yaw_offset:get()

                if buffer.yaw == '180 LR' then
                    local yaw_left = items.yaw_left:get()
                    local yaw_right = items.yaw_right:get()

                    if items.yaw_asynced:get() then
                        yaw_left = utils.random_int(yaw_left, yaw_left - math.random(11,30))
                        yaw_right = utils.random_int(yaw_right, yaw_right - math.random(11,30))
                    end

                    buffer.yaw = '180'
                    buffer.yaw_offset = 0

                    buffer.yaw_left = yaw_left
                    buffer.yaw_right = yaw_right
                end
            end

            local function update_jitter(items)
                if items.yaw_jitter == nil then
                    return
                end

                buffer.yaw_jitter = items.yaw_jitter:get()
                buffer.jitter_offset = items.jitter_offset:get()
            end

            local function update_roll(items)
                if items.roll_value == nil then
                    return
                end

                buffer.roll = items.roll_value:get()
            end

            local function update_body_yaw(items)
                if items.body_yaw == nil then
                    return
                end

                buffer.body_yaw = items.body_yaw:get()

                buffer.body_yaw_offset = items.body_yaw_offset:get()
                buffer.freestanding_body_yaw = items.freestanding_body_yaw:get()

                if buffer.body_yaw == 'LBY' then
                    buffer.body_yaw_offset = items.lby_desync:get()

                    if items.lby_inverter:get() then
                        buffer.body_yaw_offset = -buffer.body_yaw_offset
                    end
                end

                if items.invert_chance ~= nil then
                    buffer.invert_chance = items.invert_chance:get()
                end

                if items.delay_body_1 ~= nil and items.delay_body_2 ~= nil then
                    local delay = utils.random_int(
                        items.delay_body_1:get(),
                        items.delay_body_2:get()
                    )

                    buffer.delay = math.max(1, delay)
                end

                if buffer.body_yaw == 'Hold Yaw' and items.hold_time ~= nil then
                    buffer.hold_time = items.hold_time:get()
                    buffer.hold_delay = items.hold_delay:get()
                end

                if buffer.body_yaw == 'Tick' and items.tick_speed ~= nil then
                    buffer.tick_speed = items.tick_speed:get()
                    buffer.tick_delay = items.tick_delay:get()
                end
            end

            function builder:get(state)
                return ref[state]
            end

            function builder:is_active_ex(items)
                return items.enabled == nil
                    or items.enabled:get()
            end

            function builder:is_active(state)
                local items = self:get(state)

                if items == nil then
                    return false
                end

                return self:is_active_ex(items)
            end

            function builder:apply_ex(items)
                if items == nil then
                    return false
                end

                buffer.enabled = true

                update_pitch(items)
                update_yaw(items)
                update_jitter(items)
                update_body_yaw(items)
                update_roll(items)

                return true
            end

            function builder:apply(state)
                local items = self:get(state)

                if items == nil then
                    return false, nil
                end

                if not self:is_active_ex(items) then
                    return false, items
                end

                self:apply_ex(items)
                return true, items
            end

            function builder:update(cmd)
                if not exploit.get().shift then
                    local state, items = self:apply 'Fakelag'

                    if state and items ~= nil then
                        return state, items
                    end
                end

                if is_dormant() then
                    local state, items = self:apply 'Dormant'

                    if state and items ~= nil then
                        return state, items
                    end
                end

                local states = statement.get()
                local state = states[#states]

                if state == nil then
                    return false, nil
                end

                local active, items = self:apply(state)

                if not active or items == nil then
                    local _, new_items = self:apply 'Default'

                    if new_items ~= nil then
                        items = new_items
                    end
                end

                return true, items
            end
        end

        local legit_aa = { } do
            local is_interact_traced = false

            local function should_update(cmd, items)
                local me = entity.get_local_player()

                if me == nil then
                    return false
                end

                local weapon = entity.get_player_weapon(me)

                if weapon == nil then
                    return false
                end

                local weapon_info = csgo_weapons(weapon)

                if weapon_info == nil then
                    return false
                end

                local team = entity.get_prop(me, 'm_iTeamNum')
                local my_origin = vector(entity.get_origin(me))

                local is_weapon_bomb = weapon_info.idx == 49

                local is_defusing = entity.get_prop(me, 'm_bIsDefusing') == 1
                local is_rescuing = entity.get_prop(me, 'm_bIsGrabbingHostage') == 1

                local in_bomb_site = entity.get_prop(me, 'm_bInBombZone') == 1

                if is_defusing or is_rescuing then
                    return false
                end

                if in_bomb_site and is_weapon_bomb then
                    return false
                end

                if team == 3 and cmd.pitch > 15 then
                    local bombs = entity.get_all 'CPlantedC4'

                    for i = 1, #bombs do
                        local bomb = bombs[i]

                        local origin = vector(
                            entity.get_origin(bomb)
                        )

                        local delta = origin - my_origin
                        local distancesqr = delta:lengthsqr()

                        if distancesqr < (62 * 62) then
                            return false
                        end
                    end
                end

                local camera = vector(client.camera_angles())
                local forward = vector():init_from_angles(camera:unpack())

                local eye_pos = vector(client.eye_position())
                local end_pos = eye_pos + forward * 128

                local fraction, entindex = client.trace_line(
                    me, eye_pos.x, eye_pos.y, eye_pos.z, end_pos.x, end_pos.y, end_pos.z
                )

                if fraction ~= 1 then
                    if entindex == -1 then
                        return true
                    end

                    local classname = entity.get_classname(entindex)

                    if classname == 'CWorld' then
                        return true
                    end

                    if classname == 'CFuncBrush' then
                        return true
                    end

                    if classname == 'CCSPlayer' then
                        return true
                    end

                    if classname == 'CHostage' then
                        local origin = vector(entity.get_origin(entindex))
                        local distance = eye_pos:distsqr(origin)

                        if distance < (84 * 84) then
                            return false
                        end
                    end

                    if not is_interact_traced then
                        is_interact_traced = true
                        return false
                    end
                end

                return true
            end

            function legit_aa:update(cmd)
                if cmd.in_use == 0 then
                    is_interact_traced = false

                    return false
                end

                local items = builder:get 'Legit AA'

                if items == nil then
                    return false
                end

                if items.override ~= nil and not items.override:get() then
                    return false
                end

                if not should_update(cmd, items) then
                    return false
                end

                buffer.pitch = 'Custom'
                buffer.pitch_offset = cmd.pitch

                builder:apply_ex(items)

                if items ~= nil and items.defensive ~= nil then
                    defensive:apply(cmd, items.defensive)
                end

                buffer.yaw_offset = buffer.yaw_offset + 180
                buffer.freestanding = false

                cmd.in_use = 0
                
                buffer.yaw_base = 'Local view'
                return true
            end
        end

        local safe_head = { } do
            local ref = ref.antiaim.settings.safe_head

            local WEAPONTYPE_KNIFE = 0
            local FAR_DISTANCE_SQR = 1200 * 1200

            local function is_weapon_taser(weapon)
                local weapon_info = csgo_weapons(weapon)

                if weapon_info == nil then
                    return false
                end

                return weapon_info.idx == 31
            end

            local function is_weapon_knife(weapon)
                local weapon_info = csgo_weapons(weapon)

                if weapon_info == nil then
                    return false
                end

                if weapon_info.idx == 31 then -- taser
                    return false
                end

                return weapon_info.weapon_type_int == WEAPONTYPE_KNIFE
            end

            local function get_state()
                local me = entity.get_local_player()

                if me == nil then
                    return nil
                end

                local weapon = entity.get_player_weapon(me)

                if weapon == nil then
                    return nil
                end

                local is_knife = is_weapon_knife(weapon)
                local is_taser = is_weapon_taser(weapon)

                local in_air = not localplayer.is_onground
                local is_moving = localplayer.is_moving
                local is_crouched = localplayer.is_crouched

                if is_knife and in_air and is_crouched and ref.states:get 'Knife' then
                    return 'Knife'
                end

                if is_taser and in_air and is_crouched and ref.states:get 'Taser' then
                    return 'Taser'
                end

                local threat = client.current_threat()

                if threat ~= nil then
                    local my_origin = vector(entity.get_origin(me))
                    local threat_origin = vector(entity.get_origin(threat))

                    local delta = my_origin - threat_origin
                    local lengthsqr = delta:lengthsqr()

                    if delta.z > 50 and (not is_moving or is_crouched) and ref.states:get 'Above enemy' then
                        return 'Above enemy'
                    end

                    if lengthsqr > FAR_DISTANCE_SQR and (not is_moving and is_crouched) and ref.states:get 'Distance' then
                        return 'Distance'
                    end
                end

                return nil
            end

            local function update_safe_head_buffer(cmd)
                local applied, items = builder:apply 'Safe Head'

                if not applied then
                    return false
                end

                if items ~= nil and cmd ~= nil and items.defensive ~= nil then
                    defensive:apply(cmd, items.defensive)
                end

                return true
            end

            function safe_head:update(cmd)
                if not ref.enabled:get() then
                    return false
                end

                local state = get_state()

                if state == nil then
                    return false
                end

                return update_safe_head_buffer(cmd)
            end
        end

        local disablers = { } do
            local ref = ref.antiaim.settings.disablers

            local function is_warmup()
                local game_rules = entity.get_game_rules()

                if game_rules == nil then
                    return false
                end

                local warmup_period = entity.get_prop(
                    game_rules, 'm_bWarmupPeriod'
                )

                return warmup_period == 1
            end

            local function is_no_enemies()
                local me = entity.get_local_player()

                if me == nil then
                    return false
                end

                local my_team = entity.get_prop(me, 'm_iTeamNum')
                local player_resource = entity.get_player_resource()

                for i = 1, globals.maxplayers() do
                    local is_connected = entity.get_prop(
                        player_resource, 'm_bConnected', i
                    )

                    if is_connected ~= 1 then
                        goto continue
                    end

                    local player_team = entity.get_prop(
                        player_resource, 'm_iTeam', i
                    )

                    if me == i or player_team == my_team then
                        goto continue
                    end

                    local is_alive = entity.get_prop(
                        player_resource, 'm_bAlive', i
                    )

                    if is_alive == 1 then
                        return false
                    end

                    ::continue::
                end

                return true
            end

            local function should_disable()
                if ref.select:get 'Warmup' and is_warmup() then
                    return true
                end

                if ref.select:get 'No enemies' and is_no_enemies() then
                    return true
                end

                return false
            end

            function disablers:update(cmd)
                if not ref.enabled:get() then
                    return
                end

                if should_disable() then
                    buffer.pitch = 'Custom'
                    buffer.pitch_offset = 0
                    buffer.yaw = "Spin"
                    buffer.yaw_offset = 90
                    buffer.yaw_base = 'Local view'
                    buffer.yaw_jitter = "Off"
                    buffer.jitter_offset = 0
                    buffer.body_yaw = 'Static'
                    buffer.body_yaw_offset = 0
                end
            end
        end

        local avoid_backstab = { } do
            local ref = ref.antiaim.settings.avoid_backstab

            local WEAPONTYPE_KNIFE = 0
            local MAX_DISTANCE_SQR = 400 * 400

            local function is_weapon_knife(weapon)
                local weapon_info = csgo_weapons(weapon)

                if weapon_info == nil then
                    return false
                end

                if weapon_info.idx == 31 then -- taser
                    return false
                end

                return weapon_info.weapon_type_int == WEAPONTYPE_KNIFE
            end

            local function is_player_weapon_knife(player)
                local weapon = entity.get_player_weapon(player)

                if weapon == nil then
                    return false
                end

                return is_weapon_knife(weapon)
            end

            local function get_backstab_angle(player)
                local best_delta = nil
                local best_target = nil
                local best_distancesqr = math.huge

                local origin = vector(
                    entity.get_origin(player)
                )

                local enemies = entity.get_players(true)

                for i = 1, #enemies do
                    local enemy = enemies[i]

                    if not is_player_weapon_knife(enemy) then
                        goto continue
                    end

                    local enemy_origin = vector(
                        entity.get_origin(enemy)
                    )

                    local delta = enemy_origin - origin
                    local distancesqr = delta:lengthsqr()

                    best_delta = delta
                    best_target = enemy
                    best_distancesqr = distancesqr

                    ::continue::
                end

                return best_target, best_distancesqr, best_delta
            end

            function avoid_backstab:update()
                if not ref.enabled:get() then
                    return false
                end

                local me = entity.get_local_player()

                if me == nil then
                    return false
                end

                local target, distancesqr, delta = get_backstab_angle(me)

                if target == nil or distancesqr > MAX_DISTANCE_SQR then
                    return false
                end

                local angle = vector(
                    delta:angles()
                )

                buffer.enabled = true
                buffer.yaw_base = 'Local view'

                buffer.yaw = 'Static'
                buffer.yaw_offset = angle.y

                buffer.freestanding_body_yaw = false

                buffer.edge_yaw = false
                buffer.freestanding = false

                buffer.roll = 0

                return true
            end
        end

        local manual_yaw = { } do
            local ref = ref.antiaim.settings.manual_yaw

            local current_dir = nil
            local hotkey_data = { }
            local hotkey_initialized = false

            local dir_rotations = {
                ['left'] = -90,
                ['right'] = 90,
                ['forward'] = 180,
                ['backward'] = 0
            }

            local function get_hotkey_state(old_state, state, mode)
                if mode == 1 or mode == 2 then
                    return old_state ~= state
                end

                return false
            end

            local function update_hotkey_state(data, state, mode)
                local active = get_hotkey_state(
                    data.state, state, mode
                )

                data.state = state
                return active
            end

            local function update_hotkey_data(id, dir)
                if hotkey_data[id] == nil then
                    hotkey_data[id] = {
                        state = false
                    }
                end

                local changed = update_hotkey_state(
                    hotkey_data[id], ui.get(id)
                )

                if not changed then
                    return
                end

                if current_dir == dir then
                    current_dir = nil
                else
                    current_dir = dir
                end
            end

            local function on_paint_ui()
                if not hotkey_initialized then
                    hotkey_initialized = true

                    local dirs = {
                        { ref = ref.left_hotkey.ref, dir = 'left' },
                        { ref = ref.right_hotkey.ref, dir = 'right' },
                        { ref = ref.forward_hotkey.ref, dir = 'forward' },
                        { ref = ref.backward_hotkey.ref, dir = 'backward' },
                    }

                    for i = 1, #dirs do
                        local id = dirs[i].ref
                        hotkey_data[id] = { state = ui.get(id) }

                        if ui.get(id) then
                            current_dir = dirs[i].dir
                        end
                    end

                    local reset_id = ref.reset_hotkey.ref
                    hotkey_data[reset_id] = { state = ui.get(reset_id) }

                    return
                end

                update_hotkey_data(ref.left_hotkey.ref, 'left')
                update_hotkey_data(ref.right_hotkey.ref, 'right')
                update_hotkey_data(ref.forward_hotkey.ref, 'forward')
                update_hotkey_data(ref.backward_hotkey.ref, 'backward')

                update_hotkey_data(ref.reset_hotkey.ref, nil)
            end

            function manual_yaw:get()
                return current_dir
            end

            function manual_yaw:update(cmd)
                local angle = dir_rotations[
                    current_dir
                ]

                if angle == nil then
                    return false
                end

                buffer.enabled = true

                buffer.yaw_offset = angle

                buffer.yaw_left = 0
                buffer.yaw_right = 0

                buffer.edge_yaw = false
                buffer.freestanding = false

                buffer.roll = 0

                if ref.disable_yaw_modifiers:get() then
                    buffer.yaw_jitter = 'Off'
                    buffer.jitter_offset = 0
                end

                if ref.body_freestanding:get() then
                    buffer.body_yaw = 'Static'
                    buffer.body_yaw_offset = 180
                    buffer.freestanding_body_yaw = true
                end

                local state, items = builder:apply 'Manual AA'

                if state and items ~= nil then
                    buffer.yaw_offset = buffer.yaw_offset + angle

                    if items.defensive ~= nil then
                        if defensive:apply(cmd, items.defensive) then
                            local yaw_offset = buffer.defensive.yaw_offset

                            if yaw_offset ~= nil then
                                buffer.defensive.yaw_offset = yaw_offset + angle
                            end
                        end
                    end
                end

                buffer.yaw_base = 'Local view'

                return true
            end

            client.set_event_callback(
                'paint_ui', on_paint_ui
            )

            antiaim.manual_yaw = manual_yaw
        end

        local freestanding = { } do
            local ref = ref.antiaim.settings.freestanding

            local last_ack_defensive_side = nil
            local freestanding_side = nil

            local function is_value_near(value, target)
                return math.abs(target - value) <= 2.0
            end

            local function get_target_yaw(player)
                local threat = client.current_threat()

                if threat == nil then
                    return nil
                end

                local player_origin = vector(
                    entity.get_origin(player)
                )

                local threat_origin = vector(
                    entity.get_origin(threat)
                )

                local delta = threat_origin - player_origin
                local _, yaw = delta:angles()

                return yaw - 180
            end

            local function get_side()
                local me = entity.get_local_player()

                if me == nil then
                    return nil
                end

                local entity_data = c_entity(me)

                if entity_data == nil then
                    return nil
                end

                local animstate = entity_data:get_anim_state()

                if animstate == nil then
                    return nil
                end

                local target_yaw = get_target_yaw(me)

                if target_yaw == nil then
                    return nil
                end

                local delta = utils.normalize(animstate.eye_angles_y - target_yaw, -180, 180)

                if delta < 0 then
                    return -90
                end

                return 90
            end

            local function is_enabled()
                if not ref.enabled:get() then
                    return false
                end

                if not ref.hotkey:get() then
                    return false
                end

                return true
            end

            local function update_freestanding_options(cmd)
                local items = builder:get 'Freestanding'

                if not builder:is_active_ex(items) then
                    items = nil
                end

                if freestanding_side ~= nil then
                    buffer.pitch = 'Default'

                    if items ~= nil then
                        builder:apply_ex(items)
                    end

                    buffer.body_yaw = 'Static'
                    buffer.body_yaw_offset = 180
                    buffer.freestanding_body_yaw = true
                end

                if localplayer.is_vulnerable then
                    if items ~= nil and items.defensive ~= nil then
                        if defensive:apply(cmd, items.defensive) then
                            local yaw_offset = buffer.defensive.yaw_offset

                            if yaw_offset ~= nil and last_ack_defensive_side ~= nil then
                                buffer.defensive.yaw_offset = yaw_offset + last_ack_defensive_side
                            end
                        else
                            if freestanding_side ~= nil then
                                last_ack_defensive_side = freestanding_side
                            end
                        end
                    end
                end
            end

            function freestanding:update(cmd)
                if not is_enabled() then
                    freestanding_side = nil
                    return
                end

                if cmd.chokedcommands == 0 then
                    freestanding_side = get_side()
                end

                buffer.freestanding = true
                update_freestanding_options(cmd)
            end
        end

        local defensive_flick = { } do
            local ref = ref.antiaim.settings.defensive_flick

            local function get_state()
                if not localplayer.is_onground then
                    if localplayer.is_crouched then
                        return 'Jumping+'
                    end

                    return 'Jumping'
                end

                if localplayer.is_crouched then
                    if localplayer.is_moving then
                        return 'Move-Crouch'
                    end

                    return 'Crouch'
                end

                if localplayer.is_moving then
                    if software.is_slow_motion() then
                        return 'Slow Walk'
                    end

                    return 'Moving'
                end

                return 'Standing'
            end

            local function should_update()
                if not ref.enabled:get() then
                    return false
                end

                local me = entity.get_local_player()

                if me == nil then
                    return false
                end

                local weapon = entity.get_player_weapon(me)

                if weapon == nil then
                    return false
                end

                local weapon_info = csgo_weapons(weapon)

                if weapon_info == nil or weapon_info.is_revolver then
                    return false
                end

                local exp_data = exploit.get()

                if not exp_data.shift then
                    return false
                end

                return ref.states:get(get_state())
            end

            local flick_tick_counter = 0
            local flick_current_speed = 0

            function defensive_flick:update(cmd)
                if not should_update() then
                    flick_tick_counter = 0
                    return
                end

                local inverter = ref.inverter:get()
                local defensive = exploit.get().defensive
                local is_defensive_active = defensive.left ~= 0

                local speed = ref.speed:get()
                local speed_random = ref.speed_random:get()
                local flick_pitch = ref.pitch:get()
                local flick_yaw = ref.yaw:get()
                local flick_yaw_random = ref.yaw_random:get()
                local flick_auto_body_yaw = ref.auto_body_yaw:get()

                -- randomize speed per defensive window
                if defensive.left == defensive.max then
                    flick_tick_counter = 0
                    if speed_random > 0 then
                        flick_current_speed = speed + utils.random_int(0, speed_random)
                    else
                        flick_current_speed = speed
                    end
                end

                -- toggle force_defensive at configured speed
                local effective_speed = math.max(2, flick_current_speed)
                cmd.force_defensive = cmd.command_number % effective_speed == 0

                flick_tick_counter = flick_tick_counter + 1

                -- yaw + random offset
                local yaw_offset = flick_yaw
                if flick_yaw_random > 0 then
                    yaw_offset = yaw_offset + utils.random_int(-flick_yaw_random, flick_yaw_random)
                end

                -- override AA angles
                buffer.pitch = is_defensive_active and 'Custom' or 'Default'
                buffer.pitch_offset = is_defensive_active and flick_pitch or 180

                buffer.yaw_base = 'At targets'

                buffer.yaw = '180'
                buffer.yaw_offset = is_defensive_active and yaw_offset or 0

                buffer.yaw_left = 0
                buffer.yaw_right = 0

                buffer.yaw_jitter = 'Off'
                buffer.jitter_offset = 0

                buffer.body_yaw = 'Static'
                if flick_auto_body_yaw then
                    local body_yaw_offset = 0

                    if buffer.yaw_offset < 0 then
                        body_yaw_offset = -1
                    end

                    if buffer.yaw_offset > 0 then
                        body_yaw_offset = 1
                    end

                    buffer.body_yaw_offset = body_yaw_offset
                else
                    buffer.body_yaw_offset = is_defensive_active and -1 or 1
                end

                buffer.freestanding_body_yaw = false

                buffer.edge_yaw = false
                buffer.freestanding = false

                buffer.roll = 0

                if inverter then
                    buffer.yaw_offset = -buffer.yaw_offset
                end
            end
        end

        local function update_defensive(cmd)
            local list = buffer.defensive

            local exp_data = exploit.get()
            local defensive = exp_data.defensive

            local is_valid = (
                list ~= nil and
                defensive.left > 0
            )

            if not is_valid then
                return false
            end

            buffer:copy(list)
            return true
        end

        local function update_inverter(mode)
            if exploit.get().shift then
                local delay = math.max(
                    1, buffer.delay or 1
                )

                delay_ptr[mode] = delay_ptr[mode] + 1

                if delay_ptr[mode] < delay then
                    return
                end
            end

            local should_invert = true

            if buffer.body_yaw == 'Jitter' then
                local chance = buffer.invert_chance or 100
                should_invert = utils.random_int(0, 100) <= chance
            end

            if buffer.body_yaw == 'Random' then
                should_invert = utils.random_int(0, 1) == 0
            end

            inverts = inverts + 1

            if should_invert then
                inverted = not inverted
            end

            delay_ptr[mode] = 0
        end

        local function update_antiaims(cmd)
            buffer.freestanding = false

            defensive:update(cmd)

            local state, items = builder:update(cmd)

            if legit_aa:update(cmd) then
                return
            end

            if manual_yaw:update(cmd) then
                return
            end

            if avoid_backstab:update() then
                return
            end

            local safe_head_active = safe_head:update(cmd)

            if not safe_head_active and state and items ~= nil and items.defensive ~= nil then
                defensive:apply(cmd, items.defensive)
            end

            freestanding:update(cmd)
            defensive_flick:update(cmd)

            disablers:update(cmd)
        end

        local function update_micromove(cmd)
            if cmd.chokedcommands == 0 then
                return
            end

            if cmd.in_attack == 1 then
                return
            end

            micromove_inverted = not micromove_inverted

            cmd.yaw = math.random(-180, 180)
        end

        local function update_yaw_offset()
            if buffer.body_yaw_offset == nil then
                return
            end

            if buffer.yaw_left ~= nil and buffer.yaw_right ~= nil then
                local yaw = buffer.yaw_offset or 0

                if buffer.body_yaw_offset < 0 then
                    buffer.yaw_offset = yaw + buffer.yaw_left
                end

                if buffer.body_yaw_offset > 0 then
                    buffer.yaw_offset = yaw + buffer.yaw_right
                end

                return
            end
        end

        local function update_yaw_jitter()
            if buffer.yaw_jitter == 'Offset' then
                local yaw = buffer.yaw_offset or 0
                local offset = buffer.jitter_offset

                buffer.yaw_jitter = 'Off'
                buffer.jitter_offset = 0

                buffer.yaw_offset = yaw + (inverted and offset or 0)

                return
            end

            if buffer.yaw_jitter == 'Center' then
                local yaw = buffer.yaw_offset or 0
                local offset = buffer.jitter_offset

                if not inverted then
                    offset = -offset
                end

                buffer.yaw_jitter = 'Off'
                buffer.jitter_offset = 0

                buffer.yaw_offset = yaw + offset / 2

                return
            end

            if buffer.yaw_jitter == 'Skitter' then
                local index = inverts % #skitter
                local multiplier = skitter[index + 1]

                local yaw = buffer.yaw_offset or 0
                local offset = buffer.jitter_offset

                buffer.yaw_jitter = 'Off'
                buffer.jitter_offset = 0

                buffer.yaw_offset = yaw + (offset * multiplier)

                return
            end

            if buffer.yaw_jitter == 'Spin' then
                local time = globals.curtime() * 3

                local yaw = buffer.yaw_offset or 0
                local offset = buffer.jitter_offset

                buffer.yaw_jitter = 'Off'
                buffer.jitter_offset = 0

                buffer.yaw_offset = yaw + utils.lerp(
                    -offset, offset, time % 1
                )

                return
            end
        end

        local function update_body_yaw(cmd)
            if buffer.body_yaw == 'LBY' then
                buffer.body_yaw = 'Static'

                local me = entity.get_local_player()
                local movetype = entity.get_prop(me, 'm_MoveType')

                if movetype ~= 9 then
                    update_micromove(cmd)

                    if cmd.chokedcommands == 0 and cmd.in_attack ~= 1 then
                        cmd.yaw = cmd.yaw - buffer.body_yaw_offset
                        cmd.allow_send_packet = false
                    end
                end
            end

            if buffer.body_yaw == 'Jitter' then
                local offset = buffer.body_yaw_offset

                if offset == 0 then
                    offset = 1
                end

                if not inverted then
                    offset = -offset
                end

                buffer.body_yaw = 'Static'
                buffer.body_yaw_offset = offset
            end

            if buffer.body_yaw == 'Random' then
                local offset = buffer.body_yaw_offset

                if offset == 0 then
                    offset = 1
                end

                buffer.body_yaw = 'Static'
                buffer.body_yaw_offset = inverted and offset or -offset
            end

            if buffer.body_yaw == 'Smart' then
                local SMART_RATIO = 1.6180339887

                local me = entity.get_local_player()
                local fl = entity.get_prop(me, 'm_nTickBase') - globals.tickcount()

                local offset = buffer.yaw_offset or 0

                if buffer.yaw_left ~= nil and not inverted then
                    offset = offset + buffer.yaw_left
                end

                if buffer.yaw_right ~= nil and inverted then
                    offset = offset + buffer.yaw_right
                end

                local max = antiaim_funcs.get_overlap(true) * (fl < 2 and 30 or 60)
                local modifier = utils.normalize(offset, -180, 180)

                local desync = math.abs(modifier * SMART_RATIO - (max * (inverted and 1 or -1)))

                if not inverted then
                    desync = desync * -1
                end

                buffer.body_yaw = 'Static'
                buffer.body_yaw_offset = desync
            end

            if buffer.body_yaw == 'Hold Yaw' then
                local offset = buffer.body_yaw_offset
                local hold_time = buffer.hold_time or 2
                local hold_delay = buffer.hold_delay or 2

                if offset == 0 then
                    offset = 1
                end

                if cmd.chokedcommands == 0 then
                    if hold_yaw_state.delay + 1 >= hold_delay then
                        if hold_yaw_state.time >= hold_time then
                            hold_yaw_state.side = not hold_yaw_state.side
                            hold_yaw_state.delay = 0
                            hold_yaw_state.time = 0
                        else
                            hold_yaw_state.time = hold_yaw_state.time + 1
                        end
                    else
                        hold_yaw_state.side = not hold_yaw_state.side
                        hold_yaw_state.delay = hold_yaw_state.delay + 1
                    end
                end

                inverted = hold_yaw_state.side
                buffer.body_yaw = 'Static'
                buffer.body_yaw_offset = hold_yaw_state.side and offset or -offset
            end

            if buffer.body_yaw == 'Tick' then
                local offset = buffer.body_yaw_offset
                local speed = buffer.tick_speed or 4
                local delay = buffer.tick_delay or 2

                if offset == 0 then
                    offset = 1
                end

                local period = delay + speed

                if cmd.chokedcommands == 0 then
                    tick_yaw_state.counter = tick_yaw_state.counter + 1
                    if tick_yaw_state.counter >= period then
                        tick_yaw_state.counter = 0
                    end
                end

                local is_left = tick_yaw_state.counter < speed
                inverted = is_left

                if is_left then
                    buffer.body_yaw_offset = offset
                else
                    buffer.body_yaw_offset = -offset
                end

                buffer.body_yaw = 'Static'
            end
        end

        local function update_buffer(cmd)
            local mode = 'default'

            if update_defensive(cmd) then
                mode = 'defensive'
            end

            if cmd.chokedcommands == 0 then
                update_inverter(mode)
            end

            update_body_yaw(cmd)
            update_yaw_jitter()
            update_yaw_offset()
        end

        local function on_shutdown()
            buffer:clear()
            buffer:unset()
        end

        local function on_setup_command(cmd)
            buffer:clear()
            buffer:unset()

            update_antiaims(cmd)
            update_buffer(cmd)

            -- roll + MM spoof
            local roll_val = buffer.roll or 0
            if roll_val ~= 0 then
                cmd.roll = roll_val
                buffer.roll = nil -- don't double-set via GS override

                -- spoof game rules for MM roll
                if mm_game_rule_ptr ~= nil then
                    local is_mm = ffi.cast('bool*', mm_game_rule_ptr[0] + 124)
                    if is_mm ~= nil and is_mm[0] == true then
                        is_mm[0] = false
                        mm_roll_spoofed = true
                    end
                end
            else
                cmd.roll = 0
            end

            buffer:set()
        end

        local function restore_mm_spoof()
            if mm_roll_spoofed and mm_game_rule_ptr ~= nil then
                local is_mm = ffi.cast('bool*', mm_game_rule_ptr[0] + 124)
                if is_mm ~= nil and is_mm[0] == false then
                    is_mm[0] = true
                end
                mm_roll_spoofed = false
            end
        end

        client.set_event_callback('shutdown', function()
            on_shutdown()
            restore_mm_spoof()
        end)
        client.set_event_callback('setup_command', on_setup_command)
    end

    local visuals = { } do
        local aspect_ratio do
            local ref = ref.visuals.aspect_ratio

            local r_aspectratio = cvar.r_aspectratio

            local function shutdown_aspect_ratio()
                r_aspectratio:set_raw_float(
                    tostring(r_aspectratio:get_string())
                )
            end

            local function on_shutdown()
                shutdown_aspect_ratio()
            end

            local function update_event_callbacks(value)
                if not value then
                    shutdown_aspect_ratio()
                end

                utils.event_callback(
                    'shutdown',
                    on_shutdown,
                    value
                )
            end

            local callbacks do
                local function on_value(item)
                    r_aspectratio:set_raw_float(
                        item:get() * 0.01
                    )
                end

                local function on_enabled(item)
                    local value = item:get()

                    if value then
                        ref.value:set_callback(on_value, true)
                    else
                        ref.value:unset_callback(on_value)
                    end

                    update_event_callbacks(value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local third_person do
            local ref = ref.visuals.third_person

            local cam_idealdist = cvar.cam_idealdist

            local ref_third_person = {
                ui.reference('Visuals', 'Effects', 'Force third person (alive)')
            }

            local dist_value = 15

            local function restore_values()
                cam_idealdist:set_float(tonumber(cam_idealdist:get_string()))
            end

            local function update_values(value)
                cam_idealdist:set_raw_float(value)
            end

            local function on_shutdown()
                cam_idealdist:set_raw_float(dist_value)
            end

            local function on_paint_ui()
                local me = entity.get_local_player()

                local should_update = (
                    entity.is_alive(me)
                    and ui.get(ref_third_person[1])
                    and ui.get(ref_third_person[2])
                )

                if not should_update then
                    dist_value = 15
                    return
                end

                local distance = ref.distance:get()
                local zoom_speed = ref.zoom_speed:get()

                local offset = (distance - dist_value) / zoom_speed

                dist_value = dist_value + (distance > dist_value and offset or -offset)
                dist_value = distance < dist_value and distance or dist_value

                update_values(dist_value)
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        restore_values()
                    end

                    utils.event_callback(
                        'shutdown',
                        on_shutdown,
                        value
                    )

                    utils.event_callback(
                        'paint_ui',
                        on_paint_ui,
                        value
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local viewmodel do
            local ref = ref.visuals.viewmodel

            local viewmodel_fov = cvar.viewmodel_fov

            local viewmodel_offset_x = cvar.viewmodel_offset_x
            local viewmodel_offset_y = cvar.viewmodel_offset_y
            local viewmodel_offset_z = cvar.viewmodel_offset_z

            local cl_righthand = cvar.cl_righthand

            local function get_weapon_info()
                local me = entity.get_local_player()

                if me == nil then
                    return nil
                end

                local weapon = entity.get_player_weapon(me)

                if weapon == nil then
                    return nil
                end

                return csgo_weapons(weapon)
            end

            local function update_knife_hand(is_knife)
                local is_right = cl_righthand:get_string() == '1'

                if is_right then
                    cl_righthand:set_raw_int(is_knife and 0 or 1)
                else
                    cl_righthand:set_raw_int(is_knife and 1 or 0)
                end
            end

            local function shutdown_viewmodel()
                viewmodel_fov:set_float(tonumber(viewmodel_fov:get_string()))

                viewmodel_offset_x:set_float(tonumber(viewmodel_offset_x:get_string()))
                viewmodel_offset_y:set_float(tonumber(viewmodel_offset_y:get_string()))
                viewmodel_offset_z:set_float(tonumber(viewmodel_offset_z:get_string()))

                cl_righthand:set_int(cl_righthand:get_string() == '1' and 1 or 0)
            end

            local function on_shutdown()
                shutdown_viewmodel()
            end

            local function on_pre_render(cmd)
                local weapon_info = get_weapon_info()

                if weapon_info == nil then
                    return
                end

                local weapon_index = weapon_info.idx

                if old_weaponindex ~= weapon_index then
                    weapon_index = old_weaponindex

                    -- update knife hand
                    update_knife_hand(weapon_info.type == 'knife')
                end
            end

            local function update_event_callbacks(value)
                if not value then
                    shutdown_viewmodel()

                    utils.event_callback(
                        'pre_render',
                        on_pre_render,
                        false
                    )
                end

                utils.event_callback(
                    'shutdown',
                    on_shutdown,
                    value
                )
            end

            local callbacks do
                local function on_fov(item)
                    viewmodel_fov:set_raw_float(
                        item:get() * 0.1
                    )
                end

                local function on_offset_x(item)
                    viewmodel_offset_x:set_raw_float(
                        item:get() * 0.1
                    )
                end

                local function on_offset_y(item)
                    viewmodel_offset_y:set_raw_float(
                        item:get() * 0.1
                    )
                end

                local function on_offset_z(item)
                    viewmodel_offset_z:set_raw_float(
                        item:get() * 0.1
                    )
                end

                local function on_opposite_knife_hand(item)
                    local value = item:get()

                    if value then
                        local weapon_info = get_weapon_info()

                        if weapon_info ~= nil then
                            update_knife_hand(weapon_info.type == 'knife')
                        end
                    else
                        cl_righthand:set_raw_int(cl_righthand:get_string() == '1' and 1 or 0)
                    end

                    utils.event_callback(
                        'pre_render',
                        on_pre_render,
                        value
                    )
                end

                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        shutdown_viewmodel()
                    end

                    if value then
                        ref.fov:set_callback(on_fov, true)

                        ref.offset_x:set_callback(on_offset_x, true)
                        ref.offset_y:set_callback(on_offset_y, true)
                        ref.offset_z:set_callback(on_offset_z, true)

                        ref.opposite_knife_hand:set_callback(
                            on_opposite_knife_hand, true
                        )
                    else
                        ref.fov:unset_callback(on_fov)

                        ref.offset_x:unset_callback(on_offset_x)
                        ref.offset_y:unset_callback(on_offset_y)
                        ref.offset_z:unset_callback(on_offset_z)

                        ref.opposite_knife_hand:unset_callback(
                            on_opposite_knife_hand
                        )
                    end

                    update_event_callbacks(value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local scope_animation do
            local ref = ref.visuals.scope_animation

            local fov_value = nil

            local function on_override_view(e)
                if fov_value == nil then
                    fov_value = e.fov
                end

                fov_value = motion.interp(
                    fov_value, e.fov, 0.035
                )

                e.fov = fov_value
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        fov_value = nil
                    end

                    utils.event_callback(
                        'override_view',
                        on_override_view,
                        value
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local custom_scope do
            local ref = ref.visuals.custom_scope

            local RESOLUTION = 1 / 1080

            local alpha = 0.0

            local function on_paint()
                override.set(software.visuals.effects.remove_scope_overlay, false)
            end

            local function on_paint_ui()
                local me = entity.get_local_player()

                if me == nil or not entity.is_alive(me) then
                    return
                end

                override.set(software.visuals.effects.remove_scope_overlay, true)

                local is_scoped = entity.get_prop(
                    me, 'm_bIsScoped'
                )

                alpha = motion.interp(alpha, is_scoped == 1, 1 / ref.animation_speed:get())

                if alpha == 0.0 then
                    return
                end

                local screen = vector(
                    client.screen_size()
                )

                local center = screen * 0.5

                local col = color(ref.color:get())

                local offset = ref.offset:get() * screen.y * RESOLUTION
                local position = ref.position:get() * screen.y * RESOLUTION

                offset = math.floor(offset)
                position = math.floor(position)

                local delta = position - offset

                local color_a = col:clone()
                local color_b = col:clone()

                color_a.a = color_a.a * alpha
                color_b.a = 0

                renderer.gradient(
                    center.x, center.y - offset + 1, 1, -delta,
                    color_a.r, color_a.g, color_a.b, color_a.a,
                    color_b.r, color_b.g, color_b.b, color_b.a,
                    false
                )

                renderer.gradient(
                    center.x, center.y + offset, 1, delta,
                    color_a.r, color_a.g, color_a.b, color_a.a,
                    color_b.r, color_b.g, color_b.b, color_b.a,
                    false
                )

                renderer.gradient(
                    center.x - offset + 1, center.y, -delta, 1,
                    color_a.r, color_a.g, color_a.b, color_a.a,
                    color_b.r, color_b.g, color_b.b, color_b.a,
                    true
                )

                renderer.gradient(
                    center.x + offset, center.y, delta, 1,
                    color_a.r, color_a.g, color_a.b, color_a.a,
                    color_b.r, color_b.g, color_b.b, color_b.a,
                    true
                )
            end

            local function update_event_callbacks(value)
                if not value then
                    override.unset(software.visuals.effects.remove_scope_overlay)
                end

                utils.event_callback(
                    'paint',
                    on_paint,
                    value
                )

                utils.event_callback(
                    'paint_ui',
                    on_paint_ui,
                    value
                )
            end

            local callbacks do
                local function on_enabled(item)
                    update_event_callbacks(item:get())
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local world_marker do
            local ref = ref.visuals.world_marker

            local queue = { }
            local aim_data = { }

            local function on_paint()
                if not boot.done then return end
                local dt = globals.frametime()

                local offset = 3
                local size = offset + 3

                local r, g, b, a = ref.color:get()

                for i = #queue, 1, -1 do
                    local data = queue[i]

                    data.time = data.time - dt

                    if data.time <= 0.0 then
                        data.alpha = motion.interp(
                            data.alpha, 0.0, 0.05
                        )

                        if data.alpha <= 0.0 then
                            table.remove(queue, i)
                        end
                    end
                end

                for i = 1, #queue do
                    local data = queue[i]

                    local x, y = renderer.world_to_screen(
                        data.pos:unpack()
                    )

                    if x == nil or y == nil then
                        goto continue
                    end

                    renderer.line(x - offset, y - offset, x - size, y - size, r, g, b, a * data.alpha)
                    renderer.line(x - offset, y + offset, x - size, y + size, r, g, b, a * data.alpha)
                    renderer.line(x + offset, y - offset, x + size, y - size, r, g, b, a * data.alpha)
                    renderer.line(x + offset, y + offset, x + size, y + size, r, g, b, a * data.alpha)

                    ::continue::
                end
            end

            local function on_aim_fire(e)
                aim_data[e.id] = vector(
                    e.x, e.y, e.z
                )
            end

            local function on_aim_hit(e)
                local pos = aim_data[e.id]

                if pos == nil then
                    return
                end

                table.insert(queue, {
                    pos = pos,
                    time = 1.5,
                    alpha = 1.0
                })
            end

            local function on_round_start()
                for i = 1, #queue do
                    queue[i] = nil
                end
            end

            local function update_event_callbacks(value)
                utils.event_callback('paint', on_paint, value)
                utils.event_callback('aim_hit', on_aim_hit, value)
                utils.event_callback('aim_fire', on_aim_fire, value)
                utils.event_callback('round_start', on_round_start, value)
            end

            local callbacks do
                local function on_enabled(item)
                    update_event_callbacks(item:get())
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local damage_marker do
            local ref = ref.visuals.damage_marker

            local queue = { }
            local aim_data = { }

            local function on_paint()
                if not boot.done then return end
                local dt = globals.frametime()
                local r, g, b, a = ref.color:get()

                for i = #queue, 1, -1 do
                    local data = queue[i]

                    data.time = data.time - dt
                    data.pos.z = data.pos.z + dt * 35

                    data.value = motion.interp(
                        data.value, 1.0, 0.1
                    )

                    if data.time <= 0.0 then
                        data.alpha = motion.interp(
                            data.alpha, 0.0, 0.05
                        )

                        if data.alpha <= 0.0 then
                            table.remove(queue, i)
                        end
                    end
                end

                for i = 1, #queue do
                    local data = queue[i]

                    local x, y = renderer.world_to_screen(data.pos:unpack())

                    if x == nil or y == nil then
                        goto continue
                    end

                    local damage = math.floor(
                        data.damage * data.value
                    )

                    renderer.text(x, y, r, g, b, a * data.alpha, 'c', nil, damage)

                    ::continue::
                end
            end

            local function on_aim_fire(e)
                aim_data[e.id] = vector(
                    e.x, e.y, e.z
                )
            end

            local function on_aim_hit(e)
                local pos = aim_data[e.id]

                if pos == nil then
                    return
                end

                table.insert(queue, {
                    pos = pos,
                    time = 3.0,

                    value = 0.0,
                    alpha = 1.0,

                    damage = e.damage
                })
            end

            local function on_round_start()
                for i = 1, #queue do
                    queue[i] = nil
                end
            end

            local function update_event_callbacks(value)
                utils.event_callback('paint', on_paint, value)

                utils.event_callback('aim_hit', on_aim_hit, value)
                utils.event_callback('aim_fire', on_aim_fire, value)

                utils.event_callback('round_start', on_round_start, value)
            end

            local callbacks do
                local function on_enabled(item)
                    update_event_callbacks(item:get())
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local watermark do
            local ref = ref.visuals.watermark

            local TITLE = string.format(
                '%s %s', script.name, script.build
            )

            local function get_text_array(text)
                local arr, size = { }, #text

                for i = 1, size do
                    arr[i] = text:sub(i, i)
                end

                return arr, size
            end

            local function get_caps_animation(text, time, start_pos, end_pos)
                local arr, size = get_text_array(text)
                local delta_pos = end_pos - start_pos + 1

                local index = start_pos + math.floor(time % delta_pos)

                if arr[index] ~= nil then
                    arr[index] = arr[index]:upper()
                end

                return table.concat(arr, nil, 1, size)
            end

            local function draw_default()
                if not boot.done then return end
                local screen_size = vector(
                    client.screen_size()
                )

                local position = vector(
                    screen_size.x * 0.5,
                    screen_size.y - 8
                )

                local str = TITLE do
                    local time = globals.realtime() * 6

                    str = get_caps_animation(
                        str, time, 2, #str
                    )
                end

                local text_size = vector(
                    renderer.measure_text('', str)
                )

                position.x = position.x - text_size.x * 0.5 + 0.5
                position.y = position.y - text_size.y

                renderer.text(position.x, position.y, 255, 255, 255, 200, '', nil, str)
            end

            local function draw_alternative()
                if not boot.done then return end
                local screen_size = vector(
                    client.screen_size()
                )

                local position = vector(
                    screen_size.x * 0.5,
                    screen_size.y - 8
                )

                local r0, g0, b0, a0 = 255, 255, 255, 255

                local text_list = { } do
                    local time = globals.realtime() * 0.5

                    local r1, g1, b1, a1 = 80, 80, 80, 255
                    local r2, g2, b2, a2 = ref.color:get()

                    table.insert(text_list, string.format(
                        '%s\a%s', text_anims.gradient(
                            script.name..' '..script.build, time, r1, g1, b1, a1, r2, g2, b2, a2
                        ), utils.to_hex(r0, g0, b0, a0)
                    ))

                    table.insert(text_list, string.format(
                        'delay: %dms', client.latency() * 1000
                    ))

                    table.insert(text_list, string.format(
                        '%02d:%02d:%02d', client.system_time()
                    ))
                end

                local text = table.concat(text_list, '   ')

                local text_size = vector(
                    renderer.measure_text('', text)
                )

                local box_size = text_size + vector(8, 10)

                position.x = position.x - box_size.x * 0.5
                position.y = position.y - box_size.y

                local text_pos = position + (box_size - text_size) * 0.5

                renderer.rectangle(position.x, position.y, box_size.x, box_size.y, 32, 32, 32, 50)
                renderer.text(text_pos.x, text_pos.y, r0, g0, b0, a0, '', nil, text)
            end

            local callbacks do
                local function on_select(item)
                    local value = item:get()

                    utils.event_callback('paint_ui', draw_default, value == 'Default')
                    utils.event_callback('paint_ui', draw_alternative, value == 'Alternative')
                end

                ref.select:set_callback(
                    on_select, true
                )
            end
        end
        local indicators do
            local ref = ref.visuals.indicators

            local y_offset = 0

            local TITLE_NAME = script.name:upper()
            local BUILD_NAME = script.build:upper()

            local draw_sparkles_indicators do
                local stars = {
                    { '★', -1, 7, 0.6 },
                    { '⋆', -8, 3, 0.2 },
                    { '✨', -2, 8, 0.7 },
                    { '✦', -2, 12, 0.5 },
                    { '★', -3, 8, 0.4 },
                    { '⋆', -5, 4, 0.3 },
                    { '✨', -3, 6, 0.7 },
                    { '⋆', -4, 5, 0.2 }
                }

                local alpha_value = 0.0
                local align_value = 0.0
                local alpha_scope = 1.0
                local frozen_value = 1.0

                local dt_value = 0.0
                local osaa_value = 0.0
                local dmg_value = 0.0
                local hc_value = 0.0
                local ad_value = 0.0
                local rapid_value = 0.0
                local state_value = 0.0
                local state_width = 0

                local y_center = 0

                local function get_state()
                    if not localplayer.is_onground then
                        if localplayer.is_crouched then
                            return 'jump+'
                        end

                        return 'jump'
                    end

                    if localplayer.is_crouched then
                        return 'crouch'
                    end

                    if localplayer.is_moving then
                        if software.is_slow_motion() then
                            return 'slow'
                        end

                        return 'move'
                    end

                    return 'stand'
                end

                local function animate_text(time, str, r1, g1, b1, a1, r2, g2, b2, a2)
                    local t_out, idx = {}, 1
                    local r_d, g_d, b_d, a_d = r2 - r1, g2 - g1, b2 - b1, a2 - a1

                    for i = 1, #str do
                        local iter = (i - 1) / math.max(#str - 1, 1) + time
                        local c = math.abs(math.cos(iter))

                        t_out[idx] = '\a' .. utils.to_hex(
                            round(r1 + r_d * c),
                            round(g1 + g_d * c),
                            round(b1 + b_d * c),
                            round(a1 + a_d * c)
                        )
                        t_out[idx + 1] = str:sub(i, i)
                        idx = idx + 2
                    end

                    return t_out
                end

                local function draw_stars(px, py, r, g, b, a)
                    local time = globals.realtime()

                    local x, y = px, py - 5

                    local sizes, len = { }, #stars
                    local width, height = 0, 0

                    for i = 1, len do
                        local data = stars[i]

                        local measure = vector(
                            renderer.measure_text('', data[1])
                        )

                        width = width + (measure.x + data[2])
                        height = math.max(height, measure.y + data[3])

                        sizes[i] = measure
                    end

                    x = round(x - width * 0.47) + round(36 * align_value)

                    for i = 1, len do
                        local star = stars[i]
                        local size = sizes[i]

                        local phase_value = math.sin(time * star[4]) do
                            phase_value = phase_value * 0.5 + 0.5
                            phase_value = phase_value * 0.7 + 0.3
                        end

                        renderer.text(
                            x + star[2], y + star[3],
                            r, g, b, a * phase_value,
                            '', nil, star[1]
                        )

                        x = x + (size.x + star[2])
                    end

                    return round(height * 0.58)
                end

                local function indicatext(px, py, r, g, b, a, flags, alpha, tw, ...)
                    if not alpha or alpha <= 0 then return end

                    local w = tw or renderer.measure_text(flags, ...)

                    local center_w = w
                    if align_value == 0 then
                        center_w = w * alpha
                    end

                    local x = round(px - center_w * 0.5 * (1 - align_value)) + round(20 * align_value)
                    local y = py

                    local final_a = a * math.max(0, alpha - (1 - frozen_value))

                    renderer.text(x, y, r, g, b, final_a, flags, 0, ...)

                    local _, h = renderer.measure_text(flags, ...)
                    y_center = y_center + round((h + 1) * alpha)
                end

                local function update_values(me)
                    local is_alive = entity.is_alive(me)
                    local is_scoped = entity.get_prop(me, 'm_bIsScoped')

                    local is_double_tap = software.is_double_tap_active()
                    local is_min_damage = software.is_override_minimum_damage()
                    local is_onshot_aa = software.is_on_shot_antiaim_active()

                    local m_fFlags = entity.get_prop(me, 'm_fFlags') or 0
                    local is_frozen = is_alive and bit.band(m_fFlags, bit.lshift(1, 6)) ~= 0

                    local is_rapid_ready = false
                    if is_alive and is_double_tap then
                        local tickbase = entity.get_prop(me, 'm_nTickBase') or 0
                        local tickcount = globals.tickcount()
                        is_rapid_ready = (tickbase - tickcount) > 0
                    end

                    alpha_value = motion.interp(alpha_value, is_alive, 0.04)
                    align_value = motion.interp(align_value, is_scoped == 1, 0.04)
                    local scope_dim_target = 1
                    if is_scoped == 1 and ref.scope_dim:get() then
                        scope_dim_target = ref.scope_dim_alpha:get() * 0.01
                    end
                    alpha_scope = motion.interp(alpha_scope, scope_dim_target, 0.04)
                    frozen_value = motion.interp(frozen_value, is_frozen and 0.5 or 1, 0.04)

                    local is_hc_override = software.is_hitchance_override_active()

                    local is_ad_active = exploit.is_anti_defensive_active()

                    dt_value = motion.interp(dt_value, is_double_tap, 0.04)
                    osaa_value = motion.interp(osaa_value, dt_value == 0 and is_onshot_aa, 0.04)
                    dmg_value = motion.interp(dmg_value, is_min_damage, 0.04)
                    hc_value = motion.interp(hc_value, is_hc_override, 0.04)
                    ad_value = motion.interp(ad_value, is_ad_active, 0.04)
                    rapid_value = motion.interp(rapid_value, is_rapid_ready and 0 or 1, 0.04)

                    local sw = renderer.measure_text('', get_state())
                    state_value = motion.interp(state_value, state_width == sw and 1 or 0, 0.04)
                    if state_value < 0.5 then
                        state_width = sw
                    end
                end

                local function draw_indicators()
                    local sw, sh = client.screen_size()
                    local cx, cy = sw * 0.5, sh * 0.5

                    local r1, g1, b1, a1 = ref.color_accent:get()
                    local r2, g2, b2, a2 = ref.color_secondary:get()

                    cy = cy + y_offset
                    a1 = round(a1 * alpha_value)
                    a2 = round(a2 * alpha_value)

                    y_center = 11

                    local rap = rapid_value

                    local stars_a = round(a1 * 0.75 * alpha_scope)
                    if stars_a > 0 then
                        local stars_h = draw_stars(cx, cy + 22, r1, g1, b1, stars_a)
                        y_center = math.max(y_center, 18 + stars_h)
                    end

                    local name = script.name:lower()
                    local name_w = renderer.measure_text('b', name)
                    local a_main = round(255 * alpha_value * alpha_scope)
                    local a_sec = round(255 * alpha_value * 0.75 * alpha_scope)
                    local namz = animate_text(
                        globals.curtime(), name,
                        r1, g1, b1, a_main,
                        r2, g2, b2, a_sec
                    )
                    indicatext(cx, cy + y_center, r1, g1, b1, a1 * alpha_scope, 'b', alpha_value, name_w, unpack(namz))

                    local dt_text = 'dt'
                    local shown_dt = dt_text:sub(1, round(0.5 + #dt_text * dt_value))
                    if #shown_dt > 0 then
                        indicatext(cx, cy + y_center, 255, round(255 * rap), round(255 * rap), round(200 * alpha_scope), '', dt_value, nil, shown_dt)
                    end

                    local osaa_text = 'osaa'
                    local shown_osaa = osaa_text:sub(1, round(0.5 + #osaa_text * osaa_value))
                    if #shown_osaa > 0 then
                        indicatext(cx, cy + y_center, 255, 255, 255, round(200 * alpha_scope), '', osaa_value, nil, shown_osaa)
                    end

                    local damage_text = 'dmg'
                    local shown_damage = damage_text:sub(1, round(0.5 + #damage_text * dmg_value))
                    if #shown_damage > 0 then
                        indicatext(cx, cy + y_center, 255, 255, 255, round(200 * alpha_scope), '', dmg_value, nil, shown_damage)
                    end

                    local hc_text = 'hc-ovr'
                    local shown_hc = hc_text:sub(1, round(0.5 + #hc_text * hc_value))
                    if #shown_hc > 0 then
                        indicatext(cx, cy + y_center, 255, 200, 100, round(200 * alpha_scope), '', hc_value, nil, shown_hc)
                    end

                    local ad_text = 'anti-def'
                    local shown_ad = ad_text:sub(1, round(0.5 + #ad_text * ad_value))
                    if #shown_ad > 0 then
                        local ad_pulse = math.abs(math.sin(globals.realtime() * 6.0))
                        indicatext(cx, cy + y_center, 255, round(60 + 40 * ad_pulse), round(60 + 40 * ad_pulse), round(200 * alpha_scope), '', ad_value, nil, shown_ad)
                    end

                    local state_text = get_state()
                    indicatext(cx, cy + y_center, 255, 255, 255, round(200 * alpha_scope), '', state_value, nil, state_text)
                end

                function draw_sparkles_indicators()
                    if not boot.done then return end
                    local me = entity.get_local_player()

                    if me == nil then
                        return
                    end

                    update_values(me)

                    if alpha_value > 0 then
                        draw_indicators()
                    end
                end
            end

            local draw_default_indicators do
                local old_exploit = ''

                local alpha_value = 0.0
                local align_value = 0.0

                local state_width = 0

                local dt_value = 0.0
                local dmg_value = 0.0
                local osaa_value = 0.0
                local hc_value = 0.0
                local ad_value = 0.0
                local exploit_value = 0.0

                local function is_holding_grenade(player)
                    local weapon = entity.get_player_weapon(player)

                    if weapon == nil then
                        return false
                    end

                    local weapon_info = csgo_weapons(weapon)

                    if weapon_info == nil then
                        return false
                    end

                    local weapon_type = weapon_info.type

                    if weapon_type ~= 'grenade' then
                        return false
                    end

                    return true
                end

                local function get_pulse(a, b)
                    local time = 0.6 + globals.realtime() * 3.0
                    local pulse = math.abs(math.sin(time))

                    return utils.lerp(a, b, pulse)
                end

                local function get_state()
                    if not localplayer.is_onground then
                        return '<AIR>'
                    end

                    if localplayer.is_crouched then
                        return '<CROUCH>'
                    end

                    if localplayer.is_moving then
                        if software.is_slow_motion() then
                            return '<WALKING>'
                        end

                        return '<MOVING>'
                    end

                    return '<WAITING>'
                end

                local function get_exploit_text()
                    if software.is_double_tap_active() then
                        old_exploit = ''
                    elseif software.is_on_shot_antiaim_active() then
                        old_exploit = 'HIDE'
                    end

                    return old_exploit
                end

                local function update_text_alpha(text, alpha)
                    local result = text:gsub('\a(%x%x%x%x%x%x)(%x%x)', function(rgb, a)
                        return '\a' .. rgb .. string.format('%02x', tonumber(a, 16) * alpha)
                    end)

                    return result
                end

                local function draw_title(position, r1, g1, b1, a1, r2, g2, b2, a2, alpha)
                    local flags, pad = '-', 1

                    local title1, title2 = "[+] ", TITLE_NAME, "[+]"

                    local measure1 = vector(renderer.measure_text(flags, title1))
                    local measure2 = vector(renderer.measure_text(flags, title2))

                    local width = measure1.x + measure2.x + pad
                    local height = math.max(measure1.y, measure2.y)

                    local x, y = position:unpack() do
                        x = round(x - (2 + width * 0.5) * (1 - align_value))
                    end

                    local pulse = get_pulse(0.25, 1.0)

                    renderer.text(x, y, r2, g2, b2, a2 * alpha, flags, nil, title1)
                    x = x + measure1.x + pad

                    renderer.text(x, y, r1, g1, b1, a1 * alpha * pulse, flags, nil, title2)
                    position.y = position.y + height
                end

                local function draw_state(position, r, g, b, a, alpha)
                    local text, flags = get_state(), '-'

                    local measure = vector(
                        renderer.measure_text(flags, text)
                    )

                    measure.x = measure.x + 1

                    if measure.x < state_width then
                        state_width = measure.x
                    else
                        state_width = motion.interp(
                            state_width, measure.x, 0.045
                        )
                    end

                    local x, y = position:unpack() do
                        x = round(x - (2 + state_width * 0.5) * (1 - align_value))
                    end

                    renderer.text(x, y, r, g, b, a * alpha, flags, round(state_width), text)
                    position.y = position.y + measure.y
                end

                local function draw_exploit(position, alpha, global_alpha)
                    local exp = exploit.get()
                    local def = exp.defensive
                    local is_double_tap = software.is_double_tap_active()

                    local text, flags = get_exploit_text(), '-'
                    local status, r, g, b, a = 'IDLE', 255, 255, 255, 200

                    if exploit_value == 1 then
                        if is_double_tap then
                            if def.left > 0 then
                                status = 'CHOKING'
                                r, g, b, a = 120, 255, 255, 255
                            else
                                status = 'EXPLOIT'
                                r, g, b, a = 192, 255, 109, 255
                            end
                        else
                            if def.left > 0 then
                                status = 'CHOKING'
                                r, g, b, a = 120, 255, 255, 255
                            else
                                status = 'ACTIVE'
                                r, g, b, a = 192, 255, 109, 255
                            end
                        end

                    elseif exploit_value == 0 then
                        status = 'WAITING'
                        r, g, b, a = 255, 64, 64, 128
                    else
                        status = 'WAITING   '

                        r = utils.lerp(255, 192, exploit_value)
                        g = utils.lerp(64, 255, exploit_value)
                        b = utils.lerp(64, 145, exploit_value)
                        a = 255
                    end

                    text = string.format(
                        '\a%s%s \a%s%s',
                        utils.to_hex(255, 255, 255, a), text,
                        utils.to_hex(r, g, b, a), status
                    )

                    local global_text = update_text_alpha(text, global_alpha * alpha)
                    local alpha_text = update_text_alpha(global_text, 0.5 * alpha)

                    local measure = vector(renderer.measure_text(flags, text)) do
                        measure.x = measure.x + 1
                    end

                    local width = round(measure.x * alpha)
                    local height = round(measure.y * alpha)

                    local charge_width = round(width * exploit_value)

                    local x, y = position:unpack() do
                        x = round(x - (1 + width * 0.5) * (1 - align_value))
                    end

                    if charge_width ~= 0 then
                        renderer.text(x, y, r, g, b, a * alpha * global_alpha, flags, charge_width, global_text)
                    end

                    if width ~= 0 then
                        renderer.text(x, y, r, g, b, a * alpha * global_alpha, flags, width, alpha_text)
                    end

                    position.y = position.y + height
                end

                local function draw_minimum_damage(position, alpha, global_alpha)
                    local text, flags = 'DMG', '-'

                    local measure = vector(
                        renderer.measure_text(flags, text)
                    )

                    measure.x = measure.x + 1

                    local width = round(measure.x)
                    local height = round(measure.y * alpha)

                    if width == 0 then
                        return
                    end

                    local x, y = position:unpack() do
                        x = round(x - (2 + width * 0.5) * (1 - align_value))
                    end

                    renderer.text(x, y, 255, 255, 255, 255 * alpha * global_alpha, flags, width, text)
                    position.y = position.y + height
                end

                local function draw_hitchance_override(position, alpha, global_alpha)
                    local text, flags = 'HC', '-'

                    local measure = vector(
                        renderer.measure_text(flags, text)
                    )

                    measure.x = measure.x + 1

                    local width = round(measure.x)
                    local height = round(measure.y * alpha)

                    if width == 0 then
                        return
                    end

                    local x, y = position:unpack() do
                        x = round(x - (2 + width * 0.5) * (1 - align_value))
                    end

                    renderer.text(x, y, 255, 200, 100, 255 * alpha * global_alpha, flags, width, text)
                    position.y = position.y + height
                end

                local function draw_anti_defensive(position, alpha, global_alpha)
                    local text, flags = 'AD', '-'

                    local measure = vector(
                        renderer.measure_text(flags, text)
                    )

                    measure.x = measure.x + 1

                    local width = round(measure.x)
                    local height = round(measure.y * alpha)

                    if width == 0 then
                        return
                    end

                    local x, y = position:unpack() do
                        x = round(x - (2 + width * 0.5) * (1 - align_value))
                    end

                    local pulse = get_pulse(0.4, 1.0)
                    renderer.text(x, y, 255, 60, 60, 255 * alpha * global_alpha * pulse, flags, width, text)
                    position.y = position.y + height
                end

                local function update_values(me)
                    local exp = exploit.get()

                    local is_alive = entity.is_alive(me)
                    local is_scoped = entity.get_prop(me, 'm_bIsScoped')

                    local is_grenade = is_holding_grenade(me)

                    local is_double_tap = software.is_double_tap_active()
                    local is_min_damage = software.is_override_minimum_damage()
                    local is_onshot_aa = software.is_on_shot_antiaim_active()

                    local alpha = 0.0

                    if is_alive then
                        alpha = is_grenade and 0.5 or 1.0
                    end

                    alpha_value = motion.interp(alpha_value, alpha, 0.04)
                    align_value = motion.interp(align_value, is_scoped == 1, 0.04)

                    local is_hc_override = software.is_hitchance_override_active()

                    local is_ad_active = exploit.is_anti_defensive_active()

                    dt_value = motion.interp(dt_value, is_double_tap, 0.03)
                    dmg_value = motion.interp(dmg_value, is_min_damage, 0.03)
                    osaa_value = motion.interp(osaa_value, is_onshot_aa, 0.03)
                    hc_value = motion.interp(hc_value, is_hc_override, 0.03)
                    ad_value = motion.interp(ad_value, is_ad_active, 0.03)
                    exploit_value = motion.interp(exploit_value, exp.shift, 0.025)

                    if not exp.shift then
                        exploit_value = 0
                    end
                end

                local function draw_indicators()
                    local screen = vector(client.screen_size())
                    local position = screen * 0.5

                    local r1, g1, b1, a1 = ref.color_accent:get()
                    local r2, g2, b2, a2 = ref.color_secondary:get()

                    position.x = position.x + round(10 * align_value)
                    position.y = position.y + y_offset

                    draw_title(position, r1, g1, b1, a1, r2, g2, b2, a2, alpha_value)
                    draw_exploit(position, math.max(dt_value, osaa_value), alpha_value)
                    draw_state(position, 255, 255, 255, 255, alpha_value)
                    draw_minimum_damage(position, dmg_value, alpha_value)
                    draw_hitchance_override(position, hc_value, alpha_value)
                    draw_anti_defensive(position, ad_value, alpha_value)
                end

                function draw_default_indicators()
                    if not boot.done then return end
                    local me = entity.get_local_player()

                    if me == nil then
                        return
                    end

                    update_values(me)

                    if alpha_value > 0 then
                        draw_indicators()
                    end
                end
            end

            local callbacks do
                local function on_scope_dim(item)
                    local value = item:get()
                    ref.scope_dim_alpha:set_visible(value)
                end

                local function on_style(item)
                    local value = item:get()
                    local is_sparkles = value == 'Sparkles'

                    utils.event_callback('paint_ui', draw_default_indicators, value == 'Default')
                    utils.event_callback('paint_ui', draw_sparkles_indicators, is_sparkles)

                    ref.scope_dim:set_visible(is_sparkles)
                    ref.scope_dim_alpha:set_visible(is_sparkles and ref.scope_dim:get())
                end

                local function on_offset(item)
                    y_offset = item:get() * 2
                end

                local function on_enabled(item)
                    local value = item:get()

                    if value then
                        ref.style:set_callback(on_style, true)
                        ref.offset:set_callback(on_offset, true)
                        ref.scope_dim:set_callback(on_scope_dim, true)
                    else
                        ref.style:unset_callback(on_style)
                        ref.offset:unset_callback(on_offset)
                        ref.scope_dim:unset_callback(on_scope_dim)
                    end

                    if not value then
                        utils.event_callback('paint_ui', draw_default_indicators, false)
                        utils.event_callback('paint_ui', draw_sparkles_indicators, false)
                        ref.scope_dim:set_visible(false)
                        ref.scope_dim_alpha:set_visible(false)
                    end
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end
        local defensive_bar do
            local ref = ref.visuals.defensive_bar

            local smooth_fill = 0.0
            local smooth_alpha = 0.0
            local smooth_label_alpha = 0.0
            local smooth_glow = 0.0
            local last_ticks = 0
            local last_max = 0
            local pulse_time = 0.0

            local function lerp_color(r1, g1, b1, r2, g2, b2, t)
                return
                    math.floor(r1 + (r2 - r1) * t),
                    math.floor(g1 + (g2 - g1) * t),
                    math.floor(b1 + (b2 - b1) * t)
            end

            local function get_fade_color(base_r, base_g, base_b, fill_pct)
                -- green -> yellow -> red as ticks deplete
                if fill_pct > 0.5 then
                    local t = (fill_pct - 0.5) / 0.5
                    return lerp_color(255, 220, 50, base_r, base_g, base_b, t)
                else
                    local t = fill_pct / 0.5
                    return lerp_color(255, 60, 60, 255, 220, 50, t)
                end
            end

            local function draw_bar(sx, sy)
                local bar_width = 130
                local bar_height = ref.height:get()
                local offset_y = ref.position_y:get()
                local use_glow = ref.glow:get()
                local use_segments = ref.segmented:get()
                local use_fade = ref.fade_color:get()

                local cr, cg, cb, ca = ref.color:get()

                local exp = exploit.get()
                local def = exp.defensive

                local is_active = def.left > 0
                local fill = def.max > 0 and (def.left / def.max) or 0

                if is_active then
                    last_ticks = def.left
                    last_max = def.max
                end

                smooth_fill = motion.interp(smooth_fill, fill, 0.1)
                smooth_alpha = motion.interp(smooth_alpha, is_active or ui.is_menu_open(), 0.06)
                smooth_label_alpha = motion.interp(smooth_label_alpha, is_active, 0.08)
                smooth_glow = motion.interp(smooth_glow, is_active, 0.05)

                if smooth_alpha < 0.01 then
                    return
                end

                pulse_time = pulse_time + globals.frametime()

                local alpha = smooth_alpha
                local cx = math.floor(sx / 2)
                local cy = math.floor(sy / 2) + offset_y
                local x = cx - math.floor(bar_width / 2)
                local y = cy

                -- fill color
                local fr, fg, fb = cr, cg, cb
                if use_fade then
                    fr, fg, fb = get_fade_color(cr, cg, cb, smooth_fill)
                end

                -- pulse
                local pulse = 0
                if is_active then
                    pulse = math.abs(math.sin(pulse_time * 3.0)) * 0.15
                end

                -- glow behind bar
                if use_glow and smooth_glow > 0.01 then
                    local glow_alpha = smooth_glow * (0.3 + pulse * 0.5)
                    local glow_expand = 6

                    -- vertical glow
                    renderer.gradient(
                        x - glow_expand, y - glow_expand, bar_width + glow_expand * 2, glow_expand,
                        fr, fg, fb, 0,
                        fr, fg, fb, math.floor(ca * alpha * glow_alpha * 0.5),
                        false
                    )
                    renderer.gradient(
                        x - glow_expand, y + bar_height, bar_width + glow_expand * 2, glow_expand,
                        fr, fg, fb, math.floor(ca * alpha * glow_alpha * 0.5),
                        fr, fg, fb, 0,
                        false
                    )

                        -- horizontal
                    renderer.gradient(
                        x - glow_expand, y, glow_expand, bar_height,
                        fr, fg, fb, 0,
                        fr, fg, fb, math.floor(ca * alpha * glow_alpha * 0.5),
                        true
                    )
                    renderer.gradient(
                        x + bar_width, y, glow_expand, bar_height,
                        fr, fg, fb, math.floor(ca * alpha * glow_alpha * 0.5),
                        fr, fg, fb, 0,
                        true
                    )
                end

                -- border
                renderer.rectangle(x - 1, y - 1, bar_width + 2, bar_height + 2, 0, 0, 0, math.floor(200 * alpha))

                -- bg
                renderer.rectangle(x, y, bar_width, bar_height, 20, 20, 20, math.floor(180 * alpha))

                -- fill
                local fill_width = math.floor(bar_width * smooth_fill)

                if fill_width > 0 then
                    if use_segments and last_max > 0 then
                        -- segmented fill
                        local seg_width = bar_width / last_max
                        local gap = 1
                        local filled_segs = math.ceil(smooth_fill * last_max)

                        for i = 0, filled_segs - 1 do
                            local seg_x = x + math.floor(i * seg_width)
                            local seg_w = math.floor(seg_width) - gap
                            if seg_w < 1 then seg_w = 1 end

                            -- fade per segment
                            local sr, sg, sb = fr, fg, fb
                            if use_fade then
                                local seg_pct = (i + 1) / last_max
                                sr, sg, sb = get_fade_color(cr, cg, cb, seg_pct)
                            end

                            local seg_alpha = math.floor(ca * alpha * (0.85 + pulse))

                            -- gradient fill
                            local half = math.floor(bar_height / 2)
                            if half > 0 then
                                renderer.gradient(
                                    seg_x, y, seg_w, half,
                                    math.min(255, sr + 40), math.min(255, sg + 40), math.min(255, sb + 40), seg_alpha,
                                    sr, sg, sb, seg_alpha,
                                    false
                                )
                                renderer.gradient(
                                    seg_x, y + half, seg_w, bar_height - half,
                                    sr, sg, sb, seg_alpha,
                                    math.floor(sr * 0.6), math.floor(sg * 0.6), math.floor(sb * 0.6), seg_alpha,
                                    false
                                )
                            end
                        end
                    else
                        -- solid fill
                        local fill_alpha = math.floor(ca * alpha * (0.85 + pulse))
                        local half = math.floor(bar_height / 2)

                        if half > 0 then
                            renderer.gradient(
                                x, y, fill_width, half,
                                math.min(255, fr + 40), math.min(255, fg + 40), math.min(255, fb + 40), fill_alpha,
                                fr, fg, fb, fill_alpha,
                                false
                            )
                            renderer.gradient(
                                x, y + half, fill_width, bar_height - half,
                                fr, fg, fb, fill_alpha,
                                math.floor(fr * 0.6), math.floor(fg * 0.6), math.floor(fb * 0.6), fill_alpha,
                                false
                            )
                        end

                        -- sweep
                        if is_active then
                            local sweep_period = 1.5
                            local sweep_t = (pulse_time % sweep_period) / sweep_period
                            local sweep_x = x + math.floor(fill_width * sweep_t)
                            local sweep_w = math.floor(fill_width * 0.15)

                            if sweep_w > 1 and sweep_x + sweep_w <= x + fill_width then
                                renderer.gradient(
                                    sweep_x, y, sweep_w, bar_height,
                                    255, 255, 255, 0,
                                    255, 255, 255, math.floor(35 * alpha),
                                    true
                                )
                                renderer.gradient(
                                    sweep_x + sweep_w, y, sweep_w, bar_height,
                                    255, 255, 255, math.floor(35 * alpha),
                                    255, 255, 255, 0,
                                    true
                                )
                            end
                        end
                    end
                end

                -- top highlight
                renderer.rectangle(x, y, bar_width, 1, 255, 255, 255, math.floor(15 * alpha))

                -- label
                local text_alpha = math.floor(255 * alpha * math.max(smooth_label_alpha, ui.is_menu_open() and 1 or 0))

                if text_alpha > 0 then
                    local label = string.format(
                        '\a%sDEFENSIVE',
                        last_ticks > 0 and utils.to_hex(fr, fg, fb, 255) or 'ffffffcc'
                    )

                    -- shadow
                    renderer.text(cx + 1, y - 13, 0, 0, 0, math.floor(text_alpha * 0.6), 'c-', nil, label)
                    renderer.text(cx, y - 14, 255, 255, 255, text_alpha, 'c-', nil, label)
                end
            end

            local function on_paint_ui()
                if not boot.done then return end

                local me = entity.get_local_player()
                if me == nil or not entity.is_alive(me) then
                    smooth_alpha = 0
                    smooth_label_alpha = 0
                    smooth_glow = 0
                    return
                end

                local sx, sy = client.screen_size()
                draw_bar(sx, sy)
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()
                    utils.event_callback('paint_ui', on_paint_ui, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end
        local cat_whiskers_visual do
            local custom_scope_ref = ref.visuals.custom_scope
            local ref = ref.visuals.cat_whiskers

            local smooth_alpha = 0.0
            local anim_time = 0.0

            local bezier_segments = 20

            local function bezier_point(p0x, p0y, p1x, p1y, p2x, p2y, t)
                local inv = 1 - t
                return inv * inv * p0x + 2 * inv * t * p1x + t * t * p2x,
                       inv * inv * p0y + 2 * inv * t * p1y + t * t * p2y
            end

            local function draw_curved_whisker(p0x, p0y, p1x, p1y, p2x, p2y, r, g, b, a)
                local prev_x, prev_y = p0x, p0y

                for i = 1, bezier_segments do
                    local t = i / bezier_segments
                    local nx, ny = bezier_point(p0x, p0y, p1x, p1y, p2x, p2y, t)

                    -- fade toward tip
                    local fade = 1 - t * t * 0.6
                    local seg_a = math.floor(a * fade)
                    if seg_a < 1 then seg_a = 1 end

                    local fpx, fpy = math.floor(prev_x), math.floor(prev_y)
                    local fnx, fny = math.floor(nx), math.floor(ny)

                    -- shadow
                    renderer.line(fpx, fpy + 1, fnx, fny + 1, 0, 0, 0, math.floor(seg_a * 0.15))

                    -- AA
                    local aa_a = math.floor(seg_a * 0.25 * fade)
                    if aa_a > 0 then
                        renderer.line(fpx, fpy - 1, fnx, fny - 1, r, g, b, aa_a)
                        renderer.line(fpx, fpy + 1, fnx, fny + 1, r, g, b, aa_a)
                    end

                    -- stroke
                    renderer.line(fpx, fpy, fnx, fny, r, g, b, seg_a)

                    prev_x, prev_y = nx, ny
                end
            end

            local function draw_curved_whisker_glow(p0x, p0y, p1x, p1y, p2x, p2y, r, g, b, a)
                local prev_x, prev_y = p0x, p0y

                for i = 1, bezier_segments do
                    local t = i / bezier_segments
                    local nx, ny = bezier_point(p0x, p0y, p1x, p1y, p2x, p2y, t)

                    local fpx, fpy = math.floor(prev_x), math.floor(prev_y)
                    local fnx, fny = math.floor(nx), math.floor(ny)

                    local fade = 1 - t * 0.5
                    for off = -3, 3 do
                        local dist = math.abs(off) / 3
                        local ga = math.floor(a * 0.04 * fade * (1 - dist * dist))
                        if ga > 0 then
                            renderer.line(fpx, fpy + off, fnx, fny + off, r, g, b, ga)
                        end
                    end

                    prev_x, prev_y = nx, ny
                end
            end

            -- whisker defs: angle, droop, phase
            local whisker_defs = {
                { angle = -0.38, droop = 0.18, phase = 0.0 },
                { angle = -0.02, droop = 0.28, phase = 0.7 },
                { angle =  0.32, droop = 0.22, phase = 1.4 },
            }

            local function draw_whiskers(sx, sy)
                local size = ref.size:get()
                local use_glow = ref.glow:get()
                local use_anim = ref.animate:get()

                local cr, cg, cb, ca = ref.color:get()

                smooth_alpha = motion.interp(smooth_alpha, 1, 0.08)

                if smooth_alpha < 0.01 then
                    return
                end

                anim_time = anim_time + globals.frametime()

                local alpha = smooth_alpha
                local cx = math.floor((sx - 1) / 2)
                local cy = math.floor((sy - 1) / 2)
                local gap = 5

                -- nose
                local nose_size = math.max(2, math.floor(size * 0.05))
                local nose_a = math.floor(ca * alpha)
                local nr, ng, nb = math.min(255, cr + 40), math.min(255, cg + 40), math.min(255, cb + 40)
                renderer.circle(math.floor(cx), math.floor(cy), nr, ng, nb, nose_a, nose_size, 0, 1.0)
                renderer.circle_outline(math.floor(cx), math.floor(cy), 0, 0, 0, math.floor(nose_a * 0.2), nose_size + 1, 0, 1.0, 1)

                -- hide when scoped w/ custom scope
                if custom_scope_ref.enabled:get() then
                    local me = entity.get_local_player()
                    if me and entity.get_prop(me, 'm_bIsScoped') == 1 then
                        return
                    end
                end

                -- whisker pairs
                for _, def in ipairs(whisker_defs) do
                    local sway = 0
                    if use_anim then
                        sway = math.sin(anim_time * 1.8 + def.phase) * 3
                    end

                    local base_a = math.floor(ca * alpha * (0.85 + math.abs(def.angle) * 0.4))
                    local droop_px = def.droop * size

                    -- right
                    local rx0 = cx + gap
                    local ry0 = cy + sway * 0.1
                    local rx_ctrl = cx + gap + math.cos(def.angle) * size * 0.55
                    local ry_ctrl = cy + math.sin(def.angle) * size * 0.35 + sway * 0.4
                    local rx_end = cx + gap + math.cos(def.angle) * size
                    local ry_end = cy + math.sin(def.angle) * size + droop_px + sway

                    if use_glow and alpha > 0.01 then
                        draw_curved_whisker_glow(rx0, ry0, rx_ctrl, ry_ctrl, rx_end, ry_end, cr, cg, cb, base_a)
                    end
                    draw_curved_whisker(rx0, ry0, rx_ctrl, ry_ctrl, rx_end, ry_end, cr, cg, cb, base_a)

                    -- left (mirrored)
                    local lx0 = cx - gap
                    local ly0 = ry0
                    local lx_ctrl = cx - gap - math.cos(def.angle) * size * 0.55
                    local ly_ctrl = ry_ctrl
                    local lx_end = cx - gap - math.cos(def.angle) * size
                    local ly_end = ry_end

                    if use_glow and alpha > 0.01 then
                        draw_curved_whisker_glow(lx0, ly0, lx_ctrl, ly_ctrl, lx_end, ly_end, cr, cg, cb, base_a)
                    end
                    draw_curved_whisker(lx0, ly0, lx_ctrl, ly_ctrl, lx_end, ly_end, cr, cg, cb, base_a)
                end
            end

            local function on_paint_ui()
                if not boot.done then return end

                local me = entity.get_local_player()
                if me == nil or not entity.is_alive(me) then
                    smooth_alpha = 0
                    return
                end

                local sx, sy = client.screen_size()
                draw_whiskers(sx, sy)
            end

            local callbacks do
                local crosshair_cvar = cvar.crosshair
                local saved_crosshair = nil

                local function on_enabled(item)
                    local value = item:get()
                    utils.event_callback('paint_ui', on_paint_ui, value)

                    if value then
                        saved_crosshair = crosshair_cvar:get_int()
                        crosshair_cvar:set_int(0)
                    elseif saved_crosshair ~= nil then
                        crosshair_cvar:set_int(saved_crosshair)
                        saved_crosshair = nil
                    end
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local debug_panel do
            local ref = ref.debug.debug_panel

            local DB_KEY = 'catboy#debug_panel_pos'
            local saved_pos = database.read(DB_KEY) or { }

            local panel_x = saved_pos.x or 300
            local panel_y = saved_pos.y or 300
            local smooth_px = panel_x
            local smooth_py = panel_y
            local panel_dragging = false
            local drag_offset_x, drag_offset_y = 0, 0
            local was_mouse_down = false
            local dim_panel_alpha = 0.0
            local smooth_w, smooth_h = nil, nil -- lazy-init on first frame
            local smooth_content_alpha = 1.0
            local prev_layout = nil
            local DP_SNAP = 15
            local dp_snap_cx, dp_snap_cy = false, false
            local dp_snap_left, dp_snap_right = false, false
            local dp_snap_top, dp_snap_bottom = false, false
            local dp_snap_cx_alpha, dp_snap_cy_alpha = 0.0, 0.0
            local dp_snap_w_alpha, dp_snap_h_alpha = 0.0, 0.0

            local smooth_lc = 0.0
            local smooth_peek = 0.0
            local smooth_vuln = 0.0
            local pulse_time = 0.0
            local smooth_alpha = 0.0
            local smooth_eye_yaw = 0.0
            local smooth_feet_yaw = 0.0
            local smooth_desync = 0.0

            -- shot markers on compass
            local shot_markers = { }
            local MAX_MARKERS = 8
            local MARKER_LIFETIME = 4.0

            -- gc tracking
            local GC_HISTORY_LEN = 120
            local GC_SAMPLE_INTERVAL = 0.05 -- ~20 samples/sec, 6s window
            local gc_history = { }
            local gc_mem_prev = collectgarbage('count')
            local gc_alloc_rate = 0.0
            local gc_smooth_alloc = 0.0
            local gc_cycles = 0
            local gc_last_cycle_time = 0
            local gc_cycle_flash = 0.0
            local gc_mem_peak = gc_mem_prev
            local gc_mem_min = gc_mem_prev
            local gc_sample_accum = 0.0
            local gc_alloc_accum = 0.0
            local gc_alloc_time = 0.0
            for i = 1, GC_HISTORY_LEN do gc_history[i] = gc_mem_prev end

            -- persists when target is lost
            local frozen = {
                eye_yaw = 0,
                feet_yaw = 0,
                side = 0,
                desync = 0,
                max_desync = 58,
                target = '?',
                using_gs = false,
                has_data = false,
            }
            local smooth_active = 0.0

            local function save_panel_pos()
                database.write(DB_KEY, { x = panel_x, y = panel_y })
            end

            local function draw_status_row(px, py, w, label, value_text, smooth_val, pulse_val, ar, ag, ab, alpha)
                local idle_r, idle_g, idle_b = 60, 60, 70

                -- dot
                local dot_r = math.floor(idle_r + (ar - idle_r) * smooth_val)
                local dot_g = math.floor(idle_g + (ag - idle_g) * smooth_val)
                local dot_b = math.floor(idle_b + (ab - idle_b) * smooth_val)

                if smooth_val < 0.5 then
                    dot_r, dot_g, dot_b = idle_r, idle_g, idle_b
                end

                -- glow
                if smooth_val > 0.01 then
                    local ga = math.floor(30 * smooth_val * alpha * (0.8 + pulse_val))
                    renderer.rectangle(px - 2, py - 1, 7, 7, dot_r, dot_g, dot_b, ga)
                end

                renderer.rectangle(px, py + 1, 3, 3, dot_r, dot_g, dot_b, math.floor(220 * alpha))

                renderer.text(px + 8, py - 1, 120, 120, 130, math.floor(200 * alpha), '', nil, label)

                -- value
                local vr = math.floor(idle_r + (ar - idle_r) * smooth_val)
                local vg = math.floor(idle_g + (ag - idle_g) * smooth_val)
                local vb = math.floor(idle_b + (ab - idle_b) * smooth_val)

                local tw = renderer.measure_text('', value_text)
                renderer.text(px + w - tw, py - 1, vr, vg, vb, math.floor(220 * alpha * (0.85 + pulse_val * 0.15)), '', nil, value_text)

                return 14
            end

            local function draw_info_row(px, py, w, label, value_text, alpha)
                renderer.text(px, py, 90, 90, 100, math.floor(160 * alpha), '', nil, label)
                local tw = renderer.measure_text('', value_text)
                renderer.text(px + w - tw, py, 160, 160, 170, math.floor(200 * alpha), '', nil, value_text)
                return 13
            end

            local function draw_yaw_compass(cx_pos, cy_pos, radius, eye_yaw, feet_yaw, desync_pct, ar, ag, ab, alpha, local_yaw)
                -- 12 o'clock = local view dir, negate yaw for screen coords
                local ref = local_yaw or 0

                -- bg circle
                local segments = 32
                for i = 0, segments - 1 do
                    local a1 = (i / segments) * math.pi * 2
                    local a2 = ((i + 1) / segments) * math.pi * 2
                    local x1 = cx_pos + math.floor(math.sin(a1) * radius)
                    local y1 = cy_pos - math.floor(math.cos(a1) * radius)
                    local x2 = cx_pos + math.floor(math.sin(a2) * radius)
                    local y2 = cy_pos - math.floor(math.cos(a2) * radius)
                    renderer.line(x1, y1, x2, y2, 40, 40, 50, math.floor(100 * alpha))
                end

                -- tick marks
                for i = 0, 3 do
                    local ang = (i / 4) * math.pi * 2
                    local inner = radius - 3
                    local outer = radius + 2
                    local ix = cx_pos + math.floor(math.sin(ang) * inner)
                    local iy = cy_pos - math.floor(math.cos(ang) * inner)
                    local ox = cx_pos + math.floor(math.sin(ang) * outer)
                    local oy = cy_pos - math.floor(math.cos(ang) * outer)
                    local tr, tg, tb = 70, 70, 80
                    if i == 0 then tr, tg, tb = 100, 100, 110 end
                    renderer.line(ix, iy, ox, oy, tr, tg, tb, math.floor(150 * alpha))
                end

                -- enemy yaws (screen space)
                local eye_screen = math.rad(-(eye_yaw - ref))
                local feet_screen = math.rad(-(feet_yaw - ref))

                -- desync arc
                local arc_radius = radius - 5
                local diff = feet_yaw - eye_yaw
                while diff > 180 do diff = diff - 360 end
                while diff < -180 do diff = diff + 360 end

                local arc_steps = math.max(math.floor(math.abs(diff) / 5), 2)
                local step_angle = -diff / arc_steps -- negate for screen

                for i = 0, arc_steps - 1 do
                    local a1 = eye_screen + math.rad(step_angle * i)
                    local a2 = eye_screen + math.rad(step_angle * (i + 1))
                    local x1 = cx_pos + math.floor(math.sin(a1) * arc_radius)
                    local y1 = cy_pos - math.floor(math.cos(a1) * arc_radius)
                    local x2 = cx_pos + math.floor(math.sin(a2) * arc_radius)
                    local y2 = cy_pos - math.floor(math.cos(a2) * arc_radius)

                    local arc_a = math.floor(60 * desync_pct * alpha)
                    renderer.line(x1, y1, x2, y2, ar, ag, ab, arc_a)
                end

                -- eye yaw
                local eye_len = radius - 2
                local ex = cx_pos + math.floor(math.sin(eye_screen) * eye_len)
                local ey = cy_pos - math.floor(math.cos(eye_screen) * eye_len)
                renderer.line(cx_pos, cy_pos, ex, ey, ar, ag, ab, math.floor(200 * alpha))
                renderer.rectangle(ex - 1, ey - 1, 3, 3, ar, ag, ab, math.floor(220 * alpha))

                -- feet yaw
                local feet_len = radius - 4
                local fx = cx_pos + math.floor(math.sin(feet_screen) * feet_len)
                local fy = cy_pos - math.floor(math.cos(feet_screen) * feet_len)
                renderer.line(cx_pos, cy_pos, fx, fy, 180, 180, 200, math.floor(140 * alpha))

                renderer.rectangle(cx_pos - 1, cy_pos - 1, 3, 3, 80, 80, 90, math.floor(200 * alpha))
            end

            local function on_paint_ui()
                if not boot.done then return end

                local me = entity.get_local_player()
                local is_alive = me ~= nil and entity.is_alive(me)

                smooth_alpha = motion.interp(smooth_alpha, true, 0.08)

                if smooth_alpha < 0.01 then
                    return
                end

                -- gather data
                local info = debug_panel_info
                local is_lc = is_alive and info.breaking_lc or false
                local is_peeking = is_alive and localplayer.is_peeking or false
                local is_vulnerable = is_alive and localplayer.is_vulnerable or false
                local ft = globals.frametime()

                -- resolver data
                local has_target = is_alive and info.resolver_active or false
                local using_gs = false

                -- fallback: read GS resolver via FFI
                if is_alive and not has_target and info.get_gs_resolver then
                    local gs = info.get_gs_resolver()
                    if gs then
                        has_target = true
                        using_gs = true
                        info.resolver_target = gs.target
                        info.resolver_eye_yaw = gs.eye_yaw
                        info.resolver_feet_yaw = gs.feet_yaw
                        info.resolver_side = gs.side
                        info.resolver_desync = gs.desync
                        info.resolver_max_desync = gs.max_desync
                    end
                end

                -- freeze state when target is live
                if has_target then
                    frozen.eye_yaw = info.resolver_eye_yaw or 0
                    frozen.feet_yaw = info.resolver_feet_yaw or 0
                    frozen.side = info.resolver_side or 0
                    frozen.desync = info.resolver_desync or 0
                    frozen.max_desync = info.resolver_max_desync or 58
                    frozen.target = info.resolver_target or '?'
                    frozen.using_gs = using_gs
                    frozen.has_data = true
                end

                -- read from frozen
                local eye_yaw = frozen.eye_yaw
                local feet_yaw = frozen.feet_yaw
                local r_side = frozen.side
                local r_desync = frozen.desync
                local r_max_desync = frozen.max_desync
                local r_target = frozen.target

                smooth_active = motion.interp(smooth_active, has_target, 0.08)

                if has_target then
                    smooth_eye_yaw = eye_yaw
                    smooth_feet_yaw = feet_yaw
                    smooth_desync = r_desync
                end

                smooth_lc = motion.interp(smooth_lc, is_lc, 0.1)
                smooth_peek = motion.interp(smooth_peek, is_peeking, 0.1)
                smooth_vuln = motion.interp(smooth_vuln, is_vulnerable, 0.1)
                pulse_time = pulse_time + ft

                -- gc tracking
                if ref.gc_monitor:get() then
                    local gc_mem_now = collectgarbage('count')
                    local gc_delta = gc_mem_now - gc_mem_prev

                    -- detect gc cycle
                    if gc_delta < -5 then
                        gc_cycles = gc_cycles + 1
                        gc_last_cycle_time = globals.realtime()
                        gc_cycle_flash = 1.0
                    end

                    if gc_delta > 0 then
                        gc_alloc_accum = gc_alloc_accum + gc_delta
                    end
                    gc_alloc_time = gc_alloc_time + ft

                    -- flash decay
                    gc_cycle_flash = math.max(0, gc_cycle_flash - ft * 1.5)

                    -- fixed-interval sampling
                    gc_sample_accum = gc_sample_accum + ft
                    if gc_sample_accum >= GC_SAMPLE_INTERVAL then
                        gc_sample_accum = gc_sample_accum - GC_SAMPLE_INTERVAL

                        -- alloc rate
                        if gc_alloc_time > 0 then
                            gc_alloc_rate = gc_alloc_accum / gc_alloc_time
                        end
                        gc_alloc_accum = 0.0
                        gc_alloc_time = 0.0

                        table.remove(gc_history, 1)
                        gc_history[GC_HISTORY_LEN] = gc_mem_now

                        -- update peak/min
                        gc_mem_peak = 0
                        gc_mem_min = math.huge
                        for i = 1, GC_HISTORY_LEN do
                            if gc_history[i] > gc_mem_peak then gc_mem_peak = gc_history[i] end
                            if gc_history[i] < gc_mem_min then gc_mem_min = gc_history[i] end
                        end
                    end

                    -- smooth alloc rate
                    local gc_lerp_speed = 1 - math.pow(1 - 0.08, ft / 0.0166)
                    gc_smooth_alloc = gc_smooth_alloc + (gc_alloc_rate - gc_smooth_alloc) * gc_lerp_speed

                    gc_mem_prev = gc_mem_now
                end

                local pulse = math.abs(math.sin(pulse_time * 3.0)) * 0.3

                local ar, ag, ab = ref.color:get()

                -- layout
                local is_horizontal = ref.layout:get() == 'Horizontal'
                local title_h = 20
                local row_h = 14
                local padding = 8
                local compass_size = 60
                local compass_h = compass_size + 28
                local rows = 3
                local info_rows = 5
                local gc_enabled = ref.gc_monitor:get()
                local gc_graph_h = 28
                local gc_rows = 3
                local gc_section_h = gc_enabled and (12 + (row_h * gc_rows) + 6 + gc_graph_h + 6) or 0

                local target_w, target_h
                if is_horizontal then
                    -- horizontal layout
                    local col_status_w = 140
                    local col_compass_w = compass_size + 20
                    local col_info_w = 155
                    local col_gc_w = gc_enabled and 155 or 0
                    local col_gap = 12
                    local num_cols = gc_enabled and 4 or 3
                    target_w = padding + col_status_w + col_gap + col_compass_w + col_gap + col_info_w + (gc_enabled and (col_gap + col_gc_w) or 0) + padding
                    local max_col_h = math.max(
                        row_h * rows,
                        compass_h,
                        row_h * (info_rows + 1),
                        gc_enabled and (row_h * gc_rows + 6 + gc_graph_h + row_h) or 0
                    )
                    target_h = title_h + padding + max_col_h + padding
                else
                    target_w = 185
                    local body_h = padding + (row_h * rows) + 12 + compass_h + 12 + (row_h * info_rows) + gc_section_h + padding
                    target_h = title_h + body_h
                end

                -- smooth dimensions
                if smooth_w == nil then smooth_w = target_w end
                if smooth_h == nil then smooth_h = target_h end

                local current_layout = ref.layout:get()
                if prev_layout ~= nil and prev_layout ~= current_layout then
                    smooth_content_alpha = 0.0
                end
                prev_layout = current_layout

                local dim_lerp = 1 - math.pow(1 - 0.12, globals.frametime() / (1 / 60))
                smooth_w = smooth_w + (target_w - smooth_w) * dim_lerp
                smooth_h = smooth_h + (target_h - smooth_h) * dim_lerp

                local content_lerp = 1 - math.pow(1 - 0.08, globals.frametime() / (1 / 60))
                smooth_content_alpha = smooth_content_alpha + (1.0 - smooth_content_alpha) * content_lerp

                local w = math.floor(smooth_w)
                local h = math.floor(smooth_h)

                local alpha = smooth_alpha

                -- dragging
                local is_menu = ui.is_menu_open()

                if is_menu then
                    local mouse_x, mouse_y = ui.mouse_position()
                    local mouse_down = client.key_state(0x01)

                    -- hit test
                    local hit_x = math.floor(smooth_px)
                    local hit_y = math.floor(smooth_py)

                    if mouse_down and not was_mouse_down then
                        if mouse_x >= hit_x and mouse_x <= hit_x + w
                            and mouse_y >= hit_y and mouse_y <= hit_y + title_h then
                            panel_dragging = true
                            drag_offset_x = mouse_x - hit_x
                            drag_offset_y = mouse_y - hit_y
                        end
                    end

                    if not mouse_down then
                        if panel_dragging then save_panel_pos() end
                        panel_dragging = false
                    end

                    if panel_dragging then
                        local screen_w, screen_h = client.screen_size()
                        local new_x = mouse_x - drag_offset_x
                        local new_y = mouse_y - drag_offset_y

                        dp_snap_cx, dp_snap_cy = false, false
                        dp_snap_left, dp_snap_right = false, false
                        dp_snap_top, dp_snap_bottom = false, false

                        -- center snap
                        local center_x = math.floor(screen_w * 0.5 - target_w * 0.5)
                        if math.abs(new_x - center_x) < DP_SNAP then
                            new_x = center_x
                            dp_snap_cx = true
                        end

                        -- edge snap x
                        if math.abs(new_x) < DP_SNAP then
                            new_x = 0
                            dp_snap_cx = false
                            dp_snap_left = true
                        elseif math.abs(new_x - (screen_w - target_w)) < DP_SNAP then
                            new_x = screen_w - target_w
                            dp_snap_cx = false
                            dp_snap_right = true
                        end

                        -- center snap y
                        local center_y = math.floor(screen_h * 0.5 - target_h * 0.5)
                        if math.abs(new_y - center_y) < DP_SNAP then
                            new_y = center_y
                            dp_snap_cy = true
                        end

                        -- edge snap y
                        if math.abs(new_y) < DP_SNAP then
                            new_y = 0
                            dp_snap_cy = false
                            dp_snap_top = true
                        elseif math.abs(new_y - (screen_h - target_h)) < DP_SNAP then
                            new_y = screen_h - target_h
                            dp_snap_cy = false
                            dp_snap_bottom = true
                        end

                        panel_x = new_x
                        panel_y = new_y
                    end

                    was_mouse_down = mouse_down
                else
                    panel_dragging = false
                    was_mouse_down = false
                end

                debug_panel_info.dragging = panel_dragging
                debug_panel_info.dragging_panel = panel_dragging

                -- hover detection
                local hover_pad = 6
                if is_menu then
                    local mx, my = ui.mouse_position()
                    local hx, hy = math.floor(smooth_px), math.floor(smooth_py)
                    debug_panel_info.hovering_panel = mx >= hx - hover_pad and mx <= hx + w + hover_pad and my >= hy - hover_pad and my <= hy + h + hover_pad
                else
                    debug_panel_info.hovering_panel = false
                end

                -- smooth position
                local base_speed = panel_dragging and 0.35 or 0.15
                local lerp_speed = 1 - math.pow(1 - base_speed, globals.frametime() / (1 / 60))
                smooth_px = smooth_px + (panel_x - smooth_px) * lerp_speed
                smooth_py = smooth_py + (panel_y - smooth_py) * lerp_speed

                -- dim overlay
                dim_panel_alpha = dim_panel_alpha + ((panel_dragging and 1 or 0) - dim_panel_alpha) * (1 - math.pow(1 - 0.1, globals.frametime() / (1 / 60)))
                if dim_panel_alpha > 0.01 then
                    local screen_w, screen_h = client.screen_size()
                    renderer.rectangle(0, 0, screen_w, screen_h, 0, 0, 0, math.floor(60 * dim_panel_alpha * alpha))
                end

                -- snap guides
                local snap_lerp = 1 - math.pow(1 - 0.15, globals.frametime() / (1 / 60))
                dp_snap_cx_alpha = dp_snap_cx_alpha + ((panel_dragging and dp_snap_cx and 1 or 0) - dp_snap_cx_alpha) * snap_lerp
                dp_snap_cy_alpha = dp_snap_cy_alpha + ((panel_dragging and dp_snap_cy and 1 or 0) - dp_snap_cy_alpha) * snap_lerp
                dp_snap_w_alpha = dp_snap_w_alpha + ((panel_dragging and (dp_snap_left or dp_snap_right) and 1 or 0) - dp_snap_w_alpha) * snap_lerp
                dp_snap_h_alpha = dp_snap_h_alpha + ((panel_dragging and (dp_snap_top or dp_snap_bottom) and 1 or 0) - dp_snap_h_alpha) * snap_lerp

                local px, py = math.floor(smooth_px), math.floor(smooth_py)

                -- snap lines
                do
                    local screen_w, screen_h = client.screen_size()
                    if dp_snap_cx_alpha > 0.01 then
                        local cx = math.floor(screen_w * 0.5)
                        local sa = math.floor(120 * dp_snap_cx_alpha * alpha)
                        renderer.rectangle(cx, py - 12, 1, h + 24, ar, ag, ab, sa)
                    end
                    if dp_snap_cy_alpha > 0.01 then
                        local cy = math.floor(screen_h * 0.5)
                        local sa = math.floor(120 * dp_snap_cy_alpha * alpha)
                        renderer.rectangle(px - 12, cy, w + 24, 1, ar, ag, ab, sa)
                    end
                    if dp_snap_w_alpha > 0.01 then
                        local sa = math.floor(120 * dp_snap_w_alpha * alpha)
                        if dp_snap_left then
                            renderer.rectangle(0, py - 12, 1, h + 24, ar, ag, ab, sa)
                        elseif dp_snap_right then
                            renderer.rectangle(screen_w - 1, py - 12, 1, h + 24, ar, ag, ab, sa)
                        end
                    end
                    if dp_snap_h_alpha > 0.01 then
                        local sa = math.floor(120 * dp_snap_h_alpha * alpha)
                        if dp_snap_top then
                            renderer.rectangle(px - 12, 0, w + 24, 1, ar, ag, ab, sa)
                        elseif dp_snap_bottom then
                            renderer.rectangle(px - 12, screen_h - 1, w + 24, 1, ar, ag, ab, sa)
                        end
                    end
                end

                -- shadow
                renderer.rectangle(px + 3, py + 3, w, h, 0, 0, 0, math.floor(30 * alpha))
                renderer.rectangle(px + 2, py + 2, w, h, 0, 0, 0, math.floor(40 * alpha))

                -- bg
                renderer.gradient(
                    px, py, w, h,
                    14, 14, 18, math.floor(235 * alpha),
                    10, 10, 14, math.floor(235 * alpha),
                    false
                )

                -- accent
                renderer.gradient(
                    px, py, math.floor(w * 0.5), 1,
                    ar, ag, ab, 0,
                    ar, ag, ab, math.floor(180 * alpha),
                    true
                )
                renderer.gradient(
                    px + math.floor(w * 0.5), py, math.floor(w * 0.5), 1,
                    ar, ag, ab, math.floor(180 * alpha),
                    ar, ag, ab, 0,
                    true
                )

                -- title bg
                renderer.gradient(
                    px, py + 1, w, title_h - 1,
                    math.floor(20 + ar * 0.08), math.floor(18 + ag * 0.08), math.floor(22 + ab * 0.08), math.floor(240 * alpha),
                    14, 14, 18, math.floor(240 * alpha),
                    false
                )

                local title = 'catboy  ·  debug'
                local ttw = renderer.measure_text('', title)
                renderer.text(px + math.floor((w - ttw) * 0.5) + 1, py + 5, 0, 0, 0, math.floor(60 * alpha), '', nil, title)
                renderer.text(px + math.floor((w - ttw) * 0.5), py + 4, ar, ag, ab, math.floor(220 * alpha), '', nil, title)

                -- separator
                renderer.rectangle(px + 8, py + title_h, w - 16, 1, 40, 40, 50, math.floor(120 * alpha))

                -- border
                local border_a = math.floor((50 + 30 * (panel_dragging and 1 or 0)) * alpha)
                renderer.rectangle(px, py, w, 1, 50, 50, 60, border_a)
                renderer.rectangle(px, py + h - 1, w, 1, 30, 30, 40, border_a)
                renderer.rectangle(px, py, 1, h, 40, 40, 50, border_a)
                renderer.rectangle(px + w - 1, py, 1, h, 40, 40, 50, border_a)

                -- body
                alpha = alpha * smooth_content_alpha
                local cx = px + 10
                local cy = py + title_h + padding
                local content_w = w - 20

                -- status data
                local lc_text = is_lc and 'breaking' or 'idle'
                local peek_text = is_peeking and 'yes' or 'no'
                local vuln_text = is_vulnerable and 'exposed' or 'safe'
                local vuln_r = math.floor(255 * smooth_vuln + 60 * (1 - smooth_vuln))
                local vuln_g = math.floor(80 * smooth_vuln + 60 * (1 - smooth_vuln))
                local vuln_b = math.floor(80 * smooth_vuln + 70 * (1 - smooth_vuln))
                local af = frozen.has_data and (0.35 + smooth_active * 0.65) or 1
                local desync_pct = frozen.has_data and math.min(smooth_desync / r_max_desync, 1) or 0
                local c_ar = math.floor(ar * smooth_active + 70 * (1 - smooth_active))
                local c_ag = math.floor(ag * smooth_active + 70 * (1 - smooth_active))
                local c_ab = math.floor(ab * smooth_active + 80 * (1 - smooth_active))
                local _, my_yaw = client.camera_angles()

                -- shot markers
                local function draw_shot_markers_at(compass_cx_pos, compass_cy_pos, compass_r)
                    local now = globals.realtime()
                    local i = 1
                    while i <= #shot_markers do
                        local m = shot_markers[i]
                        local age = now - m.time

                        if age > MARKER_LIFETIME then
                            table.remove(shot_markers, i)
                        else
                            local fade = 1.0 - (age / MARKER_LIFETIME)
                            fade = fade * fade
                            local ma = math.floor(220 * fade * alpha)

                            if ma > 0 then
                                local rad = math.rad(-(m.yaw - my_yaw))
                                local marker_r = compass_r + 4
                                local mx_pos = compass_cx_pos + math.floor(math.sin(rad) * marker_r)
                                local my_pos = compass_cy_pos - math.floor(math.cos(rad) * marker_r)

                                if m.hit then
                                    local hr, hg, hb = 80, 220, 80
                                    renderer.rectangle(mx_pos - 1, my_pos - 3, 2, 6, hr, hg, hb, ma)
                                    renderer.rectangle(mx_pos - 3, my_pos - 1, 6, 2, hr, hg, hb, ma)
                                    renderer.rectangle(mx_pos - 2, my_pos - 4, 4, 8, hr, hg, hb, math.floor(ma * 0.15))
                                else
                                    local mr, mg, mb = 255, 70, 70
                                    renderer.line(mx_pos - 2, my_pos - 2, mx_pos + 3, my_pos + 3, mr, mg, mb, ma)
                                    renderer.line(mx_pos + 2, my_pos - 2, mx_pos - 3, my_pos + 3, mr, mg, mb, ma)
                                    renderer.rectangle(mx_pos - 3, my_pos - 3, 6, 6, mr, mg, mb, math.floor(ma * 0.12))
                                end
                            end

                            i = i + 1
                        end
                    end
                end

                -- helper: draw gc section at given position/width, returns height used
                local function draw_gc_section(gx, gy, gw)
                    local gc_cy = gy

                    -- gc header
                    local gc_header = 'garbage collector'
                    renderer.text(gx, gc_cy, ar, ag, ab, math.floor(160 * alpha), '', nil, gc_header)

                    local cycle_text = gc_cycles .. ' cycles'
                    local ctw = renderer.measure_text('', cycle_text)
                    local flash_r = math.floor(60 + (ar - 60) * gc_cycle_flash)
                    local flash_g = math.floor(60 + (ag - 60) * gc_cycle_flash)
                    local flash_b = math.floor(70 + (ab - 70) * gc_cycle_flash)
                    renderer.text(gx + gw - ctw, gc_cy, flash_r, flash_g, flash_b, math.floor((140 + 80 * gc_cycle_flash) * alpha), '', nil, cycle_text)
                    gc_cy = gc_cy + row_h

                    local gc_mem_now_kb = gc_history[GC_HISTORY_LEN]
                    local mem_text
                    if gc_mem_now_kb >= 1024 then
                        mem_text = string.format('%.1f MB', gc_mem_now_kb / 1024)
                    else
                        mem_text = string.format('%.0f KB', gc_mem_now_kb)
                    end
                    gc_cy = gc_cy + draw_info_row(gx, gc_cy, gw, 'memory', mem_text, alpha)

                    local alloc_text
                    if gc_smooth_alloc >= 1024 then
                        alloc_text = string.format('%.1f MB/s', gc_smooth_alloc / 1024)
                    else
                        alloc_text = string.format('%.0f KB/s', gc_smooth_alloc)
                    end
                    gc_cy = gc_cy + draw_info_row(gx, gc_cy, gw, 'alloc rate', alloc_text, alpha)

                    gc_cy = gc_cy + 3
                    local graph_x = gx
                    local graph_y = gc_cy
                    local graph_w = gw
                    local graph_h = gc_graph_h

                    renderer.rectangle(graph_x, graph_y, graph_w, graph_h, 8, 8, 12, math.floor(180 * alpha))
                    renderer.rectangle(graph_x, graph_y, graph_w, 1, 30, 30, 40, math.floor(60 * alpha))
                    renderer.rectangle(graph_x, graph_y + graph_h - 1, graph_w, 1, 20, 20, 28, math.floor(40 * alpha))

                    local gc_range = gc_mem_peak - gc_mem_min
                    if gc_range < 10 then gc_range = 10 end
                    local gc_floor = gc_mem_min - gc_range * 0.1
                    local gc_ceil = gc_mem_peak + gc_range * 0.1
                    local gc_span = gc_ceil - gc_floor

                    local step_w = graph_w / (GC_HISTORY_LEN - 1)
                    local prev_sx, prev_sy

                    for i = 1, GC_HISTORY_LEN do
                        local val = gc_history[i]
                        local norm = (val - gc_floor) / gc_span
                        norm = math.max(0, math.min(1, norm))

                        local sx = graph_x + math.floor((i - 1) * step_w)
                        local sy = graph_y + graph_h - 1 - math.floor(norm * (graph_h - 2))

                        local fill_h = graph_y + graph_h - sy
                        if fill_h > 0 then
                            local fill_a = math.floor(25 * alpha)
                            renderer.gradient(
                                sx, sy, math.max(1, math.floor(step_w) + 1), fill_h,
                                ar, ag, ab, fill_a,
                                ar, ag, ab, math.floor(5 * alpha),
                                false
                            )
                        end

                        if prev_sx then
                            renderer.line(prev_sx, prev_sy, sx, sy, ar, ag, ab, math.floor(180 * alpha))
                        end

                        prev_sx, prev_sy = sx, sy
                    end

                    if prev_sx then
                        renderer.rectangle(prev_sx - 1, prev_sy - 1, 3, 3, ar, ag, ab, math.floor(220 * alpha))
                        renderer.rectangle(prev_sx - 3, prev_sy - 3, 7, 7, ar, ag, ab, math.floor(30 * alpha))
                    end

                    for i = 2, GC_HISTORY_LEN do
                        local drop = gc_history[i - 1] - gc_history[i]
                        if drop > 5 then
                            local sx = graph_x + math.floor((i - 1) * step_w)
                            renderer.rectangle(sx, graph_y, 1, graph_h, 255, 100, 100, math.floor(60 * alpha))
                        end
                    end

                    local top_label = gc_ceil >= 1024 and string.format('%.1fM', gc_ceil / 1024) or string.format('%.0fK', gc_ceil)
                    local bot_label = gc_floor >= 1024 and string.format('%.1fM', gc_floor / 1024) or string.format('%.0fK', gc_floor)
                    renderer.text(graph_x + 2, graph_y + 1, 80, 80, 90, math.floor(100 * alpha), '', nil, top_label)
                    renderer.text(graph_x + 2, graph_y + graph_h - 10, 80, 80, 90, math.floor(100 * alpha), '', nil, bot_label)

                    return (gc_cy - gy) + graph_h + 3
                end

                if is_horizontal then
                    -- horizontal
                    local col_gap = 12
                    local col_status_w = 140
                    local col_compass_w = compass_size + 20
                    local col_info_w = 155
                    local col_gc_w = 155

                    -- col 1: status
                    local col1_x = cx
                    local col1_y = cy
                    col1_y = col1_y + draw_status_row(col1_x, col1_y, col_status_w, 'breaking lc', lc_text, smooth_lc, pulse * smooth_lc, ar, ag, ab, alpha)
                    col1_y = col1_y + draw_status_row(col1_x, col1_y, col_status_w, 'peeking', peek_text, smooth_peek, pulse * smooth_peek, ar, ag, ab, alpha)
                    col1_y = col1_y + draw_status_row(col1_x, col1_y, col_status_w, 'vulnerable', vuln_text, smooth_vuln, pulse * smooth_vuln, vuln_r, vuln_g, vuln_b, alpha)

                    -- col 2: compass
                    local col2_x = col1_x + col_status_w + col_gap
                    local compass_cx_pos = col2_x + math.floor(col_compass_w * 0.5)
                    local compass_cy_pos = cy + math.floor(compass_size * 0.5)
                    local compass_r = math.floor(compass_size * 0.5)

                    if frozen.has_data then
                        draw_yaw_compass(compass_cx_pos, compass_cy_pos, compass_r, smooth_eye_yaw, smooth_feet_yaw, desync_pct, c_ar, c_ag, c_ab, alpha * af, my_yaw)
                        draw_shot_markers_at(compass_cx_pos, compass_cy_pos, compass_r)

                        -- legend
                        local legend_y = cy + compass_size + 4
                        renderer.rectangle(col2_x + 2, legend_y + 4, 8, 2, c_ar, c_ag, c_ab, math.floor(200 * alpha * af))
                        renderer.text(col2_x + 14, legend_y, 110, 110, 120, math.floor(160 * alpha * af), '', nil, 'eye')
                        local feet_lx = col2_x + col_compass_w - 32
                        renderer.rectangle(feet_lx, legend_y + 4, 8, 2, math.floor(180 * af), math.floor(180 * af), math.floor(200 * af), math.floor(140 * alpha * af))
                        renderer.text(feet_lx + 12, legend_y, 110, 110, 120, math.floor(160 * alpha * af), '', nil, 'feet')

                        local desync_str = string.format('%d°', math.floor(smooth_desync))
                        local dw = renderer.measure_text('', desync_str)
                        renderer.text(compass_cx_pos - math.floor(dw * 0.5), legend_y + 12, c_ar, c_ag, c_ab, math.floor(180 * alpha * af * (0.7 + desync_pct * 0.3)), '', nil, desync_str)
                    else
                        local no_text = 'no target'
                        local ntw = renderer.measure_text('', no_text)
                        renderer.text(compass_cx_pos - math.floor(ntw * 0.5), compass_cy_pos - 4, 60, 60, 70, math.floor(120 * alpha), '', nil, no_text)
                    end

                    -- col 3: resolver info
                    local col3_x = col2_x + col_compass_w + col_gap
                    local col3_y = cy

                    if frozen.has_data then
                        local info_alpha = alpha * af

                        local name_trunc = #r_target > 14 and r_target:sub(1, 13) .. '..' or r_target
                        local status_suffix = has_target and '' or '  (lost)'
                        local name_display = name_trunc .. status_suffix
                        renderer.text(col3_x, col3_y, 90, 90, 100, math.floor(140 * info_alpha), '', nil, 'target:')
                        local ntw = renderer.measure_text('', name_display)
                        local name_r = math.floor(200 * af + 60 * (1 - af))
                        local name_g = math.floor(200 * af + 60 * (1 - af))
                        local name_b = math.floor(210 * af + 70 * (1 - af))
                        renderer.text(col3_x + col_info_w - ntw, col3_y, name_r, name_g, name_b, math.floor(200 * info_alpha), '', nil, name_display)
                        col3_y = col3_y + row_h

                        local source_text = frozen.using_gs and 'gamesense' or (debug_panel_info.resolver_mode == 'desync resolver' and 'desync resolver' or 'kittysolver >w<')
                        local src_r = frozen.using_gs and 140 or math.floor(ar * 0.7 + 90 * 0.3)
                        local src_g = frozen.using_gs and 140 or math.floor(ag * 0.7 + 90 * 0.3)
                        local src_b = frozen.using_gs and 150 or math.floor(ab * 0.7 + 100 * 0.3)
                        renderer.text(col3_x, col3_y, 90, 90, 100, math.floor(140 * info_alpha), '', nil, 'resolver:')
                        local stw = renderer.measure_text('', source_text)
                        renderer.text(col3_x + col_info_w - stw, col3_y, src_r, src_g, src_b, math.floor(200 * info_alpha), '', nil, source_text)
                        col3_y = col3_y + row_h

                        local side_text = r_side > 0 and 'right' or (r_side < 0 and 'left' or 'center')
                        col3_y = col3_y + draw_info_row(col3_x, col3_y, col_info_w, 'resolved side', side_text, info_alpha)

                        local desync_text = string.format('%d°', math.floor(r_desync))
                        col3_y = col3_y + draw_info_row(col3_x, col3_y, col_info_w, 'desync', desync_text, info_alpha)

                        local max_text = string.format('%d°', math.floor(r_max_desync))
                        col3_y = col3_y + draw_info_row(col3_x, col3_y, col_info_w, 'max desync', max_text, info_alpha)

                        local eye_text = string.format('%d°', math.floor(smooth_eye_yaw) % 360)
                        local feet_text = string.format('%d°', math.floor(smooth_feet_yaw) % 360)
                        col3_y = col3_y + draw_info_row(col3_x, col3_y, col_info_w, 'eye / feet', eye_text .. '  ' .. feet_text, info_alpha)
                    end

                    -- col 4: gc monitor
                    if gc_enabled then
                        local col4_x = col3_x + col_info_w + col_gap
                        renderer.rectangle(col4_x - math.floor(col_gap * 0.5), cy, 1, h - title_h - padding * 2, 40, 40, 50, math.floor(60 * alpha))
                        draw_gc_section(col4_x, cy, col_gc_w)
                    end

                    -- column separators
                    renderer.rectangle(col2_x - math.floor(col_gap * 0.5), cy, 1, h - title_h - padding * 2, 40, 40, 50, math.floor(60 * alpha))
                    renderer.rectangle(col3_x - math.floor(col_gap * 0.5), cy, 1, h - title_h - padding * 2, 40, 40, 50, math.floor(60 * alpha))

                else
                    -- vertical

                -- status rows
                cy = cy + draw_status_row(cx, cy, content_w, 'breaking lc', lc_text, smooth_lc, pulse * smooth_lc, ar, ag, ab, alpha)
                cy = cy + draw_status_row(cx, cy, content_w, 'peeking', peek_text, smooth_peek, pulse * smooth_peek, ar, ag, ab, alpha)
                cy = cy + draw_status_row(cx, cy, content_w, 'vulnerable', vuln_text, smooth_vuln, pulse * smooth_vuln, vuln_r, vuln_g, vuln_b, alpha)

                -- separator
                cy = cy + 4
                renderer.rectangle(cx, cy, content_w, 1, 40, 40, 50, math.floor(80 * alpha))
                cy = cy + 8

                if frozen.has_data then
                    local name_trunc = #r_target > 16 and r_target:sub(1, 15) .. '..' or r_target
                    local status_suffix = has_target and '' or '  (lost)'
                    renderer.text(cx, cy, 90, 90, 100, math.floor(140 * alpha * af), '', nil, 'target:')
                    local name_display = name_trunc .. status_suffix
                    local ntw = renderer.measure_text('', name_display)
                    local name_r = math.floor(200 * af + 60 * (1 - af))
                    local name_g = math.floor(200 * af + 60 * (1 - af))
                    local name_b = math.floor(210 * af + 70 * (1 - af))
                    renderer.text(cx + content_w - ntw, cy, name_r, name_g, name_b, math.floor(200 * alpha * af), '', nil, name_display)
                    cy = cy + row_h + 2

                    -- compass
                    local compass_cx = px + math.floor(w * 0.5)
                    local compass_cy = cy + math.floor(compass_size * 0.5)
                    local compass_r = math.floor(compass_size * 0.5)

                    draw_yaw_compass(compass_cx, compass_cy, compass_r, smooth_eye_yaw, smooth_feet_yaw, desync_pct, c_ar, c_ag, c_ab, alpha * af, my_yaw)
                    draw_shot_markers_at(compass_cx, compass_cy, compass_r)

                    -- legend
                    local legend_y = cy + compass_size + 4

                    renderer.rectangle(cx + 4, legend_y + 4, 8, 2, c_ar, c_ag, c_ab, math.floor(200 * alpha * af))
                    renderer.text(cx + 16, legend_y, 110, 110, 120, math.floor(160 * alpha * af), '', nil, 'eye')

                    local feet_lx = cx + content_w - 40
                    renderer.rectangle(feet_lx, legend_y + 4, 8, 2, math.floor(180 * af), math.floor(180 * af), math.floor(200 * af), math.floor(140 * alpha * af))
                    renderer.text(feet_lx + 12, legend_y, 110, 110, 120, math.floor(160 * alpha * af), '', nil, 'feet')

                    -- desync label
                    local desync_str = string.format('%d°', math.floor(smooth_desync))
                    local dw = renderer.measure_text('', desync_str)
                    renderer.text(compass_cx - math.floor(dw * 0.5), legend_y, c_ar, c_ag, c_ab, math.floor(180 * alpha * af * (0.7 + desync_pct * 0.3)), '', nil, desync_str)

                    cy = legend_y + 16

                    -- separator
                    renderer.rectangle(cx, cy, content_w, 1, 40, 40, 50, math.floor(80 * alpha * af))
                    cy = cy + 8

                    -- resolver info
                    local info_alpha = alpha * af

                    local source_text = frozen.using_gs and 'gamesense' or (debug_panel_info.resolver_mode == 'desync resolver' and 'desync resolver' or 'kittysolver >w<')
                    local src_r = frozen.using_gs and 140 or math.floor(ar * 0.7 + 90 * 0.3)
                    local src_g = frozen.using_gs and 140 or math.floor(ag * 0.7 + 90 * 0.3)
                    local src_b = frozen.using_gs and 150 or math.floor(ab * 0.7 + 100 * 0.3)
                    renderer.text(cx, cy, 90, 90, 100, math.floor(140 * info_alpha), '', nil, 'resolver:')
                    local stw = renderer.measure_text('', source_text)
                    renderer.text(cx + content_w - stw, cy, src_r, src_g, src_b, math.floor(200 * info_alpha), '', nil, source_text)
                    cy = cy + row_h

                    local side_text = r_side > 0 and 'right' or (r_side < 0 and 'left' or 'center')
                    cy = cy + draw_info_row(cx, cy, content_w, 'resolved side', side_text, info_alpha)

                    local desync_text = string.format('%d°', math.floor(r_desync))
                    cy = cy + draw_info_row(cx, cy, content_w, 'desync', desync_text, info_alpha)

                    local max_text = string.format('%d°', math.floor(r_max_desync))
                    cy = cy + draw_info_row(cx, cy, content_w, 'max desync', max_text, info_alpha)

                    local eye_text = string.format('%d°', math.floor(smooth_eye_yaw) % 360)
                    local feet_text = string.format('%d°', math.floor(smooth_feet_yaw) % 360)
                    cy = cy + draw_info_row(cx, cy, content_w, 'eye / feet', eye_text .. '  ' .. feet_text, info_alpha)
                else
                    -- no target
                    local no_text = 'no target'
                    local ntw = renderer.measure_text('', no_text)
                    renderer.text(px + math.floor((w - ntw) * 0.5), cy + 30, 60, 60, 70, math.floor(120 * alpha), '', nil, no_text)
                end

                -- gc monitor
                if gc_enabled then

                -- separator
                cy = cy + 4
                renderer.rectangle(cx, cy, content_w, 1, 40, 40, 50, math.floor(80 * alpha))
                cy = cy + 8

                draw_gc_section(cx, cy, content_w)

                end -- gc_enabled

                end -- is_horizontal
            end

            local function add_shot_marker(e, is_hit)
                local target = e.target
                if not target then return end

                -- reconstruct feet yaw from body yaw override
                local body_yaw_value = plist.get(target, 'Force body yaw value') or 0
                local eye_yaw = select(2, entity.get_prop(target, 'm_angEyeAngles')) or 0

                local resolved_yaw = eye_yaw - body_yaw_value -- feet = eye - value
                local _, local_yaw = client.camera_angles()

                table.insert(shot_markers, {
                    yaw = resolved_yaw,
                    hit = is_hit,
                    time = globals.realtime(),
                    alpha = 1.0,
                    target = target,
                    local_yaw = local_yaw or 0,
                })

                while #shot_markers > MAX_MARKERS do
                    table.remove(shot_markers, 1)
                end
            end

            local function on_debug_aim_hit(e)
                add_shot_marker(e, true)
            end

            local function on_debug_aim_miss(e)
                add_shot_marker(e, false)
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()
                    utils.event_callback('paint_ui', on_paint_ui, value)
                    utils.event_callback('aim_hit', on_debug_aim_hit, value)
                    utils.event_callback('aim_miss', on_debug_aim_miss, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end
        local manual_arrows do
            local ref = ref.visuals.manual_arrows

            local draw_default do
                local PADDING = 40

                local left_value = 0
                local right_value = 0
                local forward_value = 0

                local scope_align = 0

                local function update_values(me)
                    local value = antiaim.manual_yaw:get()

                    local is_alive = entity.is_alive(me)
                    local is_scoped = entity.get_prop(me, 'm_bIsScoped')

                    left_value = motion.interp(left_value, is_alive and value == 'left', 0.05)
                    right_value = motion.interp(right_value, is_alive and value == 'right', 0.05)
                    forward_value = motion.interp(forward_value, is_alive and value == 'forward', 0.05)

                    scope_align = motion.interp(scope_align, is_scoped, 0.05)
                end

                local function draw_left_arrow(x, y, r, g, b, a, alpha)
                    if alpha <= 0 then
                        return
                    end

                    local flags, text = '+', '<'

                    local text_size = vector(
                        renderer.measure_text(
                            flags, text
                        )
                    )

                    x = x - round(text_size.x - 1)
                    y = y - round(text_size.y / 2)

                    renderer.text(x, y, r, g, b, a * alpha, flags, nil, text)
                end

                local function draw_right_arrow(x, y, r, g, b, a, alpha)
                    if alpha <= 0 then
                        return
                    end

                    local flags, text = '+', '>'

                    local text_size = vector(
                        renderer.measure_text(
                            flags, text
                        )
                    )

                    y = y - round(text_size.y / 2)

                    renderer.text(x, y, r, g, b, a * alpha, flags, nil, text)
                end

                local function draw_forward_arrow(x, y, r, g, b, a, alpha)
                    if alpha <= 0 then
                        return
                    end

                    local flags, text = '+', '^'

                    local text_size = vector(
                        renderer.measure_text(
                            flags, text
                        )
                    )

                    x = x - round(text_size.x / 2)
                    y = y - round(text_size.y * 0.5)

                    renderer.text(x, y, r, g, b, a * alpha, flags, nil, text)
                end

                local function draw_arrows()
                    local r, g, b, a = ref.color_accent:get()

                    local screen_size = vector(
                        client.screen_size()
                    )

                    local position = screen_size / 2

                    draw_forward_arrow(position.x, position.y - PADDING, r, g, b, a, forward_value)

                    position.y = position.y - round(
                        scope_align * 15
                    )

                    draw_left_arrow(position.x - PADDING, position.y, r, g, b, a, left_value)
                    draw_right_arrow(position.x + PADDING, position.y, r, g, b, a, right_value)
                end

                function draw_default()
                    if not boot.done then return end
                    local me = entity.get_local_player()

                    if me == nil then
                        return
                    end

                    update_values(me)
                    draw_arrows()
                end
            end

            local draw_alternative do
                local PADDING = 40

                local function draw_arrows()
                    local screen_size = vector(
                        client.screen_size()
                    )

                    local position = screen_size / 2

                    local color_accent = color(ref.color_accent:get())
                    local color_secondary = color(ref.color_secondary:get())

                    local manual_value = antiaim.manual_yaw:get()
                    local desync_angle = antiaim.buffer.body_yaw_offset

                    local x_offset = PADDING
                    local rect_size = 2

                    local width = 13
                    local height = 9

                    local color_inactive = color(35, 35, 35, 150)

                    local left_manual = manual_value == 'left' and color_accent or color_inactive
                    local right_manual = manual_value == 'right' and color_accent or color_inactive

                    local left_desync = (desync_angle ~= nil and desync_angle < 0) and color_secondary or color_inactive
                    local right_desync = (desync_angle ~= nil and desync_angle > 0) and color_secondary or color_inactive

                    local left_x = position.x - x_offset - (rect_size + 2)
                    local right_x = position.x + x_offset + (rect_size + 2)

                    left_desync = left_desync:clone()
                    right_desync = right_desync:clone()

                    renderer.triangle(left_x - width, position.y, left_x, position.y - height, left_x, position.y + height, left_manual:unpack())
                    renderer.triangle(right_x + width, position.y, right_x, position.y - height, right_x, position.y + height, right_manual:unpack())

                    renderer.rectangle(left_x + rect_size + 2, position.y - height, -rect_size, height * 2, left_desync:unpack())
                    renderer.rectangle(right_x - rect_size - 2, position.y - height, rect_size, height * 2, right_desync:unpack())
                end

                function draw_alternative()
                    if not boot.done then return end
                    local me = entity.get_local_player()

                    if me == nil or not entity.is_alive(me) then
                        return
                    end

                    draw_arrows()
                end
            end

            local callbacks do
                local function on_style(item)
                    local value = item:get()

                    utils.event_callback('paint_ui', draw_default, value == 'Default')
                    utils.event_callback('paint_ui', draw_alternative, value == 'Alternative')
                end

                local function on_enabled(item)
                    local value = item:get()

                    if value then
                        ref.style:set_callback(on_style, true)
                    else
                        ref.style:unset_callback(on_style)
                    end

                    if not value then
                        utils.event_callback('paint_ui', draw_default, false)
                        utils.event_callback('paint_ui', draw_alternative, false)
                    end
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local velocity_warning do
            local ref = ref.visuals.velocity_warning

            local alpha_value = 0

            local function draw_bar(x, y, w, h, r, g, b, a, alpha)
                render.glow(x, y, w, h, r, g, b, a * alpha * 0.075, 1, 8)
                renderer.rectangle(x, y, w, h, 0, 0, 0, a / 2 * alpha)
            end

            local function on_paint()
                if not boot.done then return end
                local me = entity.get_local_player()

                if me == nil then
                    return
                end

                local screen_size = vector(
                    client.screen_size()
                )

                local position = vector(
                    screen_size.x * 0.5,
                    ref.offset:get() * 2
                )

                local is_alive = entity.is_alive(me)
                local is_menu_open = ui.is_menu_open()

                local velocity_modifier = entity.get_prop(
                    me, 'm_flVelocityModifier'
                )

                if not is_alive then
                    velocity_modifier = 1.0
                end

                local should_interp = is_menu_open or (is_alive and velocity_modifier < 1.0)

                alpha_value = motion.interp(alpha_value, should_interp, 0.05)

                if alpha_value <= 0 then
                    return
                end

                local fill_color = color(
                    ref.color:get()
                )

                local text_color = color(
                    255, 255, 255, 200
                )

                text_color.a = text_color.a * alpha_value

                local flags, text = '', string.format(
                    'Your velocity is reduced by %d%%',
                    (1 - velocity_modifier) * 100
                )

                local text_size = vector(
                    renderer.measure_text(flags, text)
                )

                local text_pos = position + vector(
                    -text_size.x * 0.5 + 1, 0
                )

                renderer.text(text_pos.x, text_pos.y, text_color.r, text_color.g, text_color.b, text_color.a, flags, nil, text)

                position.y = position.y + text_size.y + 7

                if fill_color.a > 0 then
                    local rect_size = vector(180, 4)

                    local rect_pos = position + vector(
                        -rect_size.x * 0.5, 0
                    )

                    draw_bar(
                        rect_pos.x, rect_pos.y, rect_size.x, rect_size.y,
                        fill_color.r, fill_color.g, fill_color.b, fill_color.a,
                        alpha_value
                    )

                    renderer.rectangle(
                        rect_pos.x + 1, rect_pos.y + 1, (rect_size.x - 2) * velocity_modifier, rect_size.y - 2,
                        fill_color.r, fill_color.g, fill_color.b, fill_color.a * alpha_value
                    )
                end
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    utils.event_callback(
                        'paint',
                        on_paint,
                        value
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local velocity_graph do
            local ref = ref.visuals.velocity_graph

            local DB_KEY = 'catboy#velocity_graph_pos'
            local saved_pos = database.read(DB_KEY) or { }

            local MAX_SAMPLES = 128
            local velocity_samples = { }
            local sample_index = 0
            local peak_velocity = 0
            local alpha_value = 0

            -- position state
            local pos_x = saved_pos.x or 0
            local pos_y = saved_pos.y or 400
            local smooth_x = pos_x
            local smooth_y = pos_y
            local is_centered = saved_pos.centered ~= false

            -- drag state
            local dragging = false
            local drag_ox, drag_oy = 0, 0
            local was_mouse_down = false
            local drag_target_x, drag_target_y = pos_x, pos_y

            -- snap
            local SNAP_DISTANCE = 15
            local snap_alpha = 0
            local snap_w_alpha = 0
            local snap_h_alpha = 0
            local snap_h_type = nil
            local dim_alpha = 0

            for i = 1, MAX_SAMPLES do
                velocity_samples[i] = 0
            end

            local function save_position()
                database.write(DB_KEY, {
                    x = pos_x,
                    y = pos_y,
                    centered = is_centered,
                })
            end

            local function on_paint()
                if not boot.done then return end
                local me = entity.get_local_player()

                if me == nil then return end

                local is_alive = entity.is_alive(me)

                alpha_value = motion.interp(alpha_value, is_alive, 0.08)

                if alpha_value <= 0.01 then
                    return
                end

                local velocity = math.sqrt(localplayer.velocity2d_sqr)

                sample_index = sample_index + 1
                if sample_index > MAX_SAMPLES then
                    sample_index = 1
                end
                velocity_samples[sample_index] = velocity

                local max_vel = 300
                for i = 1, MAX_SAMPLES do
                    if velocity_samples[i] > max_vel then
                        max_vel = velocity_samples[i]
                    end
                end

                peak_velocity = motion.interp(peak_velocity, max_vel, 0.05)
                local graph_max = math.max(peak_velocity, 300)

                local screen_w, screen_h = client.screen_size()
                local graph_w = ref.width:get()
                local graph_h = ref.height:get()

                -- dragging (menu open only)
                local is_menu = ui.is_menu_open()
                local is_snapped_w = false
                local is_snapped_h_now = false

                if is_menu then
                    local mouse_x, mouse_y = ui.mouse_position()
                    local mouse_down = client.key_state(0x01)

                    -- use smooth position for hit test so it matches what user sees
                    local hit_x = math.floor(smooth_x)
                    local hit_y = math.floor(smooth_y)

                    if mouse_down and not was_mouse_down then
                        if mouse_x >= hit_x and mouse_x <= hit_x + graph_w
                            and mouse_y >= hit_y and mouse_y <= hit_y + graph_h then
                            dragging = true
                            drag_ox = mouse_x - hit_x
                            drag_oy = mouse_y - hit_y
                            drag_target_x = hit_x
                            drag_target_y = hit_y
                        end
                    end

                    if not mouse_down then
                        if dragging then
                            save_position()
                        end
                        dragging = false
                    end

                    if dragging then
                        local new_x = mouse_x - drag_ox
                        local new_y = mouse_y - drag_oy

                        -- clamp to screen
                        new_x = math.max(0, math.min(new_x, screen_w - graph_w))
                        new_y = math.max(0, math.min(new_y, screen_h - graph_h))

                        -- center snap (horizontal center)
                        local center_x = math.floor(screen_w * 0.5 - graph_w * 0.5)
                        if math.abs(new_x - center_x) < SNAP_DISTANCE then
                            is_centered = true
                            drag_target_x = center_x
                        else
                            is_centered = false
                            drag_target_x = new_x
                        end

                        -- width snap (left edge, right edge)
                        if math.abs(new_x) < SNAP_DISTANCE then
                            drag_target_x = 0
                            is_centered = false
                            is_snapped_w = true
                        elseif math.abs(new_x - (screen_w - graph_w)) < SNAP_DISTANCE then
                            drag_target_x = screen_w - graph_w
                            is_centered = false
                            is_snapped_w = true
                        end

                        -- horizontal snap (vertical center, top edge, bottom edge)
                        local center_y = math.floor(screen_h * 0.5 - graph_h * 0.5)
                        if math.abs(new_y - center_y) < SNAP_DISTANCE then
                            drag_target_y = center_y
                            snap_h_type = 'center'
                            is_snapped_h_now = true
                        elseif math.abs(new_y) < SNAP_DISTANCE then
                            drag_target_y = 0
                            snap_h_type = 'top'
                            is_snapped_h_now = true
                        elseif math.abs(new_y - (screen_h - graph_h)) < SNAP_DISTANCE then
                            drag_target_y = screen_h - graph_h
                            snap_h_type = 'bottom'
                            is_snapped_h_now = true
                        else
                            drag_target_y = new_y
                        end

                        pos_x = drag_target_x
                        pos_y = drag_target_y
                    end

                    was_mouse_down = mouse_down
                else
                    dragging = false
                    was_mouse_down = false
                end

                debug_panel_info.dragging_graph = dragging

                -- animate snap guides and dim
                snap_alpha = motion.interp(snap_alpha, dragging and is_centered, 0.15)
                snap_w_alpha = motion.interp(snap_w_alpha, dragging and is_snapped_w, 0.15)
                snap_h_alpha = motion.interp(snap_h_alpha, dragging and is_snapped_h_now, 0.15)
                dim_alpha = motion.interp(dim_alpha, dragging, 0.1)

                -- smooth position (smooth while dragging too)
                local target_x = is_centered and math.floor(screen_w * 0.5 - graph_w * 0.5) or pos_x
                local target_y = pos_y

                local base_speed = dragging and 0.35 or 0.15
                local lerp_speed = 1 - math.pow(1 - base_speed, globals.frametime() / (1 / 60))
                smooth_x = smooth_x + (target_x - smooth_x) * lerp_speed
                smooth_y = smooth_y + (target_y - smooth_y) * lerp_speed

                local graph_x = math.floor(smooth_x)
                local graph_y = math.floor(smooth_y)

                local fill_color = color(ref.color:get())
                local alpha = alpha_value

                -- dim background when dragging
                if dim_alpha > 0.01 then
                    renderer.rectangle(0, 0, screen_w, screen_h, 0, 0, 0, math.floor(60 * dim_alpha * alpha))
                end

                -- center snap guide line
                if snap_alpha > 0.01 then
                    local cx = math.floor(screen_w * 0.5)
                    local sa = math.floor(120 * snap_alpha * alpha)
                    renderer.rectangle(cx, graph_y - 12, 1, graph_h + 24, fill_color.r, fill_color.g, fill_color.b, sa)
                end

                -- width snap guide lines (left/right edge)
                if snap_w_alpha > 0.01 then
                    local sa = math.floor(120 * snap_w_alpha * alpha)
                    if pos_x == 0 then
                        renderer.rectangle(0, graph_y - 12, 1, graph_h + 24, fill_color.r, fill_color.g, fill_color.b, sa)
                    elseif pos_x == screen_w - graph_w then
                        renderer.rectangle(screen_w - 1, graph_y - 12, 1, graph_h + 24, fill_color.r, fill_color.g, fill_color.b, sa)
                    end
                end

                -- horizontal snap guide lines (vertical center, top, bottom)
                if snap_h_alpha > 0.01 then
                    local sa = math.floor(120 * snap_h_alpha * alpha)
                    if snap_h_type == 'center' then
                        local cy = math.floor(screen_h * 0.5)
                        renderer.rectangle(graph_x - 12, cy, graph_w + 24, 1, fill_color.r, fill_color.g, fill_color.b, sa)
                    elseif snap_h_type == 'top' then
                        renderer.rectangle(graph_x - 12, 0, graph_w + 24, 1, fill_color.r, fill_color.g, fill_color.b, sa)
                    elseif snap_h_type == 'bottom' then
                        renderer.rectangle(graph_x - 12, screen_h - 1, graph_w + 24, 1, fill_color.r, fill_color.g, fill_color.b, sa)
                    end
                end

                -- background
                renderer.rectangle(graph_x, graph_y, graph_w, graph_h, 0, 0, 0, math.floor(120 * alpha))

                -- border (highlight when dragging)
                local border_a = math.floor(80 + 80 * dim_alpha)
                renderer.rectangle(graph_x, graph_y, graph_w, 1, fill_color.r, fill_color.g, fill_color.b, math.floor(border_a * alpha))
                renderer.rectangle(graph_x, graph_y + graph_h - 1, graph_w, 1, fill_color.r, fill_color.g, fill_color.b, math.floor(border_a * alpha))
                renderer.rectangle(graph_x, graph_y, 1, graph_h, fill_color.r, fill_color.g, fill_color.b, math.floor(border_a * alpha))
                renderer.rectangle(graph_x + graph_w - 1, graph_y, 1, graph_h, fill_color.r, fill_color.g, fill_color.b, math.floor(border_a * alpha))

                -- grid lines (25%, 50%, 75%)
                for i = 1, 3 do
                    local gy = graph_y + math.floor(graph_h * (i / 4))
                    for gx = graph_x + 2, graph_x + graph_w - 3, 4 do
                        renderer.rectangle(gx, gy, 2, 1, 255, 255, 255, math.floor(20 * alpha))
                    end
                end

                -- draw graph lines with gradient fill
                local padding = 2
                local draw_w = graph_w - padding * 2
                local draw_h = graph_h - padding * 2
                local step = draw_w / (MAX_SAMPLES - 1)

                for i = 0, MAX_SAMPLES - 2 do
                    local idx1 = ((sample_index + i) % MAX_SAMPLES) + 1
                    local idx2 = ((sample_index + i + 1) % MAX_SAMPLES) + 1

                    local v1 = math.min(velocity_samples[idx1] / graph_max, 1)
                    local v2 = math.min(velocity_samples[idx2] / graph_max, 1)

                    local x1 = graph_x + padding + math.floor(i * step)
                    local y1 = graph_y + padding + math.floor(draw_h * (1 - v1))
                    local x2 = graph_x + padding + math.floor((i + 1) * step)
                    local y2 = graph_y + padding + math.floor(draw_h * (1 - v2))

                    -- gradient fill column
                    local col_x = math.floor(x1)
                    local col_top = math.min(y1, y2)
                    local col_bot = graph_y + graph_h - padding
                    if col_bot > col_top then
                        renderer.gradient(
                            col_x, col_top, math.max(math.floor(step), 1), col_bot - col_top,
                            fill_color.r, fill_color.g, fill_color.b, math.floor(fill_color.a * 0.25 * alpha),
                            fill_color.r, fill_color.g, fill_color.b, 0,
                            false
                        )
                    end

                    -- line
                    renderer.line(x1, y1, x2, y2, fill_color.r, fill_color.g, fill_color.b, math.floor(fill_color.a * alpha))
                end

                -- current speed text
                local speed_text = string.format('%d u/s', math.floor(velocity))
                local tw, th = renderer.measure_text('', speed_text)
                renderer.text(
                    graph_x + graph_w - tw - 4, graph_y + 3,
                    255, 255, 255, math.floor(220 * alpha),
                    '', nil, speed_text
                )

                -- peak text
                local peak_text = string.format('peak: %d', math.floor(max_vel))
                renderer.text(
                    graph_x + 4, graph_y + 3,
                    255, 255, 255, math.floor(120 * alpha),
                    '', nil, peak_text
                )

                -- bottom label
                renderer.text(
                    graph_x + math.floor(graph_w * 0.5) - 15, graph_y + graph_h + 2,
                    255, 255, 255, math.floor(80 * alpha),
                    '', nil, 'velocity'
                )
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    utils.event_callback(
                        'paint',
                        on_paint,
                        value
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local spotify_player do
            local ref = ref.debug.spotify_player

            local DB_KEY = 'catboy#spotify_pos'
            local saved_pos = database.read(DB_KEY) or { }

            -- position / dragging
            local sp_x = saved_pos.x or 500
            local sp_y = saved_pos.y or 300
            local smooth_spx = sp_x
            local smooth_spy = sp_y
            local sp_dragging = false
            local sp_drag_ox, sp_drag_oy = 0, 0
            local sp_was_mouse = false
            local sp_dim_alpha = 0.0
            local smooth_alpha = 0.0
            -- snap state
            local sp_snap = {
                dist = 15,
                cx = false, cy = false,
                left = false, right = false,
                top = false, bottom = false,
                cx_alpha = 0.0, cy_alpha = 0.0,
                w_alpha = 0.0, h_alpha = 0.0,
            }

            -- panel dimensions
            local SP = {
                W = 260, H = 90, ART = 64, PADDING = 8,
                TITLE_H = 18, CTRL_H = 16, PROG_H = 4, VOL_W = 50,
            }

            -- smooth layout transitions
            local sp_smooth_w, sp_smooth_h = nil, nil
            local sp_smooth_content_alpha = 1.0
            local sp_prev_layout = nil

            -- playback + interaction state
            local sp = {
                update_wait = false,
                song = 'No track', artist = '',
                playing = false, progress_ms = 0, duration_ms = 0,
                volume = 50, album_art = nil, last_art_url = nil,
                last_update = 0, last_progress_sync = 0, data = nil,
                hovering = 'none', vol_dragging = false, seek_dragging = false,
            }

            -- smooth animation
            local sp_smooth = {
                prog = 0.0, prev_hover = 0.0, pp_hover = 0.0,
                next_hover = 0.0, vol_fill = 0.0,
                time_bright = 0.0, vol_bright = 0.0,
            }

            local function save_sp_pos()
                database.write(DB_KEY, { x = sp_x, y = sp_y })
            end

            local function ms_to_time(ms)
                ms = tonumber(ms) or 0
                local total_sec = math.floor(ms / 1000)
                local min = math.floor(total_sec / 60)
                local sec = total_sec - min * 60
                return string.format('%d:%02d', min, sec)
            end

            local function sp_api_headers()
                return {
                    headers = {
                        ['Accept'] = 'application/json',
                        ['Content-Type'] = 'application/json',
                        ['Authorization'] = 'Bearer ' .. (sp_auth_state.apikey or ''),
                        ['Content-length'] = 0
                    }
                }
            end

            -- update playback state
            local function sp_update()
                if not sp_auth_state.authed or not sp_auth_state.apikey or sp_auth_state.pending then return end
                sp_auth_state.pending = true
                http.get('https://api.spotify.com/v1/me/player', { headers = { ['Authorization'] = 'Bearer ' .. sp_auth_state.apikey } }, function(s, r)
                    sp_auth_state.pending = false
                    if not s or r.status ~= 200 then
                        if r and r.status == 401 then
                            sp_auth_state.authed = false
                            sp_fetch_token()
                        end
                        return
                    end
                    local ok, data = pcall(json.parse, r.body)
                    if not ok or not data then return end
                    sp.data = data

                    if data.device then
                        sp_auth_state.device_id = data.device.id
                        sp.volume = data.device.volume_percent or 50
                    end

                    sp.playing = data.is_playing or false

                    if data.progress_ms then
                        sp.progress_ms = data.progress_ms
                        sp.last_progress_sync = globals.realtime()
                    end

                    if type(data.item) == 'table' then
                        sp.song = data.item.name or 'Unknown'
                        if data.item.artists and data.item.artists[1] then
                            sp.artist = data.item.artists[1].name or ''
                        end
                        sp.duration_ms = data.item.duration_ms or 0

                        -- load album art
                        if not data.item.is_local and data.item.album and data.item.album.images and data.item.album.images[1] then
                            local art_url = data.item.album.images[#data.item.album.images].url
                            if art_url ~= sp.last_art_url then
                                sp.last_art_url = art_url
                                http.get(art_url, function(as, ar)
                                    if as and ar.status == 200 then
                                        local aok, img = pcall(images.load_jpg, ar.body)
                                        if aok and img then
                                            sp.album_art = img
                                        end
                                    end
                                end)
                            end
                        end
                    end
                end)
            end

            -- controls
            local function sp_play_pause()
                if not sp_auth_state.authed or not sp_auth_state.device_id then return end
                local opts = sp_api_headers()
                if sp.playing then
                    http.put('https://api.spotify.com/v1/me/player/pause?device_id=' .. sp_auth_state.device_id, opts, function()
                        sp.update_wait = true
                    end)
                    sp.playing = false
                else
                    http.put('https://api.spotify.com/v1/me/player/play?device_id=' .. sp_auth_state.device_id, opts, function()
                        sp.update_wait = true
                    end)
                    sp.playing = true
                end
            end

            local function sp_next()
                if not sp_auth_state.authed or not sp_auth_state.device_id then return end
                http.post('https://api.spotify.com/v1/me/player/next?device_id=' .. sp_auth_state.device_id, sp_api_headers(), function()
                    sp.update_wait = true
                end)
            end

            local function sp_prev()
                if not sp_auth_state.authed or not sp_auth_state.device_id then return end
                http.post('https://api.spotify.com/v1/me/player/previous?device_id=' .. sp_auth_state.device_id, sp_api_headers(), function()
                    sp.update_wait = true
                end)
            end

            local function sp_set_volume(vol)
                if not sp_auth_state.authed or not sp_auth_state.device_id then return end
                vol = math.max(0, math.min(100, math.floor(vol)))
                sp.volume = vol
                http.put('https://api.spotify.com/v1/me/player/volume?volume_percent=' .. vol .. '&device_id=' .. sp_auth_state.device_id, sp_api_headers(), function() end)
            end

            local function sp_seek(ms)
                if not sp_auth_state.authed or not sp_auth_state.device_id then return end
                ms = math.max(0, math.floor(ms))
                sp.progress_ms = ms
                sp.last_progress_sync = globals.realtime()
                http.put('https://api.spotify.com/v1/me/player/seek?position_ms=' .. ms .. '&device_id=' .. sp_auth_state.device_id, sp_api_headers(), function() end)
            end

            -- auth is handled by file-level sp_auth_state / sp_fetch_token

            local function in_rect(mx, my, rx, ry, rw, rh)
                return mx >= rx and mx <= rx + rw and my >= ry and my <= ry + rh
            end

            -- utf-8 aware helpers
            local function utf8_chars(text)
                local chars = { }
                local i = 1
                local len = #text
                while i <= len do
                    local b = text:byte(i)
                    local char_len
                    if b < 0x80 then char_len = 1
                    elseif b < 0xC0 then char_len = 1 -- continuation byte (shouldn't be leading), skip
                    elseif b < 0xE0 then char_len = 2
                    elseif b < 0xF0 then char_len = 3
                    else char_len = 4
                    end
                    if i + char_len - 1 > len then char_len = len - i + 1 end
                    chars[#chars + 1] = text:sub(i, i + char_len - 1)
                    i = i + char_len
                end
                return chars
            end

            local function truncate_text(text, max_w, flags)
                flags = flags or ''
                local tw = renderer.measure_text(flags, text)
                if tw <= max_w then return text end
                local chars = utf8_chars(text)
                while #chars > 1 do
                    chars[#chars] = nil
                    local joined = table.concat(chars)
                    tw = renderer.measure_text(flags, joined .. '..')
                    if tw <= max_w then return joined .. '..' end
                end
                return '..'
            end

            local function on_paint_ui()
                if not boot.done then return end

                local ar, ag, ab, aa = ref.color:get()
                local ft = globals.frametime()
                local base_dt = 1 / 60
                local is_minimal = ref.layout:get() == 'Minimal'

                -- fade in
                smooth_alpha = smooth_alpha + (1 - smooth_alpha) * (1 - math.pow(1 - 0.1, ft / base_dt))
                local alpha = smooth_alpha
                if alpha < 0.01 then
                    debug_panel_info.hovering_spotify = false
                    return
                end

                -- periodic update (every 3s, or immediately if action pending)
                local now = globals.realtime()
                local update_interval = sp.update_wait and 0.5 or 3.0
                if sp_auth_state.authed and now - sp.last_update > update_interval then
                    sp.last_update = now
                    sp.update_wait = false
                    sp_update()
                end

                -- estimated progress (client-side interpolation)
                local est_progress = sp.progress_ms
                if sp.playing and sp.last_progress_sync > 0 then
                    est_progress = sp.progress_ms + (now - sp.last_progress_sync) * 1000
                    if est_progress > sp.duration_ms then est_progress = sp.duration_ms end
                end

                -- dragging
                local mouse_x, mouse_y = ui.mouse_position()
                local mouse_down = client.key_state(0x01)
                local just_pressed = mouse_down and not sp_was_mouse

                -- dynamic panel dimensions based on layout
                local MIN_H = 32 -- minimal mode height
                local target_panel_w = is_minimal and 200 or SP.W
                local target_panel_h = is_minimal and MIN_H or (SP.TITLE_H + SP.PADDING + SP.ART + SP.PADDING + SP.PROG_H + SP.PADDING + SP.CTRL_H + SP.PADDING)
                local drag_h = is_minimal and MIN_H or SP.TITLE_H

                -- smooth layout transitions
                if sp_smooth_w == nil then sp_smooth_w = target_panel_w end
                if sp_smooth_h == nil then sp_smooth_h = target_panel_h end

                local current_sp_layout = ref.layout:get()
                if sp_prev_layout ~= nil and sp_prev_layout ~= current_sp_layout then
                    sp_smooth_content_alpha = 0.0
                end
                sp_prev_layout = current_sp_layout

                local sp_dim_lerp = 1 - math.pow(1 - 0.12, ft / base_dt)
                sp_smooth_w = sp_smooth_w + (target_panel_w - sp_smooth_w) * sp_dim_lerp
                sp_smooth_h = sp_smooth_h + (target_panel_h - sp_smooth_h) * sp_dim_lerp

                local sp_content_lerp = 1 - math.pow(1 - 0.08, ft / base_dt)
                sp_smooth_content_alpha = sp_smooth_content_alpha + (1.0 - sp_smooth_content_alpha) * sp_content_lerp

                local panel_w = math.floor(sp_smooth_w)

                if ui.is_menu_open() then
                    if just_pressed then
                        if in_rect(mouse_x, mouse_y, smooth_spx, smooth_spy, target_panel_w, drag_h) then
                            sp_dragging = true
                            sp_drag_ox = mouse_x - sp_x
                            sp_drag_oy = mouse_y - sp_y
                        end
                    end

                    if not mouse_down and sp_dragging then
                        sp_dragging = false
                        save_sp_pos()
                    end

                    if sp_dragging then
                        local screen_w, screen_h = client.screen_size()
                        local new_x = mouse_x - sp_drag_ox
                        local new_y = mouse_y - sp_drag_oy
                        local panel_h
                        if is_minimal then
                            panel_h = MIN_H
                        else
                            panel_h = SP.TITLE_H + SP.PADDING + SP.ART + SP.PADDING + SP.PROG_H + SP.PADDING + SP.CTRL_H + SP.PADDING
                            if not sp_auth_state.authed then panel_h = SP.TITLE_H + 30 end
                        end

                        -- reset snaps
                        sp_snap.cx = false
                        sp_snap.cy = false
                        sp_snap.left = false
                        sp_snap.right = false
                        sp_snap.top = false
                        sp_snap.bottom = false

                        -- horizontal center snap (use target width for accurate snap)
                        local center_x = math.floor(screen_w * 0.5 - target_panel_w * 0.5)
                        if math.abs(new_x - center_x) < sp_snap.dist then
                            new_x = center_x
                            sp_snap.cx = true
                        end

                        -- edge snap x
                        if math.abs(new_x) < sp_snap.dist then
                            new_x = 0
                            sp_snap.cx = false
                            sp_snap.left = true
                        elseif math.abs(new_x - (screen_w - target_panel_w)) < sp_snap.dist then
                            new_x = screen_w - target_panel_w
                            sp_snap.cx = false
                            sp_snap.right = true
                        end

                        -- center snap y
                        local center_y = math.floor(screen_h * 0.5 - panel_h * 0.5)
                        if math.abs(new_y - center_y) < sp_snap.dist then
                            new_y = center_y
                            sp_snap.cy = true
                        end

                        -- edge snap y
                        if math.abs(new_y) < sp_snap.dist then
                            new_y = 0
                            sp_snap.cy = false
                            sp_snap.top = true
                        elseif math.abs(new_y - (screen_h - panel_h)) < sp_snap.dist then
                            new_y = screen_h - panel_h
                            sp_snap.cy = false
                            sp_snap.bottom = true
                        end

                        sp_x = new_x
                        sp_y = new_y
                    end
                else
                    sp_dragging = false
                end

                debug_panel_info.dragging_spotify = sp_dragging

                -- block input when hovering over spotify panel (with padding)
                local total_h_pre
                if is_minimal then
                    total_h_pre = MIN_H
                else
                    local body_h_pre = SP.PADDING + SP.ART + SP.PADDING + SP.PROG_H + SP.PADDING + SP.CTRL_H + SP.PADDING
                    total_h_pre = SP.TITLE_H + body_h_pre
                    if not sp_auth_state.authed then total_h_pre = SP.TITLE_H + 30 end
                end
                local hover_pad = 6
                debug_panel_info.hovering_spotify = ui.is_menu_open() and in_rect(mouse_x, mouse_y, smooth_spx - hover_pad, smooth_spy - hover_pad, target_panel_w + hover_pad * 2, total_h_pre + hover_pad * 2)

                -- smooth position
                local spd = sp_dragging and 0.35 or 0.15
                local lerp = 1 - math.pow(1 - spd, ft / base_dt)
                smooth_spx = smooth_spx + (sp_x - smooth_spx) * lerp
                smooth_spy = smooth_spy + (sp_y - smooth_spy) * lerp

                -- dim overlay
                sp_dim_alpha = sp_dim_alpha + ((sp_dragging and 1 or 0) - sp_dim_alpha) * (1 - math.pow(1 - 0.1, ft / base_dt))
                if sp_dim_alpha > 0.01 then
                    local sw, sh = client.screen_size()
                    renderer.rectangle(0, 0, sw, sh, 0, 0, 0, math.floor(60 * sp_dim_alpha * alpha))
                end

                -- snap guides
                local snap_lerp = 1 - math.pow(1 - 0.15, ft / base_dt)
                sp_snap.cx_alpha = sp_snap.cx_alpha + ((sp_dragging and sp_snap.cx and 1 or 0) - sp_snap.cx_alpha) * snap_lerp
                sp_snap.cy_alpha = sp_snap.cy_alpha + ((sp_dragging and sp_snap.cy and 1 or 0) - sp_snap.cy_alpha) * snap_lerp
                sp_snap.w_alpha = sp_snap.w_alpha + ((sp_dragging and (sp_snap.left or sp_snap.right) and 1 or 0) - sp_snap.w_alpha) * snap_lerp
                sp_snap.h_alpha = sp_snap.h_alpha + ((sp_dragging and (sp_snap.top or sp_snap.bottom) and 1 or 0) - sp_snap.h_alpha) * snap_lerp

                local px, py = math.floor(smooth_spx), math.floor(smooth_spy)

                -- use smooth height for rendering
                local total_h = math.floor(sp_smooth_h)
                if not is_minimal and not sp_auth_state.authed then
                    total_h = SP.TITLE_H + 30
                end

                -- snap lines
                do
                    local sw, sh = client.screen_size()
                    if sp_snap.cx_alpha > 0.01 then
                        local cx = math.floor(sw * 0.5)
                        local sa = math.floor(120 * sp_snap.cx_alpha * alpha)
                        renderer.rectangle(cx, py - 12, 1, total_h + 24, ar, ag, ab, sa)
                    end
                    if sp_snap.cy_alpha > 0.01 then
                        local cy = math.floor(sh * 0.5)
                        local sa = math.floor(120 * sp_snap.cy_alpha * alpha)
                        renderer.rectangle(px - 12, cy, panel_w + 24, 1, ar, ag, ab, sa)
                    end
                    if sp_snap.w_alpha > 0.01 then
                        local sa = math.floor(120 * sp_snap.w_alpha * alpha)
                        if sp_snap.left then
                            renderer.rectangle(0, py - 12, 1, total_h + 24, ar, ag, ab, sa)
                        elseif sp_snap.right then
                            renderer.rectangle(sw - 1, py - 12, 1, total_h + 24, ar, ag, ab, sa)
                        end
                    end
                    if sp_snap.h_alpha > 0.01 then
                        local sa = math.floor(120 * sp_snap.h_alpha * alpha)
                        if sp_snap.top then
                            renderer.rectangle(px - 12, 0, panel_w + 24, 1, ar, ag, ab, sa)
                        elseif sp_snap.bottom then
                            renderer.rectangle(px - 12, sh - 1, panel_w + 24, 1, ar, ag, ab, sa)
                        end
                    end
                end

                -- drop shadow
                renderer.rectangle(px + 3, py + 3, panel_w, total_h, 0, 0, 0, math.floor(30 * alpha))
                renderer.rectangle(px + 2, py + 2, panel_w, total_h, 0, 0, 0, math.floor(40 * alpha))

                -- main background
                renderer.gradient(px, py, panel_w, total_h, 14, 14, 18, math.floor(235 * alpha), 10, 10, 14, math.floor(235 * alpha), false)

                -- accent
                renderer.gradient(px, py, math.floor(panel_w * 0.5), 1, ar, ag, ab, 0, ar, ag, ab, math.floor(180 * alpha), true)
                renderer.gradient(px + math.floor(panel_w * 0.5), py, math.floor(panel_w * 0.5), 1, ar, ag, ab, math.floor(180 * alpha), ar, ag, ab, 0, true)

                -- border
                local border_a = math.floor((50 + 30 * (sp_dragging and 1 or 0)) * alpha)
                renderer.rectangle(px, py, panel_w, 1, 50, 50, 60, border_a)
                renderer.rectangle(px, py + total_h - 1, panel_w, 1, 30, 30, 40, border_a)
                renderer.rectangle(px, py, 1, total_h, 40, 40, 50, border_a)
                renderer.rectangle(px + panel_w - 1, py, 1, total_h, 40, 40, 50, border_a)

                if is_minimal then
                    -- ===== MINIMAL LAYOUT =====
                    -- fade content during layout transition
                    alpha = alpha * sp_smooth_content_alpha
                    local menu_open = ui.is_menu_open()
                    local lerp_btn = 1 - math.pow(1 - 0.15, ft / base_dt)
                    local m_pad = 6
                    local btn_size = 10
                    local btn_gap = 16

                    -- progress bar across the top (2px thin)
                    local prog_y = py + 1
                    local prog_w = panel_w - 2
                    local prog_pct = sp.duration_ms > 0 and (est_progress / sp.duration_ms) or 0
                    local target_prog = prog_w * math.min(1, prog_pct)
                    local prog_speed = sp.seek_dragging and 0.4 or 0.08
                    local prog_lerp = 1 - math.pow(1 - prog_speed, ft / base_dt)
                    sp_smooth.prog = sp_smooth.prog + (target_prog - sp_smooth.prog) * prog_lerp
                    local prog_fill = math.floor(sp_smooth.prog)

                    renderer.rectangle(px + 1, prog_y, prog_w, 2, 30, 30, 40, math.floor(120 * alpha))
                    if prog_fill > 0 then
                        renderer.rectangle(px + 1, prog_y, prog_fill, 2, ar, ag, ab, math.floor(200 * alpha))
                        -- head dot
                        local dot_x = px + 1 + prog_fill
                        renderer.rectangle(dot_x - 2, prog_y - 1, 4, 4, 240, 240, 250, math.floor(245 * alpha))
                        renderer.rectangle(dot_x - 3, prog_y - 2, 6, 6, ar, ag, ab, math.floor(40 * alpha))
                    end

                    -- seek interaction on progress bar
                    if menu_open then
                        local prog_hit = in_rect(mouse_x, mouse_y, px + 1, prog_y - 3, prog_w, 8)
                        if prog_hit and just_pressed then
                            sp.seek_dragging = true
                        end
                        if sp.seek_dragging then
                            if mouse_down then
                                local pct = math.max(0, math.min(1, (mouse_x - (px + 1)) / prog_w))
                                est_progress = pct * sp.duration_ms
                                sp.progress_ms = est_progress
                                sp.last_progress_sync = globals.realtime()
                            else
                                sp_seek(est_progress)
                                sp.seek_dragging = false
                            end
                        end
                    end

                    if not sp_auth_state.authed then
                        local msg = sp_auth_state.status == 'connecting' and 'Connecting...' or 'Not connected'
                        local mw = renderer.measure_text('', msg)
                        renderer.text(px + math.floor((panel_w - mw) * 0.5), py + 10, 100, 100, 110, math.floor(180 * alpha), '', nil, msg)
                        sp_was_mouse = mouse_down
                        return
                    end

                    -- controls on left side
                    local ctrl_y = py + math.floor((MIN_H - btn_size) * 0.5) + 1
                    local ctrl_x = px + m_pad

                    -- helper for minimal buttons
                    local function draw_min_btn(bx, by, label, hover_smooth_val, is_accent)
                        local hover = menu_open and in_rect(mouse_x, mouse_y, bx - 4, by - 4, btn_size + 8, btn_size + 8)
                        local hv = hover_smooth_val

                        local br, bg_c, bb
                        if is_accent then
                            br = math.floor(ar + (255 - ar) * hv)
                            bg_c = math.floor(ag + (255 - ag) * hv)
                            bb = math.floor(ab + (255 - ab) * hv)
                        else
                            br = math.floor(130 + 125 * hv)
                            bg_c = math.floor(130 + 125 * hv)
                            bb = math.floor(140 + 115 * hv)
                        end

                        if hv > 0.01 then
                            local ga = math.floor(40 * hv * alpha)
                            local gr, gg, gb = is_accent and ar or 200, is_accent and ag or 200, is_accent and ab or 210
                            renderer.rectangle(bx - 3, by - 3, btn_size + 6, btn_size + 6, gr, gg, gb, ga)
                        end

                        local tw = renderer.measure_text('', label)
                        renderer.text(bx + math.floor((btn_size - tw) / 2), by - 1, br, bg_c, bb, math.floor((200 + 55 * hv) * alpha), '', nil, label)
                        return hover
                    end

                    -- prev
                    sp_smooth.prev_hover = sp_smooth.prev_hover + ((menu_open and in_rect(mouse_x, mouse_y, ctrl_x - 4, ctrl_y - 4, btn_size + 8, btn_size + 8) and 1 or 0) - sp_smooth.prev_hover) * lerp_btn
                    local prev_hover = draw_min_btn(ctrl_x, ctrl_y, '|<', sp_smooth.prev_hover, false)
                    if prev_hover and just_pressed then sp_prev() end

                    -- play/pause
                    ctrl_x = ctrl_x + btn_gap
                    sp_smooth.pp_hover = sp_smooth.pp_hover + ((menu_open and in_rect(mouse_x, mouse_y, ctrl_x - 4, ctrl_y - 4, btn_size + 8, btn_size + 8) and 1 or 0) - sp_smooth.pp_hover) * lerp_btn
                    local pp_label = sp.playing and '||' or '>'
                    local pp_hover = draw_min_btn(ctrl_x, ctrl_y, pp_label, math.max(sp_smooth.pp_hover, sp.playing and 0.6 or 0), true)
                    if pp_hover and just_pressed then sp_play_pause() end

                    -- next
                    ctrl_x = ctrl_x + btn_gap
                    sp_smooth.next_hover = sp_smooth.next_hover + ((menu_open and in_rect(mouse_x, mouse_y, ctrl_x - 4, ctrl_y - 4, btn_size + 8, btn_size + 8) and 1 or 0) - sp_smooth.next_hover) * lerp_btn
                    local next_hover = draw_min_btn(ctrl_x, ctrl_y, '>|', sp_smooth.next_hover, false)
                    if next_hover and just_pressed then sp_next() end

                    -- song name (right of controls)
                    local text_x = ctrl_x + btn_size + m_pad + 2
                    local text_w = panel_w - (text_x - px) - m_pad
                    local song_text = truncate_text(sp.song, text_w, '')

                    -- elapsed time on the right
                    local elapsed_text = ms_to_time(est_progress)
                    local etw = renderer.measure_text('', elapsed_text)
                    local song_max_w = text_w - etw - 6

                    song_text = truncate_text(sp.song, song_max_w, '')
                    renderer.text(text_x, py + 5, 200, 200, 210, math.floor(220 * alpha), '', nil, song_text)
                    renderer.text(text_x, py + 16, 100, 100, 110, math.floor(150 * alpha), '', nil, truncate_text(sp.artist, song_max_w, ''))

                    -- elapsed time right-aligned
                    renderer.text(px + panel_w - m_pad - etw, py + math.floor((MIN_H - 8) * 0.5), 90, 90, 100, math.floor(140 * alpha), '', nil, elapsed_text)

                    sp_was_mouse = mouse_down
                    return
                end
                --==== FULL LAYOUT =====
                -- fade content during layout transition
                alpha = alpha * sp_smooth_content_alpha

                -- title bg
                renderer.gradient(px, py + 1, panel_w, SP.TITLE_H - 1, math.floor(20 + ar * 0.08), math.floor(18 + ag * 0.08), math.floor(22 + ab * 0.08), math.floor(240 * alpha), 14, 14, 18, math.floor(240 * alpha), false)

                -- title text
                local title = 'catboy  ·  spotify'
                local ttw = renderer.measure_text('', title)
                renderer.text(px + math.floor((panel_w - ttw) * 0.5) + 1, py + 4, 0, 0, 0, math.floor(60 * alpha), '', nil, title)
                renderer.text(px + math.floor((panel_w - ttw) * 0.5), py + 3, ar, ag, ab, math.floor(220 * alpha), '', nil, title)

                -- separator
                renderer.rectangle(px + 8, py + SP.TITLE_H, panel_w - 16, 1, 40, 40, 50, math.floor(120 * alpha))

                if not sp_auth_state.authed then
                    -- not authenticated message
                    local msg = sp_auth_state.status == 'connecting' and 'Connecting...' or 'Not connected'
                    local mw = renderer.measure_text('', msg)
                    local msg_x = px + math.floor((panel_w - mw) * 0.5)
                    local msg_y = py + SP.TITLE_H + 8
                    if sp_auth_state.status == 'connecting' then
                        local now_t = globals.realtime()
                        local ox = 0
                        for i = 1, #msg do
                            local ch = msg:sub(i, i)
                            local t = (math.sin((now_t * 10.0) + (i * 0.5)) + 1) * 0.5
                            local cr = math.floor(100 + 155 * t)
                            local cg = math.floor(100 + 155 * t)
                            local cb = math.floor(110 + 145 * t)
                            renderer.text(msg_x + ox, msg_y, cr, cg, cb, math.floor(220 * alpha), '', nil, ch)
                            ox = ox + renderer.measure_text('', ch)
                        end
                    else
                        renderer.text(msg_x, msg_y, 100, 100, 110, math.floor(180 * alpha), '', nil, msg)
                    end
                    return
                end

                -- body
                local cx = px + SP.PADDING
                local cy = py + SP.TITLE_H + SP.PADDING
                local content_w = panel_w - SP.PADDING * 2

                -- album art
                local art_x = cx
                local art_y = cy
                if sp.album_art then
                    local art_ok, art_err = pcall(sp.album_art.draw, sp.album_art, art_x, art_y, SP.ART, SP.ART, 255, 255, 255, math.floor(255 * alpha))
                    if not art_ok then
                        sp.album_art = nil
                    end
                end
                if not sp.album_art then
                    renderer.rectangle(art_x, art_y, SP.ART, SP.ART, 30, 30, 35, math.floor(200 * alpha))
                    local nw = renderer.measure_text('', '?')
                    renderer.text(art_x + math.floor((SP.ART - nw) / 2), art_y + math.floor(SP.ART / 2) - 6, 60, 60, 70, math.floor(150 * alpha), '', nil, '?')
                end

                -- song info (right of album art)
                local info_x = art_x + SP.ART + SP.PADDING
                local info_w = content_w - SP.ART - SP.PADDING
                local song_text = truncate_text(sp.song, info_w, '')
                local artist_text = truncate_text(sp.artist, info_w, '')

                -- animated gradient text
                local now_t = globals.realtime()
                local function draw_gradient_text(text, tx, ty, r1, g1, b1, r2, g2, b2, a, speed, offset)
                    local chars = utf8_chars(text)
                    local ox = 0
                    for i, ch in ipairs(chars) do
                        local t = (math.sin((now_t * speed) + (i * 0.35) + offset) + 1) * 0.5
                        local cr = math.floor(r1 + (r2 - r1) * t)
                        local cg = math.floor(g1 + (g2 - g1) * t)
                        local cb = math.floor(b1 + (b2 - b1) * t)
                        renderer.text(tx + ox, ty, cr, cg, cb, math.floor(a), '', nil, ch)
                        ox = ox + renderer.measure_text('', ch)
                    end
                end

                draw_gradient_text(song_text, info_x, art_y + 2, 220, 220, 230, ar, ag, ab, 230 * alpha, 2.0, 0)
                draw_gradient_text(artist_text, info_x, art_y + 15, 120, 120, 130, ar, ag, ab, 180 * alpha, 1.5, 3.0)

                -- controls (below song info, right of art)
                local ctrl_y = art_y + 34
                local ctrl_x = info_x
                local menu_open = ui.is_menu_open()
                local lerp_btn = 1 - math.pow(1 - 0.15, ft / base_dt)
                local btn_size = 10
                local btn_gap = 20

                -- helper: draw a control button with smooth hover glow
                local function draw_ctrl_btn(bx, by, label, hover_smooth, is_accent)
                    local hover = menu_open and in_rect(mouse_x, mouse_y, bx - 4, by - 4, btn_size + 8, btn_size + 8)
                    local h = hover_smooth

                    -- base color
                    local br, bg, bb
                    if is_accent then
                        br = math.floor(ar + (255 - ar) * h)
                        bg = math.floor(ag + (255 - ag) * h)
                        bb = math.floor(ab + (255 - ab) * h)
                    else
                        br = math.floor(130 + 125 * h)
                        bg = math.floor(130 + 125 * h)
                        bb = math.floor(140 + 115 * h)
                    end

                    -- glow behind on hover
                    if h > 0.01 then
                        local ga = math.floor(40 * h * alpha)
                        local gr, gg, gb = is_accent and ar or 200, is_accent and ag or 200, is_accent and ab or 210
                        renderer.rectangle(bx - 3, by - 3, btn_size + 6, btn_size + 6, gr, gg, gb, ga)
                    end

                    -- text
                    local tw = renderer.measure_text('', label)
                    renderer.text(bx + math.floor((btn_size - tw) / 2), by - 1, br, bg, bb, math.floor((200 + 55 * h) * alpha), '', nil, label)

                    return hover
                end

                -- prev
                sp_smooth.prev_hover = sp_smooth.prev_hover + ((menu_open and in_rect(mouse_x, mouse_y, ctrl_x - 4, ctrl_y - 4, btn_size + 8, btn_size + 8) and 1 or 0) - sp_smooth.prev_hover) * lerp_btn
                local prev_hover = draw_ctrl_btn(ctrl_x, ctrl_y, '|<', sp_smooth.prev_hover, false)
                if prev_hover and just_pressed then sp_prev() end

                -- play/pause (accent colored, larger feel)
                ctrl_x = ctrl_x + btn_gap
                sp_smooth.pp_hover = sp_smooth.pp_hover + ((menu_open and in_rect(mouse_x, mouse_y, ctrl_x - 4, ctrl_y - 4, btn_size + 8, btn_size + 8) and 1 or 0) - sp_smooth.pp_hover) * lerp_btn
                local pp_label = sp.playing and '||' or '>'
                local pp_hover = draw_ctrl_btn(ctrl_x, ctrl_y, pp_label, math.max(sp_smooth.pp_hover, sp.playing and 0.6 or 0), true)
                if pp_hover and just_pressed then sp_play_pause() end

                -- next
                ctrl_x = ctrl_x + btn_gap
                sp_smooth.next_hover = sp_smooth.next_hover + ((menu_open and in_rect(mouse_x, mouse_y, ctrl_x - 4, ctrl_y - 4, btn_size + 8, btn_size + 8) and 1 or 0) - sp_smooth.next_hover) * lerp_btn
                local next_hover = draw_ctrl_btn(ctrl_x, ctrl_y, '>|', sp_smooth.next_hover, false)
                if next_hover and just_pressed then sp_next() end

                -- volume slider (right side)
                local vol_x = px + panel_w - SP.PADDING - SP.VOL_W
                local vol_y = ctrl_y + 3
                local vol_h = 3

                -- smooth volume fill
                sp_smooth.vol_fill = sp_smooth.vol_fill + (sp.volume - sp_smooth.vol_fill) * lerp_btn
                local vol_fill_px = math.floor(SP.VOL_W * sp_smooth.vol_fill / 100)

                -- volume background
                renderer.rectangle(vol_x, vol_y, SP.VOL_W, vol_h, 35, 35, 45, math.floor(160 * alpha))
                -- volume fill with glow
                if vol_fill_px > 0 then
                    renderer.rectangle(vol_x, vol_y - 1, vol_fill_px, vol_h + 2, ar, ag, ab, math.floor(30 * alpha))
                    renderer.rectangle(vol_x, vol_y, vol_fill_px, vol_h, ar, ag, ab, math.floor(200 * alpha))
                end
                -- volume knob
                local knob_x = vol_x + vol_fill_px
                renderer.rectangle(knob_x - 1, vol_y - 2, 3, vol_h + 4, 220, 220, 230, math.floor(240 * alpha))

                -- volume percentage text (brighten on hover/drag)
                local vol_hover = menu_open and in_rect(mouse_x, mouse_y, vol_x - 4, vol_y - 6, SP.VOL_W + 8, vol_h + 12)
                sp_smooth.vol_bright = sp_smooth.vol_bright + (((vol_hover or sp.vol_dragging) and 1 or 0) - sp_smooth.vol_bright) * (1 - math.pow(1 - 0.15, ft / base_dt))
                local vt_r = math.floor(80 + 160 * sp_smooth.vol_bright)
                local vt_g = math.floor(80 + 160 * sp_smooth.vol_bright)
                local vt_b = math.floor(90 + 160 * sp_smooth.vol_bright)
                local vt_a = math.floor((130 + 100 * sp_smooth.vol_bright) * alpha)

                local vol_text = tostring(math.floor(sp_smooth.vol_fill)) .. '%'
                local vtw = renderer.measure_text('', vol_text)
                renderer.text(vol_x - vtw - 4, ctrl_y, vt_r, vt_g, vt_b, vt_a, '', nil, vol_text)

                -- volume interaction
                if menu_open then
                    local vol_hit = vol_hover
                    if vol_hit and just_pressed then
                        sp.vol_dragging = true
                    end
                    if sp.vol_dragging then
                        if mouse_down then
                            local pct = math.max(0, math.min(1, (mouse_x - vol_x) / SP.VOL_W))
                            sp.volume = math.floor(pct * 100)
                        else
                            sp_set_volume(sp.volume)
                            sp.vol_dragging = false
                        end
                    end
                end

                -- progress bar
                local prog_y = art_y + SP.ART + SP.PADDING
                local prog_w = content_w
                local prog_h = SP.PROG_H

                -- smooth progress
                local prog_pct = sp.duration_ms > 0 and (est_progress / sp.duration_ms) or 0
                local target_prog = prog_w * math.min(1, prog_pct)
                -- fast lerp for smooth scrubbing, slow for playback
                local prog_speed = sp.seek_dragging and 0.4 or 0.08
                local prog_lerp = 1 - math.pow(1 - prog_speed, ft / base_dt)
                sp_smooth.prog = sp_smooth.prog + (target_prog - sp_smooth.prog) * prog_lerp
                local prog_fill = math.floor(sp_smooth.prog)

                -- time labels (brighten on hover/drag)
                local prog_hover = menu_open and in_rect(mouse_x, mouse_y, cx, prog_y - 4, prog_w, prog_h + 8)
                sp_smooth.time_bright = sp_smooth.time_bright + (((prog_hover or sp.seek_dragging) and 1 or 0) - sp_smooth.time_bright) * (1 - math.pow(1 - 0.15, ft / base_dt))
                local time_r = math.floor(100 + 140 * sp_smooth.time_bright)
                local time_g = math.floor(100 + 140 * sp_smooth.time_bright)
                local time_b = math.floor(110 + 140 * sp_smooth.time_bright)
                local time_a = math.floor((160 + 70 * sp_smooth.time_bright) * alpha)

                local elapsed_text = ms_to_time(est_progress)
                local total_text = ms_to_time(sp.duration_ms)
                local ttw2 = renderer.measure_text('', total_text)
                renderer.text(cx, prog_y + prog_h + 3, time_r, time_g, time_b, time_a, '', nil, elapsed_text)
                renderer.text(cx + content_w - ttw2, prog_y + prog_h + 3, time_r, time_g, time_b, time_a, '', nil, total_text)

                -- progress background
                renderer.rectangle(cx, prog_y, prog_w, prog_h, 35, 35, 45, math.floor(140 * alpha))

                -- progress glow (behind the fill) - multi-layer bloom
                if prog_fill > 0 then
                    renderer.rectangle(cx - 2, prog_y - 5, prog_fill + 4, prog_h + 10, ar, ag, ab, math.floor(10 * alpha))
                    renderer.rectangle(cx - 1, prog_y - 4, prog_fill + 2, prog_h + 8, ar, ag, ab, math.floor(18 * alpha))
                    renderer.rectangle(cx, prog_y - 3, prog_fill, prog_h + 6, ar, ag, ab, math.floor(30 * alpha))
                    renderer.rectangle(cx, prog_y - 2, prog_fill, prog_h + 4, ar, ag, ab, math.floor(45 * alpha))
                    renderer.rectangle(cx, prog_y - 1, prog_fill, prog_h + 2, ar, ag, ab, math.floor(60 * alpha))
                end

                -- progress fill
                if prog_fill > 0 then
                    renderer.gradient(cx, prog_y, prog_fill, prog_h, ar, ag, ab, math.floor(180 * alpha), ar, ag, ab, math.floor(255 * alpha), true)
                end

                -- progress head dot
                if prog_fill > 0 then
                    local dot_x = cx + prog_fill
                    -- dot glow layers
                    renderer.rectangle(dot_x - 5, prog_y - 4, 10, prog_h + 8, ar, ag, ab, math.floor(25 * alpha))
                    renderer.rectangle(dot_x - 4, prog_y - 3, 8, prog_h + 6, ar, ag, ab, math.floor(45 * alpha))
                    renderer.rectangle(dot_x - 3, prog_y - 2, 6, prog_h + 4, ar, ag, ab, math.floor(70 * alpha))
                    -- dot itself
                    renderer.rectangle(dot_x - 2, prog_y - 1, 4, prog_h + 2, 240, 240, 250, math.floor(245 * alpha))
                end

                -- progress interaction (seek)
                if menu_open then
                    local prog_hit = in_rect(mouse_x, mouse_y, cx, prog_y - 4, prog_w, prog_h + 8)
                    if prog_hit and just_pressed then
                        sp.seek_dragging = true
                    end
                    if sp.seek_dragging then
                        if mouse_down then
                            local pct = math.max(0, math.min(1, (mouse_x - cx) / prog_w))
                            est_progress = pct * sp.duration_ms
                            sp.progress_ms = est_progress
                            sp_last_progress_sync = globals.realtime()
                        else
                            sp_seek(est_progress)
                            sp.seek_dragging = false
                        end
                    end
                end

                sp_was_mouse = mouse_down
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()
                    utils.event_callback('paint_ui', on_paint_ui, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local custom_killfeed do
            local ref = ref.visuals.custom_killfeed

            local killfeed_entries = { }

            local WEAPON_ICONS = {
                glock = '$', cz75a = ')', p250 = '%', fiveseven = '#',
                deagle = '!', revolver = '*', elite = '"', tec9 = '&',
                hkp2000 = "'", usp_silencer = '(', usp_silencer_off = '`',
                mac10 = ',', mp9 = '-', mp7 = '0', mp5sd = '+',
                ump45 = '/', bizon = '.', p90 = '1',
                galilar = '8', famas = '7', ak47 = '4', m4a1 = '3',
                m4a1_silencer = '2', m4a1_silencer_off = '_',
                sg556 = '5', aug = '6',
                ssg08 = '<', awp = '9', scar20 = ';', g3sg1 = ':',
                nova = '?', xm1014 = 'A', sawedoff = '@', mag7 = 'B',
                m249 = '=', negev = '>',
                hegrenade = 'e', inferno = 'a',
                bayonet = 'K', knife_css = '[', knife_flip = 'O',
                knife_gut = 'P', knife_karambit = 'Q', knife_m9_bayonet = 'R',
                knife_tactical = 'S', knife_falchion = 'N',
                knife_survival_bowie = 'L', knife_butterfly = 'M',
                knife_push = 'T', knife_cord = '\\', knife_canis = ']',
                knife_ursus = 'U', knife_gypsy_jackknife = 'V',
                knife_outdoor = 'W', knife_stiletto = 'Y',
                knife_widowmaker = 'Z', knife_skeleton = 'X',
                knife = 'R', taser = '^',
            }

            local function get_weapon_icon(weapon_name)
                return WEAPON_ICONS[weapon_name] or 'j'
            end

            local fonts = { }
            local cached_size = 0

            local function rebuild_fonts(size)
                if size == cached_size then
                    return
                end

                cached_size = size
                fonts.text = surface.create_font('Segoe UI', size, 400, 0x010)
                fonts.icons = surface.create_font('PastelIcons', size + 4, 400, 0x010 + 0x080)
            end

            local function measure_name(text)
                local w, h = surface.get_text_size(fonts.text, text)
                return w, h
            end

            local function draw_name(x, y, r, g, b, a, text)
                surface.draw_text(x, y, r, g, b, a, fonts.text, text)
            end

            local function measure_icon(text)
                local w, h = surface.get_text_size(fonts.icons, text)
                return w, h
            end

            local function draw_icon(x, y, r, g, b, a, text)
                surface.draw_text(x, y, r, g, b, a, fonts.icons, text)
            end

            local function on_player_death(e)
                local attacker = client.userid_to_entindex(e.attacker)
                local attacked = client.userid_to_entindex(e.userid)

                if attacker == nil or attacked == nil then
                    return
                end

                if attacker == 0 and attacked == 0 then
                    return
                end

                local attacker_name = entity.get_player_name(attacker) or '?'
                local attacked_name = entity.get_player_name(attacked) or '?'

                table.insert(killfeed_entries, 1, {
                    attacker = attacker,
                    attacked = attacked,
                    attacker_name = attacker_name,
                    attacked_name = attacked_name,
                    headshot = e.headshot,
                    weapon = e.weapon,
                    time = 6,
                    alpha = 0,
                })
            end

            local function on_paint_ui()
                cvar.cl_drawhud_force_deathnotices:set_raw_int(-1)

                local me = entity.get_local_player()

                if me == nil then
                    return
                end

                local font_size = ref.size:get()
                rebuild_fonts(font_size)

                local sx, sy = client.screen_size()
                local dt = globals.frametime()
                local row_height = font_size + 8
                local padding = math.floor(font_size * 0.7)
                local spacing = math.floor(font_size * 0.35)
                local height = 120

                for i = #killfeed_entries, 1, -1 do
                    local entry = killfeed_entries[i]

                    if entry.attacker ~= me then
                        entry.time = entry.time - dt
                    end

                    local target_alpha = entry.time <= 0 and 0 or 1
                    entry.alpha = motion.interp(entry.alpha, target_alpha, 0.08)

                    if entry.alpha < 0.01 then
                        table.remove(killfeed_entries, i)
                    end
                end

                for _, entry in ipairs(killfeed_entries) do
                    if entry.alpha < 0.01 then
                        goto continue
                    end

                    local a = entry.alpha
                    local weapon_icon = get_weapon_icon(entry.weapon)
                    local weapon_w = measure_icon(weapon_icon)
                    local attacked_w = measure_name(entry.attacked_name)
                    local attacker_w = measure_name(entry.attacker_name)
                    local headshot_w = entry.headshot and measure_icon('d') or 0
                    local _, icon_h = measure_icon(weapon_icon)

                    local total_w = padding * 2 + attacked_w + headshot_w + weapon_w + attacker_w + spacing * 4
                    local container_x = sx - total_w
                    local container_y = 20 + height

                    local is_local = (entry.attacker == me or entry.attacked == me)

                    local bg_r, bg_g, bg_b, bg_a
                    if is_local then
                        bg_r, bg_g, bg_b, bg_a = ref.bg_active:get()
                    else
                        bg_r, bg_g, bg_b, bg_a = ref.bg_inactive:get()
                    end

                    local half_w = math.floor(total_w / 2)
                    local bg_alpha = math.floor(bg_a * a)

                    surface.draw_filled_gradient_rect(
                        container_x, container_y, half_w, row_height,
                        bg_r, bg_g, bg_b, 0,
                        bg_r, bg_g, bg_b, bg_alpha,
                        true
                    )
                    surface.draw_filled_gradient_rect(
                        container_x + half_w, container_y, total_w - half_w, row_height,
                        bg_r, bg_g, bg_b, bg_alpha,
                        bg_r, bg_g, bg_b, 0,
                        true
                    )

                    local ar, ag, ab, aa = ref.attacker_color:get()
                    local dr, dg, db, da = ref.attacked_color:get()
                    local wr, wg, wb, wa = ref.weapon_color:get()

                    local text_y = container_y + math.floor((row_height - font_size) / 2)
                    local icon_y = container_y + math.floor((row_height - icon_h) / 2)
                    local cx = container_x + padding

                    draw_name(cx, text_y, ar, ag, ab, math.floor(aa * a), entry.attacker_name)
                    cx = cx + attacker_w + spacing

                    draw_icon(cx, icon_y, wr, wg, wb, math.floor(wa * a), weapon_icon)
                    cx = cx + weapon_w + spacing

                    if entry.headshot then
                        local hr, hg, hb, ha = ref.headshot_color:get()
                        draw_icon(cx, icon_y, hr, hg, hb, math.floor(ha * a), 'd')
                    end
                    cx = cx + headshot_w + spacing

                    draw_name(cx, text_y, dr, dg, db, math.floor(da * a), entry.attacked_name)

                    height = height + (row_height + 2) * a

                    ::continue::
                end
            end

            local function on_shutdown()
                cvar.cl_drawhud_force_deathnotices:set_raw_int(0)
            end

            local function on_round_start()
                killfeed_entries = { }
            end

            local function update_event_callbacks(value)
                if not value then
                    cvar.cl_drawhud_force_deathnotices:set_raw_int(0)
                    killfeed_entries = { }
                end

                utils.event_callback(
                    'player_death',
                    on_player_death,
                    value
                )

                utils.event_callback(
                    'paint_ui',
                    on_paint_ui,
                    value
                )

                utils.event_callback(
                    'shutdown',
                    on_shutdown,
                    value
                )

                utils.event_callback(
                    'round_start',
                    on_round_start,
                    value
                )
            end

            local callbacks do
                local function on_enabled(item)
                    update_event_callbacks(item:get())
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end
    end

    local misc = { } do
    local clantag do
            local ref = ref.misc.clantag

            local old_text = nil

            local animation = {
                'c',
                'ca',
                'cat',
                'catb',
                'catbo',
                'catboy',
                'catboy.',
                'catboy.l',
                'catboy.lu',
                'catboy.lua',
                'catboy.lu',
                'catboy.l',
                'catboy.',
                'catboy',
                'catbo',
                'catb',
                'cat',
                'ca',
                'c',
            }

            local function set_clan_tag(text)
                if old_text ~= text then
                    old_text = text

                    client.set_clan_tag(text)

                    client.delay_call(0.3, function()
                        if old_text == text then
                            client.set_clan_tag(text)
                        end
                    end)
                end
            end

            local function unset_clan_tag()
                client.set_clan_tag('')

                client.delay_call(
                    0.3, client.set_clan_tag, ''
                )

                old_text = nil
            end

            local function on_shutdown()
                unset_clan_tag()
            end

            local function on_net_update_start()
                local len = #animation

                local time = globals.curtime() * 3
                local index = (math.floor(time) % len) + 1

                set_clan_tag(animation[index])
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        unset_clan_tag()
                    end

                    utils.event_callback(
                        'shutdown',
                        on_shutdown,
                        value
                    )

                    utils.event_callback(
                        'net_update_start',
                        on_net_update_start,
                        value
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local increase_ladder_movement do
            local ref = ref.misc.increase_ladder_movement

            local MOVETYPE_LADDER = 9

            local function on_setup_command(cmd)
                local me = entity.get_local_player()

                if me == nil then
                    return
                end

                local movetype = entity.get_prop(
                    me, 'm_movetype'
                )

                if movetype ~= MOVETYPE_LADDER then
                    return
                end

                local pitch = client.camera_angles()

				cmd.yaw = round(cmd.yaw)
				cmd.roll = 0

				if cmd.forwardmove > 0 and pitch < 45 then
					cmd.pitch = 89
					cmd.in_moveright, cmd.in_moveleft, cmd.in_forward, cmd.in_back = 1, 0, 0, 1

					if cmd.sidemove == 0 then cmd.yaw = cmd.yaw + 90 end
					if cmd.sidemove < 0 then cmd.yaw = cmd.yaw + 150 end
					if cmd.sidemove > 0 then cmd.yaw = cmd.yaw + 30 end
				elseif cmd.forwardmove < 0 then
					cmd.pitch = 89
					cmd.in_moveleft, cmd.in_moveright, cmd.in_forward, cmd.in_back = 1, 0, 1, 0

					if cmd.sidemove == 0 then cmd.yaw = cmd.yaw + 90 end
					if cmd.sidemove > 0 then cmd.yaw = cmd.yaw + 150 end
					if cmd.sidemove < 0 then cmd.yaw = cmd.yaw + 30 end
				end
            end

            local callbacks do
                local function on_enabled(item)
                    utils.event_callback(
                        'setup_command',
                        on_setup_command,
                        item:get()
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local animation_breaker do
            local ref = ref.misc.animation_breaker

            local MOVETYPE_WALK = 2

            local ANIMATION_LAYER_MOVEMENT_MOVE = 6
            local ANIMATION_LAYER_LEAN = 12

            local function update_onground(player)
                if localplayer.is_onground then
                    local value = ref.onground_legs:get()

                    if value == 'Static' then
                        override.set(software.antiaimbot.other.leg_movement, 'Always slide')
                        entity.set_prop(player, 'm_flPoseParameter', 0, 0)

                        return
                    end

                    if value == 'Break' then
                        override.set(software.antiaimbot.other.leg_movement, 'Always slide')
                        entity.set_prop(player, 'm_flPoseParameter', client.random_float(0.1, 1), 0)
                        return
                    end

                    if value == 'Alien' then
                        override.set(software.antiaimbot.other.leg_movement, 'Never slide')
                        entity.set_prop(player, 'm_flPoseParameter', 0, 7)
                        local entity_info = c_entity(player)

                        if entity_info == nil then
                            return
                        end

                        local layer_move = entity_info:get_anim_overlay(
                            ANIMATION_LAYER_MOVEMENT_MOVE
                        )

                        if layer_move == nil then
                            return
                        end

                        layer_move.weight =  math.random(0, 5)/2

                        return
                    end
                end

                override.unset(software.antiaimbot.other.leg_movement)
            end

            local function update_in_air(player)
                local value = ref.in_air_legs:get()

                if value == 'off' then
                    return
                end

                if localplayer.is_onground then
                    return
                end

                if value == 'Static' then
                    entity.set_prop(player, 'm_flPoseParameter', 0.5, 6)

                    return
                end

                if value == 'Alien' then
                    if not localplayer.is_moving then
                        return
                    end

                    local entity_info = c_entity(player)

                    if entity_info == nil then
                        return
                    end

                    local layer_move = entity_info:get_anim_overlay(
                        ANIMATION_LAYER_MOVEMENT_MOVE
                    )

                    if layer_move == nil then
                        return
                    end

                    layer_move.weight = 1

                    return
                end
            end

            local function update_earthquake(player)
                if not ref.freeburger:get() then
                    return
                end

                local entity_info = c_entity(player)

                if entity_info == nil then
                    return
                end

                local layer_lean = entity_info:get_anim_overlay(
                    ANIMATION_LAYER_LEAN
                )

                if layer_lean == nil then
                    return
                end

                layer_lean.weight = utils.random_float(0, 1)
            end

            local function update_body_lean(player)
                local value = ref.adjust_lean:get()

                if value == 0 then
                    return
                end

                local entity_info = c_entity(player)

                if entity_info == nil then
                    return
                end

                local layer_lean = entity_info:get_anim_overlay(
                    ANIMATION_LAYER_LEAN
                )

                if layer_lean == nil then
                    return
                end

                local self = entity.get_local_player()
                if not self or not entity.is_alive(self) then
                    return
                end

                local x_velocity = entity.get_prop(self, "m_vecVelocity[0]")

                if math.abs(x_velocity) >= 3 then
                    layer_lean.weight = value * 2
                end
            end

            local function update_perfect(player)
                if not ref.perfect:get() then
                    return
                end

                local slider_value = ref.perfect_slider:get()

                entity.set_prop(player, 'm_flPoseParameter', math.random(slider_value, 10) / 10, 3)
                entity.set_prop(player, 'm_flPoseParameter', math.random(slider_value, 10) / 10, 7)
                entity.set_prop(player, 'm_flPoseParameter', math.random(slider_value, 10) / 10, 6)
            end

            local function update_pitch_on_land(player)
                if not ref.pitch_on_land:get() then
                    return
                end

                if not localplayer.is_onground then
                    return
                end

                local entity_info = c_entity(player)

                if entity_info == nil then
                    return
                end

                local animstate = entity_info:get_anim_state()

                if animstate == nil or not animstate.hit_in_ground_animation then
                    return
                end

                entity.set_prop(player, 'm_flPoseParameter', 0.5, 12)
            end

            local function on_pre_render()
                local me = entity.get_local_player()

                if me == nil then
                    return
                end

                local movetype = entity.get_prop(
                    me, 'm_movetype'
                )

                if movetype == MOVETYPE_WALK then
                    update_onground(me)
                    update_in_air(me)
                    update_pitch_on_land(me)
                    update_perfect(me)
                end

                update_body_lean(me)
                update_earthquake(me)
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        override.unset(software.antiaimbot.other.leg_movement)
                    end

                    utils.event_callback(
                        'pre_render',
                        on_pre_render,
                        value
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local walking_on_quick_peek do
            local ref = ref.misc.walking_on_quick_peek

            local MOVETYPE_WALK = 2

            local IN_FORWARD   = bit.lshift(1, 3)
            local IN_BACK      = bit.lshift(1, 4)
            local IN_MOVELEFT  = bit.lshift(1, 9)
            local IN_MOVERIGHT = bit.lshift(1, 10)

            local function on_finish_command(e)
                if not software.is_quick_peek_assist() then
                    return
                end

                local me = entity.get_local_player()

                if me == nil then
                    return
                end

                local movetype = entity.get_prop(
                    me, 'm_movetype'
                )

                if movetype ~= MOVETYPE_WALK then
                    return
                end

                local cmd = iinput.get_usercmd(
                    0, e.command_number
                )

                if cmd == nil then
                    return
                end

                cmd.buttons = bit.band(cmd.buttons, bit.bnot(IN_FORWARD))
                cmd.buttons = bit.band(cmd.buttons, bit.bnot(IN_BACK))
                cmd.buttons = bit.band(cmd.buttons, bit.bnot(IN_MOVELEFT))
                cmd.buttons = bit.band(cmd.buttons, bit.bnot(IN_MOVERIGHT))
            end

            local callbacks do
                local function on_enabled(item)
                    utils.event_callback(
                        'finish_command',
                        on_finish_command,
                        item:get()
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local discord_rpc do
            local ref = ref.misc.discord_rpc
            local named_pipes = require 'gamesense/named_pipes'

            local native_GetNetChannelInfo = vtable_bind("engine.dll", "VEngineClient014", 78, "void*(__thiscall*)(void*)")
            local native_GetAddress = vtable_thunk(1, "const char*(__thiscall*)(void*)")
            local native_IsLoopback = vtable_thunk(6, "bool(__thiscall*)(void*)")
            local native_IsInGame = vtable_bind("engine.dll", "VEngineClient014", 26, "bool(__thiscall*)(void*)")
            local native_IsConnected = vtable_bind("engine.dll", "VEngineClient014", 27, "bool(__thiscall*)(void*)")
            local native_IsConnecting = vtable_bind("engine.dll", "VEngineClient014", 28, "bool(__thiscall*)(void*)")

            local js = panorama.open()
            local LobbyAPI, PartyListAPI, GameStateAPI, FriendsListAPI = js.LobbyAPI, js.PartyListAPI, js.GameStateAPI, js.FriendsListAPI

            local OPCODE_HANDSHAKE = 0
            local OPCODE_FRAME = 1
            local OPCODE_CLOSE = 2
            local OPCODE_PING = 3
            local OPCODE_PONG = 4

            local GAMEPHASE_WARMUP = 0
            local GAMEPHASE_MATCH = 1
            local GAMEPHASE_FIRST_HALF = 2
            local GAMEPHASE_SECOND_HALF = 3
            local GAMEPHASE_HALFTIME = 4
            local GAMEPHASE_END_OF_MATCH = 5

            local EVENT_KEYS = {
                join_game = "ACTIVITY_JOIN",
                spectate_game = "ACTIVITY_SPECTATE",
                join_request = "ACTIVITY_JOIN_REQUEST"
            }

            local EVENT_LOOKUP = {
                ERRORED = "error"
            }

            local function drpc_deep_compare(tbl1, tbl2)
                if tbl1 == tbl2 then return true end
                if type(tbl1) == "table" and type(tbl2) == "table" then
                    for key1, value1 in pairs(tbl1) do
                        local value2 = tbl2[key1]
                        if value2 == nil then return false end
                        if value1 ~= value2 then
                            if type(value1) == "table" and type(value2) == "table" then
                                if not drpc_deep_compare(value1, value2) then return false end
                            else
                                return false
                            end
                        end
                    end
                    for key2, _ in pairs(tbl2) do
                        if tbl1[key2] == nil then return false end
                    end
                    return true
                end
                return false
            end

            local function drpc_table_dig(tbl, ...)
                local keys = {...}
                for i = 1, #keys do
                    if tbl == nil then return nil end
                    tbl = tbl[keys[i]]
                end
                return tbl or nil
            end

            local function drpc_generate_nonce()
                local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
                return (string.gsub(template, '[xy]', function(c)
                    local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
                    return string.format('%x', v)
                end))
            end

            local function drpc_pack_int32le(int)
                return ffi.string(ffi.cast("const char*", ffi.new("uint32_t[1]", int)), 4)
            end

            local function drpc_unpack_int32le(str)
                return tonumber(ffi.cast("uint32_t*", ffi.cast("const char*", str))[0])
            end

            local function drpc_encode_str(opcode, str)
                return drpc_pack_int32le(opcode) .. drpc_pack_int32le(str:len()) .. str
            end

            local function drpc_read_data(pipe)
                local header = pipe:read(8)
                if header == nil then return end
                local opcode = drpc_unpack_int32le(header:sub(1, 4))
                local len = drpc_unpack_int32le(header:sub(5, 8))
                local raw = pipe:read(len)
                if raw == nil then return end
                return opcode, json.parse(raw)
            end

            -- localization
            local drpc_localize_impl = panorama.loadstring([[
                return {
                    localize: (str, params) => {
                        if(params == null)
                            return $.Localize(str)
                        var panel = $.CreatePanel("Panel", $.GetContextPanel(), "")
                        for(key in params) {
                            panel.SetDialogVariable(key, params[key])
                        }
                        var result = $.Localize(str, panel)
                        panel.DeleteAsync(0.0)
                        return result
                    }
                }
            ]])().localize

            local drpc_localize_cache = {}
            local function drpc_localize(str, params)
                if str == nil then return "" end
                if drpc_localize_cache[str] == nil then drpc_localize_cache[str] = {} end
                local params_key = params ~= nil and json.stringify(params) or true
                if drpc_localize_cache[str][params_key] == nil then
                    drpc_localize_cache[str][params_key] = drpc_localize_impl(str, params)
                end
                return drpc_localize_cache[str][params_key]
            end

            local drpc_localize_lookup = setmetatable({
                ["Practice With Bots"] = "Local Server",
                ["Offline"] = "Local Server",
                ["Main Menu"] = "In Main Menu",
                ["Playing CS:GO"] = "In Game"
            }, {
                __index = function(tbl, key)
                    tbl[key] = key
                    return key
                end
            })

            local drpc_ts_offset = panorama.loadstring("return Date.now()/1000")() - globals.realtime()
            local function drpc_get_unix_timestamp()
                return math.floor(drpc_ts_offset + globals.realtime() + 0.5)
            end

            local function drpc_table_elements(tbl)
                local out = {}
                for i = 1, #tbl do out[tbl[i]] = true end
                return out
            end

            local function drpc_localize_mapname(mapname)
                local token = GameStateAPI.GetMapDisplayNameToken(mapname)
                if mapname == token then return mapname end
                return drpc_localize(token)
            end

            local function drpc_clean_mapname(mapname)
                if mapname:find("ag_texture") then return "aim_ag_texture2"
                elseif mapname:find("dust2") then return "de_dust2"
                elseif mapname:find("dust") then return "de_dust"
                elseif mapname:find("mirage") then return "de_mirage"
                end
                return mapname:gsub("_scrimmagemap$", "")
            end

            local function drpc_title_case(str)
                return str:gsub("%u%u+", function(s) return s:sub(1, 1) .. s:sub(2, -1):lower() end)
            end

            -- rpc client
            local rpc_pipe = nil
            local rpc_open = false
            local rpc_ready = false
            local rpc_activity = nil
            local rpc_activity_prev = nil
            local rpc_request_callbacks = {}
            local rpc_failed_images = {}
            local rpc_event_handlers_subscribed = {}
            local rpc_client_id = "1489745773770838157"
            local rpc_last_update = 0
            local rpc_next_connect = globals.realtime() + 5
            local rpc_timestamp_delta_max = 300
            local rpc_status = "Idle"

            local SERVER_MATCH = "^" .. drpc_localize("SFUI_Scoreboard_ServerName", {s1 = "(.*)"}) .. "$"
            local MATCHMAKING_MATCH = drpc_localize("SFUI_PlayMenu_Online"):gsub(".", function(c) return string.format("[%s%s]", c:lower(), c:upper()) end)

            local function rpc_set_status(status)
                rpc_status = status
                logging_system.default('Discord RPC: ' .. status)
            end

            local function rpc_write(opcode, str)
                if rpc_pipe ~= nil then
                    local success, res = pcall(rpc_pipe.write, rpc_pipe, drpc_encode_str(opcode, str))
                    if not success then
                        rpc_pipe = nil
                        rpc_open = false
                        rpc_ready = false
                        rpc_set_status('Disconnected (write error)')
                    else
                        return true
                    end
                end
            end

            local function rpc_request(cmd, args, evt, callback)
                local args_text = args == nil and "" or string.format('"args":%s,', json.stringify(args))
                local evt_text = evt == nil and "" or string.format('"evt":%s,', json.stringify(evt))
                local nonce = drpc_generate_nonce()
                local json_str = string.format('{"cmd":%s,%s%s"nonce":%s}', json.stringify(cmd), args_text, evt_text, json.stringify(nonce))
                if callback ~= nil then
                    rpc_request_callbacks[nonce] = callback
                end
                rpc_write(OPCODE_FRAME, json_str)
            end

            local function rpc_set_activity(activity)
                rpc_activity = activity

                if rpc_timestamp_delta_max > 0 then
                    if type(drpc_table_dig(rpc_activity, "timestamps", "start")) == "number" and type(drpc_table_dig(rpc_activity_prev, "timestamps", "start")) == "number" then
                        local delta = math.abs(rpc_activity_prev.timestamps["start"] - rpc_activity.timestamps["start"])
                        if delta < rpc_timestamp_delta_max then
                            rpc_activity.timestamps["start"] = rpc_activity_prev.timestamps["start"]
                        end
                    end
                    if type(drpc_table_dig(rpc_activity, "timestamps", "end")) == "number" and type(drpc_table_dig(rpc_activity_prev, "timestamps", "end")) == "number" then
                        local delta = math.abs(rpc_activity_prev.timestamps["end"] - rpc_activity.timestamps["end"])
                        if delta < rpc_timestamp_delta_max then
                            rpc_activity.timestamps["end"] = rpc_activity_prev.timestamps["end"]
                        end
                    end
                end

                if rpc_ready and not drpc_deep_compare(rpc_activity, rpc_activity_prev) then
                    local images_check
                    if rpc_activity ~= nil and rpc_activity.assets ~= nil and (rpc_activity.assets.small_image ~= nil or rpc_activity.assets.large_image ~= nil) then
                        images_check = {
                            small_image = rpc_activity.assets.small_image,
                            large_image = rpc_activity.assets.large_image
                        }
                    end

                    rpc_request("SET_ACTIVITY", {
                        pid = 4,
                        activity = rpc_activity
                    }, nil, function(response)
                        if images_check ~= nil and response.evt == json.null then
                            for key, value in pairs(images_check) do
                                if response.data.assets[key] == nil and not rpc_failed_images[value] then
                                    rpc_failed_images[value] = true
                                end
                            end
                        end
                    end)
                    rpc_activity_prev = rpc_activity
                end
            end

            local function rpc_connect()
                if rpc_pipe == nil then
                    local success, pipe, err
                    for i = 0, 10 do
                        success, pipe = pcall(named_pipes.open_pipe, "\\\\?\\pipe\\discord-ipc-" .. i)
                        if success then break end
                        if err == nil or pipe ~= "Failed to open pipe: File not found" then
                            err = pipe
                        end
                    end

                    if success then
                        rpc_pipe = pipe
                        rpc_open = true
                        rpc_ready = false
                        rpc_set_status('Connecting...')
                        rpc_write(OPCODE_HANDSHAKE, string.format('{"v":1,"client_id":%s}', json.stringify(rpc_client_id)))
                    else
                        local reason = err and err:gsub("^Failed to open pipe: ", "") or "Unknown"
                        rpc_set_status('Connection failed: ' .. reason)
                        rpc_next_connect = globals.realtime() + 5
                    end
                end
            end

            local function rpc_close()
                if rpc_pipe ~= nil then
                    if rpc_ready then
                        rpc_request("SET_ACTIVITY", {
                            pid = 4,
                            activity = nil
                        })
                    end
                    rpc_write(OPCODE_CLOSE, string.format('{"v":1,"client_id":%s}', json.stringify(rpc_client_id)))
                    pcall(named_pipes.close_pipe, rpc_pipe)
                    rpc_pipe = nil
                    rpc_open = false
                    rpc_ready = false
                    rpc_activity = nil
                    rpc_activity_prev = nil
                    rpc_set_status('Disconnected')
                end
            end

            local function rpc_update_event_handlers()
                for event_key, event_name in pairs(EVENT_KEYS) do
                    if not rpc_event_handlers_subscribed[event_key] then
                        rpc_request("SUBSCRIBE", nil, event_name)
                        rpc_event_handlers_subscribed[event_key] = true
                    end
                end
            end

            local function rpc_process_messages()
                if rpc_pipe == nil then return end

                for i = 1, 100 do
                    local success, opcode, data = pcall(drpc_read_data, rpc_pipe)

                    if not success then
                        rpc_pipe = nil
                        rpc_open = false
                        rpc_ready = false
                        rpc_next_connect = globals.realtime() + 5
                        rpc_set_status('Disconnected (read error)')
                        return
                    elseif opcode == nil then
                        break
                    else
                        if opcode == OPCODE_FRAME and data.cmd == "DISPATCH" then
                            if data.evt == "READY" then
                                rpc_update_event_handlers()
                                rpc_ready = true
                                local username = drpc_table_dig(data, "data", "user", "username") or "Unknown"
                                local discriminator = drpc_table_dig(data, "data", "user", "discriminator") or "0"
                                rpc_set_status('Connected as ' .. username .. '#' .. discriminator)
                            end
                        elseif opcode == OPCODE_FRAME then
                            local callback = rpc_request_callbacks[data.nonce]
                            if callback ~= nil then
                                rpc_request_callbacks[data.nonce] = nil
                                callback(data)
                            end
                        elseif opcode == OPCODE_PING then
                            rpc_write(OPCODE_PONG, "")
                        elseif opcode == OPCODE_CLOSE then
                            rpc_pipe = nil
                            rpc_open = false
                            rpc_ready = false
                            rpc_next_connect = globals.realtime() + 5
                            rpc_set_status('Disconnected (remote close)')
                        end
                    end
                end
            end

            -- rich presence builder
            local function update_rich_presence()
                local activity = {
                    details = "dev build rawr!~ >w<",
                    state = "Playing",
                    assets = {
                        large_image = "catboy_logo",
                        large_text = "catboy.lua"
                    },
                    instance = true
                }

                local mapname = globals.mapname()
                if mapname ~= nil then
                    local server_name = (GameStateAPI.GetServerName() or ""):gsub("^Server:%s*", "")
                    if server_name == "" then
                        local nci = native_GetNetChannelInfo()
                        if nci ~= nil and native_IsLoopback(nci) then
                            server_name = "Local Server"
                        else
                            server_name = "Unknown Server"
                        end
                    end

                    local score_text = ""
                    local local_player = entity.get_local_player()
                    if local_player ~= nil then
                        local team = entity.get_prop(local_player, "m_iTeamNum")
                        local primary_team = team == 2 and "TERRORIST" or "CT"
                        local secondary_team = team == 2 and "CT" or "TERRORIST"

                        local success, score_data = pcall(function()
                            return json.parse(tostring(GameStateAPI.GetScoreDataJSO()))
                        end)

                        if success and score_data and score_data.teamdata and score_data.teamdata[primary_team] and score_data.teamdata[secondary_team] then
                            score_text = string.format(" [%d:%d]", score_data.teamdata[primary_team].score, score_data.teamdata[secondary_team].score)
                        end
                    end

                    activity.state = server_name .. score_text
                elseif native_IsConnecting() then
                    activity.state = "Connecting..."
                else
                    activity.state = "In Main Menu"
                end

                rpc_set_activity(activity)
            end

            local function drpc_force_update()
                rpc_last_update = 0
            end

            local function on_paint_ui()
                rpc_process_messages()

                local realtime = globals.realtime()
                if not rpc_open and realtime > rpc_next_connect then
                    rpc_next_connect = realtime
                    rpc_connect()
                elseif rpc_open and not rpc_ready and realtime > rpc_next_connect + 150 then
                    rpc_set_status('Connection timed out')
                    rpc_next_connect = rpc_next_connect + 150 + 30
                    rpc_close()
                elseif rpc_open and rpc_ready then
                    if realtime - rpc_last_update > 1 then
                        rpc_last_update = realtime
                        update_rich_presence()
                    end
                end
            end

            local function on_shutdown()
                if rpc_open then
                    rpc_close()
                end
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    utils.event_callback('paint_ui', on_paint_ui, value)
                    utils.event_callback('player_death', drpc_force_update, value)
                    utils.event_callback('bomb_planted', drpc_force_update, value)
                    utils.event_callback('round_start', drpc_force_update, value)
                    utils.event_callback('round_end', drpc_force_update, value)
                    utils.event_callback('buytime_ended', drpc_force_update, value)
                    utils.event_callback('cs_game_disconnected', drpc_force_update, value)
                    utils.event_callback('cs_win_panel_match', drpc_force_update, value)
                    utils.event_callback('cs_match_end_restart', drpc_force_update, value)
                    utils.event_callback('shutdown', on_shutdown, value)

                    if value then
                        rpc_set_status('Waiting to connect...')
                        rpc_next_connect = globals.realtime() + 1
                    else
                        if rpc_open then
                            rpc_close()
                        end
                        rpc_status = 'Idle'
                    end
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end
    end

    local damage_indicator do
        local ref = ref.visuals.damage_indicator

        local ref_minimum_damage = ui.reference(
            'Rage', 'Aimbot', 'Minimum damage'
        )

        local ref_override_damage = {
            ui.reference('Rage', 'Aimbot', 'Minimum damage override')
        }

        local font_flags = {
            ['Default'] = '',
            ['Small'] = '-',
            ['Bold'] = 'b'
        }

        local function is_minimum_damage_override()
            return ui.get(ref_override_damage[1])
                and ui.get(ref_override_damage[2])
        end

        local function get_flags()
            return font_flags[ref.font:get()] or ''
        end

        local function get_aimbot_damage(override)
            if override then
                return ui.get(ref_override_damage[3])
            end

            return ui.get(ref_minimum_damage)
        end

        local function get_render_damage(override)
            local damage = get_aimbot_damage(override)

            if damage == 0 then
                return 'AUTO'
            end

            if damage > 100 then
                return string.format(
                    '+%d', damage - 100
                )
            end

            return tostring(damage)
        end

        local function on_paint_ui()
            local me = entity.get_local_player()

            if me == nil or not entity.is_alive(me) then
                return
            end

            local screen_size = vector(
                client.screen_size()
            )

            local position = screen_size * 0.5
            local offset = ref.offset:get()

            position.x = position.x + offset
            position.y = position.y - offset

            local r, g, b, a = ref.inactive_color:get()

            local is_override = is_minimum_damage_override()
            local flags, text = get_flags(), get_render_damage(is_override)

            if ref.only_if_active:get() and not is_override then
                return
            end

            if is_override then
                r, g, b, a = ref.active_color:get()
            end

            if a <= 0 then
                return
            end

            local text_size = vector(
                renderer.measure_text(flags, text)
            )

            position.y = position.y - text_size.y

            renderer.text(
                position.x,
                position.y,
                r, g, b, a,
                flags, nil, text
            )
        end

        local function update_event_callbacks(value)
            utils.event_callback(
                'paint_ui',
                on_paint_ui,
                value
            )
        end

        local callbacks do
            local function on_enabled(item)
                update_event_callbacks(item:get())
            end

            ref.enabled:set_callback(
                on_enabled, true
            )
        end
    end

    local enhance_grenade_release do
        local ref = ref.misc.enhance_grenade_release

        local ref_grenade_release = {
            ui.reference('Misc', 'Miscellaneous', 'Automatic grenade release')
        }

        local function get_weapon_type(weapon)
            local weapon_info = csgo_weapons(weapon)

            if weapon_info == nil then
                return nil
            end

            local weapon_index = weapon_info.idx

            if weapon_index == 44 then
                return 'HE Grenade'
            end

            if weapon_index == 45 then
                return 'Smoke Grenade'
            end

            if weapon_index == 48 then
                return 'Molotov'
            end

            return nil
        end

        local function is_double_tap_active()
            return software.is_double_tap_active()
                and not software.is_duck_peek_assist()
        end

        local function should_disable(weapon)
            if ref.only_with_dt:get() then
                local is_double_tap = (
                    is_double_tap_active()
                    and exploit.get().shift
                )

                if not is_double_tap then
                    return true
                end
            end

            local weapon_type = get_weapon_type(weapon)

            if weapon_type == nil then
                return false
            end

            return ref.disablers:get(
                weapon_type
            )
        end

        local function on_shutdown()
            override.unset(ref_grenade_release[1])
        end

        local function on_paint_ui()
            override.unset(ref_grenade_release[1])
        end

        local function on_setup_command(cmd)
            local me = entity.get_local_player()

            if me == nil then
                return
            end

            local weapon = entity.get_player_weapon(me)

            if weapon == nil then
                return
            end

            if should_disable(weapon) then
                override.set(ref_grenade_release[1], false)
            end
        end

        local function update_event_callbacks(value)
            if not value then
                override.unset(ref_grenade_release[1])
            end

            utils.event_callback(
                'shutdown',
                on_shutdown,
                value
            )

            utils.event_callback(
                'paint_ui',
                on_paint_ui,
                value
            )

            utils.event_callback(
                'setup_command',
                on_setup_command,
                value
            )
        end

        local callbacks do
            local function on_enabled(item)
                update_event_callbacks(item:get())
            end

            ref.enabled:set_callback(
                on_enabled, true
            )
        end
    end

    local fps_optimize do
        local ref = ref.misc.fps_optimize

        local changed = false

        local tree = { } do
            local function wrap(convar, value)
                local item = { }

                item.convar = convar
                item.old_value = nil
                item.new_value = value

                return item
            end

            tree['Blood'] = {
                wrap(cvar.violence_hblood, 0)
            }

            tree['Bloom'] = {
                wrap(cvar.mat_disable_bloom, 1)
            }

            tree['Decals'] = {
                wrap(cvar.r_drawdecals, 0)
            }

            tree['Shadows'] = {
                wrap(cvar.r_shadows, 0),
                wrap(cvar.cl_csm_static_prop_shadows, 0),
                wrap(cvar.cl_csm_shadows, 0),
                wrap(cvar.cl_csm_world_shadows, 0),
                wrap(cvar.cl_foot_contact_shadows, 0),
                wrap(cvar.cl_csm_viewmodel_shadows, 0),
                wrap(cvar.cl_csm_rope_shadows, 0),
                wrap(cvar.cl_csm_sprite_shadows, 0),
                wrap(cvar.cl_csm_translucent_shadows, 0),
                wrap(cvar.cl_csm_entity_shadows, 0),
                wrap(cvar.cl_csm_world_shadows_in_viewmodelcascad, 0)
            }

            tree['Sprites'] = {
                wrap(cvar.r_drawsprites, 0)
            }

            tree['Particles'] = {
                wrap(cvar.r_drawparticles, 0)
            }

            tree['Ropes'] = {
                wrap(cvar.r_drawropes, 0)
            }

            tree['Dynamic lights'] = {
                wrap(cvar.mat_disable_fancy_blending, 1)
            }

            tree['Map details'] = {
                wrap(cvar.func_break_max_pieces, 0),
                wrap(cvar.props_break_max_pieces, 0)
            }

            tree['Weapon effects'] = {
                wrap(cvar.muzzleflash_light, 0),
                wrap(cvar.r_drawtracers_firstperson, 0)
            }
        end

        local function should_update()
            if ref.always_on:get() then
                return true
            end

            if ref.detections:get 'Peeking' and localplayer.is_peeking then
                return true
            end

            if ref.detections:get 'Hit flag' then
                local enemies = entity.get_players(true)

                for i = 1, #enemies do
                    local enemy = enemies[i]

                    local esp_data = entity.get_esp_data(enemy)

                    if esp_data == nil then
                        goto continue
                    end

                    if bit.band(esp_data.flags, bit.lshift(1, 11)) ~= 0 then
                        return true
                    end

                    ::continue::
                end
            end

            return false
        end

        local function restore_convars()
            if not changed then
                return
            end

            for _, v in pairs(tree) do
                for i = 1, #v do
                    local item = v[i]
                    local convar = item.convar

                    if item.old_value == nil then
                        goto continue
                    end

                    convar:set_int(item.old_value)
                    item.old_value = nil

                    ::continue::
                end
            end

            changed = false
        end

        local function update_convars()
            if changed then
                return
            end

            local values = ref.list:get()

            for i = 1, #values do
                local value = values[i]
                local items = tree[value]

                for j = 1, #items do
                    local item = items[j]
                    local convar = item.convar

                    if convar == nil or item.old_value ~= nil then
                        goto continue
                    end

                    item.old_value = convar:get_int()
                    convar:set_int(item.new_value)

                    ::continue::
                end
            end

            changed = true
        end

        local function on_shutdown()
            restore_convars()
        end

        local function on_net_update_end()
            if not should_update() then
                return restore_convars()
            end

            update_convars()
        end

        local callbacks do
            local function on_list(item)
                restore_convars()
                update_convars()
            end

            local function on_enabled(item)
                local value = item:get()

                if value then
                    ref.list:set_callback(on_list, true)
                else
                    ref.list:unset_callback(on_list)
                end

                if not value then
                    restore_convars()
                end

                utils.event_callback(
                    'shutdown',
                    on_shutdown,
                    value
                )

                utils.event_callback(
                    'net_update_end',
                    on_net_update_end,
                    value
                )
            end

            ref.enabled:set_callback(
                on_enabled, true
            )
        end
    end

    local automatic_purchase do
        local ref = ref.misc.automatic_purchase

        local mp_afterroundmoney = cvar.mp_afterroundmoney

        local primary_items = {
            ['AWP'] = 'awp',
            ['Scout'] = 'ssg08',
            ['G3SG1 / SCAR-20'] = 'scar20'
        }

        local secondary_items = {
            ['P250'] = 'p250',
            ['Elites'] = 'elite',
            ['Five-seven / Tec-9 / CZ75'] = 'fn57',
            ['Deagle / Revolver'] = 'deagle'
        }

        local equipment_items = {
            ['Kevlar'] = 'vest',
            ['Kevlar + Helmet'] = 'vesthelm',
            ['Defuse kit'] = 'defuser',
            ['HE'] = 'hegrenade',
            ['Smoke'] = 'smokegrenade',
            ['Molotov'] = 'molotov',
            ['Taser'] = 'taser'
        }

        local function should_buy()
            local me = entity.get_local_player()

            if me == nil then
                return false
            end

            local account = entity.get_prop(
                me, 'm_iAccount'
            )

            if ref.ignore_pistol_round:get() then
                if account <= 1000 then
                    return false
                end
            end

            if ref.only_16k:get() then
                local after_round_money = mp_afterroundmoney:get_int()

                return account >= 16000
                    or after_round_money >= 16000
            end

            return true
        end

        local function should_buy_reserved()
            local me = entity.get_local_player()

            if me == nil then
                return false
            end

            local weapons = utils.get_player_weapons(me)

            for i = 1, #weapons do
                local weapon = weapons[i]

                local weapon_info = csgo_weapons(weapon)

                if weapon_info == nil then
                    goto continue
                end

                local weapon_idx = weapon_info.idx

                if weapon_idx == 9 then
                    return false
                end

                ::continue::
            end

            return true
        end

        local function buy_primary(list)
            local item = primary_items[
                ref.primary:get()
            ]

            if item == nil then
                return
            end

            if item == 'awp' then
                local function on_awp()
                    if not should_buy_reserved() then
                        return
                    end

                    local reserv = primary_items[
                        ref.alternative:get()
                    ]

                    if reserv == nil then
                        return
                    end

                    client.exec('buy ' .. reserv)
                end

                local duration = client.latency() + 0.15

                client.delay_call(duration, on_awp)
            end

            table.insert(list, item)
        end

        local function buy_secondary(list)
            local item = secondary_items[
                ref.secondary:get()
            ]

            if item ~= nil then
                table.insert(list, item)
            end
        end

        local function buy_equipment(list)
            local values = ref.equipment:get()

            for i = 1, #values do
                local value = equipment_items[
                    values[i]
                ]

                if value ~= nil then
                    table.insert(list, value)
                end
            end
        end

        local function process_buy()
            if not should_buy() then
                return
            end

            local list = { }

            buy_primary(list)
            buy_secondary(list)
            buy_equipment(list)

            local command = ''

            for i = 1, #list do
                local item = list[i]

                command = command .. string.format(
                    'buy %s;', item
                )
            end

            if command ~= '' then
                client.exec(command)
            end
        end

        local function on_round_prestart()
            client.delay_call(client.latency() + 0.125, process_buy)
        end

        local callbacks do
            local function on_enabled(item)
                utils.event_callback(
                    'round_prestart',
                    on_round_prestart,
                    item:get()
                )
            end

            ref.enabled:set_callback(
                on_enabled, true
            )
        end
    end

    local killsay do
        local ref = ref.misc.killsay

        local killsay_messages = {
        "you're cute yknow :3",
        "i'd love to cuddle you <3",
        ">:3",
        "NYYYAAAAAA!!!~~~",
        "hii daddy~ >w<",
        "soooorry =w=",
        "nice try <3",
        "meow  (=^･ω･^=)ﾉ",
        "purr~ (˘ω˘)",
        "uwu what's this? >w<",
        "rawr x3",
        "s-s-senpai noticed me!! >w<",
        "i'm not a cat, i'm a catboy!! >w<",
        "you just got pounced on! >:3",
        "i hope you like catboys, because you just got killed by one! >:3",
        "purrfect shot! >w<",
        "nyaa~ you just got rekt! >w<",
        "𝕒𝕗𝕥𝕖𝕣 𝕕𝕣𝕚𝕟𝕜𝕚𝕟𝕘 𝕞𝕚𝕝𝕜 𝕚 𝕓𝕖𝕔𝕠𝕞𝕖 𝕦𝕟𝕤𝕥𝕠𝕡𝕡𝕒𝕓𝕝𝕖 𝕔𝕒𝕥𝕓𝕠𝕪 >:3",
        "𝓬𝓪𝓽𝓫𝓸𝔂 𝓻𝓮𝔃𝓸𝓵𝓿𝓮𝓻 𝓽𝓮𝓬𝓱𝓷𝓸𝓵𝓸𝓰𝓲𝓮𝓼 𝓼𝓮𝓷𝓭 𝓾 𝓽𝓸 𝓵𝓲𝓽𝓽𝓮𝓻 𝓫𝓸𝔁 ◣_◢",
        "𝕚 𝕡𝕦𝕣𝕣 𝕒𝕟𝕕 𝕪𝕠𝕦 𝕘𝕠 𝕤𝕝𝕖𝕖𝕡 𝕗𝕠𝕣𝕖𝕧𝕖𝕣 (=^･ω･^=)",
        "ᴛʜɪꜱ ᴄᴀᴛʙᴏʏ ʜᴀꜱ 9 ʟɪᴠᴇꜱ ʏᴏᴜ ʜᴀᴠᴇ 0 ◣_◢",
        "𝔦 𝔰𝔥𝔞𝔯𝔭𝔢𝔫 𝔪𝔶 𝔠𝔩𝔞𝔴𝔰 𝔬𝔫 𝔶𝔬𝔲𝔯 𝔞𝔫𝔱𝔦 𝔞𝔦𝔪𝔟𝔬𝔱",
        "𝕞𝕖𝕠𝕨 𝕞𝕖𝕠𝕨 𝕟𝕚𝕘𝕘𝕒 𝕪𝕠𝕦 𝕛𝕦𝕤𝕥 𝕕𝕚𝕖𝕕 𝕥𝕠 𝕒 𝕔𝕒𝕥𝕓𝕠𝕪 ◣_◢",
        "𝙘𝙖𝙩𝙗𝙤𝙮 𝙨𝙪𝙥𝙧𝙚𝙢𝙖𝙘𝙮 𝙞𝙨 𝙣𝙤𝙩 𝙖 𝙟𝙤𝙠𝙚 𝙞𝙩𝙨 𝙖 𝙡𝙞𝙛𝙚𝙨𝙩𝙮𝙡𝙚 (=^･ω･^=)",
        "𝘢𝘧𝘵𝘦𝘳 𝘱𝘦𝘵𝘵𝘪𝘯𝘨 𝘮𝘺 𝘤𝘢𝘵 𝘪 𝘳𝘦𝘤𝘪𝘦𝘷𝘦𝘥 𝘱𝘰𝘸𝘦𝘳 𝘵𝘰 1𝘵𝘢𝘱 𝘢𝘭𝘭 𝘥𝘰𝘨𝘴",
        "𝕡𝕣𝕖𝕤𝕚𝕕𝕖𝕟𝕥 𝕠𝕗 𝕔𝕒𝕥𝕓𝕠𝕪 𝕟𝕒𝕥𝕚𝕠𝕟 𝕛𝕦𝕤𝕥 𝕙𝕤𝕕 𝕪𝕠𝕦 𝕗𝕣𝕠𝕞 𝕥𝕙𝕖 𝕝𝕚𝕥𝕥𝕖𝕣 𝕓𝕠𝕩 ◣_◢",
        "(っ◔◡◔)っ ♥ enjoy this headshot from catboy.lua ♥",
        "ᵐᵉᵒʷ ᵐᵉᵒʷ ᵐᶠ ʸᵒᵘ ʲᵘˢᵗ ᵍᵒᵗ ˢᶜʳᵃᵗᶜʰᵉᵈ",
        "𝓲 𝓭𝓸𝓷𝓽 𝓷𝓮𝓮𝓭 9 𝓵𝓲𝓿𝓮𝓼 𝓽𝓸 𝓸𝔀𝓷 𝔂𝓸𝓾 𝓲 𝓳𝓾𝓼𝓽 𝓷𝓮𝓮𝓭 1 𝓫𝓾𝓵𝓵𝓮𝓽 :3",
        "𝕨𝕖𝕒𝕜 𝕕𝕠𝕘 𝕘𝕠 𝕡𝕝𝕒𝕪 𝕗𝕖𝕥𝕔𝕙 𝕨𝕙𝕚𝕝𝕖 𝕔𝕒𝕥𝕓𝕠𝕪 𝕣𝕦𝕝𝕖𝕤 𝕥𝕙𝕖 𝕤𝕖𝕣𝕧𝕖𝕣 >:3",
        "𝘨𝘰𝘥 𝘮𝘢𝘥𝘦 𝘤𝘢𝘵𝘴 𝘱𝘦𝘳𝘧𝘦𝘤𝘵 𝘢𝘯𝘥 𝘵𝘩𝘦𝘯 𝘩𝘦 𝘮𝘢𝘥𝘦 𝘮𝘦 𝘸𝘪𝘵𝘩 𝘢 𝘳𝘦𝘴𝘰𝘭𝘷𝘦𝘳 ◣_◢",
        "𝙞 𝙠𝙣𝙤𝙘𝙠 𝙮𝙤𝙪𝙧 𝙖𝙣𝙩𝙞𝙖𝙞𝙢 𝙤𝙛𝙛 𝙩𝙝𝙚 𝙩𝙖𝙗𝙡𝙚 𝙡𝙞𝙠𝙚 𝙖 𝙘𝙖𝙩 >:3",
        "𝕔𝕒𝕥𝕓𝕠𝕪 𝕝𝕦𝕒 𝕤𝕖𝕟𝕕𝕤 𝕪𝕠𝕦 𝕥𝕠 𝕥𝕙𝕖 𝕡𝕠𝕦𝕟𝕕 (=^･ω･^=)ﾉ",
        "ＹＯＵ ＴＨＩＮＫ ＹＯＵ ＡＲＥ ＳＩＧＭＡ ＢＵＴ ＹＯＵ ＡＲＥ ＪＵＳＴ Ａ ＤＯＧ ＴＯ ＭＥ >:3",
        "𝔦 𝔩𝔞𝔫𝔡 𝔬𝔫 𝔪𝔶 𝔣𝔢𝔢𝔱 𝔶𝔬𝔲 𝔩𝔞𝔫𝔡 𝔬𝔫 𝔶𝔬𝔲𝔯 𝔣𝔞𝔠𝔢",
        "nyaa~ 𝕪𝕠𝕦𝕣 𝕔𝕠𝕟𝕗𝕚𝕘 𝕤𝕞𝕖𝕝𝕝𝕤 𝕝𝕚𝕜𝕖 𝕨𝕖𝕥 𝕕𝕠𝕘 ◣_◢",
        "ɪ ᴅᴏɴᴛ ᴀʟᴡᴀʏꜱ ʟᴀɴᴅ ᴏɴ ᴍʏ ꜰᴇᴇᴛ ʙᴜᴛ ɪ ᴀʟᴡᴀʏꜱ ʟᴀɴᴅ ᴏɴ ʏᴏᴜʀ ʜᴇᴀᴅ :3",
        "𝘤𝘢𝘵𝘣𝘰𝘺.𝘭𝘶𝘢 𝘦𝘳𝘳𝘰𝘳 404: 𝘺𝘰𝘶𝘳 𝘴𝘬𝘪𝘭𝘭 𝘯𝘰𝘵 𝘧𝘰𝘶𝘯𝘥",
        "𝕒𝕗𝕥𝕖𝕣 𝕖𝕤𝕔𝕒𝕡𝕚𝕟𝕘 𝕥𝕙𝕖 𝕒𝕟𝕚𝕞𝕒𝕝 𝕤𝕙𝕖𝕝𝕥𝕖𝕣 𝕚 𝕨𝕖𝕟𝕥 𝕠𝕟 𝕜𝕚𝕝𝕝𝕚𝕟𝕘 𝕤𝕡𝕣𝕖𝕖 ◣_◢",
        "𝓬𝓾𝓻𝓲𝓸𝓼𝓲𝓽𝔂 𝓴𝓲𝓵𝓵𝓮𝓭 𝓽𝓱𝓮 𝓬𝓪𝓽? 𝓷𝓸.. 𝓽𝓱𝓮 𝓬𝓪𝓽 𝓴𝓲𝓵𝓵𝓮𝓭 𝔂𝓸𝓾 >:3",
        "u need catnip to hit my aa",
        "𝙞 𝙨𝙡𝙚𝙚𝙥 18 𝙝𝙤𝙪𝙧𝙨 𝙖 𝙙𝙖𝙮 𝙖𝙣𝙙 𝙨𝙩𝙞𝙡𝙡 𝙤𝙬𝙣 𝙮𝙤𝙪 ◣_◢",
        "ᵗʰⁱˢ ᶜᵃᵗᵇᵒʸ ʰᵃˢ ᶜˡᵃʷˢ ˢʰᵃʳᵖᵉʳ ᵗʰᵃⁿ ʸᵒᵘʳ ʳᵉˢᵒˡᵛᵉʳ",
        "𝕘𝕠𝕕 𝕞𝕒𝕕𝕖 𝕔𝕒𝕥𝕤 𝕥𝕠 𝕣𝕦𝕝𝕖 𝕒𝕟𝕕 𝕕𝕠𝕘𝕤 𝕥𝕠 𝕕𝕚𝕖 𝕪𝕠𝕦 𝕒𝕣𝕖 𝕕𝕠𝕘 (=^･ω･^=)",
        "ᴍᴇᴏᴡ ᴍᴇᴏᴡ ɪ ᴊᴜꜱᴛ ᴀᴛᴇ ʏᴏᴜʀ ᴀɴᴛɪᴀɪᴍ ʟɪᴋᴇ ᴛᴜɴᴀ",
        "sowwy i knocked ur hp off the counter >w<",
        "𝘪 𝘸𝘢𝘴 𝘴𝘭𝘦𝘦𝘱𝘪𝘯𝘨 𝘪𝘯 𝘴𝘶𝘯𝘣𝘦𝘢𝘮 𝘸𝘩𝘦𝘯 𝘪 𝘩𝘦𝘢𝘳𝘥 𝘸𝘦𝘢𝘬 𝘥𝘰𝘨 𝘣𝘢𝘳𝘬𝘪𝘯𝘨 𝘴𝘰 𝘪 1𝘵𝘢𝘱𝘱𝘦𝘥 𝘪𝘵",
        "𝕔𝕒𝕥𝕓𝕠𝕪 𝕝𝕦𝕒 𝕔𝕠𝕤𝕥 𝕞𝕖 0$ 𝕒𝕟𝕕 𝕤𝕥𝕚𝕝𝕝 𝕠𝕨𝕟𝕤 𝕪𝕠𝕦𝕣 𝕡𝕒𝕤𝕥𝕖 ◣_◢",
        "𝘪 𝘤𝘰𝘶𝘨𝘩 𝘩𝘢𝘪𝘳𝘣𝘢𝘭𝘭 𝘰𝘯 𝘺𝘰𝘶𝘳 𝘨𝘳𝘢𝘷𝘦 >:3",
        "𝕟𝕠 𝕞𝕠𝕦𝕤𝕖 𝕔𝕒𝕟 𝕖𝕤𝕔𝕒𝕡𝕖 𝕥𝕙𝕚𝕤 𝕔𝕒𝕥 𝕟𝕠 𝕡𝕝𝕒𝕪𝕖𝕣 𝕔𝕒𝕟 𝕖𝕤𝕔𝕒𝕡𝕖 𝕥𝕙𝕚𝕤 𝕙𝕤 ◣_◢",
        "ＭＥＯＷ ＭＥＯＷ ＩＭ ＩＮ ＹＯＵＲ ＷＡＬＬＳ ＡＮＤ ＹＯＵＲ ＨＥＡＤ >:3",
        "𝓲 𝓼𝓲𝓽 𝓸𝓷 𝔂𝓸𝓾𝓻 𝓴𝓮𝔂𝓫𝓸𝓪𝓻𝓭 𝓪𝓷𝓭 𝓼𝓽𝓲𝓵𝓵 𝓹𝓵𝓪𝔂 𝓫𝓮𝓽𝓽𝓮𝓻 𝓽𝓱𝓪𝓷 𝔂𝓸𝓾",
        "ɪ ᴡᴀꜱ ʙᴏʀɴ ɪɴ ᴛʜᴇ ʟɪᴛᴛᴇʀ ʙᴏx. ᴍᴏʟᴅᴇᴅ ʙʏ ɪᴛ. ʏᴏᴜ ᴍᴇʀᴇʟʏ ᴅɪᴇᴅ ɪɴ ɪᴛ ◣_◢",
        "𝕤𝕥𝕠𝕡 𝕓𝕒𝕣𝕜𝕚𝕟𝕘 𝕨𝕖𝕒𝕜 𝕕𝕠𝕘 𝕪𝕠𝕦 𝕒𝕣𝕖 *𝔻𝔼𝔸𝔻* (=^･ω･^=)",
        "𝔱𝔥𝔢 𝔠𝔞𝔱𝔟𝔬𝔶 𝔡𝔬𝔢𝔰 𝔫𝔬𝔱 𝔣𝔬𝔯𝔤𝔦𝔳𝔢. 𝔱𝔥𝔢 𝔠𝔞𝔱𝔟𝔬𝔶 𝔡𝔬𝔢𝔰 𝔫𝔬𝔱 𝔣𝔬𝔯𝔤𝔢𝔱. >:3",
        "𝙞 𝙗𝙧𝙞𝙣𝙜 𝙮𝙤𝙪𝙧 𝙙𝙚𝙖𝙩𝙝 𝙖𝙨 𝙜𝙞𝙛𝙩 𝙡𝙞𝙠𝙚 𝙘𝙖𝙩 𝙗𝙧𝙞𝙣𝙜𝙨 𝙙𝙚𝙖𝙙 𝙗𝙞𝙧𝙙 ◣_◢",
        "nyaa~ 𝕚 𝕜𝕟𝕖𝕒𝕕 𝕓𝕚𝕤𝕔𝕦𝕚𝕥𝕤 𝕠𝕟 𝕪𝕠𝕦𝕣 𝕔𝕠𝕣𝕡𝕤𝕖 (˘ω˘)",
        "ᵘ ᵗʰⁱⁿᵏ ⁱᵐ ᶜᵘᵗᵉ ᵘⁿᵗⁱˡ ⁱ ¹ᵗᵃᵖ ᵘ ᵃᵗ ³ᵃᵐ",
        "𝘴𝘰 𝘪 𝘳𝘦𝘤𝘪𝘦𝘷𝘦𝘥 𝘤𝘢𝘵𝘣𝘰𝘺.𝘭𝘶𝘢 𝘧𝘳𝘰𝘮 𝘵𝘩𝘦 𝘴𝘵𝘳𝘦𝘦𝘵𝘴 𝘢𝘯𝘥 𝘯𝘰𝘸 𝘪𝘵𝘴 𝘰𝘸𝘯 𝘢𝘭𝘭 𝘴𝘦𝘳𝘷𝘦𝘳𝘴",
        "𝕚 𝕡𝕦𝕤𝕙 𝕪𝕠𝕦𝕣 𝕙𝕡 𝕠𝕗𝕗 𝕥𝕙𝕖 𝕖𝕕𝕘𝕖 𝕒𝕟𝕕 𝕨𝕒𝕥𝕔𝕙 𝕚𝕥 𝕗𝕒𝕝𝕝 :3",
        "ＣＡＴＢＯＹ ＮＡＴＩＯＮ ＤＯＥＳ ＮＯＴ ＮＥＧＯＴＩＡＴＥ ＷＩＴＨ ＤＯＧＳ",
        "𝓶𝔂 𝓬𝓪𝓽 𝓮𝓪𝓻𝓼 𝓱𝓮𝓪𝓻 𝔂𝓸𝓾𝓻 𝓭𝓮𝓼𝔂𝓷𝓬 𝓫𝓮𝓯𝓸𝓻𝓮 𝔂𝓸𝓾 𝓮𝓿𝓮𝓷 𝓹𝓮𝓮𝓴 >:3",
        "𝘶𝘯𝘧𝘰𝘳𝘵𝘶𝘯𝘢𝘵𝘦 𝘮𝘦𝘮𝘣𝘦𝘳 𝘬𝘯𝘦𝘦𝘭𝘴 𝘣𝘦𝘧𝘰𝘳𝘦 𝘤𝘢𝘵𝘣𝘰𝘺 𝘳𝘦𝘻𝘰𝘭𝘷𝘦𝘳 ◣_◢",
        "ɪ ᴅᴏɴᴛ ᴄʜᴀꜱᴇ ᴍɪᴄᴇ ᴀɴʏᴍᴏʀᴇ ɪ ᴄʜᴀꜱᴇ ʜᴇᴀᴅꜱ (=^･ω･^=)",
        "𝕚 𝕤𝕥𝕒𝕣𝕖 𝕒𝕥 𝕪𝕠𝕦 𝕗𝕣𝕠𝕞 𝕥𝕙𝕖 𝕤𝕙𝕖𝕝𝕗 𝕒𝕟𝕕 𝕡𝕦𝕤𝕙 𝕪𝕠𝕦 𝕠𝕗𝕗 𝕥𝕙𝕖 𝕤𝕔𝕠𝕣𝕖𝕓𝕠𝕒𝕣𝕕 ◣_◢",
        "𝔞𝔣𝔱𝔢𝔯 𝔡𝔯𝔦𝔫𝔨𝔦𝔫𝔤 𝔴𝔞𝔱𝔢𝔯 𝔣𝔯𝔬𝔪 𝔱𝔬𝔦𝔩𝔢𝔱 𝔦 𝔞𝔠𝔥𝔦𝔢𝔳𝔢𝔡 𝔭𝔢𝔯𝔣𝔢𝔠𝔱 𝔥𝔰 :3",
        "𝙘𝙖𝙩𝙨 𝙧𝙪𝙡𝙚 𝙩𝙝𝙚 𝙞𝙣𝙩𝙚𝙧𝙣𝙚𝙩 𝙖𝙣𝙙 𝙩𝙝𝙞𝙨 𝙨𝙚𝙧𝙫𝙚𝙧 ◣_◢",
        "i scratch your face and your elo >:3",
        "𝕪𝕠𝕦 𝕔𝕒𝕟 𝕓𝕦𝕪 𝕒 𝕟𝕖𝕨 𝕝𝕦𝕒 𝕓𝕦𝕥 𝕪𝕠𝕦 𝕔𝕒𝕟𝕥 𝕓𝕦𝕪 𝟡 𝕝𝕚𝕧𝕖𝕤 (=^･ω･^=)",
        "𝓽𝓱𝓲𝓼 𝓬𝓪𝓽𝓫𝓸𝔂 𝓲𝓼 𝓷𝓸𝓽 𝓭𝓸𝓶𝓮𝓼𝓽𝓲𝓬𝓪𝓽𝓮𝓭 ◣_◢",
        "ᵐʸ ᶠᵘʳ ⁱˢ ᵗʰⁱᶜᵏᵉʳ ᵗʰᵃⁿ ʸᵒᵘʳ ˢᵏᵘˡˡ ᵃⁿᵈ ⁱ ˢᵗⁱˡˡ ¹ᵗᵃᵖ ⁱᵗ",
        "𝘪 𝘸𝘢𝘴 𝘤𝘩𝘢𝘴𝘪𝘯𝘨 𝘭𝘢𝘴𝘦𝘳 𝘱𝘰𝘪𝘯𝘵𝘦𝘳 𝘸𝘩𝘦𝘯 𝘪 𝘢𝘤𝘤𝘪𝘥𝘦𝘯𝘵𝘢𝘭𝘭𝘺 𝘩𝘴𝘥 𝘺𝘰𝘶",
        "𝕒𝕗𝕥𝕖𝕣 𝕜𝕟𝕠𝕔𝕜𝕚𝕟𝕘 𝕖𝕧𝕖𝕣𝕪 𝕘𝕝𝕒𝕤𝕤 𝕠𝕗𝕗 𝕥𝕙𝕖 𝕥𝕒𝕓𝕝𝕖 𝕚 𝕜𝕟𝕠𝕔𝕜 𝕪𝕠𝕦 𝕠𝕗𝕗 𝕥𝕙𝕖 𝕤𝕖𝕣𝕧𝕖𝕣 ◣_◢",
        "god may forgive you but catboy resolver won't (◣_◢)",
        "𝙞 𝙢𝙖𝙠𝙚 𝙗𝙞𝙨𝙘𝙪𝙞𝙩𝙨 𝙤𝙣 𝙮𝙤𝙪𝙧 𝙙𝙚𝙖𝙩𝙝𝙘𝙖𝙢 :3",
        "ᴅᴏɴᴛ ᴘᴇᴛ ᴍᴇ ᴅᴏɴᴛ ꜰᴇᴇᴅ ᴍᴇ ᴊᴜꜱᴛ ᴅɪᴇ ꜰᴏʀ ᴍᴇ >:3",
        "𝓲 𝓱𝓲𝓼𝓼 𝓪𝓽 𝔂𝓸𝓾𝓻 𝓻𝓮𝔃𝓸𝓵𝓿𝓮𝓻 𝓪𝓷𝓭 𝓲𝓽 𝓻𝓾𝓷𝓼 𝓪𝔀𝓪𝔂",
        "𝘺𝘰𝘶 𝘢𝘳𝘦 𝘮𝘰𝘶𝘴𝘦. 𝘪 𝘢𝘮 𝘤𝘢𝘵. 𝘵𝘩𝘪𝘴 𝘸𝘢𝘴 𝘢𝘭𝘸𝘢𝘺𝘴 𝘵𝘩𝘦 𝘰𝘶𝘵𝘤𝘰𝘮𝘦 ◣_◢",
        "𝕚 𝕙𝕒𝕧𝕖 𝕥𝕙𝕖 𝕫𝕠𝕠𝕞𝕚𝕖𝕤 𝕒𝕟𝕕 𝕪𝕠𝕦 𝕙𝕒𝕧𝕖 𝕥𝕙𝕖 𝕕𝕖𝕒𝕥𝕙𝕚𝕖𝕤 (=^･ω･^=)",
    }

        local function on_player_death(e)
            local victim = client.userid_to_entindex(e.userid)
            local attacker = client.userid_to_entindex(e.attacker)
            local lp = entity.get_local_player()

            if attacker == lp and victim ~= lp then
                local msg = killsay_messages[math.random(#killsay_messages)]
                client.exec("say " .. msg)
            end
        end

        local callbacks do
            local function on_enabled(item)
                local value = item:get()
                utils.event_callback('player_death', on_player_death, value)
            end

            ref.enabled:set_callback(
                on_enabled, true
            )
        end
    end

    local net_graph do
        local ref = ref.misc.net_graph
        local ffi = require 'ffi'
        local ffi_cast = ffi.cast

        -- convars
        local cl_interp = cvar.cl_interp
        local cl_interp_ratio = cvar.cl_interp_ratio
        local cl_updaterate = cvar.cl_updaterate

        -- FFI net channel
        local pflFrameTime = ffi.new("float[1]")
        local pflFrameTimeStdDeviation = ffi.new("float[1]")
        local pflFrameStartTimeStdDeviation = ffi.new("float[1]")

        local interface_ptr = ffi.typeof('void***')
        local netc_bool = ffi.typeof("bool(__thiscall*)(void*)")
        local netc_float = ffi.typeof("float(__thiscall*)(void*, int)")
        local netc_int = ffi.typeof("int(__thiscall*)(void*, int)")
        local net_fr_to = ffi.typeof("void(__thiscall*)(void*, float*, float*, float*)")

        local rawivengineclient = client.create_interface("engine.dll", "VEngineClient014")
        local ivengineclient = ffi_cast(interface_ptr, rawivengineclient)
        local get_net_channel_info = ffi_cast("void*(__thiscall*)(void*)", ivengineclient[0][78])
        local slv_is_ingame_t = ffi_cast("bool(__thiscall*)(void*)", ivengineclient[0][26])

        local ping_spike_refs = { ui.reference('MISC', 'Miscellaneous', 'Ping spike') }

        -- panel state
        local NG_DB_KEY = 'catboy#netgraph_pos'
        local ng_saved = database.read(NG_DB_KEY) or { }
        local ng = {
            x = ng_saved.x or nil,
            y = ng_saved.y or nil,
            dragging = false,
            drag_ox = 0, drag_oy = 0,
            was_mouse_down = false,
            W = 270, H = 0, -- H computed dynamically
        }
        local NG_SNAP = 15

        -- snap guide state
        local ng_snap = {
            cx = false, cy = false,
            left = false, right = false,
            top = false, bottom = false,
            cx_alpha = 0.0, cy_alpha = 0.0,
            w_alpha = 0.0, h_alpha = 0.0,
        }

        -- EMA smoothing
        local ng_smooth = {
            bytes_in = 0, bytes_out = 0,
            sv_framerate = 0, sv_var = 0,
            initialized = false,
            alpha = 0.0,
        }
        local NG_EMA = 0.08
        local ng_lc_alpha = 1.0

        -- ping history for graph
        local PING_HISTORY_MAX = 80
        local ping_history = { }
        local ping_history_timer = 0

        -- choke/loss history for secondary graph
        local LOSS_HISTORY_MAX = 80
        local loss_history = { }
        local choke_history = { }

        -- smooth position
        local ng_smooth_px, ng_smooth_py = ng.x or 0, ng.y or 0
        local ng_dim_alpha = 0.0
        local ng_status_pulse = 0.0

        -- warning icon (20x19 RGBA)
        local ng_warning_icon = renderer.load_rgba(
            "\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x02\xFF\xFF\xFF\x00\xFF\xFF\xFF\x6B\xFF\xFF\xFF\xFC\xFF\xFF\xFF\xFD\xFF\xFF\xFF\x6F\xFF\xFF\xFF\x00\xFF\xFF\xFF\x02\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x02\xFF\xFF\xFF\x00\xFF\xFF\xFF\x3C\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x6A\xFF\xFF\xFF\x70\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x40\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\xCA\xFF\xFF\xFF\xA1\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xB6\xFF\xFF\xFF\xCE\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x4D\xFF\xFF\xFF\xFC\xFF\xFF\xFF\x20\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x31\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x50\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xD8\xFF\xFF\xFF\x94\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xAA\xFF\xFF\xFF\xDC\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x5E\xFF\xFF\xFF\xF7\xFF\xFF\xFF\x15\xFF\xFF\xFF\x00\xFF\xFF\xFF\x52\xFF\xFF\xFF\x56\xFF\xFF\xFF\x00\xFF\xFF\xFF\x24\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x61\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\xE5\xFF\xFF\xFF\x83\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xDA\xFF\xFF\xFF\xE3\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x99\xFF\xFF\xFF\xE9\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x70\xFF\xFF\xFF\xF0\xFF\xFF\xFF\x0A\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xD1\xFF\xFF\xFF\xD9\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x17\xFF\xFF\xFF\xFE\xFF\xFF\xFF\x73\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x09\xFF\xFF\xFF\xEF\xFF\xFF\xFF\x72\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\xD2\xFF\xFF\xFF\xDB\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x86\xFF\xFF\xFF\xF4\xFF\xFF\xFF\x0B\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x82\xFF\xFF\xFF\xE7\xFF\xFF\xFF\x02\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xD2\xFF\xFF\xFF\xDB\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x0C\xFF\xFF\xFF\xF5\xFF\xFF\xFF\x84\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x13\xFF\xFF\xFF\xF8\xFF\xFF\xFF\x61\xFF\xFF\xFF\x00\xFF\xFF\xFF\x04\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xD2\xFF\xFF\xFF\xDB\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x04\xFF\xFF\xFF\x00\xFF\xFF\xFF\x73\xFF\xFF\xFF\xFE\xFF\xFF\xFF\x16\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x94\xFF\xFF\xFF\xDB\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xD0\xFF\xFF\xFF\xD8\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\xE9\xFF\xFF\xFF\x97\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x1F\xFF\xFF\xFF\xFE\xFF\xFF\xFF\x51\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xE0\xFF\xFF\xFF\xE9\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x61\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x22\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xA6\xFF\xFF\xFF\xCD\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x6D\xFF\xFF\xFF\x72\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xDC\xFF\xFF\xFF\xA9\xFF\xFF\xFF\x00\xFF\xFF\xFF\x2D\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x41\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x7D\xFF\xFF\xFF\x82\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x4F\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x30\xFF\xFF\xFF\xBC\xFF\xFF\xFF\xBC\xFF\xFF\xFF\x00\xFF\xFF\xFF\x02\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x02\xFF\xFF\xFF\x00\xFF\xFF\xFF\xA7\xFF\xFF\xFF\xAE\xFF\xFF\xFF\x00\xFF\xFF\xFF\x02\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\xCC\xFF\xFF\xFF\xBB\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x3E\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x02\xFF\xFF\xFF\x00\xFF\xFF\xFF\x40\xFF\xFF\xFF\xF7\xFF\xFF\xFF\xE0\xFF\xFF\xFF\x7D\xFF\xFF\xFF\x00\xFF\xFF\xFF\x07\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x06\xFF\xFF\xFF\x00\xFF\xFF\xFF\x8A\xFF\xFF\xFF\xDC\xFF\xFF\xFF\x3F\xFF\xFF\xFF\xE7\xFF\xFF\xFF\xE4\xFF\xFF\xFF\xE1\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE3\xFF\xFF\xFF\xE3\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE1\xFF\xFF\xFF\xE5\xFF\xFF\xFF\xF0\xFF\xFF\xFF\x43",
            20, 19
        )

        -- smooth warning/tint state
        local ng_warn_alpha = 0.0        -- smooth warning icon alpha
        local ng_tint_alpha = 0.0        -- smooth glass tint shift
        local ng_border_flash = 0.0      -- border flash intensity (spikes then decays)

        local function ng_get_net_channel(ptr)
            if ptr == nil then return end
            local seqNr_out = ffi_cast(netc_int, ptr[0][17])(ptr, 1)
            return {
                seqNr_out = seqNr_out,
                is_loopback = ffi_cast(netc_bool, ptr[0][6])(ptr),
                is_timing_out = ffi_cast(netc_bool, ptr[0][7])(ptr),
                latency = {
                    crn = function(flow) return ffi_cast(netc_float, ptr[0][9])(ptr, flow) end,
                    average = function(flow) return ffi_cast(netc_float, ptr[0][10])(ptr, flow) end,
                },
                loss = ffi_cast(netc_float, ptr[0][11])(ptr, 1),
                choke = ffi_cast(netc_float, ptr[0][12])(ptr, 1),
                got_bytes = ffi_cast(netc_float, ptr[0][13])(ptr, 1),
                sent_bytes = ffi_cast(netc_float, ptr[0][13])(ptr, 0),
            }
        end

        local function ng_get_framerate(ptr)
            if ptr == nil then return 0, 0 end
            ffi_cast(net_fr_to, ptr[0][25])(ptr, pflFrameTime, pflFrameTimeStdDeviation, pflFrameStartTimeStdDeviation)
            if pflFrameTime ~= nil and pflFrameTimeStdDeviation ~= nil and pflFrameStartTimeStdDeviation ~= nil then
                if pflFrameTime[0] > 0 then
                    return pflFrameTime[0] * 1000, pflFrameStartTimeStdDeviation[0] * 1000
                end
            end
            return 0, 0
        end

        local function ng_ping_color(ping)
            ping = ping or 0
            if ping < 40 then return 160, 220, 180 end
            if ping < 100 then return 255, 200, 120 end
            return 255, 90, 100
        end

        local function ng_save_pos()
            database.write(NG_DB_KEY, { x = ng.x, y = ng.y })
        end

        local function on_paint_ui()
            if not boot.done then return end

            local me = entity.get_local_player()
            if not me or not slv_is_ingame_t(ivengineclient) then
                ng_smooth.alpha = motion.interp(ng_smooth.alpha, false, 0.08)
                if ng_smooth.alpha < 0.01 then return end
            else
                ng_smooth.alpha = motion.interp(ng_smooth.alpha, true, 0.08)
            end

            local alpha = ng_smooth.alpha
            if alpha < 0.01 then return end

            local net_ptr = ffi_cast("void***", get_net_channel_info(ivengineclient))
            if net_ptr == nil then return end

            local net = ng_get_net_channel(net_ptr)
            if net == nil then return end

            local raw_sv_fr, raw_sv_var = ng_get_framerate(net_ptr)
            local ft = globals.frametime()
            local now = globals.realtime()

            -- EMA smoothing
            if not ng_smooth.initialized then
                ng_smooth.bytes_in = net.got_bytes
                ng_smooth.bytes_out = net.sent_bytes
                ng_smooth.sv_framerate = raw_sv_fr
                ng_smooth.sv_var = raw_sv_var
                ng_smooth.initialized = true
            else
                ng_smooth.bytes_in = ng_smooth.bytes_in + (net.got_bytes - ng_smooth.bytes_in) * NG_EMA
                ng_smooth.bytes_out = ng_smooth.bytes_out + (net.sent_bytes - ng_smooth.bytes_out) * NG_EMA
                ng_smooth.sv_framerate = ng_smooth.sv_framerate + (raw_sv_fr - ng_smooth.sv_framerate) * NG_EMA
                ng_smooth.sv_var = ng_smooth.sv_var + (raw_sv_var - ng_smooth.sv_var) * NG_EMA
            end

            -- net state
            local net_state = 0
            if net.choke > 0 then net_state = 1 end
            if net.loss > 0 then net_state = 2 end
            if net.is_timing_out then
                net_state = 3
                net.loss = 1
                ng_lc_alpha = math.max(0.05, ng_lc_alpha - ft)
            else
                ng_lc_alpha = math.min(1.0, ng_lc_alpha + ft * 2)
            end

            -- accent color (from picker — used for all UI chrome)
            local ar, ag, ab = ref.color:get()

            -- warning color (used for tint/flash/status effects only)
            local wr, wg, wb = ar, ag, ab
            if net_state == 1 then wr, wg, wb = 255, 200, 95
            elseif net_state >= 2 then wr, wg, wb = 255, 60, 70 end

            ng_status_pulse = ng_status_pulse + ft * 4
            local warn_target = (net_state >= 2) and 1.0 or 0.0
            local tint_target = (net_state >= 1) and 1.0 or 0.0

            -- smooth warning transitions
            local warn_speed = 1 - math.pow(1 - 0.12, ft / (1 / 60))
            ng_warn_alpha = ng_warn_alpha + (warn_target - ng_warn_alpha) * warn_speed
            ng_tint_alpha = ng_tint_alpha + (tint_target - ng_tint_alpha) * warn_speed

            -- border flash: spike on state change then decay
            if net_state >= 2 then
                ng_border_flash = math.min(1.0, ng_border_flash + ft * 8)
            else
                ng_border_flash = math.max(0.0, ng_border_flash - ft * 3)
            end
            local border_flash_val = ng_border_flash * (math.sin(ng_status_pulse * 2) * 0.3 + 0.7)

            -- ping data
            local outgoing, incoming = net.latency.crn(0), net.latency.crn(1)
            local ping_now, avg_ping = outgoing * 1000, net.latency.average(0) * 1000
            local pcr, pcg, pcb = ng_ping_color(avg_ping)

            -- record histories
            if now - ping_history_timer > 0.08 then
                ping_history_timer = now
                ping_history[#ping_history + 1] = avg_ping
                if #ping_history > PING_HISTORY_MAX then table.remove(ping_history, 1) end
                loss_history[#loss_history + 1] = net.loss * 100
                if #loss_history > LOSS_HISTORY_MAX then table.remove(loss_history, 1) end
                choke_history[#choke_history + 1] = net.choke * 100
                if #choke_history > LOSS_HISTORY_MAX then table.remove(choke_history, 1) end
            end

            -- layout
            local scr_w, scr_h = client.screen_size()
            local rad = 8
            local pad = 10
            local graph_h = 44
            local row_h = 13
            local panel_w = 230
            local panel_h = pad + graph_h + 6 + row_h * 3 + pad
            ng.W = panel_w
            ng.H = panel_h

            local default_x = math.floor(scr_w / 2 - panel_w / 2)
            local default_y = scr_h - 140
            local px = ng.x or default_x
            local py = ng.y or default_y

            -- drag handling
            local menu_open = ui.is_menu_open()
            local mouse_down = menu_open and client.key_state(0x01)
            local mx, my = ui.mouse_position()

            -- smooth position
            local drag_speed = ng.dragging and 0.35 or 0.15
            local lerp_s = 1 - math.pow(1 - drag_speed, ft / (1 / 60))
            ng_smooth_px = ng_smooth_px + (px - ng_smooth_px) * lerp_s
            ng_smooth_py = ng_smooth_py + (py - ng_smooth_py) * lerp_s
            local spx = math.floor(ng_smooth_px)
            local spy = math.floor(ng_smooth_py)

            local in_panel = mx >= spx and mx <= spx + panel_w and my >= spy and my <= spy + panel_h
            debug_panel_info.hovering_netgraph = menu_open and in_panel

            if menu_open then
                if mouse_down and not ng.was_mouse_down and in_panel then
                    ng.dragging = true
                    ng.drag_ox = mx - spx
                    ng.drag_oy = my - spy
                end
                if not mouse_down then
                    if ng.dragging then ng_save_pos() end
                    ng.dragging = false
                end
                debug_panel_info.dragging_netgraph = ng.dragging

                if ng.dragging then
                    local new_x = mx - ng.drag_ox
                    local new_y = my - ng.drag_oy

                    ng_snap.cx = false; ng_snap.cy = false
                    ng_snap.left = false; ng_snap.right = false
                    ng_snap.top = false; ng_snap.bottom = false

                    local cx = math.floor(scr_w / 2 - panel_w / 2)
                    local cy = math.floor(scr_h / 2 - panel_h / 2)

                    if math.abs(new_x - cx) < NG_SNAP then new_x = cx; ng_snap.cx = true end
                    if math.abs(new_x) < NG_SNAP then new_x = 0; ng_snap.cx = false; ng_snap.left = true
                    elseif math.abs(new_x - (scr_w - panel_w)) < NG_SNAP then new_x = scr_w - panel_w; ng_snap.cx = false; ng_snap.right = true end

                    if math.abs(new_y - cy) < NG_SNAP then new_y = cy; ng_snap.cy = true end
                    if math.abs(new_y) < NG_SNAP then new_y = 0; ng_snap.cy = false; ng_snap.top = true
                    elseif math.abs(new_y - (scr_h - panel_h)) < NG_SNAP then new_y = scr_h - panel_h; ng_snap.cy = false; ng_snap.bottom = true end

                    px = new_x; py = new_y
                    ng.x = px; ng.y = py
                end
            else
                ng.dragging = false
                debug_panel_info.dragging_netgraph = false
            end
            ng.was_mouse_down = mouse_down

            -- blended source color: accent → warning as issues increase
            local t = ng_tint_alpha
            local sr = math.floor(ar + (wr - ar) * t)
            local sg = math.floor(ag + (wg - ag) * t)
            local sb = math.floor(ab + (wb - ab) * t)

            -- dim + snap animations
            ng_dim_alpha = ng_dim_alpha + ((ng.dragging and 1 or 0) - ng_dim_alpha) * (1 - math.pow(1 - 0.1, ft / (1 / 60)))
            local snap_lerp = 1 - math.pow(1 - 0.15, ft / (1 / 60))
            ng_snap.cx_alpha = ng_snap.cx_alpha + ((ng.dragging and ng_snap.cx and 1 or 0) - ng_snap.cx_alpha) * snap_lerp
            ng_snap.cy_alpha = ng_snap.cy_alpha + ((ng.dragging and ng_snap.cy and 1 or 0) - ng_snap.cy_alpha) * snap_lerp
            ng_snap.w_alpha = ng_snap.w_alpha + ((ng.dragging and (ng_snap.left or ng_snap.right) and 1 or 0) - ng_snap.w_alpha) * snap_lerp
            ng_snap.h_alpha = ng_snap.h_alpha + ((ng.dragging and (ng_snap.top or ng_snap.bottom) and 1 or 0) - ng_snap.h_alpha) * snap_lerp

            if ng_snap.cx_alpha > 0.01 then
                renderer.rectangle(math.floor(scr_w * 0.5), spy - 12, 1, panel_h + 24, sr, sg, sb, math.floor(120 * ng_snap.cx_alpha * alpha))
            end
            if ng_snap.cy_alpha > 0.01 then
                renderer.rectangle(spx - 12, math.floor(scr_h * 0.5), panel_w + 24, 1, sr, sg, sb, math.floor(120 * ng_snap.cy_alpha * alpha))
            end
            if ng_snap.w_alpha > 0.01 then
                local ga = math.floor(120 * ng_snap.w_alpha * alpha)
                if ng_snap.left then renderer.rectangle(0, spy - 12, 1, panel_h + 24, sr, sg, sb, ga) end
                if ng_snap.right then renderer.rectangle(scr_w - 1, spy - 12, 1, panel_h + 24, sr, sg, sb, ga) end
            end
            if ng_snap.h_alpha > 0.01 then
                local ga = math.floor(120 * ng_snap.h_alpha * alpha)
                if ng_snap.top then renderer.rectangle(spx - 12, 0, panel_w + 24, 1, sr, sg, sb, ga) end
                if ng_snap.bottom then renderer.rectangle(spx - 12, scr_h - 1, panel_w + 24, 1, sr, sg, sb, ga) end
            end
            if ng_dim_alpha > 0.01 then
                renderer.rectangle(0, 0, scr_w, scr_h, 0, 0, 0, math.floor(60 * ng_dim_alpha * alpha))
            end

            local la = math.floor(ng_lc_alpha * alpha * 255)

            -- glass layers derived from blended source
            local glass_r1 = math.floor(sr * 0.10)
            local glass_g1 = math.floor(sg * 0.10)
            local glass_b1 = math.floor(sb * 0.12)
            local glass_r2 = math.floor(sr * 0.16)
            local glass_g2 = math.floor(sg * 0.16)
            local glass_b2 = math.floor(sb * 0.20)
            local glass_r3 = math.floor(sr * 0.22)
            local glass_g3 = math.floor(sg * 0.22)
            local glass_b3 = math.floor(sb * 0.28)

            -- outer shadow (soft, offset)
            render.rectangle(spx + 2, spy + 3, panel_w, panel_h, 0, 0, 0, math.floor(20 * alpha), rad)
            render.rectangle(spx + 1, spy + 2, panel_w, panel_h, 0, 0, 0, math.floor(30 * alpha), rad)

            -- glass layers — accent-tinted, shifts toward warning on issues
            render.rectangle(spx, spy, panel_w, panel_h, glass_r1, glass_g1, glass_b1, math.floor(160 * alpha), rad)
            render.rectangle(spx, spy, panel_w, panel_h, glass_r2, glass_g2, glass_b2, math.floor(80 * alpha), rad)
            render.rectangle(spx, spy, panel_w, panel_h, glass_r3, glass_g3, glass_b3, math.floor(40 * alpha), rad)

            -- warning tint overlay — additional colored wash when issues detected
            if ng_tint_alpha > 0.01 then
                local tint_a = math.floor(25 * ng_tint_alpha * alpha * (math.sin(ng_status_pulse) * 0.2 + 0.8))
                render.rectangle(spx, spy, panel_w, panel_h, wr, wg, wb, tint_a, rad)
            end

            -- top highlight — light reflection tinted to blended source
            local hl_r = math.min(255, math.floor(sr * 0.5 + 128))
            local hl_g = math.min(255, math.floor(sg * 0.5 + 128))
            local hl_b = math.min(255, math.floor(sb * 0.5 + 128))
            renderer.gradient(spx + rad, spy + 1, panel_w - rad * 2, 1, hl_r, hl_g, hl_b, math.floor(18 * alpha), hl_r, hl_g, hl_b, math.floor(6 * alpha), true)
            renderer.gradient(spx + rad, spy + 2, panel_w - rad * 2, 1, hl_r, hl_g, hl_b, math.floor(8 * alpha), hl_r, hl_g, hl_b, math.floor(2 * alpha), true)

            -- inner glow from top
            renderer.gradient(spx + 1, spy + 1, panel_w - 2, math.floor(panel_h * 0.35), hl_r, hl_g, hl_b, math.floor(8 * alpha), hl_r, hl_g, hl_b, 0, false)

            -- glass border — uses blended source, intensifies on flash
            local bdr_r = math.min(255, math.floor(sr * 0.4 + 150))
            local bdr_g = math.min(255, math.floor(sg * 0.4 + 150))
            local bdr_b = math.min(255, math.floor(sb * 0.4 + 150))
            local bdr_a = math.floor((22 + 30 * border_flash_val) * alpha)
            render.rectangle_outline(spx, spy, panel_w, panel_h, bdr_r, bdr_g, bdr_b, bdr_a, 1, rad)

            -- inner border
            local ibdr_a = math.floor((8 + 15 * border_flash_val) * alpha)
            render.rectangle_outline(spx + 1, spy + 1, panel_w - 2, panel_h - 2, bdr_r, bdr_g, bdr_b, ibdr_a, 1, math.max(0, rad - 1))

            -- border glow on flash
            if border_flash_val > 0.01 then
                render.glow(spx, spy, panel_w, panel_h, wr, wg, wb, math.floor(20 * border_flash_val * alpha), rad, 2)
            end

            -- accent glow along bottom edge
            renderer.gradient(spx + rad, spy + panel_h - 2, panel_w - rad * 2, 2, sr, sg, sb, 0, sr, sg, sb, math.floor(40 * alpha), true)
            renderer.gradient(spx + rad, spy + panel_h - 2, panel_w - rad * 2, 2, sr, sg, sb, math.floor(40 * alpha), sr, sg, sb, 0, true)

            local gx = spx + pad
            local gy = spy + pad
            local gw = panel_w - pad * 2
            local gh = graph_h

            -- graph recessed area — slightly darker inset
            render.rectangle(gx, gy, gw, gh, 0, 0, 0, math.floor(40 * alpha), 4)
            render.rectangle_outline(gx, gy, gw, gh, 255, 255, 255, math.floor(8 * alpha), 1, 4)

            -- horizontal guides
            for i = 1, 3 do
                local ly = gy + math.floor(gh * i / 4)
                renderer.line(gx + 2, ly, gx + gw - 2, ly, 255, 255, 255, math.floor(6 * alpha))
            end

            -- ping line
            if #ping_history >= 2 then
                local max_ping = 1
                for i = 1, #ping_history do
                    if ping_history[i] > max_ping then max_ping = ping_history[i] end
                end
                max_ping = math.max(max_ping * 1.25, 15)

                local count = #ping_history
                local step = gw / (PING_HISTORY_MAX - 1)
                local offset = PING_HISTORY_MAX - count

                for i = 1, count - 1 do
                    local x1 = gx + math.floor((i - 1 + offset) * step)
                    local x2 = gx + math.floor((i + offset) * step)
                    local h1 = math.min(ping_history[i] / max_ping, 1) * (gh - 6)
                    local h2 = math.min(ping_history[i + 1] / max_ping, 1) * (gh - 6)
                    local y1 = gy + gh - 3 - math.floor(h1)
                    local y2 = gy + gh - 3 - math.floor(h2)

                    -- per-segment ping color (blends based on ping value at that point)
                    local seg_ping = ping_history[i + 1]
                    local spr, spg, spb = ng_ping_color(seg_ping)

                    -- fill under line
                    local seg_w = math.max(1, x2 - x1)
                    local top = math.min(y1, y2)
                    local bot = gy + gh
                    if bot - top > 0 then
                        local fill_a = math.floor((12 + 10 * (i / count)) * alpha)
                        renderer.gradient(x1, top, seg_w, bot - top, spr, spg, spb, fill_a, spr, spg, spb, 0, false)
                    end

                    -- line with fade-in from left to right
                    local line_a = math.floor((60 + 140 * (i / count)) * alpha)
                    renderer.line(x1, y1, x2, y2, spr, spg, spb, line_a)
                end

                -- loss/choke bars
                for i = 1, count do
                    local lx = gx + math.floor((i - 1 + offset) * step)
                    local sw = math.max(1, math.floor(step))
                    if loss_history[i] and loss_history[i] > 0 then
                        local lh = math.max(1, math.floor(loss_history[i] / 100 * gh * 0.25))
                        renderer.gradient(lx, gy + gh - lh, sw, lh, 255, 60, 70, 0, 255, 60, 70, math.floor(45 * alpha), false)
                    end
                    if choke_history[i] and choke_history[i] > 0 and (not loss_history[i] or loss_history[i] == 0) then
                        local ch = math.max(1, math.floor(choke_history[i] / 100 * gh * 0.15))
                        renderer.gradient(lx, gy + gh - ch, sw, ch, 255, 200, 80, 0, 255, 200, 80, math.floor(30 * alpha), false)
                    end
                end

                -- glow dot on latest
                local last_x = gx + math.floor((count - 1 + offset) * step)
                local last_h = math.min(ping_history[count] / max_ping, 1) * (gh - 6)
                local last_y = gy + gh - 3 - math.floor(last_h)

                render.glow(last_x - 4, last_y - 4, 8, 8, pcr, pcg, pcb, math.floor(40 * alpha), 4, 2)
                renderer.rectangle(last_x - 1, last_y - 1, 3, 3, 255, 255, 255, math.floor(220 * alpha))
            end

            -- ping value overlaid top-left of graph
            local pr, pg, pb = ng_ping_color(avg_ping)
            local ping_str = string.format('%d', avg_ping)
            -- text shadow
            renderer.text(gx + 5, gy + 3, 0, 0, 0, math.floor(60 * alpha), 'b', nil, ping_str)
            renderer.text(gx + 4, gy + 2, pr, pg, pb, math.floor(la * 0.95), 'b', nil, ping_str)
            local pw = renderer.measure_text('b', ping_str)
            renderer.text(gx + 4 + pw + 2, gy + 3, 210, 215, 225, math.floor(la * 0.5), '', nil, 'ms')

            -- sv top-right of graph
            local sv_str = string.format('sv %.1f', ng_smooth.sv_framerate)
            local sv_tw = renderer.measure_text('', sv_str)
            renderer.text(gx + gw - sv_tw - 4, gy + 3, 200, 205, 220, math.floor(la * 0.55), '', nil, sv_str)

            -- warning icon (top-right, next to ping text) — fades in on loss/timeout
            if ng_warn_alpha > 0.01 then
                local icon_a = math.floor(255 * ng_warn_alpha * alpha * (math.sin(ng_status_pulse * 1.5) * 0.25 + 0.75))
                local icon_x = gx + 4 + pw + 2 + renderer.measure_text('', 'ms') + 6
                local icon_y = gy + 1
                renderer.texture(ng_warning_icon, icon_x, icon_y, 20, 19, wr, wg, wb, icon_a)
            end

            -- status text inside graph (bottom-left) — appears on network issues
            if net_state > 0 then
                local status_texts = { [1] = 'packet choke', [2] = 'packet loss', [3] = 'lost connection' }
                local status_str = status_texts[net_state] or ''
                local status_a = math.floor(ng_tint_alpha * alpha * 220 * (math.sin(ng_status_pulse * 1.5) * 0.15 + 0.85))
                -- shadow
                renderer.text(gx + 5, gy + gh - 13, 0, 0, 0, math.floor(status_a * 0.5), '', nil, status_str)
                renderer.text(gx + 4, gy + gh - 14, wr, wg, wb, status_a, '', nil, status_str)
            end

            local sy = gy + gh + 8
            local content_w = gw
            local dim = math.floor(la * 0.55)
            local bright = la

            -- thin separator
            renderer.gradient(gx, sy - 4, gw, 1, 255, 255, 255, 0, 255, 255, 255, math.floor(10 * alpha), true)
            renderer.gradient(gx, sy - 4, gw, 1, 255, 255, 255, math.floor(10 * alpha), 255, 255, 255, 0, true)

            -- row 1: loss · choke · bandwidth
            renderer.text(gx, sy, 180, 185, 200, dim, '', nil, 'loss')
            local loss_val = string.format('%.0f%%', net.loss * 100)
            local lr1 = net.loss > 0 and 255 or 210
            local lg1 = net.loss > 0 and 90 or 215
            local lb1 = net.loss > 0 and 100 or 230
            renderer.text(gx + 26, sy, lr1, lg1, lb1, bright, '', nil, loss_val)

            renderer.text(gx + 58, sy, 180, 185, 200, dim, '', nil, 'choke')
            local choke_val = string.format('%.0f%%', net.choke * 100)
            local cr = net.choke > 0 and 255 or 210
            local cg = net.choke > 0 and 200 or 215
            renderer.text(gx + 92, sy, cr, cg, 180, bright, '', nil, choke_val)

            local bw = string.format('%.0f / %.0f k', ng_smooth.bytes_in / 1024, ng_smooth.bytes_out / 1024)
            local bw_tw = renderer.measure_text('', bw)
            renderer.text(gx + content_w - bw_tw, sy, 170, 175, 195, dim, '', nil, bw)
            sy = sy + row_h

            -- row 2: ping jitter · tick · lerp
            local jitter = math.abs(avg_ping - ping_now)
            renderer.text(gx, sy, 180, 185, 200, dim, '', nil, 'jitter')
            renderer.text(gx + 34, sy, 210, 215, 230, bright, '', nil, string.format('%.0fms', jitter))

            local tickrate = 1 / globals.tickinterval()
            renderer.text(gx + 80, sy, 180, 185, 200, dim, '', nil, 'tick')
            renderer.text(gx + 104, sy, 210, 215, 230, bright, '', nil, string.format('%d', tickrate))

            local lerp_time = cl_interp_ratio:get_float() * (1000 / tickrate)
            local lerp_ok = lerp_time / 1000 >= 2 / cl_updaterate:get_int()
            local lerp_str = string.format('%.1fms', lerp_time)
            local lerp_tw = renderer.measure_text('', lerp_str)
            local lerp_label_tw = renderer.measure_text('', 'lerp ')
            renderer.text(gx + content_w - lerp_tw - lerp_label_tw, sy, 180, 185, 200, dim, '', nil, 'lerp')
            local lerp_r = lerp_ok and 210 or 255
            local lerp_g = lerp_ok and 225 or 150
            local lerp_b = lerp_ok and 210 or 120
            renderer.text(gx + content_w - lerp_tw, sy, lerp_r, lerp_g, lerp_b, bright, '', nil, lerp_str)
            sy = sy + row_h

            -- row 3: sv var · datagram bar
            local var_str = string.format('var %.1fms', ng_smooth.sv_var)
            renderer.text(gx, sy, 180, 185, 200, dim, '', nil, var_str)

            -- datagram bar
            local ping_spike_val = (ui.get(ping_spike_refs[1]) and ui.get(ping_spike_refs[2])) and ui.get(ping_spike_refs[3]) or 1
            local latency_interval = (outgoing + incoming) / (ping_spike_val - globals.tickinterval())
            local additional_latency = math.min(latency_interval * 1000, 1) * 100

            local dgram_label_tw = renderer.measure_text('', 'dgram ')
            local dg_bar_w = content_w - 70 - dgram_label_tw
            local dg_bar_x = gx + 70 + dgram_label_tw
            local dg_bar_y = sy + 4
            local dg_bar_h = 3
            local dg_fill = math.floor(dg_bar_w * additional_latency / 100)
            local dg_g = math.floor(255 / 100 * additional_latency)

            renderer.text(gx + 70, sy, 180, 185, 200, dim, '', nil, 'dgram')
            -- bar bg (glass inset)
            render.rectangle(dg_bar_x, dg_bar_y, dg_bar_w, dg_bar_h, 0, 0, 0, math.floor(30 * alpha), 1)
            render.rectangle_outline(dg_bar_x, dg_bar_y, dg_bar_w, dg_bar_h, 255, 255, 255, math.floor(6 * alpha), 1, 1)
            if dg_fill > 0 then
                renderer.gradient(dg_bar_x, dg_bar_y, dg_fill, dg_bar_h, 255, dg_g, dg_g, math.floor(la * 0.5), 255, dg_g, dg_g, math.floor(la * 0.2), true)
            end

            -- status: accent glow at bottom when issues
            if net_state > 0 then
                local pulse = math.sin(ng_status_pulse) * 0.3 + 0.7
                local pa = math.floor(30 * alpha * pulse)
                render.glow(spx, spy + panel_h - 4, panel_w, 4, wr, wg, wb, pa, rad, 2)
            end
        end

        local callbacks do
            local function on_enabled(item)
                local value = item:get()
                utils.event_callback('paint_ui', on_paint_ui, value)
            end

            ref.enabled:set_callback(on_enabled, true)
        end
    end

    local aa_icon do
        ffi.cdef[[
            typedef struct {
                int x;
                int y;
            } catboy_IconVec2;
            typedef struct {
                char            pad0[0x4];
                int             TextureId;
                int             TextureOffset;
                char            pad1[0x4];
                catboy_IconVec2 Size;
            } catboy_IconTab;
        ]]

        local AA_TAB_INDEX = 1
        local AA_ICON_URL = 'https://raw.githubusercontent.com/lanesuwu/catboy.lua/e2746b800b3424fccc7e0de7f3a96160b5eff823/assets/13476111-2.png'
        local AA_ICON_PATH = 'catboy_aa_icon.png'

        local tabsptr = ffi.cast('intptr_t*', 0x434799AC + 0x54)
        local tab_raw = ffi.cast('int*', tabsptr[0])[AA_TAB_INDEX]
        local tabicon = ffi.cast('catboy_IconTab*', tab_raw + 0x7C)

        local backup = {
            TextureId = tabicon.TextureId,
            TextureOffset = tabicon.TextureOffset,
            Size = { x = tabicon.Size.x, y = tabicon.Size.y }
        }

        local function restore_icon()
            tabicon.TextureId = backup.TextureId
            tabicon.TextureOffset = backup.TextureOffset
            tabicon.Size.x = backup.Size.x
            tabicon.Size.y = backup.Size.y
        end

        local function apply_icon_data(data)
            local texture = renderer.load_png(data, 48, 48)
            if not texture then
                return
            end

            tabicon.TextureId = texture
            tabicon.TextureOffset = 0
            tabicon.Size.x = 48
            tabicon.Size.y = 48
        end

        local data = readfile(AA_ICON_PATH)
        if data then
            apply_icon_data(data)
        else
            http.get(AA_ICON_URL, function(s, r)
                if not s or r.status ~= 200 then
                    return
                end

                writefile(AA_ICON_PATH, r.body)
                apply_icon_data(r.body)
            end)
        end

        client.set_event_callback('shutdown', restore_icon)
    end

    local compensate_throw do
        local ref = ref.misc.compensate_throw

        local GRENADE_IDS = {
            [43] = true, -- Flashbang
            [44] = true, -- HE Grenade
            [45] = true, -- Smoke Grenade
            [46] = true, -- Molotov
            [47] = true, -- Decoy
            [48] = true, -- Incendiary
        }

        local THROW_VELOCITY = 750

        local air_strafe_ref = { ui.reference('Misc', 'Movement', 'Air strafe') }

        local local_velocity = vector()
        local last_local_velocity = vector()

        local function is_grenade(weapon)
            local weapon_info = csgo_weapons(weapon)
            if weapon_info == nil then return false end
            return GRENADE_IDS[weapon_info.idx] == true
        end

        local function ray_circle_intersection(ray, center, r)
            if math.abs(ray.x) > math.abs(ray.y) then
                local k = ray.y / ray.x

                local a = 1 + k * k
                local b = -2 * center.x - 2 * k * center.y
                local c = center:length2dsqr() - r * r

                local d = b * b - 4 * a * c

                if d < 0 then
                    local dot = center.x * ray.x + center.y * ray.y
                    local nearest = vector(ray.x * dot, ray.y * dot)
                    local diff = vector(nearest.x - center.x, nearest.y - center.y)
                    local diff_len = diff:length2d()
                    if diff_len > 0 then
                        diff.x = diff.x / diff_len
                        diff.y = diff.y / diff_len
                    end
                    return vector(center.x + diff.x * r, center.y + diff.y * r)
                elseif d < 0.001 then
                    local x = -b / (2 * a)
                    local y = k * x
                    return vector(x, y)
                end

                local d_sqrt = math.sqrt(d)

                local x1 = (-b + d_sqrt) / (2 * a)
                local y1 = k * x1
                local dir1 = vector(x1, y1)

                local x2 = (-b - d_sqrt) / (2 * a)
                local y2 = k * x2
                local dir2 = vector(x2, y2)

                local dot1 = ray.x * dir1.x + ray.y * dir1.y
                local dot2 = ray.x * dir2.x + ray.y * dir2.y

                if dot1 > dot2 then return dir1 end
                return dir2
            else
                local k = ray.x / ray.y

                local a = 1 + k * k
                local b = -2 * center.y - 2 * k * center.x
                local c = center:length2dsqr() - r * r

                local d = b * b - 4 * a * c

                if d < 0 then
                    local dot = center.x * ray.x + center.y * ray.y
                    local nearest = vector(ray.x * dot, ray.y * dot)
                    local diff = vector(nearest.x - center.x, nearest.y - center.y)
                    local diff_len = diff:length2d()
                    if diff_len > 0 then
                        diff.x = diff.x / diff_len
                        diff.y = diff.y / diff_len
                    end
                    return vector(center.x + diff.x * r, center.y + diff.y * r)
                elseif d < 0.001 then
                    local y = -b / (2 * a)
                    local x = k * y
                    return vector(x, y)
                end

                local d_sqrt = math.sqrt(d)

                local y1 = (-b + d_sqrt) / (2 * a)
                local x1 = k * y1
                local dir1 = vector(x1, y1)

                local y2 = (-b - d_sqrt) / (2 * a)
                local x2 = k * y2
                local dir2 = vector(x2, y2)

                local dot1 = ray.x * dir1.x + ray.y * dir1.y
                local dot2 = ray.x * dir2.x + ray.y * dir2.y

                if dot1 > dot2 then return dir1 end
                return dir2
            end
        end

        local function calculate_throw_yaw(wish_dir, vel, throw_velocity, throw_strength)
            local dir_normalized = wish_dir:clone()
            dir_normalized.z = 0
            local len2d = dir_normalized:length2d()
            if len2d > 0 then
                dir_normalized.x = dir_normalized.x / len2d
                dir_normalized.y = dir_normalized.y / len2d
            end

            local wish_len = wish_dir:length()
            local cos_pitch = 1
            if wish_len > 0 then
                cos_pitch = (dir_normalized.x * wish_dir.x + dir_normalized.y * wish_dir.y) / wish_len
            end

            local speed = utils.clamp(throw_velocity * 0.9, 15, 750) * (utils.clamp(throw_strength, 0.0, 1.0) * 0.7 + 0.3) * cos_pitch
            local center = vector(vel.x * 1.25, vel.y * 1.25)

            local real_dir = ray_circle_intersection(dir_normalized, center, speed)
            real_dir.x = real_dir.x - center.x
            real_dir.y = real_dir.y - center.y

            local _, yaw = real_dir:angles()
            return yaw
        end

        local function calculate_throw_pitch(wish_dir, wish_z_vel, vel, throw_velocity, throw_strength)
            local speed = utils.clamp(throw_velocity * 0.9, 15, 750) * (utils.clamp(throw_strength, 0.0, 1.0) * 0.7 + 0.3)

            local cur_vel = vector(
                vel.x * 1.25 + wish_dir.x * speed,
                vel.y * 1.25 + wish_dir.y * speed,
                vel.z * 1.25 + wish_dir.z * speed
            )
            local wish_vel = vector(
                vel.x * 1.25 + wish_dir.x * speed,
                vel.y * 1.25 + wish_dir.y * speed,
                wish_z_vel * 1.25 + wish_dir.z * speed
            )

            local ang1_pitch = select(1, cur_vel:angles())
            local ang2_pitch = select(1, wish_dir:angles())

            local ang_diff = ang2_pitch - ang1_pitch

            return ang_diff * (math.cos(math.rad(ang_diff)) + 1) * 0.5
        end

        local function on_setup_command(cmd)
            local me = entity.get_local_player()
            if me == nil then return end

            local weapon = entity.get_player_weapon(me)
            if weapon == nil then return end

            if not is_grenade(weapon) then return end

            local throw_time = entity.get_prop(weapon, 'm_fThrowTime')
            if throw_time == nil or throw_time <= 0 or throw_time < globals.curtime() then return end

            local throw_strength = entity.get_prop(weapon, 'm_flThrowStrength') or 0
            throw_strength = utils.clamp(throw_strength, 0.0, 1.0)

            local vel = vector(entity.get_prop(me, 'm_vecVelocity'))

            last_local_velocity = local_velocity:clone()
            local_velocity = vel:clone()

            local smoothed_velocity = vector(
                (local_velocity.x + last_local_velocity.x) * 0.5,
                (local_velocity.y + last_local_velocity.y) * 0.5,
                (local_velocity.z + last_local_velocity.z) * 0.5
            )

            local pitch = cmd.pitch
            local yaw = cmd.yaw

            local direction = vector():init_from_angles(pitch, yaw)

            local base_vel = vector(
                direction.x * (utils.clamp(THROW_VELOCITY * 0.9, 15, 750) * (throw_strength * 0.7 + 0.3)),
                direction.y * (utils.clamp(THROW_VELOCITY * 0.9, 15, 750) * (throw_strength * 0.7 + 0.3)),
                direction.z * (utils.clamp(THROW_VELOCITY * 0.9, 15, 750) * (throw_strength * 0.7 + 0.3))
            )

            local curent_vel = vector(
                local_velocity.x * 1.25 + base_vel.x,
                local_velocity.y * 1.25 + base_vel.y,
                local_velocity.z * 1.25 + base_vel.z
            )

            local dot = curent_vel.x * direction.x + curent_vel.y * direction.y + curent_vel.z * direction.z

            local target_vel
            if dot > 0.0 then
                target_vel = direction
            else
                local combined = vector(
                    base_vel.x + smoothed_velocity.x * 1.25,
                    base_vel.y + smoothed_velocity.y * 1.25,
                    base_vel.z + smoothed_velocity.z * 1.25
                )
                local combined_len = combined:length()
                if combined_len > 0 then
                    target_vel = vector(combined.x / combined_len, combined.y / combined_len, combined.z / combined_len)
                else
                    target_vel = direction
                end
            end

            cmd.pitch = cmd.pitch + calculate_throw_pitch(
                vector():init_from_angles(cmd.pitch, cmd.yaw),
                0.0,
                smoothed_velocity,
                THROW_VELOCITY,
                throw_strength
            )

            cmd.yaw = calculate_throw_yaw(
                target_vel, last_local_velocity, THROW_VELOCITY, throw_strength
            )

            -- disable air strafe during throw
            override.set(air_strafe_ref[1], false)
        end

        local function on_shutdown()
            override.unset(air_strafe_ref[1])
        end

        local function on_paint_ui()
            local me = entity.get_local_player()
            if me == nil then
                override.unset(air_strafe_ref[1])
                return
            end

            local weapon = entity.get_player_weapon(me)
            if weapon == nil then
                override.unset(air_strafe_ref[1])
                return
            end

            local throw_time = entity.get_prop(weapon, 'm_fThrowTime')
            if throw_time == nil or throw_time <= 0 or throw_time < globals.curtime() then
                override.unset(air_strafe_ref[1])
            end
        end

        local callbacks do
            local function on_enabled(item)
                local value = item:get()

                if not value then
                    override.unset(air_strafe_ref[1])
                end

                utils.event_callback(
                    'shutdown',
                    on_shutdown,
                    value
                )

                utils.event_callback(
                    'paint_ui',
                    on_paint_ui,
                    value
                )

                utils.event_callback(
                    'setup_command',
                    on_setup_command,
                    value
                )
            end

            ref.enabled:set_callback(
                on_enabled, true
            )
        end
    end

end

local menu_gif do
    local MENU_GIF_URL = 'https://raw.githubusercontent.com/lanesuwu/catboy.lua/refs/heads/main/assets/catboy-menu.gif'
    local MENU_GIF_PATH = 'catboy_menu_gif.gif'

    menu_gif = { gif = nil, start_time = globals.realtime() }

    local data = readfile(MENU_GIF_PATH)
    if not data then
        http.get(MENU_GIF_URL, function(s, r)
            if not s or r.status ~= 200 then
                return
            end

            writefile(MENU_GIF_PATH, r.body)
        end)
    end

    client.delay_call(3, function()
        local gif_data = readfile(MENU_GIF_PATH)
        if gif_data then
            local ok, result = pcall(gif_decoder.load_gif, gif_data)
            if ok and result then
                menu_gif.gif = result
            end
        end
    end)
end

client.set_event_callback('paint_ui', function()
    if boot.image and not boot.done then
        local now = globals.realtime()
        local elapsed = now - boot.start_time
        local sx, sy = client.screen_size()
        local img_w, img_h = 1920, 1080

        if elapsed < 0.5 then
            boot.alpha = math.floor((elapsed / 0.5) * 255)
        elseif elapsed < boot.duration - 0.15 then
            boot.alpha = 255
        elseif elapsed < boot.duration then
            boot.alpha = math.floor(((boot.duration - elapsed) / 0.15) * 255)
        else
            boot.done = true
        end

        if not boot.done then

            renderer.rectangle(0, 0, sx, sy, 0, 0, 0, math.floor(boot.alpha * 0.6))
            boot.image:draw(
                sx / 2 - img_w / 2,
                sy / 2 - img_h / 2,
                img_w, img_h,
                255, 255, 255, boot.alpha
            )
        end
    end

    if menu_gif.gif and ui.is_menu_open() then
        local mx, my = ui.menu_position()
        local mw, mh = ui.menu_size()
        local gif = menu_gif.gif
        local draw_x = mx + 10
        local draw_y = my - gif.height + 174

        gif:draw(globals.realtime() - menu_gif.start_time, draw_x, draw_y, 140, 100, 255, 255, 255, 255)
    end
end)
