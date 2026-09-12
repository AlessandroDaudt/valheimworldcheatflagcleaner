import copy
import tarfile
import tempfile
import unittest
from pathlib import Path

from valheim_cheat_flag_cleaner.save_format import read_fch, write_fch_bytes
from valheim_cheat_flag_cleaner.valheim_cheat_cleaner import (
    clean_character,
    inspect_world_backup,
    scan_character,
)


LOCAL_CHARACTER = Path.home() / "AppData" / "LocalLow" / "IronGate" / "Valheim" / "characters_local" / "tosquerashi2.fch"


class CheatCleanerTests(unittest.TestCase):
    def test_clean_removes_only_item_flag_and_keeps_source(self) -> None:
        if not LOCAL_CHARACTER.is_file():
            self.skipTest("No current local character save is available")
        original = read_fch(LOCAL_CHARACTER)
        if not original.get("player_data", {}).get("inventory"):
            self.skipTest("Character has no inventory item to mark")

        flagged = copy.deepcopy(original)
        item = flagged["player_data"]["inventory"][0]
        item["cheated"] = True
        item["_cheated_flags"] = int(item.get("_cheated_flags", 0)) | 1

        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            source = folder / "synthetic.fch"
            output = folder / "synthetic.cheat-cleaned.fch"
            source.write_bytes(write_fch_bytes(flagged))
            before = source.read_bytes()
            self.assertEqual(scan_character(source).cheated_items, 1)

            result = clean_character(source, output)

            self.assertEqual(result.removed_items, 1)
            self.assertEqual(scan_character(output).cheated_items, 0)
            self.assertEqual(source.read_bytes(), before)

    def test_world_archive_is_inspected_without_extraction(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            archive = folder / "world.tar.gz"
            world = folder / "ExampleWorld"
            world.mkdir()
            (world / "_main.1.db2").write_bytes(b"db")
            (world / "_main.1.fwl2").write_bytes(b"fwl")
            (world / "0_0.chunk").write_bytes(b"chunk")
            with tarfile.open(archive, "w:gz") as handle:
                handle.add(world, arcname="ExampleWorld")

            info = inspect_world_backup(archive)

            self.assertFalse(info.error)
            self.assertEqual(info.chunks, 1)
            self.assertIn("ExampleWorld/_main.1.db2", info.metadata_files)
            self.assertTrue((folder / "ExampleWorld" / "_main.1.db2").exists())


if __name__ == "__main__":
    unittest.main()
