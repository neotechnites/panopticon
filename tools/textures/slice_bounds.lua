-- Prints each slice of the active sheet: name x y w h.
for _, s in ipairs(app.activeSprite.slices) do
  print(s.name, s.bounds.x, s.bounds.y, s.bounds.width, s.bounds.height)
end
