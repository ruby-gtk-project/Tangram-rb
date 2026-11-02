# frozen_string_literal: true

require 'fileutils'

# Env reports which of the three environments Tangram is running in, and the
# directories it may write to in that environment.
#
# Ported from upstream's src/env.js. Upstream asks GLib for the XDG base
# directories; this port reads the same XDG variables directly, with the same
# fallbacks GLib applies, so no binding is needed for a handful of paths.
#
# The one upstream export left out is `keyfile_settings_path`: it exists so the
# dev environment can point GSettings at a keyfile backend under `var/config`.
# This port stores settings in a JSON file of its own (see Settings), and that
# file's location is `config_dir`, which branches on the environment in exactly
# the same way.
module Env
  FLATPAK = 'flatpak'
  DEV = 'dev'
  HOST = 'host'

  class << self
    # One of FLATPAK, DEV or HOST.
    def current = @current ||= detect

    def flatpak? = current == FLATPAK
    def dev? = current == DEV
    def host? = current == HOST

    def data_dir
      @data_dir ||= resolve('var/data/Tangram', File.join(user_data_dir, 'Tangram'))
    end

    def cache_dir
      @cache_dir ||= resolve('var/cache/Tangram', File.join(user_cache_dir, 'Tangram'))
    end

    def config_dir
      @config_dir ||= resolve('var/config/Tangram', File.join(user_config_dir, 'Tangram'))
    end

    # Where a desktop entry for a tab would go. Under Flatpak the sandbox's own
    # data directory is not on the host's XDG_DATA_DIRS, so the entry has to be
    # written to the real home directory instead.
    def applications_dir
      @applications_dir ||= applications_dir_for(current)
    end

    # Creates a directory and every missing parent, and says nothing when it is
    # already there — upstream's util.js `ensureDirectory`.
    def ensure_directory(path)
      FileUtils.mkdir_p(path)
      path
    end

    # Drops the memoized paths. The specs set XDG variables per example, and
    # without this they would all see whichever directory the first example
    # happened to resolve.
    def reset!
      @current = nil
      @data_dir = nil
      @cache_dir = nil
      @config_dir = nil
      @applications_dir = nil
    end

    private

      # On Flatpak 1.0 (Ubuntu 18.04 and derivatives such as Mint 19.3)
      # FLATPAK_ID is not defined, hence the second test.
      def detect
        if ENV['FLATPAK_ID'] || File.exist?('/.flatpak-info')
          FLATPAK
        elsif ENV['DEV']
          DEV
        else
          HOST
        end
      end

      def applications_dir_for(env)
        case env
        when DEV then File.join(Dir.pwd, 'var/applications')
        when FLATPAK then File.join(Dir.home, '.local/share/applications')
        else File.join(user_data_dir, 'applications')
        end
      end

      # In the dev environment everything lives under the checkout, so a run
      # from a working copy leaves the installed app's data alone.
      def resolve(dev_path, host_path)
        if dev?
          File.join(Dir.pwd, dev_path)
        else
          host_path
        end
      end

      def user_data_dir = ENV.fetch('XDG_DATA_HOME', File.join(Dir.home, '.local/share'))
      def user_cache_dir = ENV.fetch('XDG_CACHE_HOME', File.join(Dir.home, '.cache'))
      def user_config_dir = ENV.fetch('XDG_CONFIG_HOME', File.join(Dir.home, '.config'))
  end
end
