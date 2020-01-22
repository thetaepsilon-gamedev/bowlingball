-- detect slopes using glorious MT 5.x raycasting.
-- entity is assumed to have a hitbox of fixed half-diameter (imitating a radius),
-- e.g. {-r,-r,-r,r,r,r}.

-- amount to push past the edge of the entity to avoid intersecting self.
local tiny = 0.0001

-- some table re-use to avoid allocations.
local mk_getray = function(raycast)
	local p1 = {}
	local p2 = {}

	return function(x, y1, z, y2, r)
		p1.x = x
		p1.y = y1
		p1.z = z
		p2.x = x
		p2.y = y2
		p2.z = z

		local cast = raycast(p1, p2, true, true)
		local pointed_thing = cast:next()

		-- if we didn't find anything, assume a max distance of r.
		-- this is to prevent slope calculations going to infinity.
		if not pointed_thing then return r end

		-- otherwise, get exact intersection and return Y difference
		local pos = assert(pointed_thing.intersection_point)
		return y1 - pos.y
	end
end



local middle = function(a, b)
	return (a + b) * 0.5
end

local calc_dxz = function(nn, np, pn, pp)
	-- given the four corners already casted,
	-- we calculate the centre points and use that to determine dy/dx and dy/dz.
	local xn = middle(nn, np)
	local xp = middle(pn, pp)
	local zn = middle(nn, pn)
	local zp = middle(np, pp)

	local dydx = xp - xn
	local dydz = zp - zn
	return dydx, dydz
end



return function(raycast) -- dependency injection
	local ray = mk_getray(raycast)

	local detect = function(ox, oy, oz, r)
		-- bump the radius to avoid self intersection as above.
		local r = r + tiny
		-- nn, np, etc - negative or positive for x, z in that order
		local down = oy - r
		local nn = ray(ox-r, oy, oz-r, down, r)
		local np = ray(ox-r, oy, oz+r, down, r)
		local pn = ray(ox+r, oy, oz-r, down, r)
		local pp = ray(ox+r, oy, oz+r, down, r)

		return nn, np, pn, pp, calc_dxz(nn, np, pn, pp)
	end

	return detect
end

