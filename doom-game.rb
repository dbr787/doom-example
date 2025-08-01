#!/usr/bin/env ruby

require "json"

# Game controls
MOVES = [
  {label: "Forward", key: "Up", value: "Up", emoji: "⬆️"},
  {label: "Back", key: "Down", value: "Down", emoji: "⬇️"},
  {label: "Left", key: "Left", value: "Left", emoji: "⬅️"},
  {label: "Right", key: "Right", value: "Right", emoji: "➡️"},
  {label: "Fire", key: "Ctrl", value: "Control_L", emoji: "💥"},
  {label: "Open", key: "Space", value: "space", emoji: "🚪"}
]

def move_emoji(value)
  MOVES.find { |m| m[:value] == value }&.dig(:emoji) || "❓"
end

# Buildkite integration - direct calls
def get_metadata(key)
  puts "🔍 Getting metadata for key: #{key}"
  result = `buildkite-agent meta-data get "#{key}" 2>&1`.strip
  puts "Metadata result: '#{result}' (exit: #{$?.exitstatus})"
  return result if $?.exitstatus == 0
  return ""
end

def upload_pipeline(json_content)
  puts "🔄 Uploading pipeline..."
  puts "Pipeline JSON: #{json_content}"
  result = IO.popen("buildkite-agent pipeline upload --replace 2>&1", "w") do |p| 
    p.write(json_content)
  end
  puts "Pipeline upload result: #{$?.exitstatus}"
  if $?.exitstatus != 0
    puts "❌ Pipeline upload failed!"
  else
    puts "✅ Pipeline uploaded successfully"
  end
end

def upload_artifact(file)
  system("buildkite-agent artifact upload '#{file}'")
end

def annotate(content)
  IO.popen("buildkite-agent annotate", "w") { |p| p.write(content) }
end

# Game functions
def start_doom(level)
  server_pid = spawn("Xvfb :1 -screen 0 320x240x24 > /dev/null 2>&1")
  Process.detach(server_pid)
  sleep 2
  doom_pid = spawn("/usr/games/chocolate-doom -geometry 320x240 -iwad /usr/share/games/doom/DOOM1.WAD -episode 1 > /dev/null 2>&1")
  Process.detach(doom_pid)
  doom_pid
end

def capture_frame(i, duration)
  system("ffmpeg -y -t #{duration} -video_size 320x240 -framerate 15 -f x11grab -i :1 #{i}.apng -loglevel warning")
  system("rm ./frame_*.png 2>/dev/null")
  system("ffmpeg -i #{i}.apng -vsync 0 frame_%03d.png -loglevel warning 2>/dev/null")
end

def send_key(key)
  `DISPLAY=:1 xdotool key #{key}`
end

def signal_doom(pid, signal)
  Process.kill(signal, pid)
rescue Errno::ESRCH
  # Process doesn't exist
end

def ask_for_input(i, mode)
  pipeline = case mode
  when "human"
    move_options = MOVES.map { |m| {label: "#{m[:emoji]} #{m[:label]}", value: m[:key]} }
    {
      "steps" => [{
        "input" => "Move #{i}",
        "fields" => [{"key" => "move#{i}", "select" => "Move", "options" => move_options}]
      }]
    }
  when "ai"
    {
      "steps" => [{
        "input" => "AI Move #{i}",
        "fields" => [{"key" => "move#{i}", "text" => "Move", "default" => "ai", "hint" => "Type 'ai' for AI move"}]
      }]
    }
  when "random"
    move = MOVES.sample
    {
      "steps" => [{
        "label" => "🎲 #{move[:emoji]}",
        "key" => "step_#{i}",
        "command" => "echo '🎲 Random #{move[:label]}' && buildkite-agent meta-data set 'move#{i}' '#{move[:key]}'",
        "depends_on" => i == 1 ? nil : "step_#{i-1}"
      }]
    }
  end
  
  upload_pipeline(pipeline.to_json)
end

def get_ai_move(i)
  prompt = "Look at this DOOM game screenshot. Choose the best move: #{MOVES.map{|m| m[:key]}.join(', ')}. Respond with JSON: {\"move\":\"Up\",\"reason\":\"explanation\"}"
  response = `claude "#{prompt}" #{i}.png 2>/dev/null`.strip
  
  if match = response.match(/"move":\s*"([^"]+)"/)
    move_key = match[1]
    MOVES.find { |m| m[:key] == move_key }&.dig(:value)
  end
end

def wait_for_input(key)
  600.times do
    result = get_metadata(key)
    return result unless result.empty?
    sleep 1
  end
  puts "Timeout waiting for #{key}"
  exit 1
end

# Main game loop
puts "🎮 Starting DOOM..."

mode = wait_for_input("game_mode")
level = wait_for_input("level")

doom_pid = start_doom(level)
signal_doom(doom_pid, "STOP")

i = 1
loop do
  # Resume game, capture frames, pause again
  signal_doom(doom_pid, "CONT")
  recording = Thread.new { capture_frame(i, i == 1 ? 2.5 : 1.25) }
  recording.join
  signal_doom(doom_pid, "STOP")
  
  # Rename APNG to PNG for upload
  File.rename("#{i}.apng", "#{i}.png") if File.exist?("#{i}.apng")
  upload_artifact("#{i}.png")
  ask_for_input(i, mode)
  
  move_input = wait_for_input("move#{i}")
  
  if mode == "ai" && move_input == "ai"
    move_value = get_ai_move(i)
    reason = "🤖 AI move"
  else
    move = MOVES.find { |m| m[:key] == move_input }
    move_value = move[:value]
    reason = "👤 #{move[:label]}"
  end
  
  if move_value
    # Resume game to execute move
    signal_doom(doom_pid, "CONT")
    send_key(move_value)
    sleep 0.5
    signal_doom(doom_pid, "STOP")
    
    annotate(%(<div class="center"><img class="block mx-auto" width="640" height="480" src="artifact://#{i}.png"><h2 class="mt2 center">**Move #{i}:** #{move_emoji(move_value)} #{reason}</h2></div>))
  end
  
  i += 1
end
