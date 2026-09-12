"""Valheim 1.0 character (.fch) reader and writer.

The 1.0 world-save redesign does not change the character container used by
the game.  Character data is still stored in an outer package with a
SHA-512 digest and a nested Player.Save payload.  This module deliberately
keeps map blobs, custom item data and unknown statistics in memory so saving
an edited character does not discard data that the editor does not expose.
"""

from __future__ import annotations

import hashlib
import io
import struct
from pathlib import Path
from typing import Any, Iterable


CURRENT_PROFILE_VERSION = 46
CURRENT_PLAYER_VERSION = 33
CURRENT_INVENTORY_VERSION = 109
CURRENT_SKILL_VERSION = 2
MAX_COLLECTION = 1_000_000
MAX_STRING_BYTES = 16 * 1024 * 1024
MAX_BYTE_ARRAY = 512 * 1024 * 1024


class SaveFormatError(ValueError):
    """Raised when a file is not a supported Valheim character save."""


class BinaryReader:
    def __init__(self, data: bytes):
        self.stream = io.BytesIO(data)

    @property
    def position(self) -> int:
        return self.stream.tell()

    @property
    def remaining(self) -> int:
        current = self.stream.tell()
        self.stream.seek(0, io.SEEK_END)
        end = self.stream.tell()
        self.stream.seek(current)
        return end - current

    def read_bytes(self, length: int) -> bytes:
        if length < 0 or length > MAX_BYTE_ARRAY:
            raise SaveFormatError(f"Invalid block size: {length}")
        data = self.stream.read(length)
        if len(data) != length:
            raise SaveFormatError(
                f"Unexpected end of file at position {self.position}: "
                f"expected {length} bytes, received {len(data)}"
            )
        return data

    def read_byte(self) -> int:
        return self.read_bytes(1)[0]

    def read_bool(self) -> bool:
        return self.read_byte() != 0

    def read_ushort(self) -> int:
        return struct.unpack("<H", self.read_bytes(2))[0]

    def read_int32(self) -> int:
        return struct.unpack("<i", self.read_bytes(4))[0]

    def read_long(self) -> int:
        return struct.unpack("<q", self.read_bytes(8))[0]

    def read_float(self) -> float:
        return struct.unpack("<f", self.read_bytes(4))[0]

    def read_vector3(self) -> list[float]:
        return list(struct.unpack("<fff", self.read_bytes(12)))

    def read_7bit_int(self) -> int:
        value = 0
        shift = 0
        for _ in range(5):
            byte = self.read_byte()
            value |= (byte & 0x7F) << shift
            if (byte & 0x80) == 0:
                return value
            shift += 7
        raise SaveFormatError("Invalid 7-bit string length")

    def read_string(self) -> str:
        length = self.read_7bit_int()
        if length > MAX_STRING_BYTES:
            raise SaveFormatError(f"String is too large: {length} bytes")
        if length == 0:
            return ""
        return self.read_bytes(length).decode("utf-8", errors="replace")

    def read_byte_array(self) -> bytes:
        length = self.read_int32()
        return self.read_bytes(length)

    def read_num_items(self) -> int:
        """Read Valheim/ZPackage's compact count used by custom item data."""
        first = self.read_byte()
        if (first & 0x80) == 0:
            return first
        return ((first & 0x7F) << 8) | self.read_byte()


class BinaryWriter:
    def __init__(self):
        self.stream = io.BytesIO()

    def get_bytes(self) -> bytes:
        return self.stream.getvalue()

    def write_bytes(self, value: bytes) -> None:
        self.stream.write(value)

    def write_byte(self, value: int) -> None:
        self.stream.write(struct.pack("<B", value & 0xFF))

    def write_bool(self, value: bool) -> None:
        self.write_byte(1 if value else 0)

    def write_ushort(self, value: int) -> None:
        self.stream.write(struct.pack("<H", value & 0xFFFF))

    def write_int32(self, value: int) -> None:
        self.stream.write(struct.pack("<i", int(value)))

    def write_long(self, value: int) -> None:
        self.stream.write(struct.pack("<q", int(value)))

    def write_float(self, value: float) -> None:
        self.stream.write(struct.pack("<f", float(value)))

    def write_vector3(self, value: Iterable[float]) -> None:
        x, y, z = value
        self.stream.write(struct.pack("<fff", float(x), float(y), float(z)))

    def write_7bit_int(self, value: int) -> None:
        if value < 0:
            raise ValueError("Negative length")
        while value >= 0x80:
            self.write_byte((value & 0x7F) | 0x80)
            value >>= 7
        self.write_byte(value)

    def write_string(self, value: str) -> None:
        encoded = str(value).encode("utf-8")
        self.write_7bit_int(len(encoded))
        self.write_bytes(encoded)

    def write_byte_array(self, value: bytes) -> None:
        self.write_int32(len(value))
        self.write_bytes(value)

    def write_num_items(self, value: int) -> None:
        if value < 0 or value > 0x7FFF:
            raise ValueError(f"Invalid compact quantity: {value}")
        if value < 128:
            self.write_byte(value)
        else:
            self.write_byte((value >> 8) | 0x80)
            self.write_byte(value & 0xFF)


def _check_count(count: int, label: str) -> int:
    if count < 0 or count > MAX_COLLECTION:
        raise SaveFormatError(f"Invalid count in {label}: {count}")
    return count


def _read_float_dict(reader: BinaryReader, label: str) -> dict[str, float]:
    result: dict[str, float] = {}
    for _ in range(_check_count(reader.read_int32(), label)):
        key = reader.read_string()
        result[key] = reader.read_float()
    return result


def _write_float_dict(writer: BinaryWriter, values: dict[str, float]) -> None:
    writer.write_int32(len(values))
    for key, value in values.items():
        writer.write_string(key)
        writer.write_float(value)


def _read_int_dict(reader: BinaryReader, label: str) -> dict[str, int]:
    result: dict[str, int] = {}
    for _ in range(_check_count(reader.read_int32(), label)):
        key = reader.read_string()
        result[key] = reader.read_int32()
    return result


def _write_int_dict(writer: BinaryWriter, values: dict[str, int]) -> None:
    writer.write_int32(len(values))
    for key, value in values.items():
        writer.write_string(key)
        writer.write_int32(value)


def _read_string_dict(reader: BinaryReader, label: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for _ in range(_check_count(reader.read_int32(), label)):
        key = reader.read_string()
        result[key] = reader.read_string()
    return result


def _write_string_dict(writer: BinaryWriter, values: dict[str, str]) -> None:
    writer.write_int32(len(values))
    for key, value in values.items():
        writer.write_string(key)
        writer.write_string(value)


def _read_string_list(reader: BinaryReader, label: str) -> list[str]:
    return [
        reader.read_string()
        for _ in range(_check_count(reader.read_int32(), label))
    ]


def _write_string_list(writer: BinaryWriter, values: list[str]) -> None:
    writer.write_int32(len(values))
    for value in values:
        writer.write_string(value)


def _read_profile(reader: BinaryReader, stat_count: int) -> dict[str, Any]:
    profile: dict[str, Any] = {
        "stats": [reader.read_float() for _ in range(stat_count)],
        "known_worlds": _read_float_dict(reader, "known_worlds"),
        "known_world_keys": _read_float_dict(reader, "known_world_keys"),
        "known_commands": _read_float_dict(reader, "known_commands"),
    }
    enemy_count = _check_count(reader.read_int32(), "enemy_stats")
    profile["enemy_stats"] = [
        _read_float_dict(reader, "enemy_stat_group")
        for _ in range(enemy_count)
    ]
    profile["item_pickup_stats"] = _read_float_dict(reader, "item_pickup_stats")
    profile["item_craft_stats"] = _read_float_dict(reader, "item_craft_stats")
    profile["pickable_stats"] = _read_float_dict(reader, "pickable_stats")
    profile["food_eaten_stats"] = _read_float_dict(reader, "food_eaten_stats")
    profile["pieces_placed_stats"] = _read_float_dict(reader, "pieces_placed_stats")
    return profile


def _write_profile(writer: BinaryWriter, profile: dict[str, Any], stat_count: int) -> None:
    stats = list(profile.get("stats", []))
    if len(stats) != stat_count:
        raise SaveFormatError(
            f"Profile has {len(stats)} statistics; expected {stat_count}"
        )
    for value in stats:
        writer.write_float(value)
    _write_float_dict(writer, profile.get("known_worlds", {}))
    _write_float_dict(writer, profile.get("known_world_keys", {}))
    _write_float_dict(writer, profile.get("known_commands", {}))
    enemy_stats = profile.get("enemy_stats", [])
    writer.write_int32(len(enemy_stats))
    for values in enemy_stats:
        _write_float_dict(writer, values)
    _write_float_dict(writer, profile.get("item_pickup_stats", {}))
    _write_float_dict(writer, profile.get("item_craft_stats", {}))
    _write_float_dict(writer, profile.get("pickable_stats", {}))
    _write_float_dict(writer, profile.get("food_eaten_stats", {}))
    _write_float_dict(writer, profile.get("pieces_placed_stats", {}))


def _read_item(reader: BinaryReader) -> dict[str, Any]:
    durability_raw = reader.read_int32()
    item: dict[str, Any] = {
        "durability": durability_raw * 0.01,
        "grid_x": reader.read_byte(),
        "grid_y": reader.read_byte(),
        "world_level": reader.read_byte(),
    }
    flags = reader.read_byte()
    item["_flags"] = flags
    item["picked_up"] = bool(flags & 1)
    item["equipped"] = bool(flags & 2)
    item["quality"] = reader.read_ushort() if flags & 4 else 1
    item["stack"] = reader.read_ushort() if flags & 8 else 1
    item["variant"] = reader.read_int32() if flags & 16 else 0
    if flags & 32:
        item["crafter_id"] = reader.read_long()
        item["crafter_name"] = reader.read_string()
    else:
        item["crafter_id"] = 0
        item["crafter_name"] = ""
    item["prefab_hash"] = reader.read_int32() if flags & 64 else 0
    custom_count = reader.read_num_items() if flags & 128 else 0
    item["custom_data"] = {
        reader.read_string(): reader.read_string()
        for _ in range(_check_count(custom_count, "item custom_data"))
    }
    item["_cheated_flags"] = reader.read_byte()
    item["cheated"] = bool(item["_cheated_flags"] & 1)
    return item


def _write_item(writer: BinaryWriter, item: dict[str, Any]) -> None:
    durability = float(item.get("durability", 100.0))
    writer.write_int32(round(durability * 100.0))
    writer.write_byte(item.get("grid_x", 0))
    writer.write_byte(item.get("grid_y", 0))
    writer.write_byte(item.get("world_level", 0))

    flags = int(item.get("_flags", 0)) & 0xFF
    if item.get("picked_up", False):
        flags |= 1
    else:
        flags &= ~1
    if item.get("equipped", False):
        flags |= 2
    else:
        flags &= ~2

    optional = (
        (4, "quality", 1),
        (8, "stack", 1),
        (16, "variant", 0),
    )
    for bit, key, default in optional:
        if item.get(key, default) != default or (flags & bit):
            flags |= bit
        else:
            flags &= ~bit

    crafter_present = bool(
        item.get("crafter_id", 0)
        or item.get("crafter_name", "")
        or (flags & 32)
    )
    if crafter_present:
        flags |= 32
    else:
        flags &= ~32

    prefab_hash = int(item.get("prefab_hash", 0))
    if prefab_hash or (flags & 64):
        flags |= 64
    else:
        flags &= ~64

    custom_data = item.get("custom_data", {}) or {}
    if custom_data or (flags & 128):
        flags |= 128
    else:
        flags &= ~128

    writer.write_byte(flags)
    if flags & 4:
        writer.write_ushort(item.get("quality", 1))
    if flags & 8:
        writer.write_ushort(item.get("stack", 1))
    if flags & 16:
        writer.write_int32(item.get("variant", 0))
    if flags & 32:
        writer.write_long(item.get("crafter_id", 0))
        writer.write_string(item.get("crafter_name", ""))
    if flags & 64:
        writer.write_int32(prefab_hash)
    if flags & 128:
        writer.write_num_items(len(custom_data))
        for key, value in custom_data.items():
            writer.write_string(key)
            writer.write_string(value)

    cheated_flags = int(item.get("_cheated_flags", 0)) & 0xFE
    if item.get("cheated", False):
        cheated_flags |= 1
    writer.write_byte(cheated_flags)


def unpack_player_data(data: bytes) -> dict[str, Any]:
    reader = BinaryReader(data)
    result: dict[str, Any] = {"version": reader.read_int32()}
    if result["version"] != CURRENT_PLAYER_VERSION:
        raise SaveFormatError(
            f"Unsupported Player.Save version: {result['version']} "
            f"(this version expects {CURRENT_PLAYER_VERSION})"
        )

    result["max_health"] = reader.read_float()
    result["health"] = reader.read_float()
    result["max_stamina"] = reader.read_float()
    result["time_since_death"] = reader.read_float()
    result["guardian_power"] = reader.read_string()
    result["guardian_power_cooldown"] = reader.read_float()

    result["inventory_version"] = reader.read_int32()
    if result["inventory_version"] != CURRENT_INVENTORY_VERSION:
        raise SaveFormatError(
            f"Unsupported inventory version: {result['inventory_version']} "
            f"(this version expects {CURRENT_INVENTORY_VERSION})"
        )
    item_count = reader.read_ushort()
    result["inventory"] = [_read_item(reader) for _ in range(item_count)]

    result["known_recipes"] = _read_string_list(reader, "known_recipes")
    result["known_stations"] = _read_int_dict(reader, "known_stations")
    result["known_material"] = _read_string_list(reader, "known_material")
    result["shown_tutorials"] = _read_string_list(reader, "shown_tutorials")
    result["uniques"] = _read_string_list(reader, "uniques")
    result["trophies"] = _read_string_list(reader, "trophies")
    result["known_biomes"] = _read_string_list(reader, "known_biomes")
    result["known_texts"] = _read_string_dict(reader, "known_texts")

    result["beard"] = reader.read_string()
    result["hair"] = reader.read_string()
    result["skin_color"] = reader.read_vector3()
    result["hair_color"] = reader.read_vector3()
    result["model_index"] = reader.read_int32()

    food_count = _check_count(reader.read_int32(), "foods")
    result["foods"] = [
        {"name": reader.read_string(), "time": reader.read_float()}
        for _ in range(food_count)
    ]

    result["skill_version"] = reader.read_int32()
    if result["skill_version"] != CURRENT_SKILL_VERSION:
        raise SaveFormatError(
            f"Unsupported skills version: {result['skill_version']}"
        )
    skill_count = _check_count(reader.read_int32(), "skills")
    result["skills"] = [
        {
            "id": reader.read_int32(),
            "level": reader.read_float(),
            "xp": reader.read_float(),
        }
        for _ in range(skill_count)
    ]
    result["custom_data"] = _read_string_dict(reader, "player custom_data")
    result["stamina"] = reader.read_float()
    result["max_eitr"] = reader.read_float()
    result["eitr"] = reader.read_float()
    result["build_ui_data"] = reader.read_byte_array()
    if reader.remaining:
        # A trailing section would indicate that the layout changed. Refuse to
        # write it back silently because that could corrupt the character.
        raise SaveFormatError(
            f"Player.Save has {reader.remaining} unknown trailing bytes"
        )
    return result


def pack_player_data(data: dict[str, Any]) -> bytes:
    writer = BinaryWriter()
    writer.write_int32(CURRENT_PLAYER_VERSION)
    writer.write_float(data.get("max_health", 25.0))
    writer.write_float(data.get("health", 25.0))
    writer.write_float(data.get("max_stamina", 50.0))
    writer.write_float(data.get("time_since_death", 0.0))
    writer.write_string(data.get("guardian_power", ""))
    writer.write_float(data.get("guardian_power_cooldown", 0.0))

    writer.write_int32(CURRENT_INVENTORY_VERSION)
    inventory = data.get("inventory", [])
    if len(inventory) > 0xFFFF:
        raise SaveFormatError("Inventory exceeds 65535 items")
    writer.write_ushort(len(inventory))
    for item in inventory:
        _write_item(writer, item)

    _write_string_list(writer, data.get("known_recipes", []))
    _write_int_dict(writer, data.get("known_stations", {}))
    _write_string_list(writer, data.get("known_material", []))
    _write_string_list(writer, data.get("shown_tutorials", []))
    _write_string_list(writer, data.get("uniques", []))
    _write_string_list(writer, data.get("trophies", []))
    _write_string_list(writer, data.get("known_biomes", []))
    _write_string_dict(writer, data.get("known_texts", {}))

    writer.write_string(data.get("beard", ""))
    writer.write_string(data.get("hair", ""))
    writer.write_vector3(data.get("skin_color", [1.0, 1.0, 1.0]))
    writer.write_vector3(data.get("hair_color", [1.0, 1.0, 1.0]))
    writer.write_int32(data.get("model_index", 0))

    foods = data.get("foods", [])
    writer.write_int32(len(foods))
    for food in foods:
        writer.write_string(food.get("name", ""))
        writer.write_float(food.get("time", 0.0))

    writer.write_int32(CURRENT_SKILL_VERSION)
    skills = data.get("skills", [])
    writer.write_int32(len(skills))
    for skill in skills:
        writer.write_int32(skill.get("id", 0))
        writer.write_float(skill.get("level", 0.0))
        writer.write_float(skill.get("xp", 0.0))

    _write_string_dict(writer, data.get("custom_data", {}))
    writer.write_float(data.get("stamina", 50.0))
    writer.write_float(data.get("max_eitr", 0.0))
    writer.write_float(data.get("eitr", 0.0))
    writer.write_byte_array(data.get("build_ui_data", b""))
    return writer.get_bytes()


def _read_world(reader: BinaryReader) -> dict[str, Any]:
    world = {
        "world_id": reader.read_long(),
        "have_custom_spawn": reader.read_bool(),
        "spawn_point": reader.read_vector3(),
        "have_logout_point": reader.read_bool(),
        "logout_point": reader.read_vector3(),
        "have_death_point": reader.read_bool(),
        "death_point": reader.read_vector3(),
        "home_point": reader.read_vector3(),
    }
    has_map_data = reader.read_bool()
    world["map_data"] = reader.read_byte_array() if has_map_data else None
    return world


def _write_world(writer: BinaryWriter, world: dict[str, Any]) -> None:
    writer.write_long(world.get("world_id", 0))
    writer.write_bool(world.get("have_custom_spawn", False))
    writer.write_vector3(world.get("spawn_point", [0.0, 0.0, 0.0]))
    writer.write_bool(world.get("have_logout_point", False))
    writer.write_vector3(world.get("logout_point", [0.0, 0.0, 0.0]))
    writer.write_bool(world.get("have_death_point", False))
    writer.write_vector3(world.get("death_point", [0.0, 0.0, 0.0]))
    writer.write_vector3(world.get("home_point", [0.0, 0.0, 0.0]))
    map_data = world.get("map_data")
    writer.write_bool(map_data is not None)
    if map_data is not None:
        writer.write_byte_array(map_data)


def _decode_outer(data: bytes) -> tuple[bytes, bytes]:
    reader = BinaryReader(data)
    package = reader.read_byte_array()
    stored_hash = reader.read_byte_array()
    if reader.remaining:
        raise SaveFormatError(f"There are {reader.remaining} bytes after the checksum")
    return package, stored_hash


def read_fch(path: str | Path, verify_hash: bool = True) -> dict[str, Any]:
    path = Path(path)
    raw = path.read_bytes()
    package, stored_hash = _decode_outer(raw)
    calculated_hash = hashlib.sha512(package).digest()
    hash_valid = stored_hash == calculated_hash
    if verify_hash and not hash_valid:
        raise SaveFormatError(
            "The SHA-512 checksum does not match. The file may be corrupt "
            "or may still be being saved by Valheim."
        )

    reader = BinaryReader(package)
    result: dict[str, Any] = {
        "version": reader.read_int32(),
        "hash_valid": hash_valid,
        "source_path": str(path),
        "source_size": len(raw),
    }
    if result["version"] != CURRENT_PROFILE_VERSION:
        raise SaveFormatError(
            f"Unsupported profile version: {result['version']} "
            f"(this version expects {CURRENT_PROFILE_VERSION})"
        )

    stat_count = _check_count(reader.read_int32(), "stat_count")
    profile_count = _check_count(reader.read_int32(), "profile_count")
    result["stat_count"] = stat_count
    result["profile_count"] = profile_count
    result["profiles"] = [
        _read_profile(reader, stat_count)
        for _ in range(profile_count)
    ]
    result["first_spawn"] = reader.read_bool()
    world_count = _check_count(reader.read_int32(), "world_count")
    result["worlds"] = [_read_world(reader) for _ in range(world_count)]
    result["character_name"] = reader.read_string()
    result["player_id"] = reader.read_long()
    result["start_seed"] = reader.read_string()
    result["used_cheats"] = reader.read_bool()
    result["date_created_unix"] = reader.read_long()
    has_player_data = reader.read_bool()
    result["player_data"] = (
        unpack_player_data(reader.read_byte_array())
        if has_player_data
        else None
    )
    if reader.remaining:
        raise SaveFormatError(
            f"The character profile has {reader.remaining} unknown trailing bytes"
        )
    result["stored_hash"] = stored_hash
    return result


def write_fch_bytes(data: dict[str, Any]) -> bytes:
    player_data = data.get("player_data")
    if player_data is None:
        raise SaveFormatError("This character has no editable Player.Save data")

    stat_count = int(data.get("stat_count", 205))
    profiles = data.get("profiles", [])
    if len(profiles) != int(data.get("profile_count", len(profiles))):
        raise SaveFormatError("The profile count does not match the header")

    package_writer = BinaryWriter()
    package_writer.write_int32(CURRENT_PROFILE_VERSION)
    package_writer.write_int32(stat_count)
    package_writer.write_int32(len(profiles))
    for profile in profiles:
        _write_profile(package_writer, profile, stat_count)
    package_writer.write_bool(data.get("first_spawn", False))

    worlds = data.get("worlds", [])
    package_writer.write_int32(len(worlds))
    for world in worlds:
        _write_world(package_writer, world)

    package_writer.write_string(data.get("character_name", "Viking"))
    package_writer.write_long(data.get("player_id", 0))
    package_writer.write_string(data.get("start_seed", ""))
    package_writer.write_bool(data.get("used_cheats", False))
    package_writer.write_long(data.get("date_created_unix", 0))
    package_writer.write_bool(True)
    package_writer.write_byte_array(pack_player_data(player_data))

    package = package_writer.get_bytes()
    writer = BinaryWriter()
    writer.write_byte_array(package)
    writer.write_byte_array(hashlib.sha512(package).digest())
    return writer.get_bytes()


def write_fch(path: str | Path, data: dict[str, Any]) -> None:
    Path(path).write_bytes(write_fch_bytes(data))


def inspect_fch(path: str | Path) -> dict[str, Any]:
    """Read just enough to report the checksum without editing the file."""
    raw = Path(path).read_bytes()
    package, stored_hash = _decode_outer(raw)
    return {
        "hash_valid": hashlib.sha512(package).digest() == stored_hash,
        "package_size": len(package),
        "file_size": len(raw),
    }
