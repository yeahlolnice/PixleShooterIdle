class_name SaveService
extends RefCounted
## Reads and writes the GameState save file. All file IO goes through a
## SteamService-like backend (save_file/load_file/file_exists/delete_file), so
## Steam Cloud can replace the user:// stub later without touching this class.
##
## The backend's save_file must be atomic (the stub writes a temp file and
## renames it), so a crash mid-write leaves the previous save intact.
##
## Usage:
##   var saves := SaveService.new(SteamService)
##   saves.save(GameState)
##   match saves.load_into(GameState): ...

enum LoadResult { LOADED, MISSING, CORRUPT }

const DEFAULT_FILE := "save.json"
## Corrupt saves are copied here (suffix added before .json) before starting fresh.
const CORRUPT_SUFFIX := ".corrupt"

## Anything with save_file(name, text), load_file(name), file_exists(name), delete_file(name).
var backend: Object
var file_name: String


func _init(storage: Object, save_file_name: String = DEFAULT_FILE) -> void:
	backend = storage
	file_name = save_file_name


## Writes state.to_dict() as JSON. Returns false (and logs) on failure.
func save(state: Object) -> bool:
	var text := JSON.stringify(state.to_dict(), "\t", true, true)
	var ok: bool = backend.save_file(file_name, text)
	if not ok:
		push_error("[SaveService] could not write %s" % file_name)
	return ok


## Replaces state from the save file. On a missing file the state is left
## untouched. On a corrupt file the bad text is backed up, the original is
## removed, a warning is logged and the state is left untouched, so the caller
## keeps its fresh new-game state.
func load_into(state: Object) -> LoadResult:
	if not backend.file_exists(file_name):
		return LoadResult.MISSING
	var text: String = backend.load_file(file_name)
	var data: Variant = parse(text)
	if data == null:
		var backup := backup_name()
		backend.save_file(backup, text)
		backend.delete_file(file_name)
		push_warning("[SaveService] %s is corrupt; backed up to %s and starting fresh" % [file_name, backup])
		return LoadResult.CORRUPT
	state.from_dict(data)
	return LoadResult.LOADED


## Parsed save dictionary, or null if the text is not a JSON object.
static func parse(text: String) -> Variant:
	if text.strip_edges() == "":
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	if typeof(json.data) != TYPE_DICTIONARY:
		return null
	return json.data


## "save.corrupt.json"; overwritten by the next corrupt save (only the latest is kept).
func backup_name() -> String:
	return file_name.get_basename() + CORRUPT_SUFFIX + "." + file_name.get_extension()
