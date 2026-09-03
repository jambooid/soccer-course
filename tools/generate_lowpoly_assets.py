#!/usr/bin/env python3
"""Generate deterministic low-poly OBJ assets for the WE2000-style 3D view.

The script intentionally uses only the Python standard library so it can run in
CI or on a machine without Blender. Generated OBJ/MTL files are small enough
for placeholder and debug scenes; final art can replace them without changing
the presentation API.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path


class ObjWriter:
    def __init__(self) -> None:
        self.vertices: list[tuple[float, float, float]] = []
        self.faces: list[tuple[str, tuple[int, ...]]] = []

    def vertex(self, x: float, y: float, z: float) -> int:
        self.vertices.append((x, y, z))
        return len(self.vertices)

    def face(self, material: str, *indices: int) -> None:
        self.faces.append((material, indices))

    def save(self, path: Path, materials: dict[str, tuple[float, float, float]]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        mtl_path = path.with_suffix(".mtl")
        mtl_lines = []
        for name, color in materials.items():
            mtl_lines += [f"newmtl {name}", "Kd %.4f %.4f %.4f" % color, "roughness 1.0", ""]
        mtl_path.write_text("\n".join(mtl_lines), encoding="ascii")

        lines = [f"mtllib {mtl_path.name}", "o generated_asset"]
        lines += ["v %.6f %.6f %.6f" % vertex for vertex in self.vertices]
        current_material = ""
        for material, indices in self.faces:
            if material != current_material:
                lines.append(f"usemtl {material}")
                current_material = material
            lines.append("f " + " ".join(str(index) for index in indices))
        path.write_text("\n".join(lines) + "\n", encoding="ascii")


def add_cylinder(obj: ObjWriter, radius: float, y0: float, y1: float,
                 segments: int, material: str) -> None:
    bottom = [obj.vertex(radius * math.cos(i * 2 * math.pi / segments), y0,
                         radius * math.sin(i * 2 * math.pi / segments))
              for i in range(segments)]
    top = [obj.vertex(radius * math.cos(i * 2 * math.pi / segments), y1,
                      radius * math.sin(i * 2 * math.pi / segments))
           for i in range(segments)]
    for i in range(segments):
        j = (i + 1) % segments
        obj.face(material, bottom[i], bottom[j], top[j], top[i])
    obj.face(material, *reversed(bottom))
    obj.face(material, *top)


def add_uv_sphere(obj: ObjWriter, radius: float, center_y: float,
                  rings: int, sectors: int, material: str) -> None:
    rows: list[list[int]] = []
    for ring in range(rings + 1):
        phi = math.pi * ring / rings
        row = []
        for sector in range(sectors):
            theta = 2 * math.pi * sector / sectors
            row.append(obj.vertex(radius * math.sin(phi) * math.cos(theta),
                                  center_y + radius * math.cos(phi),
                                  radius * math.sin(phi) * math.sin(theta)))
        rows.append(row)
    for ring in range(rings):
        for sector in range(sectors):
            nxt = (sector + 1) % sectors
            obj.face(material, rows[ring][sector], rows[ring][nxt],
                     rows[ring + 1][nxt], rows[ring + 1][sector])


def add_box(obj: ObjWriter, x0: float, x1: float, y0: float, y1: float,
            z0: float, z1: float, material: str) -> None:
    v = [obj.vertex(x, y, z) for x, y, z in (
        (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
        (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1))]
    for face in ((0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1),
                 (3, 2, 6, 7), (1, 5, 6, 2), (0, 3, 7, 4)):
        obj.face(material, *(v[index] for index in face))


def generate_player(path: Path) -> None:
    obj = ObjWriter()
    add_cylinder(obj, 0.30, 0.25, 1.15, 8, "shirt")
    add_uv_sphere(obj, 0.20, 1.38, 4, 8, "skin")
    add_box(obj, -0.20, -0.04, 0.0, 0.28, -0.10, 0.10, "shorts")
    add_box(obj, 0.04, 0.20, 0.0, 0.28, -0.10, 0.10, "shorts")
    add_box(obj, -0.18, -0.03, -0.05, 0.08, -0.13, 0.13, "boots")
    add_box(obj, 0.03, 0.18, -0.05, 0.08, -0.13, 0.13, "boots")
    obj.save(path, {
        "shirt": (0.78, 0.08, 0.06),
        "skin": (0.72, 0.42, 0.24),
        "shorts": (0.06, 0.08, 0.12),
        "boots": (0.02, 0.02, 0.02),
    })


def generate_ball(path: Path) -> None:
    obj = ObjWriter()
    add_uv_sphere(obj, 0.14, 0.14, 6, 10, "ball")
    obj.save(path, {"ball": (0.92, 0.92, 0.82)})


def generate_pitch(path: Path) -> None:
    obj = ObjWriter()
    add_box(obj, 0.0, 85.0, -0.04, 0.0, 0.0, 36.0, "grass")
    obj.save(path, {"grass": (0.16, 0.42, 0.12)})


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path,
                        default=Path("assets/3d/generated"))
    args = parser.parse_args()
    generate_player(args.output / "player.obj")
    generate_ball(args.output / "ball.obj")
    generate_pitch(args.output / "pitch.obj")
    print(f"Generated low-poly assets in {args.output}")


if __name__ == "__main__":
    main()
