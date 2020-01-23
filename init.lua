--[[
Bowling ball entity:
moves across surfaces without friction,
rebounds if a sudden stop is detected.
]]
local mp = minetest.get_modpath(minetest.get_current_modname()).."/"
local detect = dofile(mp.."slope_handling.lua")(minetest.raycast)

-- returns true if the vector was modified
local dampening = -0.4
local rebound_if_zero = function(oldv, newv, k)
	local v = newv[k]
	--print("# current velocity", k, v)
	local change = v == 0
	if change then
		local r = oldv[k] * dampening
		--print("# changed velocity", k, r)
		newv[k] = r
		return true
	end
	return change
end

-- ball radius - used for some checking around the ball
local r = 0.3
-- scale of acceleration from slope detection.
local ds = 12
-- downwards roll acceleration bias.
local bias = 1.8
-- dampening factor of ball rebound.
local k = -0.3
-- forward declaration of names used in varios functions below.
local ballreturn = "bowlingball:return"
local n = "bowlingball:ball"



-- registration of the bowling ball return block.
-- this node is passive, having no logic of it's own;
-- it serves only as a marker for the entity.
-- see the handle_return() function below to see this behaviour.
local side = "bowlingball_return_side.png"
local hole = "bowlingball_return_hole.png"
minetest.register_node(ballreturn, {
	description = "Bowling ball capture block (roll ball over this)",
	tiles = { hole, hole, side, side, side, side },
	groups = { oddly_breakable_by_hand = 3 },
})



-- handle the ball return node being beneath us.
local offset = r + 0.0001	-- avoid node boundary issues
-- boundary check
local b = function(v)
	return (v % 1.0) == 0.5
end
local round = function(v)
	return math.floor(v + 0.5)
end
local rp_mut = function(p)
	p.x = round(p.x)
	p.y = round(p.y)
	p.z = round(p.z)
	return p
end
local handle_return = function(object)
	local pos = object:get_pos()
	pos.y = pos.y - offset
	-- I've had enough of boundary rounding issues...
	if b(pos.x) or b(pos.y) or b(pos.z) then
		return false
	end

	local node = minetest.get_node(pos)
	local act = (node.name == ballreturn)

	if act then
		-- spawn an item just below that block.
		pos = rp_mut(pos)
		pos.y = pos.y - 0.501
		minetest.add_item(pos, n)
	end

	return act
end



local cast = minetest.raycast



local ve = mtrequire("ds2.minetest.vectorextras")
local mul = ve.scalar_multiply.raw
local vadd = ve.add.raw
local vnew = ve.wrap
local unwrap = ve.unwrap

-- see lua_prelude in devsupport_modpack
local sign = math.sign

local get_axial_rebound = function(px, py, pz, old_speed, new_speed, ax, ay, az)
	-- only perform this rebound check on an abrupt stop.
	if new_speed ~= 0 then
		return new_speed
	end

	-- to get ray endpoints, offset in the provided direction.
	-- the sign of the direction we look in is determined by the sign of the old axial velocity.
	local s = sign(old_speed)

	-- p1 is just outside the entity border (see step() below)
	local p1 = vnew(vadd(px, py, pz, mul(s, ax, ay, az)))

	-- then do the same but step the ray a tiny bit further to see what's there.
	s = s * 1.1
	local p2 = vnew(vadd(px, py, pz, mul(s, ax, ay, az)))
	local ray = cast(p1, p2, true, false)	-- liquids won't have hard stopped us anyway.
	local collided = ray:next()

	-- if there is anything there, rebound in the opposite direction, else remain on course.
	return collided and (k * old_speed) or old_speed
end



local step = function(self, dtime)
	-- first and foremost: check if the block below us is ball return node.
	-- if this indicates that it did anything,
	-- perform no further action and delete ourselves.
	if (handle_return(self.object)) then
		self.object:remove()
		return
	end


	-- on a given axis, check for abrupt stops and cast rays to see if we hit anything.
	local oldv = self.previous
	local px, py, pz = unwrap(self.object:get_pos())
	local newv = self.object:get_velocity()
	local nx, ny, nz = unwrap(newv)

	if oldv then	-- skip if no data available yet from previous tick
		local ra = offset
		local xc = get_axial_rebound(px, py, pz, oldv.x, nx, ra, 0,  0 )
		local yc = get_axial_rebound(px, py, pz, oldv.y, ny, 0,  ra, 0 )
		local zc = get_axial_rebound(px, py, pz, oldv.z, nz, 0,  0,  ra)
		nx = xc
		ny = yc
		nz = zc
	end
	self.previous = newv


	-- apply slope acceleration.
	local _,_,_,_, dx, dz = detect(px, py, pz, r)
	-- if downwards movement is detected, bias the acceleration a bit.
	local b = ((ny < 0) and bias or 1.0)
	nx = nx + (dx * dtime * ds * b)
	nz = nz + (dz * dtime * ds * b)

	-- we may well be constantly updating due to slope acceleration,
	-- so just refresh the velocity anyway.
	self.object:set_velocity(vnew(nx, ny, nz))
end

-- object is fairly dense.
-- also make entity punch operable
local gravity = {x=0,y=-20,z=0}
local groups = { punch_operable = 1 }
local on_activate = function(self)
	-- gravity... is there something better for this
	self.object:set_acceleration(gravity)
	self.object:set_armor_groups(groups)
end



-- let the player retrieve the item by right clicking.
local on_rightclick = function(self, clicker)
	-- check if the player has room in their inventory and add item if so.
	-- if it did fit, then remove the entity.
	local pickup = ItemStack(n)
	local remainder = clicker:get_inventory():add_item("main", pickup)
	local c = remainder:get_count()
	--print("# pickup: remainder count "..c)
	if c == 0 then
		self.object:remove()
	end
end

-- the player can punch the entity to make it roll if stopped
local throw_mult = 5
local on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
	local cvel = self.object:get_velocity()
	local avel = vector.multiply(dir, throw_mult)
	--print(dump(avel))
	local rvel = vector.add(cvel, avel)
	self.object:set_velocity(rvel)
end




local tex = "bowlingball_ball.png"
minetest.register_entity(n, {
	visual = "sprite",
	visual_size = {x=0.75,y=0.75},
	textures = { tex },
	on_activate = on_activate,
	on_step = step,
	physical = true,
	collide_with_objects = true,
	collisionbox = {-r, -r, -r, r, r, r},
	on_rightclick = on_rightclick,
	on_punch = on_punch,
	stepheight = 0.601,
})
-- TNT version

if minetest.get_modpath("tnt") ~= nil then
	local tnt_step = dofile(mp.."tntball_logic.lua")

	minetest.register_entity("bowlingball:tntball", {
		visual = "sprite",
		visual_size = {x=0.75,y=0.75},
		textures = { "bowlingball_tntball.png" },
		-- same armor groups and gravity, currently
		on_activate = on_activate,
		on_step = tnt_step,
		physical = true,
		collide_with_objects = true,
		collisionbox = {-r, -r, -r, r, r, r},
		-- no on_rightclick, can't pick up a bomb... mwuhahahaha
		on_punch = on_punch,
	})
end



-- a throwable ball item.
-- fix a complaint about itemstacks from on_use despite clearly returning one...
-- give it an itemstring instead to keep it happy.
local take_one = function(stack)
	stack:set_count(stack:get_count() - 1)
	return stack:to_string()
end

local head = 1.6
local use = function(itemstack, user, pointed)
	local look = user:get_look_dir()
	local vel = vector.multiply(look, 5)
	local spos = user:get_pos()
	-- damned feet position
	spos.y = spos.y + head
	local ent = minetest.add_entity(spos, n)
	ent:set_velocity(vel)
	return take_one(itemstack)
end



minetest.register_craftitem(n, {
	description = "Throwable bowling ball (punch to toss, RMB to pick up)",
	on_use = use,
	inventory_image = tex,
})
-- optional crafts to follow
dofile(mp.."crafting.lua")


