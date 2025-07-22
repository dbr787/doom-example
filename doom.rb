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

def ask_for_key(i)
  mode = `buildkite-agent meta-data get "mode"`

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
            %Q[buildkite-agent meta-data set "reason#{i}" "#{reason}"],
            %Q[buildkite-agent meta-data set "key#{i}" "#{move[:value]}"]
          ]
        }
      ]
    })
  elsif mode == "random"
    move = MOVES.sample
    reason = "Totally random decision #{move[:description].downcase}."

    append_to_pipeline({
      steps: [
        {
          label: "#{move[:emoji]} #{move[:label]}",
          key: "step_#{i}",
          depends_on: i == 0 ? [] : "step_#{i - 1}",
          commands: [
            %Q[buildkite-agent meta-data set "reason#{i}" "#{reason}"],
            %Q[buildkite-agent meta-data set "key#{i}" "#{move[:value]}"]
          ]
        }
      ]
    })
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
  Open3.capture2("buildkite-agent pipeline upload --replace", stdin_data: JSON.generate(pipeline))
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
    result = `buildkite-agent meta-data get key#{i}`
    return result if result != ""
    sleep 0.5
  end
end

def start_doom
  ENV["DISPLAY"] = ":1"

  puts "Starting Xvfb..."
  server_pid = spawn "Xvfb :1 -screen 0 320x240x24 -ac +extension GLX +render -noreset"
  Process.detach(server_pid)
  sleep 3

  puts "Checking for DOOM1.WAD..."
  wad_file = "/usr/share/games/doom/DOOM1.WAD"
  unless File.exist?(wad_file)
    puts "ERROR: DOOM1.WAD not found at #{wad_file}"
    puts "Available files in /usr/share/games/doom/:"
    system "ls -la /usr/share/games/doom/"
    exit 1
  end
  
  puts "Starting Doom..."
  doom_pid = spawn "/usr/games/chocolate-doom -geometry 320x240 -iwad #{wad_file} -episode 1"
  Process.detach(doom_pid)
  sleep 2
  
  # Check if doom process is still alive
  begin
    Process.kill(0, doom_pid)
    puts "Doom process #{doom_pid} started successfully"
  rescue Errno::ESRCH
    puts "ERROR: Doom process #{doom_pid} died immediately after starting"
    exit 1
  end
  
  doom_pid
end

def signal_doom(pid, signal)
  begin
    Process.kill(signal, pid)
  rescue Errno::ESRCH
    puts "Warning: Doom process #{pid} no longer exists"
    false
  end
end

def grab_frames(i, duration)
  system "ffmpeg -y -t #{duration} -video_size 320x240 -framerate 15 -f x11grab -i :1 -loop -1 #{i}.apng"
  system "rm ./frame_*.png"
  system "ffmpeg -i #{i}.apng -vsync 0 frame_%03d.png"
end

def upload_clip(i)
  reason = i == 0 ? "Game on." : `buildkite-agent meta-data get "reason#{i - 1}"`

  # Smuggle the APNG in as a PNG, otherwise Camo blocks it.
  File.rename("#{i}.apng", "#{i}.png")
  file = "#{i}.png"
  system "buildkite-agent artifact upload #{file}"
  Open3.capture2("buildkite-agent annotate", stdin_data: %(<img class="block" width="640" height="480" src="artifact://#{file}"><p>#{reason}</p></div>))
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
