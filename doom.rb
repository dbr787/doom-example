#!/usr/bin/env ruby

require "json"

ENV['DISPLAY'] = ':1'

MODES = [
  {key: "manual", emoji: "🧑"},
  {key: "random", emoji: "🎲"},
  {key: "ai", emoji: "🤖"}
]

MOVES = [
  {label: "Forward", key: "Up", value: "Up", emoji: "⬆️"},
  {label: "Back", key: "Down", value: "Down", emoji: "⬇️"},
  {label: "Left", key: "Left", value: "Left", emoji: "⬅️"},
  {label: "Right", key: "Right", value: "Right", emoji: "➡️"},
  {label: "Fire", key: "Ctrl", value: "Control_L", emoji: "💥"},
  {label: "Open", key: "Space", value: "space", emoji: "🚪"}
]

# Buildkite communication
def get_metadata(key)
  result = `buildkite-agent meta-data get "#{key}" 2>/dev/null`.strip
  return result if $?.exitstatus == 0
  return ""
end

def upload_pipeline(json_content)
  IO.popen("buildkite-agent pipeline upload --replace", "w") do |p| 
    p.write(json_content)
  end
end

def upload_artifact(file)
  system("buildkite-agent artifact upload '#{file}'")
end

def annotate(content)
  IO.popen("buildkite-agent annotate", "w") { |p| p.write(content) }
end

def start_doom(level)
  server_pid = spawn("Xvfb :1 -screen 0 320x240x24 > /dev/null 2>&1")
  Process.detach(server_pid)
  sleep 1
  
  doom_pid = spawn("/usr/games/chocolate-doom -geometry 320x240 -iwad /usr/share/games/doom/DOOM1.WAD -warp 1 #{level} -nomusic -nosound")
  Process.detach(doom_pid)
  
  doom_pid
end

def capture_frame(i, duration)
  system("ffmpeg -y -t #{duration} -video_size 320x240 -framerate 15 -f x11grab -i :1 #{i}.apng -loglevel warning")
  system("rm ./frame_*.png 2>/dev/null")
  system("ffmpeg -i #{i}.apng -vsync 0 frame_%03d.png -loglevel warning 2>/dev/null")
end

def send_key(key)
  delay = case key
  when "Control_L", "space" then 100
  else 1000
  end
  
  system("xdotool key --delay #{delay} #{key}")
end

def signal_doom(pid, signal)
  Process.kill(signal, pid)
rescue Errno::ESRCH
end

def ask_for_input(i, mode)
  pipeline = case mode
  when "manual"
    move_options = MOVES.map { |m| {label: "#{m[:emoji]} #{m[:label]}", value: m[:key]} }
    step = {
      "input" => "Move #{i}",
      "key" => "step_#{i}",
      "fields" => [{"key" => "move#{i}", "select" => "Choose your move", "options" => move_options}]
    }
    step["depends_on"] = "step_#{i-1}" if i > 0
    {"steps" => [step]}
  when "ai"
    step = {
      "input" => "AI Move #{i}",
      "key" => "step_#{i}",
      "fields" => [{"key" => "move#{i}", "text" => "Type 'ai' for AI move", "default" => "ai"}]
    }
    step["depends_on"] = "step_#{i-1}" if i > 0
    {"steps" => [step]}
  when "random"
    move = MOVES.sample
    step = {
      "label" => "🎲 #{move[:emoji]}",
      "key" => "step_#{i}",
      "command" => "echo '🎲 Random #{move[:label]}' && buildkite-agent meta-data set 'move#{i}' '#{move[:key]}'"
    }
    step["depends_on"] = "step_#{i-1}" if i > 0
    {"steps" => [step]}
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

mode = wait_for_input("game_mode")
level = wait_for_input("level")

doom_pid = start_doom(level)
signal_doom(doom_pid, "STOP")

i = 0
move = nil
move_history = []
loop do
  signal_doom(doom_pid, "CONT")
  recording = Thread.new { capture_frame(i, i == 0 ? 2.5 : 1.25) }
  send_key(move) if move
  recording.join
  signal_doom(doom_pid, "STOP")
  
  File.rename("#{i}.apng", "#{i}.png") if File.exist?("#{i}.apng")
  upload_artifact("#{i}.png")
  
  history_table = if move_history.empty?
    ""
  else
    rows = move_history.take(10).map { |entry| "<tr><td>#{entry[:mode_emoji]}</td><td>#{entry[:move_emoji]}</td></tr>" }.join
    %(<table class="mt2 mx-auto" style="width: 640px;"><thead><tr><th>Mode</th><th>Move</th></tr></thead><tbody>#{rows}</tbody></table>)
  end
  
  annotate(%(<div class="center"><img class="block mx-auto" width="640" height="480" src="artifact://#{i}.png">#{history_table}</div>))
  
  ask_for_input(i, mode)
  
  move_input = wait_for_input("move#{i}")
  
  if mode == "ai" && move_input == "ai"
    move = get_ai_move(i)
    move_obj = MOVES.find { |m| m[:value] == move }
  else
    move_obj = MOVES.find { |m| m[:key] == move_input }
    move = move_obj&.dig(:value)
  end
  
  if move_obj
    mode_obj = MODES.find { |m| m[:key] == mode }
    move_history.unshift({
      mode_emoji: mode_obj[:emoji],
      move_emoji: move_obj[:emoji]
    })
  end
  
  i += 1
end
