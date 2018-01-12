/mob/var/skincmds = list()
/obj/proc/SkinCmd(mob/user as mob, var/data as text)

/proc/SkinCmdRegister(var/mob/user, var/name as text, var/O as obj)
			user.skincmds[name] = O

/mob/verb/skincmd(data as text)
	set hidden = TRUE

	var/ref = copytext(data, TRUE, findtext(data, ";"))
	if (src.skincmds[ref] != null)
		var/obj/a = src.skincmds[ref]
		a.SkinCmd(src, copytext(data, findtext(data, ";") + TRUE))