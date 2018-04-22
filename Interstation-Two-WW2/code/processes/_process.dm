// Process

/process
	parent_type = /datum
	/**
	 * State vars
	 */
	// Main controller ref
	var/tmp/processScheduler/main

	// TRUE if process is not running or queued
	var/tmp/idle = TRUE

	// TRUE if process is queued
	var/tmp/queued = FALSE

	// TRUE if process is running
	var/tmp/running = FALSE

	// TRUE if process is blocked up
	var/tmp/hung = FALSE

	// TRUE if process was killed
	var/tmp/killed = FALSE

	// Status text var
	var/tmp/status

	// Previous status text var
	var/tmp/previousStatus

	// TRUE if process is disabled
	var/tmp/disabled = FALSE

	/**
	 * Config vars
	 */
	// Process name
	var/name

	// Process schedule interval
	// This controls how often the process would run under ideal conditions.
	// If the process scheduler sees that the process has finished, it will wait until
	// this amount of time has elapsed from the start of the previous run to start the
	// process running again.
	var/tmp/schedule_interval = PROCESS_DEFAULT_SCHEDULE_INTERVAL // run every 50 ticks

	// Process sleep interval
	// This controls how often the process will yield (call sleep(0)) while it is running.
	// Every concurrent process should sleep periodically while running in order to allow other
	// processes to execute concurrently.
	var/tmp/sleep_interval

	// hang_warning_time - this is the time (in TRUE/10 seconds) after which the server will begin to show "maybe hung" in the context window
	var/tmp/hang_warning_time = PROCESS_DEFAULT_HANG_WARNING_TIME

	// hang_alert_time - After this much time(in TRUE/10 seconds), the server will send an admin debug message saying the process may be hung
	var/tmp/hang_alert_time = PROCESS_DEFAULT_HANG_ALERT_TIME

	// hang_restart_time - After this much time(in TRUE/10 seconds), the server will automatically kill and restart the process.
	var/tmp/hang_restart_time = PROCESS_DEFAULT_HANG_RESTART_TIME

	// How many times in the current run has the process deferred work till the next tick?
	var/tmp/cpu_defer_count = 0

	// How many SCHECKs have been skipped (to limit btime calls)
	var/tmp/calls_since_last_scheck = 0

	/**
	 * recordkeeping vars
	 */

	// Records the time (1/10s timeoftick) at which the process last finished sleeping
	var/tmp/last_slept = 0

	// Records the time (1/10s timeoftick) at which the process last began running
	var/tmp/run_start = 0

	// Records the number of times this process has been killed and restarted
	var/tmp/times_killed

	// Tick count
	var/tmp/ticks = 0

	var/tmp/last_task = ""

	var/tmp/last_object

	// Counts the number of times an exception has occurred; gets reset after 10
	var/tmp/list/exceptions = list()

	// Number of deciseconds to delay before starting the process
	var/start_delay = 0

	// are we paused (admin-initiated only)
	var/paused = FALSE

	// are our non-vital processes paused (admin-initiated only)
	// currently only implemented for the obj process
	var/paused_nonvital = 0

	// when can we call process()
	var/list/fires_at_gamestates = list(GAME_STATE_PREGAME, GAME_STATE_SETTING_UP, GAME_STATE_PLAYING, GAME_STATE_FINISHED)

	// are we a subsystem that processes independently of other processes
	var/subsystem = FALSE

/process/New(var/processScheduler/scheduler)
	..()
	main = scheduler
	previousStatus = "idle"
	idle()
	name = "process"
	schedule_interval = 50
	sleep_interval = world.tick_lag / PROCESS_DEFAULT_SLEEP_INTERVAL
	last_slept = 0
	run_start = 0
	ticks = 0
	last_task = 0
	last_object = null

/process/proc/started()
	// Initialize run_start so we can detect hung processes.
	run_start = TimeOfGame

	// Initialize defer count
	cpu_defer_count = 0

	running()
	main.processStarted(src)

	onStart()

/process/proc/finished()
	ticks++
	idle()
	main.processFinished(src)

	onFinish()

/process/proc/fire()
	return

/process/proc/setup()
	return

/process/proc/process()
	started()
	if (!paused && !subsystem)
		fire()
	finished()

/process/proc/running()
	idle = FALSE
	queued = FALSE
	running = TRUE
	hung = FALSE
	setStatus(PROCESS_STATUS_RUNNING)

/process/proc/idle()
	queued = FALSE
	running = FALSE
	idle = TRUE
	hung = FALSE
	setStatus(PROCESS_STATUS_IDLE)

/process/proc/queued()
	idle = FALSE
	running = FALSE
	queued = TRUE
	hung = FALSE
	setStatus(PROCESS_STATUS_QUEUED)

/process/proc/hung()
	hung = TRUE
	setStatus(PROCESS_STATUS_HUNG)

/process/proc/handleHung()
	var/datum/lastObj = last_object
	var/lastObjType = "null"
	if(istype(lastObj))
		lastObjType = lastObj.type

	var/msg = "PROCESS SCHEDULER: [name] process hung at tick #[ticks]. Process was unresponsive for [(TimeOfGame - run_start) / 10] seconds and was restarted. Last task: [last_task]. Last Object Type: [lastObjType]"
	log_debug(msg)
	message_admins(msg)

	main.restartProcess(name)

/process/proc/kill()
	if (!killed)
		var/msg = "PROCESS SCHEDULER: [name] process was killed at tick #[ticks]."
		log_debug(msg)
		message_admins(msg)
		//finished()

		// Allow inheritors to clean up if needed
		onKill()

		// This should del
		del(src)

// Do not call this directly - use SHECK or SCHECK_EVERY
/process/proc/sleepCheck(var/tickId = 0)
	calls_since_last_scheck = 0
	if (killed)
		// The kill proc is the only place where killed is set.
		// The kill proc should have deleted this datum, and all sleeping procs that are
		// owned by it.
		CRASH("A killed process is still running somehow...")
	if (hung)
		// This will only really help if the doWork proc ends up in an infinite loop.
		handleHung()
		CRASH("Process [name] hung and was restarted.")

	if (main.getCurrentTickElapsedTime() > main.timeAllowance)
		sleep(world.tick_lag)
		cpu_defer_count++
		last_slept = 0
	else
		if (TimeOfTick > last_slept + sleep_interval)
			// If we haven't slept in sleep_interval deciseconds, sleep to allow other work to proceed.
			sleep(0)
			last_slept = TimeOfTick

/process/proc/update()
	// Clear delta
	if(previousStatus != status)
		setStatus(status)

	var/elapsedTime = getElapsedTime()

	if (hung)
		handleHung()
		return
	else if (elapsedTime > hang_restart_time)
		hung()
	else if (elapsedTime > hang_alert_time)
		setStatus(PROCESS_STATUS_PROBABLY_HUNG)
	else if (elapsedTime > hang_warning_time)
		setStatus(PROCESS_STATUS_MAYBE_HUNG)

/process/proc/getElapsedTime()
	return TimeOfGame - run_start

/process/proc/tickDetail()
	return

/process/proc/getContext()
	return "<tr><td>[name]</td><td>[main.averageRunTime(src)]</td><td>[main.last_run_time[src]]</td><td>[main.highest_run_time[src]]</td><td>[ticks]</td></tr>\n"

/process/proc/getContextData()
	return list(
	"name" = name,
	"averageRunTime" = main.averageRunTime(src),
	"lastRunTime" = main.last_run_time[src],
	"highestRunTime" = main.highest_run_time[src],
	"ticks" = ticks,
	"schedule" = schedule_interval,
	"status" = getStatusText(),
	"disabled" = disabled
	)

/process/proc/getStatus()
	return status

/process/proc/getStatusText(var/s = FALSE)
	if(!s)
		s = status
	switch(s)
		if(PROCESS_STATUS_IDLE)
			return "idle"
		if(PROCESS_STATUS_QUEUED)
			return "queued"
		if(PROCESS_STATUS_RUNNING)
			return "running"
		if(PROCESS_STATUS_MAYBE_HUNG)
			return "maybe hung"
		if(PROCESS_STATUS_PROBABLY_HUNG)
			return "probably hung"
		if(PROCESS_STATUS_HUNG)
			return "HUNG"
		else
			return "UNKNOWN"

/process/proc/getPreviousStatus()
	return previousStatus

/process/proc/getPreviousStatusText()
	return getStatusText(previousStatus)

/process/proc/setStatus(var/newStatus)
	previousStatus = status
	status = newStatus

/process/proc/setLastTask(var/task, var/object)
	last_task = task
	last_object = object

/process/proc/_copyStateFrom(var/process/target)
	main = target.main
	name = target.name
	schedule_interval = target.schedule_interval
	sleep_interval = target.sleep_interval
	last_slept = 0
	run_start = 0
	times_killed = target.times_killed
	ticks = target.ticks
	last_task = target.last_task
	last_object = target.last_object
	copyStateFrom(target)

/process/proc/copyStateFrom(var/process/target)
	return

/process/proc/onKill()
	return

/process/proc/onStart()
	return

/process/proc/onFinish()
	return

/process/proc/disable()
	disabled = TRUE

/process/proc/enable()
	disabled = FALSE

/process/proc/getAverageRunTime()
	return main.averageRunTime(src)

/process/proc/getLastRunTime()
	return main.getProcessLastRunTime(src)

/process/proc/getHighestRunTime()
	return main.getProcessHighestRunTime(src)

/process/proc/getTicks()
	return ticks

/process/proc/statProcess()
	var/averageRunTime = round(getAverageRunTime(), 0.1)/10
	var/lastRunTime = round(getLastRunTime(), 0.1)/10
	var/highestRunTime = round(getHighestRunTime(), 0.1)/10
	stat("[name]", "T#[getTicks()] | AR [averageRunTime] | LR [lastRunTime] | HR [highestRunTime] | D [cpu_defer_count]")

/process/proc/htmlProcess()
	var/averageRunTime = round(getAverageRunTime(), 0.1)/10
	var/lastRunTime = round(getLastRunTime(), 0.1)/10
	var/highestRunTime = round(getHighestRunTime(), 0.1)/10
	return "T#[getTicks()] | AR [averageRunTime] | LR [lastRunTime] | HR [highestRunTime] | D [cpu_defer_count]<br>"

/process/proc/catchException(var/exception/e, var/thrower)
	if(ispath(thrower) || istext(thrower))
		log_to_dd("PROCESS SCHEDULER: [src].catchException() was given a path or text type, [thrower], which was set to null.")
		log_debug("PROCESS SCHEDULER: [src].catchException() was given a path or text type, [thrower], which was set to null.")
		thrower = null // I think this prevents crashes - Kachnov
		return

	if(istype(e)) // Real runtimes go to the real error handler
		// There are two newlines here, because handling desc sucks
		e.desc = "  Caught by process: [name]\n\n" + e.desc
		if (thrower)
			world.Error(e, e_src = thrower)
		else
			world.Error(e)
		return

	var/etext = "[e]"
	var/eid = "[e]" // Exception ID, for tracking repeated exceptions
	var/ptext = "" // "processing..." text, for what was being processed (if known)
	if(istype(e))
		etext += " in [e.file], line [e.line]"
		eid = "[e.file]:[e.line]"
	if(eid in exceptions)
		if(exceptions[eid]++ >= 10)
			return
	else
		exceptions[eid] = TRUE
	if(istype(thrower, /datum))
		var/datum/D = thrower
		ptext = " processing [D.type]"
		if(istype(thrower, /atom))
			var/atom/A = thrower
			ptext += " ([A]) ([A.x],[A.y],[A.z])"
	log_to_dd("\[[time_stamp()]\] Process [name] caught exception[ptext]: [etext]")
	if(exceptions[eid] >= 10)
		log_to_dd("This exception will now be ignored for ten minutes.")
		spawn(6000)
			exceptions[eid] = 0

/process/proc/catchBadType(var/datum/caught)
	if(isnull(caught) || !istype(caught) || !isnull(caught.gcDestroyed))
		return // Only bother with types we can identify and that don't belong
	catchException("Type [caught.type] does not belong in process' queue")