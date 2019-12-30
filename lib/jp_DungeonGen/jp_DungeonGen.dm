/*
	This datum is the heart of the generator. It provides the interface - you create a
	jp_DungeonGenerator object, twiddle some parameters, call a procedure, and then grab
	the results.
*/
jp_DungeonGenerator
	var
		turf/corner1 //One corner of the rectangle the algorithm is allowed to modify
		turf/corner2 //The other corner of the rectangle the algorithm is allowed to modify

		list/allowedRooms //The list of rooms the algorithm may place

		doAccurateRoomPlacementCheck = FALSE //Whether the algorithm should just use AABB collision detection between rooms, or use the slower version with no false positives
		usePreexistingRegions = FALSE //Whether the algorithm should find any already extant open regions in the area it is working on, and incorporate them into the dungeon being generated

		floortype //The type used for open floors placed in corridors
		list/walltype //Either a single type, or a list of types that are considered 'walls' for the purpose of this algorithm

		numRooms //The upper limit of the number of 'rooms' placed in the dungeon. NOT GUARANTEED TO BE REACHED
		numExtraPaths //The upper limit on the number of extra paths placed beyond those required to ensure connectivity. NOT GUARANTEED TO BE REACHED
		maximumIterations = 100 //The number of do-nothing iterations before the generator gives up with an error.
		roomMinSize //The minimum 'size' passed to rooms.
		roomMaxSize //The maximum 'size' passed to rooms.
		maxPathLength //The absolute maximum length paths are allowed to be.
		minPathLength //The absolute minimum length paths are allowed to be.
		minLongPathLength //The absolute minimum length of a long path
		pathEndChance //The chance of terminating a path when it's found a valid endpoint, as a percentage
		longPathChance //The chance that any given path will be designated 'long'

		list
			border_turfs //Internal list. No touching, unless you really know what you're doing.
			examined //Internal list, used for pre-existing region stuff

		out_numRooms //The number of rooms the generator managed to place
		out_numPaths //The total number of paths the generator managed to place. This includes those required for reachability as well as 'extra' paths, as well as all long paths.
		out_numLongPaths //The number of long paths the generator managed to place. This includes those required for reachability, as well as 'extra' paths.
		out_error //0 if no error, positive value if a fatal error occured, negative value if something potentially bad but not fatal happened
		out_time //How long it took, in ms. May be negative if the generator runs 'over' midnight that is, starts in one day, ends in another.
		out_seed //What seed was used to power the RNG for the dungeon.
		jp_DungeonRegion/out_region //The jp_DungeonRegion object that we were left with after all the rooms were connected

		list
			jp_DungeonRoom/out_rooms //A list containing all the jp_DungeonRoom datums placed on the map

		const
			ERROR_NO_ROOMS = 1 //The allowed-rooms list is empty or bad.
			ERROR_BAD_AREA = 2 //The area that the generator is allowed to work on was specified badly
			ERROR_NO_WALLTYPE = 3 //The type used for walls wasn't specified
			ERROR_NO_FLOORTYPE = 4 //The type used for floors wasn't specified
			ERROR_NUMROOMS_BAD = 5 //The number of rooms to draw was a bad number
			ERROR_NUMEXTRAPATHS_BAD = 6 //The number of extra paths to draw was a bad number
			ERROR_ROOM_SIZE_BAD = 7 //The specified room sizes (either max or min) include a bad number
			ERROR_PATH_LENGTH_BAD = 8 //The specified path lengths (either max or min) include a bad number
			ERROR_PATHENDCHANCE_BAD = 9 //The pathend chance is a bad number
			ERROR_LONGPATHCHANCE_BAD = 10 //The chance of getting a long path was a bad number

			ERROR_MAX_ITERATIONS_ROOMS = -1 //Parameters were fine, but maximum iterations was reached while placing rooms. This is not necessarily a fatal error condition - it just means not all the rooms you specified may have been placed. This error may be masked by errors further along in the process.
			ERROR_MAX_ITERATIONS_CONNECTIVITY = 11 //Parameters were fine, but maximum iterations was reached while ensuring connectivity. If you get this error, there are /no/ guarantees about reachability - indeed, you may end up with a dungeon where no room is reachable from any other room.
			ERROR_MAX_ITERATIONS_EXTRAPATHS = -2 //Parameters were fine, but maximum iterations was reached while placing extra paths after connectivity was ensured. The dungeon should be fine, all the rooms should be reachable, but it may be less interesting. Or you may just have asked to place too many extra paths.

	proc
		/***********************************************************************************
		 *	Internal procedures. Might be useful if you're writing a /jp_DungeonRoom datum.*
		 *	Probably not useful if you just want to make a simple dungeon				   *
		 ***********************************************************************************/

		/*
			Returns a list of turfs adjacent to the turf 't'. The definition of 'adjacent'
			may depend on various properties set - at the moment, it is limited to the turfs
			in the four cardinal directions.
		*/
		getAdjacent(turf/t)
			//Doesn't just go list(get_step(blah blah), get_step(blah blah) etc. because that could return null if on the border of the map
			.=list()
			var/k = get_step(t,NORTH)
			if(k).+=k
			k = get_step(t,SOUTH)
			if(k).+=k
			k = get_step(t,EAST)
			if(k).+=k
			k = get_step(t,WEST)
			if(k).+=k

		/*
			Returns 'true' if the turf 't' is of one of the types specified as a wall by the
			parameters of the generator. False otherwise.
		*/
		isWall(turf/t)
			if(islist(walltype)) return t.type in walltype
			return t.type == walltype

		/*
			Returns 'true' if l is a list, false otherwise
		*/
		islist(l)
			return istype(l, /list)

		/***********************************************************************************
		 *	External procedures, intended to be used by user code.						   *
		 ***********************************************************************************/

		/*
			Returns a string representation of the error you pass into it.
			So you'd call g.errString(g.out_error)
		*/
		errString(e)
			switch(e)
				if(0) return "No error"
				if(ERROR_NO_ROOMS) return "The allowedRooms list was either empty, or an illegal value"
				if(ERROR_BAD_AREA) return "The area that the generator is allowed to work on was either empty, or crossed a z-level"
				if(ERROR_NO_WALLTYPE) return "The types that are walls were either not specified, or weren't a typepath or list of typepaths"
				if(ERROR_NO_FLOORTYPE) return "The type used for floors either wasn't specified, or wasn't a typepath"
				if(ERROR_NUMROOMS_BAD) return "The number of rooms to place was either negative, or not an integer"
				if(ERROR_NUMEXTRAPATHS_BAD) return "The number of extra paths to place was either negative, or not an integer"
				if(ERROR_ROOM_SIZE_BAD) return "One of the minimum and maximum room sizes was negative, or not an integer. Alternatively, the minimum room size was larger than the maximum room size"
				if(ERROR_PATH_LENGTH_BAD) return "One of the path-length parameters was negative, or not an integer. Alternatively, either minimum path length or minimum long path length was larger than maximum path length"
				if(ERROR_PATHENDCHANCE_BAD) return "The pathend chance was either less than 0 or greater than 100"
				if(ERROR_LONGPATHCHANCE_BAD) return "The long-path chance was either less than 0, or greater than 100"
				if(ERROR_MAX_ITERATIONS_ROOMS) return "Maximum iterations was reached while placing rooms on the map. The number of rooms you specified may not have been placed. The dungeon should still be usable"
				if(ERROR_MAX_ITERATIONS_CONNECTIVITY) return "Maximum iterations was reached while ensuring connectivity. No guarantees can be made about reachability. This dungeon is likely unusable"
				if(ERROR_MAX_ITERATIONS_EXTRAPATHS) return "Maximum iterations was reached while placing extra paths. The number of extra paths you specified may not have been placed. The dungeon should still be usable"

		/*
			Sets the number of rooms that will be placed in the dungeon to 'r'.
			Positive integers only
		*/
		setNumRooms(r)
			numRooms = r

		/*
			Returns the number of rooms that will be placed in the dungeon
		*/
		getNumRooms()
			return numRooms

		/*
			Sets the number of 'extra' paths that will be placed in the dungeon - 'extra'
			in that they aren't required to ensure reachability
		*/
		setExtraPaths(p)
			numExtraPaths = p

		/*
			Returns the number of extra paths that will be placed in the dungeon
		*/
		getExtraPaths()
			return numExtraPaths

		/*
			Sets the maximum number of do-nothing loops that can occur in a row before the
			generator gives up and does something else.
		*/
		setMaximumIterations(i)
			maximumIterations = i

		/*
			Gets the maximum number of do-nothing loops that can occur in a row
		*/
		getMaximumIterations()
			return maximumIterations

		/*
			Sets and gets the maximum and minimum sizes used for rooms placed on the dungeon.
			m must be a positive integer.
		*/
		setRoomMinSize(m, typepath="")
			roomMinSize = m
		getRoomMinSize(typepath="")
			return roomMinSize
		setRoomMaxSize(m, typepath="")
			roomMaxSize = m
		getRoomMaxSize(typepath="")
			return roomMaxSize


		/*
			Sets and gets the maximum and minimum lengths used for paths drawn between rooms
			in the dungeon, including 'long' paths (Which are required to be of a certain length)
			m must be a positive integer.
		*/
		setMaxPathLength(m)
			maxPathLength = m
		setMinPathLength(m)
			minPathLength = m
		setMinLongPathLength(m)
			minLongPathLength = m
		getMaxPathLength()
			return maxPathLength
		getMinPathLength()
			return minPathLength
		getMinLongPathLength()
			return minLongPathLength

		/*
			Sets and gets the chance of a path ending when it finds a suitable end turf.
			c must be a number between 0 and 100, inclusive
		*/
		setPathEndChance(c)
			pathEndChance = c
		getPathEndChance()
			return pathEndChance

		/*
			Sets and gets the chance of a path being designated a 'long' path, which has
			a different minimum length to a regular path. c must be a number between 0
			and 100, inclusive.
		*/
		setLongPathChance(c)
			longPathChance = c
		getLongPathChance()
			return longPathChance

		/*
			Sets the area that the generator is allowed to touch. This is required to be a
			rectangle. The parameters 'c1' and 'c2' specify the corners of the rectangle. They
			can be any two opposite corners. The generator does /not/ work over z-levels.
		*/
		setArea(turf/c1, turf/c2)
			corner1 = c1
			corner2 = c2

		/*
			Returns a list containing two of the corners of the area the generator is allowed to touch.
			Returns a list of nulls if the area isn't specified
		*/
		getArea()
			return list(corner1, corner2)

		/*
			Returns the smallest x-value that the generator is allowed to touch.
			Returns null if the area isn't specified.
		*/
		getMinX()
			if(!corner1||!corner2) return null
			return min(corner1.x, corner2.x)

		/*
			Returns the largest x-value that the generator is allowed to touch
			Returns null if the area isn't specified.
		*/
		getMaxX()
			if(!corner1||!corner2) return null
			return max(corner1.x, corner2.x)

		/*
			Returns the smallest y-value that the generator is allowed to touch.
			Returns null if the area isn't specified.
		*/
		getMinY()
			if(!corner1||!corner2) return null
			return min(corner1.y, corner2.y)

		/*
			Returns the largest y-value that the generator is allowed to touch
			Returns null if the area isn't specified.
		*/
		getMaxY()
			if(!corner1||!corner2) return null
			return max(corner1.y, corner2.y)

		/*
			Returns the Z-level that the generator operates on
			Returns null if the area isn't specified.
		*/
		getZ()
			if(!corner1||!corner2) return null
			return corner1.z

		/*
			Sets the list of jp_DungeonRooms allowed in this dungeon to 'l'.
			'l' should be a list of types.
		*/
		setAllowedRooms(list/l)
			allowedRooms = list()
			for(var/k in l)	allowedRooms["[k]"] = new /jp_DungeonRoomEntry(k)

		/*
			Adds the type 'r' to the list of allowed jp_DungeonRooms. Will create
			the list if it doesn't exist yet.
		*/
		addAllowedRoom(r, maxsize=-1, minsize=-1, required=-1, maxnum=-1)
			if(!allowedRooms) allowedRooms = list()
			allowedRooms["[r]"] = new /jp_DungeonRoomEntry(r, maxsize, minsize, required, maxnum)

		/*
			Removes the type 'r' from the list of allowed jp_DungeonRooms. Will create
			the list if it doesn't exist yet.
		*/
		removeAllowedRoom(r)
			allowedRooms["[r]"] = null
			if(!allowedRooms || !allowedRooms.len) allowedRooms = null

		/*
			Returns the list of allowed jp_DungeonRooms. This may be null, if the list is empty
		*/
		getAllowedRooms()
			if(!allowedRooms) return null
			var/list/l = list()
			for(var/k in allowedRooms) l+=text2path(k)
			return l

		/*
			Sets the accurate room placement check to 'b'.
		*/
		setDoAccurateRoomPlacementCheck(b)
			doAccurateRoomPlacementCheck = b

		/*
			Gets the current value of the accurate room placement check
		*/
		getDoAccurateRoomPlacementCheck()
			return doAccurateRoomPlacementCheck


		/*
			Sets the use-preexisting-regions check to 'b'
		*/
		setUsePreexistingRegions(b)
			usePreexistingRegions = b

		/*
			Gets the current value of the use-preexisting-regions check
		*/
		getUsePreexistingRegions()
			return usePreexistingRegions

		/*
			Sets the type used for floors - both in corridors, and in some rooms - to 'f'
		*/
		setFloorType(f)
			floortype = f

		/*
			Gets the type used for floors.
		*/
		getFloorType()
			return floortype

		/*
			Sets the type/s detected as 'wall' to either the typepath 'w' or
			the list of typepaths 'w'
		*/
		setWallType(w)
			walltype = w

		/*
			Adds the typepath 'w' to the list of types considered walls.
		*/
		addWallType(w)
			if(!walltype) walltype = list()
			if(!islist(walltype)) walltype = list(walltype)
			walltype+=w

		/*
			Removes 'w' from the list of types considered walls
		*/
		removeWallType(w)
			if(!islist(walltype))
				if(walltype==w) walltype = null
				return
			walltype-=w

		/*
			Gets the types considered walls. This may be null, a typepath, or a list of typepaths
		*/
		getWallType()
			return walltype

		/*
			Actually goes out on a limb and generates the dungeon. This procedure runs in the
			background, because it's very slow. The various out_ variables will be updated after
			the generator has finished running. I suggest spawn()ing off the call to the generator.

			After this procedure finishes executing, you should have a beautiful shiny dungeon,
			with all rooms reachable from all other rooms. If you don't, first check the parameters
			you've passed to the generator - if you've set the number of rooms to 0, or haven't set
			it, you may not get the results you expect. If the parameters you've passed seem fine,
			and you've written your own /jp_DungeonRoom object, it might be a good idea to check whether'
			or not you meet all the assumptions my code makes about jp_DungeonRoom objects. There should
			be a reasonably complete list in the helpfile. If that doesn't help you out, contact me in
			some way - you may have found a bug, or an assumption I haven't documented, or I can show
			you where you've gone wrong.
		*/
		generate(seed=null)
			set background = 1
			if(!check_params()) return
			out_numPaths = 0
			out_numLongPaths = 0
			var
				tempseed = rand(-65535, 65535)
				numits
				paths
				jp_DungeonRoomEntry/nextentry
				jp_DungeonRoom/nextroom
				list/jp_DungeonRoom/rooms = list()
				list/jp_DungeonRegion/regions = list()
				list/jp_DungeonRoomEntry/required = list()
				turf/nextloc

				minx
				maxx
				miny
				maxy
				z

				jp_DungeonRegion/region1
				jp_DungeonRegion/region2

				timer = world.timeofday

			if(seed==null)
				out_seed = rand(-65535, 65535)
				rand_seed(out_seed)
			else
				out_seed = seed
				rand_seed(seed)

			z = corner1.z
			minx = min(corner1.x, corner2.x) + roomMaxSize + 1
			maxx = max(corner1.x, corner2.x) - roomMaxSize - 1
			miny = min(corner1.y, corner2.y) + roomMaxSize + 1
			maxy = max(corner1.y, corner2.y) - roomMaxSize - 1

			if(minx>maxx || miny>maxy)
				out_error = ERROR_BAD_AREA
				return

			if(usePreexistingRegions)
				examined = list()
				for(var/turf/t in block(locate(getMinX(), getMinY(), getZ()), locate(getMaxX(), getMaxY(), getZ())))
					if(!isWall(t)) if(!(t in examined)) rooms+=regionCreate(t)

			for(var/k in allowedRooms)
				nextentry = allowedRooms[k]
				if(nextentry.required>0) required+=nextentry

			var/rooms_placed = 0
			while(rooms_placed<numRooms)
				if(numits>maximumIterations)
					out_error=ERROR_MAX_ITERATIONS_ROOMS
					break

				nextloc = locate(rand(minx, maxx), rand(miny, maxy), z)

				if(!required.len) nextentry = allowedRooms[pick(allowedRooms)]
				else
					nextentry = required[1]
					if(nextentry.count>=nextentry.required)
						required-=nextentry
						continue
				if(nextentry.maxnum>-1 && nextentry.count>=nextentry.maxnum) continue
				nextroom = new nextentry.roomtype(rand((nextentry.minsize<0)?(roomMinSize):(nextentry.minsize), (nextentry.maxsize<0)?(roomMaxSize):(nextentry.maxsize)), nextloc, src)
				numits++
				if(!nextroom.ok()) continue
				if(!rooms || !intersects(nextroom, rooms))
					nextroom.place()
					numits=0
					rooms+=nextroom
					rooms_placed++
					nextentry.count++

			border_turfs = list()

			for(var/jp_DungeonRoom/r in rooms)
				if(!r.doesMultiborder())
					var/jp_DungeonRegion/reg = new /jp_DungeonRegion(src)
					reg.addTurfs(r.getTurfs(), 1)
					reg.addBorder(r.getBorder())
					regions+=reg
					border_turfs+=reg.getBorder()
				else
					for(var/l in r.getMultiborder())
						var/jp_DungeonRegion/reg = new /jp_DungeonRegion(src)
						reg.addTurfs(r.getTurfs(), 1)
						reg.addBorder(l)
						regions+=reg
						border_turfs+=l

			for(var/turf/t in border_turfs)
				for(var/turf/t2 in range(t, 1))
					if(isWall(t2)&&!(t2 in border_turfs))
						for(var/turf/t3 in range(t2, 1))
							if(!isWall(t3))
								border_turfs+=t2
								break

			numits = 0
			paths = numExtraPaths

			while(regions.len>1 || paths>0)
				if(numits>maximumIterations)
					if(regions.len>1) out_error = ERROR_MAX_ITERATIONS_CONNECTIVITY
					else out_error = ERROR_MAX_ITERATIONS_EXTRAPATHS
					break
				numits++
				region1 = pick(regions)
				region2 = pick(regions)

				if(region1==region2) if(regions.len>1) continue

				var/list/turf/path = getPath(region1, region2, regions)

				if(!path || !path.len) continue

				numits = 0

				if(region1==region2) if(regions.len<=1) paths--

				for(var/turf/t in path)
					path-=t
					path+=new floortype(t)

				region1.addTurfs(path)

				if(region1!=region2)
					region1.addTurfs(region2.getTurfs(), 1)
					region1.addBorder(region2.getBorder())
					regions-=region2

				for(var/turf/t in region1.getBorder()) if(!(t in border_turfs)) border_turfs+=t
				for(var/turf/t in path)	for(var/turf/t2 in range(t, 1))	if(!(t2 in border_turfs)) border_turfs+=t2

			for(var/jp_DungeonRoom/r in rooms) r.finalise()
			out_time = (world.timeofday-timer)
			out_rooms = rooms
			out_region = region1
			out_numRooms = out_rooms.len
			rand_seed(tempseed)

		/***********************************************************************************
		 *	The remaining procedures are seriously internal, and I strongly suggest not    *
		 *  touching them unless you're certain you know what you're doing. That includes  *
		 *  calling them, unless you've figured out what the side-effects and assumptions  *
		 *  of the procedure are. These may not work except in the context of a generate() *
		 *  call.
		 ***********************************************************************************/

		regionCreate(turf/t)
			var
				size
				centre
				minx=t.x
				miny=t.y
				maxx=t.x
				maxy=t.y
				jp_DungeonRoom/preexist/r
				list/border = list()
				list/turfs = list()
				list/walls = list()
				list/next = list(t)

			while(next.len>=1)
				var/turf/nt = next[next.len]

				next-=nt
				examined+=nt
				if(nt.x<getMinX() || nt.x>getMaxX() || nt.y<getMinY() || nt.y>getMaxY()) continue
				if(isWall(nt))
					border+=nt
					continue

				if(nt.x<minx) minx=nt.x
				if(nt.x>maxx) maxx=nt.x
				if(nt.y<miny) miny=nt.y
				if(nt.y>maxy) maxy=nt.y
				if(!nt.density)
					turfs+=nt
					for(var/turf/t2 in getAdjacent(nt))	if(!((t2 in border) || (t2 in turfs))) next+=t2
				else
					walls+=nt

			size = max(maxy-miny, maxx-minx)
			size/=2
			size = round(size+0.4, 1)
			centre = locate(minx+size, miny+size, getZ())

			r=new /jp_DungeonRoom/preexist(size, centre, src)
			r.setBorder(border)
			r.setTurfs(turfs)
			r.setWalls(walls)

			return r

		/*
			Checks if two jp_DungeonRooms are too close to each other
		*/
		intersects(jp_DungeonRoom/newroom, list/jp_DungeonRoom/rooms)
			for(var/jp_DungeonRoom/r in rooms)
				. = newroom.getSize() + r.getSize()+2
				if((. > abs(newroom.getX() - r.getX())) && (. > abs(newroom.getY() - r.getY())))
					if(!doAccurateRoomPlacementCheck) return TRUE
					if(!(newroom.doesAccurate() && r.doesAccurate())) return TRUE
					var
						intx1=-1
						intx2=-1
						inty1=-1
						inty2=-1

						rx1 = r.getX()-r.getSize()-1
						rx2 = r.getX()+r.getSize()+1
						sx1 = newroom.getX()-newroom.getSize()-1
						sx2 = newroom.getX()+newroom.getSize()+1

						ry1 = r.getY()-r.getSize()-1
						ry2 = r.getY()+r.getSize()+1
						sy1 = newroom.getY()-newroom.getSize()-1
						sy2 = newroom.getY()+newroom.getSize()+1

					if(rx1>=sx1 && rx1<=sx2) intx1 = rx1
					if(rx2>=sx1 && rx2<=sx2)
						if(intx1<0) intx1=rx2
						else intx2 = rx2
					if(sx1>rx1 && sx1<rx2)
						if(intx1<0) intx1 = sx1
						else intx2 = sx1
					if(sx2>rx1 && sx2<rx2)
						if(intx1<0) intx1 = sx2
						else intx2 = sx2

					if(ry1>=sy1 && ry1<=sy2) inty1 = ry1
					if(ry2>=sy1 && ry2<=sy2)
						if(inty1<0) inty1=ry2
						else inty2 = ry2
					if(sy1>ry1 && sy1<ry2)
						if(inty1<0) inty1 = sy1
						else inty2 = sy1
					if(sy2>ry1 && sy2<ry2)
						if(inty1<0) inty1 = sy2
						else inty2 = sy2

					for(var/turf/t in block(locate(intx1, inty1, getZ()), locate(intx2, inty2, getZ())))
						var/ret = (t in newroom.getTurfs()) + (t in newroom.getBorder()) + (t in newroom.getWalls()) + (t in r.getTurfs()) + (t in r.getBorder()) + (t in r.getWalls())
						if(ret>1) return TRUE
			return FALSE

		/*
			Constructs a path between two jp_DungeonRegions.
		*/
		getPath(jp_DungeonRegion/region1, jp_DungeonRegion/region2)
			var/turf/start = pick(region1.getBorder())
			var/turf/end
			var/long = FALSE
			var/minlength = minPathLength
			if(prob(longPathChance))
				minlength=minLongPathLength
				long = TRUE

			var/list/borders=list()
			borders.Add(border_turfs)
			borders.Remove(region2.getBorder())

			borders-=start

			var/list/turf/previous = list()
			var/list/turf/done = list(start)
			var/list/turf/next = getAdjacent(start)
			var/list/turf/cost = list("\ref[start]"=0)

			if(minlength<=0)
				if(start in region2.getBorder())
					out_numPaths++
					if(long) out_numLongPaths++
					end = start
					goto endloop //Oooo, I feel naughty.

			next-=borders
			for(var/turf/t in next)
				if(!isWall(t)) next-=t
				previous["\ref[t]"] = start
				cost["\ref[t]"]=1
			if(!next.len) return list()

			while(1)
				var/turf/min
				var/mincost = maxPathLength

				for(var/turf/t in next)
					if((cost["\ref[t]"]<mincost) || (cost["\ref[t]"]==mincost && prob(50)))
						min = t
						mincost=cost["\ref[t]"]

				if(!min) return list()

				done += min
				next -= min

				if(min in region2.getBorder())
					if(mincost>minlength && prob(pathEndChance))
						out_numPaths++
						if(long) out_numLongPaths++
						end = min
						break
					else
						continue

				for(var/turf/t in getAdjacent(min))
					if(isWall(t) && !(t in borders))
						if(!(t in done) && !(t in next))
							next+=t
							previous["\ref[t]"] = min
							cost["\ref[t]"] = mincost+1

			endloop:
			var/list/ret = list(end)
			var/turf/last = end
			while(1)
				if(last==start) break
				ret+=previous["\ref[last]"]
				last=previous["\ref[last]"]

			return ret

		check_params()
			if(!islist(allowedRooms) || allowedRooms.len<=0)
				out_error = ERROR_NO_ROOMS
				return 0

			if(!corner1 || !corner2 || corner1.z!=corner2.z)
				out_error = ERROR_BAD_AREA
				return 0

			if(!walltype || (islist(walltype) && walltype.len<=0))
				out_error = ERROR_NO_WALLTYPE
				return 0

			if(islist(walltype))
				for(var/k in walltype)
					if(!ispath(k))
						out_error = ERROR_NO_WALLTYPE
						return 0
			else
				if(!ispath(walltype))
					out_error = ERROR_NO_WALLTYPE
					return 0

			if(!floortype || !ispath(floortype))
				out_error = ERROR_NO_FLOORTYPE
				return 0

			if(numRooms<0 || round(numRooms)!=numRooms)
				out_error = ERROR_NUMROOMS_BAD
				return 0

			if(numExtraPaths<0 || round(numExtraPaths)!=numExtraPaths)
				out_error = ERROR_NUMEXTRAPATHS_BAD
				return 0

			if(roomMinSize>roomMaxSize || roomMinSize<0 || roomMaxSize<0 || round(roomMinSize)!=roomMinSize || round(roomMaxSize)!=roomMaxSize)
				out_error = ERROR_ROOM_SIZE_BAD
				return 0

			if(minPathLength>maxPathLength || minLongPathLength>maxPathLength || minPathLength<0 || maxPathLength<0 || minLongPathLength<0 || round(minPathLength)!=minPathLength || round(maxPathLength)!=maxPathLength || round(minLongPathLength)!=minLongPathLength)
				out_error = ERROR_PATH_LENGTH_BAD
				return 0

			if(pathEndChance<0 || pathEndChance>100)
				out_error = ERROR_PATHENDCHANCE_BAD
				return 0

			if(longPathChance<0 || longPathChance>100)
				out_error = ERROR_LONGPATHCHANCE_BAD
				return 0

			return 1

/*
	Seriously internal. No touching, unless you really know what you're doing. It's highly
	unlikely that you'll need to modify this
*/
jp_DungeonRoomEntry
	var
		roomtype //The typepath of the room this is an entry for
		maxsize //The maximum size of the room. -1 for default.
		minsize //The minimum size of the room. -1 for default

		required //The number of rooms of this type that must be placed in the dungeon. 0 for no requirement.
		maxnum //The maximum number of rooms of this type that can be placed in the dungeon. -1 for no limit
		count //The number of rooms that have been placed. Used to ensure compliance with maxnum.

	New(roomtype_n, maxsize_n=-1, minsize_n=-1, required_n=-1, maxnum_n=-1)
		roomtype = roomtype_n
		maxsize = maxsize_n
		minsize = minsize_n
		required = required_n
		maxnum = maxnum_n

/*
	This object is used to represent a 'region' in the dungeon - a set of contiguous floor turfs,
	along with the walls that border them. This object is used extensively by the generator, and
	has several assumptions embedded in it - think carefully before making changes
*/
jp_DungeonRegion
	var
		jp_DungeonGenerator/gen //A reference to the jp_DungeonGenerator using us
		list/turf/contained = list() //A list of the floors contained by the region
		list/turf/border = list() //A list of the walls bordering the floors of this region

	/*
		Make a new jp_DungeonRegion, and set its reference to its generator object
	*/
	New(jp_DungeonGenerator/g)
		gen = g

	proc
		/*
			Add a list of turfs to the region, optionally without adding the walls around
			them to the list of borders
		*/
		addTurfs(list/turf/l, noborder=0)
			for(var/turf/t in l)
				if(t in border) border-=t
				if(!(t in contained))
					contained+=t
					if(!noborder)
						for(var/turf/t2 in gen.getAdjacent(t))
							if(gen.isWall(t2) && !(t2 in border)) border+=t2

		/*
			Adds a list of turfs to the border of the region.
		*/
		addBorder(list/turf/l)
			for(var/turf/t in l) if(!(t in border)) border+=t

		/*
			Returns the list of floors in this region
		*/
		getTurfs()
			return contained

		/*
			Returns the list of walls bordering the floors in this region
		*/
		getBorder()
			return border

/*
	These objects are used to represent a 'room' - a distinct part of the dungeon
	that is placed at the start, and then linked together. You will quite likely
	want to create new jp_DungeonRooms. Consult the helpfile for more information
*/
jp_DungeonRoom
	var
		turf/centre //The centrepoint of the room
		size //The size of the room. IMPORTANT: ROOMS MAY NOT TOUCH TURFS OUTSIDE range(centre, size). TURFS INSIDE range(centre,size) MAY BE DEALT WITH AS YOU WILL
		jp_DungeonGenerator/gen //A reference to the generator using this room
		list
			turfs = list() //The list of turfs in this room. That should include internal walls.
			border = list() //The list of walls bordering this room. Anything in this list could be knocked down in order to make a path into the room
			walls = list() //The list of walls bordering the room that aren't used for connections into the room. Should include every wall turf next to a floor turf. May include turfs up to range(centre, size+1)
			multiborder = list() //Only used by rooms that have disjoint sets of borders. A list of lists of turfs. The sub-lists are treated like the border turf list

	/*
		Make a new jp_DungeonRoom, size 's', centre 'c', generator 'g'
	*/
	New(s, turf/c, jp_DungeonGenerator/g)
		size = s
		centre = c
		gen = g

	proc
		/*
			Get various pieces of information about the centrepoint of this room
		*/
		getCentre()
			return centre
		getX()
			return centre.x
		getY()
			return centre.y
		getZ()
			return centre.z

		/*
			Get the size of this room
		*/
		getSize()
			return size

		/*
			Actually place the room on the dungeon. place() is one of the few procedures allowed
			to actually modify turfs in the dungeon - do NOT change turfs outside of place() or
			finalise(). This is called /before/ paths are placed, and may be called /before/ any
			other rooms are placed. If you would like to pretty the room up after basic dungeon
			geometry is done and dusted, use 'finalise()'
		*/
		place()
			return

		/*
			Called on every room after everything has been generated. Use it to pretty up the
			room, or what-have-you. finalise() is the only other jp_DungeonRoom procedure that
			is allowed to modify turfs in the dungeon.
		*/
		finalise()
			return

		/*
			Return the border walls of this room.
		*/
		getBorder()
			return border

		/*
			Return the turfs inside of this room
		*/
		getTurfs()
			return turfs

		getMultiborder()
			return multiborder

		getWalls()
			return walls

		/*
			Returns true if the room is okay to be placed here, false otherwise
		*/
		ok()
			return TRUE

		doesAccurate()
			return FALSE

		doesMultiborder()
			return FALSE

	preexist
		proc
			setBorder(list/l)
				border = l

			setTurfs(list/l)
				turfs = l

			setWalls(list/l)
				walls = l

		doesAccurate()
			return TRUE

	/*
		Class for a simple square room, size*2+1 by size*2+1 units. Border is all turfs adjacent
		to the floor that return true from isWall().
	*/
	square
		doesAccurate()
			return TRUE

		New(s, c, g)
			..(s, c, g)
			for(var/turf/t in range(centre, size)) turfs += t
			for(var/turf/t in turfs) for(var/turf/t2 in gen.getAdjacent(t))
				if(t2 in turfs) continue
				if(gen.isWall(t2) && !(t2 in border)) border+=t2

		place()
			for(var/turf/t in turfs)
				turfs-=t
				turfs+=new gen.floortype(t)

	/*
		A simple circle of radius 'size' units. Border is all turfs adjacent to the floor that
		return true from isWall()
	*/
	circle
		doesAccurate()
			return TRUE

		New(s, c, g)
			..(s, c, g)
			var/radsqr = size*size

			for(var/turf/t in range(centre, size))
				var/ti = t.x-getX()
				var/tj = t.y-getY()

				if(ti*ti + tj*tj>radsqr) continue

				turfs += t

			for(var/turf/t in turfs) for(var/turf/t2 in gen.getAdjacent(t))
				if(t2 in turfs) continue
				if(gen.isWall(t2) && !(t2 in border)) border+=t2

		place()
			for(var/turf/t in turfs)
				turfs-=t
				turfs+=new gen.floortype(t)

	/*
		A giant plus sign, with arms of length size*2 + 1. Border is the turfs on the 'end' of
		the arms of the plus sign - there are only four.
	*/
	cross
		doesAccurate()
			return TRUE

		New(s, c, g)
			..(s, c, g)
			for(var/turf/t in range(centre, size))
				if(t.x == getX() || t.y == getY())
					turfs += t

			for(var/turf/t in range(centre, size+1))
				if(t in turfs) continue
				if(gen.isWall(t) && (t.x == getX() || t.y == getY()))
					border+=t

		place()
			for(var/turf/t in turfs)
				turfs-=t
				turfs+=new gen.floortype(t)