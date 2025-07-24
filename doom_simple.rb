#!/usr/bin/env ruby

require "json"
require "open3"

MOVES = [
  {label: "Move Forward", key: "Up", value: "Up", emoji: "⬆️"},
  {label: "Move Backward", key: "Down", value: "Down", emoji: "⬇️"},
  {label: "Turn Left", key: "Left", value: "Left", emoji: "⬅️"},
  {label: "Turn Right", key: "Right", value: "Right", emoji: "➡️"},
  {label: "Fire", key: "Ctrl", value: "Control_L", emoji: "💥"},
  {label: "Open Door", key: "Space", value: "space", emoji: "🚪"}
]

def setup_doom
  puts "Setting up DOOM..."
  
  # Kill any existing processes
  puts "Killing existing processes..."
  system("pkill -f chocolate-doom 2>/dev/null")
  system("pkill -f Xvfb 2>/dev/null")
  sleep 1
  
  # Start virtual display
  puts "Starting Xvfb..."
  system("Xvfb :99 -screen 0 320x240x24 > /dev/null 2>&1 &")
  sleep 3
  
  # Set display
  ENV["DISPLAY"] = ":99"
  puts "Set DISPLAY=:99"
  
  # Download DOOM WAD if not present
  unless File.exist?("DOOM1.WAD")
    puts "Downloading DOOM shareware..."
    result = system("curl -L -o doom.zip 'https://www.doomworld.com/3ddownloads/ports/shareware_doom_iwad.zip'")
    puts "Download failed!" unless result
    
    result = system("unzip -j doom.zip")
    puts "Unzip failed!" unless result
    
    system("rm -f doom.zip")
    
    unless File.exist?("DOOM1.WAD")
      puts "ERROR: DOOM1.WAD not found after download!"
      exit 1
    end
  end
  
  # Start DOOM in background
  puts "Starting DOOM..."
  system("chocolate-doom -geometry 320x240 -iwad DOOM1.WAD -episode 1 > /dev/null 2>&1 &")
  sleep 5
  
  # Check if DOOM is running
  result = system("pgrep -f chocolate-doom > /dev/null")
  if result
    puts "DOOM is ready!"
  else
    puts "ERROR: DOOM failed to start!"
    exit 1
  end
end

def send_key(key)
  return unless key
  puts "Sending key: #{key}"
  result = system("xdotool key #{key}")
  puts "Key send failed!" unless result
  sleep 0.1
end

def capture_frame(step)
  puts "Capturing frame #{step}..."
  duration = step == 0 ? 3.0 : 1.5
  
  # Capture video as animated PNG
  result = system("ffmpeg -y -t #{duration} -video_size 320x240 -framerate 15 -f x11grab -i :99 #{step}.apng 2>/dev/null")
  puts "Video capture failed!" unless result
  
  # Rename for artifact upload (Buildkite likes .png better)
  if File.exist?("#{step}.apng")
    File.rename("#{step}.apng", "#{step}.png")
  else
    puts "Warning: #{step}.apng not found after capture"
  end
end

def upload_artifact(step)
  file = "#{step}.png"
  return unless File.exist?(file)
  
  puts "Uploading #{file}..."
  system("buildkite-agent artifact upload #{file}")
  
  reason = if step == 0
    "Game started!"
  else
    `buildkite-agent meta-data get "reason_#{step - 1}" 2>/dev/null`.strip
  end
  reason = "Move executed" if reason.empty?
  
  annotation = %(<img width="640" height="480" src="artifact://#{file}"><p>#{reason}</p>)
  Open3.capture2("buildkite-agent annotate", stdin_data: annotation)
end

def ask_for_key(step)
  mode = `buildkite-agent meta-data get "mode" 2>/dev/null`.strip
  
  case mode
  when "random"
    move = MOVES.sample
    reason = "Random move: #{move[:label].downcase}"
    
    # Create pipeline step that sets the metadata
    pipeline = {
      steps: [{
        label: "#{move[:emoji]} #{move[:label]}",
        key: "step_#{step}",
        depends_on: step == 0 ? [] : ["step_#{step - 1}"],
        commands: [
          "buildkite-agent meta-data set \"reason_#{step}\" \"#{reason}\"",
          "buildkite-agent meta-data set \"key_#{step}\" \"#{move[:value]}\""
        ]
      }]
    }
    
    Open3.capture2("buildkite-agent pipeline upload --replace", stdin_data: JSON.generate(pipeline))
    
  else
    # Create input step for manual control (default behavior)
    pipeline = {
      steps: [{
        input: "Choose your move (Step #{step})",
        key: "step_#{step}",
        depends_on: step == 0 ? [] : ["step_#{step - 1}"],
        fields: [{
          select: "What should we do?",
          key: "key_#{step}",
          options: MOVES.map { |m| { label: "#{m[:emoji]} #{m[:label]}", value: m[:value] } }
        }]
      }]
    }
    
    Open3.capture2("buildkite-agent pipeline upload --replace", stdin_data: JSON.generate(pipeline))
  end
end

def wait_for_key(step)
  puts "Waiting for key_#{step}..."
  timeout = 300  # 5 minutes max wait
  elapsed = 0
  
  loop do
    result = `buildkite-agent meta-data get "key_#{step}" 2>/dev/null`.strip
    if !result.empty?
      puts "Got key_#{step}: #{result}"
      return result
    end
    
    sleep 1
    elapsed += 1
    
    if elapsed >= timeout
      puts "Timeout waiting for key_#{step}, using random move"
      move = MOVES.sample
      return move[:value]
    end
  end
end

def cleanup
  puts "Cleaning up..."
  system("pkill -f chocolate-doom 2>/dev/null")
  system("pkill -f Xvfb 2>/dev/null")
end

# Main execution
puts "Starting simple DOOM game..."

# Setup cleanup on exit
at_exit { cleanup }
trap("INT") { cleanup; exit }
trap("TERM") { cleanup; exit }

# Initialize DOOM
setup_doom

step = 0
puts "Starting game loop..."

loop do
  puts "\n=== STEP #{step} ==="
  
  # Capture current frame
  puts "Capturing frame..."
  capture_frame(step)
  
  # Upload to Buildkite
  puts "Uploading artifact..."
  upload_artifact(step)
  
  # Ask for next move (creates pipeline steps)
  puts "Creating next move step..."
  ask_for_key(step)
  
  # Wait for the key to be set by the pipeline step
  puts "Waiting for user input..."
  key = wait_for_key(step)
  
  # Execute the move
  puts "Executing move: #{key}"
  send_key(key)
  
  step += 1
  
  # Limit to reasonable number of steps
  if step >= 20
    puts "Reached step limit"
    break
  end
end

puts "Game complete!"
