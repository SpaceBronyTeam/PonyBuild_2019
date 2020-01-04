/obj/structure/closet/coffin
	name = "coffin"
	desc = "It's a burial receptacle for the dearly departed."
	icon_state = "coffin"
	icon_closed = "coffin"
	icon_opened = "coffin_open"

/obj/structure/closet/coffin/update_icon()
	if(!opened)
		icon_state = icon_closed
	else
		icon_state = icon_opened

/obj/structure/closet/coffin/refrigerator
	name = "old fridge"
	desc = "It's a old fridge for saving food."
	var/ghost_block = 0
	var/timer = 0
	icon = 'icons/obj/toy.dmi'
	icon_state = "ghost"
	icon_opened = "ghost_open"

	New()
		..()
		spawn(1)
			for()
				sleep(10)
				if(!opened)
					timer = 0
				else
					timer++
					if(timer>=580)
						ghost_block = 1
						sleep(230)
						ghost_block = 0
						timer = 0

	can_open()
		if(ghost_block)
			return 0
		..()