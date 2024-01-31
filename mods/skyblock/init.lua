skyblock = {}

local storage = minetest.get_mod_storage()

local CEL_SIZE = 256
local CEL_PADDING = 256
local CEL_TOTAL_SIZE = CEL_SIZE + CEL_PADDING

local MAX_WIDTH = 60000
local GRID_WIDTH = math.floor(MAX_WIDTH / CEL_TOTAL_SIZE)
local GRID_VOLUME = GRID_WIDTH * GRID_WIDTH

local MIN_POS = vector.new(-30000, 30000 - CEL_TOTAL_SIZE, -30000)

minetest.register_node("skyblock:wall", {
    drawtype = "airlike",
    -- tiles = {"blank.png^[invert:rgba"},
    pointable = false,
    walkable = true,
    diggable = false,
    paramtype = "light",
    sunlight_propagates = true,
})

local CID_WALL = minetest.get_content_id("skyblock:wall")
local CID_PLATFORM = minetest.get_content_id("default:steelblock")
local PLATFORM_RADIUS = 3

skyblock.get_cel = function(id)
    if id >= GRID_VOLUME then return end

    local grid_x = id % GRID_WIDTH
    local grid_z = math.floor(id / GRID_WIDTH)

    local cel_pos = vector.new(grid_x * CEL_TOTAL_SIZE, 0, grid_z * CEL_TOTAL_SIZE)
    local cel_center = vector.new(CEL_TOTAL_SIZE / 2, CEL_TOTAL_SIZE / 2, CEL_TOTAL_SIZE / 2):floor()
    local cel_padded = cel_pos + vector.new(CEL_PADDING / 2, CEL_PADDING / 2, CEL_PADDING / 2)

    return {
        pos = MIN_POS + cel_pos,
        center = MIN_POS + cel_center,
        bounds = {
            min = MIN_POS + cel_padded,
            max = MIN_POS + cel_padded + vector.new(CEL_SIZE - 1, CEL_SIZE - 1, CEL_SIZE - 1)
        }
    }
end

local function generate_cuboid(pos1, pos2, buffer, content_id)
    local vm = minetest.get_voxel_manip(pos1, pos2)
    local emin, emax = vm:get_emerged_area()
    vm:get_data(buffer)

    local va = VoxelArea(emin, emax)
    for idx in va:iterp(pos1, pos2) do
        buffer[idx] = content_id
    end

    vm:set_data(buffer)
    vm:write_to_map(true)
end

local function generate_wall(pos1, pos2, buffer)
    generate_cuboid(pos1, pos2, buffer, CID_WALL)
end

skyblock.generate_cel = function(id)
    local cel = skyblock.get_cel(id)
    local buffer = {}

    local min = cel.bounds.min - vector.new(1, 1, 1)
    local max = cel.bounds.max + vector.new(1, 1, 1)
    local width = CEL_SIZE + 1

    generate_wall(min, min + vector.new(width, width, 0), buffer)
    generate_wall(min, min + vector.new(0, width, width), buffer)
    generate_wall(min + vector.new(width, 0, 0), max, buffer)
    generate_wall(min + vector.new(0, width, 0), max, buffer)
    generate_wall(min + vector.new(0, 0, width), max, buffer)

    local plat_min = cel.center - vector.new(PLATFORM_RADIUS - 1, 0, PLATFORM_RADIUS - 1)
    local plat_max = cel.center + vector.new(PLATFORM_RADIUS, 0, PLATFORM_RADIUS)

    generate_cuboid(plat_min, plat_max, buffer, CID_PLATFORM)

    return cel
end

skyblock.get_player_cel = function(name)
    local id = tonumber(storage:get_string(name))
    if id then return skyblock.get_cel(id) end
end

skyblock.set_home = function(player, pos)
    player:get_meta():set_string("skyblock:home", minetest.pos_to_string(pos, 2))
end

skyblock.get_home = function(player)
    local home = player:get_meta():get_string("skyblock:home")
    if home == "" then return end

    return minetest.string_to_pos(home)
end

skyblock.allocate_cel = function(name)
    local player = minetest.get_player_by_name(name)
    if not player then return end

    local existing = skyblock.get_player_cel(name)
    if existing then return existing end

    local id = storage:get_int("next_cel")
    storage:set_int("next_cel", id + 1)

    local cel = skyblock.generate_cel(id)

    storage:set_string(name, tostring(id))
    storage:set_string(tostring(id), name)

    skyblock.set_home(player, cel.center + vector.new(0.5, 1, 0.5))

    return cel
end

skyblock.current_players = {}

skyblock.enter_cel = function(name)
    local player = minetest.get_player_by_name(name)
    if player and skyblock.get_player_cel(name) then
        player:get_meta():set_int("skyblock:in_skyblock", 1)
        player:set_pos(skyblock.get_home(player))
        skyblock.current_players[name] = true
    end
end

skyblock.exit_cel = function(name, pos)
    local player = minetest.get_player_by_name(name)
    if player  then
        player:get_meta():set_int("skyblock:in_skyblock", 0)
        player:set_pos(pos)
    end

    skyblock.current_players[name] = nil
end

skyblock.handle_bounds = function(player, pos)
    local cel = skyblock.get_player_cel(player:get_player_name())
    if not cel then return end

    local bounds = cel.bounds

    if pos.x < bounds.min.x - 1   or pos.x > bounds.max.x + 1   or
       pos.y < bounds.min.y - 1.5 or pos.y > bounds.max.y - 0.5 or
       pos.z < bounds.min.z - 1   or pos.z > bounds.max.z + 1   then

        player:set_pos(skyblock.get_home(player))
    end
end

local interval = 0.5
local timer = 0
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer >= interval then
        while timer > interval do
            timer = timer - interval
        end

        for name in pairs(skyblock.current_players) do
            local player = minetest.get_player_by_name(name)
            local pos = player:get_pos()

            skyblock.handle_bounds(player, pos)
        end
    end
end)

minetest.register_on_joinplayer(function(player)
    if player:get_meta():get_int("skyblock:in_skyblock") > 0 then
        skyblock.current_players[player:get_player_name()] = true
    end
end)

minetest.register_on_leaveplayer(function(player)
    skyblock.current_players[player:get_player_name()].current_players = nil
end)