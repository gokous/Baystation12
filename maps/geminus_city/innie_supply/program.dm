/datum/computer_file/program/innie_supply
	filename = "base_supply"
	filedesc = "Rabbit Hole Base Supply Management"
	program_icon_state = "supply"
	nanomodule_path = /datum/nano_module/program/innie_supply
	extended_desc = "A management tool that allows for ordering of various supplies through the base's cargo system. Some features may require additional access."
	size = 21
	available_on_ntnet = 1
	requires_ntnet = 1

/datum/nano_module/program/innie_supply
	name = "Rabbit Hole Base Supply Management program"
	var/screen = 1		// 0: Ordering menu, 1: Statistics 2: Shuttle control, 3: Orders menu
	var/selected_category
	var/list/category_names
	var/list/category_contents
	var/emagged = FALSE	// TODO: Implement synchronisation with modular computer framework.

/datum/nano_module/program/innie_supply/ui_interact(mob/user, ui_key = "main", datum/nanoui/ui = null, force_open = 1, state = GLOB.default_state)
	var/list/data = host.initial_data()
	var/is_admin = check_access(user, access_innie_boss)
	if(!category_names || !category_contents)
		generate_categories()

	data["is_admin"] = is_admin
	data["screen"] = screen
	data["credits"] = "[GLOB.innie_factions_controller.innie_credits]"
	switch(screen)
		if(1)// Main ordering menu
			data["categories"] = category_names
			if(selected_category)
				data["category"] = selected_category
				data["possible_purchases"] = category_contents[selected_category]

		if(2)// Statistics screen with credit overview
			data["total_credits"] = GLOB.innie_factions_controller.export_credits
			data["exports"] = GLOB.innie_factions_controller.exports_formatted
			data["can_print"] = can_print()

		if(3)// Shuttle monitoring and control
			var/datum/shuttle/autodock/ferry/geminus_innie/shuttle = GLOB.innie_factions_controller.geminus_supply_shuttle
			if(istype(shuttle))
				data["shuttle_location"] = shuttle.at_station() ? "Rabbit Hole Base Cargo Bay" : "Black market station"
			else
				data["shuttle_location"] = "No Connection"
			data["shuttle_status"] = get_shuttle_status()
			data["shuttle_can_control"] = shuttle.can_launch()


		if(4)// Order processing
			var/list/cart[0]
			var/list/requests[0]
			for(var/datum/supply_order/SO in GLOB.innie_factions_controller.shoppinglist)
				cart.Add(list(list(
					"id" = SO.ordernum,
					"object" = SO.object.name,
					"orderer" = SO.orderedby,
					"cost" = SO.object.cost,
					"reason" = SO.reason
				)))
			for(var/datum/supply_order/SO in GLOB.innie_factions_controller.requestlist)
				requests.Add(list(list(
					"id" = SO.ordernum,
					"object" = SO.object.name,
					"orderer" = SO.orderedby,
					"cost" = SO.object.cost,
					"reason" = SO.reason
					)))
			data["cart"] = cart
			data["requests"] = requests

	ui = GLOB.nanomanager.try_update_ui(user, src, ui_key, ui, data, force_open)
	if (!ui)
		ui = new(user, src, ui_key, "supply_innie.tmpl", name, 1050, 800, state = state)
		ui.set_auto_update(1)
		ui.set_initial_data(data)
		ui.open()

/datum/nano_module/program/innie_supply/Topic(href, href_list)
	var/mob/user = usr
	if(..())
		return 1

	if(href_list["select_category"])
		selected_category = href_list["select_category"]
		return 1

	if(href_list["set_screen"])
		screen = text2num(href_list["set_screen"])
		return 1

	if(href_list["order"])
		var/decl/hierarchy/supply_pack/P = locate(href_list["order"]) in supply_controller.master_supply_list
		if(!istype(P) || P.is_category())
			return 1

		if(P.hidden && !emagged)
			return 1

		var/reason = sanitize(input(user,"Reason:","Why do you require this item?","") as null|text,,0)
		if(!reason)
			return 1

		var/idname = "*None Provided*"
		var/idrank = "*None Provided*"
		var/mob/living/carbon/human/H = user
		idname = H.get_authentification_name()
		idrank = H.get_assignment()

		supply_controller.ordernum++

		var/datum/supply_order/O = new /datum/supply_order()
		O.ordernum = supply_controller.ordernum
		O.object = P
		O.orderedby = idname
		O.reason = reason
		O.orderedrank = idrank
		O.comment = "#[O.ordernum]"
		GLOB.innie_factions_controller.requestlist += O

		if(can_print() && alert(user, "Would you like to print a confirmation receipt?", "Print receipt?", "Yes", "No") == "Yes")
			print_order(O, user)
		return 1

	if(href_list["print_summary"])
		if(!can_print())
			return
		print_summary(user)

	if(href_list["launch_shuttle"])
		var/datum/shuttle/autodock/ferry/geminus_innie/shuttle = GLOB.innie_factions_controller.geminus_supply_shuttle
		if(!shuttle)
			to_chat(user, "<span class='warning'>Error connecting to the shuttle.</span>")
			return
		if(shuttle.at_station())
			if (shuttle.forbidden_atoms_check())
				to_chat(usr, "<span class='warning'>For safety reasons the automated supply shuttle cannot transport live organisms, classified nuclear weaponry or homing beacons.</span>")
			else
				shuttle.launch(user)

		else
			shuttle.launch(user)
			var/datum/radio_frequency/frequency = radio_controller.return_frequency(1435)
			if(!frequency)
				return

			var/datum/signal/status_signal = new
			status_signal.source = src
			status_signal.transmission_method = 1
			status_signal.data["command"] = "supply"
			frequency.post_signal(src, status_signal)

			GLOB.innie_factions_controller.shuttle_buy()

		return 1

	if(href_list["approve_order"])
		var/id = text2num(href_list["approve_order"])
		for(var/datum/supply_order/SO in GLOB.innie_factions_controller.requestlist)
			if(SO.ordernum != id)
				continue
			if(SO.object.cost > GLOB.innie_factions_controller.innie_credits)
				to_chat(usr, "<span class='warning'>Not enough credits to purchase \the [SO.object.name]!</span>")
				return 1
			GLOB.innie_factions_controller.requestlist -= SO
			GLOB.innie_factions_controller.shoppinglist += SO
			GLOB.innie_factions_controller.innie_credits -= SO.object.cost
			break
		return 1

	if(href_list["deny_order"])
		var/id = text2num(href_list["deny_order"])
		for(var/datum/supply_order/SO in GLOB.innie_factions_controller.requestlist)
			if(SO.ordernum == id)
				GLOB.innie_factions_controller.requestlist -= SO
				break
		return 1

	if(href_list["withdraw_credits"])
		if(program && program.computer)
			var/amount = input("How much do you want to withdraw?","Make withdrawal",0) as num
			if(amount > 0)
				amount = min(amount, GLOB.innie_factions_controller.innie_credits)
				GLOB.innie_factions_controller.innie_credits -= amount
				spawn_money(amount, program.computer.loc, user)
				playsound(program.computer, 'sound/machines/chime.ogg', 50, 1)
				program.computer.visible_message("\icon[program.computer] [user] withdraws a [amount >= 10000 ? "thick " : ""]wad of cash from [program.computer].")
		else
			to_chat(user,"<span class='warning'>You cannot do that right now.</span>")

	if(href_list["deposit_credits"])
		if(program && program.computer)
			var/obj/item/weapon/spacecash/S = user.get_active_hand()
			if(istype(S))
				user.drop_item(S)
				S.loc = program.computer
				GLOB.innie_factions_controller.innie_credits += S.worth
				program.computer.visible_message("\icon[program.computer] [user] deposits a [S.worth >= 10000 ? "thick " : ""]wad of cash into [program.computer].")
				qdel(S)
		else
			to_chat(user,"<span class='warning'>You cannot do that right now.</span>")

	if(href_list["cancel_order"])
		var/id = text2num(href_list["cancel_order"])
		for(var/datum/supply_order/SO in GLOB.innie_factions_controller.shoppinglist)
			if(SO.ordernum == id)
				GLOB.innie_factions_controller.shoppinglist -= SO
				GLOB.innie_factions_controller.innie_credits += SO.object.cost
				break
		return 1

/datum/nano_module/program/innie_supply/proc/generate_categories()
	category_names = list()
	category_contents = list()
	for(var/decl/hierarchy/supply_pack/sp in cargo_supply_pack_root.children)
		if(sp.is_category())
			category_names.Add(sp.name)
			var/list/category[0]
			for(var/decl/hierarchy/supply_pack/spc in sp.children)
				if((spc.hidden || spc.contraband) && !emagged)
					continue
				category.Add(list(list(
					"name" = spc.name,
					"cost" = spc.cost,
					"ref" = "\ref[spc]"
				)))
			category_contents[sp.name] = category

/datum/nano_module/program/innie_supply/proc/get_shuttle_status()
	var/datum/shuttle/autodock/ferry/geminus_innie/shuttle = GLOB.innie_factions_controller.geminus_supply_shuttle
	if(!istype(shuttle))
		return "No Connection"

	if(shuttle.has_arrive_time())
		return "In transit ([shuttle.eta_seconds()] s)"

	if (shuttle.can_launch())
		return "Docked"
	return "Docking/Undocking"


/datum/nano_module/program/innie_supply/proc/can_print()
	var/obj/item/modular_computer/MC = nano_host()
	if(!istype(MC) || !istype(MC.nano_printer))
		return 0
	return 1

/datum/nano_module/program/innie_supply/proc/print_order(var/datum/supply_order/O, var/mob/user)
	if(!O)
		return

	var/t = ""
	t += "<h3>Rabbit Hole Base Supply Requisition Receipt</h3><hr>"
	t += "INDEX: #[O.ordernum]<br>"
	t += "REQUESTED BY: [O.orderedby]<br>"
	t += "RANK: [O.orderedrank]<br>"
	t += "REASON: [O.reason]<br>"
	t += "SUPPLY CRATE TYPE: [O.object.name]<br>"
	t += "ACCESS RESTRICTION: [get_access_desc(O.object.access)]<br>"
	t += "CONTENTS:<br>"
	t += O.object.manifest
	t += "<hr>"
	print_text(t, user)

/datum/nano_module/program/innie_supply/proc/print_summary(var/mob/user)
	var/t = ""
	t += "<center><BR><b><large>[GLOB.using_map.station_name]</large></b><BR><i>[station_date]</i><BR><i>Export overview<field></i></center><hr>"
	for(var/source in point_source_descriptions)
		t += "[point_source_descriptions[source]]: [supply_controller.point_sources[source] || 0]<br>"
	print_text(t, user)

/datum/nano_module/program/innie_supply/proc/print_text(var/text, var/mob/user)
	var/obj/item/modular_computer/MC = nano_host()
	if(istype(MC))
		if(!MC.nano_printer)
			to_chat(user, "Error: No printer detected. Unable to print document.")
			return

		if(!MC.nano_printer.print_text(text))
			to_chat(user, "Error: Printer was unable to print the document. It may be out of paper.")
	else
		to_chat(user, "Error: Unable to detect compatible printer interface. Are you running NTOSv2 compatible system?")