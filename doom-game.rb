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
  `buildkite-agent meta-data get "#{key}" 2>/dev/null`.strip
end

def upload_pipeline(yaml)
  IO.popen("buildkite-agent pipeline upload --replace", "w") { |p| p.write(yaml) }
end

def upload_artifact(file)
  system("buildkite-agent artifact upload '#{file}'")
end

def annotate(content)
  IO.popen("buildkite-agent annotate", "w") { |p| p.write(content) }
end

# Game functions
def start_doom(level)
  spawn("Xvfb :1 -screen 0 800x600x24 > /dev/null 2>&1")
  sleep 2
  spawn("chocolate-doom -iwad /usr/share/games/doom/DOOM1.WAD -warp 1 #{level} -window > /dev/null 2>&1")
end

def screenshot(i)
  `ffmpeg -f x11grab -video_size 800x600 -i :1 -vframes 1 -y #{i}.png > /dev/null 2>&1`
end

def send_key(key)
  `DISPLAY=:1 xdotool key #{key}`
end

def ask_for_input(i, mode)
  pipeline = case mode
  when "human"
    move_options = MOVES.map { |m| {label: "#{m[:emoji]} #{m[:label]}", value: m[:key]} }
    {
      "steps" => [{
        "input" => "Move #{i}",
        "fields" => [{"select" => "move#{i}", "options" => move_options}]
      }]
    }
  when "ai"
    {
      "steps" => [{
        "input" => "AI Move #{i}",
        "fields" => [{"text" => "move#{i}", "default" => "ai", "hint" => "Type 'ai' for AI move"}]
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
system("kill -STOP #{doom_pid}")

i = 1
loop do
  screenshot(i)
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
    send_key(move_value)
    annotate("**Move #{i}:** #{move_emoji(move_value)} #{reason}")
  end
  
  i += 1
  sleep 0.5
end
