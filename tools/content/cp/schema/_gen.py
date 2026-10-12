import json
D="https://json-schema.org/draft/2020-12/schema"
def S(title, desc, props, req, extra=True, defs=None):
    s={"$schema":D,"$id":f"panopticon/cp/{title}.json","title":title,"description":desc,"type":"object",
       "properties":props,"required":req,"additionalProperties":extra}
    if defs: s["$defs"]=defs
    return s
LID={"type":"string","pattern":"^[LM][0-9]+[a-z]?$"}
NUM={"type":"number"}; STR={"type":"string"}; NSTR={"type":["string","null"]}
SHA1={"type":"string","pattern":"^[0-9a-f]{40}$"}
interp={"type":"array","items":{"type":"object","properties":{"field":STR,"why":STR},"required":["field","why"],"additionalProperties":False}}
game={"type":["object","null"],"properties":{
  "map":STR,"pov":{"type":"string","enum":["guard","runner","prisoner","free","spectator","orbit","drone","other"]},
  "hud":STR,"stage":STR,"set":STR,"bots":{"type":"integer","minimum":0},"ref":STR,"humans":{"type":"string","enum":["on","off"]},
  "seconds":NUM,"seed":{"type":["integer","null"]},"tape":NSTR,"look_override":{"type":"boolean"},"keep_audio":{"type":"boolean"},
  "args":{"type":"array","items":STR}},"required":["map","pov","stage"],"additionalProperties":True}
editor={"type":["object","null"],"properties":{"ref":STR,"scene":STR,"dock":STR,"camera":STR,"seconds":NUM},"required":["ref","scene"],"additionalProperties":True}
online={"type":["object","null"],"properties":{"url":STR,"from":NUM,"to":NUM,"find":STR,"name":STR},"additionalProperties":True}
card={"type":["object","null"],"properties":{"kind":{"type":"string","enum":["comment","title","text","black"]},"handle":STR,"text":STR,"seconds":NUM},"required":["kind"],"additionalProperties":True}
box={"type":"object","properties":{"x":NUM,"y":NUM,"w":NUM,"h":NUM},"required":["x","y","w","h"],"additionalProperties":False}
overlay={"type":"object","properties":{
  "kind":{"type":"string","enum":["comment_card","text","image","letterbox","arrow","logo"]},
  "handle":STR,"text":STR,"path":STR,
  "in":{"type":"string","description":"line_start | line_end | word:<word> | t:<seconds>"},
  "out":{"type":"string"},"placeholder":{"type":"boolean"},"box":{"$ref":"#/$defs/box"}},"required":["kind","in","out"],"additionalProperties":True}
beat={"type":"object","properties":{"word":STR,"event":{"type":"string","enum":["hit","shove","death","spawn","fire","land","cut","other"]},"tolerance_s":{"type":"number","default":0.034}},"required":["word","event"],"additionalProperties":True}
cand={"type":"object","properties":{"inventory_id":{"type":"integer"},"path":STR,"sha1":STR,"in":NUM,"len":NUM,
  "rule":{"type":"string","enum":["explicit","capture_key","description"]},"fit":{"type":"number","description":"0-1 fit of clip to note"},
  "uses":{"type":"integer","description":"prior uses in other cuts"},"score":{"type":"number","description":"fit minus variety penalty"},
  "from_project":STR,"from_line":STR,"why":STR},"required":["path","in","len","rule","score"],"additionalProperties":True}
reuse={"oneOf":[{"type":"null"},cand]}
SOURCES=["game","editor","online","card","black","reuse"]
FLAGS=["refilm","look_override","freeze_waive","keep_audio","letterbox"]
specline={"type":"object","properties":{
  "id":LID,"kind":{"type":"string","enum":["line","music"]},"text":{"type":"string","description":"voice text verbatim; empty for M lines"},
  "note":{"type":"string","description":"Ryan's shot note verbatim (braces stripped, multiple notes joined by ' | ')"},
  "pauses":{"type":"array","items":{"type":"object","properties":{"at_char":{"type":"integer"},"seconds":{"type":["number","null"]}},"additionalProperties":True}},
  "flags":{"type":"array","items":{"type":"string","enum":FLAGS}},
  "src_line":{"type":"integer"},"auto_id":{"type":"boolean","description":"true when the parser numbered the line (no L/M prefix in the md)"}},
  "required":["id","kind","text","note","src_line"],"additionalProperties":True}
header={"type":"object","properties":{
  "kind":{"type":"string","enum":["short","devlog","trailer"]},"music":NSTR,"captions":{"type":"string","enum":["pop","stack","none"]},
  "base":NSTR,"cutoff":NSTR,"voice":{"type":"string","enum":["andrew","ryan","none"]},"tag":NSTR},"additionalProperties":True}
gate={"type":"object","properties":{"pass":{"type":"boolean"},"reason":STR},"required":["pass","reason"]}
schemas={}
schemas["spec"]=S("spec","content plan: deterministic parse of tools/content/projects/<name>.md",
 {"name":STR,"src":STR,"src_sha1":SHA1,"header":header,"lines":{"type":"array","items":specline,"minItems":1},
  "warnings":{"type":"array","items":STR}},["name","src","header","lines"])
shotrow={"type":"object","properties":{
  "line":LID,"text":STR,"note":STR,"source":{"type":"string","enum":SOURCES},
  "game":game,"editor":editor,"online":online,"card":card,
  "overlays":{"type":"array","items":overlay},"beats":{"type":"array","items":beat},
  "min_seconds":{"oneOf":[{"type":"number"},{"const":"voice"}]},
  "continuity":{"type":["string","null"],"description":"same_take_as:<id> | null"},
  "flags":{"type":"array","items":STR},"interpreted":interp},
  "required":["line","text","note","source","overlays","beats","interpreted"],"additionalProperties":True}
schemas["shots"]=S("shots","LLM translation of spec.json into machine shot rows; one row per spec line",
 {"name":STR,"spec_sha1":STR,"rows":{"type":"array","items":shotrow}},["name","rows"],defs={"box":box})
planline={"type":"object","properties":{
  "id":LID,"text":STR,"note":STR,"source":{"type":"string","enum":SOURCES},
  "action":{"type":"string","enum":["reuse","capture","editor","fetch","card","black"]},
  "reuse":reuse,"candidates":{"type":"array","items":cand,"description":"ranked inventory candidates, best first"},
  "game":game,"editor":editor,"online":online,"card":card,
  "overlays":{"type":"array","items":overlay},"beats":{"type":"array","items":beat},
  "continuity":{"type":["string","null"]},"min_seconds":{"oneOf":[{"type":"number"},{"const":"voice"}]},
  "flags":{"type":"array","items":STR},"interpreted":interp,
  "match":{"type":"object","description":"what each inventory rule found, for G2","properties":{
     "explicit":{"type":["object","null"]},"capture_key":{"type":["object","null"]},"description":{"type":["object","null"]}},"additionalProperties":True}},
  "required":["id","text","note","source","action","reuse","overlays","beats"],"additionalProperties":True}
schemas["plan"]=S("plan","content plan output: every line with its action; consumed by capture, render, verify",
 {"name":STR,"kind":{"type":"string","enum":["short","devlog","trailer"]},"aspect":{"type":"array","items":{"type":"integer"},"minItems":2,"maxItems":2},
  "fps":{"const":60},"cutoff":NSTR,"base":NSTR,"captions":{"type":"string","enum":["pop","stack","none"]},"music":NSTR,
  "counts":{"type":"object","additionalProperties":{"type":"integer"}},
  "lines":{"type":"array","items":planline},
  "gates":{"type":"object","properties":{"G1":{"$ref":"#/$defs/gate"},"G2":{"$ref":"#/$defs/gate"}},"additionalProperties":True}},
 ["name","kind","aspect","fps","lines"],defs={"box":box,"gate":gate})
schemas["take"]=S("take","capture output manifest per take (WP2)",
 {"line":LID,"path":STR,"w":{"type":"integer"},"h":{"type":"integer"},"fps":NUM,"commit":STR,"args":{"type":"array","items":STR},
  "seed":{"type":["integer","null"]},"t0":NUM,"t1":NUM,
  "map":STR,"pov":STR,"stage":STR,"set":STR,"bots":{"type":"integer"},"look":STR,
  "events":{"type":"array","items":{"type":"object","properties":{"t":NUM,"kind":STR,"who":STR},"required":["t","kind"]}},
  "light":{"type":"object","properties":{"exposure":NUM,"ambient":NUM,"sky":NUM,"look":STR}},
  "clip_events":{"type":"array","items":{"type":"object","properties":{"t":NUM,"what":STR},"required":["t","what"]}},
  "gates":{"type":"object","additionalProperties":gate}},
 ["line","path","w","h","fps","commit","t0","t1"])
words={"type":"array","items":{"type":"object","properties":{"w":STR,"t0":NUM,"t1":NUM},"required":["w","t0","t1"]}}
schemas["voice_manifest"]=S("voice_manifest","voice/manifest.json (WP3)",
 {"engine":{"type":"string","enum":["edge-tts","ryan"]},"voice":STR,"rate":STR,"endpoint":STR,
  "lines":{"type":"object","additionalProperties":{"type":"object","properties":{"wav":STR,"dur":NUM,"words":words},"required":["wav","dur","words"]}}},
 ["engine","voice","rate","lines"])
schemas["words"]={"$schema":D,"$id":"panopticon/cp/words.json","title":"words","description":"voice/words.json: line id -> word timings, seconds from line start",
 "type":"object","additionalProperties":words}
schemas["edl"]=S("edl","render output edit list (WP3)",
 {"lines":{"type":"array","items":{"type":"object","properties":{"id":LID,"start":NUM,"dur":NUM,
   "parts":{"type":"array","items":{"type":"object","properties":{"path":STR,"sha1":STR,"in":NUM,"len":NUM,"speed":{"const":1.0}},"required":["path","in","len","speed"]}},
   "overlays":{"type":"array","items":{"type":"object","properties":{"kind":STR,"box":{"$ref":"#/$defs/box"},"t0":NUM,"t1":NUM},"required":["kind","box","t0","t1"]}},
   "captions":{"type":"array","items":{"type":"object","properties":{"text":STR,"box":{"$ref":"#/$defs/box"},"t0":NUM,"t1":NUM},"required":["text","box","t0","t1"]}},
   "beats":{"type":"array","items":{"type":"object","properties":{"word":STR,"t_word":NUM,"t_event":NUM}}}},"required":["id","start","dur","parts"]}},
  "master":STR,"final":STR},["lines"],defs={"box":box})
schemas["prov"]=S("prov","<file>.prov.json sidecar on every output",
 {"inputs":{"type":"array","items":STR,"description":"sha1 of each input"},"input_paths":{"type":"array","items":STR},
  "encoder":STR,"lossless":{"type":"boolean"},"tool":STR,"version":STR,"commit":STR,"sha1":STR},["inputs","encoder","lossless","tool","version"])
schemas["review"]=S("review","Gemini review (WP4)",
 {"model":STR,"fps":NUM,"lines":{"type":"array","items":{"type":"object","properties":{"id":LID,"heard":STR,"seen":STR,
   "matches_note":{"type":"string","enum":["yes","partly","no"]},"defects":{"type":"array","items":STR},"why":STR},"required":["id","matches_note","defects"]}},
  "overall_defects":{"type":"array","items":STR}},["model","lines","overall_defects"])
schemas["verify"]=S("verify","gate results (WP4 runner); each gate pass/fail + one-line reason",
 {"gates":{"type":"object","patternProperties":{"^G[0-9]+$":{"type":"object","properties":{"pass":{"type":"boolean"},"reason":STR,"lines":{"type":"object"}},"required":["pass","reason"]}}},
  "pass":{"type":"boolean"}},["gates","pass"])
schemas["inventory_row"]=S("inventory_row","one row of inventory.sqlite table clips (WP1); every take, line clip and cut on PC and Mac",
 {"id":{"type":"integer"},"host":{"type":"string","enum":["pc","mac"]},"path":STR,"sha1":STR,"size":{"type":"integer"},"mtime":NUM,
  "duration":NUM,"w":{"type":"integer"},"h":{"type":"integer"},"fps":NUM,
  "codec":STR,"lossless":{"type":"boolean"},"project":STR,"version":NSTR,"line":NSTR,"line_text":NSTR,
  "role":{"type":"string","enum":["take","line","final","external","other"]},
  "commit":NSTR,"date":NSTR,"map":NSTR,"pov":NSTR,"stage":NSTR,"set":NSTR,"bots":{"type":["integer","null"]},"seed":{"type":["integer","null"]},"look":NSTR,
  "events":{"type":"array","items":STR,"description":"action/event kinds: from take.json or the caption"},
  "caption":NSTR,"caption_src":{"type":["string","null"],"enum":["take","notes","gemini",None]},"approved":{"type":"boolean"}},
 ["path","duration","w","h","project","role"])
schemas["usage_row"]=S("usage_row","one row of inventory.sqlite table usage: a clip window used by a cut; drives the variety penalty",
 {"sha1":STR,"path":STR,"project":STR,"version":STR,"line":STR,"in":NUM,"len":NUM,"published":{"type":"boolean"},"at":STR},
 ["path","project","version","line"])
import sys,os
out=sys.argv[1]
for k,v in schemas.items():
    open(os.path.join(out,f"{k}.json"),"w").write(json.dumps(v,indent=1)+"\n")
print(list(schemas))
