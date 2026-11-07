#!/usr/bin/env ruby
# frozen_string_literal: true

# The one gate command: runs every check this port has — the three
# house-style scripts (`check_models.rb`, `drive_main_window.rb`,
# `drive_new_tab.rb`) *and* the RSpec suite (`spec/`) — and prints one
# combined total, so "the gate" means the whole suite rather than three
# scripts someone has to remember to also run RSpec alongside.
#
#   nix develop --command xvfb-run -a ruby test/run_all.rb
#
# Previously the gate's headline number ("128 checks passed") was the sum of
# the three scripts alone; `spec/url_spec.rb` and `spec/web_app_info_spec.rb`
# passed or failed in a separate run that had to be remembered and run by
# hand, and nothing in the 128 said it had been left out. This script runs
# all four itself and folds every one of them into the one number it prints.

require 'tempfile'

root = File.expand_path('..', __dir__)

# Every check runs as its own subprocess, the RSpec suite included. GTK and
# WebKitGTK are not meant to be initialized twice in one process — running
# `drive_*.rb`'s GTK app and then RSpec's WebKit-backed examples in the same
# process (as an earlier version of this script tried, calling
# `RSpec::Core::Runner.run` in-process after shelling out to the drivers)
# crashed the process outright. A fresh `ruby` per check is what every one
# of these already assumed when it was written to be run on its own.
RSPEC_COMMAND =
  'require "rspec/core"; exit RSpec::Core::Runner.run(["--format", "progress", "--require", "spec_helper", "spec"])'

CHECKS = [
  ['check_models.rb', %w[ruby test/check_models.rb]],
  ['drive_main_window.rb', %w[ruby test/drive_main_window.rb]],
  ['drive_new_tab.rb', %w[ruby test/drive_new_tab.rb]],
  ['spec/ (rspec)', ['ruby', '-e', RSPEC_COMMAND]],
].freeze

driver_total = 0
driver_failed = 0
all_ok = true

puts '# Every check'
CHECKS.each do |name, command|
  # Not `Open3.capture3`: it wires the child's stdout/stderr to pipes, and a
  # WebKitGTK-backed child (the RSpec suite's `web_app_info_spec.rb`) aborts
  # partway through every time it is spawned with its stdio on pipes rather
  # than real files — reproduced directly, independent of this script, by
  # running the same `ruby -e` command under `Process.spawn(..., out: pipe)`
  # versus `out: a_tempfile.path`. Real files avoid whatever about a pipe
  # trips WebKit's own child-process spawning, so the output is captured to
  # temp files and read back instead.
  stdout = nil
  status = nil
  Tempfile.create('run_all-out') do |out_file|
    Tempfile.create('run_all-err') do |err_file|
      pid = Process.spawn(*command, chdir: root, out: out_file.path, err: err_file.path)
      Process.wait(pid)
      status = $?
      stdout = File.read(out_file.path)
    end
  end

  # `check_models.rb` prints "N checks, M failed"; the two `drive_*.rb`
  # scripts print "X of Y checks passed"; RSpec's progress formatter prints
  # "N examples, M failures". All three shapes are parsed so this script
  # does not have to be told which kind of check it is running.
  if (match = stdout.match(/(\d+) of (\d+) checks passed/))
    passed = match[1].to_i
    total = match[2].to_i
  elsif (match = stdout.match(/(\d+) checks, (\d+) failed/))
    total = match[1].to_i
    passed = total - match[2].to_i
  elsif (match = stdout.match(/(\d+) examples?, (\d+) failures?/))
    total = match[1].to_i
    passed = total - match[2].to_i
  else
    total = 0
    passed = 0
  end

  ok = status.success? && passed == total && total.positive?
  driver_total += total
  driver_failed += (total - passed)
  all_ok &&= ok

  puts "#{ok ? 'ok  ' : 'FAIL'} #{name} (#{passed}/#{total})"
  unless ok
    puts stdout
  end
end

puts
puts "#{driver_total - driver_failed} of #{driver_total} checks passed across #{CHECKS.length} checks (#{CHECKS.map(&:first).join(', ')})"
puts(all_ok ? 'GATE OK' : 'GATE FAILED')
exit(all_ok ? 0 : 1)
