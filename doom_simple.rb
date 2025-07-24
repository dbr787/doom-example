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
  system("pkill -f chocolate-doom 2>/dev/null")
  system("pkill -f Xvfb 2>/dev/null")
  
  # Start virtual display
  system("Xvfb :99 -screen 0 320x240x24 &")
  sleep 2
  
  # Set display
  ENV["DISPLAY"] = ":99"
  
  # Download DOOM WAD if not present
  unless File.exist?("DOOM1.WAD")
    puts "Downloading DOOM shareware..."
    system("curl -L -o doom.zip 'https://www.doomworld.com/3ddownloads/ports/shareware_doom_iwad.zip'")
    system("unzip -j doom.zip")
    system("rm -f doom.zip")
  end
  
  # Start DOOM in background
  system("chocolate-doom -geometry 320x240 -iwad DOOM1.WAD -episode 1 &")
  sleep 3
  
  puts "DOOM is ready!"
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

def upload_artifact(step, reason = nil)
  file = "#{step}.png"
  return unless File.exist?(file)
  
  puts "Uploading #{file}..."
  system("buildkite-agent artifact upload #{file}")
  
  reason ||= step == 0 ? "Game started!" : "Move executed"
  
  annotation = %(<img width="640" height="480" src="artifact://#{file}"><p>#{reason}</p>)
  Open3.capture2("buildkite-agent annotate", stdin_data: annotation)
end

def get_next_move(step)
  mode = `buildkite-agent meta-data get "mode" 2>/dev/null`.strip
  
  case mode
  when "random"
    move = MOVES.sample
    reason = "Random move: #{move[:label].downcase}"
    puts "Random mode: #{move[:key]}"
    return move[:value], reason
    
  when "manual"
    # Create input step for manual control
    pipeline = {
      steps: [{
        input: "Choose your move (Step #{step})",
        key: "move_#{step}",
        fields: [{
          select: "What should we do?",
          key: "key_#{step}",
          options: MOVES.map { |m| { label: "#{m[:emoji]} #{m[:label]}", value: m[:value] } }
        }]
      }]
    }
    
    stdout, stderr = Open3.capture2("buildkite-agent pipeline upload", stdin_data: JSON.generate(pipeline))
    puts "Pipeline upload result: #{stdout}" if stdout && !stdout.empty?
    puts "Pipeline upload error: #{stderr}" if stderr && !stderr.empty?
    
    # Wait for input
    puts "Waiting for manual input..."
    loop do
      result = `buildkite-agent meta-data get "key_#{step}" 2>/dev/null`.strip
      if !result.empty?
        move = MOVES.find { |m| m[:value] == result }
        return result, "Manual choice: #{move ? move[:label].downcase : result}"
      end
      sleep 1
    end
    
  else
    # Default to random if mode not set
    move = MOVES.sample  
    reason = "Default random move: #{move[:label].downcase}"
    puts "No mode set, using random: #{move[:key]}"
    return move[:value], reason
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
loop do
  # Get next move
  key, reason = get_next_move(step)
  
  # Execute move
  send_key(key)
  
  # Capture result
  capture_frame(step)
  
  # Upload to Buildkite
  upload_artifact(step, reason)
  
  step += 1
  
  # Limit to reasonable number of steps
  break if step >= 20
end

puts "Game complete!"
