extends RefCounted

const FIRST_LOCATION := 402938001
const GRANT_ITEM := 402939001
var path := ""
var identity := ""
var count := 0
var checks: Array = []
var confirmed: Array = []
var received: Array = []
var bank := 0
var error := ""

static func integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

func open(file_path: String, campaign_identity: String, location_count: int) -> bool:
	path = file_path
	identity = campaign_identity
	count = location_count
	if not FileAccess.file_exists(path):
		return _save()
	var parser := JSON.new()
	var text := FileAccess.get_file_as_string(path)
	if FileAccess.get_open_error() != OK or parser.parse(text) != OK:
		error = "Cannot read campaign journal; it has not been reset."
		return false
	var data: Variant = parser.data
	if not data is Dictionary or data.get("schema") != 1 or data.get("identity") != identity \
			or data.get("count") != count or not _locations(data.get("checks")) \
			or not _locations(data.get("confirmed")) or not data.get("received") is Array \
			or not integer(data.get("bank")) or int(data.bank) < 0:
		error = "Invalid or incompatible campaign journal; it has not been reset."
		return false
	for id in data.confirmed:
		if not id in data.checks:
			error = "Confirmed location missing from campaign journal."
			return false
	for item in data.received:
		if not integer(item) or int(item) != GRANT_ITEM:
			error = "Unknown item in campaign journal."
			return false
	if int(data.bank) > data.received.size():
		error = "Invalid grant balance in campaign journal."
		return false
	checks = data.checks.map(func(value: Variant) -> int: return int(value))
	confirmed = data.confirmed.map(func(value: Variant) -> int: return int(value))
	received = data.received.map(func(value: Variant) -> int: return int(value))
	bank = int(data.bank)
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

func purchase(location: int) -> bool:
	if location != next_location() or location < 0:
		error = "Attempted duplicate or out-of-order AP purchase."
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
	for id in ids:
		if int(id) < FIRST_LOCATION or int(id) >= FIRST_LOCATION + count:
			continue
		if not int(id) in checks:
			checks.append(int(id))
		if not int(id) in confirmed:
			confirmed.append(int(id))
	if checks == previous_checks and confirmed == previous_confirmed:
		return true
	if not _save():
		checks = previous_checks
		confirmed = previous_confirmed
		return false
	return true

func accept_items(items: Array) -> bool:
	if items.size() < received.size():
		error = "Server received-item history is shorter than the persisted history."
		return false
	for i in items.size():
		if not items[i] is Dictionary or not integer(items[i].get("item")) or int(items[i].item) != GRANT_ITEM:
			error = "Unsupported item for this APWorld."
			return false
		if i < received.size() and int(items[i].item) != int(received[i]):
			error = "Server received-item history differs from the journal."
			return false
	var added := items.size() - received.size()
	if added == 0:
		return true
	for i in added:
		received.append(GRANT_ITEM)
	bank += added
	if not _save():
		received.resize(received.size() - added)
		bank -= added
		return false
	return true

func redeem() -> bool:
	var previous := bank
	bank = 0
	if not _save():
		bank = previous
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
		"confirmed": confirmed, "received": received, "bank": bank
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
