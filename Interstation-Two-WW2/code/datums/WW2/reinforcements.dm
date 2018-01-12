var/datum/reinforcements/reinforcements_master


/proc/len(var/list/l)
	return l.len

/datum/reinforcements
	var/soviet_countdown = 50
	var/german_countdown = 50

	var/tick_len = TRUE // a decisecond

	// for now
	var/soviet_countdown_failure_reset = 50
	var/german_countdown_failure_reset = 50

	var/soviet_countdown_success_reset = 300
	var/german_countdown_success_reset = 300

	var/german_reinforcements_at_once = 9
	var/soviet_reinforcements_at_once = 12

	var/max_german_reinforcements = 100
	var/max_soviet_reinforcements = 100

	var/reinforcement_add_limit_german = 7
	var/reinforcement_add_limit_soviet = 7

	var/reinforcement_spawn_req = 3

	var/reinforcement_difference_cutoff = 12 // once one side has this many more reinforcements than the other, lock it until that's untrue

	var/reinforcements_granted[2] // keep track of how many troops we've given to germans, how many to soviets, for autobalance

	var/locked[2] // lock german or soviet based on reinforcements_granted[]

	var/reinforcement_pool[2] // how many people are trying to join for each side

	var/allow_quickspawn[2]

	var/showed_permalock_message[2]

/datum/reinforcements/New()
	..()

	reinforcement_add_limit_german = german_reinforcements_at_once
	reinforcement_add_limit_soviet = soviet_reinforcements_at_once

	if (config && config.debug)
		soviet_countdown = 10
		german_countdown = 10
		soviet_countdown_failure_reset = 10
		german_countdown_failure_reset = 10

	reinforcements_granted[SOVIET] = FALSE
	reinforcements_granted[GERMAN] = FALSE

	locked[SOVIET] = FALSE
	locked[GERMAN] = FALSE

	reinforcement_pool[SOVIET] = list()
	reinforcement_pool[GERMAN] = list()

	allow_quickspawn[SOVIET] = FALSE
	allow_quickspawn[GERMAN] = FALSE

	showed_permalock_message[GERMAN] = FALSE
	showed_permalock_message[SOVIET] = FALSE

	tick()


/datum/reinforcements/proc/is_ready()
	return game_started // no reinforcements until the train is sent

/datum/reinforcements/proc/tick()

	if (clients.len <= 20 && reinforcement_spawn_req != TRUE)

		reinforcement_spawn_req = TRUE
		world << "<span class = 'danger'>Reinforcements require <b>one</b> person to fill a queue.</span>"

		// half everything
		max_german_reinforcements = config.max_german_reinforcements/2
		max_soviet_reinforcements = config.max_soviet_reinforcements/2
		german_reinforcements_at_once = round(german_reinforcements_at_once/2)
		soviet_reinforcements_at_once = round(soviet_reinforcements_at_once/2)
		reinforcement_add_limit_german = round(reinforcement_add_limit_german/2)
		reinforcement_add_limit_soviet = round(reinforcement_add_limit_soviet/2)
		// but make this TRUE/3rd for b a l a n c e
		reinforcement_difference_cutoff = round(reinforcement_difference_cutoff/3)

	else if (clients.len > 20 && reinforcement_spawn_req == TRUE)
		reinforcement_spawn_req = initial(reinforcement_spawn_req)
		world << "<span class = 'danger'>Reinforcements require <b>three</b> people to fill a queue.</span>"
		max_german_reinforcements = config.max_german_reinforcements
		max_soviet_reinforcements = config.max_soviet_reinforcements
	else
		max_german_reinforcements = config.max_german_reinforcements
		max_soviet_reinforcements = config.max_soviet_reinforcements

	spawn while (1)

		if (reinforcement_pool[SOVIET] && reinforcement_pool[GERMAN])
			for (var/mob/new_player/np in reinforcement_pool[SOVIET])
				if (!np || !np.client)
					reinforcement_pool[SOVIET] -= np
			for (var/mob/new_player/np in reinforcement_pool[GERMAN])
				if (!np || !np.client)
					reinforcement_pool[GERMAN] -= np

		soviet_countdown = soviet_countdown - tick_len
		if (soviet_countdown < TRUE)
			if (!reset_soviet_timer())
				soviet_countdown = soviet_countdown_failure_reset
			else
				soviet_countdown = soviet_countdown_success_reset
				allow_quickspawn[SOVIET] = FALSE

		german_countdown = german_countdown - tick_len
		if (german_countdown < TRUE)
			if (!reset_german_timer())
				german_countdown = german_countdown_failure_reset
			else
				german_countdown = german_countdown_success_reset
				allow_quickspawn[GERMAN] = FALSE

		sleep(10)

/datum/reinforcements/proc/add(var/mob/new_player/np, side)

	var/nope[2]

	switch (side)
		if (SOVIET)
			if (len(reinforcement_pool[SOVIET]) >= reinforcement_add_limit_soviet)
				nope[SOVIET] = TRUE
			else
				nope[SOVIET] = FALSE
		if (GERMAN)
			if (len(reinforcement_pool[GERMAN]) >= reinforcement_add_limit_german)
				nope[GERMAN] = TRUE
			else
				nope[GERMAN] = FALSE

	if (locked[side])
		np << "<span class = 'danger'>This side is locked.</span>"
		return

	if (nope[side])
		np << "<span class = 'danger'>Sorry, too many people are attempting to join this side already.</span>"
		return

	//remove them from all pools, just in case
	var/list/r = reinforcement_pool[SOVIET]
	var/list/g = reinforcement_pool[GERMAN]

	if (r.Find(np))
		r -= np
	if (g.Find(np))
		g -= np

	var/sname[0]

	sname[SOVIET] = "SOVIET"
	sname[GERMAN] = "German"

	np << "<span class = 'danger'>You have joined a queue for [sname[side]] reinforcements, please wait until the timer reaches FALSE to spawn.</span>"
	var/list/l = reinforcement_pool[side]
	l += np

/datum/reinforcements/proc/remove(var/mob/new_player/np, side)
	var/list/l = reinforcement_pool[side]
	if (l.Find(np))
		l -= np

/datum/reinforcements/proc/has(var/mob/new_player/np, side_or_null)

	if (side_or_null)
		var/side = side_or_null
		var/list/l = reinforcement_pool[side]
		if (l.Find(np))
			return TRUE
	else
		var/list/r = reinforcement_pool[SOVIET]
		var/list/g = reinforcement_pool[GERMAN]

		if (r.Find(np) || g.Find(np))
			return TRUE

	return FALSE

/datum/reinforcements/proc/reset_soviet_timer()

	var/ret = FALSE
	var/list/l = reinforcement_pool[SOVIET]
	if (l.len < reinforcement_spawn_req && !allow_quickspawn[SOVIET])
		for (var/mob/new_player/np in l)
			np << "<span class='danger'>Failed to spawn a new Soviet squadron. [reinforcement_spawn_req - l.len] more draftees needed."
		return ret
	else if (has_occupied_base(SOVIET))
		for (var/mob/new_player/np in l)
			np << "<span class='danger'>The Germans are currently occupying the bunker! Reinforcements can't be sent."
		return ret
	for (var/mob/new_player/np in l)
		if (np)
			np.LateSpawnForced("Sovietsky Soldat", TRUE, TRUE)
			reinforcements_granted[SOVIET] = reinforcements_granted[SOVIET]+1
			ret = TRUE
	reinforcement_pool[SOVIET] = list()
	lock_check()
	var/obj/item/device/radio/R = main_radios[SOVIET]
	if (R && R.loc)
		spawn (10)
			R.announce("A new squadron has been deployed.", "Reinforcements Announcement System")
	world << "<font size=3>A new <b>Soviet</b> squadron has been deployed.</font>"
	return ret

/datum/reinforcements/proc/reset_german_timer()
	var/ret = FALSE
	var/list/l = reinforcement_pool[GERMAN]
	if (l.len < reinforcement_spawn_req && !allow_quickspawn[GERMAN])
		for (var/mob/new_player/np in l)
			np << "<span class='danger'>Failed to spawn a new German squadron. [reinforcement_spawn_req - l.len] more draftees needed."
		return ret
	else if (has_occupied_base(GERMAN))
		for (var/mob/new_player/np in l)
			np << "<span class='danger'>The Soviets are currently occupying your base! Reinforcements can't be sent."
		return ret
	for (var/mob/new_player/np in l)
		if (np) // maybe helps with logged out nps
			np.LateSpawnForced("Soldat", TRUE, TRUE)
			reinforcements_granted[GERMAN] = reinforcements_granted[GERMAN]+1
			ret = TRUE
	reinforcement_pool[GERMAN] = list()
	lock_check()
	var/obj/item/device/radio/R = main_radios[GERMAN]
	if (R && R.loc)
		spawn (10)
			R.announce("A new squadron has been deployed.", "Reinforcements Announcement System")
	world << "<font size=3>A new <b>German</b> squadron has been deployed.</font>"
	return ret

/datum/reinforcements/proc/r_german()
	var/list/l = reinforcement_pool[GERMAN]
	return l.len

/datum/reinforcements/proc/r_soviet()
	var/list/l = reinforcement_pool[SOVIET]
	return l.len

/datum/reinforcements/proc/lock_check()

	var/r = reinforcements_granted[SOVIET]
	var/g = reinforcements_granted[GERMAN]

	if (abs(r-g) >= reinforcement_difference_cutoff)

		if (max(r,g) == r)
			locked[SOVIET] = TRUE
		else
			locked[GERMAN] = TRUE

	else
		locked[SOVIET] = FALSE
		locked[GERMAN] = FALSE

	if (is_permalocked(SOVIET))

		if (!showed_permalock_message[SOVIET])
			world << "<font size = 3>The Soviet Army is all out of reinforcements.</font>"
			showed_permalock_message[SOVIET] = TRUE

		locked[SOVIET] = TRUE
		locked[GERMAN] = TRUE // since soviets get more reinforcements,
		 // if they are locked german must also be

	if (is_permalocked(GERMAN))

		if (!showed_permalock_message[GERMAN])
			world << "<font size = 3>The German Army is all out of reinforcements.</font>"
			showed_permalock_message[GERMAN] = TRUE

		locked[GERMAN] = TRUE

		if (!is_permalocked(SOVIET))
			locked[SOVIET] = FALSE // if germans are permalocked but not soviets, soviets must be unlocked

/datum/reinforcements/proc/is_permalocked(side)
	switch (side)
		if (GERMAN)
			if (reinforcements_granted[GERMAN] > max_german_reinforcements)
				return TRUE
		if (SOVIET)
			if (reinforcements_granted[SOVIET] > max_soviet_reinforcements)
				return TRUE
	return FALSE

/datum/reinforcements/proc/get_status_addendums()

	var/list/l = list()
	l += "GERMAN REINFORCEMENTS:"
	l += "Deployed: [reinforcements_granted[GERMAN]]"
	l += "Deploying: [r_german()]/[reinforcement_add_limit_german] in [german_countdown] seconds"
	l += "Locked: [locked[GERMAN] ? "Yes" : "No"]"
	l += "SOVIET REINFORCEMENTS:"
	l += "Deployed: [reinforcements_granted[SOVIET]]"
	l += "Deploying: [r_soviet()]/[reinforcement_add_limit_soviet] in [soviet_countdown] seconds"
	l += "Locked: [locked[SOVIET] ? "Yes" : "No"]"

	return l

