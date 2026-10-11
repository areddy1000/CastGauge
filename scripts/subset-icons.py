import sys
from fontTools.ttLib import TTFont
from fontTools import subset

src, dst = sys.argv[1], sys.argv[2]
names = set(sys.argv[3].split())
font = TTFont(src)
cmap = font.getBestCmap()
char_of = {glyph: chr(code) for code, glyph in cmap.items()}

kept_outputs = set()
for lookup in font["GSUB"].table.LookupList.Lookup:
    for sub in lookup.SubTable:
        if lookup.LookupType == 7:
            sub = sub.ExtSubTable
        if not hasattr(sub, "ligatures"):
            continue
        pruned = {}
        for first, ligatures in sub.ligatures.items():
            keep = [l for l in ligatures
                    if "".join(char_of.get(g, "\0") for g in [first] + l.Component) in names]
            if keep:
                pruned[first] = keep
                kept_outputs.update(l.LigGlyph for l in keep)
        sub.ligatures = pruned
print("ligatures kept:", len(kept_outputs), "of", len(names))

letters = sorted({c for n in names for c in n})
options = subset.Options()
options.layout_features = ["*"]
options.notdef_outline = True
subsetter = subset.Subsetter(options)
subsetter.populate(glyphs=sorted(kept_outputs), unicodes=[ord(c) for c in letters])
subsetter.subset(font)
font.save(dst)
