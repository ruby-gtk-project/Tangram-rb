# frozen_string_literal: true

require 'adwaita'

require_relative 'instance_dialog'
require_relative 'translations'
require_relative 'web_view'

# Tabs is the repeater over the tab view's pages: one page per tab, each
# carrying that tab's web view, with the page's title, icon, loading spinner
# and audio indicator kept in step with the tab and the view behind it.
#
# Ported from upstream's src/tabs.js. Upstream's closure returns a bag of four
# functions; here they are the four public methods, over the same tab view.
class Tabs
  include Translations

  AUDIO_ICON = 'audio-volume-high-symbolic'
  AUDIO_TOOLTIP = 'Playing Audio'

  # `on_notification` takes a WebKit notification and a tab id; `delete_tab`
  # takes a tab id and is the window's tab deletion, which the tab editor's
  # delete button calls.
  def initialize(
    tab_view:,
    tab_overview:,
    state:,
    instances:,
    window:,
    on_notification:,
    delete_tab:
  )
    @tab_view = tab_view
    @tab_overview = tab_overview
    @state = state
    @instances = instances
    @window = window
    @on_notification = on_notification
    @delete_tab = delete_tab
  end

  attr_reader :tab_view, :tab_overview, :state, :instances, :window

  def build
    @build ||= tab_view.tap do |view|
      view.signal_connect('notify::selected-page') { publish_selected_web_view }
      view.signal_connect('close-page') { |_view, page| close_page(page) }
    end
  end

  # Builds the tab's web view, appends a page for it, and ties the page's
  # title, icon and spinner to the tab and the view.
  def add_tab(instance)
    build_web_view(instance).then do |view|
      instance.web_view = view

      tab_view.append(view).tap do |page|
        page.live_thumbnail = true

        view.bind_property(
          'favicon',
          page,
          'icon',
          :sync_create,
        )
        view.bind_property(
          'is-loading',
          page,
          'loading',
          :sync_create,
        )
        instance.bind('name', page, 'title')

        view.signal_connect('notify::is-playing-audio') { update_indicator(view, page) }
      end
    end
  end

  def remove_tab(instance)
    tab_view.close_page(tab_view.get_page(instance.web_view))
  end

  def select_tab(instance)
    tab_view.selected_page = tab_view.get_page(instance.web_view)
  end

  # Brings the tab to the front and opens its editor on top of the window.
  def edit_tab(instance)
    select_tab(instance)
    editor(instance).present(window)
  end

  # One editor per tab, memoized like every other widget: reopening a tab's
  # editor brings back the same dialog rather than stacking another one on it.
  def editor(instance)
    editors[instance.id] ||= InstanceDialog.new(
      instance:  instance,
      on_delete: @delete_tab,
    )
  end

  def editors = @editors ||= {}

  private

    def build_web_view(instance)
      WebView.new(
        instance:        instance,
        window:          window,
        on_notification: @on_notification,
      ).build
    end

    # Which web view is in front is the one piece of state the whole window
    # navigates by: the header bars' buttons, the shortcuts and the tab editor
    # all read it.
    def publish_selected_web_view
      instance_of(tab_view.selected_page).then do |instance|
        state.set(webview: instance&.web_view)
      end
    end

    # Closing a page takes the tab's stored data with it and drops the user
    # back in the overview, where another tab can be picked.
    def close_page(page)
      tab_view.close_page_finish(page, true)
      tab_overview.open = true

      instance_of(page).then do |instance|
        if instance
          instances.destroy(instance)
        end
      end

      # Upstream's `Gdk.EVENT_STOP`, which the Ruby bindings do not define:
      # the close has been handled here and no other handler should see it.
      true
    end

    def instance_of(page)
      if page
        instances.get(page.child.instance_id)
      end
    end

    def update_indicator(view, page)
      if view.playing_audio?
        page.indicator_icon = Gio::ThemedIcon.new(AUDIO_ICON)
        page.indicator_tooltip = _(AUDIO_TOOLTIP)
      else
        page.indicator_icon = nil
        page.indicator_tooltip = ''
      end
    end
end
