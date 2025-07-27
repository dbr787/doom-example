#!/usr/bin/env ruby
#
# Interactive Doom game runner for Buildkite pipelines
# 
# This script runs inside a Docker container and orchestrates:
# - Starting the Doom game process
# - Capturing screenshots of gameplay
# - Creating dynamic Buildkite pipeline steps for user input
# - Communicating with the host script via shared files
#

require "json"
require "open3"

# Doom game controls - maps UI labels to actual key inputs
MOVES = [
  {label: "Forward", key: "Up", value: "Up", emoji: ":arrow_up:", description: "To move forward"},
  {label: "Back", key: "Down", value: "Down", emoji: ":arrow_down:", description: "To move backward"},
  {label: "Left", key: "Left", value: "Left", emoji: ":arrow_left:", description: "To turn left"},
  {label: "Right", key: "Right", value: "Right", emoji: ":arrow_right:", description: "To turn right"},
  {label: "Fire", key: "Ctrl", value: "Control_L", emoji: ":boom:", description: "To fire"},
  {label: "Open", key: "Space", value: "space", emoji: ":door:", description: "To open a door"}
]

# Convert move values to emoji for display in Buildkite annotations
def move_to_emoji(move_value)
  case move_value
  when 'Up' then '⬆️'
  when 'Down' then '⬇️'
  when 'Left' then '⬅️'
  when 'Right' then '➡️'
  when 'Control_L' then '💥'
  when 'space' then '🚪'
  else '❓'
  end
end

# Functions for communicating with the host script via shared files
def get_move_data(key)
  retries = 3
  begin
    # Write request file
    File.write("/shared/get_metadata", key)
    # Wait for response
    while !File.exist?("/shared/metadata_response")
      sleep 0.1
    end
    # Read and clean up response file
    result = File.read("/shared/metadata_response").strip
    File.delete("/shared/metadata_response")
    result
  rescue Errno::ENOENT => e
    retries -= 1
    if retries > 0
      puts "Warning: Shared directory issue (#{e.message}), retrying..."
      sleep 0.5
      retry
    else
      puts "Error: Shared directory unavailable after retries. Exiting."
      exit 1
    end
  end
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

def get_ai_move(i)
  begin
    # Simple approach: pass image and prompt directly to Claude
    prompt = create_ai_prompt(i)
    
    # Call Claude with image, let it decide and output to stdout
    response = `claude "#{prompt}" #{i}.png 2>/dev/null`.strip
    
    # Try to extract JSON from response (Claude might wrap it in text)
    json_match = response.match(/\{[^}]*"move"\s*:\s*"([^"]+)"[^}]*"reason"\s*:\s*"([^"]+)"[^}]*\}/)
    
    if json_match
      move_key = json_match[1]
      reason = json_match[2]
      
      # Find the move in our MOVES array
      move = MOVES.find { |m| m[:key] == move_key }
      if move
        return [move, "🤖 #{move_to_emoji(move[:value])} AI: #{reason}"]
      end
    end
    
    # Try parsing as direct JSON if regex didn't work
    if response.include?('"move"')
      parsed = JSON.parse(response)
      move_key = parsed["move"]
      reason = parsed["reason"] || "AI decision"
      
      move = MOVES.find { |m| m[:key] == move_key }
      if move
        return [move, "🤖 #{move_to_emoji(move[:value])} AI: #{reason}"]
      end
    end
    
  rescue => e
    puts "AI error: #{e.message}"
    puts "Claude AI failed. Exiting."
    exit 1
  end
  
  puts "Claude AI failed to return valid move. Exiting."
  exit 1
end

def create_ai_prompt(i)
  moves_list = MOVES.map { |m| "#{m[:key]}: #{m[:description]}" }.join(", ")
  
  <<~PROMPT
    You're playing Doom. Look at this game screenshot and decide the next move.
    
    Available moves: #{moves_list}
    
    Strategy: Move forward to explore, turn to navigate, fire at enemies, use space for doors.
    
    Respond with JSON only: {"move": "Up", "reason": "exploring forward"}
    
    Move must be one of: #{MOVES.map { |m| m[:key] }.join(", ")}
  PROMPT
end

def ask_for_key(i, mode)

  if mode == "ai" && ENV["ANTHROPIC_API_KEY"]
    # Claude AI integration with smart fallback
    move, reason = get_ai_move(i)

    pipeline = {
      steps: [{
        label: "🤖 #{move_to_emoji(move[:value])}",
        key: "step_#{i}",
        depends_on: i == 0 ? "mode" : "step_#{i - 1}",
        command: "echo '#{reason}' && buildkite-agent meta-data set 'move#{i}' '#{move[:value]}' && buildkite-agent meta-data set 'reason#{i}' '#{reason}'"
      }]
    }
  elsif mode == "random"
    move = MOVES.sample
    reason = "🎲 #{move_to_emoji(move[:value])} Random #{move[:description].downcase}"

    pipeline = {
      steps: [{
        label: "🎲 #{move_to_emoji(move[:value])}",
        key: "step_#{i}",
        depends_on: i == 0 ? "mode" : "step_#{i - 1}",
        command: "echo '#{reason}' && buildkite-agent meta-data set 'move#{i}' '#{move[:value]}' && buildkite-agent meta-data set 'reason#{i}' '#{reason}'"
      }]
    }
  else # manual
    pipeline = {
      steps: [{
        input: "💬 What next?", 
        key: "step_#{i}",
        depends_on: i == 0 ? "mode" : "step_#{i - 1}",
        fields: [
          {
            select: "Select your next move",
            key: "move#{i}",
            default: "Up",
            options: MOVES.map { |m| { label: "#{m[:emoji]} #{m[:label]}", value: m[:value] } }
          },
          {
            select: "Game options",
            key: "game_option#{i}",
            required: false,
            default: "continue",
            options: [
              { label: "💬 Continue with current mode", value: "continue" },
              { label: "🎲 Switch to random mode", value: "switch_random" },
              { label: "🤖 Switch to AI mode", value: "switch_ai" },
              { label: "🏳️ Rage quit", value: "end_game" }
            ]
          }
        ]
      }]
    }
  end

  upload_pipeline(JSON.generate(pipeline))
end

# Remove this function - use wait_for_metadata instead

def start_doom(level)
  server_pid = spawn "Xvfb :1 -screen 0 320x240x24"
  Process.detach(server_pid)
  sleep 1

  doom_pid = spawn "/usr/games/chocolate-doom -geometry 320x240 -iwad /usr/share/games/doom/DOOM1.WAD -warp 1 #{level} -nosound"
  Process.detach(doom_pid)
  doom_pid
end

def signal_doom(pid, signal)
  Process.kill(signal, pid)
rescue Errno::ESRCH
  # Process doesn't exist
end

def capture_frame(frame_num, duration)
  system "ffmpeg -y -t #{duration} -video_size 320x240 -framerate 15 -f x11grab -i :1 #{frame_num}.apng -loglevel warning"
  system "rm ./frame_*.png 2>/dev/null"
  system "ffmpeg -i #{frame_num}.apng -vsync 0 frame_%03d.png -loglevel warning 2>/dev/null"
end

def send_key(key)
  delay = case key
  when "Control_L", "space" then 100
  else 1000
  end
  system "xdotool key --delay #{delay} #{key}"
end

def upload_clip(i, mode)
  if i == 0
    reason = "🎮 🟢"
  else
    # Get the move and generate emoji representation
    move_value = get_move_data("move#{i - 1}")
    
    # For AI and random modes, include the reasoning if available
    if mode == "ai" || mode == "random"
      stored_reason = get_move_data("reason#{i - 1}")
      if stored_reason && !stored_reason.empty?
        reason = stored_reason
      else
        # Fallback to emoji if no reason stored
        mode_emoji = mode == 'ai' ? '🤖' : '🎲'
        reason = "#{mode_emoji} #{move_to_emoji(move_value)}"
      end
    else
      # Manual mode just shows emoji
      reason = "💬 #{move_to_emoji(move_value)}"
    end
  end

  # Rename APNG as PNG for upload  
  File.rename("#{i}.apng", "#{i}.png") if File.exist?("#{i}.apng")
  file = "#{i}.png"
  
  # Upload artifact (waits for completion via host communication)
  upload_artifact(file)
  
  # Reference artifact by filename only (matches upload path)
  annotate(%(<div class="center"><img class="block mx-auto" width="640" height="480" src="artifact://#{file}"><h2 class="mt2 center">#{reason}</h2></div>))
end

# Generic wait function for any metadata key
def wait_for_metadata(key, description = nil)
  puts "Waiting for #{description || key}..."
  loop do
    result = get_move_data(key)
    return result if result != ""
    sleep 0.5
  end
end

# === MAIN GAME EXECUTION ===

puts "Starting Doom..."

# Get initial game settings from Buildkite pipeline input
mode = wait_for_metadata("game_mode", "mode selection")
puts "Game mode: #{mode}"

level = wait_for_metadata("level", "level selection") 
puts "Level: E1M#{level}"

# Start Doom process and pause it initially
doom_pid = start_doom(level)
signal_doom(doom_pid, "STOP")

# Set up graceful shutdown
["INT", "TERM", "HUP", "QUIT"].each do |signal|
  Signal.trap(signal) do
    puts "Received #{signal}, exiting cleanly..."
    signal_doom(doom_pid, "KILL") rescue nil
    exit 0
  end
end

# Main game loop - capture frames, get user input, execute moves
i = 0
move = nil
loop do
  # Resume game, capture frame, execute move, pause game
  signal_doom(doom_pid, "CONT")
  recording = Thread.new { capture_frame(i, i == 0 ? 2.5 : 1.25) }
  send_key(move) if move
  recording.join
  signal_doom(doom_pid, "STOP")
  
  # Upload screenshot and create next input step
  upload_clip(i, mode)
  ask_for_key(i, mode)
  
  puts "Pipeline uploaded, waiting for step to start..."
  sleep 2
  
  # Wait for user's next move
  move = wait_for_metadata("move#{i}", "move #{i}")
  puts "Got move: #{move}"

  # Increment immediately after getting move to prevent infinite loops
  current_move_index = i
  i += 1

  # Handle mode switches and game end (manual mode only)
  if mode == "manual"
    game_option = get_move_data("game_option#{current_move_index}")
    puts "Got game_option: '#{game_option}'"
    
    case game_option
    when "switch_random"
      mode = "random"
      puts "Switched to random mode"
    when "switch_ai"
      mode = "ai"
      puts "Switched to AI mode"
    when "end_game"
      puts "Game ended by user"
      break
    end
  end
  
  # Auto-end game after 100 moves for reasonable session length
  if i >= 100
    puts "Game ended automatically after 100 moves"
    break
  end
  
  # Continue until timeout, move limit, or user ends game
end

puts "Game finished!"
