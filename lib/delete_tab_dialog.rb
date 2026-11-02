# frozen_string_literal: true

require 'adwaita'

# DeleteTabDialog asks whether the tab, and everything stored for it, should
# go.
#
# Ported from the `onDelete` function at the bottom of upstream's
# src/instanceDialog.js. Upstream awaits `choose`; the Ruby binding has the
# `response` signal that promise wraps, which carries the same answers.
class DeleteTabDialog
  HEADING = 'Delete Tab?'
  BODY = 'The Tab and locally saved data will be gone.'

  CANCEL = 'cancel'
  DELETE = 'delete'

  # `on_delete` is the window's tab deletion, which takes a tab id.
  def initialize(instance:, on_delete:)
    @instance = instance
    @on_delete = on_delete
  end

  attr_reader :instance

  def build
    @build ||= dialog.tap do |alert|
      alert.add_response(CANCEL, 'Cancel')
      alert.add_response(DELETE, 'Delete')
      alert.set_response_appearance(DELETE, Adwaita::ResponseAppearance::DESTRUCTIVE)

      alert.signal_connect('response') do |_alert, response|
        if response == DELETE
          @on_delete.call(instance.id)
          @parent&.force_close
        end
      end
    end
  end

  # `parent` is the tab's own dialog: the alert is presented on top of it, and
  # on a delete it takes that dialog down with it.
  def present(parent)
    @parent = parent
    build.present(parent)
  end

  def dialog
    @dialog ||= Adwaita::AlertDialog.new(HEADING, BODY).tap do |alert|
      alert.close_response = CANCEL
    end
  end
end
