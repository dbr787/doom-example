#!/usr/bin/env ruby

require "json"

# Container script - only handles DOOM execution, no buildkite operations

def send_key(key)
  delay = case key
  when "Control_L", "space" then 100
  else 1000
  end

  system "xdotool key --delay #{delay} #{key}"
end

def start_doom
  ENV["DISPLAY"] = ":1"

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

def grab_frames(step, duration)
  system "ffmpeg -y -t #{duration} -video_size 320x240 -framerate 15 -f x11grab -i :1 -loop -1 /output/#{step}.apng"
  system "rm ./frame_*.png"
  system "ffmpeg -i /output/#{step}.apng -vsync 0 /output/frame_%03d.png"
end

# Main execution
step = ARGV[0].to_i
key = ARGV[1]
duration = step == 0 ? 2.5 : 1.25

puts "Running DOOM step #{step} with key: #{key || 'none'}"

doom_pid = start_doom
signal_doom(doom_pid, "STOP")

["INT", "TERM", "HUP", "QUIT"].each do |signal|
  Signal.trap(signal) do
    puts "Received #{signal}, exiting cleanly..."
    exit 0
  end
end

signal_doom(doom_pid, "CONT")
recording = Thread.new { grab_frames(step, duration) }
send_key(key) if key
recording.join
signal_doom(doom_pid, "STOP")

puts "DOOM step #{step} completed"
