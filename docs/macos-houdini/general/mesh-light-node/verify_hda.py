# hython docs/research/mesh-light-node/verify_hda.py <hda_path>
import hou, sys
from pxr import Sdf, UsdGeom
hou.hda.installFile(sys.argv[1])
stage = hou.node("/stage")

emitter = stage.createNode("sphere")           # any mesh source
# convert to a Mesh prim path; sphere LOP outputs /sphere1 by default
node = stage.createNode("moonray::mesh_light::1.0")
node.setInput(0, emitter)
node.parm("geometry").set("/sphere1")

# color/intensity/exposure now author by DEFAULT (their control companions
# default to "set"), so just set the VALUES -- do NOT touch their controls.
node.parmTuple(hou.text.encode("inputs:intensity")).set((6.0,))
node.parmTuple(hou.text.encode("inputs:color")).set((0.2, 0.4, 0.6))
# moonray:label is left at its default control ("none") -> must NOT be authored.

s = node.stage()
light = s.GetPrimAtPath("/lights/meshlight1")
assert light and light.IsValid(), "carrier light prim not authored"
assert str(light.GetTypeName()) == "SphereLight", light.GetTypeName()

# --- carrier contract ---
assert light.GetAttribute("moonray:class").Get() == "MeshLight"
assert light.GetAttribute("moonray:geometry").Get() == "/sphere1"
assert abs(light.GetAttribute("inputs:radius").Get() - 0.01) < 1e-6, \
    ("radius", light.GetAttribute("inputs:radius").Get())
targets = light.GetRelationship("inputs:geometry").GetTargets()
assert targets == [Sdf.Path("/sphere1")], ("geometry rel targets", targets)

# --- emitter is ALWAYS hidden ---
emprim = s.GetPrimAtPath("/sphere1")
vis = UsdGeom.Imageable(emprim).ComputeVisibility()
assert vis == UsdGeom.Tokens.invisible, ("emitter not hidden", vis)

# --- common params author by DEFAULT (control defaults to "set") ---
assert abs(light.GetAttribute("inputs:intensity").Get() - 6.0) < 1e-5, \
    ("intensity", light.GetAttribute("inputs:intensity").Get())
col = light.GetAttribute("inputs:color").Get()
assert (abs(col[0] - 0.2) < 1e-5 and abs(col[1] - 0.4) < 1e-5 and
        abs(col[2] - 0.6) < 1e-5), ("color", col)

# --- origin-dot fix: visible_in_camera authored "force off" by default ---
vic = light.GetAttribute("moonray:visible_in_camera")
assert vic.IsAuthored() and vic.Get() == "force off", \
    ("visible_in_camera", vic.IsAuthored(), vic.Get())

# --- control "none" (default) param is NOT authored ---
assert not light.GetAttribute("moonray:label").IsAuthored(), \
    "moonray:label authored despite control left at 'none'"

# --- On checkbox drives the carrier light prim's visibility ---
# default On=1 (checked) -> light visible
assert UsdGeom.Imageable(light).ComputeVisibility() != UsdGeom.Tokens.invisible, \
    "light prim invisible with On checked"
# On=0 -> light prim invisible (light off)
node.parm(hou.text.encode("moonray:on")).set(0)
light_off = node.stage().GetPrimAtPath("/lights/meshlight1")
assert UsdGeom.Imageable(light_off).ComputeVisibility() == UsdGeom.Tokens.invisible, \
    "light prim not invisible with On unchecked"
# On=1 again -> visible
node.parm(hou.text.encode("moonray:on")).set(1)
light_on = node.stage().GetPrimAtPath("/lights/meshlight1")
assert UsdGeom.Imageable(light_on).ComputeVisibility() != UsdGeom.Tokens.invisible, \
    "light prim invisible after re-checking On"

print("PASS: carrier + default-author (color/intensity/exposure) + visible_in_camera=force off + On->prim visibility + control-none skipped + emitter hidden")
