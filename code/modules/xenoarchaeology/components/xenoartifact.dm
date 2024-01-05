/*
	Items with this component will act like alien artifatcs
*/

//TODO: Replace all instances of this - Racc
/obj/item/xenoartifact
	icon_state = "skub"

/obj/item/xenoartifact/ComponentInitialize()
	. = ..()
	AddComponent(/datum/component/xenoartifact)

/datum/component/xenoartifact_pricing ///Pricing component for shipping solution. Consider swapping to cargo after change.
	///Buying and selling related, based on guess qaulity
	var/modifier = 0.5
	///default price gets generated if it isn't set by console. This only happens if the artifact spawns outside of that process
	var/price

/datum/component/xenoartifact_pricing/Initialize(...)
	RegisterSignal(parent, XENOA_CHANGE_PRICE, PROC_REF(update_price))
	..()

/datum/component/xenoartifact_pricing/Destroy(force, silent)
	UnregisterSignal(parent, XENOA_CHANGE_PRICE)
	..()

///Typically used to change internally
/datum/component/xenoartifact_pricing/proc/update_price(datum/source, f_price)
	price = f_price


/datum/component/xenoartifact
	///List of artifact-traits we have : list(PRIORITY = list(trait))
	var/list/artifact_traits = list()
	///Blacklist of components this artifact is currently incompatible with
	var/list/blacklisted_traits = list()

	///What strenght are our traits operating at?
	var/trait_strength = XENOA_TRAIT_STRENGTH_STRONG

	///Level of instability, associated with gaining malfunctions
	var/instability = 0

	///What type of artifact are we?
	var/datum/component/xenoartifact_material/artifact_type

	///Cooldown logic for uses
	var/use_cooldown = XENOA_GENERIC_COOLDOWN
	var/use_cooldown_timer
	///Extra cooldown from traits - update this with get_extra_cooldowns() when you add traits
	var/trait_cooldown = 0 SECONDS
	///Cooldown override. If this is true, we're on cooldown
	var/cooldown_override = FALSE

	///List of targets we can pass to our traits
	var/list/targets = list()

	///Description for the material, based on the traits - Update this with get_material_desc() when you add traits
	var/material_description = ""

/datum/component/xenoartifact/New(list/raw_args, type, list/traits)
	. = ..()
	generate_xenoa_statics()

	//Setup our typing
	artifact_type = type || pick_weight(GLOB.xenoartifact_material_weights)
	artifact_type = new artifact_type()

	//If we're force-generating traits
	if(traits)
		for(var/datum/xenoartifact_trait/T as() in traits)
			//List building
			if(!artifact_traits[T.priority])
				artifact_traits[T.priority] = list()
			//handle adding trait
			T = new T(src)
			artifact_traits[T.priority] += T
			blacklisted_traits += T.blacklist_traits
			blacklisted_traits += T
	//Otherwise, randomly generate our own traits
	else
		var/list/focus_traits
		//Generate activators
		focus_traits = GLOB.xenoa_activators & artifact_type.get_trait_list()
		build_traits(focus_traits, artifact_type.trait_activators)

		//Generate minors
		focus_traits = GLOB.xenoa_minors & artifact_type.get_trait_list()
		build_traits(focus_traits, artifact_type.trait_minors)

		//Generate majors
		focus_traits = GLOB.xenoa_majors & artifact_type.get_trait_list()
		build_traits(focus_traits, artifact_type.trait_majors)

		//Generate malfunctions
		focus_traits = GLOB.xenoa_malfunctions & artifact_type.get_trait_list()
		build_traits(focus_traits, artifact_type.trait_malfunctions)
	//Cooldown
	trait_cooldown = get_extra_cooldowns()
	//Description
	material_description = get_material_desc()
	//Setup description stuff
	RegisterSignal(parent, COMSIG_PARENT_EXAMINE, PROC_REF(on_examined))

///Used to trigger all our traits in order
/datum/component/xenoartifact/proc/trigger(force)
	//Timer logic
	if((use_cooldown_timer || cooldown_override) && !force)
		return
	else if(use_cooldown_timer)
		reset_timer(use_cooldown_timer)
	//Timer setup
	use_cooldown_timer = addtimer(CALLBACK(src, PROC_REF(reset_timer)), use_cooldown + trait_cooldown, TIMER_STOPPABLE)
	//Trait triggers
	for(var/i in GLOB.xenoartifact_trait_priorities)
		SEND_SIGNAL(src, XENOA_TRIGGER, i)
	//Malfunctions
	handle_malfunctions()
	//Cleanup targets
	for(var/atom/A in targets)
		unregister_target(A)

/datum/component/xenoartifact/proc/build_traits(list/trait_list, amount)
	if(!length(trait_list))
		CRASH("TODO: - Racc")
	var/list/options = trait_list
	options -= blacklisted_traits
	for(var/i in 1 to amount)
		//Pick a random trait
		var/datum/xenoartifact_trait/T = pick_weight(options)
		//List building
		if(!artifact_traits[initial(T.priority)])
			artifact_traits[initial(T.priority)] = list()
		//handle trait adding
		T = new T(src)
		artifact_traits[T.priority] += T
		blacklisted_traits += T.blacklist_traits
		blacklisted_traits += T
	
//Cooldown finish logic goes here
/datum/component/xenoartifact/proc/reset_timer()
	if(use_cooldown_timer)
		deltimer(use_cooldown_timer)
	use_cooldown_timer = null //Just incase

/datum/component/xenoartifact/proc/get_extra_cooldowns()
	var/time = 0 SECONDS
	for(var/i in artifact_traits)
		for(var/datum/xenoartifact_trait/T as() in artifact_traits[i])
			time += T.cooldown
	return time

/datum/component/xenoartifact/proc/handle_malfunctions()
	if(!prob(instability))
		return
	var/list/focus_traits
	focus_traits = GLOB.xenoa_malfunctions & artifact_type.get_trait_list()
	build_traits(focus_traits, artifact_type.trait_malfunctions)

/datum/component/xenoartifact/proc/register_target(atom/target, force)
	//Don't register new targets unless the cooldown is finished
	if(use_cooldown_timer && !force)
		return
	targets += target
	RegisterSignal(target, COMSIG_PARENT_QDELETING, PROC_REF(unregister_target), TRUE)

/datum/component/xenoartifact/proc/unregister_target(datum/source)
	SIGNAL_HANDLER

	targets -= source
	UnregisterSignal(source, COMSIG_PARENT_QDELETING)

/datum/component/xenoartifact/proc/on_examined(datum/source, mob/user, list/examine_text)
	SIGNAL_HANDLER

	var/mob/living/carbon/M = user
	if(iscarbon(user) && M.can_see_reagents() || isobserver(user))
		examine_text += "<span class='notice'>[parent] seems to be made from a [material_description]material.</span>"
	//Special case for observers that shows all the traits
	if(isobserver(user))
		for(var/i in artifact_traits)
			for(var/datum/xenoartifact_trait/T as() in artifact_traits[i])
				if(T.label_name)
					examine_text += "<span class='info'>- [T.label_name]</span>"
	return

/datum/component/xenoartifact/proc/get_material_desc()
	var/temp = ""
	for(var/i in artifact_traits)
		for(var/datum/xenoartifact_trait/T as() in artifact_traits[i])
			temp = "[temp][T.examine_desc ? "[T.examine_desc] " : ""]"
	return temp

///material datums
/datum/component/xenoartifact_material
	var/name = "debugium"
	///What color we associate with this material
	var/material_color = "#ff4800"

	///Trait info, how many of each trait are we allowed
	var/trait_activators = 1
	var/trait_minors = 3
	var/trait_majors = 1
	var/trait_malfunctions = 0

	///How much we increase artifact instability by for every use
	var/instability_step = 0

/datum/component/xenoartifact_material/proc/get_trait_list()
	return GLOB.xenoa_all_traits
