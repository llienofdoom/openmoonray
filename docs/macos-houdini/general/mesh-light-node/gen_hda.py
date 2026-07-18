# hython docs/research/mesh-light-node/gen_hda.py <output.hda>
#
# Builds the "Moonray Mesh Light" LOP HDA. The node authors a SphereLight
# carrier prim (moonray:class="MeshLight" + inputs:radius=0.01 + moonray:geometry
# + inputs:geometry rel), ALWAYS hides the emitter (required: MoonRay rejects an
# emitter that is still in the render layer), and generically authors the full
# MeshLight parameter set loaded from moonray_MeshLight.ds via each param's
# "Set or Create / Block / Do Nothing" control companion.
import hou, sys, loputils

out_hda = sys.argv[1]
DS = "/Applications/MoonRay/installs/openmoonray-houdini/plugin/houdini/soho/parameters/moonray_MeshLight.ds"

stage = hou.node("/stage")
lop = stage.createNode("pythonscript", "moonray_mesh_light")

# --- cook code: author the carrier prim + generically author the .ds params ---
cook = r'''
from pxr import Usd, UsdGeom, Sdf
node = hou.pwd(); stage = node.editableStage()
USD_TYPE = {
    "bool": Sdf.ValueTypeNames.Bool, "float": Sdf.ValueTypeNames.Float,
    "int": Sdf.ValueTypeNames.Int, "token": Sdf.ValueTypeNames.Token,
    "string": Sdf.ValueTypeNames.String, "color3f": Sdf.ValueTypeNames.Color3f,
    "float2": Sdf.ValueTypeNames.Float2, "float3": Sdf.ValueTypeNames.Float3,
    "vector3f": Sdf.ValueTypeNames.Vector3f, "asset": Sdf.ValueTypeNames.Asset,
}
AUTHOR_MODES = ("set", "setexisting", "add", "multiply")
# moonray:on is driven via the carrier prim's visibility below, not authored:
# the delegate skips the moonray:on attr (Light.cc:224) and derives on/off from
# the light prim's visibility + intensity>0.
SKIP = ("moonray:class", "moonray:geometry", "inputs:geometry", "inputs:radius", "moonray:on")

lightpath = node.evalParm("lightpath") or "/lights/meshlight1"
emitter   = node.evalParm("geometry")

light = stage.DefinePrim(lightpath, "SphereLight")
light.CreateAttribute("moonray:class", Sdf.ValueTypeNames.Token, True, Sdf.VariabilityUniform).Set("MeshLight")
light.CreateAttribute("inputs:radius", Sdf.ValueTypeNames.Float, False).Set(0.01)
if emitter:
    light.CreateAttribute("moonray:geometry", Sdf.ValueTypeNames.String, True).Set(emitter)
    light.CreateRelationship("inputs:geometry").SetTargets([Sdf.Path(emitter)])
    em = stage.GetPrimAtPath(emitter)
    if em and em.IsValid():
        UsdGeom.Imageable(em).MakeInvisible()   # required: emitter must leave the render layer

# On/off: the delegate ignores moonray:on, so drive the CARRIER light prim's
# visibility instead (invisible => light off).
if not node.evalParm(hou.text.encode("moonray:on")):
    UsdGeom.Imageable(light).MakeInvisible()

for pt in node.parmTuples():
    nm = pt.name()
    if not nm.startswith("xn__") or "_control_" in nm:
        continue
    attr = hou.text.decode(nm)
    if ";" in attr or attr.count(":") > 1 or attr in SKIP:
        continue
    cp = node.parm(hou.text.encode(attr + "_control"))
    if not cp or cp.eval() not in AUTHOR_MODES:
        continue
    ut = pt.parmTemplate().tags().get("usdvaluetype")
    if ut not in USD_TYPE:
        continue
    v = pt.eval(); v = v[0] if len(v) == 1 else tuple(v)
    light.CreateAttribute(attr, USD_TYPE[ut], True).Set(v)
'''
lop.parm("python").set(cook)

# --- interface: the full MeshLight .ds param UI + our two params on top ---
loputils.addDialogScriptFolder(DS, lop, "Moonray")   # Properties/Map two-tab param UI

g = lop.parmTemplateGroup()
# our params at the very top
g.insertBefore(g.entries()[0],
               hou.StringParmTemplate("lightpath", "Light Path", 1,
                                      default_value=("/lights/meshlight1",)))
emit = hou.StringParmTemplate(
    "geometry", "Emitter Geometry", 1, default_value=("",),
    tags={"script_action": "import loputils\nloputils.selectPrimsInParm(kwargs, False)",
          "script_action_help": "Select the emitter mesh in the Scene Graph Tree.",
          "script_action_icon": "BUTTONS_reselect",
          "sidefx::usdpathtype": "prim"})
g.insertAfter("lightpath", emit)

# Default the common params to "Set or Create" so they author out of the box
# (user shouldn't have to flip each control companion).
for attr in ("inputs:color", "inputs:intensity", "inputs:exposure", "moonray:visible_in_camera"):
    cp = g.find(hou.text.encode(attr + "_control"))
    if cp:
        cp.setDefaultValue(("set",))
        g.replace(hou.text.encode(attr + "_control"), cp)

# Origin-dot fix (hypothesis): default moonray:visible_in_camera to "force off"
# so the (origin-located, xform-less) light source isn't camera-visible. The
# emitter is hidden anyway, so the light itself should never show in-camera.
vc = g.find(hou.text.encode("moonray:visible_in_camera"))
if vc:
    vc.setDefaultValue(("force off",))
    g.replace(hou.text.encode("moonray:visible_in_camera"), vc)

# hide the redundant .ds inputs:geometry value+control (we drive geometry via 'geometry'),
# and the moonray:on CONTROL companion (on/off is driven by the On checkbox -> prim
# visibility, so the control menu is meaningless). KEEP the On checkbox visible.
for base in ("inputs:geometry", "inputs:geometry_control", "moonray:on_control"):
    pt = g.find(hou.text.encode(base))
    if pt:
        pt.hide(True)
        g.replace(hou.text.encode(base), pt)
# hide the underlying pythonscript LOP's own params (the raw cook code + state toggle)
# so users only see the Moonray Mesh Light interface.
for base in ("python", "maintainstate"):
    pt = g.find(base)
    if pt:
        pt.hide(True)
        g.replace(base, pt)
lop.setParmTemplateGroup(g)

# --- digital asset ---
# Per the earlier finding, a pre-set parm template group does NOT survive
# createDigitalAsset(); capture the FULL group and re-apply on the definition
# AFTER conversion.
full = lop.parmTemplateGroup()
asset = lop.createDigitalAsset(
    name="moonray::mesh_light::1.0", hda_file_name=out_hda,
    description="Moonray Mesh Light", min_num_inputs=0, max_num_inputs=1)
defn = asset.type().definition()
defn.setParmTemplateGroup(full)
defn.setIcon("SOP_grid")

# --- TAB-menu placement: put it under "Lights" (LOP context), not Digital Assets ---
tools_shelf = '''<?xml version="1.0" encoding="UTF-8"?>
<shelfDocument>
  <tool name="$HDA_DEFAULT_TOOL" label="$HDA_LABEL" icon="$HDA_ICON">
    <toolMenuContext name="viewer">
      <contextNetType>LOP</contextNetType>
    </toolMenuContext>
    <toolMenuContext name="network">
      <contextOpType>$HDA_TABLE_AND_NAME</contextOpType>
    </toolMenuContext>
    <toolSubmenu>Lights</toolSubmenu>
    <script scriptType="python"><![CDATA[import loptoolutils
loptoolutils.genericTool(kwargs, '$HDA_NAME')]]></script>
  </tool>
</shelfDocument>'''
defn.addSection("Tools.shelf", tools_shelf)
defn.save(out_hda)
print("WROTE", out_hda)
