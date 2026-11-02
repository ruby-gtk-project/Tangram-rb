# frozen_string_literal: true

require 'securerandom'

require_relative 'env'
require_relative 'settings'

# Instance is one tab: an id, the two directories WebKit keeps its data and
# cache in, and the settings holding the name, homepage, user agent and
# notification priority the user chose for it.
#
# Ported from upstream's src/instances.js.
class Instance
  def initialize(id, settings: Settings.instance(id))
    @id = id
    @data_dir = File.join(Env.data_dir, id)
    @cache_dir = File.join(Env.cache_dir, id)
    @settings = settings
  end

  attr_reader :id, :data_dir, :cache_dir, :settings

  # The web view showing this tab, once one has been built for it.
  attr_accessor :web_view

  def name = settings.get_string('name')

  def name=(name)
    settings.set_string('name', name)
  end

  def url = settings.get_string('url')

  def url=(url)
    settings.set_string('url', url)
  end

  def user_agent = settings.get_string('user-agent')

  def user_agent=(user_agent)
    settings.set_string('user-agent', user_agent)
  end

  # The priority as Gio::NotificationPriority orders it, which is how the
  # notification and the dialog's combo row both want it.
  def notifications_priority = settings.get_enum('notifications-priority')

  def notifications_priority=(index)
    settings.set_enum('notifications-priority', index)
  end

  # Calls the block with the key's value now and on every change — upstream's
  # `observe`, which it uses to follow a tab's name and homepage.
  def observe(key, &handler) = settings.observe(key, &handler)

  # Keeps a widget property in step with one of the tab's keys.
  def bind(key, object, property) = settings.bind(key, object, property)

  def ensure_directories
    tap do
      Env.ensure_directory(data_dir)
      Env.ensure_directory(cache_dir)
    end
  end

  # Upstream removes the directories with GLib.rmdir, which only empties a
  # directory that is already empty and reports failure otherwise; a tab that
  # has been browsed keeps its data. Dir.rmdir behaves the same way, and the
  # failure is ignored here for the same reason.
  def remove_directories
    tap do
      [data_dir, cache_dir].each do |directory|
        Dir.rmdir(directory)
      rescue SystemCallError
        nil
      end
    end
  end
end

# Instances is the list of tabs the application knows about, and the
# operations the window performs on it: loading the ids the settings hold,
# attaching a new tab to that list, detaching a deleted one, and creating or
# destroying the tab itself.
#
# Ported from upstream's src/instances.js, whose module-level `list` and
# exported functions become one object the window passes around — the same
# single list, without the global.
class Instances
  include Enumerable

  KEY = 'instances'

  def initialize(settings)
    @settings = settings
    @list = []
  end

  attr_reader :settings

  def each(&) = @list.each(&)

  def list = @list.dup

  def get(id) = @list.find { |instance| instance.id == id }

  # Builds an Instance for every id the settings list, in that order.
  def load
    tap do
      settings.get_strv(KEY).each { |id| @list << Instance.new(id) }
    end
  end

  # Adds the id to the settings list, which is what makes a tab permanent.
  def attach(instance)
    settings.set_strv(KEY, settings.get_strv(KEY) + [instance.id])
    instance
  end

  # Takes the id out of the settings list and answers the position it held, or
  # nil when it was not there.
  def detach(instance)
    ids = settings.get_strv(KEY)
    ids.index(instance.id).then do |index|
      if index
        ids.delete_at(index)
        settings.set_strv(KEY, ids)
      end

      index
    end
  end

  # A new tab, with its directories in place and its name and homepage set,
  # not yet attached: upstream creates the instance when the address is
  # entered and attaches it when "Add" is clicked.
  def create(id: self.class.random_id, name: '', url: '')
    Instance.new(id).tap do |instance|
      instance.ensure_directories
      instance.name = name
      instance.url = url
      @list << instance
    end
  end

  # Forgets the tab and everything stored for it.
  def destroy(instance)
    @list.delete(instance)
    instance.settings.reset_all
    instance.remove_directories
    instance
  end

  # Upstream's `GLib.uuid_string_random()` with the dashes taken out — the id
  # ends up in a settings object path and in two directory names.
  def self.random_id = SecureRandom.uuid.delete('-')
end
