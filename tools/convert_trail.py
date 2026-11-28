"""Convert between trail CSV and mission JSON files."""
import argparse
import csv
import json
from pathlib import Path
import re


# Keep field mappings in sync with customskirmishtrails/missionjson.lua (toRow).
ADVANTAGE = ("human_large", "human_small", "neutral", "ai_small", "ai_large")
START_MODE = ("normal", "crusader", "deathmatch")
GROUPS = {"producible": "producible_", "recruitable": "recruitable_",
          "resources": "resource_", "tradeable": "tradeable_", "icon": "icon_"}
DIRECT = ("map_name", "mission_name", "mission_type", "difficulty_scaling", "scenario_briefing")
ENUMS = {"mission_type": ("skirmish", "scenario", "skirmish_scenario"),
         "difficulty_scaling": ("vanilla", "none")}
COLORS = ("orange", "yellow", "blue", "black", "purple", "lightblue", "green")
TEXT_COLUMNS = tuple(f"text_description_line_{line:02d}" for line in range(1, 9))
TRAILS = {"First": "First-Edition", "Warchest": "Warchest", "Extreme": "Extreme"}
SCHEMA = "https://github.com/gynt/ucp-extension-custom-skirmish-trails/resources/{}.schema.json"
# Canonical key order from customskirmishtrails/settings.lua (readAiMapping).
AI_KEYS = ("SK_RAT", "SK_SNAKE", "SK_PIG", "SK_WOLF", "SK_SALADIN", "SK_CALIPH", "SK_SULTAN", "SK_RICHARD",
           "SK_FREDERICK", "SK_PHILLIP", "SK_WAZIR", "SK_EMIR", "SK_NIZAR", "SK_SHERIFF", "SK_MARSHAL", "SK_ABBOT")


def player_columns(player):
    columns = {"name": f"player{player}_name", "start_position": f"start_position{player}",
               "team": f"team{player}", "aiv_type": f"aiv_type{player}", "gold": f"gold_player_{player}"}
    if player == 1:
        columns.update(lord="player1_lord", skip_start_units="player1_skip_start_units")
    else:
        columns.update(ai=f"player{player}", color=f"player{player}_color")
    return columns


def integer(text, minimum=0, maximum=None):
    if re.fullmatch(r"0|[1-9][0-9]*", text):
        value = int(text)
        if minimum <= value and (maximum is None or value <= maximum):
            return value
    return None


def unit_limit(text):
    # Values outside the unitlimits.lua grammar remain CSV text under extra.
    parts = text.split(" ")
    if len(parts) == 3 and parts[0] == "formula":
        base, offset = integer(parts[1], 1, 100000), integer(parts[2], 0, 100000)
        if base is not None and offset is not None:
            return {"formula": {"base": base, "offset": offset}}
    if parts[0] == "by_alive" and 2 <= len(parts) <= 9:
        points = {}
        for part in parts[1:]:
            lord_text, sep, limit_text = part.partition("=")
            lords = integer(lord_text, 1, 8)
            limit = integer(limit_text, 0, 100000)
            if not sep or lords is None or limit is None or lords in points:
                return None
            points[lords] = limit
        return {"by_alive": [{"lords": lords, "limit": limit} for lords, limit in points.items()]}
    return None


def mission_json(row):
    if not row.get("map_name"):
        raise ValueError("a mission needs a map_name")
    mission = {"$schema": SCHEMA.format("mission"), "format": 1}
    for column in DIRECT:
        if column in row and (column not in ENUMS or row[column] in ENUMS[column]):
            mission[column] = row[column]
    for key, column, names in (("advantage", "fairness", ADVANTAGE), ("start_mode", "start_levels", START_MODE)):
        value = integer(row.get(column, ""), 1, len(names))
        if value is not None:
            mission[key] = names[value - 1]
    limit = unit_limit(row.get("unit_limit", ""))
    if limit is not None:
        mission["unit_limit"] = limit
    lines = [row.get(column, "") for column in TEXT_COLUMNS]
    while lines and TEXT_COLUMNS[len(lines) - 1] not in row:
        lines.pop()
    if lines:
        mission["text_description"] = lines

    count = integer(row.get("num_players", ""), 1, 8) or 1
    players = []
    for player in range(1, count + 1):
        entry = {}
        for key, column in player_columns(player).items():
            value = row.get(column, "")
            if key == "ai":
                entry[key] = value or "0"
            elif key == "name" and column in row or key == "lord" and value in ("Arab", "Europ"):
                entry[key] = value
            elif key == "color":
                if value in COLORS:
                    entry[key] = value
                elif integer(value, 2, 8) is not None:
                    entry[key] = int(value)
            elif key not in ("lord", "name"):
                number = integer(value, maximum=1 if key == "skip_start_units" else None)
                if number is not None:
                    entry[key] = number
        players.append(entry)
    mission["players"] = players

    for group, prefix in GROUPS.items():
        values = {}
        for column, value in row.items():
            if column.startswith(prefix):
                key = column[len(prefix):]
                if group != "icon":
                    values[key] = value
                elif key in ("locked", "available", "won") and integer(value) is not None:
                    values[key] = int(value)
        if values:
            mission[group] = values

    represented = csv_row(mission, {})
    extra = {column: value for column, value in row.items() if represented.get(column) != value}
    if extra:
        mission["extra"] = extra
    return mission


def cell(value):
    if value is None or value == {} or value == []:
        return ""
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    if isinstance(value, (str, int, float)):
        return str(value)
    raise ValueError(f"expected a scalar CSV cell, got {value!r}")


def csv_row(mission, aliases):
    if not isinstance(mission, dict):
        raise ValueError("expected a mission object")
    map_name = mission.get("map_name")
    if (mission.get("format") is None and mission.get("players") is None
            and type(map_name) in (str, int, float)
            and all(mission.get(key) is not None for key in ("fairness", "start_levels", "num_players"))):
        row = {}
        for column, value in mission.items():
            if isinstance(value, (dict, list)):
                raise ValueError(f"flat mission column {column!r} must have a scalar value")
            if value is not None:
                text = cell(value)
                row[column] = aliases.get(text, text) if re.fullmatch(r"player[1-8]", column) else text
        return row
    if mission.get("format") != 1 or not mission.get("map_name"):
        raise ValueError("expected flat mission columns or a format-1 mission with a map_name")
    row = {key: cell(mission[key]) for key in DIRECT if key in mission}
    for key, column, names in (("advantage", "fairness", ADVANTAGE), ("start_mode", "start_levels", START_MODE)):
        if key in mission:
            value = cell(mission[key])
            row[column] = str(names.index(value.lower()) + 1) if value.lower() in names else value

    players = mission["players"]
    if not 1 <= len(players) <= 8:
        raise ValueError("a mission needs 1 to 8 players")
    row.update(num_players=str(len(players)), player1="0")
    for player, entry in enumerate(players, 1):
        for key, column in player_columns(player).items():
            if key in entry:
                value = cell(entry[key])
                row[column] = aliases.get(value, value or "0") if key == "ai" else value

    row.update((column, cell(value)) for column, value in zip(TEXT_COLUMNS, mission.get("text_description", [])))
    for group, prefix in GROUPS.items():
        row.update((prefix + key, cell(value)) for key, value in mission.get(group, {}).items())
    limit = mission.get("unit_limit")
    if limit is not None:
        if "formula" in limit:
            formula = limit["formula"]
            row["unit_limit"] = f"formula {formula['base']} {formula['offset']}"
        else:
            row["unit_limit"] = "by_alive " + " ".join(
                f"{point['lords']}={point['limit']}" for point in limit["by_alive"])
    row.update((column, cell(value)) for column, value in mission.get("extra", {}).items())
    return row


def condition_dependencies(condition):
    if "won" in condition:
        yield condition["won"]["mission"]
    for group in ("all", "any"):
        for entry in condition.get(group, []):
            yield from condition_dependencies(entry)


def route_files(route):
    # Keep row order in sync with customskirmishtrails/route.lua (needs and placeRows).
    main = {key for key, node in route.items() if node.get("kind") != "side"}
    deps = {key: set(node.get("requires", [])) | set(node.get("requires_any", []))
            | set(condition_dependencies(node.get("unlock", {}))) for key, node in route.items()}
    ends = [key for key, node in route.items() if node.get("end")]
    if not ends:
        ends = sorted(main - set().union(*deps.values()))
    if len(ends) != 1 or ends[0] not in main:
        raise ValueError("trail_route needs one main end node")
    end = ends[0]
    remaining = set(route) - {end}
    ordered = {}
    while remaining:
        ready = [key for key in remaining if deps[key] <= ordered.keys()]
        if not ready:
            raise ValueError("trail_route has a cycle or a missing dependency")
        key = min(ready, key=lambda key: (key not in main, key))
        ordered[key] = route[key]["file"]
        remaining.remove(key)
    if not deps[end] <= ordered.keys():
        raise ValueError("the end node has a missing dependency")
    return [*ordered.values(), route[end]["file"]]


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(path, data):
    with path.open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def csv_to_json(source, destination, trail_type, base_settings):
    with source.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.reader(handle, strict=True)
        header = next(reader, [])
        if not {"map_name", "num_players"} <= set(header) or len(set(header)) != len(header):
            raise ValueError("CSV needs unique column names including map_name and num_players")
        missions = [mission_json(dict(zip(header, row, strict=True))) for row in reader if row]
    settings = load_json(base_settings) if base_settings else {}
    if settings.get("trail_route"):
        raise ValueError("--settings needs positions from a trail without a route")
    trail_type = trail_type or settings.get("trail_type")
    if trail_type not in TRAILS:
        raise ValueError("choose --trail-type First, Warchest or Extreme")
    positions = settings.pop("trail_mission_positions", None)
    if positions is None:
        templates = Path(__file__).resolve().parents[1] / "resources" / "trails"
        positions = load_json(templates / f"template-{TRAILS[trail_type]}-Trail-settings.json")["trail_mission_positions"]
    if not 0 < len(missions) <= len(positions):
        raise ValueError(f"found {len(missions)} missions for {len(positions)} positions")

    base = destination.stem.removesuffix("-settings")
    folder = destination.with_name(base + "-missions")
    if destination.exists() or folder.exists():
        raise ValueError(f"output already exists: {destination} or {folder}")
    route = {}
    for index, position in enumerate(positions[:len(missions)], 1):
        key = f"mission{index:02d}"
        route[key] = {"file": f"{folder.name}/{key}.json", "position": position}
        if index > 1:
            route[key]["requires"] = [f"mission{index - 1:02d}"]
        if index == len(missions):
            route[key]["end"] = True
    settings.update({"$schema": SCHEMA.format("trail-settings"), "trail_type": trail_type,
                     "trail_missions": {"base_name": base, "data_mode": "json_folder"}, "trail_route": route})
    folder.mkdir()
    for node, mission in zip(route.values(), missions, strict=True):
        write_json(destination.parent / node["file"], mission)
    write_json(destination, settings)


def resolve_relative(directory, path):
    # Match settings.resolveRelative in customskirmishtrails/settings.lua, with the game as the working directory.
    path = path.replace("\\", "/")
    if re.match(r"^(?:[a-z]:/|/|ucp/)", path, re.IGNORECASE | re.ASCII):
        return Path(path)
    return Path(directory) / path


def json_to_csv(source, destination):
    settings = load_json(source)
    route = settings.get("trail_route", {})
    if any("file" in node for node in route.values()):
        files = [resolve_relative(source.parent, name) for name in route_files(route)]
    else:
        # Match customskirmishtrails/conversion.lua (listMissionFiles) and sync.lua.
        name = re.sub(r"\.csv\Z", "", settings["trail_missions"]["base_name"], flags=re.IGNORECASE)
        folder = resolve_relative(source.parent, name)
        pattern = re.compile(rf"{re.escape(folder.name)}_mission_([0-9]+)\.json", re.IGNORECASE | re.ASCII)
        numbered = []
        for path in folder.iterdir():
            match = pattern.fullmatch(path.name)
            if match and path.is_file():
                numbered.append((int(match[1]), path))
        files = []
        for index, (number, path) in enumerate(sorted(numbered), 1):
            if number != index:
                raise ValueError(f"expected mission file {index} in {folder}")
            files.append(path)
    aliases = {}
    mapping = settings.get("ai_character_mapping")
    if isinstance(mapping, dict):
        for key in AI_KEYS:
            alias = mapping.get(key)
            if isinstance(alias, str) and alias and alias not in aliases and (alias == key or alias not in AI_KEYS):
                aliases[alias] = key
    rows = []
    for path in files:
        try:
            rows.append(csv_row(load_json(path), aliases))
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError(f"{path}: {error}") from error
    if not rows:
        raise ValueError("no mission files")
    columns = dict.fromkeys(column for row in rows for column in row)
    if "" in columns:
        del columns[""]
        columns[""] = None
    # Match the required numeric cells and scenario exception in customskirmishtrails/io.lua.
    # Its CSV reader trims names and values (vendor/lua-csv.lua, trim_space), and a later column wins.
    whitespace = " \t\n\r\v\f"
    for index, (path, row) in enumerate(zip(files, rows, strict=True), 1):
        cells = {column.strip(whitespace): row.get(column, "").strip(whitespace) for column in columns}
        scenario = cells.get("mission_type", "").lower() in ("scenario", "skirmish_scenario")
        for column, value in cells.items():
            required = re.fullmatch(r"num_players|fairness|start_levels|(?:start_position|team|aiv_type)[1-8]", column)
            if required and (column == "num_players" or not scenario) and not value:
                raise ValueError(f"{path}: mission {index} has an empty CSV cell in {column!r}")
    with destination.open("x", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, columns)
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--trail-type", choices=TRAILS, help="trail edition for CSV to JSON")
    parser.add_argument("--settings", type=Path, help="existing JSON settings to keep when converting a CSV")
    args = parser.parse_args()
    formats = args.source.suffix.lower(), args.destination.suffix.lower()
    try:
        if formats == (".csv", ".json"):
            csv_to_json(args.source, args.destination, args.trail_type, args.settings)
        elif formats == (".json", ".csv") and not (args.trail_type or args.settings):
            json_to_csv(args.source, args.destination)
        else:
            parser.error("choose a .csv source and .json destination, or the reverse")
    except (OSError, csv.Error, KeyError, TypeError, ValueError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
