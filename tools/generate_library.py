from __future__ import annotations

import argparse
import json
import os
import re
from datetime import datetime
from pathlib import Path
from typing import Iterable
from xml.etree import ElementTree as ET


MAPLE_TAG_RE = re.compile(r"#[A-Za-z0-9]")


def clean_text(value: str | None) -> str:
    if not value:
        return ""
    value = value.replace("\\r", "\r").replace("\\n", "\n")
    value = MAPLE_TAG_RE.sub("", value)
    value = re.sub(r"[ \t]+\n", "\n", value)
    return value.strip()


def file_set(path: Path, suffix: str) -> set[str]:
    if not path.is_dir():
        return set()
    return {entry.name for entry in path.iterdir() if entry.is_file() and entry.name.endswith(suffix)}


def equip_category(item_id: int) -> str:
    if (1010000 <= item_id < 1040000) or (1120000 <= item_id < 1200000):
        return "Accessory"
    if 1000000 <= item_id < 1010000:
        return "Cap"
    if 1100000 <= item_id < 1110000:
        return "Cape"
    if 1040000 <= item_id < 1050000:
        return "Coat"
    if (20000 <= item_id < 30000) or (50000 <= item_id < 60000):
        return "Face"
    if 1080000 <= item_id < 1090000:
        return "Glove"
    if (30000 <= item_id < 50000) or (60000 <= item_id < 70000):
        return "Hair"
    if 1050000 <= item_id < 1060000:
        return "Longcoat"
    if 1060000 <= item_id < 1070000:
        return "Pants"
    if 1802000 <= item_id < 1842000:
        return "PetEquip"
    if 1112000 <= item_id < 1120000:
        return "Ring"
    if 1090000 <= item_id < 1100000:
        return "Shield"
    if 1070000 <= item_id < 1080000:
        return "Shoes"
    if 1900000 <= item_id < 2000000:
        return "TamingMob"
    if 1210000 <= item_id < 1800000:
        return "Weapon"
    return "Equipment"


def child_value(node: ET.Element, name: str) -> str:
    child = node.find(f"./string[@name='{name}']")
    if child is None:
        return ""
    return clean_text(child.attrib.get("value", ""))


def item_group_file(item_id: int, server: bool) -> str:
    name = f"{item_id:08d}"[:4] + ".img"
    return f"{name}.xml" if server else name


def equip_file(item_id: int, server: bool) -> str:
    name = f"{item_id:08d}.img"
    return f"{name}.xml" if server else name


def make_record(
    item_id: int,
    name: str,
    desc: str,
    item_type: str,
    category: str,
    client_asset: bool,
    server_asset: bool,
) -> dict:
    search = f"{item_id} {name} {desc} {item_type} {category}".lower()
    return {
        "id": item_id,
        "name": name,
        "desc": desc,
        "type": item_type,
        "category": category,
        "clientAsset": client_asset,
        "serverAsset": server_asset,
        "search": search,
    }


def parse_id(value: str | None) -> int | None:
    if not value or not value.isdigit():
        return None
    return int(value)


def walk_item_nodes(parent: ET.Element) -> Iterable[ET.Element]:
    for node in parent.findall("./imgdir"):
        if parse_id(node.attrib.get("name")) is not None:
            yield node


def build_database(server_wz: Path, client_data: Path) -> list[dict]:
    string_wz = server_wz / "String.wz"
    if not string_wz.is_dir():
        raise FileNotFoundError(f"Missing String.wz folder: {string_wz}")

    equip_categories = [
        "Accessory",
        "Afterimage",
        "Cap",
        "Cape",
        "Coat",
        "Dragon",
        "Face",
        "Glove",
        "Hair",
        "Longcoat",
        "Pants",
        "PetEquip",
        "Ring",
        "Shield",
        "Shoes",
        "TamingMob",
        "Weapon",
    ]
    item_categories = ["Cash", "Consume", "Etc", "Install", "Pet", "Special"]

    client_equip = {
        cat: file_set(client_data / "Character" / cat, ".img") for cat in equip_categories
    }
    server_equip = {
        cat: file_set(server_wz / "Character.wz" / cat, ".img.xml")
        for cat in equip_categories
    }
    client_item = {
        cat: file_set(client_data / "Item" / cat, ".img") for cat in item_categories
    }
    server_item = {
        cat: file_set(server_wz / "Item.wz" / cat, ".img.xml") for cat in item_categories
    }

    records: list[dict] = []

    eqp_root = ET.parse(string_wz / "Eqp.img.xml").getroot()
    eqp_parent = eqp_root.find("./imgdir[@name='Eqp']")
    if eqp_parent is not None:
        for category_node in eqp_parent.findall("./imgdir"):
            category = category_node.attrib.get("name", "Equipment")
            for node in walk_item_nodes(category_node):
                item_id = int(node.attrib["name"])
                name = child_value(node, "name")
                if not name:
                    continue
                desc = child_value(node, "desc")
                actual_category = category or equip_category(item_id)
                client_asset = equip_file(item_id, False) in client_equip.get(actual_category, set())
                server_asset = equip_file(item_id, True) in server_equip.get(actual_category, set())
                records.append(
                    make_record(
                        item_id,
                        name,
                        desc,
                        "Equipment",
                        actual_category,
                        client_asset,
                        server_asset,
                    )
                )

    specs = [
        ("Consume.img.xml", "Use", "Consume", None),
        ("Etc.img.xml", "Etc", "Etc", "Etc"),
        ("Ins.img.xml", "Setup", "Install", None),
        ("Cash.img.xml", "Cash", "Cash", None),
        ("Pet.img.xml", "Pet", "Pet", None),
    ]

    for file_name, item_type, category, nested in specs:
        path = string_wz / file_name
        if not path.is_file():
            continue
        root = ET.parse(path).getroot()
        parent = root.find(f"./imgdir[@name='{nested}']") if nested else root
        if parent is None:
            continue
        for node in walk_item_nodes(parent):
            item_id = int(node.attrib["name"])
            name = child_value(node, "name")
            if not name:
                continue
            desc = child_value(node, "desc")
            client_asset = item_group_file(item_id, False) in client_item.get(category, set())
            server_asset = item_group_file(item_id, True) in server_item.get(category, set())
            records.append(
                make_record(item_id, name, desc, item_type, category, client_asset, server_asset)
            )

    deduped = {record["id"]: record for record in records}
    return sorted(deduped.values(), key=lambda item: (item["name"].lower(), item["id"]))


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate the KairoMS Library item database.")
    parser.add_argument("--server-wz", default=r"C:\Users\DELL\Desktop\MapleRoot Full Repack\Server\wz")
    parser.add_argument("--client-data", default=r"C:\Users\DELL\Desktop\KairoMS\Data")
    parser.add_argument(
        "--out",
        default=str(Path(__file__).resolve().parents[1] / "data" / "items.json"),
    )
    args = parser.parse_args()

    server_wz = Path(args.server_wz)
    client_data = Path(args.client_data)
    out_file = Path(args.out)
    out_file.parent.mkdir(parents=True, exist_ok=True)

    records = build_database(server_wz, client_data)
    payload = {
        "generatedAt": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "serverWz": str(server_wz),
        "clientData": str(client_data),
        "total": len(records),
        "items": records,
    }

    out_file.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Generated KairoMS library database: {out_file}")
    print(f"Items: {len(records)}")


if __name__ == "__main__":
    main()
