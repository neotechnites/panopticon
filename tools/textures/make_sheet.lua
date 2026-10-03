-- Packs PNGs into one .ase sheet, 2 px gaps, one named slice per PNG (basename).
-- Params: out=<sheet.ase> pngs=<a.png;b.png;...>
local out, list = app.params["out"], app.params["pngs"]
local imgs, maxRow, x, y, rowH, w, h = {}, 1024, 0, 0, 0, 0, 0
for p in string.gmatch(list, "[^;]+") do
  local img = Image{ fromFile = p }
  if x > 0 and x + img.width > maxRow then x, y, rowH = 0, y + rowH + 2, 0 end
  table.insert(imgs, { img = img, x = x, y = y, name = p:match("([^/]+)%.png$") })
  w, h = math.max(w, x + img.width), math.max(h, y + img.height)
  x, rowH = x + img.width + 2, math.max(rowH, img.height)
end
local spr = Sprite(w, h, ColorMode.RGB)
local cel = spr.cels[1]
local canvas = Image(w, h, ColorMode.RGB)
for _, e in ipairs(imgs) do
  local src = e.img
  if src.colorMode ~= ColorMode.RGB then
    local c = Image(src.width, src.height, ColorMode.RGB)
    c:drawImage(src, Point(0, 0)); src = c
  end
  canvas:drawImage(src, Point(e.x, e.y), 255, BlendMode.SRC)
  local s = spr:newSlice(Rectangle(e.x, e.y, e.img.width, e.img.height))
  s.name = e.name
end
cel.image = canvas
cel.position = Point(0, 0)
spr:saveAs(out)
