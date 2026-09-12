"""Safe Valheim inventory flag cleaner.

This small desktop app is intentionally narrower than a complete save editor:
it reads Valheim character files (``.fch``), reports item cheat flags, and
writes cleaned copies without touching the originals.  It can also inspect a
Valheim 1.0 world backup archive, but it does not rewrite world chunks: item
inventories live in character saves, not in the world chunk directory.
"""

from __future__ import annotations

import argparse
import copy
import csv
import json
import os
import shutil
import sys
import tarfile
import tempfile
import tkinter as tk
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from tkinter import filedialog, messagebox, ttk
from typing import Any, Iterable

from .save_format import SaveFormatError, read_fch, write_fch_bytes


APP_TITLE = "Valheim Cheat Flag Cleaner"


@dataclass(frozen=True)
class FlaggedItem:
    """A compact, user-facing description of one flagged inventory entry."""

    slot: str
    prefab_hash: int
    stack: int
    quality: int
    world_level: int


@dataclass
class ScanResult:
    path: str
    character_name: str = ""
    player_id: int = 0
    inventory_items: int = 0
    cheated_items: int = 0
    cheated_units: int = 0
    used_cheats: bool = False
    hash_valid: bool = False
    flagged: list[FlaggedItem] = field(default_factory=list)
    error: str = ""

    @property
    def ok(self) -> bool:
        return not self.error


@dataclass(frozen=True)
class CleanResult:
    source: str
    output: str
    removed_items: int
    removed_units: int
    cleared_profile_flag: bool


@dataclass(frozen=True)
class WorldBackupInfo:
    path: str
    members: int
    files: int
    chunks: int
    metadata_files: tuple[str, ...]
    top_level: tuple[str, ...]
    size_bytes: int
    error: str = ""


def _flagged_items(data: dict[str, Any]) -> list[FlaggedItem]:
    player = data.get("player_data") or {}
    result: list[FlaggedItem] = []
    for index, item in enumerate(player.get("inventory", [])):
        if not bool(item.get("cheated", False)):
            continue
        stack = max(1, int(item.get("stack", 1)))
        result.append(
            FlaggedItem(
                slot=f"{int(item.get('grid_x', 0))},{int(item.get('grid_y', 0))}",
                prefab_hash=int(item.get("prefab_hash", 0)),
                stack=stack,
                quality=int(item.get("quality", 1)),
                world_level=int(item.get("world_level", 0)),
            )
        )
    return result


def scan_character(path: str | Path) -> ScanResult:
    """Read one character and return counts without modifying it."""

    source = Path(path)
    result = ScanResult(path=str(source))
    try:
        data = read_fch(source, verify_hash=True)
        flagged = _flagged_items(data)
        result.character_name = str(data.get("character_name", ""))
        result.player_id = int(data.get("player_id", 0))
        result.inventory_items = len((data.get("player_data") or {}).get("inventory", []))
        result.cheated_items = len(flagged)
        result.cheated_units = sum(item.stack for item in flagged)
        result.used_cheats = bool(data.get("used_cheats", False))
        result.hash_valid = bool(data.get("hash_valid", False))
        result.flagged = flagged
    except (OSError, SaveFormatError, ValueError) as exc:
        result.error = f"{type(exc).__name__}: {exc}"
    return result


def discover_characters(path: str | Path) -> list[Path]:
    """Return stable, de-duplicated ``.fch`` paths from a file or folder."""

    source = Path(path)
    if source.is_file():
        return [source] if source.suffix.lower() == ".fch" else []
    if not source.is_dir():
        return []
    return sorted(
        {candidate.resolve() for candidate in source.rglob("*.fch")},
        key=lambda item: str(item).lower(),
    )


def scan_characters(path: str | Path) -> list[ScanResult]:
    return [scan_character(candidate) for candidate in discover_characters(path)]


def _next_available(path: Path) -> Path:
    if not path.exists():
        return path
    for counter in range(2, 10000):
        candidate = path.with_name(f"{path.stem}.{counter}{path.suffix}")
        if not candidate.exists():
            return candidate
    raise FileExistsError(f"Could not allocate an output name for {path}")


def clean_character(
    source: str | Path,
    output: str | Path,
    *,
    clear_profile_flag: bool = False,
) -> CleanResult:
    """Write a cleaned copy, atomically, and verify its checksum/count."""

    source_path = Path(source)
    output_path = Path(output)
    data = read_fch(source_path, verify_hash=True)
    player = data.get("player_data")
    if not isinstance(player, dict):
        raise SaveFormatError("Character has no editable Player.Save payload")

    before = _flagged_items(data)
    edited = copy.deepcopy(data)
    edited_player = edited["player_data"]
    for item in edited_player.get("inventory", []):
        if item.get("cheated", False):
            item["cheated"] = False
            item["_cheated_flags"] = int(item.get("_cheated_flags", 0)) & 0xFE
    if clear_profile_flag:
        edited["used_cheats"] = False

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="wb", prefix=f".{output_path.name}.", suffix=".tmp", dir=output_path.parent, delete=False
    ) as temporary:
        temporary_path = Path(temporary.name)
        temporary.write(write_fch_bytes(edited))
        temporary.flush()
        os.fsync(temporary.fileno())
    try:
        os.replace(temporary_path, output_path)
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise

    verification = scan_character(output_path)
    if not verification.ok:
        raise SaveFormatError(f"Output verification failed: {verification.error}")
    if verification.cheated_items != 0:
        raise SaveFormatError("Output still contains cheated item flags")
    if clear_profile_flag and verification.used_cheats:
        raise SaveFormatError("Output still contains the profile cheat indicator")
    if verification.inventory_items != len(player.get("inventory", [])):
        raise SaveFormatError("Output inventory count changed unexpectedly")

    return CleanResult(
        source=str(source_path),
        output=str(output_path),
        removed_items=len(before),
        removed_units=sum(item.stack for item in before),
        cleared_profile_flag=clear_profile_flag,
    )


def clean_characters(
    source: str | Path,
    output_dir: str | Path,
    *,
    clear_profile_flag: bool = False,
) -> list[CleanResult]:
    """Clean all valid character files into a separate directory."""

    destination = Path(output_dir)
    destination.mkdir(parents=True, exist_ok=True)
    results: list[CleanResult] = []
    for candidate in discover_characters(source):
        output = _next_available(destination / f"{candidate.stem}.cheat-cleaned.fch")
        results.append(
            clean_character(candidate, output, clear_profile_flag=clear_profile_flag)
        )
    return results


def _safe_tar_member(name: str) -> bool:
    normalized = Path(name)
    return not normalized.is_absolute() and ".." not in normalized.parts


def inspect_world_backup(path: str | Path) -> WorldBackupInfo:
    """Inspect a world archive without extracting or changing it."""

    archive = Path(path)
    try:
        with tarfile.open(archive, mode="r:gz") as handle:
            members = handle.getmembers()
            unsafe = [member.name for member in members if not _safe_tar_member(member.name)]
            if unsafe:
                raise ValueError(f"unsafe archive member: {unsafe[0]}")
            files = [member for member in members if member.isfile()]
            chunks = [member for member in files if member.name.endswith(".chunk")]
            metadata = tuple(
                member.name
                for member in files
                if Path(member.name).name.endswith((".db2", ".fwl2", ".ok", ".chunks"))
            )
            top_level = tuple(
                sorted({Path(member.name).parts[0] for member in members if Path(member.name).parts})
            )
            return WorldBackupInfo(
                path=str(archive),
                members=len(members),
                files=len(files),
                chunks=len(chunks),
                metadata_files=metadata,
                top_level=top_level,
                size_bytes=archive.stat().st_size,
            )
    except (OSError, tarfile.TarError, ValueError) as exc:
        return WorldBackupInfo(
            path=str(archive),
            members=0,
            files=0,
            chunks=0,
            metadata_files=(),
            top_level=(),
            size_bytes=0,
            error=f"{type(exc).__name__}: {exc}",
        )


def _result_row(result: ScanResult) -> list[str]:
    if result.error:
        return [Path(result.path).name, "", "", "", "", "", f"ERRO: {result.error}"]
    return [
        Path(result.path).name,
        result.character_name,
        str(result.inventory_items),
        str(result.cheated_items),
        str(result.cheated_units),
        "sim" if result.used_cheats else "não",
        "OK",
    ]


def write_report(path: str | Path, results: Iterable[ScanResult]) -> None:
    """Write a compact CSV report next to a cleaned batch."""

    rows = list(results)
    destination = Path(path)
    with destination.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            ["arquivo", "personagem", "itens_inventario", "itens_com_flag", "unidades_com_flag", "used_cheats", "status"]
        )
        writer.writerows(_result_row(result) for result in rows)


def _format_summary(results: list[ScanResult]) -> str:
    valid = [result for result in results if result.ok]
    errors = [result for result in results if not result.ok]
    item_count = sum(result.cheated_items for result in valid)
    unit_count = sum(result.cheated_units for result in valid)
    profile_count = sum(1 for result in valid if result.used_cheats)
    return (
        f"Arquivos: {len(results)} | válidos: {len(valid)} | erros: {len(errors)}\n"
        f"Itens com flag cheated: {item_count} (unidades somadas: {unit_count})\n"
        f"Perfis com indicador used_cheats: {profile_count}\n"
    )


class CleanerApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(APP_TITLE)
        self.geometry("1120x680")
        self.minsize(900, 560)
        self.source_var = tk.StringVar()
        self.clear_profile_var = tk.BooleanVar(value=False)
        self.status_var = tk.StringVar(value="Selecione uma pasta ou arquivo .fch para começar.")
        self.results: list[ScanResult] = []
        self._build_ui()

    def _build_ui(self) -> None:
        root = ttk.Frame(self, padding=12)
        root.pack(fill="both", expand=True)
        ttk.Label(root, text=APP_TITLE, font=("Segoe UI", 16, "bold")).pack(anchor="w")
        ttk.Label(
            root,
            text="As cópias originais não são alteradas. As flags ficam nos saves .fch dos personagens; o backup do mundo serve para recuperação.",
            wraplength=1040,
        ).pack(anchor="w", pady=(3, 12))

        source_line = ttk.Frame(root)
        source_line.pack(fill="x")
        ttk.Entry(source_line, textvariable=self.source_var).pack(side="left", fill="x", expand=True)
        ttk.Button(source_line, text="Arquivo .fch", command=self.choose_file).pack(side="left", padx=(8, 0))
        ttk.Button(source_line, text="Pasta de personagens", command=self.choose_folder).pack(side="left", padx=(8, 0))
        ttk.Button(source_line, text="Backup do mundo", command=self.choose_world_backup).pack(side="left", padx=(8, 0))
        ttk.Button(source_line, text="Escanear", command=self.scan).pack(side="left", padx=(8, 0))

        options = ttk.Frame(root)
        options.pack(fill="x", pady=(10, 8))
        ttk.Checkbutton(
            options,
            text="Limpar também o indicador global used_cheats do personagem",
            variable=self.clear_profile_var,
        ).pack(side="left")
        ttk.Button(options, text="Remover flags em cópias", command=self.clean).pack(side="right")

        table_frame = ttk.Frame(root)
        table_frame.pack(fill="both", expand=True)
        columns = ("file", "character", "inventory", "cheated", "units", "profile", "status")
        self.tree = ttk.Treeview(table_frame, columns=columns, show="headings", selectmode="browse")
        headings = {
            "file": "Arquivo",
            "character": "Personagem",
            "inventory": "Inventário",
            "cheated": "Itens com flag",
            "units": "Unidades",
            "profile": "used_cheats",
            "status": "Status",
        }
        widths = {"file": 250, "character": 150, "inventory": 90, "cheated": 100, "units": 90, "profile": 100, "status": 300}
        for column in columns:
            self.tree.heading(column, text=headings[column])
            self.tree.column(column, width=widths[column], anchor="w")
        scrollbar = ttk.Scrollbar(table_frame, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)
        self.tree.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        self.tree.bind("<<TreeviewSelect>>", self.show_selected)

        self.details = tk.Text(root, height=8, wrap="word", state="disabled")
        self.details.pack(fill="x", pady=(10, 0))
        ttk.Label(root, textvariable=self.status_var).pack(anchor="w", pady=(8, 0))

    def choose_file(self) -> None:
        selected = filedialog.askopenfilename(filetypes=[("Valheim character", "*.fch"), ("All files", "*.*")])
        if selected:
            self.source_var.set(selected)
            self.scan()

    def choose_folder(self) -> None:
        selected = filedialog.askdirectory(title="Pasta com saves .fch")
        if selected:
            self.source_var.set(selected)
            self.scan()

    def choose_world_backup(self) -> None:
        selected = filedialog.askopenfilename(
            title="World backup",
            filetypes=[("World backup", "*.tar.gz"), ("All files", "*.*")],
        )
        if not selected:
            return
        self.source_var.set(selected)
        info = inspect_world_backup(selected)
        if info.error:
            self._set_details(info.error)
            self.status_var.set("Não foi possível ler o backup do mundo.")
            return
        self._set_details(
            "Backup do mundo lido sem extração:\n"
            f"Arquivo: {info.path}\nTamanho: {info.size_bytes:,} bytes\n"
            f"Arquivos: {info.files} | chunks: {info.chunks}\n"
            f"Metadados: {', '.join(info.metadata_files) or 'não encontrados'}\n\n"
            "Os itens de inventário e suas flags de cheat ficam nos arquivos .fch dos personagens."
        )
        self.status_var.set("Backup do mundo inspecionado; selecione uma pasta/arquivo .fch para limpar itens.")

    def scan(self) -> None:
        source = self.source_var.get().strip()
        if not source:
            messagebox.showinfo(APP_TITLE, "Selecione um arquivo .fch ou uma pasta de personagens.")
            return
        if Path(source).suffix.lower() in {".gz", ".tgz"}:
            self.choose_world_backup()
            return
        self.results = scan_characters(source)
        for item in self.tree.get_children():
            self.tree.delete(item)
        for result in self.results:
            self.tree.insert("", "end", iid=str(len(self.tree.get_children())), values=_result_row(result))
        self.status_var.set(_format_summary(self.results).replace("\n", "  "))
        self._set_details(_format_summary(self.results))

    def show_selected(self, _event: Any = None) -> None:
        selection = self.tree.selection()
        if not selection:
            return
        result = self.results[int(selection[0])]
        if result.error:
            self._set_details(result.error)
            return
        lines = [
            f"Arquivo: {result.path}",
            f"Personagem: {result.character_name} | player ID: {result.player_id}",
            f"Itens com flag: {result.cheated_items} | unidades: {result.cheated_units}",
        ]
        if result.flagged:
            lines.append("Entradas marcadas (slot x,y | prefab hash | stack | qualidade | world level):")
            lines.extend(
                f"  {item.slot} | {item.prefab_hash} | {item.stack} | {item.quality} | {item.world_level}"
                for item in result.flagged
            )
        else:
            lines.append("Nenhum item com flag cheated.")
        self._set_details("\n".join(lines))

    def clean(self) -> None:
        source = self.source_var.get().strip()
        if not source or Path(source).suffix.lower() != ".fch" and not Path(source).is_dir():
            messagebox.showinfo(APP_TITLE, "Selecione um arquivo .fch ou uma pasta que contenha saves .fch.")
            return
        candidates = discover_characters(source)
        if not candidates:
            messagebox.showinfo(APP_TITLE, "Nenhum arquivo .fch encontrado.")
            return
        output = filedialog.askdirectory(title="Pasta para salvar as cópias limpas")
        if not output:
            return
        try:
            cleaned = clean_characters(
                source,
                output,
                clear_profile_flag=self.clear_profile_var.get(),
            )
            total_items = sum(item.removed_items for item in cleaned)
            total_units = sum(item.removed_units for item in cleaned)
            report_path = Path(output) / "cheat-cleaner-report.csv"
            write_report(report_path, [scan_character(item.output) for item in cleaned])
            self._set_details(
                f"Concluído. Arquivos escritos: {len(cleaned)}\n"
                f"Itens com flag removidos: {total_items}\n"
                f"Unidades somadas: {total_units}\n"
                f"Relatório: {report_path}"
            )
            self.status_var.set(f"Removidos {total_items} itens com flag em {len(cleaned)} arquivo(s).")
            messagebox.showinfo(APP_TITLE, f"Concluído. Itens com flag removidos: {total_items}\nUnidades: {total_units}")
        except (OSError, SaveFormatError, ValueError) as exc:
            messagebox.showerror(APP_TITLE, f"Não foi possível limpar os arquivos:\n{exc}")

    def _set_details(self, text: str) -> None:
        self.details.configure(state="normal")
        self.details.delete("1.0", "end")
        self.details.insert("1.0", text)
        self.details.configure(state="disabled")


def _cli_scan(source: str, json_output: bool) -> int:
    results = scan_characters(source)
    if json_output:
        print(json.dumps([asdict(result) for result in results], ensure_ascii=False, indent=2))
    else:
        print(_format_summary(results), end="")
        for result in results:
            print(" | ".join(_result_row(result)))
    return 1 if any(result.error for result in results) else 0


def _cli_clean(args: argparse.Namespace) -> int:
    results = scan_characters(args.source)
    invalid = [result for result in results if result.error]
    if invalid:
        for result in invalid:
            print(f"ERRO: {result.path}: {result.error}", file=sys.stderr)
        return 2
    before_items = sum(result.cheated_items for result in results)
    before_units = sum(result.cheated_units for result in results)
    cleaned = clean_characters(
        args.source,
        args.output_dir,
        clear_profile_flag=args.clear_profile_flag,
    )
    report = Path(args.output_dir) / "cheat-cleaner-report.csv"
    write_report(report, [scan_character(item.output) for item in cleaned])
    print(f"Arquivos escritos: {len(cleaned)}")
    print(f"Itens com flag encontrados/removidos: {before_items}")
    print(f"Unidades somadas: {before_units}")
    print(f"Relatório: {report}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=APP_TITLE)
    subparsers = parser.add_subparsers(dest="command")
    scan_parser = subparsers.add_parser("scan", help="conta flags sem alterar arquivos")
    scan_parser.add_argument("source", help="arquivo .fch ou pasta")
    scan_parser.add_argument("--json", action="store_true", dest="json_output")
    clean_parser = subparsers.add_parser("clean", help="escreve cópias limpas")
    clean_parser.add_argument("source", help="arquivo .fch ou pasta")
    clean_parser.add_argument("output_dir", help="pasta de saída")
    clean_parser.add_argument("--clear-profile-flag", action="store_true")
    world_parser = subparsers.add_parser("world-info", help="inspeciona um backup .tar.gz")
    world_parser.add_argument("archive")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "scan":
        return _cli_scan(args.source, args.json_output)
    if args.command == "clean":
        return _cli_clean(args)
    if args.command == "world-info":
        info = inspect_world_backup(args.archive)
        print(json.dumps(asdict(info), ensure_ascii=False, indent=2))
        return 1 if info.error else 0
    app = CleanerApp()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
