# frozen_string_literal: true

require 'adwaita'

require_relative 'actions'
require_relative 'instances'
require_relative 'settings'
require_relative 'shortcuts'
require_relative 'tabs'
require_relative 'view_new'
require_relative 'view_tabs'
require_relative 'web_app_info'

# Window is the application's one window: a stack of the two views, the tab
# list behind them, and the navigation the header bars, the shortcuts and the
# actions all drive through it.
#
# Ported from upstream's src/window.blp and src/window.js.
class Window
  TITLE = 'Tangram'

  MINIMUM_SIZE = 360

  # Narrower than this and the navigation controls move to a bottom bar; see
  # ViewTabs' `reveal_bars`.
  BREAKPOINT = 'max-width: 460'

  TABS_VIEW = 'tabs'
  NEW_VIEW = 'new'

  # Gio's priorities in the order of the schema's NotificationPriority enum,
  # which is the order `Instance#notifications_priority` answers in.
  NOTIFICATION_PRIORITIES = [
    Gio::NotificationPriority::NORMAL,
    Gio::NotificationPriority::LOW,
    Gio::NotificationPriority::HIGH,
    Gio::NotificationPriority::URGENT,
  ].freeze

  def initialize(application:, state:)
    @application = application
    @state = state
  end

  attr_reader :application, :state

  def build
    @build ||= window.tap do |win|
      win.content = stack_views
      win.add_breakpoint(breakpoint)

      stack_views.tap do |stack|
        stack.add_named(view_tabs.build, TABS_VIEW)
        stack.add_named(view_new.build, NEW_VIEW)
      end

      state.bind('view', stack_views, 'visible_child_name')

      settings.persist_window_state(win)

      load_tabs

      # Upstream observes the key rather than its own list, so a tab deleted
      # or added anywhere — including by another window of the same app —
      # moves the window to the view that makes sense.
      settings.observe('instances') { |ids| follow_tab_list(ids) }

      shortcuts.build
      actions.build
    end
  end

  def present = build.present

  def window
    @window ||= Adwaita::ApplicationWindow.new(application).tap do |win|
      win.title = TITLE
      win.resizable = true
      win.width_request = MINIMUM_SIZE
      win.height_request = MINIMUM_SIZE
    end
  end

  def breakpoint
    @breakpoint ||= Adwaita::Breakpoint.new(Adwaita::BreakpointCondition.parse(BREAKPOINT))
  end

  def stack_views
    @stack_views ||= Gtk::Stack.new.tap do |stack|
      stack.hhomogeneous = true
      stack.transition_type = :crossfade
    end
  end

  def settings = @settings ||= Settings.application
  def instances = @instances ||= Instances.new(settings)

  def view_tabs
    @view_tabs ||= ViewTabs.new(
      state:           state,
      settings:        settings,
      instances:       instances,
      window:          window,
      breakpoint:      breakpoint,
      on_reload:       method(:reload),
      on_stop_loading: method(:stop_loading),
      on_go_back:      method(:go_back),
      on_go_forward:   method(:go_forward),
      on_go_home:      method(:go_home),
      on_new_tab:      -> { view_new.on_new_tab },
      on_notification: method(:notify),
      delete_tab:      method(:delete_tab),
    )
  end

  def view_new
    @view_new ||= ViewNew.new(
      state:             state,
      instances:         instances,
      window:            window,
      on_add_tab:        method(:add_tab),
      on_cancel_new_tab: method(:cancel_new_tab),
      on_notification:   method(:notify),
    )
  end

  def tabs = view_tabs.tabs

  def shortcuts
    @shortcuts ||= Shortcuts.new(
      window:                  window,
      application:             application,
      on_reload:               method(:reload),
      on_stop_loading:         method(:stop_loading),
      on_go_back:              method(:go_back),
      on_go_forward:           method(:go_forward),
      on_go_home:              method(:go_home),
      on_toggle_web_inspector: method(:toggle_web_inspector),
      on_focus_address_bar:    -> { view_new.focus_address_bar },
    )
  end

  def actions
    @actions ||= Actions.new(
      window:      window,
      application: application,
      settings:    settings,
      state:       state,
      instances:   instances,
      select_tab:  ->(instance) { tabs.select_tab(instance) },
      edit_tab:    ->(instance) { tabs.edit_tab(instance) },
    )
  end

  private

    # Every tab the settings remember, in the order they were added. A window
    # that opens with more than one of them opens in the overview, so the user
    # picks which web app they came for.
    def load_tabs
      instances.load
      instances.each { |instance| tabs.add_tab(instance) }
      view_tabs.tab_overview.open = instances.list.length > 1
    end

    def follow_tab_list(ids)
      state.set(instances: Array(ids))

      if Array(ids).empty?
        view_new.on_new_tab
      else
        state.set(view: TABS_VIEW)
      end
    end

    def web_view_in_front = state.get('webview')

    def stop_loading
      web_view_in_front&.stop_loading
    end

    def reload(bypass_cache)
      web_view_in_front.then do |view|
        if view
          reload_view(view, bypass_cache)
        end
      end
    end

    def reload_view(view, bypass_cache)
      if bypass_cache
        view.reload_bypass_cache
      else
        view.reload
      end
    end

    def go_back
      web_view_in_front&.go_back
    end

    def go_forward
      web_view_in_front&.go_forward
    end

    # Home is the tab's own homepage, not the page's — a web app that has
    # wandered off comes back to the address the tab was added with.
    def go_home
      instance_in_front.then do |view, instance|
        if instance
          view.load_uri(instance.url)
        end
      end
    end

    def instance_in_front
      web_view_in_front.then do |view|
        if view&.instance_id
          [view, instances.get(view.instance_id)]
        else
          [view, nil]
        end
      end
    end

    def toggle_web_inspector
      web_view_in_front&.inspector.then do |inspector|
        if inspector
          toggle_inspector(inspector)
        end
      end
    end

    # A zero attached height means the inspector is not up.
    def toggle_inspector(inspector)
      if inspector.attached_height.zero?
        inspector.show
      else
        inspector.close
      end
    end

    # The tab the new-tab view has been building becomes permanent: the page
    # is asked what web app it is, the answer fills in whatever the user did
    # not type, and the id goes into the settings list.
    def add_tab
      view_new.web_view.then do |view|
        if view
          WebAppInfo.fetch(view) { |info| keep_tab(view, info) }
        end
      end
    end

    def keep_tab(view, info)
      instances.get(view.instance_id).then do |instance|
        if instance
          keep(instance, view, info)
        end
      end
    end

    def keep(instance, view, info)
      unless info[:url].to_s.empty?
        instance.url = info[:url]
      end

      if instance.name.empty?
        instance.name = info[:title] || view.title.to_s
      end

      instances.attach(instance)
      view_new.detach_web_view

      tabs.add_tab(instance)
      tabs.select_tab(instance)
    end

    # Giving up on a tab being added takes it, and everything its session
    # wrote, back out again.
    def cancel_new_tab
      state.set(view: TABS_VIEW)

      view_new.web_view.then do |view|
        if view
          discard(view)
        end
      end
    end

    def discard(view)
      instances.get(view.instance_id).then do |instance|
        view_new.detach_web_view

        if instance
          instances.destroy(instance)
        end
      end
    end

    # Deleting a tab takes its id out of the settings list, closes its page —
    # which is what takes its stored data with it — and drops the tab.
    def delete_tab(id)
      instances.get(id).then do |instance|
        if instance
          instances.detach(instance)
          tabs.remove_tab(instance)
          instances.destroy(instance)
        end
      end
    end

    # A notification the page raised, sent on as the application's own at the
    # priority the tab was configured with, carrying the action that brings
    # the tab to the front.
    def notify(web_notification, instance_id)
      instances.get(instance_id).then do |instance|
        if instance
          send_notification(instance, web_notification)
        end
      end
    end

    def send_notification(instance, web_notification)
      Gio::Notification.new(web_notification.title.to_s).tap do |notification|
        notification.body = web_notification.body.to_s
        notification.priority = NOTIFICATION_PRIORITIES.fetch(instance.notifications_priority)
        notification.set_default_action("app.#{Actions::SHOW_INSTANCE}('#{instance.id}')")

        application.send_notification(instance.id, notification)
      end
    end
end
