-- Draws PNGs into a sheet's named slices (PNG already slice-sized) and saves it in place.
-- Params: sheet=<sheet.ase> pairs=<slice=a.png;slice=b.png;...>
local spr = app.open(app.params["sheet"])
local bounds = {}
for _, s in ipairs(spr.slices) do bounds[s.name] = s.bounds end
local cel = spr.layers[1]:cel(1)
local canvas = Image(spr.width, spr.height, ColorMode.RGB)
canvas:drawImage(cel.image, cel.position, 255, BlendMode.SRC)
for name, png in string.gmatch(app.params["pairs"], "([^=;]+)=([^;]+)") do
  local b, img = bounds[name], Image{ fromFile = png }
  if img.colorMode ~= ColorMode.RGB then
    local c = Image(img.width, img.height, ColorMode.RGB)
    c:drawImage(img, Point(0, 0)); img = c
  end
  canvas:drawImage(img, Point(b.x, b.y), 255, BlendMode.SRC)
end
cel.image = canvas
cel.position = Point(0, 0)
spr:saveAs(spr.filename)
