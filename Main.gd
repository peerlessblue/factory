extends Node


class Math:
	static func factorial(n):
		var out = 1
		for i in range(2, n+1):
			out *= i
		return out
	
	static func distance(first: Vector2, second: Vector2):
		return sqrt((first.x - second.x)**2 + (first.y - second.y)**2)

class Random:
	const remove_entropy = true
	static func random() -> float:
		if remove_entropy:
			return 0.5
		else:
			return randf()

	static func choice(array: Array):
		if remove_entropy:
			return array[0]
		else:
			return array[randi() % array.size()]

	static func weighted_choice(options: Array, weights: Array):
		if remove_entropy:
			return options[0]
		else:
			var out_i = 0
			var check = randf()
			var accumulator = weights[0]
			while check > accumulator:
				out_i += 1
				accumulator += weights[out_i]
			return options[out_i]
	
	#FIXME: does this work??
	static func beta_variate(alpha, beta):
		if remove_entropy:
			return alpha / (alpha + beta)
		else:
			return randf() ** (1.0 / alpha) / (randf() ** (1.0 / beta))

	static func exponential_variate(lmbda: float) -> float:
		if remove_entropy:
			return 1 / lmbda
		else:
			return -log(1 - randf()) / lmbda
	#FIXME: does this work??
	static func geometric_variate(p):
		if remove_entropy:
			return floor(1 / p)
		else:
			return floor(log(randf())/log(1-p))

	static func normal_variate(mu, sigma):
		if remove_entropy:
			return mu
		else:
			return randfn(mu, sigma)

	#FIXME: does this work??
	static func poisson_variate(lmbda):
		if remove_entropy:
			return floor(lmbda)
		else:
			var out = 0
			var check = randf()
			var accumulator = lmbda ** out * exp(-lmbda)/Math.factorial(out)
			while check > accumulator:
				out += 1
				accumulator += lmbda ** out * exp(-lmbda)/Math.factorial(out)
			return out

class Actor extends Object:
	static var actor_count = 0
	static var kind_counts = {}
	static var DEBUG_ACTORS = false
	static var ANNOUNCE = false
	static var SCALE_FACTOR = 2880 # 2880 is one day
	static var STRING_MODE = "kind"
	static var STRICT_MODE = true
	const RICH_PRINT = true
	const PRINT_COLORS = [
		"red",
		"green",
		"yellow",
		"blue",
		"magenta",
		"pink",
		"purple",
		"cyan",
		"white",
		"orange",
		"gray",]

	var sim
	var kind
	var internal_name = "actor"
	var coords: Vector2
	var kind_and_type
	var debug = Actor.DEBUG_ACTORS
	var engaged = false
	var ready_to_act = false
	var capacity = INF
	var location
	var contents: Array = []
	var size = Vector2(12,12)
	var color = Color(255,0,0,255)
	var generic
	var number
	var kind_number
	var active_events = 0
	var past_events = 0
	var intents = []
	var day_action_counts = {}
	var day_action_list = []
	var day_proc_list = []
	var all_action_counts = {}
	var all_action_list = []
	var all_proc_list = []
	var records = []
	var memory = []  # Reintroduced memory list

	func _init(sim_p, kind_p = "generic", coords_p: Vector2 = Vector2(0,0)):
		sim = sim_p
		kind = kind_p
		coords = coords_p
		kind_and_type = str(kind) + " " + type_string(typeof(self)).to_lower()

		generic = kind == "generic"
		Actor.actor_count += 1
		number = Actor.actor_count

		if kind_and_type in Actor.kind_counts:
			Actor.kind_counts[kind_and_type] += 1
		else:
			Actor.kind_counts[kind_and_type] = 1
		kind_number = Actor.kind_counts[kind_and_type]

		location = sim
		location.contents.append(self)

	func _to_string():
		if Actor.STRING_MODE == "kind":
			return "%s %s %s" % [kind, internal_name ,str(number)]
		elif generic:
			return type_string(typeof(self)).to_lower() + str(number)
		else:
			return str(kind) + " " + type_string(typeof(self)).to_lower() + " " + str(number)

	func record(args):
		if Actor.RICH_PRINT:
			print_rich(args)
		else:
			print(args)
		if args is String:
			self.sim.records.append(args)
		elif args is Array:
			self.sim.records.append_array(args)
		else:
			self.sim.records.append(str(args))

	func dump_statistics():
		for x in day_action_counts:
			if x in all_action_counts:
				all_action_counts[x] += day_action_counts[x]
			else:
				all_action_counts[x] = day_action_counts[x]

		all_action_list.append_array(day_action_list)
		all_proc_list.append_array(day_proc_list)

		day_action_counts = {}
		day_action_list = []
		day_proc_list = []

	func proc(function: Callable, kwargs: Dictionary = {}):
		#TODO: make proc fire a single event
		#TODO: make a signal path
		active_events += 1
		var new_event = Event.new(self, function, kwargs)
		day_proc_list.append(new_event)
		sim.prep(new_event)

	func transfer_to(location_p, active_position = false, index = "bulk"):
		#TODO: clean this up?
		location.contents.erase(self)
		if location_p == null:
			record("trashing" + str(self))
			#FIXME: unload this working?
			assert(len(contents) == 0)
			# queue_free()
		else:
		# if len(location.contents) >= location.capacity:
		# 	raise ValueError("Location at capacity:"+ str(location))
			assert(len(location.contents) <= location.capacity)
			if engaged:
				location.active_position = null
				engaged = false
			if not location.contents and location is Bin:
				record("trashing bin")
				location.transfer_to(null)
			location = location_p
			if index == "bulk":
				location.contents.append(self)
			else:
				location.contents[index] = self
			if active_position:
				location.active_position = self
				engaged = true

	func trash():
		pass
		#fixme: make this

	func contents_of_kind(type_p):
		var result = []
		for x in contents:
			if typeof(x) == typeof(type_p):
				result.append(x)
		return result

	func count_action(action):
		if action in day_action_counts:
			day_action_counts[action] += 1
		else:
			day_action_counts[action] = 1
			if action == "operate":
				record("First daily operation for %s @ %s" % [self, sim.day_clock])
				# sim.output.append(sim.day_clock)
				memory.append("first")  # Reintroduced use of memory list
		day_action_list.append("%s : %s" % [("%.4f" % sim.clock), action])
		if Actor.STRICT_MODE:
			assert(active_events > 0)

	func draw(screen):
		pass
		#FIXME: ensure not needed
		# rect = pg.Rect(coords, size)
		# pg.draw.rect(screen, color, rect, border_radius=2)

class Widget extends Actor:
	static var widget_count = 0
	var values
	var property_one
	var property_two
	var property_three
	var property_four
	var frequency
	var quality = {}
	var on_conveyor = false
	var p_n
	
	# this is static here but is normally built by the simulator when run. this is more for reference for what the data I was using generates
	const  PART_TABLE = {
		"0" : {"property_one": 0, "property_two": 0, "property_three": false, "property_four": false, 'frequency': 0},
		'A': {'property_one': 0.625, 'property_two': 'four', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'B-0': {'property_one': 1.5, 'property_two': 'four', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'C': {'property_one': 0.625, 'property_two': 'six', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'D-1': {'property_one': 0.5, 'property_two': 'six', 'property_three': false, 'property_four': true, 'frequency': 1.0/42.0}, 
		'E-1': {'property_one': 1.25, 'property_two': 'six', 'property_three': false, 'property_four': true, 'frequency': 1.0/42.0}, 
		'F-1': {'property_one': 3.0, 'property_two': 'six', 'property_three': false, 'property_four': true, 'frequency': 1.0/42.0}, 
		'G': {'property_one': 1.0, 'property_two': 'six', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'H': {'property_one': 1.125, 'property_two': 'six', 'property_three': true, 'property_four': true, 'frequency': 1.0/42.0}, 
		'I-1': {'property_one': 1.5, 'property_two': 'six', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'J': {'property_one': 1.25, 'property_two': 'four', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'K-0': {'property_one': 1.0, 'property_two': 'six', 'property_three': false, 'property_four': true, 'frequency': 1.0/42.0}, 
		'L-1': {'property_one': 1.0, 'property_two': 'six', 'property_three': false, 'property_four': true, 'frequency': 1.0/42.0}, 
		'M-1': {'property_one': 1.5, 'property_two': 'six', 'property_three': false, 'property_four': true, 'frequency': 1.0/42.0}, 
		'N': {'property_one': 1.25, 'property_two': 'four', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'O-0': {'property_one': 0.5, 'property_two': 'six', 'property_three': false, 'property_four': true, 'frequency': 1.0/42.0}, 
		'P': {'property_one': 1.75, 'property_two': 'four', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'Q': {'property_one': 1.25, 'property_two': 'six', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'R': {'property_one': 1.5, 'property_two': 'six', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'S': {'property_one': 0.75, 'property_two': 'six', 'property_three': true, 'property_four': true, 'frequency': 1.0/42.0}, 
		'T-0': {'property_one': 0.75, 'property_two': 'six', 'property_three': false, 'property_four': true, 'frequency': 1.0/42.0}, 
		'U': {'property_one': 1.5, 'property_two': 'four', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'V-1': {'property_one': 0.75, 'property_two': 'six', 'property_three': false, 'property_four': true, 'frequency': 1.0/42.0}, 
		'W': {'property_one': 1.0, 'property_two': 'four', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'X-1': {'property_one': 2.0, 'property_two': 'six', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'Y-1': {'property_one': 0.5, 'property_two': 'six', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'Z-1': {'property_one': 2.0, 'property_two': 'six', 'property_three': false, 'property_four': true, 'frequency': 1.0/42.0}, 
		'AA': {'property_one': 0.75, 'property_two': 'six', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'BB': {'property_one': 0.5, 'property_two': 'four', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'CC': {'property_one': 1.75, 'property_two': 'four', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'DD-1': {'property_one': 2.5, 'property_two': 'six', 'property_three': false, 'property_four': true, 'frequency': 1.0/42.0}, 
		'EE': {'property_one': 0.75, 'property_two': 'four', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'FF-1': {'property_one': 1.5, 'property_two': 'four', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'GG-0': {'property_one': 1.75, 'property_two': 'four', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'HH': {'property_one': 0.5, 'property_two': 'four', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'II-1': {'property_one': 3.0, 'property_two': 'six', 'property_three': false, 'property_four': true, 'frequency': 1.0/42.0}, 
		'JJ': {'property_one': 0.5, 'property_two': 'six', 'property_three': true, 'property_four': true, 'frequency': 1.0/42.0}, 
		'KK': {'property_one': 0.5, 'property_two': 'six', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'LL-1': {'property_one': 0.75, 'property_two': 'six', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'MM-1': {'property_one': 2.5, 'property_two': 'six', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'NN-0': {'property_one': 1.5, 'property_two': 'four', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'OO': {'property_one': 2.0, 'property_two': 'four', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'PP-1': {'property_one': 1.0, 'property_two': 'six', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}, 
		'QQ': {'property_one': 2.0, 'property_two': 'six', 'property_three': false, 'property_four': false, 'frequency': 1.0/42.0}
	}
	func _init(sim_p: Simulator, kind = "generic", p_n_p = "0"):
		values = Widget.PART_TABLE[p_n_p].values()
		property_one = values[0]
		property_two = values[1]
		property_three = values[2]
		property_four = values[3]
		frequency = values[4]
		super._init(sim_p, kind)
		Widget.widget_count += 1
		number = Widget.widget_count
		
		location = sim.staging
		location.contents.append(self)
		
		p_n = p_n_p
		
		internal_name = "widget"

class Agent extends Actor:
	static var agent_count = 0
	var moving
	var new_coords
	var speed
	var priority_list
	func _init(sim_p: Simulator, kind = "generic", coords: Vector2 = Vector2(0,0)):
		super._init(sim_p, kind, coords)
		sim.agents.append(self)
		Agent.agent_count += 1
		number = Agent.agent_count

		moving = false
		new_coords = null
		speed = 0

		priority_list = []
		internal_name = "agent"

	func stage():
		ready_to_act = false
		sim.active_agents -= 1
		if debug:
			record("Agent %s staged." % self)
			push_warning("Agent %s staged." % self)
	func unstage():
		ready_to_act = true
		sim.active_agents += 1
		if debug:
			record("Agent %s unstaged." % self)
			push_warning("Agent %s unstaged." % self)

	func move(station_p = null, coords_p = null):
		if location != sim and station_p == location:
			var error_message = "Cannot move to current location: {0} to {1}".format([self, location])
			push_error(error_message)
		moving = true
		ready_to_act = false
		transfer_to(sim)
		var dest: Vector2
		if station_p:
			dest = station_p.coords + station_p.op_offset
		elif coords_p:
			dest = coords_p
		assert(dest != null)
		new_coords = dest
		var distance = Math.distance(coords, dest)
		var duration = 0 if not speed else distance / speed
		proc(func():
			arrive(station_p, dest),
			{
				"duration": duration,
				"kind": "arrive",
				"override": true
			}
		)
		if Actor.ANNOUNCE:
			record("%s move to %s, %s" % [self, dest.x, dest.y])
		count_action("move")
		
	func arrive(station_p = null, coords_p = null):
		if station_p:
			transfer_to(station_p)
		coords = coords_p
		moving = false
		ready_to_act = true
		proc(think)
		count_action("arrive")
	
	func reprioritize():
		#TODO: incorporate some kind of sorting
		priority_list = sim.priority_list

	func think():
		proc(think, {"duration" : 10 + Random.random()})
		count_action("think")

	func draw(screen):
		pass
		#FIXME: ensure not needed
		# rect = pg.Rect(coords, size)
		# pg.draw.rect(screen, color, rect)
		# if moving:
		# 	pg.draw.line(screen,color,coords,new_coords,3)

class Customer extends Agent:
	static var customer_count = 0
	func _init(sim_p: Simulator, kind = "generic"):
		super._init(sim_p, kind)
		Customer.customer_count += 1
		number = Customer.customer_count
	
class Worker extends Agent:
	static var worker_count = 0
	const VERBOSE = 0
	var hours
	var operation_one
	var fatigue
	var mem_count
	func _init(sim_p: Simulator, kind = "generic"):
		super._init(sim_p, kind)
		Worker.worker_count += 1
		transfer_to(sim_p.staging)
		number = Worker.worker_count		
		hours = {"operation_one" : 0, "operation_two" : 0, "hang" : 0, "break" : 0, "other" : 0}
		operation_one = true
		capacity = 1
		fatigue = 0.0
		color = Color(0,0,255)
		memory = []
		mem_count = 0
		priority_list = []
		#TODO: scale speed to fatigue
		speed = 56 * (0.95 + Random.random()/10)
		internal_name = "worker"
	func stage():
		super.stage()
	func unstage():
		super.unstage()
		reprioritize()
		proc(go_to_station)
	func think():
		#TODO: stage a wait here?
		#TODO: expectation is that agents cannot think with active events-- check this?
		assert(active_events == 0)
		if intents:
			var intent = intents.pop_back()
			match intent:
				"take break":
					proc(go_to_break, {"kind": "break"})
				"go home":
					proc(func (): move(sim.staging), {"kind": "go home"})
					intents.append("close day")
				"close day":
					proc(stage, {"kind": "sleep"})
				"wake up":
					proc(unstage, {"kind": "wake up"})
		elif sim.on_break and location.kind == "staging":
			proc(func (): take_break(), {"kind": "break"})
		elif kind == "gopher":
			proc(act_gopher)
		elif kind == "hang":
			proc(act_hang)
		elif kind == "operation_one":
			proc(act_operation_one)
		elif kind == "operation_two":
			proc(act_operation_two)
		else:
			pass
		assert(active_events > 0)
		count_action("think")
		#proc(think,duration = 10 + Random.random())
	func act_gopher():
		#TODO: come on man
		var fallback = false
		if location.kind == "operation_zero":
			if not contents:
				proc(search_location, {"duration": Random.random()})
			else:
				proc(func (): move(Random.choice(sim.get_stations("hang"))), {"kind": "move"})
		elif location.kind == "operation_two":
			if not contents:
				proc(search_location, {"duration": Random.random()})
			else:
				proc(func (): move(Random.choice(sim.get_stations("finished storage"))), {"kind": "move"})
		elif contents:		
			if location.kind == "hang" and contents[0].kind == "operation_zero":
				proc(deliver, {"duration": Random.random()})
			elif location.kind == "finished storage" and contents[0].kind == "operation_two":
				proc(deliver, {"duration": Random.random()})
			else:
				fallback = true
		elif past_events < 100:
			proc(func (): move(Random.choice(sim.get_stations("operation_zero"))), {"kind": "move"})
		elif "operation_zero empty" in memory:
			proc(func (): move(Random.choice(sim.get_stations("operation_two"))), {"kind": "move"})
		else:
			proc(func (): move(Random.choice(sim.get_stations("operation_zero")+sim.get_stations("operation_two"))), {"kind": "move"})
		if fallback:
			if contents:
				proc(deliver, {"duration": Random.random(), "kind": "fallback deliver", "announce": true})
			elif location.kind != "gopher":
				proc(go_to_station, {"duration": 10 + Random.random(), "kind": "fallback move", "announce": true})
			elif location.kind != "staging":
				proc(func (): move(sim.staging), {"duration": 10 + Random.random(), "kind": "fallback move", "announce": true})
			else:
				push_error("Runtime Error: Unhandled logic escape: %s" % self)
		count_action("act_gopher")
	func act_hang():
		#TODO: stop overhanging because of shared p_n for lower priority orders
		if location.kind == "hang":
			if not contents:
				proc(search_location, {"duration": Random.random()})
			else:
				proc(check_to_hang, {"duration": max(0.5,Random.normal_variate(2.687,0.853))})
		else:
			proc(go_to_station)
		count_action("act_hang")
	func act_operation_one():
		if location.kind == "operation_one":
			var widgets = contents_of_kind(Widget)
			if widgets:
				var operation_oneed_widgets = []
				var operation_zeroed_widgets = []
				for widget in widgets:
					if "operation_one" in widget.quality:
						operation_oneed_widgets.append(widget)
					if widget.kind == "operation_zero":
						operation_zeroed_widgets.append(widget)
				if operation_oneed_widgets:
					proc(func (): check_to_hang(Random.choice(operation_oneed_widgets)), {"kind": "check to hang", "duration": max(0.5,Random.normal_variate(2.687,0.853))})
				elif operation_zeroed_widgets and location.ready_to_act:
					proc(func (): operate(Random.choice(operation_zeroed_widgets)), {"kind": "operate operation_one"})
			else:
				proc(func (): check_to_unhang(["operation_zero"]), {"duration": max(0.5,Random.normal_variate(4.982,0.875)), "kind": "check to unhang operation_zero"})
		else:
			proc(go_to_station)
		count_action("act_operation_one")
	func act_operation_two():
		if location.kind == "operation_two":
			var widgets = contents_of_kind(Widget)
			if widgets:
				var operation_oneed_widgets = []
				var ground_widgets = []
				for widget in widgets:
					if "operation_one" in widget.quality:
						operation_oneed_widgets.append(widget)
					if "operation_two" in widget.quality:
						ground_widgets.append(widget)		
				if ground_widgets:
					proc(func (): deliver(Random.choice(ground_widgets)), {"duration": Random.random(), "kind": "deliver"})
				elif operation_oneed_widgets and location.ready_to_act:
					proc(func (): operate(Random.choice(operation_oneed_widgets)), {"kind": "operate operation_two"})
			else:
				proc(func (): check_to_unhang(["operation_one"]), {"duration": max(0.5,Random.normal_variate(4.982,0.875)), "kind": "check to unhang operation_one"})
		else:
			proc(go_to_station)
		count_action("act_operation_two")
	func search_location():
		var widgets = []
		for item in location.contents:
			if item is Widget:
				widgets.append(item)
		
		var bins = []
		for item in location.contents:
			if item is Bin:
				bins.append(item)
		
		if not location.ready_to_act:
			proc(abort_search)
		elif not widgets and not bins:
			proc(abort_search)
			if location.kind == "operation_zero":
				memory.append("operation_zero empty")
		else:
			proc(grab, {"duration": Random.random()})
		count_action("search location")
	func abort_search():
		if kind == location.kind:
			proc(think, {"duration": 100})
		else:
			proc(go_to_station)
		count_action("abort search")

	func grab(use_priority = true):
		var widgets = []
		for item in location.contents:
			if item is Widget:
				widgets.append(item)
		
		var bins = []
		for item in location.contents:
			if item is Bin:
				bins.append(item)
		
		if not bins and not widgets:
			push_error("ValueError: Cannot grab: no bins")
		
		var selected_widget = null

		if use_priority:
			for p_n in priority_list:
				for widget in widgets:
					if widget.kind == p_n:
						selected_widget = widget
						break
				for bin in bins:
					if bin.kind == p_n:
						if bin.contents:
							selected_widget = bin.contents[0]
							break
				if selected_widget:
					break
		else:
			push_error("Cannot grab: no widgets or bins on priority list")
		
		if selected_widget:
			selected_widget.transfer_to(self)
		else:
			push_error("RuntimeError: Whiffed a grab: %s" % self)
		proc(think)
		count_action("grab")

	func deliver(thing = null):
		if not contents:
			push_error("Cannot deliver: no inventory")
		if not thing:
			thing = Random.choice(contents)
		thing.transfer_to(location)
		proc(think)
		count_action("deliver")
		
	func check_to_hang(widget = null, double_up = true):
		var hook = sim.conveyor.get_hook(coords)
		# record("%s sees %s" % [self, hook])
		if len(hook.contents) == 0 or double_up and len(hook.contents) < hook.capacity:
			proc(func (): hang(widget), {"kind": "hang"})
		else:
			proc(think, {"duration": 1/sim.conveyor.speed})
		count_action("check_to_hang")
	func check_to_unhang(targets: Array[String]):
		if kind == "operation_one":
			mem_count += 1
			if "first" in memory:
				memory.clear()
		var hook = sim.conveyor.get_hook(coords)
		var items = hook.contents

		# record(f"{self} sees {hook}")

		var items_to_unhang = []
		if items:
			for target in targets:
				for item in items:
					if item.kind == target and item not in items_to_unhang:
						items_to_unhang.append(item)
		if items_to_unhang:
			proc(func (): unhang(items_to_unhang), {"kind": "unhang"})
		else:
			proc(think, {"duration": 1/sim.conveyor.speed})
		count_action("check_to_unhang")
	func hang(widget = null):
		if not contents:
			push_error("Cannot hang: no inventory")
		else:
			if not widget:
				widget = Random.choice(contents_of_kind(Widget))
			sim.conveyor.put_up(coords,widget)
			proc(think)
		count_action("hang")
	func unhang(items_to_unhang):
		for item in items_to_unhang:
			if len(contents) < capacity:
				sim.conveyor.drop_off(self, item)
			elif Worker.VERBOSE:
				#TODO: handle this better?
				record("%s at capacity." % self)
		proc(think)
		count_action("unhang")
	func operate(item):
		item.transfer_to(location, true)
		ready_to_act = false
		if kind == "operation_one":
			proc(func (): location.actuate(self), {"kind": "actuate", "override": true, "duration": max(0.5,Random.normal_variate(8.185,1.218))})
		elif kind == "operation_two":
			proc(func (): location.actuate(self), {"kind": "actuate", "override": true, "duration": max(0.5,Random.normal_variate(4.523,1.488))})
		else:
			push_error("Unhandled operation type: %s" % kind)
		count_action("operate")
	func reset():
		var widget = location.active_position
		widget.transfer_to(self)
		ready_to_act = true
		location.ready_to_act = true
		proc(think)
		count_action("reset")
	func go_to_station():
		var stations = []
		for agent in sim.agents:
			if agent is Station and agent.kind == kind:
				stations.append(agent)
		if stations:
			proc(func (): move(Random.choice(stations)), {"kind": "move"})
		else:
			proc(think)
		count_action("go to station")
	func go_to_break():
		if location.kind != "staging":
			proc(func (): move(sim.staging), {"kind": "move to break"})
	func take_break(duration = null):
		if not duration:
			duration = Random.random() + sim.break_end - sim.day_clock
		proc(think, {"duration": duration, "kind": "think after break"})
		count_action("break")

class Station extends Agent:
	static var station_count = 0
	const APPEND_CONTROL_POINT = false
	var walkable = false
	var op_offset = Vector2(0,0)
	func _init(sim: Simulator, kind = "generic", coords_p: Vector2 = Vector2(0,0)):
		super._init(sim, kind, coords_p)
		Station.station_count += 1
		number = Station.station_count	

		if not coords_p:
			coords = Vector2(Station.station_count * 100, 0)
		else:
			coords = coords_p

		ready_to_act = true
		internal_name = "station"
	func unstage():
		super.unstage()
		if Station.APPEND_CONTROL_POINT:
			sim.conveyor.set_control_points([coords])

# from oven to break room:
# 1: 3.3
# 2: BF not over 2 inch
# 3: 4p
# 4: BF not over 3 inch
# 5: 6p (brush?)

# change size: 15 minutes, all
# change between 3" and under 3": 30-45 minutes, 2/4/5
# change type: 30-45 minutes, 2/4/5

class Equipment extends Station:
	static var equipment_count = 0

	var beta_mag = 50
	var beta_ratio = 0.01
	var beta_delta = 0.001
	var beta_inc = 0

	var effectiveness = 1
	var cycles = 0
	var last_maintenance = 0
	var last_cleaning = 0

	var active_position = null
	func _init(sim: Simulator, kind = "generic", coords = Vector2(0,0), capacity_p = INF):
		super._init(sim, kind, coords)

		Equipment.equipment_count += 1
		number = Equipment.equipment_count

		capacity = capacity_p

		internal_name = "equipment"

	func actuate(operator):
		#TODO: implement fail
		ready_to_act = false
		var success = true
		if success:
			var part = active_position
			#TODO: improve this
			var beta = beta_mag * (beta_ratio + beta_delta * beta_inc)
			var alpha = beta_mag - beta
			part.quality[kind] = Random.beta_variate(alpha, beta)
			part.kind = kind
			cycles += 1
			operator.proc(operator.reset, {"override": true})
		else:
			pass

class Conveyor extends Equipment:
	static var conveyor_count = 0
	const VERBOSE = 0
	var index = 0
	var control_points = []
	var belt_length_cache = 0
	var nearest_point_cache = {}
	var cached_belt_lengths = []
	var hook_span = 6
	var hook_count = 0
	func _init(sim: Simulator, kind = "generic", control_points_p = [Vector2(0,0),Vector2(0,1000)]):
		super._init(sim, kind)
		Conveyor.conveyor_count += 1
		number = Conveyor.conveyor_count

		color = Color(255,255,255)

		walkable = true
		speed = 1/5.27 #stations per second

		control_points = control_points_p

		cache_belt_lengths()

		hook_count = int(belt_length()) / hook_span

		for x in range(hook_count):
			contents.append(Hook.new(sim))
		internal_name = "conveyor"
	func set_control_points(control_points: Array = [], clear = true):
		if clear:
			control_points = control_points
		else:
			control_points.append_array(control_points)
		nearest_point_cache = {}
		belt_length(-1, true)
		respan_hooks()
	func respan_hooks(container: Actor = null):
		var old_hook_count = hook_count
		hook_count = int(belt_length()) / hook_span
		if old_hook_count < hook_count:
			var new_hooks = []
			for x in range(hook_count - old_hook_count):
				var new_hook = Hook.new(sim)
				new_hooks.append(new_hook)
				contents.append(new_hook)
		if old_hook_count > hook_count:
			push_error("NotImplementedError: Line shrank with hook respan from %s to %s" % [old_hook_count, hook_count])
			var old_hook_contents = []
			for x in contents:
				for y in x.contents:
					old_hook_contents.append(y)
			if old_hook_contents and not container:
				push_error("Hooks respanned on line while carrying items: %s" % old_hook_contents)
			if old_hook_contents:
				container.contents.append_array(old_hook_contents)
	func advance(time):
		var old = index
		index += time * speed
		while index >= hook_count:
			index -= hook_count
		if Conveyor.VERBOSE:
			record("Conveyor: %s to %s @ %s" % [old, index, sim.day_clock])
	func advance_hook_positions():
		#TODO: this
		pass
	func belt_length(points_to_count = -1, clear_cache = false):
		#TODO check this
		if points_to_count < 0:
			points_to_count = len(control_points)
		if clear_cache:
			cache_belt_lengths()
		var a = cached_belt_lengths[points_to_count]
		return a
	func get_position_from_fraction(fraction):
		#I am very tired
		var lengths = cached_belt_lengths
		var total_length = lengths[-1]
		var prev = 0
		var next = 0
		var i = 0
		while i in range(len(lengths)):
			next = lengths[i]/total_length
			if next > fraction:
				prev = lengths[i-1]/total_length
				break
			i += 1
		var new_frac =  (fraction - prev)/(next - prev)
		if i == len(control_points):
			i = 0
		return control_points[i-1].lerp(control_points[i],new_frac)
	func cache_belt_lengths():
		cached_belt_lengths = [0]
		var dist = 0
		for i in range(len(control_points)):
			dist += Math.distance(control_points[i],control_points[(i+1)%len(control_points)])
			cached_belt_lengths.append(dist)
	func nearest_point(coords:Vector2, index_offset_form = true):
		#TODO: vectorize
		#this is like, a convex hull problem and I don't remember how that works efficiently
		if coords in nearest_point_cache and index_offset_form:
			return nearest_point_cache[coords]
		var x = coords[0]
		var y = coords[1]
		var lowest = INF
		var index = -1
		var offset = 0
		var out = null
		for i in range(len(control_points)):
			var x1 = control_points[i-1].x; var y1 = control_points[i-1].y
			var x2 = control_points[i].x; var y2 = control_points[i].y
			var xt = x - x1; var yt = y - y1
			var theta = atan2(y2 - y1, x2 - x1)
			var sin_r = sin(-theta)
			var cos_r = cos(-theta)
			var pos = xt*cos_r - yt*sin_r
			var m = ((x2 - x1)**2 + (y2 - y1)**2)**0.5
			var dist = 0
			var span = ""
			if pos <= 0:
				dist = ((x1-x)**2 + (y1-y)**2)**0.5
				span = "origin"
			elif pos >= m:
				dist = ((x2-x)**2 + (y2-y)**2)**0.5
				span = "endpoint"
			else: 
				dist = abs(xt*sin_r + yt*cos_r)
				span = "midspan"
			if dist < lowest:
				lowest = dist
				match span:
					"origin":
						out = Vector2(x1, y1)
						index = i-1
						offset = 0
					"endpoint":
						out = Vector2(x2, y2)
						index = i
						offset = 0
					"midspan":
						out = Vector2(pos*cos_r + x1, -pos*sin_r + y1)
						index = i-1
						offset = pos
		if index_offset_form:
			if index == -1:
				index = len(control_points)
			nearest_point_cache[coords] = [index, offset]
			return [index, offset]
		else:
			return out
	func get_percent(coords):
		var index = nearest_point(coords)[0]
		var offset = nearest_point(coords)[1]
		var a = belt_length(index)
		var b = offset
		var partial = a + b
		var total = belt_length()
		var out = partial / total
		if out > 1:
			push_error("ValueError: Belt percentage over 100%")
		return out
	func get_conveyor_index(coords):
		#TODO: good lord what is happening in there
		#TODO: weird flip??
		return int(floor((-index + get_percent(coords) * hook_count))) % hook_count
	func get_hook(coords):
		var hook = contents[get_conveyor_index(coords)]
		assert(hook is Hook)
		return hook
	func drop_off(agent: Agent, widget: Widget):
		widget.transfer_to(agent)
	func put_up(coords, widget: Widget):
		widget.transfer_to(get_hook(coords))
	func draw(screen):
		#FIXME: do we need this?
		pass
		# pg.draw.lines(screen, color, true, control_points, 3)
		# rect = pg.Rect(get_position_from_fraction(index/hook_count), size)
		# pg.draw.rect(screen, (0,255,0), rect)


class Hook extends Actor:
	static var hook_count = 0
	func _init(sim: Simulator, kind = "generic"):
		super._init(sim, kind)
		Hook.hook_count += 1
		number = Hook.hook_count	
		capacity = 2
		internal_name = "hook"
	func _to_string():
		return super._to_string() + " w/ %s" % (str(contents) if contents else "nothing")
	
class Bin extends Actor:
	static var bin_count = 0
	func _init(sim: Simulator, kind = "generic", capacity = INF):
		super._init(sim, kind)
		Bin.bin_count += 1
		number = Bin.bin_count	
		capacity = capacity
		internal_name = "bin"
	func _to_string():
		return super._to_string() + " w/ %s" % (str(contents) if contents else "nothing")

class Event:
	#TODO: strict mode by counting active actions
	static var event_count = 0
	const CONFORM_REPRESENTATION = true
	const VERBOSITY = 0
	const SAFETY_SECOND = false
	const BB_PRINT = false
	const ANSI_PRINT = false
	const PRINT_COLORS = [
		"red",
		"green",
		"yellow",
		"blue",
		"magenta",
		"pink",
		"purple",
		"cyan",
		"white",
		"orange",
		"gray",]
	#TODO: event kind enums
	const NAME_LENGTH = 23
	var action: Callable
	var kind: String
	var duration: float
	var priority: = 0 #lower is more important
	var next
	var override: bool
	var announce: bool
	var carryover: bool
	var number: int
	var creator
	var sim
	var start: float
	var deterministic: bool
	var internal_name = "event"
	func _init(creator_p: Actor, action_p: Callable, event_dictionary: Dictionary = {}):
		action = action_p
		kind = event_dictionary.get("kind", "generic")
		duration = event_dictionary.get("duration", 0.0)
		priority = event_dictionary.get("priority", 0)
		next = event_dictionary.get("next", null)
		override = event_dictionary.get("override", false)
		announce = event_dictionary.get("announce", false)
		carryover = event_dictionary.get("carryover", false)
		Event.event_count += 1
		number = Event.event_count
		if kind == "generic" and action:
			#if creator_p.kind == "operation_two":
				#print(action_p)
				#if str(action_p) == "deliver_test(lambda)":
					#print("yes")
			#FIXME: why does this fail when deliver doesn't have a kind in the event dictionary???
			kind = action.get_method()
			#print("hello! ",kind)
		creator = creator_p
		sim = creator.sim
		if duration == 0 and Event.SAFETY_SECOND and not priority:
			duration = Random.random()
		start = sim.clock + duration
		deterministic = false
		if priority:
			assert(duration == 0, "RuntimeError: Priority event given duration")
		
	static func lt(first, second):
		#true if self is less important than second
		if first.priority != second.priority:
			return first.priority < second.priority
		elif first.start != second.start:
			return first.start < second.start
		elif first.number != second.number:
			return first.number > second.number
		else:
			return false

	static func gt(first, second):
		if first.priority != second.priority:
			return first.priority > second.priority
		elif first.start != second.start:
			return first.start > second.start
		elif first.number != second.number:
			return first.number < second.number
		else:
			return false

	func _to_string():
		if Event.CONFORM_REPRESENTATION:
			return "%s event #%s @ %.8f by %s" % [kind, number, start, str(creator).left(-1)]
		elif kind == "move":
			#FIXME: this broke somehow
			return "%s event @ %s by %s" % [kind, start, creator]
		elif Event.BB_PRINT:
			return "[color=%s]%s[/color] event @ %13.5f by %s" % [
				Event.PRINT_COLORS[hash(kind)%len(Event.PRINT_COLORS)],
				kind.rpad(Event.NAME_LENGTH),
				start,
				creator]
		elif Event.ANSI_PRINT:
			return "\\u001b[1;31m %s event @ %13.5f by %s" % [
				31 + hash(kind)%6,
				kind.rpad(Event.NAME_LENGTH),
				start,
				creator]
		else:
			return "%s event @ %s by %s" % [kind, start, creator]
	func resolve():
		if Event.VERBOSITY >= 1 or creator.debug or announce:
			sim.record(self)
		creator.past_events += 1
		creator.active_events -= 1
		if Event.VERBOSITY >= 2:
			sim.record("resolving: " + str(action))
		if creator.ready_to_act or override:
			action.call()
		else:
			push_error("RuntimeError: Object not ready to act: %s to %s" % [creator, action])
		if next:
			sim.prep(next)

class Plant:
	var production_plan = []
	func go_to_a():
		pass
	func go_to_b():
		pass

class Order extends Actor:
	static var order_count = 0
	var p_n = -1
	var quantity = 0
	var days_to_fulfill = INF
	var days_remaining = INF
	var init_day = 0
	func _init(sim, quantity_p, kind : String = "generic", days_to_fulfill_p = INF):
		super._init(sim, kind)
		Order.order_count += 1
		number = Order.order_count

		color = Color(255,255,255)

		p_n = kind
		quantity = quantity_p
		capacity = quantity_p
		days_to_fulfill = days_to_fulfill_p
		days_remaining = days_to_fulfill_p
		init_day = sim.day
		internal_name = "order"
	func _to_string():
		return "Order #%s for %s of #%s in %sd" % [number, quantity, kind, days_remaining]
	static func lt(first, second):
		return first.days_remaining < second.days_remaining
	# func draw(screen, coords):
	# 	rect = pg.Rect(coords, size)
	# 	pg.draw.rect(screen, color, rect)


	# 	rect = pg.Rect(coords, self.size)
	# 	pg.draw.rect(screen, self.color, rect)


class Simulator extends Actor:
	static var simulator_count = 0
	const DEBUG_SIMULATOR = true

	const LAYOUT_TEST = [Vector2(100,100),Vector2(1000,100),Vector2(1000,1000),Vector2(100,1000),]

	const PUBLIC_VERSION = true

	
	var gui = false
	var data
	var job_list
	var model_directory
	var plant
	var avg_order_size = 824
	var daily_demand_rate = 1500
	var order_rate
	var operating = true
	var standby = false
	var clock = 0
	var day_clock = 0
	var break_end = 0
	var on_break = false
	var day = 1
	var end_day
	var end_time
	var clock_event_offset = 0
	var active_agents = 0
	var next_tick_procced = false
	var in_closing = false
	var closed = false
	var events: Array[Event] = []
	var agents = []
	var conveyor = null
	var staging = null
	var open_orders = []
	var filled_orders = []
	var priority_list = []
	var output = []
	var new_config
	var attempting_shutdown = false
	
	func _init(new_config_p: bool = false, day_limit_p: int = 10, clock_offset_p:int = 0, end_time_p = 0):
		super._init(self)
		Simulator.simulator_count += 1
		number = Simulator.simulator_count
		data = self.pull_data()
		job_list = self.build_job_list(data)
		model_directory = self.build_model_directory(data)
		plant = Plant.new()
		order_rate = daily_demand_rate *1.0/ avg_order_size
		end_day = day_limit_p
		end_time = end_time_p if end_time_p else Actor.SCALE_FACTOR * 100
		clock_event_offset = clock_offset_p if clock_offset_p else 50
		new_config = new_config_p
		ready_to_act = true
		internal_name = "simulator"
		proc(self.setup)

	func prep(event: Event):
		#TODO: optimize insertion?
		self.events.append(event)
		self.events.sort_custom(Event.gt)

	func advance():
		#pull first event
		var event: Event = self.events.pop_back()
		assert(event.start >= self.clock, "RuntimeError: Event %s starts in the past!" % event)

		#haul clocks up to match
		var old_clock = self.clock
		self.clock = event.start
		var delta = self.clock - old_clock
		self.day_clock += delta

		#advance conveyor offset
		if delta:
			self.conveyor.advance(delta)

		#resolve
		event.resolve()

	func setup():
		record("==================\nSimulation Start:\n==================")
		
		staging = Station.new(self,"staging",Vector2(100,100))
		var hang = null
		if not new_config:
			conveyor = Conveyor.new(self,"conveyor", Simulator.LAYOUT_OLD)
			hang = Equipment.new(self,"hang", Vector2(520,1050))
		else:
			conveyor = Conveyor.new(self,"conveyor", Simulator.LAYOUT_NEW)
			hang = Equipment.new(self,"hang", Vector2(650,850))

		hang.op_offset = Vector2(0,-18)
		# out = Station("finished storage", Vector2(625,600))
		var operation_two = Equipment.new(self,"operation_two", Vector2(625,610))
		operation_two.op_offset = Vector2(0,18)
		for i in range(5):
			var x = Equipment.new(self,"operation_one", Vector2(300,300 + i *68), 2)
			x.op_offset = Vector2(0,18)
		
		# operation_zero = Station("operation_zero", coords= Vector2(700,1050))
		# gopher = Station("gopher", coords= Vector2(815,660))

		var one = Worker.new(self,"operation_two")
		var two = Worker.new(self,"operation_one")
		var three = Worker.new(self,"hang")
		# four = Worker("gopher")

		record("Building queue...")
		dispatch_orders(10)

		open_day()
		proc(tick, {"duration" : clock_event_offset})

	func pull_data(file_name = "data//operation_one.txt"):
		if Simulator.PUBLIC_VERSION:
			pass
		else:
			var file = FileAccess.open(file_name, FileAccess.READ)
			var input = []
			
			while not file.eof_reached():
				var line = file.get_line()
				if line.length() > 0:
					input.append(line.split("\t"))
			file.close()
			
			if input.size() > 1:
				return input.slice(1)
			else:
				return []

	func build_job_list(data: Array, write_out = false, daily = true):
		var jl = {}
		for entry in data:
			var tag = ""
			if daily:
				tag = "%s @ %s" % [entry[3], entry[0]]
			else:
				tag = entry[3]
			if tag in jl:
				jl[tag][0] += float(entry[4])
			elif float(entry[4]) > 0:
				jl[tag] = [float(entry[4]),entry[9]]
		for key in jl:
			jl[key][0] = round(jl[key][0])
		#FIXME: restore logging
		# if write_out:
		# 	with open("job_list_%s.csv" % ("daily" if daily else "total"), "w") as fp:
		# 		writer = csv.writer(fp)
		# 		for key in jl:
		# 			writer.writerow([key, jl[key][0], jl[key][1]])
		var out = jl.values()
		out.sort()
		return out
	
	func build_model_directory(data):
		#non-public stuff removed
		return Widget.PART_TABLE

	func tick():
		#TODO: if tic procced
		if self.clock_event_offset:
			self.proc(self.tick, {"duration": self.clock_event_offset, "carryover": true})
		#TODO: divorce this
	
	func dispatch_orders(num : int = 0):
		var num_orders = num if num else Random.poisson_variate(self.daily_demand_rate*1.0/self.avg_order_size)
		var orders = []
		for x in range(num_orders):
			var order = self.generate_order()
			orders.append(order)
		open_orders.append_array(orders)
		record("New orders: %s" % str(orders) if orders else "No new orders.")
		record("%s open orders." % len(open_orders))
		stock_operation_zero(orders)
		return orders
	
	func reprioritize():
		open_orders.sort_custom(Order.lt)
		priority_list = []
		for order in open_orders:
			priority_list.append(order.kind)

	func generate_order():
		var quantity = Random.geometric_variate(1.0/avg_order_size)
		#TODO: Is this the right kind? or should it be p_n
		#FIXME: the AI just did this; does it work?
		var kind = Random.choice(self.model_directory.keys())
		var weights = []
		for model in model_directory:
			weights.append(self.model_directory[model]["frequency"])
		kind = Random.weighted_choice(self.model_directory.keys(), weights)
		#TODO: check this
		#FIXME: definitely not right
		var lead_time = 14 + round(Random.exponential_variate(1.0/31.0))		
		return Order.new(self,quantity,kind,lead_time)
	
	func stock_operation_zero(new_orders):
		#TODO: stock extras and handle them in one gets lost or something
		var operation_zero = self.get_stations("hang")[0]
		var count = 0
		var bin = null
		var widget = null
		for order in new_orders:
			bin = Bin.new(self.sim, order.kind)
			for x in range(order.capacity):
				widget = Widget.new(self, "operation_zero", order.p_n)
				widget.transfer_to(bin)
				count += 1
			bin.transfer_to(operation_zero)
		self.record("%s widgets stocked." % count)
	
	func fill_orders():
		var count = 0
		var widget_count = 0
		var operation_two_station = self.get_stations("operation_two")[0]
		for order in self.open_orders.duplicate():
			#TODO: finished storage?
			var matches = []
			for part in operation_two_station.contents:
				if part.p_n == order.p_n:
					matches.append(part)
			if len(matches) > order.capacity-len(order.contents):
				matches = matches.slice(0, order.capacity - order.contents.size())
			for part in matches:
				part.transfer_to(order)
				widget_count += 1
			if order.capacity == len(order.contents):
				self.record("%s complete!" % order)
				self.open_orders.erase(order)
				self.filled_orders.append(order)
				count += 1
		self.record("%s widgets transferred to open orders." % widget_count)
		self.record("%s %s filled today, %s total." % [count, "order" if count == 1 else "orders", len(self.open_orders)])

	func open_day():
		self.record("============\nDay %s Open:\n============" % self.day)
		self.closed = false
		self.day_clock = 0
		self.dispatch_orders()
		self.reprioritize()
		for agent in self.agents:
			agent.reprioritize()
			agent.proc(agent.unstage, {"override" : true})

	func close_day():
		self.break_end = 0
		for agent in self.agents:
			agent.intents.append("go home")
		#TODO: fix bug that happens if stations shutdown mid-operation
		self.proc(self.shutdown_stations, {
			"announce": true,
			"kind": "shutdown stations",
			"duration": 30
		})
		self.in_closing = true

	func shutdown_stations():
		for station in self.get_stations():
			station.proc(station.stage, {"kind": "power off station"})
	
	func go_to_tomorrow():
		#TODO: reset more stuff?
		self.record("==============\nDay %s Closed:\n==============" % self.day)
		self.fill_orders()
		for x in self.open_orders:
			x.days_remaining -= 1
		self.record("Open orders:")
		if not self.open_orders:
			self.record("null!")
		else:
			for x in self.open_orders:
				self.record("%s: %.2f%% filled" % [x, 100*len(x.contents)/x.capacity])
		for x in self.get_workers():
			self.record("%s: %s speed, %s events." % [x, x.speed, x.day_action_counts])
		for x in self.agents:
			if x is Conveyor:
				self.record("%s: %s hooks, %s widgets" % [x, len(x.contents), x.contents.reduce(func(acc, y): return acc + y.contents_of_kind(Widget).size(), 0)])
			else:
				self.record("%s: %s items, %s widgets" % [x, len(x.contents), len(x.contents_of_kind(Widget))])
			x.dump_statistics()
		self.in_closing = false
		self.closed = true
		self.day += 1
		self.attempting_shutdown = false
		# TODO make a shutdown method
		if self.day > self.end_day:
			self.operating = false
			self.record("=============================\nShutting down for day clock.\n=============================")
			if self.output:
				self.record(self.output)
				for x in self.output:
					self.record(x)
		elif self.clock > self.end_time:
			self.operating = false
			self.record("==============================\nShutting down for time clock.\n==============================")
			if self.output:
				self.record(self.output)
				for x in self.output:
					self.record(x)
		else:	
			self.proc(self.open_day, {
				"announce": true,
				"carryover": true
			})

	func call_break(duration = 30*60):
		for worker in self.get_workers():
			worker.intents.append("take break")
		self.break_end = self.day_clock + duration
		self.proc(self.return_from_break, {"duration": duration})
		self.on_break = true

	func return_from_break():
		self.on_break = false

	func one_loop():
		self.advance()

		#TODO: some kind of insurance against failing when transition was called irregularly
		if self.day_clock > 8*60*60 and not (self.in_closing or self.closed or self.attempting_shutdown):
			attempting_shutdown = true
			self.proc(self.close_day, {"announce": true})
		elif self.day_clock - self.break_end > 4*60*60 + 5*60 and not self.in_closing and not self.closed:
			self.proc(self.call_break, {"announce": true})
		elif self.in_closing and not self.active_agents:
			print("Entering close.")
			if self.events.filter(func(event): return not event.carryover).size() != 0:
				push_error("RuntimeError: Transition while events pending: %s" % self.events)
			self.proc(self.go_to_tomorrow)
		for x in self.get_workers():
			assert(x.active_events > 0 or (len(x.day_proc_list) == 0) or x.day_proc_list[-1].kind == "sleep", "RuntimeError: Strict agents without callback. sim count of dirty agents: %s/%s dirty agents: %s" % [self.active_agents, len(self.agents), str(self.agents.filter(func(agent): return agent.ready_to_act))])

	func get_stations(kind_p: String = "all") -> Array[Station]:
		var matching_stations: Array[Station] = []
		for agent in agents:
			if agent is Station and (agent.kind == kind_p or kind_p == "all"):
				matching_stations.append(agent)
		return matching_stations

	func get_workers(kind_p: String = "all") -> Array[Worker]:
		var matching_workers: Array[Worker] = []
		for agent in agents:
			if agent is Worker and (agent.kind == kind_p or kind_p == "all"):
				matching_workers.append(agent)
		return matching_workers
	
	func sanity_check():
		for widget in self.get_stations("hang")[0].contents_of_kind(Widget):
			assert(widget.kind != "operation_two")

	func build_production_plan():
		pass

func main():
	var runs = 1
	var new_config = false
	var days = 2
	var clock_offset = 100
	var hold_on_end = true
	var end_time = INF
	var total_runs = runs + runs * int(new_config)
	var simulators = []
	var abbreviate = false
	for i in range(total_runs):
		var sim = Simulator.new(int(new_config)*i*1.0/total_runs >= 0.5, days, clock_offset, end_time)
		var start_t = Time.get_ticks_msec()
		while sim.operating:
			sim.one_loop()

		var end_t = Time.get_ticks_msec()

		sim.record("done in %.4f seconds!\n" % ((end_t-start_t)/1000.0))
		
		sim.standby = true
		simulators.append(sim)
		var filename = "res://logs//log-%s-%s.txt"% [i, Time.get_unix_time_from_system()]
		var file = FileAccess.open(filename, FileAccess.WRITE_READ)
		if abbreviate:
			file.store_string('\n'.join(sim.records.slice(-100)))
		else:
			file.store_string('\n'.join(sim.records))
		file.close()
		
	print("All done.")

# george: hanger
# Connor: operation_one
# jacob: operation_twoer

# TODO: why is it jamming the conveyor with the hang priority

# Called when the node enters the scene tree for the first time.
func _ready():
	main()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
