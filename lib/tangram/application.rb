# frozen_string_literal: true

require 'gtk4'
require 'adwaita'

require_relative '../env'
require_relative '../settings'
require_relative '../instances'
require_relative '../main_menu'
require_relative '../about_dialog'
require_relative '../shortcuts_dialog'

module Tangram
  # The port's application: the window, its primary menu, and the
  # application-level actions that menu drives.
  #
  # Ported from upstream's src/application.js and src/main.js. Upstream's
  # window content is a stack of two views, both of which are built around a
  # WebKit web view; until those land the window carries the welcome page
  # upstream shows on a first run, and the chrome around it — the menu, the
  # about dialog, the shortcuts window, the accelerators and the window
  # geometry — is the real thing.
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

    # The accelerators upstream's src/Shortcuts.js sets for application
    # actions. The rest of that file drives the web view, and arrives with it.
    ACCELERATORS = {
      'app.quit'      => ['<Primary>Q'],
      'app.inspector' => ['<Primary><Shift>D'],
      'app.shortcuts' => ['<Primary>question'],
    }.freeze

    def build
      app.tap do
        app.signal_connect('activate') do
          icon_theme.add_search_path(ICON_PATH)

          ACCELERATORS.each { |action, accels| app.set_accels_for_action(action, accels) }

          app.add_action(about_action)
          app.add_action(shortcuts_action)
          app.add_action(quit_action)
          app.add_action(settings.create_action('tabs-bar'))

          about_action.signal_connect('activate') { about_dialog.present(window) }
          shortcuts_action.signal_connect('activate') { shortcuts_dialog.present(window) }
          quit_action.signal_connect('activate') { app.quit }

          window.tap do |win|
            win.content = toolbar_view
          end

          toolbar_view.tap do |view|
            view.add_top_bar(header_bar)
            view.content = status_page

            header_bar.tap do |bar|
              bar.pack_end(menu_button)
            end
          end

          settings.persist_window_state(window)
          instances.load

          window.present
        end
      end
    end

    # Adwaita::Application is broken in the Ruby bindings; the application
    # object comes from Gtk and only the window is Adwaita.
    def app = @app ||= Gtk::Application.new(APPLICATION_ID, :default_flags)

    def window
      @window ||= Adwaita::ApplicationWindow.new(app).tap do |win|
        win.title = 'Tangram'
        win.width_request = 360
        win.height_request = 360
      end
    end

    def icon_theme = @icon_theme ||= Gtk::IconTheme.get_for_display(Gdk::Display.default)

    def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
    def header_bar = @header_bar ||= Adwaita::HeaderBar.new

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = 'open-menu-symbolic'
        button.tooltip_text = 'Main Menu'
        button.primary = true
        button.menu_model = main_menu.build
      end
    end

    # The welcome page upstream's ViewNew shows when no tab has been added.
    def status_page
      @status_page ||= Adwaita::StatusPage.new.tap do |page|
        page.icon_name = 're.sonny.Tangram'
        page.title = 'Welcome to Tangram'
        page.description = "Let's add your first web application."
      end
    end

    def about_action = @about_action ||= Gio::SimpleAction.new('about')
    def shortcuts_action = @shortcuts_action ||= Gio::SimpleAction.new('shortcuts')
    def quit_action = @quit_action ||= Gio::SimpleAction.new('quit')

    def settings = @settings ||= Settings.application
    def instances = @instances ||= Instances.new(settings)

    def main_menu = @main_menu ||= MainMenu.new
    def about_dialog = @about_dialog ||= AboutDialog.new
    def shortcuts_dialog = @shortcuts_dialog ||= ShortcutsDialog.new
  end
end
