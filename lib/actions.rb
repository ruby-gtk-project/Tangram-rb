# frozen_string_literal: true

require 'adwaita'

require_relative 'about_dialog'
require_relative 'shortcuts_dialog'

# Actions is the window's and the application's action set: the two dialogs
# the main menu opens, the tabs-bar toggle behind its first item, quit, the
# tab editor the header bars' "Edit Tab" buttons point at, and the action a
# notification's default activation carries, which brings its tab to the
# front.
#
# Ported from upstream's src/Actions.js. Upstream builds its about dialog and
# its shortcuts window here; this port has a class for each, so they are
# memoized the way every other widget is.
class Actions
  SHOW_INSTANCE = 'showInstance'
  EDIT_TAB = 'editTab'
  TABS_BAR = 'tabs-bar'

  def initialize(
    window:,
    application:,
    settings:,
    state:,
    instances:,
    select_tab:,
    edit_tab:
  )
    @window = window
    @application = application
    @settings = settings
    @state = state
    @instances = instances
    @select_tab = select_tab
    @edit_tab = edit_tab
  end

  attr_reader :window, :application, :settings, :state, :instances

  def build
    @build ||= application.tap do |app|
      app.add_action(about_action)
      app.add_action(shortcuts_action)
      app.add_action(quit_action)
      app.add_action(show_instance_action)
      app.add_action(tabs_bar_action)

      window.add_action(edit_tab_action)

      about_action.signal_connect('activate') { about_dialog.present(window) }
      shortcuts_action.signal_connect('activate') { shortcuts_dialog.present(window) }
      quit_action.signal_connect('activate') { app.quit }
      edit_tab_action.signal_connect('activate') { edit_current_tab }

      show_instance_action.signal_connect('activate') do |_action, parameter|
        show_instance(parameter.value)
      end
    end
  end

  def about_action = @about_action ||= Gio::SimpleAction.new('about')
  def shortcuts_action = @shortcuts_action ||= Gio::SimpleAction.new('shortcuts')
  def quit_action = @quit_action ||= Gio::SimpleAction.new('quit')
  def edit_tab_action = @edit_tab_action ||= Gio::SimpleAction.new(EDIT_TAB)

  # The tab id travels with the notification that brought it, as the string
  # parameter of `app.showInstance('<id>')`.
  def show_instance_action
    @show_instance_action ||= Gio::SimpleAction.new(SHOW_INSTANCE, GLib::VariantType.new('s'))
  end

  # GSettings' own action, so the menu's "Show Tabs Bar" item toggles the key
  # the tabs bar's visibility follows.
  def tabs_bar_action = @tabs_bar_action ||= settings.create_action(TABS_BAR)

  def about_dialog = @about_dialog ||= AboutDialog.new
  def shortcuts_dialog = @shortcuts_dialog ||= ShortcutsDialog.new

  private

    def show_instance(id)
      instances.get(id).then do |instance|
        if instance
          @select_tab.call(instance)
        end
      end

      window.present
    end

    def edit_current_tab
      instance_in_front.then do |instance|
        if instance
          @edit_tab.call(instance)
        end
      end
    end

    def instance_in_front
      state.get('webview').then do |web_view|
        if web_view&.instance_id
          instances.get(web_view.instance_id)
        end
      end
    end
end
