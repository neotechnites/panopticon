-- Adds PNGs to a sheet as new named slices below what is there (2 px gap), growing the canvas; saves in place.
-- Params: sheet=<sheet.ase> pairs=<slice=a.png;slice=b.png;...>
local spr = app.open(app.params["sheet"])
local cel = spr.layers[1]:cel(1)
local old = Image(spr.width, spr.height, ColorMode.RGB)
old:drawImage(cel.image, cel.position, 255, BlendMode.SRC)
local adds, w, h = {}, spr.width, spr.height
for name, png in string.gmatch(app.params["pairs"], "([^=;]+)=([^;]+)") do
  local img = Image{ fromFile = png }
  if img.colorMode ~= ColorMode.RGB then
    local c = Image(img.width, img.height, ColorMode.RGB)
    c:drawImage(img, Point(0, 0)); img = c
  end
  table.insert(adds, { name = name, img = img, y = h + 2 })
  w, h = math.max(w, img.width), h + 2 + img.height
end
spr:crop(Rectangle(0, 0, w, h))
local canvas = Image(w, h, ColorMode.RGB)
canvas:drawImage(old, Point(0, 0), 255, BlendMode.SRC)
for _, a in ipairs(adds) do
  canvas:drawImage(a.img, Point(0, a.y), 255, BlendMode.SRC)
  local s = spr:newSlice(Rectangle(0, a.y, a.img.width, a.img.height))
  s.name = a.name
end
cel.image = canvas
cel.position = Point(0, 0)
spr:saveAs(spr.filename)
