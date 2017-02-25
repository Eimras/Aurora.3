// This is where the fun begins.
// These are the main datums that emit light.

/datum/light_source
	var/atom/top_atom        // The atom we're emitting light from (for example a mob if we're from a flashlight that's being held).
	var/atom/source_atom     // The atom that we belong to.

	var/turf/source_turf     // The turf under the above.
	var/light_power    	// Intensity of the emitter light.
	var/light_range     // The range of the emitted light.
	var/light_color    	// The colour of the light, string, decomposed by parse_light_color()
	var/light_uv		// The intensity of UV light, between 0 and 255.
	var/light_angle		// The light's emission angle, in degrees.

	// Variables for keeping track of the colour.
	var/lum_r
	var/lum_g
	var/lum_b
	var/lum_u

	// The lumcount values used to apply the light.
	var/tmp/applied_lum_r
	var/tmp/applied_lum_g
	var/tmp/applied_lum_b
	var/tmp/applied_lum_u

	// Variables used to keep track of the atom's angle.
	var/tmp/limit_a_x		// The first test point's X coord for the cone.
	var/tmp/limit_a_y		// The first test point's Y coord for the cone.
	var/tmp/limit_a_t		// The first test point's angle.
	var/tmp/limit_b_x		// The second test point's X coord for the cone.
	var/tmp/limit_b_y		// The second test point's Y coord for the cone.
	var/tmp/limit_b_t		// The second test point's angle.
	var/tmp/cached_origin_x	// The last known X coord of the origin.
	var/tmp/cached_origin_y	// The last known Y coord of the origin.
	var/tmp/old_direction	// The last known direction of the origin.
	var/tmp/targ_sign			
	var/tmp/test_x_offset
	var/tmp/test_y_offset

	var/list/datum/lighting_corner/effect_str     // List used to store how much we're affecting corners.
	var/list/turf/affecting_turfs

	var/applied = FALSE // Whether we have applied our light yet or not.

	var/vis_update      // Whether we should smartly recalculate visibility. and then only update tiles that became (in)visible to us.
	var/needs_update    // Whether we are queued for an update.
	var/destroyed       // Whether we are destroyed and need to stop emitting light.
	var/force_update

/datum/light_source/New(var/atom/owner, var/atom/top)
	source_atom = owner // Set our new owner.
	if (!source_atom.light_sources)
		source_atom.light_sources = list()

	source_atom.light_sources += src // Add us to the lights of our owner.
	top_atom = top
	if (top_atom != source_atom)
		if (!top.light_sources)
			top.light_sources     = list()

		top_atom.light_sources += src

	source_turf = top_atom
	light_power = source_atom.light_power
	light_range = source_atom.light_range
	light_color = source_atom.light_color
	light_uv    = source_atom.uv_intensity
	light_angle = source_atom.light_wedge

	parse_light_color()

	effect_str      = list()
	affecting_turfs = list()

	update()

	L_PROF(source_atom, "source_new")

	return ..()

// Kill ourselves.
/datum/light_source/proc/destroy(var/no_update = FALSE)
	L_PROF(source_atom, "source_destroy")

	destroyed = TRUE
	if (!no_update)
		force_update()
	if (source_atom && source_atom.light_sources)
		source_atom.light_sources -= src

	if (top_atom && top_atom.light_sources)
		top_atom.light_sources    -= src

// Process the light RIGHT NOW.
#define DO_UPDATE 								\
	if (destroyed || check() || force_update) {	\
		remove_lum(TRUE);						\
		if (!destroyed) {						\
			apply_lum(TRUE);					\
		}										\
	}											\
	else if (vis_update) {						\
		smart_vis_update(TRUE);					\
	}											\
	vis_update   = FALSE;						\
	force_update = FALSE;						\
	needs_update = FALSE;

// Queue an update.
#define QUEUE_UPDATE                    \
	if (!needs_update)                  \
	{                                   \
		lighting_update_lights += src;  \
		needs_update            = TRUE; \
	}

// Picks either scheduled or instant updates based on current server load.
#define INTELLIGENT_UPDATE 							\
	if (world.tick_usage > TICK_LIMIT || !ticker || ticker.current_state <= GAME_STATE_SETTING_UP) {	\
		QUEUE_UPDATE;								\
	}												\
	else {											\
		DO_UPDATE;									\
	}

// This proc will cause the light source to update the top atom, and add itself to the update queue.
/datum/light_source/proc/update(var/atom/new_top_atom)
	// This top atom is different.
	if (new_top_atom && new_top_atom != top_atom)
		if(top_atom != source_atom) // Remove ourselves from the light sources of that top atom.
			top_atom.light_sources -= src

		top_atom = new_top_atom

		if (top_atom != source_atom)
			if(!top_atom.light_sources)
				top_atom.light_sources = list()

			top_atom.light_sources += src // Add ourselves to the light sources of our new top atom.

	L_PROF(source_atom, "source_update")

	INTELLIGENT_UPDATE

// Will force an update without checking if it's actually needed.
/datum/light_source/proc/force_update()
	L_PROF(source_atom, "source_forceupdate")
	force_update = 1

	INTELLIGENT_UPDATE

// Will cause the light source to recalculate turfs that were removed or added to visibility only.
/datum/light_source/proc/vis_update()
	L_PROF(source_atom, "source_visupdate")
	vis_update = 1

	INTELLIGENT_UPDATE

// Will check if we actually need to update, and update any variables that may need to be updated.
/datum/light_source/proc/check()
	if (!source_atom || !light_range || !light_power)
		destroy(no_update = TRUE)
		return 1

	if (!top_atom)
		top_atom = source_atom
		. = 1

	if (istype(top_atom, /turf))
		if (source_turf != top_atom)
			source_turf = top_atom
			. = 1
	else if (top_atom.loc != source_turf)
		source_turf = top_atom.loc
		. = 1

	if (source_atom.light_power != light_power)
		light_power = source_atom.light_power
		. = 1

	if (source_atom.light_range != light_range)
		light_range = source_atom.light_range
		. = 1

	if (light_range && light_power && !applied)
		. = 1

	if (source_atom.light_color != light_color)
		light_color = source_atom.light_color
		parse_light_color()
		. = 1

	if (top_atom.dir != old_direction && light_angle)
		. = 1

	if (source_atom.light_wedge != light_angle)
		light_angle = source_atom.light_wedge
		. = 1

// Decompile the hexadecimal colour into lumcounts of each perspective.
/datum/light_source/proc/parse_light_color()
	if (light_color)
		lum_r = GetRedPart   (light_color) / 255
		lum_g = GetGreenPart (light_color) / 255
		lum_b = GetBluePart  (light_color) / 255
	else
		lum_r = 1
		lum_g = 1
		lum_b = 1

	if (light_uv)
		lum_u = light_uv / 255
	else
		lum_u = 0

// Macro that applies light to a new corner.
// It is a macro in the interest of speed, yet not having to copy paste it.
// If you're wondering what's with the backslashes, the backslashes cause BYOND to not automatically end the line.
// As such this all gets counted as a single line.
// The braces and semicolons are there to be able to do this on a single line.
#define APPLY_CORNER_XY(C,now,Tx,Ty) \
	. = LUM_FALLOFF_XY(C.x, C.y, Tx, Ty); \
                                     \
	. *= light_power;                \
                                     \
	effect_str[C] = .;               \
                                     \
	C.update_lumcount                \
	(                                \
		. * applied_lum_r,           \
		. * applied_lum_g,           \
		. * applied_lum_b,           \
		. * applied_lum_u,           \
		now							 \
	);

#define APPLY_CORNER(C,now) APPLY_CORNER_XY(C,now,source_turf.x,source_turf.y)

// I don't need to explain what this does, do I?
#define REMOVE_CORNER(C,now)             \
	. = -effect_str[C];              \
	C.update_lumcount                \
	(                                \
		. * applied_lum_r,           \
		. * applied_lum_g,           \
		. * applied_lum_b,           \
		. * applied_lum_u,           \
		now                          \
	);

#define POLAR_TO_CART_X(R,T) ((R) * cos(T))
#define POLAR_TO_CART_Y(R,T) ((R) * sin(T))
#define PSEUDO_WEDGE(A_X,A_Y,B_X,B_Y) ((A_X)*(B_Y) - (A_Y)*(B_X))

/datum/light_source/proc/update_angle()
	var/turf/T = get_turf(top_atom)
	// Don't do anything if nothing is different, trig ain't free.
	if (T.x == cached_origin_x && T.y == cached_origin_y && old_direction == top_atom.dir)
		return

	var/do_offset = TRUE
	var/turf/front = get_step(T, top_atom.dir)
	if (front.has_opaque_atom)
		do_offset = FALSE

	cached_origin_x = T.x
	test_x_offset = cached_origin_x
	cached_origin_y = T.y
	test_y_offset = cached_origin_y
	old_direction = top_atom.dir

	var/angle = light_angle / 2
	switch (top_atom.dir)
		if (NORTH)
			limit_a_t = angle + 90
			limit_b_t = -(angle) + 90
			if (do_offset)
				test_y_offset += 1

		if (SOUTH)
			limit_a_t = (angle) - 90
			limit_b_t = -(angle) - 90
			if (do_offset)
				test_y_offset -= 1

		if (EAST)
			limit_a_t = angle
			limit_b_t = -(angle)
			if (do_offset)
				test_x_offset += 1

		if (WEST)
			limit_a_t = angle + 180
			limit_b_t = -(angle) - 180
			if (do_offset)
				test_x_offset -= 1

	// Convert our angle + range into a vector.
	limit_a_x = POLAR_TO_CART_X(light_range + 10, limit_a_t)
	limit_a_y = POLAR_TO_CART_Y(light_range + 10, limit_a_t)	// 10 is an arbitrary number, yes.
	limit_b_x = POLAR_TO_CART_X(light_range + 10, limit_b_t)
	limit_b_y = POLAR_TO_CART_Y(light_range + 10, limit_b_t)
	// This won't change unless the origin or dir changes, might as well do it here.
	targ_sign = PSEUDO_WEDGE(limit_a_x, limit_a_y, limit_b_x, limit_b_y) > 0

// I know this is 2D, calling it a cone anyways. Fuck the system.
// Returns true if the test point is NOT inside the cone.
// Make sure update_angle() is called first if the light's loc or dir have changed.
/datum/light_source/proc/check_light_cone(var/test_x, var/test_y)
	test_x -= test_x_offset
	test_y -= test_y_offset
	var/at = PSEUDO_WEDGE(limit_a_x, limit_a_y, test_x, test_y)
	var/tb = PSEUDO_WEDGE(test_x, test_y, limit_b_x, limit_b_y)

	// if the signs of both at and tb are NOT the same, the point is NOT within the cone.
	if ((at > 0) != targ_sign)
		return TRUE

	if ((tb > 0) != targ_sign)
		return TRUE

#undef POLAR_TO_CART_X
#undef POLAR_TO_CART_Y
#undef PSEUDO_WEDGE

// This is the define used to calculate falloff.
#define LUM_FALLOFF(C, T) (1 - CLAMP01(sqrt((C.x - T.x) ** 2 + (C.y - T.y) ** 2 + LIGHTING_HEIGHT) / max(1, light_range)))
#define LUM_FALLOFF_XY(Cx,Cy,Tx,Ty) (1 - CLAMP01(sqrt(((Cx) - (Tx)) ** 2 + ((Cy) - (Ty)) ** 2 + LIGHTING_HEIGHT) / max(1, light_range)))

/datum/light_source/proc/apply_lum(var/now = FALSE)
	var/static/update_gen = 1
	applied = 1

	var/Tx
	var/Ty
	var/Sx = source_turf.x
	var/Sy = source_turf.y

	// Keep track of the last applied lum values so that the lighting can be reversed
	applied_lum_r = lum_r
	applied_lum_g = lum_g
	applied_lum_b = lum_b
	applied_lum_u = lum_u

	if (light_angle)
		update_angle()

	FOR_DVIEW(var/turf/T, light_range, source_turf, INVISIBILITY_LIGHTING)
		Tx = T.x
		Ty = T.y
		if (light_angle && check_light_cone(Tx, Ty))
			continue

		if (!T.lighting_corners_initialised)
			T.generate_missing_corners()

		for (var/datum/lighting_corner/C in T.get_corners())
			if (C.update_gen == update_gen)
				continue

			C.update_gen = update_gen
			C.affecting += src

			if (!C.active)
				effect_str[C] = 0
				continue

			APPLY_CORNER_XY(C, now, Sx, Sy)

		if (!T.affecting_lights)
			T.affecting_lights = list()

		T.affecting_lights += src
		affecting_turfs    += T

	update_gen++

/datum/light_source/proc/remove_lum(var/now = FALSE)
	applied = FALSE

	for (var/turf/T in affecting_turfs)
		if (!T.affecting_lights)
			T.affecting_lights = list()
		else
			T.affecting_lights -= src

	affecting_turfs.Cut()

	for (var/datum/lighting_corner/C in effect_str)
		REMOVE_CORNER(C,now)

		C.affecting -= src

	effect_str.Cut()

/datum/light_source/proc/recalc_corner(var/datum/lighting_corner/C, var/now = FALSE)
	if (effect_str.Find(C)) // Already have one.
		REMOVE_CORNER(C,now)

	APPLY_CORNER(C,now)

/datum/light_source/proc/smart_vis_update(var/now = FALSE)
	L_PROF(source_atom, "source_smartvisupdate")
	var/list/datum/lighting_corner/corners = list()
	var/list/turf/turfs                    = list()
	FOR_DVIEW(var/turf/T, light_range, source_turf, 0)
		if (!T.lighting_corners_initialised)
			T.generate_missing_corners()
		if (light_angle && check_light_cone(T.x, T.y))
			continue

		corners |= T.get_corners()
		turfs   += T

	var/list/L = turfs - affecting_turfs // New turfs, add us to the affecting lights of them.
	affecting_turfs += L
	for (var/turf/T in L)
		if (!T.affecting_lights)
			T.affecting_lights = list(src)
		else
			T.affecting_lights += src

	L = affecting_turfs - turfs // Now-gone turfs, remove us from the affecting lights.
	affecting_turfs -= L
	for (var/turf/T in L)
		T.affecting_lights -= src

	for (var/datum/lighting_corner/C in corners - effect_str) // New corners
		C.affecting += src
		if (!C.active || check_light_cone(C.x, C.y))
			effect_str[C] = 0
			continue

		APPLY_CORNER(C,now)

	for (var/datum/lighting_corner/C in effect_str - corners) // Old, now gone, corners.
		REMOVE_CORNER(C,now)
		C.affecting -= src
		effect_str -= C

#undef QUEUE_UPDATE
#undef DO_UPDATE
#undef INTELLIGENT_UPDATE
#undef LUM_FALLOFF
#undef LUM_FALLOFF_XY
#undef REMOVE_CORNER
#undef APPLY_CORNER
#undef APPLY_CORNER_XY