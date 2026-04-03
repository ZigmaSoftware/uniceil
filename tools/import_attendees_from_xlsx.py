#!/usr/bin/env python3
"""Import attendees from the travel list workbook using curl.

Dry-run is the default mode so the script is safe to inspect first.

Examples:
  python3 tools/import_attendees_from_xlsx.py
  python3 tools/import_attendees_from_xlsx.py --mode import --limit 5
  python3 tools/import_attendees_from_xlsx.py --mode cleanup
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile
from dataclasses import dataclass
from pathlib import Path


NS = {"a": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
DEFAULT_XLSX = Path("/Users/zigma-mac/Downloads/Travell List (3) (1).xlsx")
DEFAULT_BASE_URL = "https://zigmaglobal.in/uniceil/attendance"
DEFAULT_TRACK_FILE = Path("tools/last_imported_attendee_ids.txt")
DEFAULT_SQL_OUTPUT = Path("/Users/zigma-mac/Documents/uniceil/attendance/wpe_employee_import_from_excel.sql")


@dataclass(frozen=True)
class Attendee:
    employee_name: str
    designation: str
    reporting_officer: str
    phone_number: str = ""


def column_index(cell_reference: str) -> int:
    letters = "".join(char for char in cell_reference if char.isalpha())
    value = 0
    for char in letters:
        value = value * 26 + (ord(char.upper()) - ord("A") + 1)
    return value - 1


def read_shared_strings(archive: zipfile.ZipFile) -> list[str]:
    if "xl/sharedStrings.xml" not in archive.namelist():
        return []

    root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
    values: list[str] = []
    for shared_string in root.findall("a:si", NS):
        text = "".join(node.text or "" for node in shared_string.findall(".//a:t", NS))
        values.append(text.strip())
    return values


def sheet_path(archive: zipfile.ZipFile) -> str:
    workbook = ET.fromstring(archive.read("xl/workbook.xml"))
    relationships = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))

    first_sheet = workbook.find("a:sheets/a:sheet", NS)
    if first_sheet is None:
        raise RuntimeError("Workbook does not contain any sheets.")

    rel_id = first_sheet.attrib.get("{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id")
    if not rel_id:
        raise RuntimeError("Unable to resolve workbook relationship.")

    rel_map = {
        rel.attrib["Id"]: rel.attrib["Target"]
        for rel in relationships.findall("{http://schemas.openxmlformats.org/package/2006/relationships}Relationship")
    }
    target = rel_map.get(rel_id)
    if not target:
        raise RuntimeError("Unable to resolve first worksheet path.")

    return f"xl/{target}" if not target.startswith("xl/") else target


def read_rows(xlsx_path: Path) -> list[dict[str, str]]:
    with zipfile.ZipFile(xlsx_path) as archive:
        shared_strings = read_shared_strings(archive)
        worksheet = ET.fromstring(archive.read(sheet_path(archive)))

    rows: list[dict[str, str]] = []
    for row in worksheet.findall(".//a:sheetData/a:row", NS):
        values: dict[int, str] = {}
        for cell in row.findall("a:c", NS):
            ref = cell.attrib.get("r", "")
            idx = column_index(ref)
            raw_value = cell.findtext("a:v", default="", namespaces=NS)
            if cell.attrib.get("t") == "s" and raw_value != "":
                raw_value = shared_strings[int(raw_value)]
            values[idx] = raw_value.strip()

        if not values:
            continue

        max_index = max(values)
        ordered = {str(index): values.get(index, "") for index in range(max_index + 1)}
        rows.append(ordered)

    return rows


def attendees_from_workbook(xlsx_path: Path) -> list[Attendee]:
    raw_rows = read_rows(xlsx_path)
    if not raw_rows:
        return []

    header_row = raw_rows[0]
    headers = [header_row[str(index)].strip() for index in range(len(header_row))]
    lookup = {header.lower(): idx for idx, header in enumerate(headers)}

    name_idx = lookup.get("name")
    designation_idx = lookup.get("designation")
    phone_idx = lookup.get("phone number")
    reporting_idx = lookup.get("reporting manager")

    if name_idx is None or designation_idx is None or reporting_idx is None:
        raise RuntimeError(
            "Expected workbook columns 'Name', 'Designation', and 'Reporting Manager' were not found."
        )

    attendees: list[Attendee] = []
    seen: set[tuple[str, str, str, str]] = set()

    for row in raw_rows[1:]:
        name = row.get(str(name_idx), "").strip()
        designation = row.get(str(designation_idx), "").strip()
        phone_number = row.get(str(phone_idx), "").strip() if phone_idx is not None else ""
        reporting_officer = row.get(str(reporting_idx), "").strip()

        if not name or not designation or not reporting_officer:
            continue

        key = (
            name.casefold(),
            designation.casefold(),
            reporting_officer.casefold(),
            phone_number,
        )
        if key in seen:
            continue

        seen.add(key)
        attendees.append(
            Attendee(
                employee_name=name,
                designation=designation,
                reporting_officer=reporting_officer,
                phone_number=phone_number,
            )
        )

    return attendees


def curl_import(attendee: Attendee, endpoint: str) -> dict[str, object]:
    command = [
        "curl",
        "--silent",
        "--show-error",
        "--fail",
        "-X",
        "POST",
        endpoint,
        "-F",
        f"employee_name={attendee.employee_name}",
        "-F",
        f"designation={attendee.designation}",
        "-F",
        f"reporting_officer={attendee.reporting_officer}",
        "-F",
        f"phone_number={attendee.phone_number}",
    ]

    completed = subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
    )
    payload = json.loads(completed.stdout)
    if not payload.get("success", False):
        raise RuntimeError(payload.get("message", "Unknown import failure"))
    return payload


def curl_delete(employee_id: str, endpoint: str) -> None:
    command = [
        "curl",
        "--silent",
        "--show-error",
        "--fail",
        "-X",
        "POST",
        endpoint,
        "-F",
        f"employee_id={employee_id}",
    ]
    subprocess.run(command, check=True, capture_output=True, text=True)


def sql_string(value: str | None) -> str:
    if value is None:
        return "NULL"

    escaped = value.replace("\\", "\\\\").replace("'", "''")
    return f"'{escaped}'"


def sql_comment(value: str) -> str:
    sanitized = re.sub(r"[^A-Za-z0-9 _./()-]+", "", value).strip()
    return sanitized or "attendee"


def write_sql_seed(attendees: list[Attendee], output_path: Path) -> None:
    lines = [
        "-- Generated from Travell List (3) (1).xlsx",
        "-- Safe to re-run: each attendee insert is skipped if the same row already exists.",
        "",
        "START TRANSACTION;",
        "",
    ]

    for attendee in attendees:
        lines.extend(
            [
                f"-- {sql_comment(attendee.employee_name)}",
                "INSERT INTO wpe_employee (employee_name, phone_number, `Designation`, reporting_officer, image_path)",
                "SELECT",
                f"    {sql_string(attendee.employee_name)} AS employee_name,",
                f"    {sql_string(attendee.phone_number)} AS phone_number,",
                f"    {sql_string(attendee.designation)} AS `Designation`,",
                f"    {sql_string(attendee.reporting_officer)} AS reporting_officer,",
                "    NULL AS image_path",
                "FROM DUAL",
                "WHERE NOT EXISTS (",
                "    SELECT 1",
                "    FROM wpe_employee",
                f"    WHERE employee_name = {sql_string(attendee.employee_name)}",
                f"      AND COALESCE(phone_number, '') = {sql_string(attendee.phone_number)}",
                f"      AND `Designation` = {sql_string(attendee.designation)}",
                f"      AND reporting_officer = {sql_string(attendee.reporting_officer)}",
                ");",
                "",
            ]
        )

    lines.extend(
        [
            "COMMIT;",
            "",
        ]
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines), encoding="utf-8")


def write_tracking_file(path: Path, employee_ids: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(employee_ids) + ("\n" if employee_ids else ""), encoding="utf-8")


def read_tracking_file(path: Path) -> list[str]:
    if not path.exists():
        return []
    return [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xlsx", type=Path, default=DEFAULT_XLSX, help="Path to the attendee workbook.")
    parser.add_argument(
        "--base-url",
        default=DEFAULT_BASE_URL,
        help="Backend attendance folder URL.",
    )
    parser.add_argument(
        "--mode",
        choices=["dry-run", "import", "cleanup", "sql"],
        default="dry-run",
        help="Dry-run prints the payload preview. Import posts records. Cleanup deletes IDs recorded in the tracking file. SQL writes a rerunnable seed file for phpMyAdmin/manual import.",
    )
    parser.add_argument("--limit", type=int, default=0, help="Limit rows for test imports.")
    parser.add_argument(
        "--tracking-file",
        type=Path,
        default=DEFAULT_TRACK_FILE,
        help="File used to remember imported attendee IDs for cleanup.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_SQL_OUTPUT,
        help="Output file path used by --mode sql.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    register_endpoint = args.base_url.rstrip("/") + "/register_employee.php"
    delete_endpoint = args.base_url.rstrip("/") + "/delete_employee.php"

    if args.mode == "cleanup":
        employee_ids = read_tracking_file(args.tracking_file)
        if not employee_ids:
            print("No tracked attendee IDs found to delete.")
            return 0

        for employee_id in employee_ids:
            curl_delete(employee_id, delete_endpoint)
            print(f"Deleted attendee {employee_id}")

        args.tracking_file.unlink(missing_ok=True)
        return 0

    attendees = attendees_from_workbook(args.xlsx)
    if args.limit > 0:
        attendees = attendees[: args.limit]

    print(f"Workbook: {args.xlsx}")
    print(f"Prepared attendees: {len(attendees)}")
    print("Fields posted: employee_name, designation, reporting_officer, phone_number")

    if args.mode == "sql":
        write_sql_seed(attendees, args.output)
        print(f"SQL seed written to {args.output}")
        return 0

    if args.mode == "dry-run":
        preview = [
            {
                "employee_name": attendee.employee_name,
                "designation": attendee.designation,
                "reporting_officer": attendee.reporting_officer,
                "phone_number": attendee.phone_number,
            }
            for attendee in attendees[:10]
        ]
        print(json.dumps(preview, indent=2, ensure_ascii=False))
        if len(attendees) > 10:
            print(f"... {len(attendees) - 10} more rows omitted from preview")
        return 0

    imported_ids: list[str] = []
    for index, attendee in enumerate(attendees, start=1):
        payload = curl_import(attendee, register_endpoint)
        employee = payload.get("employee", {})
        employee_id = str(employee.get("employee_id", ""))
        imported_ids.append(employee_id)
        print(f"{index:03d}. Imported {attendee.employee_name} -> {employee_id}")

    write_tracking_file(args.tracking_file, imported_ids)
    print(f"Stored imported IDs in {args.tracking_file}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        print(error.stderr or error.stdout or str(error), file=sys.stderr)
        raise SystemExit(1)
    except Exception as error:  # pragma: no cover - CLI safety net
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
