#!/usr/bin/env ruby

require "json"
require "open3"

# Define supported moves
MOVES = [
  {label: "Forward", key: "Up", value: "Up", emoji: ":arrow_up:", description: "To move forward"},
  {label: "Back", key: "Down", value: "Down", emoji: ":arrow_down:", description: "To move backward"},
  {label: "Left", key: "Left", value: "Left", emoji: ":arrow_left:", description: "To turn left"},
  {label: "Right", key: "Right", value: "Right", emoji: ":arrow_right:", description: "To turn right"},
  {label: "Fire", key: "Ctrl", value: "Control_L", emoji: ":boom:", description: "To fire"},
  {label: "Open", key: "Space", value: "space", emoji: ":door:", description: "To open a door"}
]

# Communication with host via shared files
def get_move_data(key)
  File.write("/shared/get_metadata", key)
  # Wait for response
  while !File.exist?("/shared/metadata_response")
    sleep 0.1
  end
  result = File.read("/shared/metadata_response").strip
  File.delete("/shared/metadata_response")
  result
end

def upload_pipeline(pipeline_json)
  File.write("/shared/upload_pipeline", pipeline_json)
  # Wait for confirmation
  while !File.exist?("/shared/pipeline_uploaded")
    sleep 0.1
  end
  File.delete("/shared/pipeline_uploaded")
end

def upload_artifact(file)
  # Copy file to shared directory
  system("cp #{file} /shared/")
  File.write("/shared/upload_artifact", file)
  # Wait for confirmation
  while !File.exist?("/shared/artifact_uploaded")
    sleep 0.1
  end
  File.delete("/shared/artifact_uploaded")
end

def annotate(content)
  File.write("/shared/create_annotation", content)
  # Wait for confirmation
  while !File.exist?("/shared/annotation_created")
    sleep 0.1
  end
  File.delete("/shared/annotation_created")
end

def ask_for_key(i)
  mode = ENV['DOOM_MODE'] || 'manual'

  if mode == "ai" && ENV["ANTHROPIC_API_KEY"]
    # Simple AI logic
    if i % 8 == 0
      move = MOVES.select { |m| m[:key] == "Left" || m[:key] == "Right" }.sample
      reason = "AI: Exploring by turning"
    else
      move = MOVES.find { |m| m[:key] == "Up" }
      reason = "AI: Moving forward"
    end

    pipeline = {
      steps: [{
        label: "#{move[:emoji]} #{move[:label]}",
        key: "step_#{i}",
        depends_on: i == 0 ? [] : "step_#{i - 1}",
        command: "echo '#{reason}' && buildkite-agent meta-data set 'key#{i}' '#{move[:value]}'"
      }]
    }
  elsif mode == "random"
    move = MOVES.sample
    reason = "Random #{move[:description].downcase}"

    pipeline = {
      steps: [{
        label: "#{move[:emoji]} #{move[:label]}",
        key: "step_#{i}",
        depends_on: i == 0 ? [] : "step_#{i - 1}",
        command: "echo '#{reason}' && buildkite-agent meta-data set 'key#{i}' '#{move[:value]}'"
      }]
    }
  else # manual
    pipeline = {
      steps: [{
        input: "💬 What next?",
        key: "step_#{i}",
        depends_on: i == 0 ? [] : "step_#{i - 1}",
        fields: [{
          select: "Choose a key to press",
          key: "key#{i}",
          options: MOVES.map { |m| { label: "#{m[:emoji]} #{m[:label]}", value: m[:value] } }
        }]
      }]
    }
  end

  upload_pipeline(JSON.generate(pipeline))
end

def wait_for_key(i)
  loop do
    result = get_move_data("key#{i}")
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
  # Process doesn't exist
end

def capture_frame(frame_num, duration)
  system "ffmpeg -y -t #{duration} -video_size 320x240 -framerate 15 -f x11grab -i :1 #{frame_num}.apng"
  system "rm ./frame_*.png 2>/dev/null"
  system "ffmpeg -i #{frame_num}.apng -vsync 0 frame_%03d.png 2>/dev/null"
end

def send_key(key)
  delay = case key
  when "Control_L", "space" then 100
  else 1000
  end
  system "xdotool key --delay #{delay} #{key}"
end

def upload_clip(i)
  if i == 0
    reason = "🎮 🟢"
  else
    # Get the move and generate emoji representation
    move_value = get_move_data("key#{i - 1}")
    mode = ENV['DOOM_MODE'] || 'manual'
    
    # Mode emoji
    mode_emoji = case mode
    when 'manual' then '👆'
    when 'random' then '🎲'
    when 'ai' then '🤖'
    else '❓'
    end
    
    # Move emoji
    move_emoji = case move_value
    when 'Up' then '⬆️'
    when 'Down' then '⬇️'
    when 'Left' then '⬅️'
    when 'Right' then '➡️'
    when 'Control_L' then '💥'
    when 'space' then '🚪'
    else '❓'
    end
    
    reason = "#{mode_emoji} #{move_emoji}"
  end

  # Rename APNG as PNG for upload  
  File.rename("#{i}.apng", "#{i}.png") if File.exist?("#{i}.apng")
  file = "#{i}.png"
  
  # Upload artifact (waits for completion via host communication)
  upload_artifact(file)
  
  # Reference artifact by filename only (matches upload path)
  annotate(%(<div><img class="block" width="640" height="480" src="artifact://#{file}"><br><br><p>#{reason}</p></div>))
end

# Main game loop
puts "Starting DOOM..."
mode = ENV['DOOM_MODE'] || 'manual'
puts "Game mode: #{mode}"

doom_pid = start_doom
signal_doom(doom_pid, "STOP")

# Cleanup on exit
["INT", "TERM", "HUP", "QUIT"].each do |signal|
  Signal.trap(signal) do
    puts "Received #{signal}, exiting cleanly..."
    signal_doom(doom_pid, "KILL") rescue nil
    exit 0
  end
end

i = 0
key = nil
loop do
  signal_doom(doom_pid, "CONT")
  recording = Thread.new { capture_frame(i, i == 0 ? 2.5 : 1.25) }
  send_key(key) if key
  recording.join
  signal_doom(doom_pid, "STOP")
  upload_clip(i)

  ask_for_key(i)
  
  puts "Pipeline uploaded, waiting for step to start..."
  sleep 2
  
  key = wait_for_key(i)
  puts "Got move: #{key}"

  i += 1
  break if i >= 20  # Reasonable limit
end

puts "Game finished!"
