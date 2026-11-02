# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'gtk4'

require_relative 'env'

# Settings holds the keys of the two GSettings schemas upstream ships in
# data/re.sonny.Tangram.gschema.xml, with the same defaults and the same
# semantics, and the helpers upstream's src/util.js wraps GSettings in.
#
# Upstream talks to GSettings, which needs a compiled schema installed into a
# directory on XDG_DATA_DIRS; requiring an install step before the app can run
# from a checkout is worse than the alternative, so the keys are backed by one
# JSON file under the environment's config directory instead. The file is laid
# out the way dconf is — keyed by the schema's object path — so one store holds
# the application's own keys at "/re/sonny/Tangram/" and every tab's keys at
# "/re/sonny/Tangram/instances/<id>/".
#
# `observe` is upstream's util.js `observeSetting`, `create_action` is
# GSettings' own `create_action`, and `persist_window_state` is the
# `persistWindowState` helper the window imports from troll/src/util.js.
class Settings
  APPLICATION_SCHEMA = 're.sonny.Tangram'
  INSTANCE_SCHEMA = 're.sonny.Tangram.Instance'

  APPLICATION_PATH = '/re/sonny/Tangram/'

  # The nicks of re.sonny.Tangram.NotificationPriority, in value order, which
  # is also the order of Gio::NotificationPriority and of the strings the
  # instance dialog's combo row shows.
  NOTIFICATION_PRIORITIES = %w[normal low high urgent].freeze

  SCHEMAS = {
    APPLICATION_SCHEMA => {
      'window-width'        => 800,
      'window-height'       => 600,
      'window-maximized'    => false,
      'window-fullscreened' => false,
      'tabs-bar'            => true,
      'instances'           => [],
    }.freeze,
    INSTANCE_SCHEMA    => {
      'name'                   => '',
      'url'                    => '',
      'user-agent'             => '',
      'notifications-priority' => 'normal',
    }.freeze,
  }.freeze

  # The keys whose values are enum nicks rather than plain strings.
  ENUMS = {
    'notifications-priority' => NOTIFICATION_PRIORITIES,
  }.freeze

  # Store is the JSON file every Settings object reads and writes through. One
  # store per file keeps the observers in one place, so a change made through
  # one Settings object reaches the observers registered through another one on
  # the same path — which is what GSettings does.
  class Store
    def initialize(path)
      @path = path
      @data = read
      @observers = {}
    end

    attr_reader :path

    def values(object_path) = @data.fetch(object_path, {})

    def set(object_path, key, value)
      @data[object_path] ||= {}
      @data[object_path][key] = value
      write
      notify(object_path, key, value)
      value
    end

    # Takes the key out of the store and tells the observers the value they
    # will read from now on, which is the schema's default.
    def unset(object_path, key, default)
      @data.fetch(object_path, {}).delete(key)
      write
      notify(object_path, key, default)
      default
    end

    def unset_all(object_path)
      @data.delete(object_path)
      write
      object_path
    end

    def subscribe(object_path, key, &handler)
      @observers[object_path] ||= {}
      @observers[object_path][key] ||= []
      @observers[object_path][key] << handler
      handler
    end

    private

      def notify(object_path, key, value)
        @observers.dig(object_path, key).to_a.each { |handler| handler.call(value) }
      end

      def read
        if File.exist?(@path)
          JSON.parse(File.read(@path))
        else
          {}
        end
      rescue JSON::ParserError
        {}
      end

      # Written to a sibling file and renamed, so a crash half way through a
      # write cannot leave a truncated store behind.
      def write
        FileUtils.mkdir_p(File.dirname(@path))
        temporary = "#{@path}.#{Process.pid}.tmp"
        File.write(temporary, "#{JSON.pretty_generate(@data)}\n")
        File.rename(temporary, @path)
      end
  end

  class << self
    # The store every Settings object uses unless it is handed another one, so
    # the application's keys and each tab's keys share a file.
    def store = @store ||= Store.new(File.join(Env.config_dir, 'settings.json'))

    # Drops the shared store, so a later call reads the file again. The specs
    # point the environment at a temporary directory per example and need the
    # store to follow.
    def reset!
      @store = nil
    end

    # The application's own settings: upstream's
    # `new Settings({ schema_id: "re.sonny.Tangram", path: "/re/sonny/Tangram/" })`.
    def application = new(schema_id: APPLICATION_SCHEMA, path: APPLICATION_PATH)

    # A tab's settings, at the path upstream's Instance uses.
    def instance(id)
      new(
        schema_id: INSTANCE_SCHEMA,
        path:      "#{APPLICATION_PATH}instances/#{id}/",
      )
    end
  end

  def initialize(schema_id:, path:, store: Settings.store)
    @schema_id = schema_id
    @path = path
    @store = store
    @defaults = SCHEMAS.fetch(schema_id)
  end

  attr_reader :schema_id, :path, :store

  def [](key)
    @store.values(@path).fetch(known(key)) { default(key) }
  end

  def []=(key, value)
    @store.set(@path, known(key), value)
  end

  def default(key) = duplicate(@defaults.fetch(key.to_s))

  def get_string(key) = self[key].to_s
  def set_string(key, value) = self[key] = value.to_s

  def get_boolean(key) = self[key] == true
  def set_boolean(key, value) = self[key] = value == true

  def get_int(key) = self[key].to_i
  def set_int(key, value) = self[key] = value.to_i

  def get_strv(key) = Array(self[key]).map(&:to_s)
  def set_strv(key, value) = self[key] = Array(value).map(&:to_s)

  # GSettings reports an enum as its position in the schema's value list, and
  # stores it as the nick.
  def get_enum(key) = nicks(key).index(get_string(key)).to_i
  def set_enum(key, index) = self[key] = nicks(key).fetch(index)

  # Puts the key back to the schema's default.
  def reset(key) = @store.unset(@path, known(key), default(key))

  # Upstream resets a tab's whole path when the tab is deleted.
  def reset_all
    tap do
      @defaults.each_key { |key| reset(key) }
      @store.unset_all(@path)
    end
  end

  # Calls the block with the key's current value, then again on every change —
  # upstream's util.js `observeSetting`.
  def observe(key, &handler)
    handler.call(self[key])
    @store.subscribe(@path, key.to_s, &handler)
  end

  # Keeps a widget property in step with a key, the direction GSettings calls
  # GET: the setting drives the widget. Two-way bindings in upstream are all
  # for widgets a `create_action` toggle drives instead.
  def bind(key, object, property)
    observe(key) { |value| object.set_property(property.to_s.tr('_', '-'), value) }
    object
  end

  # A Gio action backed by the key, so a menu item can toggle it — GSettings'
  # own `create_action`, which upstream uses for "Show Tabs Bar".
  def create_action(key)
    Gio::SimpleAction.new(key.to_s, nil, GLib::Variant.new(self[key])).tap do |action|
      # The state arrives unwrapped from the binding, and goes back wrapped:
      # `change-state` hands the handler a Ruby value, while `set_state`
      # insists on a GLib::Variant.
      action.signal_connect('change-state') do |_action, value|
        self[key] = value
      end

      observe(key) { |value| action.set_state(GLib::Variant.new(value)) }
    end
  end

  # Restores the geometry the last run left behind and records the next one —
  # folded in from troll/src/util.js `persistWindowState`, which the window
  # calls with these same four keys.
  def persist_window_state(window)
    window.set_default_size(self['window-width'], self['window-height'])

    if self['window-maximized']
      window.maximize
    end

    if self['window-fullscreened']
      window.fullscreen
    end

    window.signal_connect('close-request') do
      remember_window_state(window)
      false
    end

    window
  end

  # Records the geometry, skipping the size while the window fills the screen
  # so the size restored is the one the user chose.
  def remember_window_state(window)
    self['window-maximized'] = window.maximized?
    self['window-fullscreened'] = window.fullscreened?

    unless window.maximized? || window.fullscreened?
      self['window-width'] = window.default_width
      self['window-height'] = window.default_height
    end

    window
  end

  private

    # The key's name, having checked the schema declares it: a typo in a key
    # should fail where it is written, not read back as a silent default.
    def known(key)
      unless @defaults.key?(key.to_s)
        raise KeyError, "#{@schema_id} has no key #{key}"
      end

      key.to_s
    end

    def nicks(key) = ENUMS.fetch(key.to_s)

    def duplicate(value)
      case value
      when Array, Hash, String then value.dup
      else value
      end
    end
end
