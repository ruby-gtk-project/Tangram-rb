# frozen_string_literal: true

require 'adwaita'

require_relative 'main_menu'
require_relative 'tabs'
require_relative 'translations'

# ViewTabs is the window's main view: the tabs themselves, the overview over
# them, and the two header bars of navigation controls around them — a top one
# on a desktop-sized window and a bottom one once the window is narrow enough
# for the breakpoint to apply.
#
# Ported from upstream's src/ViewTabs.blp and src/ViewTabs.js. The template's
# `menu menu_app` is MainMenu, ported alongside.
#
# Every `bind` in the template is a property binding this port makes by hand.
# The plain ones — a button's visibility following the overview — could be
# `bind_property`; the inverted and the transforming ones could not, because
# `bind_property_full` is not bound in ruby-gnome. Rather than split them
# across two mechanisms, every one of them is applied by `follow_overview`,
# which the overview's `notify::open` drives and which `build` calls once so
# the window opens in a consistent state.
class ViewTabs
  include Translations

  NAVIGATION_SPACING = 6

  # The bottom bar's back and forward buttons are wider than the top bar's, so
  # they stay comfortable targets on a touch screen.
  BOTTOM_BUTTON_WIDTH = 42

  RELOAD_ICON = 'view-refresh-symbolic'
  STOP_ICON = 'process-stop-symbolic'

  def initialize(
    state:,
    settings:,
    instances:,
    window:,
    breakpoint:,
    on_reload:,
    on_stop_loading:,
    on_go_back:,
    on_go_forward:,
    on_go_home:,
    on_new_tab:,
    on_notification:,
    delete_tab:
  )
    @state = state
    @settings = settings
    @instances = instances
    @window = window
    @breakpoint = breakpoint
    @on_reload = on_reload
    @on_stop_loading = on_stop_loading
    @on_go_back = on_go_back
    @on_go_forward = on_go_forward
    @on_go_home = on_go_home
    @on_new_tab = on_new_tab
    @on_notification = on_notification
    @delete_tab = delete_tab
  end

  attr_reader :state, :settings, :instances, :window, :breakpoint

  def build
    @build ||= view_tabs.tap do |view|
      view.add_top_bar(header_bar_top)
      view.add_bottom_bar(header_bar_bottom)
      view.content = tab_overview

      header_bar_top.tap do |bar|
        bar.pack_start(button_add_tab)
        bar.pack_start(navigation_box_top)
        bar.title_widget = toggle_overview_top
        bar.pack_end(menu_button_top)

        button_add_tab.signal_connect('clicked') { @on_new_tab.call }
        toggle_overview_top.signal_connect('toggled') { open_overview(toggle_overview_top) }

        navigation_box_top.tap do |box|
          box.append(button_back_top)
          box.append(button_forward_top)
          box.append(button_reload_top)
          box.append(button_home_top)
          box.append(button_edit_top)

          button_back_top.signal_connect('clicked') { @on_go_back.call }
          button_forward_top.signal_connect('clicked') { @on_go_forward.call }
          button_home_top.signal_connect('clicked') { @on_go_home.call }

          button_reload_top.add_controller(reload_gesture)
          reload_gesture.signal_connect('pressed') { on_reload_pressed }
        end
      end

      header_bar_bottom.tap do |bar|
        bar.pack_start(navigation_box_bottom)
        bar.title_widget = toggle_overview_bottom
        bar.pack_end(menu_button_bottom)
        bar.pack_end(button_edit_bottom)
        bar.pack_end(button_home_bottom)

        toggle_overview_bottom.signal_connect('toggled') { open_overview(toggle_overview_bottom) }

        navigation_box_bottom.tap do |box|
          box.append(button_back_bottom)
          box.append(button_forward_bottom)

          button_back_bottom.signal_connect('clicked') { @on_go_back.call }
          button_forward_bottom.signal_connect('clicked') { @on_go_forward.call }
        end

        button_home_bottom.signal_connect('clicked') { @on_go_home.call }
      end

      tab_overview.tap do |overview|
        overview.child = tab_box
        overview.signal_connect('notify::open') { follow_overview }

        tab_box.tap do |box|
          box.append(tabs_bar)
          box.append(tab_view)
        end
      end

      tabs.build
      settings.bind('tabs-bar', tabs_bar, 'visible')

      breakpoint.tap do |point|
        point.signal_connect('apply') { reveal_bars(handheld: true) }
        point.signal_connect('unapply') { reveal_bars(handheld: false) }
      end

      state.notify('webview') { |web_view, previous| follow_web_view(web_view, previous) }

      follow_overview
    end
  end

  def tabs
    @tabs ||= Tabs.new(
      tab_view:        tab_view,
      tab_overview:    tab_overview,
      state:           state,
      instances:       instances,
      window:          window,
      on_notification: @on_notification,
      delete_tab:      @delete_tab,
    )
  end

  def view_tabs
    @view_tabs ||= Adwaita::ToolbarView.new.tap do |view|
      view.top_bar_style = Adwaita::ToolbarStyle::FLAT
      view.bottom_bar_style = Adwaita::ToolbarStyle::RAISED_BORDER
      view.reveal_top_bars = true
      view.reveal_bottom_bars = false
    end
  end

  def header_bar_top = @header_bar_top ||= Adwaita::HeaderBar.new
  def header_bar_bottom = @header_bar_bottom ||= Adwaita::HeaderBar.new

  def button_add_tab
    @button_add_tab ||= Gtk::Button.new.tap do |button|
      button.add_css_class('suggested-action')
      button.child = add_tab_content
    end
  end

  def add_tab_content
    @add_tab_content ||= Adwaita::ButtonContent.new.tap do |content|
      content.label = _('Add Tab')
      content.icon_name = 'tab-new-symbolic'
    end
  end

  def navigation_box_top
    @navigation_box_top ||= Gtk::Box.new(:horizontal, NAVIGATION_SPACING)
  end

  def navigation_box_bottom
    @navigation_box_bottom ||= Gtk::Box.new(:horizontal, NAVIGATION_SPACING)
  end

  def button_back_top = @button_back_top ||= navigation_button('go-previous-symbolic', _('Back'))
  def button_forward_top = @button_forward_top ||= navigation_button('go-next-symbolic', _('Forward'))
  def button_reload_top = @button_reload_top ||= navigation_button(RELOAD_ICON, _('Reload'))
  def button_home_top = @button_home_top ||= navigation_button('go-home-symbolic', _('Homepage'))

  def button_edit_top
    @button_edit_top ||= navigation_button('view-more-symbolic', _('Edit Tab')).tap do |button|
      button.action_name = 'win.editTab'
    end
  end

  def button_back_bottom
    @button_back_bottom ||= navigation_button('go-previous-symbolic', _('Back')).tap do |button|
      button.width_request = BOTTOM_BUTTON_WIDTH
    end
  end

  def button_forward_bottom
    @button_forward_bottom ||= navigation_button('go-next-symbolic', _('Forward')).tap do |button|
      button.width_request = BOTTOM_BUTTON_WIDTH
    end
  end

  def button_home_bottom = @button_home_bottom ||= navigation_button('go-home-symbolic', _('Homepage'))

  def button_edit_bottom
    @button_edit_bottom ||= navigation_button('view-more-symbolic', _('Edit Tab')).tap do |button|
      button.action_name = 'win.editTab'
    end
  end

  # The top bar's overview toggle carries the application's name, so a
  # desktop-sized window has it in the title position.
  def toggle_overview_top
    @toggle_overview_top ||= Gtk::ToggleButton.new.tap do |button|
      button.tooltip_text = _('Tabs Overview')
      button.child = overview_toggle_content
    end
  end

  def overview_toggle_content
    @overview_toggle_content ||= Adwaita::ButtonContent.new.tap do |content|
      content.icon_name = 'tabs-stack-symbolic'
      content.label = '_Tangram'
      content.use_underline = true
    end
  end

  def toggle_overview_bottom
    @toggle_overview_bottom ||= Gtk::ToggleButton.new.tap do |button|
      button.icon_name = 'tabs-stack-symbolic'
      button.tooltip_text = _('Tabs Overview')
    end
  end

  def menu_button_top = @menu_button_top ||= menu_button
  def menu_button_bottom = @menu_button_bottom ||= menu_button

  # The overview's own header bar is turned off, title buttons and search
  # alike: the window's header bars stay in place over it.
  def tab_overview
    @tab_overview ||= Adwaita::TabOverview.new.tap do |overview|
      overview.view = tab_view
      overview.hexpand = true
      overview.vexpand = true
      overview.enable_search = false
      overview.show_start_title_buttons = false
      overview.show_end_title_buttons = false
    end
  end

  def tab_box = @tab_box ||= Gtk::Box.new(:vertical, 0)

  # Hidden unless the "Show Tabs Bar" menu item says otherwise, which is the
  # `tabs-bar` setting the window's action toggles.
  def tabs_bar
    @tabs_bar ||= Adwaita::TabBar.new.tap do |bar|
      bar.view = tab_view
      bar.visible = false
    end
  end

  def tab_view
    @tab_view ||= Adwaita::TabView.new.tap do |view|
      view.hexpand = true
      view.vexpand = true
      view.shortcuts = Adwaita::TabViewShortcuts::ALL_SHORTCUTS
    end
  end

  # Button 0 listens for every button, so a middle or right click on reload
  # can be let through to the widget below rather than reloading the page.
  def reload_gesture = @reload_gesture ||= Gtk::GestureClick.new.tap { |gesture| gesture.button = 0 }

  def main_menu = @main_menu ||= MainMenu.new

  private

    def navigation_button(icon_name, tooltip)
      Gtk::Button.new.tap do |button|
        button.icon_name = icon_name
        button.tooltip_text = tooltip
      end
    end

    def menu_button
      Gtk::MenuButton.new.tap do |button|
        button.icon_name = 'open-menu-symbolic'
        button.tooltip_text = _('Main Menu')
        button.primary = true
        button.menu_model = main_menu.build
      end
    end

    def open_overview(toggle)
      tab_overview.open = toggle.active?
    end

    # Everything the template binds to the overview's `open`. The navigation
    # controls belong to a page, so they go while the overview is up; the
    # add-tab button and the bottom bar's menu only make sense there, so they
    # arrive with it.
    def follow_overview
      tab_overview.open?.then do |open|
        button_add_tab.visible = open
        navigation_box_top.visible = !open
        navigation_box_bottom.visible = !open
        menu_button_bottom.visible = open
        button_edit_bottom.visible = !open
        button_home_bottom.visible = !open
        toggle_overview_top.active = open
        toggle_overview_bottom.active = open
        view_tabs.top_bar_style = overview_bar_style(open)
      end
    end

    def overview_bar_style(open)
      if open
        Adwaita::ToolbarStyle::FLAT
      else
        Adwaita::ToolbarStyle::RAISED
      end
    end

    # Narrow enough for the breakpoint and the controls move to the bottom,
    # where a thumb can reach them.
    def reveal_bars(handheld:)
      view_tabs.reveal_bottom_bars = handheld
      view_tabs.reveal_top_bars = !handheld
    end

    # A primary press reloads, or stops a page still loading; Control held
    # reloads past the cache. Any other button is handed back to the widget.
    def on_reload_pressed
      reload_gesture.current_event.then do |event|
        if event.button == Gdk::BUTTON_PRIMARY
          reload_or_stop(event)
        else
          reload_gesture.set_state(Gtk::EventSequenceState::DENIED)
        end
      end
    end

    def reload_or_stop(event)
      state.get('webview').then do |web_view|
        if web_view&.loading?
          @on_stop_loading.call
        else
          @on_reload.call(bypass_cache?(event))
        end
      end
    end

    def bypass_cache?(event)
      control = Gdk::ModifierType::CONTROL_MASK.to_i

      (event.modifier_state.to_i & control) == control
    end

    # The navigation buttons read their state off whichever web view is in
    # front, so they follow both the selected tab and that page's own loading
    # and history.
    def follow_web_view(web_view, previous)
      disconnect_web_view(previous)
      update_buttons(web_view)

      if web_view
        connect_web_view(web_view)
      end
    end

    def connect_web_view(web_view)
      @load_changed_handler = web_view.signal_connect('load-changed') { update_buttons(web_view) }
      @history_handler = web_view.back_forward_list.signal_connect('changed') { update_buttons(web_view) }
    end

    def disconnect_web_view(previous)
      if previous
        if @load_changed_handler
          previous.signal_handler_disconnect(@load_changed_handler)
          @load_changed_handler = nil
        end

        if @history_handler
          previous.back_forward_list.signal_handler_disconnect(@history_handler)
          @history_handler = nil
        end
      end
    end

    def update_buttons(web_view)
      [button_back_top, button_back_bottom].each do |button|
        button.sensitive = web_view&.can_go_back? == true
      end

      [button_forward_top, button_forward_bottom].each do |button|
        button.sensitive = web_view&.can_go_forward? == true
      end

      button_reload_top.icon_name = reload_icon(web_view)
    end

    def reload_icon(web_view)
      if web_view&.loading?
        STOP_ICON
      else
        RELOAD_ICON
      end
    end
end
