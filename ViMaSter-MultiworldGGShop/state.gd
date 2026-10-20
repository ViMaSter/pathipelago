extends RefCounted

const FIRST_LOCATION := 402938001
const COINS_ITEM := 402939001
const DNA_ITEM := 402939002
const PLASMID_FRAGMENTS_ITEM := 402939003
const GRANT_ITEM := COINS_ITEM
const UNLOCK_ITEM_BASE := 402960000
const UNLOCK_LOCATION_BASE := 402970000
var path := ""
var identity := ""
var count := 0
var checks: Array = []
var confirmed: Array = []
var received: Array = []
var unlock_ids: Array = []
var earned: Array = []
var confirmed_unlocks: Array = []
var natural_ids: Array = []
var natural: Array = []
var victories: Array = []
var bank := 0
var dna_bank := 0
var plasmid_fragment_bank := 0
var error := ""

static func integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

# ids are item/location pseudo IDs; plasmids are catalogue IDs that may be bought per character.
func open(file_path: String, campaign_identity: String, location_count: int, ids: Array = [],
		plasmids: Array = []) -> bool:
	path = file_path
	identity = campaign_identity
	count = location_count
	unlock_ids = ids.map(func(value): return int(value))
	natural_ids = plasmids.map(func(value): return int(value))
	natural.clear()
	if not FileAccess.file_exists(path):
		return _save()
	var parser := JSON.new()
	var text := FileAccess.get_file_as_string(path)
	if FileAccess.get_open_error() != OK or parser.parse(text) != OK:
		error = "Cannot read campaign journal; it has not been reset."
		return false
	var data: Variant = parser.data
	var dna_bank_value: Variant = data.get("dna_bank", 0) if data is Dictionary else null
	var plasmid_fragment_bank_value: Variant = data.get("plasmid_fragment_bank", 0) if data is Dictionary else null
	if not data is Dictionary or data.get("schema") != 1 or data.get("identity") != identity \
			or data.get("count") != count or not _locations(data.get("checks")) \
			or not _locations(data.get("confirmed")) or not data.get("received") is Array \
			or not integer(data.get("bank")) or int(data.bank) < 0 \
			or not integer(dna_bank_value) or int(dna_bank_value) < 0 \
			or not integer(plasmid_fragment_bank_value) or int(plasmid_fragment_bank_value) < 0:
		error = "Invalid or incompatible campaign journal; it has not been reset."
		return false
	for id in data.confirmed:
		if not id in data.checks:
			error = "Confirmed location missing from campaign journal."
			return false
	for item in data.received:
		if not _valid_item(item):
			error = "Unknown item in campaign journal."
			return false
	var coin_items: int = data.received.filter(func(item): return int(item) == COINS_ITEM).size()
	var dna_items: int = data.received.filter(func(item): return int(item) == DNA_ITEM).size()
	var fragment_items: int = data.received.filter(func(item): return int(item) == PLASMID_FRAGMENTS_ITEM).size()
	if int(data.bank) > coin_items or int(dna_bank_value) > dna_items \
			or int(plasmid_fragment_bank_value) > fragment_items:
		error = "Invalid currency balance in campaign journal."
		return false
	checks = data.checks.map(func(value: Variant) -> int: return int(value))
	confirmed = data.confirmed.map(func(value: Variant) -> int: return int(value))
	received = data.received.map(func(value: Variant) -> int: return int(value))
	if not _unlock_locations(data.get("earned", [])) or not _unlock_locations(data.get("confirmed_unlocks", [])):
		error = "Invalid natural unlock journal; it has not been reset."
		return false
	earned = data.get("earned", []).map(func(value: Variant) -> int: return int(value))
	confirmed_unlocks = data.get("confirmed_unlocks", []).map(func(value: Variant) -> int: return int(value))
	for location in confirmed_unlocks:
		if not location in earned:
			error = "Confirmed natural unlock missing from journal."
			return false
	var saved_natural: Variant = data.get("natural_plasmids", [])
	var seen_natural := {}
	if not saved_natural is Array:
		error = "Invalid natural Plasmid journal; it has not been reset."
		return false
	for id in saved_natural:
		if not integer(id) or not int(id) in natural_ids or seen_natural.has(int(id)):
			error = "Invalid natural Plasmid journal; it has not been reset."
			return false
		seen_natural[int(id)] = true
	natural = saved_natural.map(func(value: Variant) -> int: return int(value))
	var saved_victories: Variant = data.get("victories", [])
	if not saved_victories is Array:
		error = "Invalid victory history in campaign journal."
		return false
	var seen_victories := {}
	for run_id in saved_victories:
		if not run_id is String or run_id.is_empty() or seen_victories.has(run_id):
			error = "Invalid victory history in campaign journal."
			return false
		seen_victories[run_id] = true
	victories = saved_victories.duplicate()
	bank = int(data.bank)
	dna_bank = int(dna_bank_value)
	plasmid_fragment_bank = int(plasmid_fragment_bank_value)
	return true

func _valid_item(item: Variant) -> bool:
	return integer(item) and (int(item) in [COINS_ITEM, DNA_ITEM, PLASMID_FRAGMENTS_ITEM]
			or int(item) - UNLOCK_ITEM_BASE in unlock_ids)

func _unlock_locations(locations: Variant) -> bool:
	if not locations is Array:
		return false
	var seen := {}
	for location in locations:
		if not integer(location) or not int(location) - UNLOCK_LOCATION_BASE in unlock_ids or seen.has(int(location)):
			return false
		seen[int(location)] = true
	return true

func earn(id: int) -> bool:
	var location := UNLOCK_LOCATION_BASE + id
	if not id in unlock_ids:
		error = "Attempted to earn an unlock absent from this slot."
		return false
	if location in earned:
		return true
	earned.append(location)
	if not _save():
		earned.pop_back()
		return false
	return true

func earn_plasmid(id: int) -> bool:
	if not id in natural_ids:
		error = "Attempted to earn a Plasmid absent from this slot."
		return false
	if id in natural:
		return true
	natural.append(id)
	if not _save():
		natural.pop_back()
		return false
	return true

func _locations(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen := {}
	for id in value:
		if not integer(id) or int(id) < FIRST_LOCATION or int(id) >= FIRST_LOCATION + count or seen.has(int(id)):
			return false
		seen[int(id)] = true
	return true

func next_location() -> int:
	for i in count:
		if not FIRST_LOCATION + i in checks:
			return FIRST_LOCATION + i
	return -1

func record_victory(run_id: String) -> bool:
	if run_id.is_empty():
		error = "Cannot record a victory without a run identity."
		return false
	if run_id in victories:
		return true
	victories.append(run_id)
	if not _save():
		victories.pop_back()
		return false
	return true

func goal_reached(required_victories: int) -> bool:
	return confirmed.size() == count and victories.size() >= required_victories

func purchase(location: int) -> bool:
	if location != next_location() or location < 0:
		error = "Attempted duplicate or out-of-order MultiworldGG purchase."
		return false
	checks.append(location)
	if not _save():
		checks.pop_back()
		return false
	return true

func accept_checks(ids: Array) -> bool:
	for id in ids:
		if not integer(id):
			error = "Server sent a non-integer location ID."
			return false
	var previous_checks := checks.duplicate()
	var previous_confirmed := confirmed.duplicate()
	var previous_earned := earned.duplicate()
	var previous_unlocks := confirmed_unlocks.duplicate()
	for id in ids:
		if int(id) - UNLOCK_LOCATION_BASE in unlock_ids:
			if not int(id) in earned:
				earned.append(int(id))
			if not int(id) in confirmed_unlocks:
				confirmed_unlocks.append(int(id))
			continue
		if int(id) < FIRST_LOCATION or int(id) >= FIRST_LOCATION + count:
			continue
		if not int(id) in checks:
			checks.append(int(id))
		if not int(id) in confirmed:
			confirmed.append(int(id))
	if checks == previous_checks and confirmed == previous_confirmed and earned == previous_earned \
			and confirmed_unlocks == previous_unlocks:
		return true
	if not _save():
		checks = previous_checks
		confirmed = previous_confirmed
		earned = previous_earned
		confirmed_unlocks = previous_unlocks
		return false
	return true

func accept_items(items: Array) -> bool:
	if items.size() < received.size():
		error = "Server received-item history is shorter than the persisted history."
		return false
	for i in items.size():
		if not items[i] is Dictionary or not _valid_item(items[i].get("item")):
			error = "Unsupported item for this APWorld."
			return false
		if i < received.size() and int(items[i].item) != int(received[i]):
			error = "Server received-item history differs from the journal."
			return false
	var added := items.size() - received.size()
	if added == 0:
		return true
	var previous_banks := [bank, dna_bank, plasmid_fragment_bank]
	for i in range(received.size(), items.size()):
		var id := int(items[i].item)
		received.append(id)
		if id == COINS_ITEM:
			bank += 1
		elif id == DNA_ITEM:
			dna_bank += 1
		elif id == PLASMID_FRAGMENTS_ITEM:
			plasmid_fragment_bank += 1
	if not _save():
		received.resize(received.size() - added)
		bank = previous_banks[0]
		dna_bank = previous_banks[1]
		plasmid_fragment_bank = previous_banks[2]
		return false
	return true

func redeem() -> bool:
	var previous_banks := [bank, dna_bank, plasmid_fragment_bank]
	bank = 0
	dna_bank = 0
	plasmid_fragment_bank = 0
	if not _save():
		bank = previous_banks[0]
		dna_bank = previous_banks[1]
		plasmid_fragment_bank = previous_banks[2]
		return false
	return true

func _save() -> bool:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		error = "Cannot open campaign journal: " + error_string(FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify({
		"schema": 1, "identity": identity, "count": count, "checks": checks,
		"confirmed": confirmed, "received": received, "bank": bank,
		"dna_bank": dna_bank, "plasmid_fragment_bank": plasmid_fragment_bank,
		"earned": earned, "confirmed_unlocks": confirmed_unlocks, "victories": victories,
		"natural_plasmids": natural
	}))
	file.flush()
	var err := file.get_error()
	file.close()
	if err != OK:
		error = "Cannot write campaign journal: " + error_string(err)
		return false
	err = DirAccess.rename_absolute(temporary, path)
	if err != OK:
		error = "Cannot replace campaign journal: " + error_string(err)
		return false
	return true
