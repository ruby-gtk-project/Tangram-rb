#!/usr/bin/env ruby
# frozen_string_literal: true

# Plain checks on the port's non-widget code: the environment, the settings
# store, the state bag, the tab list and the URL helpers. No display and no
# main loop, so this runs in milliseconds.
#
# The same-site cases are upstream's own, ported one for one from
# src/utils.test.js.
#
#   nix develop --command ruby test/check_models.rb

require 'tmpdir'

root = Dir.mktmpdir('tangram-check')
ENV['XDG_CONFIG_HOME'] = File.join(root, 'config')
ENV['XDG_DATA_HOME'] = File.join(root, 'data')
ENV['XDG_CACHE_HOME'] = File.join(root, 'cache')
ENV.delete('DEV')
ENV.delete('FLATPAK_ID')

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'env'
require 'settings'
require 'state'
require 'instances'
require 'url'

CHECKS = {count: 0, failed: []}

def check(description)
  CHECKS[:count] += 1
  yield.then do |ok|
    puts(ok ? "ok   #{description}" : "FAIL #{description}")
    unless ok
      CHECKS[:failed] << description
    end
  end
rescue StandardError => error
  puts "FAIL #{description} (#{error.class}: #{error.message})"
  CHECKS[:failed] << description
end

puts '# Env'
Env.reset!
check('host environment without DEV or FLATPAK_ID') { Env.host? }
check('data dir under XDG_DATA_HOME') { Env.data_dir == File.join(ENV.fetch('XDG_DATA_HOME'), 'Tangram') }
check('cache dir under XDG_CACHE_HOME') { Env.cache_dir == File.join(ENV.fetch('XDG_CACHE_HOME'), 'Tangram') }
check('applications dir beside the data dir') do
  Env.applications_dir == File.join(ENV.fetch('XDG_DATA_HOME'), 'applications')
end
check('ensure_directory makes parents') do
  Env.ensure_directory(File.join(root, 'a/b/c'))
  Dir.exist?(File.join(root, 'a/b/c'))
end
check('ensure_directory is happy twice') do
  Env.ensure_directory(File.join(root, 'a/b/c'))
  Dir.exist?(File.join(root, 'a/b/c'))
end

puts '# Settings'
settings = Settings.application
check('schema defaults') do
  settings['window-width'] == 800 &&
    settings['window-height'] == 600 &&
    settings['tabs-bar'] == true &&
    settings.get_strv('instances').empty?
end
check('unknown keys raise') do
  begin
    settings['no-such-key']
    false
  rescue KeyError
    true
  end
end
check('a write is readable') do
  settings.set_int('window-width', 1024)
  settings.get_int('window-width') == 1024
end
check('a write survives a new store') do
  Settings.reset!
  Settings.application.get_int('window-width') == 1024
end
check('strv round trip') do
  Settings.reset!
  Settings.application.set_strv('instances', %w[one two])
  Settings.application.get_strv('instances') == %w[one two]
end
check('reset puts the default back') do
  Settings.reset!
  Settings.application.tap { |s| s.reset('window-width') }
  Settings.application.get_int('window-width') == 800
end
check('observe fires with the current value and on change') do
  Settings.reset!
  seen = []
  one = Settings.application
  one.observe('tabs-bar') { |value| seen << value }
  Settings.application.set_boolean('tabs-bar', false)
  seen == [true, false]
end
check('enum reads as an index and writes as a nick') do
  Settings.instance('abc').tap do |instance_settings|
    instance_settings.set_enum('notifications-priority', 3)
  end
  Settings.instance('abc').get_enum('notifications-priority') == 3 &&
    Settings.instance('abc')['notifications-priority'] == 'urgent'
end
check('reset_all clears a tab path') do
  Settings.instance('abc').reset_all
  Settings.instance('abc').get_enum('notifications-priority').zero?
end
check('create_action carries the key as its state') do
  Settings.reset!
  Settings.application.tap { |application| application.reset('tabs-bar') }
  Settings.application.create_action('tabs-bar').state == true
end
check('toggling the action writes the key') do
  Settings.reset!
  Settings.application.create_action('tabs-bar').tap do |action|
    action.change_state(GLib::Variant.new(false))
  end
  Settings.application.get_boolean('tabs-bar') == false
end

puts '# State'
state = State.new
check('an unset property is nil') { state.get('view').nil? }
check('set then get') { state.set(view: 'tabs').get('view') == 'tabs' }
check('notify carries the new and previous values') do
  seen = []
  state.notify('view') { |value, previous| seen << [value, previous] }
  state.set(view: 'new')
  seen == [['new', 'tabs']]
end
check('bind assigns the current value') do
  label = Gtk::Label.new
  state.set(label: 'Tangram')
  state.bind('label', label, 'label')
  label.label == 'Tangram'
end
check('bind follows later changes through the block') do
  label = Gtk::Label.new
  state.set(title: 'one')
  state.bind('title', label, 'label') { |value| value.upcase }
  state.set(title: 'two')
  label.label == 'TWO'
end

puts '# Instances'
Settings.reset!
Env.reset!
Settings.application.reset('instances')
instances = Instances.new(Settings.application)
created = instances.create(name: 'Example', url: 'https://example.org')
check('create registers the tab') { instances.list.map(&:id) == [created.id] }
check('create makes the data and cache directories') do
  Dir.exist?(created.data_dir) && Dir.exist?(created.cache_dir)
end
check('create keeps the name and homepage') do
  created.name == 'Example' && created.url == 'https://example.org'
end
check('a new tab is not attached yet') { Settings.application.get_strv('instances').empty? }
check('attach adds the id to the settings') do
  instances.attach(created)
  Settings.application.get_strv('instances') == [created.id]
end
check('load rebuilds the list from the settings') do
  Instances.new(Settings.application).load.list.map(&:id) == [created.id]
end
check('a loaded tab reads back its name') do
  Instances.new(Settings.application).load.list.first.name == 'Example'
end
check('detach answers the position and drops the id') do
  instances.detach(created) == 0 && Settings.application.get_strv('instances').empty?
end
check('detaching twice answers nil') { instances.detach(created).nil? }
check('observe sees a name change') do
  seen = []
  instance = Instances.new(Settings.application).create(name: 'Watched')
  instance.observe('name') { |value| seen << value }
  instance.name = 'Renamed'
  seen == %w[Watched Renamed]
end
check('destroy forgets the tab and its settings') do
  instances.destroy(created)
  instances.list.empty? && created.name.empty? && created.url.empty?
end
check('ids are hex with no dashes') { Instances.random_id.match?(/\A[0-9a-f]{32}\z/) }

puts '# Url (upstream src/utils.test.js)'
[
  ['https://github.com', 'https://github.com', true],
  ['https://github.com', 'http://github.com', true],
  ['https://github.com:123', 'http://github.com:567/foobar', true],
  ['https://foo.github.com', 'https://github.com', true],
  ['https://foo.github.com', 'https://bar.github.com', true],
  [
    'https://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]',
    'https://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]',
    true,
  ],
  ['https://192.0.2.235', 'https://192.0.2.235', true],
  ['https://localhost', 'https://localhost', true],
  ['https://github.io', 'https://github.io', true],
  ['https://ком.рус', 'https://xn--j1aef.xn--p1acf', true],
  ['about:blank', 'about:blank', true],
  ['https://foo', 'https://bar', false],
  ['https://foo.github.io', 'https://bar.github.io', false],
  ['https://foo.github.io', 'https://github.io', false],
  # ком.рус is a public suffix
  ['https://foo.ком.рус', 'https://bar.xn--j1aef.xn--p1acf', false],
  # кто.рф is not a public suffix
  ['https://foo.кто.рф', 'https://bar.xn--j1ail.xn--p1ai', true],
].each do |first, second, expected|
  check("same_site?(#{first}, #{second}) is #{expected}") do
    Url.same_site?(first, second) == expected
  end
end

check('punycodes a host the way g_hostname_to_ascii does') do
  Url.to_ascii('ком.рус') == 'xn--j1aef.xn--p1acf' && Url.to_ascii('münchen.de') == 'xn--mnchen-3ya.de'
end
check('normalize adds the scheme') { Url.normalize('example.org') == 'http://example.org' }
check('normalize keeps path and query') { Url.normalize('https://a.org/b?c=1') == 'https://a.org/b?c=1' }
check('normalize refuses nothing') { Url.normalize('').nil? && Url.normalize(nil).nil? }
# Anything without an http prefix is given one, so the scheme check only
# turns away a string that starts with "http" and is not http(s) — which is
# how upstream's normalizeURL behaves too.
check('normalize refuses an http-ish scheme that is not http') do
  Url.normalize('httpx://example.org').nil?
end
check('a tab being set up may navigate anywhere') do
  Url.allowed_for_navigation?(
    current_url: 'https://example.org',
    request_url: 'https://elsewhere.test',
    temporary:   true,
  )
end
check('an added tab stays on its own site') do
  Url.allowed_for_navigation?(
    current_url: 'https://example.org',
    request_url: 'https://elsewhere.test',
    temporary:   false,
  ) == false
end

puts
puts "#{CHECKS[:count]} checks, #{CHECKS[:failed].length} failed"
CHECKS[:failed].each { |description| puts "  #{description}" }
exit(CHECKS[:failed].empty? ? 0 : 1)
