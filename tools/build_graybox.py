"""Author editable .tscn grayboxes and small original procedural audio assets.

Run from any directory with Python 3. No runtime level generation or dependencies.
The generated scenes are committed sources: edit them in Godot; only rerun this
script when intentionally replacing those edits with this authoring recipe.
"""
from pathlib import Path
import math
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[1]
COLORS = {
    "ground": (0.49, 0.48, 0.42), "wall": (0.63, 0.60, 0.49),
    "light": (0.73, 0.71, 0.61), "dark": (0.32, 0.36, 0.34),
    "trim": (0.47, 0.48, 0.40), "wood": (0.38, 0.32, 0.23),
    "teal": (0.28, 0.47, 0.45), "gold": (0.63, 0.49, 0.27),
    "window": (0.15, 0.20, 0.21), "canopy": (0.49, 0.46, 0.28),
}

def vec(values):
    return "Vector3(%s)" % ", ".join(f"{v:.5f}" for v in values)

class Scene:
    def __init__(self, name):
        self.resources = []
        self.nodes = [f'[node name="{name}" type="Node3D"]']
        self.meshes = {}
        self.shapes = {}
        self.number = 0
        for name, rgb in COLORS.items():
            self.resources.append(f'''[sub_resource type="ShaderMaterial" id="Mat_{name}"]
shader = ExtResource("1")
shader_parameter/tint = Color({rgb[0]}, {rgb[1]}, {rgb[2]}, 1)
shader_parameter/grid_strength = {0.11 if name == 'ground' else 0.045}''')
        for group in ["Architecture", "Cover", "Landmarks", "Spawns", "Locations", "Targets"]:
            self.nodes.append(f'[node name="{group}" type="Node3D" parent="."]')

    def box(self, name, pos, size, mat="wall", group="Architecture", collision=True, rotation=None):
        self.number += 1
        name = f"{name}_{self.number}"
        key = tuple(size)
        if key not in self.meshes:
            mesh = f"Mesh_{len(self.meshes)}"
            self.meshes[key] = mesh
            self.resources.append(f'[sub_resource type="BoxMesh" id="{mesh}"]\nsize = {vec(size)}')
        mesh = self.meshes[key]
        if collision and key not in self.shapes:
            shape = f"Shape_{len(self.shapes)}"
            self.shapes[key] = shape
            self.resources.append(f'[sub_resource type="BoxShape3D" id="{shape}"]\nsize = {vec(size)}')
        body = "StaticBody3D" if collision else "Node3D"
        props = f'position = {vec(pos)}'
        if rotation:
            props += f'\nrotation = {vec(rotation)}'
        if collision:
            props += '\ncollision_layer = 1\ncollision_mask = 2'
        self.nodes.append(f'[node name="{name}" type="{body}" parent="{group}"]\n{props}')
        self.nodes.append(f'''[node name="Mesh" type="MeshInstance3D" parent="{group}/{name}"]
mesh = SubResource("{mesh}")
material_override = SubResource("Mat_{mat}")''')
        if collision:
            self.nodes.append(f'[node name="Collision" type="CollisionShape3D" parent="{group}/{name}"]\nshape = SubResource("{self.shapes[key]}")')

    def label(self, name, text, pos, color="light", size=64):
        rgb = COLORS[color]
        self.nodes.append(f'''[node name="{name}" type="Label3D" parent="Landmarks" groups=["guide"]]
position = {vec(pos)}
billboard = 1
modulate = Color({rgb[0]+0.15}, {rgb[1]+0.15}, {rgb[2]+0.15}, 1)
text = "{text}"
font_size = {size}
pixel_size = 0.009
outline_size = 8
visibility_range_end = 65.0''')

    def spawn(self, name, pos, yaw=0):
        self.nodes.append(f'[node name="{name}" type="Marker3D" parent="Spawns"]\nposition = {vec(pos)}\nrotation = Vector3(0, {yaw}, 0)')

    def location(self, name, title, pos, radius):
        self.nodes.append(f'''[node name="{name}" type="Marker3D" parent="Locations"]
position = {vec(pos)}
metadata/title = "{title}"
metadata/radius = {radius}''')

    def building(self, name, x, z, width, depth, height=6.4, mat="wall"):
        self.box(name, (x, height/2, z), (width, height, depth), mat)
        self.box(name+"Cornice", (x, height-0.25, z), (width+0.3, 0.25, depth+0.3), "light", collision=False)
        self.box(name+"Roof", (x, height+0.05, z), (width+0.15, 0.15, depth+0.15), "trim", collision=False)
        for y in [1.7, 4.6] if height > 5 else [1.7]:
            for offset in range(-int(width/2)+2, int(width/2)-1, 4):
                for side in [-1, 1]:
                    self.box(name+"Window", (x+offset, y, z+side*(depth/2+0.025)), (1.1, 1.5, 0.04), "window", collision=False)
                    self.box(name+"Sill", (x+offset, y-0.8, z+side*(depth/2+0.09)), (1.25, 0.12, 0.18), "light", collision=False)

    def stairs(self, name, x, z, width=2.4, height=3.2, length=7.2, direction=1):
        # Rise toward +Z or -Z. Visual treads sit over a single convex collision ramp.
        steps = 16
        for i in range(steps):
            h = height*(i+1)/steps
            pz = z + direction*(i+0.5)*length/steps
            self.box(name+"Tread", (x, h/2, pz), (width, h, length/steps), "light", collision=False)
        rid = f"Ramp_{self.number}"
        points = [(x-width/2,0,z), (x+width/2,0,z),
                  (x-width/2,0,z+direction*length), (x+width/2,0,z+direction*length),
                  (x-width/2,height,z+direction*length), (x+width/2,height,z+direction*length)]
        flat = ", ".join(str(v) for p in points for v in p)
        self.resources.append(f'[sub_resource type="ConvexPolygonShape3D" id="{rid}"]\npoints = PackedVector3Array({flat})')
        self.nodes.append(f'[node name="{name}Ramp" type="StaticBody3D" parent="Architecture"]\ncollision_layer = 1\ncollision_mask = 2')
        self.nodes.append(f'[node name="Collision" type="CollisionShape3D" parent="Architecture/{name}Ramp"]\nshape = SubResource("{rid}")')

    def target(self, name, x, z, travel=0.0):
        rid = "TargetShape" + name
        self.resources.append(f'[sub_resource type="BoxShape3D" id="{rid}"]\nsize = Vector3(0.65, 1.5, 0.12)')
        self.resources.append(f'[sub_resource type="BoxMesh" id="{rid}Mesh"]\nsize = Vector3(0.65, 1.5, 0.12)')
        self.nodes.append(f'''[node name="{name}" type="StaticBody3D" parent="Targets" groups=["range_targets"]]
position = Vector3({x}, 1.05, {z})
collision_layer = 4
collision_mask = 0
script = ExtResource("2")
travel = {travel}''')
        self.nodes.append(f'[node name="MeshInstance3D" type="MeshInstance3D" parent="Targets/{name}"]\nmesh = SubResource("{rid}Mesh")')
        self.nodes.append(f'[node name="CollisionShape3D" type="CollisionShape3D" parent="Targets/{name}"]\nshape = SubResource("{rid}")')

    def save(self, filename):
        header = f'''[gd_scene load_steps={len(self.resources)+3} format=3]

[ext_resource type="Shader" path="res://shaders/graybox.gdshader" id="1"]
[ext_resource type="Script" path="res://scripts/combat/range_target.gd" id="2"]'''
        (ROOT / "scenes/levels" / filename).write_text(header + "\n\n" + "\n\n".join(self.resources+self.nodes) + "\n")

def town():
    s = Scene("OldQuarter")
    s.box("Ground", (0,-0.5,0), (112,1,96), "ground")
    for x in [-56,56]:
        s.box("Perimeter", (x,3.5,0), (1,7,96), "wall")
    for z in [-48,48]:
        s.box("Perimeter", (0,3.5,z), (112,7,1), "wall")
    for data in [
        ("WestHomes",-44,-30,21,29,7.2,"wall"),
        ("WestStore",-28,8,12,18,6.2,"light"),
        ("NorthBlock",-17,-23,18,12,7.4,"wall"),
        ("SouthStore",-13,26,24,17,5.8,"wall"),
        ("EastStore",26,-2,16,16,7.0,"light"),
        ("EastHomes",45,-31,19,28,8.0,"wall"),
        ("SouthHomes",29,30,25,20,6.8,"light"),
        ("FarSouth",-40,37,24,17,6.8,"wall"),
    ]:
        s.building(*data)
    # Offset gateway and store corner break the otherwise long center sightline.
    for x in [-20,-14]:
        s.box("ArchPillar", (x,2.3,-5), (1.4,4.6,2.0), "light")
        s.box("PillarFoot", (x,0.2,-5), (1.7,0.4,2.3), "trim")
    s.box("ArchLintel", (-17,4.8,-5), (7.4,1.0,2.0), "light")
    s.box("ArchCrown", (-17,5.4,-5), (8,0.25,2.4), "trim", collision=False)
    s.box("MarketPaving", (0,0.015,0), (22,0.03,18), "light", collision=False)
    for x,z in [(-5,-3),(5,4),(-4,6)]:
        s.box("MarketCounter", (x,0.5,z), (3,1,1.4), "wood", "Cover")
        for dx in [-1.5,1.5]:
            for dz in [-0.7,0.7]:
                s.box("CanopyPole", (x+dx,1.4,z+dz), (0.12,2.8,0.12), "wood", "Cover")
        s.box("Canopy", (x,2.8,z), (3.5,0.12,2.3), "canopy", "Cover", rotation=(0,0,0.05))
    s.box("WellBase", (2,0.48,-4), (2.4,0.96,2.4), "trim", "Cover")
    s.box("WellRim", (2,1.02,-4), (2.7,0.12,2.7), "light", "Cover")
    for x,z,w,d in [(-37,8,3,1),(-33,-9,1,4),(12,10,4,1),(37,10,3,1),(-7,-34,4,1),(17,35,1,4)]:
        s.box("LowCover", (x,0.5,z), (w,1,d), "trim", "Cover")
    # Northern courtyard and two independently accessible balcony stairs.
    s.box("Balcony", (6,3.0,-13), (24,0.4,4), "light")
    for x in [-3.8,15.8]:
        s.box("BalconyColumn", (x,1.4,-13), (0.55,2.8,0.55), "trim")
    s.box("BalconyFrontRail", (6,3.65,-10.85), (19,0.9,0.25), "trim")
    s.box("BalconyBackRail", (6,3.65,-15.15), (19,0.9,0.25), "trim")
    s.stairs("WestBalcony", -5, -25, width=2.4, length=10.0)
    s.stairs("EastBalcony", 17, -25, width=2.4, length=10.0)
    # Stair house: enter at ground level from north or east, covered but open on two sides.
    s.box("HouseWestWall", (21,1.65,-28), (0.4,3.3,9), "wall")
    s.box("HouseSouthWall", (26,1.65,-23.7), (10,3.3,0.4), "wall")
    s.box("HouseNorthLeft", (22.7,1.65,-32.3), (3,3.3,0.4), "wall")
    s.box("HouseNorthRight", (29,1.65,-32.3), (4,3.3,0.4), "wall")
    s.box("HouseDoorLintel", (25.5,2.9,-32.3), (2.6,0.8,0.4), "wall")
    s.box("HouseRoof", (26,3.45,-28), (10.4,0.3,9), "trim")
    # South passage with roof and bends; no prone-only path is required to complete a lap.
    s.box("PassageWall", (5,1.5,24), (0.6,3,18), "wall")
    s.box("PassageOpposite", (9,1.5,29), (0.6,3,16), "wall")
    s.box("PassageRoof", (7,3.15,27), (4.7,0.3,10), "trim")
    s.box("PassageCorner", (3,1.5,15), (4.5,3,0.6), "wall")
    # Spawn staging zones and nonfunctional future objective pads.
    for x,mat in [(-45,"teal"),(45,"gold")]:
        s.box("SpawnPad", (x,0.025,10), (8,0.05,8), mat, "Landmarks", False)
    for i in range(5):
        s.spawn(f"West{i+1}", (-46+(i%2)*2,0.1,9+(i//2)*1.8), -math.pi/2)
        s.spawn(f"East{i+1}", (46-(i%2)*2,0.1,9+(i//2)*1.8), math.pi/2)
    s.label("WestSign", "WEST YARD", (-45,3,7), "teal")
    s.label("EastSign", "EAST YARD", (45,3,7), "gold")
    s.label("ArchSign", "ARCH / MARKET", (-17,6.1,-5))
    s.label("CourtyardSign", "COURTYARD", (3,3,-28))
    s.label("BalconySign", "BALCONY", (6,5.0,-13))
    s.label("PassageSign", "SERVICE PASSAGE", (7,4,19))
    for name,title,pos,radius in [
        ("West","WEST YARD",(-45,0,10),12), ("East","EAST YARD",(45,0,10),12),
        ("Market","MARKET",(0,0,0),16), ("Arch","ARCH",(-17,0,-5),7),
        ("Court","COURTYARD",(3,0,-28),18), ("Balcony","BALCONY",(6,3.2,-13),11),
        ("Passage","SERVICE PASSAGE",(7,0,27),14), ("House","STAIR HOUSE",(26,0,-28),8),
    ]:
        s.location(name,title,pos,radius)
    s.save("old_quarter.tscn")

def lab():
    s = Scene("MovementLab")
    s.box("Ground", (0,-0.5,-10), (80,1,100), "ground")
    for x in [-40,40]:
        s.box("Boundary", (x,2.5,-10), (0.5,5,100), "dark")
    for z in [-60,40]:
        s.box("Boundary", (0,2.5,z), (80,5,0.5), "dark")
    s.spawn("Start", (0,0.1,26))
    s.spawn("Range", (26,0.1,5))
    s.spawn("Stairs", (-27,0.1,19))
    s.box("StartPad", (0,0.025,25), (4,0.05,3), "teal", "Landmarks", False)
    s.label("Title", "MOVEMENT LAB", (0,4,28), "light", 88)
    s.label("LaneTitle", "25 m / MOVEMENT", (0,2,-3), "teal")
    for distance in range(0,26,5):
        z = 25-distance
        s.box("LaneStripe", (0,0.012,z), (3,0.024,0.08), "light", "Landmarks", False)
        s.label(f"Meter{distance}", f"{distance} m", (2.5,0.35,z), "light", 32)
    # Two doorway gauges and a roof you can crouch beneath.
    for x,width in [(-9,1.2),(9,1.8)]:
        for offset in [-(width/2+0.35),width/2+0.35]:
            s.box("DoorPost", (x+offset,1.4,14), (0.7,2.8,0.8), "light")
        s.box("DoorLintel", (x,2.5,14), (width+1.4,0.6,0.8), "light")
        s.label(f"Door{str(x).replace('-','N')}", f"{width} m DOOR", (x,3.3,14), "light", 40)
    s.box("CrouchCeiling", (-10,1.52,2), (5,0.25,6), "gold")
    s.box("CrouchWall", (-12.65,0.8,2), (0.3,1.6,6), "dark")
    s.label("CrouchLabel", "1.4 m / CROUCH", (-10,2.5,2), "gold", 44)
    s.box("ProneCeiling", (-10,0.84,-7), (5,0.25,5), "gold")
    s.label("ProneLabel", "0.7 m / PRONE", (-10,2.2,-7), "gold", 44)
    for x,height in [(8,0.9),(13,1.1),(18,2.2)]:
        s.box("CoverHeight", (x,height/2,-6), (3,height,0.7), "trim", "Cover")
        s.label(f"Cover{x}", f"{height} m", (x,height+0.7,-6), "light", 38)
    for index,angle in enumerate([15,30,45]):
        x = -30+index*8
        length = 6.0
        height = math.tan(math.radians(angle))*length
        s.stairs(f"Slope{angle}", x, -13, width=4, height=height, length=length, direction=-1)
        # Cover the visual stairs with a continuous tilted ramp surface.
        diagonal = math.sqrt(length*length+height*height)
        s.box("RampSurface", (x,height/2+0.012,-16), (4,0.02,diagonal), "teal", collision=False, rotation=(math.radians(angle),0,0))
        s.box("RampLanding", (x,height-0.15,-20.5), (4,0.3,3), "light")
        s.label(f"Slope{angle}Label", f"{angle}° SLOPE", (x,1,-11), "teal", 42)
    s.stairs("TestStairs", -27, 17, width=2.4, height=3.2, length=7.2, direction=-1)
    s.box("StairLanding", (-27,3.05,8), (5,0.3,3.6), "light")
    s.box("StairBackWall", (-27,4.6,6.1), (5.5,3,0.3), "wall")
    s.label("StairLabel", "STAIRS / CAMERA", (-27,5,11), "light", 46)
    s.box("CornerWall", (9,1.8,23), (5,3.6,0.4), "wall")
    s.box("CornerReturn", (11.3,1.8,25.5), (0.4,3.6,5), "wall")
    s.label("CornerLabel", "LEAN / CORNER", (10,4.3,23), "light", 42)
    s.box("RangePad", (26,0.015,5), (4,0.03,2), "gold", "Landmarks", False)
    s.label("RangeLabel", "RIFLE RANGE / R TO RELOAD", (27,3,7), "gold", 45)
    for distance,x in [(10,23),(25,27),(50,32)]:
        s.target(f"Target{distance}", x, 5-distance)
        s.label(f"TargetLabel{distance}", f"{distance} m", (x,2.7,5-distance), "gold", 40)
    s.target("MovingTarget", 25, -30, 2.5)
    s.box("RangeBackstop", (27,3,-49), (20,6,1), "dark")
    for name,pos in [("MOVEMENT LANE",(0,0,15)),("CLEARANCE",(-10,0,0)),("RIFLE RANGE",(27,0,-10)),("SLOPES",(-23,0,-16)),("STAIRS",(-27,0,13))]:
        s.location(name.replace(' ',''),name,pos,14)
    s.save("movement_lab.tscn")

def audio():
    rng = random.Random(17)
    for name,duration in [("step",0.13),("rifle",0.23)]:
        rate = 22050
        samples = []
        prev = 0.0
        for i in range(int(rate*duration)):
            t = i/rate
            noise = rng.uniform(-1,1)
            prev = prev*0.65+noise*0.35
            if name == "rifle":
                sample = (noise*0.65+math.sin(t*math.tau*95)*0.35)*math.exp(-t*26)
            else:
                sample = (prev*0.75+math.sin(t*math.tau*105)*0.25)*math.exp(-t*40)
            sample *= min(1.0,t/0.001)
            samples.append(struct.pack('<h',int(max(-1,min(1,sample))*26000)))
        with wave.open(str(ROOT/'audio'/f'{name}.wav'),'wb') as f:
            f.setnchannels(1)
            f.setsampwidth(2)
            f.setframerate(rate)
            f.writeframes(b''.join(samples))

if __name__ == '__main__':
    town()
    lab()
    audio()
    print('Wrote editable Old Quarter and Movement Lab scenes and two original sound effects.')
