// These may have some say.dm bugs regarding understanding common,
// might be worth adapting the bugs into a feature and using these
// subtypes as a basis for non-common-speaking alien foreigners. ~ Z

/mob/living/carbon/pony/dummy
	real_name = "Test Dummy"
	status_flags = GODMODE|CANPUSH

/mob/living/carbon/pony/alicorn/New(var/new_loc)
	..(new_loc, "Alicorn")

/mob/living/carbon/pony/pegasus/New(var/new_loc)
	..(new_loc, "Pegasus")

/mob/living/carbon/pony/unicorn/New(var/new_loc)
	..(new_loc, "Unicorn")
/*
/mob/living/carbon/pony/vox/New(var/new_loc)
	h_style = "Short Vox Quills"
	..(new_loc, "Vox")*/

/mob/living/carbon/pony/diona/New(var/new_loc)
	..(new_loc, "Diona")

/mob/living/carbon/pony/machine/New(var/new_loc)
	h_style = "blue IPC screen"
	..(new_loc, "Machine")