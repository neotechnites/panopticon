-- Build a DaVinci Resolve project from a content project folder, through fuscript:
--   fuscript.exe -l lua resolve_project.lua
-- with PANOPTICON_PROJECT_DIR and PANOPTICON_PROJECT_NAME in the environment.
-- Resolve must be running (assemble.sh starts it with -nogui). One video track
-- per shot, a marker named by shot at each shot's start, a placeholder Text+
-- title per shot, and a muted narration track. Nothing is rendered here.

local dir = os.getenv("PANOPTICON_PROJECT_DIR")
local name = os.getenv("PANOPTICON_PROJECT_NAME")
if not dir or not name then
  print("resolve: PANOPTICON_PROJECT_DIR and PANOPTICON_PROJECT_NAME are required")
  return
end

local resolve = Resolve()
if not resolve then
  print("resolve: no running Resolve to talk to")
  return
end
local fps = 60

local manager = resolve:GetProjectManager()
local project = manager:LoadProject(name) or manager:CreateProject(name)
if not project then
  print("resolve: could not create project " .. name)
  return
end
project:SetSetting("timelineFrameRate", tostring(fps))
project:SetSetting("timelineResolutionWidth", "1280")
project:SetSetting("timelineResolutionHeight", "720")

-- beats.txt: n, start, end, gap_start, gap_end, caption, said (tab separated).
local beats = {}
for line in io.lines(dir .. "\\beats.txt") do
  if line:sub(1, 1) ~= "#" then
    local n, s, e, gs, ge, caption, said = line:match("^(%d+)\t([%d.]+)\t([%d.]+)\t([%d.]+)\t([%d.]+)\t([^\t]*)\t(.*)$")
    if n then
      beats[#beats + 1] = {n = tonumber(n), start = tonumber(s), finish = tonumber(e),
        gap_start = tonumber(gs), gap_end = tonumber(ge), caption = caption, said = said}
    end
  end
end

local pool = project:GetMediaPool()
local root = pool:GetRootFolder()
pool:SetCurrentFolder(root)
local timeline = pool:CreateEmptyTimeline(name)
if not timeline then
  print("resolve: could not create timeline " .. name)
  return
end
project:SetCurrentTimeline(timeline)

for i, beat in ipairs(beats) do
  local path = string.format("%s\\shots\\%02d.mp4", dir, beat.n)
  local items = pool:ImportMedia({path})
  if items and items[1] then
    if i > 1 then timeline:AddTrack("video") end
    local record = math.floor(beat.start * fps + 0.5)
    timeline:AppendToTimeline({{mediaPoolItem = items[1], trackIndex = i, recordFrame = record}})
    timeline:AddMarker(record, "Blue", string.format("%02d", beat.n), beat.said, 1)
    if beat.gap_end > beat.gap_start then
      timeline:AddMarker(math.floor(beat.gap_start * fps + 0.5), "Red",
        string.format("voice %02d", beat.n), "silent gap for voice-over", math.floor((beat.gap_end - beat.gap_start) * fps + 0.5))
    end
  else
    print("resolve: could not import " .. path)
  end
end

-- Placeholder titles, one per shot, on a track of their own.
timeline:AddTrack("video")
for _, beat in ipairs(beats) do
  timeline:SetCurrentTimecode(string.format("01:00:%02d:%02d", math.floor(beat.start / 60), math.floor(beat.start % 60)))
  local title = timeline:InsertFusionTitleIntoTimeline("Text+")
  if title and beat.caption ~= "" and beat.caption ~= "-" then title:SetName(beat.caption) end
end

-- Narration: an empty audio track, muted until the recording lands.
timeline:AddTrack("audio", "mono")
local audio_tracks = timeline:GetTrackCount("audio")
timeline:SetTrackName("audio", audio_tracks, "narration")
timeline:SetTrackEnable("audio", audio_tracks, false)

manager:SaveProject()
print(string.format("resolve: project %s, %d shots, %d video tracks", name, #beats, timeline:GetTrackCount("video")))
