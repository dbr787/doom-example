#!/usr/bin/env ruby

require "json"

ENV['DISPLAY'] = ':1'

MODES = [
  {key: "manual", emoji: "🧑"},
  {key: "random", emoji: "🎲"},
  {key: "ai", emoji: "🤖"}
]

ACTIONS = [
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
  # Create optimized PNG for faster loading
  system("ffmpeg -i #{i}.apng -compression_level 1 -pred 1 #{i}.png -loglevel warning 2>/dev/null")
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
    action_options = ACTIONS.map { |a| {label: "#{a[:emoji]} #{a[:label]}", value: a[:key]} }
    step = {
      "input" => "Action #{i + 1}",
      "key" => "step_#{i}",
      "fields" => [{"key" => "action#{i}", "select" => "Choose your action", "options" => action_options}]
    }
    step["depends_on"] = "step_#{i-1}" if i > 0
    {"steps" => [step]}
  when "ai"
    step = {
      "input" => "AI Action #{i + 1}",
      "key" => "step_#{i}",
      "fields" => [{"key" => "action#{i}", "text" => "Type 'ai' for AI action", "default" => "ai"}]
    }
    step["depends_on"] = "step_#{i-1}" if i > 0
    {"steps" => [step]}
  when "random"
    action = ACTIONS.sample
    puts "🎲 Random #{action[:label]}"
    return action[:key]
  end
  
  upload_pipeline(pipeline.to_json)
end

def get_ai_action(i)
  prompt = "Look at this DOOM game screenshot. Choose the best action: #{ACTIONS.map{|a| a[:key]}.join(', ')}. Respond with JSON: {\"action\":\"Up\",\"reason\":\"explanation\"}"
  response = `claude "#{prompt}" #{i}.png 2>/dev/null`.strip
  
  if match = response.match(/"action":\s*"([^"]+)"/)
    action_key = match[1]
    ACTIONS.find { |a| a[:key] == action_key }&.dig(:value)
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

puts "🎮 Doom starting up, waiting for game configuration..."
mode = wait_for_input("game_mode")
level = wait_for_input("level")
puts "🚀 Game mode: #{mode}, Level: #{level}"

doom_pid = start_doom(level)
signal_doom(doom_pid, "STOP")

i = 0
action = nil
action_history = []
loop do
  signal_doom(doom_pid, "CONT")
  recording = Thread.new { capture_frame(i, i == 0 ? 2.5 : 1.25) }
  send_key(action) if action
  recording.join
  signal_doom(doom_pid, "STOP")
  
  File.rename("#{i}.apng", "#{i}.png") if File.exist?("#{i}.apng")
  upload_artifact("#{i}.png")
  
  history_table = if action_history.empty?
    ""
  else
    rows = action_history.map { |entry| "<tr><td class='center'>#{entry[:mode_emoji]}</td><td class='center'>#{entry[:action_emoji]}</td><td class='center'>#{entry[:turn]}</td></tr>" }.join
    %(<div style="text-align: center;"><table class="mt2" style="width: 640px; margin: 0 auto; display: inline-block;"><thead><tr><th class='center' width="213">Mode</th><th class='center' width="213">Action</th><th class='center' width="214">Turn</th></tr></thead><tbody>#{rows}</tbody></table></div>)
  end
  
  # Optimized for faster loading with cache busting
  timestamp = Time.now.to_i
  annotate(%(<div class="flex flex-column items-center"><img width="640" height="480" src="artifact://#{i}.png?v=#{timestamp}" style="image-rendering: pixelated; image-rendering: -moz-crisp-edges; image-rendering: crisp-edges;">#{history_table}</div>))
  
  if mode == "random"
    action_input = ask_for_input(i, mode)
  else
    ask_for_input(i, mode)
    action_input = wait_for_input("action#{i}")
  end
  
  if mode == "ai" && action_input == "ai"
    action = get_ai_action(i)
    action_obj = ACTIONS.find { |a| a[:value] == action }
  else
    action_obj = ACTIONS.find { |a| a[:key] == action_input }
    action = action_obj&.dig(:value)
  end
  
  if action_obj
    mode_obj = MODES.find { |m| m[:key] == mode }
    action_history.unshift({
      turn: i + 1,
      mode_emoji: mode_obj[:emoji],
      action_emoji: action_obj[:emoji]
    })
  end
  
  i += 1
end
