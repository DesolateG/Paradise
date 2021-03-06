/obj/item/organ
	name = "organ"
	icon = 'icons/obj/surgery.dmi'
	var/dead_icon
	var/mob/living/carbon/human/owner = null
	var/status = 0
	var/vital //Lose a vital limb, die immediately.
	var/damage = 0 // amount of damage to the organ

	var/min_bruised_damage = 10
	var/min_broken_damage = 30
	var/max_damage
	var/organ_tag = "organ"

	var/parent_organ = "chest"
	var/robotic = 0 //For being a robot

	var/list/datum/autopsy_data/autopsy_data = list()
	var/list/trace_chemicals = list() // traces of chemicals in the organ,
									  // links chemical IDs to number of ticks for which they'll stay in the blood
	germ_level = 0
	var/datum/dna/dna
	var/datum/species/species = "Human"

	// Stuff for tracking if this is on a tile with an open freezer or not
	var/last_freezer_update_time = 0
	var/freezer_update_period = 100
	var/is_in_freezer = 0

	var/sterile = FALSE //can the organ be infected by germs?
	var/tough = FALSE //can organ be easily damaged?
	var/emp_proof = FALSE //is the organ immune to EMPs?


/obj/item/organ/Destroy()
	processing_objects.Remove(src)
	if(owner)
		remove(owner, 1)
	QDEL_LIST_ASSOC_VAL(autopsy_data)
	QDEL_NULL(dna)
	return ..()

/obj/item/organ/proc/update_health()
	return

/obj/item/organ/New(var/mob/living/carbon/holder)
	..(holder)
	if(!max_damage)
		max_damage = min_broken_damage * 2
	if(istype(holder))
		species = all_species["Human"]
		if(holder.dna)
			dna = holder.dna.Clone()
			species = all_species[dna.species]
		else
			log_runtime(EXCEPTION("[holder] spawned without a proper DNA."), holder)
		var/mob/living/carbon/human/H = holder
		if(istype(H))
			if(dna)
				if(!blood_DNA)
					blood_DNA = list()
				blood_DNA[dna.unique_enzymes] = dna.b_type
	else
		if(istext(species))
			species = all_species[species]

/obj/item/organ/proc/set_dna(var/datum/dna/new_dna)
	if(new_dna)
		dna = new_dna.Clone()
		if(blood_DNA)
			blood_DNA.Cut()
		else
			blood_DNA = list()
		blood_DNA[dna.unique_enzymes] = dna.b_type

/obj/item/organ/proc/necrotize(update_sprite=TRUE)
	if(status & ORGAN_ROBOT)
		return
	damage = max_damage
	status |= ORGAN_DEAD
	processing_objects -= src
	if(dead_icon)
		icon_state = dead_icon
	if(owner && vital)
		owner.death()

/obj/item/organ/process()

	//dead already, no need for more processing
	if(status & ORGAN_DEAD)
		return

	if(is_preserved())
		return

	//Process infections
	if((status & ORGAN_ROBOT) || sterile || (owner && (IS_PLANT in owner.species.species_traits)))
		germ_level = 0
		return

	if(!owner)
		// Maybe scale it down a bit, have it REALLY kick in once past the basic infection threshold
		// Another mercy for surgeons preparing transplant organs
		germ_level++
		if(germ_level >= INFECTION_LEVEL_ONE)
			germ_level += rand(2,6)
		if(germ_level >= INFECTION_LEVEL_TWO)
			germ_level += rand(2,6)
		if(germ_level >= INFECTION_LEVEL_THREE)
			necrotize()

	else if(owner.bodytemperature >= 170)	//cryo stops germs from moving and doing their bad stuffs
		//** Handle antibiotics and curing infections
		handle_antibiotics()
		handle_germ_effects()

/obj/item/organ/proc/is_preserved()
	if(istype(loc,/obj/item/device/mmi))
		germ_level = max(0, germ_level - 1) // So a brain can slowly recover from being left out of an MMI
		return 1
	if(is_found_within(/obj/structure/closet/crate/freezer))
		return 1
	if(is_found_within(/obj/machinery/clonepod))
		return 1
	if(isturf(loc))
		if(world.time - last_freezer_update_time > freezer_update_period)
			// I don't want to loop through everything in the tile constantly, especially since it'll be a pile of organs
			// if the virologist releases gibbingtons again or something
			// There's probably a much less silly way of doing this, but BYOND native algorithms are stupidly naive
			is_in_freezer = 0
			for(var/obj/structure/closet/crate/freezer/F in loc.contents)
				if(F.opened)
					is_in_freezer = 1 // on the same tile, close enough, should keep organs much fresher on avg
					break
			last_freezer_update_time = world.time
		return is_in_freezer // I'd like static varibles, please

	// You can do your cool location temperature organ preserving effects here!
	return 0

/obj/item/organ/examine(mob/user)
	..(user)
	if(status & ORGAN_DEAD)
		to_chat(user, "<span class='notice'>The decay has set in.</span>")

/obj/item/organ/proc/handle_germ_effects()
	//** Handle the effects of infections
	var/antibiotics = owner.reagents.get_reagent_amount("spaceacillin")

	if(germ_level > 0 && germ_level < INFECTION_LEVEL_ONE/2 && prob(30))
		germ_level--

	if(germ_level >= INFECTION_LEVEL_ONE/2)
		//aiming for germ level to go from ambient to INFECTION_LEVEL_TWO in an average of 15 minutes
		if(antibiotics < 5 && prob(round(germ_level/6)))
			germ_level++

	if(germ_level >= INFECTION_LEVEL_ONE)
		var/fever_temperature = (owner.species.heat_level_1 - owner.species.body_temperature - 5)* min(germ_level/INFECTION_LEVEL_TWO, 1) + owner.species.body_temperature
		owner.bodytemperature += between(0, (fever_temperature - T20C)/BODYTEMP_COLD_DIVISOR + 1, fever_temperature - owner.bodytemperature)

	if(germ_level >= INFECTION_LEVEL_TWO)
		var/obj/item/organ/external/parent = owner.get_organ(parent_organ)
		//spread germs
		if(antibiotics < 5 && parent.germ_level < germ_level && ( parent.germ_level < INFECTION_LEVEL_ONE*2 || prob(30) ))
			parent.germ_level++

/obj/item/organ/internal/handle_germ_effects()
	..()
	if(germ_level >= INFECTION_LEVEL_TWO)
		if(prob(3))	//about once every 30 seconds
			receive_damage(1,silent=prob(30))

/obj/item/organ/proc/rejuvenate()
	damage = 0
	germ_level = 0
	if(status & ORGAN_ROBOT)	//Robotic organs stay robotic.
		status = ORGAN_ROBOT
	else if(status & ORGAN_ASSISTED) //Assisted organs stay assisted.
		status = ORGAN_ASSISTED
	else
		status = 0
	if(!owner)
		processing_objects |= src

/obj/item/organ/proc/is_damaged()
	return damage > 0

/obj/item/organ/proc/is_bruised()
	return damage >= min_bruised_damage

/obj/item/organ/proc/is_broken()
	return (damage >= min_broken_damage || ((status & ORGAN_BROKEN) && !(status & ORGAN_SPLINTED)))

//Germs
/obj/item/organ/proc/handle_antibiotics()
	var/antibiotics = owner.reagents.get_reagent_amount("spaceacillin")

	if(!germ_level || antibiotics <= 0.4)
		return

	if(germ_level < INFECTION_LEVEL_ONE)
		germ_level = 0	//cure instantly
	else if(germ_level < INFECTION_LEVEL_TWO)
		germ_level -= 24	//at germ_level == 500, this should cure the infection in 15 seconds
	else
		germ_level -= 8	// at germ_level == 1000, this will cure the infection in 1 minute, 15 seconds
						// Let's not drag this on, medbay has only so much antibiotics

//Adds autopsy data for used_weapon.
/obj/item/organ/proc/add_autopsy_data(var/used_weapon, var/damage)
	var/datum/autopsy_data/W = autopsy_data[used_weapon]
	if(!W)
		W = new()
		W.weapon = used_weapon
		autopsy_data[used_weapon] = W

	W.hits += 1
	W.damage += damage
	W.time_inflicted = world.time

//Note: external organs have their own version of this proc
/obj/item/organ/proc/receive_damage(amount, silent = 0)
	if(tough)
		return
	if(status & ORGAN_ROBOT)
		damage = between(0, damage + (amount * 0.8), max_damage)
	else
		damage = between(0, damage + amount, max_damage)

		//only show this if the organ is not robotic
		if(owner && parent_organ && amount > 0)
			var/obj/item/organ/external/parent = owner.get_organ(parent_organ)
			if(parent && !silent)
				owner.custom_pain("Something inside your [parent.name] hurts a lot.", 1)

		//check if we've hit max_damage
	if(damage >= max_damage)
		necrotize()

/obj/item/organ/proc/robotize() //Being used to make robutt hearts, etc
	robotic = 2
	status &= ~ORGAN_BROKEN
	status &= ~ORGAN_SPLINTED
	status |= ORGAN_ROBOT

/obj/item/organ/proc/mechassist() //Used to add things like pacemakers, etc
	robotize(1) //Skip the icon/name setting that occurs in robotize to avoid having to reset the icon file.
	status &= ~ORGAN_ROBOT
	status |= ORGAN_ASSISTED
	robotic = 1
	min_bruised_damage = 15
	min_broken_damage = 35

/obj/item/organ/external/emp_act(severity)
	if(!(status & ORGAN_ROBOT) || emp_proof)
		return
	if(tough)
		switch(severity)
			if(1)
				receive_damage(0, 5.5)
				if(owner)
					owner.Stun(10)
			if(2)
				receive_damage(0, 2.8)
				if(owner)
					owner.Stun(5)
	else
		switch(severity)
			if(1)
				receive_damage(0, 20)
			if(2)
				receive_damage(0, 7)

/obj/item/organ/internal/emp_act(severity)
	if(!robotic || emp_proof)
		return
	if(robotic == 2)
		switch(severity)
			if(1.0)
				receive_damage(20, 1)
			if(2.0)
				receive_damage(7, 1)
	else if(robotic == 1)
		receive_damage(11, 1)

/obj/item/organ/internal/heart/emp_act(intensity)
	if(emp_proof)
		return
	if(owner && robotic == 2)
		Stop() // In the name of looooove~!
		owner.visible_message("<span class='danger'>[owner] clutches their chest and gasps!</span>","<span class='userdanger'>You clutch your chest in pain!</span>")
	else if(owner && robotic == 1)
		receive_damage(11,1)

/obj/item/organ/proc/remove(var/mob/living/user,special = 0)
	if(!istype(owner))
		return

	owner.internal_organs -= src

	var/obj/item/organ/external/affected = owner.get_organ(parent_organ)
	if(affected) affected.internal_organs -= src

	loc = get_turf(owner)
	processing_objects |= src

	if(owner && vital && is_primary_organ()) // I'd do another check for species or whatever so that you couldn't "kill" an IPC by removing a human head from them, but it doesn't matter since they'll come right back from the dead
		if(user)
			user.create_attack_log("<font color='red'> removed a vital organ ([src]) from [key_name(owner)] (INTENT: [uppertext(user.a_intent)])</font>")
			owner.create_attack_log("<font color='orange'> had a vital organ ([src]) removed by [key_name(user)] (INTENT: [uppertext(user.a_intent)])</font>")
			msg_admin_attack("[key_name_admin(user)] removed a vital organ ([src]) from [key_name_admin(owner)]")
		owner.death()
	owner = null
	return src

/obj/item/organ/proc/replaced(var/mob/living/carbon/human/target)
	return // Nothing uses this, it is always overridden

// A version of `replaced` that "flattens" the process of insertion, making organs "Plug'n'play"
// (Particularly the heart, which stops beating when removed)
/obj/item/organ/proc/safe_replace(var/mob/living/carbon/human/target)
	replaced(target)

/obj/item/organ/proc/surgeryize()
	return

/*
Returns 1 if this is the organ that is handling all the functionalities of that particular organ slot
Returns 0 if it isn't
I use this so that this can be made better once the organ overhaul rolls out -- Crazylemon
*/
/obj/item/organ/proc/is_primary_organ(var/mob/living/carbon/human/O = null)
	if(isnull(O))
		O = owner
	if(!istype(owner)) // You're not the primary organ of ANYTHING, bucko
		return 0
	return src == O.get_int_organ(organ_tag)

/obj/item/organ/proc/is_robotic(var/purist = FALSE)
	if(purist && (robotic > 1 || status & (ORGAN_ROBOT))) //Only the robotiest.
		return TRUE
	if(robotic || status & (ORGAN_ROBOT|ORGAN_ASSISTED)) //Any tech will do.
		return TRUE

	return FALSE

/obj/item/organ/serialize()
	var/data = ..()
	if(status != 0)
		data["status"] = status
	if(robotic > 0)
		data["robotic"] = robotic

	// Save the DNA datum if: The owner doesn't exist, or the dna doesn't match
	// the owner
	if(!(owner && dna.unique_enzymes == owner.dna.unique_enzymes))
		data["dna"] = dna.serialize()
	return data

/obj/item/organ/deserialize(var/data)
	switch(data["robotic"])
		if(1)
			mechassist()
		if(2)
			robotize()
		else
			// Nothing
	if(isnum(data["status"]))
		status = data["status"]
	if(islist(data["dna"]))
		// The only thing the official proc does is
	 	//instantiate the list and call this proc
		dna.deserialize(data["dna"])
		..()
