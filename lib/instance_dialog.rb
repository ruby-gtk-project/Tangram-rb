# frozen_string_literal: true

require 'adwaita'

require_relative 'delete_tab_dialog'
require_relative 'settings'

# InstanceDialog edits one tab: its name, its homepage, the priority its
# notifications are sent with, the user agent it presents, and the button that
# deletes it.
#
# Ported from upstream's src/instanceDialog.blp and src/instanceDialog.js.
class InstanceDialog
  CONTENT_WIDTH = 640

  # The strings of the combo row's model, in the order of the schema's
  # notification-priority enum.
  PRIORITIES = %w[Normal Low High Urgent].freeze

  # `on_delete` is the window's tab deletion, which takes a tab id.
  def initialize(instance:, on_delete:)
    @instance = instance
    @on_delete = on_delete
  end

  attr_reader :instance

  def build
    @build ||= dialog.tap do
      toolbar_view.tap do |view|
        view.add_top_bar(header_bar)
        view.content = preferences_page

        header_bar.tap do |bar|
          bar.pack_start(button_cancel)
          bar.pack_end(button_save)

          button_cancel.signal_connect('clicked') { dialog.close }
          button_save.signal_connect('clicked') { save }
        end

        preferences_page.tap do |page|
          page.add(address_group)
          page.add(behaviour_group)
          page.add(delete_group)

          address_group.tap do |group|
            group.add(name_row)
            group.add(url_row)

            url_row.signal_connect('changed') { update_save_sensitivity }
          end

          behaviour_group.tap do |group|
            group.add(priority_row)
            group.add(user_agent_row)
          end

          delete_group.tap do |group|
            group.add(button_delete)

            button_delete.signal_connect('clicked') { delete_tab_dialog.present(dialog) }
          end
        end
      end

      dialog.child = toolbar_view
      update_save_sensitivity
    end
  end

  def present(parent) = build.present(parent)

  def dialog
    @dialog ||= Adwaita::Dialog.new.tap do |sheet|
      sheet.content_width = CONTENT_WIDTH
      sheet.title = instance.name
    end
  end

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new

  def header_bar
    @header_bar ||= Adwaita::HeaderBar.new.tap do |bar|
      bar.show_start_title_buttons = false
      bar.show_end_title_buttons = false
    end
  end

  def button_cancel = @button_cancel ||= Gtk::Button.new(label: 'Cancel')

  def button_save
    @button_save ||= Gtk::Button.new(label: 'Update').tap do |button|
      button.add_css_class('suggested-action')
    end
  end

  def preferences_page
    @preferences_page ||= Adwaita::PreferencesPage.new.tap do |page|
      page.vexpand = true
    end
  end

  def address_group
    @address_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.vexpand = true
    end
  end

  def behaviour_group
    @behaviour_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.vexpand = true
    end
  end

  def delete_group = @delete_group ||= Adwaita::PreferencesGroup.new

  def name_row
    @name_row ||= Adwaita::EntryRow.new.tap do |row|
      row.title = 'Name'
      row.text = instance.name
    end
  end

  def url_row
    @url_row ||= Adwaita::EntryRow.new.tap do |row|
      row.title = 'Homepage'
      row.input_purpose = :url
      row.text = instance.url
    end
  end

  def priority_row
    @priority_row ||= Adwaita::ComboRow.new.tap do |row|
      row.title = 'Notifications priority'
      row.model = Gtk::StringList.new(PRIORITIES)
      row.selected = instance.notifications_priority
    end
  end

  def user_agent_row
    @user_agent_row ||= Adwaita::EntryRow.new.tap do |row|
      row.title = 'User agent'
      row.text = instance.user_agent
    end
  end

  def button_delete
    @button_delete ||= Gtk::Button.new(label: 'Delete Tab').tap do |button|
      button.add_css_class('destructive-action')
      button.add_css_class('pill')
      button.halign = :center
    end
  end

  # The confirmation the delete button opens, kept so a second click reopens
  # the same dialog rather than stacking another one.
  def delete_tab_dialog
    @delete_tab_dialog ||= DeleteTabDialog.new(
      instance:  instance,
      on_delete: @on_delete,
    )
  end

  private

    # A tab with no homepage has nothing to load, so "Update" stays insensitive
    # until one is typed.
    def update_save_sensitivity
      button_save.sensitive = !url_row.text.to_s.empty?
    end

    def save
      instance.name = name_row.text
      instance.url = url_row.text
      instance.user_agent = user_agent_row.text
      instance.notifications_priority = priority_row.selected
      dialog.close
    end
end
