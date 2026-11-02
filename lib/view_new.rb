# frozen_string_literal: true

require 'adwaita'

require_relative 'instances'
require_relative 'url'
require_relative 'web_view'

# ViewNew is the view a tab is added from: an address bar, a "Go" button, and
# once an address has been loaded, a live web view of the page with "Add" over
# it. Nothing is written down until "Add" is clicked; the tab the view is
# building exists, with its own session, but is not in the window's list.
#
# Ported from upstream's src/ViewNew.blp and src/ViewNew.js.
class ViewNew
  CLAMP_MAXIMUM = 860
  CLAMP_TIGHTENING = 560
  ADDRESS_WIDTH_CHARS = 30
  GO_MARGIN = 20

  WELCOME_TITLE = 'Welcome to Tangram'
  WELCOME_DESCRIPTION = "Let's add your first web application."

  STATUS_PAGE = 'statuspage'
  NEW_TAB = 'new-tab'

  SECURE_ICON = 'channel-secure-symbolic'
  INSECURE_ICON = 'channel-insecure-symbolic'

  def initialize(
    state:,
    instances:,
    window:,
    on_add_tab:,
    on_cancel_new_tab:,
    on_notification:
  )
    @state = state
    @instances = instances
    @window = window
    @on_add_tab = on_add_tab
    @on_cancel_new_tab = on_cancel_new_tab
    @on_notification = on_notification
  end

  attr_reader :state, :instances, :window

  # The web view of the page being inspected, once an address has been
  # loaded. The window reads it when "Add" or "Cancel" is clicked.
  attr_reader :web_view

  def build
    @build ||= view_new.tap do |view|
      view.append(header_bar)
      view.append(stack_new)

      header_bar.tap do |bar|
        bar.pack_start(cancel_box)
        bar.title_widget = address_clamp
        bar.pack_end(button_done)

        cancel_box.tap do |box|
          box.append(button_cancel)

          button_cancel.signal_connect('clicked') { @on_cancel_new_tab.call }
        end

        address_clamp.child = entry_url

        entry_url.signal_connect('activate') { load_address(entry_url.text) }
        button_done.signal_connect('clicked') { done }
      end

      stack_new.tap do |stack|
        stack.add_named(status_page, STATUS_PAGE)

        status_page.child = go_box

        go_box.tap do |box|
          box.append(entry_go)
          box.append(button_go)

          button_go.signal_connect('clicked') { entry_go.signal_emit('activate') }
          entry_go.signal_connect('activate') { start(entry_go.text) }
          entry_go.signal_connect('notify::text') { follow_address_entry }
        end
      end

      state.notify('view') { reset }

      follow_address_entry
    end
  end

  def focus_address_bar = entry_url.grab_focus

  # Starts a tab from scratch: the address bar is cleared and the welcome page
  # goes up, worded for a first run when there is nothing else in the window.
  def on_new_tab
    state.set(view: 'new')

    stack_new.visible_child_name = STATUS_PAGE
    entry_go.text = ''
    entry_go.grab_focus

    describe_status_page(first_tab?)
  end

  # Takes the web view out of the stack and stops following it. The window
  # calls this once the tab has been added, or once it has been given up on.
  def detach_web_view
    web_view.then do |view|
      if view
        stop_following(view)
        stack_new.remove(view)
        @web_view = nil
      end
    end
  end

  def view_new = @view_new ||= Gtk::Box.new(:vertical, 0)

  # A strict centering policy keeps the address bar in the middle of the
  # header bar whatever sits beside it.
  def header_bar
    @header_bar ||= Adwaita::HeaderBar.new.tap do |bar|
      bar.centering_policy = :strict
    end
  end

  def cancel_box = @cancel_box ||= Gtk::Box.new(:horizontal, 0)
  def button_cancel = @button_cancel ||= Gtk::Button.new(label: 'Cancel')

  def address_clamp
    @address_clamp ||= Adwaita::Clamp.new.tap do |clamp|
      clamp.maximum_size = CLAMP_MAXIMUM
      clamp.tightening_threshold = CLAMP_TIGHTENING
    end
  end

  def entry_url
    @entry_url ||= Gtk::Entry.new.tap do |entry|
      entry.hexpand = true
      entry.placeholder_text = 'Enter address'
      entry.input_purpose = :url
      entry.activates_default = true
    end
  end

  def button_done
    @button_done ||= Gtk::Button.new(label: 'Add').tap do |button|
      button.sensitive = false
      button.add_css_class('suggested-action')
    end
  end

  def stack_new = @stack_new ||= Gtk::Stack.new

  def status_page
    @status_page ||= Adwaita::StatusPage.new.tap do |page|
      page.vexpand = true
    end
  end

  def go_box
    @go_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.hexpand = true
      box.halign = :center
    end
  end

  def entry_go
    @entry_go ||= Gtk::Entry.new.tap do |entry|
      entry.input_purpose = :url
      entry.placeholder_text = 'example.org'
      entry.hexpand = true
      entry.max_width_chars = ADDRESS_WIDTH_CHARS
      entry.activates_default = true
    end
  end

  def button_go
    @button_go ||= Gtk::Button.new(label: 'Go').tap do |button|
      button.margin_top = GO_MARGIN
      button.sensitive = false
      button.halign = :center
      button.add_css_class('suggested-action')
      button.add_css_class('pill')
    end
  end

  private

    # The address the user typed on the welcome page: a tab of its own is
    # created for it, with its own session, and the page is loaded into the
    # stack so it can be looked at before being kept.
    def start(address)
      Url.normalize(address).then do |url|
        if url
          replace_previous

          entry_url.visible = true
          button_done.visible = true

          present(temporary_web_view, url)
        end
      end
    end

    # Upstream's commented-out `const previous = stack_tabs.get_child_by_name`
    # block. The welcome page can come back with a web view still in the stack
    # — deleting the last tab puts it there — and a second address typed into
    # it would add a second child under the same name, which GTK refuses. The
    # tab the previous view was building was never attached, so it goes too.
    def replace_previous
      web_view.then do |view|
        if view
          discard_previous(view)
        end
      end
    end

    def discard_previous(view)
      instances.get(view.instance_id).then do |instance|
        detach_web_view

        if instance
          instances.destroy(instance)
        end
      end
    end

    def temporary_web_view
      instances.create.then do |instance|
        WebView.new(
          instance:        instance,
          window:          window,
          on_notification: @on_notification,
          mode:            TabWebView::TEMPORARY,
        ).build
      end
    end

    def present(view, url)
      @web_view = view

      follow(view)

      stack_new.add_named(view, NEW_TAB)
      stack_new.visible_child = view

      view.load_uri(url)
      view.grab_focus
    end

    # A new address typed into the header bar's entry once a page is up: the
    # same web view follows it, so the tab being built keeps its session.
    def load_address(address)
      Url.normalize(address).then do |url|
        if url && web_view
          web_view.load_uri(url)
          web_view.grab_focus
        end
      end
    end

    # Upstream's `offWebview`: "Add" stops the view's address and security
    # following, because what the window does next is read the page and hand
    # the view over to a tab of its own. Taking it out of the stack is the
    # window's to do, once it has what it needs from it.
    def done
      web_view.then do |view|
        if view
          stop_following(view)
        end
      end

      @on_add_tab.call
    end

    def follow(view)
      update_buttons(view)
      set_address(view)

      unless view.loading?
        set_security(view)
      end

      @loading_handler = view.signal_connect('notify::is-loading') { update_buttons(view) }

      @load_changed_handler = view.signal_connect('load-changed') do |_view, load_event|
        if load_event == WebKit::LoadEvent::COMMITTED
          set_security(view)
        end
      end

      @uri_handler = view.signal_connect('notify::uri') { set_address(view) }
    end

    def stop_following(view)
      [@loading_handler, @load_changed_handler, @uri_handler].compact.each do |handler|
        view.signal_handler_disconnect(handler)
      end

      @loading_handler = nil
      @load_changed_handler = nil
      @uri_handler = nil
    end

    # "Add" waits for the page to finish: the title and the manifest it is
    # read from are not there until it has.
    def update_buttons(view)
      button_done.sensitive = !view.loading?
    end

    def set_address(view)
      entry_url.text = displayed_uri(view.uri)
    end

    # WebKit's `uri_for_display` is what turns a punycoded host back into the
    # name the user would recognise.
    def displayed_uri(uri)
      if uri.to_s.empty?
        ''
      else
        WebKit.uri_for_display(uri).to_s
      end
    end

    def set_security(view)
      if entry_url.text.empty?
        entry_url.primary_icon_name = nil
      else
        entry_url.primary_icon_name = security_icon(view)
      end
    end

    def security_icon(view)
      view.tls_info.then do |ok, _certificate, errors|
        if ok && errors.to_i.zero?
          SECURE_ICON
        else
          INSECURE_ICON
        end
      end
    end

    def follow_address_entry
      button_go.sensitive = !entry_go.text.empty?
    end

    # Coming back to this view puts it back to its starting state. On a first
    # run there is nothing to cancel back to, so the header bar loses its
    # border and the cancel button goes.
    def reset
      button_done.sensitive = false
      entry_url.visible = false
      button_done.visible = false

      first_tab?.then do |first|
        button_cancel.visible = !first

        if first
          header_bar.add_css_class('flat')
        else
          header_bar.remove_css_class('flat')
        end
      end
    end

    def first_tab? = Array(state.get('instances')).empty?

    def describe_status_page(first)
      if first
        status_page.icon_name = 're.sonny.Tangram'
        status_page.title = WELCOME_TITLE
        status_page.description = WELCOME_DESCRIPTION
      else
        status_page.icon_name = ''
        status_page.title = ''
        status_page.description = ''
      end
    end
end
