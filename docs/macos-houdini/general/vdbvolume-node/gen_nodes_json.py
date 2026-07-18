import json, collections, sys

NODES = sys.argv[1]     # moonray_nodes.json (in/out)
SHADER = sys.argv[2]    # VdbVolume.json

sj = json.load(open(SHADER))["scene_classes"]["VdbVolume"]
attrs = sj["attributes"]

TYPE_MAP = {"String":"String","Int":"Int","Float":"Float","Rgb":"Rgb"}

def houdini_label(name):
    return " ".join(w.capitalize() for w in name.split("_"))

parms = collections.OrderedDict()
for name in sorted(attrs, key=lambda n: attrs[n]["order"]):
    a = attrs[name]
    entry = collections.OrderedDict()
    entry["moonray_name"] = name
    entry["moonray_type"] = TYPE_MAP[a["attrType"]]
    dv = a["default"]
    entry["default_value"] = dv if isinstance(dv, list) else [dv]
    entry["houdini_name"] = name
    entry["houdini_label"] = a.get("metadata", {}).get("label") or houdini_label(name)
    entry["order"] = a["order"]
    if "aliases" in a:
        entry["aliases"] = a["aliases"]
    if "bindable" in a:
        entry["bindable"] = a["bindable"]
    entry["help"] = a.get("metadata", {}).get("comment", "")
    if "enum" in a:
        en = a["enum"]
        # order menu by value
        items = sorted(((k, v) for k, v in en.items()), key=lambda kv: kv[1])
        entry["menu"] = [k for k, _ in items]
        entry["menu_values"] = [str(v) for _, v in items]
    parms[name] = entry

# Extract folder grouping from shader interface
grouping = sj.get("grouping", {})
folders_sorted = grouping.get("order", [])
folders_with_parms = grouping.get("groups", {})

node = collections.OrderedDict()
node["moonray_name"] = "VdbVolume"
node["moonray_type"] = "Volume"
node["parms"] = parms
node["folders_sorted"] = folders_sorted
node["folders_with_parms"] = folders_with_parms

data = json.load(open(NODES), object_pairs_hook=collections.OrderedDict)
data["VdbVolume"] = node
json.dump(data, open(NODES, "w"), indent=1)
print("added VdbVolume;", len(data), "top-level entries")
