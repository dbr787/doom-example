#!/usr/bin/env ruby

require "json"
require "open3"
require "base64"

# Define supported moves.
MOVES = [
  {label: "Move", key: "Up", value: "Up", emoji: ":arrow_up:", description: "To move forward"},
  {label: "Move", key: "Down", value: "Down", emoji: ":arrow_down:", description: "To move backward"},
  {label: "Turn", key: "Left", value: "Left", emoji: ":arrow_left:", description: "To turn left"},
  {label: "Turn", key: "Right", value: "Right", emoji: ":arrow_right:", description: "To turn right"},
  {label: "Fire", key: "Ctrl", value: "Control_L", emoji: ":boom:", description: "To fire"},
  {label: "Open", key: "Space", value: "space", emoji: ":door:", description: "To open a door"}
]

def use_mounted_agent?
  system("buildkite-agent --version > /dev/null 2>&1")
end

def get_move_data(key)
  if use_mounted_agent?
    `buildkite-agent meta-data get "#{key}"`
  else
    # Use artifacts as move data store - list artifacts, find by filename pattern key__value.txt
    result = `curl -s -H "Authorization: Bearer $BUILDKITE_API_TOKEN" "https://api.buildkite.com/v2/organizations/$BUILDKITE_ORGANIZATION_SLUG/pipelines/$BUILDKITE_PIPELINE_SLUG/builds/$BUILDKITE_BUILD_NUMBER/artifacts"`
    artifacts = JSON.parse(result) rescue []
    # Handle case where artifacts is not an array of hashes
    return "" unless artifacts.is_a?(Array) && artifacts.all? { |a| a.is_a?(Hash) }
    found = artifacts.find { |a| a["filename"] && a["filename"].start_with?("#{key}__") && a["filename"].end_with?(".txt") }
    found ? found["filename"].sub("#{key}__", "").sub(".txt", "") : ""
  end
end

def set_move_data(key, value)
  if use_mounted_agent?
    `buildkite-agent meta-data set "#{key}" "#{value}"`
  else
    # Use artifacts as move data store - create file, post-command hook will upload
    filename = "#{key}__#{value}.txt"
    File.write(filename, "")  # Empty file, value encoded in filename
    puts "Created #{filename} - will be uploaded by post-command hook"
  end
end

def bk_pipeline_upload(pipeline_json)
  if use_mounted_agent?
    Open3.capture2("buildkite-agent pipeline upload --replace", stdin_data: pipeline_json)
  else
    # Use curl for pipeline upload 
    Open3.capture2("curl -s -H \"Authorization: Bearer $BUILDKITE_API_TOKEN\" -X POST \"https://api.buildkite.com/v2/organizations/$BUILDKITE_ORGANIZATION_SLUG/pipelines/$BUILDKITE_PIPELINE_SLUG/builds/$BUILDKITE_BUILD_NUMBER/pipeline\" -H \"Content-Type: application/json\" --data-raw '#{pipeline_json.gsub("'", "\\'")}'")
  end
end

def bk_artifact_upload(file)
  if use_mounted_agent?
    system "buildkite-agent artifact upload #{file}"
  else
    # File created for cross-platform data storage
    # The post-command hook will upload these artifacts on the host
    puts "File #{file} created - will be uploaded by post-command hook"
  end
end

def bk_annotate(content)
  if use_mounted_agent?
    Open3.capture2("buildkite-agent annotate", stdin_data: content)
  else
    # Use curl for annotations
    Open3.capture2("curl -s -H \"Authorization: Bearer $BUILDKITE_API_TOKEN\" -X POST \"https://api.buildkite.com/v2/organizations/$BUILDKITE_ORGANIZATION_SLUG/pipelines/$BUILDKITE_PIPELINE_SLUG/builds/$BUILDKITE_BUILD_NUMBER/annotations\" -H \"Content-Type: application/json\" --data-raw '{\"body\":\"#{content.gsub('"', '\\"')}\",\"style\":\"info\"}'")
  end
end

def move_data_set_command(key, value)
  if use_mounted_agent?
    "buildkite-agent meta-data set \"#{key}\" \"#{value}\""
  else
    "echo \"#{value.gsub('"', '\\"')}\" > #{key}__#{value}.txt"
  end
end

def ask_for_key(i)
  mode = wait_for_mode

  if mode == "ai" && !ENV["ANTHROPIC_API_KEY"].nil?
    file = "./prompt.txt"
    File.write(file, get_prompt())
    %x[claude -p "@#{file}" --verbose --debug --output-format stream-json --permission-mode acceptEdits]
    
    result = JSON.parse(File.read(Dir.glob("*.json").first)) # Claude doesn't always respect the filename.
    move = MOVES.find {|m| m[:key] == result["move"]}
    reason = result["reason"]

    append_to_pipeline({
      steps: [
        {
          label: "#{move[:emoji]} #{move[:label]}",
          key: "step_#{i}",
          depends_on: i == 0 ? [] : "step_#{i - 1}",
          commands: [
            move_data_set_command("reason#{i}", reason),
            move_data_set_command("key#{i}", move[:value])
          ]
        }.tap { |step| 
          # Always add artifact_paths for cross-platform support
          # Pipeline steps might run on different agents than the main step
          step[:artifact_paths] = ["reason#{i}__*.txt", "key#{i}__*.txt"]
        }
      ]
    })
  elsif mode == "random"
    move = MOVES.sample
    reason = "Totally random decision #{move[:description].downcase}."

    # In random mode, set the data immediately - no need for pipeline steps
    set_move_data("reason#{i}", reason)
    set_move_data("key#{i}", move[:value])
    
    puts "Random move #{i}: #{move[:emoji]} #{move[:label]} (#{move[:value]})"
  else 
    append_to_pipeline({
      steps: [
        {
          input: "What next?",
          key: "step_#{i}",
          fields: [
            select: "Choose a key to press",
            key: "key#{i}",
            options: MOVES.map { |m| { label: "#{m[:emoji]} #{m[:label]}", value: m[:value] } }
          ]
        }
      ]
    })
  end
end

def append_to_pipeline(pipeline)
  bk_pipeline_upload(JSON.generate(pipeline))
end

def send_key(key)
  delay = case key
  when "Control_L", "space" then 100
  else 1000
  end

  system "xdotool key --delay #{delay} #{key}"
end

def wait_for_key(i)
  loop do
    puts "Getting metadata: key#{i}"
    result = get_move_data("key#{i}")
    return result if result != ""
    sleep 0.5
  end
end

def wait_for_mode
  # Check environment variable first (set by pipeline)
  if ENV['DOOM_MODE'] && !ENV['DOOM_MODE'].empty?
    puts "Got mode from environment: #{ENV['DOOM_MODE']}"
    return ENV['DOOM_MODE']
  end
  
  # Fallback to polling metadata (for backwards compatibility)
  loop do
    puts "Getting metadata: mode"
    result = get_move_data("mode")
    return result if result != ""
    sleep 0.5
  end
end

def start_doom
  

  server_pid = spawn "Xvfb :1 -screen 0 320x240x24"
  Process.detach(server_pid)
  sleep 1

  doom_pid = spawn "/usr/games/chocolate-doom -geometry 320x240 -iwad /usr/share/games/doom/DOOM1.WAD -episode 1"
  Process.detach(doom_pid)
  doom_pid
end

def signal_doom(pid, signal)
  Process.kill(signal, pid)
rescue Errno::ESRCH
  # Ignore if process no longer exists
end

def grab_frames(i, duration)
  system "ffmpeg -y -t #{duration} -video_size 320x240 -framerate 15 -f x11grab -i :1 -loop -1 #{i}.apng"
  system "rm ./frame_*.png"
  system "ffmpeg -i #{i}.apng -vsync 0 frame_%03d.png"
end

def upload_clip(i)
  reason = i == 0 ? "Game on." : get_move_data("reason#{i - 1}")

  # Smuggle the APNG in as a PNG, otherwise Camo blocks it.
  File.rename("#{i}.apng", "#{i}.png")
  file = "#{i}.png"
  bk_artifact_upload(file)
  bk_annotate(%(<img class="block" width="640" height="480" src="artifact://#{file}"><p>#{reason}</p></div>))
end

def get_prompt()
  choices = MOVES.map { |m| "'#{m[:key]}' #{m[:description]}" }.join(", ")
  move_file = "./move.json"

  %Q[
    The sequence of images in the current directory (./frame_*.png) is a clip from the video game DOOM. 
    Read these images in order and decide the best move to make next. Your choices are #{choices}.

    Additional instructions:

    * DO not fire at any object unless it looks like a human who is standing or walking. 
    * DO not fire at objects that are red or that look like demons lying on the ground.
    * Your goal is to find and eliminate bad guys.
    * If you see what looks like a corner you can go around, move toward it to see if there's a door nearby that you can open.

    Important: 

    * YOU MUST write your decision to a valid JSON file at `#{move_file}`. This file MUST be of the following structure,
      where `move` is your chosen move (case sensitive) and `reason` is a brief explanation as to why:

      { "move": "Up", "reason": "I see a door up ahead." }

    * DO NOT WRITE ANYTHING ELSE to this file -- only this single, two-property JSON object. 
    * You MUST name this file `#{move_file}` -- DO NOT name it anything else.
  ].strip
end

doom_pid = start_doom
signal_doom(doom_pid, "STOP")

["INT", "TERM", "HUP", "QUIT"].each do |signal|
  Signal.trap(signal) do
    puts "Received #{signal}, exiting cleanly..."
    exit 0
  end
end

i = 0
key = nil
loop do
  signal_doom(doom_pid, "CONT")
  recording = Thread.new { grab_frames(i, i == 0 ? 2.5 : 1.25) }
  send_key(key) if key
  recording.join
  signal_doom(doom_pid, "STOP")
  upload_clip(i)

  ask_for_key(i)
  key = wait_for_key(i)

  i += 1
end
