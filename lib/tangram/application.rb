# frozen_string_literal: true

require 'gtk4'
require 'adwaita'

require_relative '../state'
require_relative '../window'

module Tangram
  # The port's application: the one window, presented on activation.
  #
  # Ported from upstream's src/application.js and src/main.js. Upstream's
  # Adw.Application is a Gtk::Application here, because Adwaita::Application
  # is unusable in the Ruby bindings; the window and everything in it is
  # Adwaita's.
  #
  # Upstream's `__DEV__` restart action is left out: it exists so a running
  # app can re-exec the bundle a Flatpak dev build was built from, and this
  # port has no such build to re-exec.
  #
  # House style (see .claude/skills/ruby-gtk): every widget is a memoized
  # method, all configuration lives in its `tap`, assembly happens only in
  # `build`, and the launcher is one expression.
  class Application
    APPLICATION_ID = 'org.rubygtkproject.Tangram'

    # The application icon, which upstream installs into the system icon
    # theme from data/icons; run from a checkout there is no install step, so
    # the directory is added to the theme's search path instead.
    ICON_PATH = File.expand_path('../../data/icons', __dir__)

    # Upstream's src/style.css, installed as a GResource there; run from a
    # checkout it is loaded straight off disk instead.
    STYLE_PATH = File.expand_path('../../data/style.css', __dir__)

    # What PulseAudio labels the app's streams with, which is how a web app
    # playing video shows up in the system's volume controls — upstream sets
    # these two before the application is built.
    PULSE_PROPERTIES = {
      'PULSE_PROP_application.icon_name' => 're.sonny.Tangram-symbolic',
      'PULSE_PROP_media.role'            => 'video',
    }.freeze

    def build
      app.tap do
        PULSE_PROPERTIES.each { |name, value| ENV[name] = value }

        app.signal_connect('activate') do
          icon_theme.add_search_path(ICON_PATH)
          Gtk::StyleContext.add_provider_for_display(
            Gdk::Display.default,
            style_provider,
            Gtk::StyleProvider::PRIORITY_APPLICATION,
          )

          app.add_window(window.build)
          window.present
        end
      end
    end

    def run = app.run([])

    # Adwaita::Application is broken in the Ruby bindings; the application
    # object comes from Gtk and everything in the window is Adwaita's.
    def app = @app ||= Gtk::Application.new(APPLICATION_ID, :default_flags)

    def window = @window ||= Window.new(application: app, state: state)
    def state = @state ||= State.new

    def icon_theme = @icon_theme ||= Gtk::IconTheme.get_for_display(Gdk::Display.default)

    def style_provider = @style_provider ||= Gtk::CssProvider.new.tap { |p| p.load_from_path(STYLE_PATH) }
  end
end
