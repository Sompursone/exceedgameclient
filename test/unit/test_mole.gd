extends GutTest


var game_logic : LocalGame
var image_loader : CardImageLoader
var default_deck = CardDefinitions.get_deck_from_str_id("mole")
const TestCardId1 = 50001
const TestCardId2 = 50002
const TestCardId3 = 50003
const TestCardId4 = 50004
const TestCardId5 = 50005

var player1 : Player
var player2 : Player

func default_game_setup():
	image_loader = CardImageLoader.new(true)
	game_logic = LocalGame.new(image_loader)
	var seed_value = randi()
	game_logic.initialize_game(default_deck, default_deck, "p1", "p2", Enums.PlayerId.PlayerId_Player, seed_value)
	game_logic.draw_starting_hands_and_begin()
	game_logic.do_mulligan(game_logic.player, [])
	game_logic.do_mulligan(game_logic.opponent, [])
	player1 = game_logic.player
	player2 = game_logic.opponent
	game_logic.get_latest_events()

func give_player_specific_card(player, def_id, card_id):
	var card_def = CardDefinitions.get_card(def_id)
	var card = GameCard.new(card_id, card_def, player.my_id)
	var card_db = game_logic.get_card_database()
	card_db._test_insert_card(card)
	player.hand.append(card)

func give_specific_cards(p1, id1, p2, id2):
	if p1:
		give_player_specific_card(p1, id1, TestCardId1)
	if p2:
		give_player_specific_card(p2, id2, TestCardId2)

func position_players(p1, loc1, p2, loc2):
	p1.arena_location = loc1
	p2.arena_location = loc2

func give_gauge(player, amount):
	for i in range(amount):
		player.add_to_gauge(player.deck[0])
		player.deck.remove_at(0)

func validate_has_event(events, event_type, target_player, number = null):
	for event in events:
		if event['event_type'] == event_type:
			if event['event_player'] == target_player.my_id:
				if number != null and event['number'] == number:
					return
				elif number == null:
					return
	fail_test("Event not found: %s" % event_type)

func before_each():
	default_game_setup()

	gut.p("ran setup", 2)

func after_each():
	game_logic.teardown()
	game_logic.free()
	gut.p("ran teardown", 2)

func before_all():
	gut.p("ran run setup", 2)

func after_all():
	gut.p("ran run teardown", 2)

func do_and_validate_strike(player, card_id, ex_card_id = -1):
	assert_true(game_logic.can_do_strike(player))
	assert_true(game_logic.do_strike(player, card_id, false, ex_card_id))
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_Strike_Started, player, card_id)
	if game_logic.game_state == Enums.GameState.GameState_Strike_Opponent_Response or game_logic.game_state == Enums.GameState.GameState_PlayerDecision:
		pass
	else:
		fail_test("Unexpected game state after strike")

func do_strike_response(player, card_id, ex_card = -1):
	assert_true(game_logic.do_strike(player, card_id, false, ex_card))
	var events = game_logic.get_latest_events()
	return events

func advance_turn(player):
	assert_true(game_logic.do_prepare(player))
	if player.hand.size() > 7:
		var cards = []
		var to_discard = player.hand.size() - 7
		for i in range(to_discard):
			cards.append(player.hand[i].id)
		assert_true(game_logic.do_discard_to_max(player, cards))

func validate_gauge(player, amount, id):
	assert_eq(len(player.gauge), amount)
	if len(player.gauge) != amount: return
	if amount == 0: return
	for card in player.gauge:
		if card.id == id:
			return
	fail_test("Didn't have required card in gauge.")

func validate_discard(player, amount, id):
	assert_eq(len(player.discards), amount)
	if len(player.discards) != amount: return
	if amount == 0: return
	for card in player.discards:
		if card.id == id:
			return
	fail_test("Didn't have required card in discard.")

func handle_simultaneous_effects(initiator, defender, simul_idx):
	while game_logic.game_state == Enums.GameState.GameState_PlayerDecision and game_logic.decision_info.type == Enums.DecisionType.DecisionType_ChooseSimultaneousEffect:
		var decider = initiator
		if game_logic.decision_info.player == defender.my_id:
			decider = defender
		assert_true(game_logic.do_choice(decider, simul_idx), "Failed simuleffect choice")

func execute_strike(initiator, defender, init_card : String, def_card : String, init_choices, def_choices, init_ex = false, def_ex = false,
		init_force_special = false, def_force_special = false, init_set_choice = 1, simul_idx = 0):
	var all_events = []
	give_specific_cards(initiator, init_card, defender, def_card)
	if init_ex:
		give_player_specific_card(initiator, init_card, TestCardId3)
		do_and_validate_strike(initiator, TestCardId1, TestCardId3)
	else:
		do_and_validate_strike(initiator, TestCardId1)

	if game_logic.game_state == Enums.GameState.GameState_PlayerDecision and game_logic.active_strike.strike_state == game_logic.StrikeState.StrikeState_Initiator_SetEffects:
		game_logic.do_choice(initiator, init_set_choice)

	if def_ex:
		give_player_specific_card(defender, def_card, TestCardId4)
		all_events += do_strike_response(defender, TestCardId2, TestCardId4)
	elif def_card:
		all_events += do_strike_response(defender, TestCardId2)

	# Pay any costs from hand/gauge
	if game_logic.active_strike and game_logic.active_strike.strike_state == game_logic.StrikeState.StrikeState_Initiator_PayCosts:
		if init_force_special:
			var cost = game_logic.active_strike.initiator_card.definition['force_cost']
			var cards = []
			for i in range(cost):
				cards.append(initiator.hand[i].id)
			game_logic.do_pay_strike_cost(initiator, cards, false)
		else:
			var cost = game_logic.active_strike.initiator_card.definition['gauge_cost']
			var cards = []
			for i in range(cost):
				cards.append(initiator.gauge[i].id)
			game_logic.do_pay_strike_cost(initiator, cards, false)

	# Pay any costs from hand/gauge
	if game_logic.active_strike and game_logic.active_strike.strike_state == game_logic.StrikeState.StrikeState_Defender_PayCosts:
		if def_force_special:
			var cost = game_logic.active_strike.defender_card.definition['force_cost']
			var cards = []
			for i in range(cost):
				cards.append(defender.hand[i].id)
			game_logic.do_pay_strike_cost(defender, cards, false)
		else:
			var cost = game_logic.active_strike.defender_card.definition['gauge_cost']
			var cards = []
			for i in range(cost):
				cards.append(defender.gauge[i].id)
			game_logic.do_pay_strike_cost(defender, cards, false)

	handle_simultaneous_effects(initiator, defender, simul_idx)

	for i in range(init_choices.size()):
		assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
		assert_true(game_logic.do_choice(initiator, init_choices[i]))
		handle_simultaneous_effects(initiator, defender, simul_idx)
	handle_simultaneous_effects(initiator, defender, simul_idx)

	for i in range(def_choices.size()):
		assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
		assert_true(game_logic.do_choice(defender, def_choices[i]))
		handle_simultaneous_effects(initiator, defender, simul_idx)

	var events = game_logic.get_latest_events()
	all_events += events
	return all_events

func validate_positions(p1, l1, p2, l2):
	assert_eq(p1.arena_location, l1)
	assert_eq(p2.arena_location, l2)

func validate_life(p1, l1, p2, l2):
	assert_eq(p1.life, l1)
	assert_eq(p2.life, l2)

##
## Tests start here
##

func test_mole_UA():
	position_players(player1, 4, player2, 8)
	player1.discard_hand()
	assert_true(game_logic.do_character_action(player1, []))
	# options are 1 and 7
	assert_true(game_logic.do_choice(player1, 1))
	assert_eq(player1.get_buddy_location(), 7)
	assert_eq(len(player1.hand), 2)
	advance_turn(player2)

	execute_strike(player1, player2, "standard_normal_grasp","standard_normal_dive", [3], [],
		false, false, false, false, 0)
	validate_positions(player1, 7, player2, 5)
	validate_life(player1, 30, player2, 27)
	advance_turn(player2)

func test_mole_exceed_UA():
	position_players(player1, 3, player2, 8)
	player1.exceed()
	player1.discard_hand()
	assert_true(game_logic.do_character_action(player1, []))
	# options are 1, 5, 6, 7
	assert_true(game_logic.do_choice(player1, 3))
	assert_eq(player1.get_buddy_location(), 7)
	assert_eq(len(player1.hand), 2)
	advance_turn(player2)

	execute_strike(player1, player2, "standard_normal_grasp","standard_normal_dive", [3], [],
		false, false, false, false, 0)
	validate_positions(player1, 7, player2, 5)
	validate_life(player1, 30, player2, 25)
	advance_turn(player2)

func test_mole_exceed_UA_advance_off():
	position_players(player1, 3, player2, 8)
	player1.exceed()
	player1.set_buddy_location("burrow", 5)

	execute_strike(player1, player2, "standard_normal_assault","standard_normal_dive", [], [],
		false, false, false, false, 0, 1)
	validate_positions(player1, 7, player2, 8)
	validate_life(player1, 30, player2, 24)
	advance_turn(player1)

func test_mole_exceed_UA_occupied():
	position_players(player1, 5, player2, 3)
	player1.exceed()
	player1.discard_hand()
	assert_true(game_logic.do_character_action(player1, []))
	# options are 1, 2, 3, 7, 8, 9
	assert_true(game_logic.do_choice(player1, 2))
	assert_eq(player1.get_buddy_location(), 3)
	assert_eq(len(player1.hand), 2)
	advance_turn(player2)

	execute_strike(player1, player2, "standard_normal_assault","standard_normal_sweep", [], [],
		false, false, false, false, 0)
	validate_positions(player1, 4, player2, 3)
	validate_life(player1, 24, player2, 26)
	advance_turn(player1)

func test_mole_lost_treasure():
	player1.discard_hand()
	give_player_specific_card(player1, "mole_burrowdig", TestCardId1)
	give_player_specific_card(player1, "mole_headbutt", TestCardId2)
	player1.discard([TestCardId2])

	assert_true(game_logic.do_boost(player1, TestCardId1, []))
	assert_true(game_logic.do_choose_from_discard(player1, [TestCardId2]))
	assert_true(player1.is_card_in_hand(TestCardId2))
	assert_eq(len(player1.hand), 1)
	advance_turn(player2)

func test_mole_tunneling_to_gauge():
	position_players(player1, 4, player2, 8)
	player1.set_buddy_location("burrow", 5)
	give_player_specific_card(player1, "mole_divingdig", TestCardId1)

	assert_true(game_logic.do_boost(player1, TestCardId1, []))
	assert_true(game_logic.do_choice(player1, 4))
	validate_positions(player1, 5, player2, 8)
	assert_true(player1.is_card_in_gauge(TestCardId1))
	advance_turn(player2)

func test_mole_tunneling_no_gauge():
	position_players(player1, 4, player2, 8)
	player1.set_buddy_location("burrow", 5)
	give_player_specific_card(player1, "mole_divingdig", TestCardId1)

	assert_true(game_logic.do_boost(player1, TestCardId1, []))
	assert_true(game_logic.do_choice(player1, 2))
	validate_positions(player1, 2, player2, 8)
	assert_true(player1.is_card_in_discards(TestCardId1))
	advance_turn(player2)

func test_mole_cave_in_prevents_advance():
	position_players(player1, 3, player2, 6)
	give_gauge(player1, 2)

	execute_strike(player1, player2, "mole_cavein", "standard_normal_assault", [], [], false, false)
	validate_positions(player1, 3, player2, 6)
	validate_life(player1, 30, player2, 26)
	advance_turn(player2)

func test_mole_cave_in_prevents_retreat():
	position_players(player1, 3, player2, 5)
	give_gauge(player1, 2)

	execute_strike(player1, player2, "mole_cavein", "standard_normal_cross", [], [], false, false)
	validate_positions(player1, 3, player2, 5)
	validate_life(player1, 30, player2, 26)
	advance_turn(player2)

func test_mole_cave_in_weaving():
	position_players(player1, 2, player2, 6)
	give_gauge(player2, 2)
	player1.set_buddy_location("burrow", 4)

	execute_strike(player1, player2, "standard_normal_cross", "mole_cavein", [], [], false, false,
		false, false, 0, 1)
	validate_positions(player1, 4, player2, 6)
	validate_life(player1, 26, player2, 30)
	advance_turn(player2)

func test_mole_cave_in_out_of_range():
	position_players(player1, 2, player2, 6)
	give_gauge(player1, 2)
	execute_strike(player1, player2, "mole_cavein", "standard_normal_dive", [], [], false, false)
	validate_positions(player1, 2, player2, 3)
	validate_life(player1, 28, player2, 30)
	advance_turn(player2)

func test_mole_cave_in_range_boost():
	position_players(player1, 2, player2, 6)
	give_gauge(player1, 2)

	give_player_specific_card(player1, "mole_erupt", TestCardId3)
	assert_true(game_logic.do_boost(player1, TestCardId3, [player1.hand[0].id]))
	advance_turn(player2)

	execute_strike(player1, player2, "mole_cavein", "standard_normal_dive", [], [], false, false)
	validate_positions(player1, 2, player2, 6)
	validate_life(player1, 30, player2, 26)
	advance_turn(player2)

func test_mole_undermine_move():
	position_players(player1, 2, player2, 6)
	give_gauge(player2, 2)
	player1.set_buddy_location("burrow", 4)

	give_player_specific_card(player1, "mole_cavein", TestCardId3)
	assert_true(game_logic.do_boost(player1, TestCardId3, []))
	advance_turn(player2)

	assert_true(game_logic.do_choice(player1, 1))
	assert_true(game_logic.do_choice(player1, 1))
	assert_eq(player1.get_buddy_location(), 5)
	advance_turn(player1)
	advance_turn(player2)

	assert_true(game_logic.do_choice(player1, 1))
	assert_true(game_logic.do_choice(player1, 1))
	assert_eq(player1.get_buddy_location(), 6)
	advance_turn(player1)
	advance_turn(player2)

	assert_true(game_logic.do_choice(player1, 1))
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.get_buddy_location(), 5)
	advance_turn(player1)

func test_mole_undermine_discard_on_opponent():
	position_players(player1, 2, player2, 6)
	give_gauge(player2, 2)
	player1.set_buddy_location("burrow", 6)

	give_player_specific_card(player1, "mole_cavein", TestCardId3)
	assert_true(game_logic.do_boost(player1, TestCardId3, []))
	advance_turn(player2)

	assert_true(game_logic.do_choice(player1, 0))
	assert_true(player1.is_card_in_discards(TestCardId3))
	validate_life(player1, 30, player2, 26)
	advance_turn(player1)

func test_mole_undermine_discard_nonlethal():
	position_players(player1, 2, player2, 6)
	player2.life = 3
	give_gauge(player2, 2)
	player1.set_buddy_location("burrow", 6)

	give_player_specific_card(player1, "mole_cavein", TestCardId3)
	assert_true(game_logic.do_boost(player1, TestCardId3, []))
	advance_turn(player2)

	assert_true(game_logic.do_choice(player1, 0))
	assert_true(player1.is_card_in_discards(TestCardId3))
	validate_life(player1, 30, player2, 1)
	advance_turn(player1)

func test_mole_undermine_discard_off_opponent():
	position_players(player1, 2, player2, 6)
	give_gauge(player2, 2)
	player1.set_buddy_location("burrow", 5)

	give_player_specific_card(player1, "mole_cavein", TestCardId3)
	assert_true(game_logic.do_boost(player1, TestCardId3, []))
	advance_turn(player2)

	assert_true(game_logic.do_choice(player1, 0))
	assert_true(player1.is_card_in_discards(TestCardId3))
	validate_life(player1, 30, player2, 30)
	advance_turn(player1)

func test_mole_molten_armor():
	position_players(player1, 2, player2, 4)

	give_player_specific_card(player1, "mole_erupt", TestCardId3)
	assert_true(game_logic.do_boost(player1, TestCardId3, [player1.hand[0].id]))
	advance_turn(player2)

	execute_strike(player1, player2, "standard_normal_sweep", "standard_normal_assault", [], [], false, false)
	validate_positions(player1, 2, player2, 3)
	validate_life(player1, 26, player2, 22)
	advance_turn(player2)

func test_mole_molten_nonlethal():
	position_players(player1, 2, player2, 5)
	player2.life = 2

	give_player_specific_card(player1, "mole_erupt", TestCardId3)
	assert_true(game_logic.do_boost(player1, TestCardId3, [player1.hand[0].id]))
	advance_turn(player2)

	execute_strike(player1, player2, "standard_normal_grasp", "standard_normal_assault", [], [], false, false)
	validate_positions(player1, 2, player2, 3)
	validate_life(player1, 26, player2, 1)
	advance_turn(player2)
