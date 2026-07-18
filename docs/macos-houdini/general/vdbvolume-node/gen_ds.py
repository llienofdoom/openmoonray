import sys, hou

OUT = sys.argv[1]

FULL_MENU = '''            menujoin {
                "set"           "![BUTTONS_set_or_create]Set or Create"
                "setexisting"   "![BUTTONS_set_if_exists]Set if Exists"
                "add"           "![BUTTONS_set_add]Add if Exists"
                "multiply"      "![BUTTONS_set_multiply]Multiply if Exists"
                "block"         "![BUTTONS_set_block]Block"
                "none"          "![BUTTONS_set_nothing]Do Nothing"
            }'''
SHORT_MENU = '''            menujoin {
                "set"           "![BUTTONS_set_or_create]Set or Create"
                "setexisting"   "![BUTTONS_set_if_exists]Set if Exists"
                "block"         "![BUTTONS_set_block]Block"
                "none"          "![BUTTONS_set_nothing]Do Nothing"
            }'''

def enc(attr, control=False):
    n = "inputs:" + attr + ("_control" if control else "")
    return hou.text.encode(n)

def control_parm(attr, short=False):
    return f'''        parm {{
            name    "{enc(attr, True)}"
            label   "inputs:{attr}"
            type    string
            default {{ "none" }}
{SHORT_MENU if short else FULL_MENU}
            parmtag {{ "sidefx::look" "icon" }}
        }}'''

def value_parm(attr, label, usdtype, dstype, default, help_, *, size=None, menu=None, ranged=True, rng="0 10"):
    ctrl = enc(attr, True)
    lines = [f'''        parm {{
            name    "{enc(attr)}"
            label   "{label}"
            type    {dstype}''']
    if size:
        lines.append(f"            size    {size}")
    lines.append(f"            default {{ {default} }}")
    if help_:
        lines.append(f'            help    "{help_}"')
    lines.append(f'            disablewhen "{{ {ctrl} == block }} {{ {ctrl} == none }}"')
    if menu:
        lines.append("            menu {\n" + menu + "\n            }")
    if ranged:
        lines.append("            range   { " + rng + " }")
    lines.append(f'            parmtag {{ "usdvaluetype" "{usdtype}" }}')
    lines.append("        }")
    return "\n".join(lines)

BAKE_HELP = ('Method to specify grid resolution of baked density grid.  Choices are:'
             '\\n\t\t\\"default\\": For shaders that are bound to vdb volumes, use vdb resolution.'
             '\\n\t\t\t\t\t\tFor shaders that are bounds to mesh geometries use 100 divisions'
             '\\n\t\t\\"divisions\\": Specify number of divisions.'
             '\\n\t\t\\"voxel size\\": Specify voxel size.')
RES_MENU = ('                "default"       "Default"\n'
            '                "divisions"     "Divisions"\n'
            '                "voxel size"    "Voxel Size"')

out = []
out.append('#include "$HFS/houdini/soho/parameters/CommonMacros.ds"')
out.append("{")
out.append("    name\tparameters")
# --- Volume Baking folder ---
out.append('    group {\n        name    "folder"\n        label   "Volume Baking"\n')
out.append(control_parm("bake_resolution_mode"))
out.append(value_parm("bake_resolution_mode", "Bake Resolution Mode", "token", "string",
                      '"default"', BAKE_HELP, menu=RES_MENU, ranged=False))
out.append(control_parm("bake_divisions"))
out.append(value_parm("bake_divisions", "Bake Divisions", "int", "integer",
                      '"100"', "Divide widest axis by this many divisions"))
out.append(control_parm("bake_voxel_size"))
out.append(value_parm("bake_voxel_size", "Bake Voxel Size", "float", "float",
                      '"10"', "Size of voxel in world space"))
out.append("    }\n")
# --- Volume folder ---
out.append('    group {\n        name    "folder2"\n        label   "Volume"\n')
out.append(control_parm("surface_opacity_threshold"))
out.append(value_parm("surface_opacity_threshold", "Surface Opacity Threshold", "float", "float",
                      '"0.5"', "Accumulated opacity that's considered the 'surface' for computing surface position and Z"))
out.append(control_parm("opacity_gain_mult"))
out.append(value_parm("opacity_gain_mult", "Opacity Gain Mult", "color3f", "color",
                      '"1" "1" "1"', "A multiplier applied to the volume density", size=3))
out.append(control_parm("color_mult"))
out.append(value_parm("color_mult", "Color Mult", "color3f", "color",
                      '"1" "1" "1"', "The albedo of the volume", size=3))
out.append(control_parm("incandescence_gain_mult"))
out.append(value_parm("incandescence_gain_mult", "Incandescence Gain Mult", "color3f", "color",
                      '"1" "1" "1"', "A multiplier applied to the volume emission", size=3))
out.append(control_parm("anisotropy"))
out.append(value_parm("anisotropy", "Anisotropy", "float", "float", '"0"',
                      "Value in the interval [-1,1] that defines how foward (1) or backward (-1) scattering the volume is.  A value of 0.0 indicates an isotropic volume.",
                      rng="-1 1"))
out.append("    }\n")
def dedent4(s):
    """Dedent a control_parm/value_parm block by 4 spaces (in-folder depth ->
    top-level depth), matching BaseVolume's top-level label parm indentation."""
    return "\n".join(line[4:] if line.startswith("    ") else line
                     for line in s.split("\n"))

# --- top-level label (string -> short menu) ---
out.append(dedent4(control_parm("label", short=True)))
out.append(dedent4(value_parm("label", "Label", "string", "string", '""',
                      "label used in light aovs", ranged=False)))
out.append("}")

open(OUT, "w").write("\n".join(out) + "\n")
print("wrote", OUT)
